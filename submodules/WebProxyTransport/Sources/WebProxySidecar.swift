import Foundation
import Network

private final class WebProxyStream {
    let id: UInt32
    let connection: NWConnection
    var pendingWrite = Data()
    var isWriting = false
    var isClosed = false
    /// Uplink credit granted by the relay, in bytes. Both directions open with an implicit 4 MiB
    /// window; `DATA` spends it and `WINDOW` grants it back.
    var sendCredit: Int = WebProxySidecar.initialStreamWindow
    /// Bytes read off the local socket that have no credit to travel on yet.
    var pendingUplink = Data()
    /// Read cursor into `pendingUplink`. Chunking used to re-base the buffer with `dropFirst`,
    /// copying the whole remainder for every 64 KiB chunk - draining the 8 MiB ceiling that way
    /// moves about half a gigabyte through memcpy, and the buffer is fullest exactly when the relay
    /// has stopped granting credit.
    var pendingUplinkOffset = 0
    /// Downlink bytes already written to the local socket whose credit has not been returned to the
    /// relay yet. Announcing every write was a `WINDOW` frame - and so its own HTTPS POST - for
    /// each socket send, which kept the radio busy for the whole of a download.
    var pendingWindowCredit = 0
    /// Most already-sent bytes this stream may keep in front of the read cursor before compacting.
    static let maximumRetainedUplinkPrefix = 1024 * 1024
    
    var pendingUplinkCount: Int {
        return self.pendingUplink.count - self.pendingUplinkOffset
    }
    
    /// Drops the consumed prefix once it is at least half the buffer: amortised linear in the bytes
    /// sent rather than quadratic in the buffer size.
    func compactPendingUplink() {
        if self.pendingUplinkOffset == 0 {
            return
        }
        if self.pendingUplinkOffset >= self.pendingUplink.count {
            self.pendingUplink = Data()
            self.pendingUplinkOffset = 0
            return
        }
        // Half-consumed keeps the amortised copy cost linear; the absolute ceiling bounds how much
        // already-sent data a single stream can keep alive in front of the cursor.
        if self.pendingUplinkOffset * 2 >= self.pendingUplink.count || self.pendingUplinkOffset >= WebProxyStream.maximumRetainedUplinkPrefix {
            self.pendingUplink = Data(self.pendingUplink[(self.pendingUplink.startIndex + self.pendingUplinkOffset)...])
            self.pendingUplinkOffset = 0
        }
    }
    
    init(id: UInt32, connection: NWConnection) {
        self.id = id
        self.connection = connection
    }
}

public final class WebProxySidecar {
    public struct Endpoint: Equatable {
        public let host: String
        public let port: UInt16
        
        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }
    
    private let queue = DispatchQueue(label: "WebProxySidecar", qos: .userInitiated)
    private var listener: NWListener?
    private var carrier: WebProxyHttpCarrier?
    private var urlSession: URLSession?
    private var streams: [UInt32: WebProxyStream] = [:]
    private var nextStreamId: UInt32 = 1
    /// Wire stream ids are 3 bytes; encoding past 0xffffff used to hit a precondition trap.
    private static let maxStreamId: UInt32 = 0xffffff
    private var endpoint: Endpoint?
    private var onFailure: (() -> Void)?
    private var hostname: String?
    private var secret: Data?
    private var bridgeCapability: String?
    /// Serializes transport rebuilds so background cancel + foreground reconnect cannot stack.
    private var transportReconnectInFlight = false
    private var transportReconnectGeneration: UInt64 = 0
    /// There is deliberately no local retry budget here. A reconnect that fails takes the whole
    /// sidecar down with it, so escalation is the manager's: it rebuilds listener and session
    /// together and applies its own backoff. A counter kept here could only ever read zero.
    ///
    /// A reconnect must not hang "Connecting" forever if the relay accepts the TLS handshake and
    /// then says nothing.
    private static let transportReconnectTimeout: Double = 45.0
    /// Callers that arrived while a reconnect was already running. They are answered with that
    /// reconnect's real outcome — see `reconnectTransportLocked`.
    private var pendingReconnectCompletions: [(Result<Void, Error>) -> Void] = []
    private var startInFlight = false
    private var startBootstrapGeneration: UInt64 = 0
    /// Generous enough for radio reassociate after unlock; 30s caused false failures and slow
    /// multi-retry first connects on wake.
    private static let coldStartTimeout: Double = 90.0
    
    /// Implicit per-stream window both directions start with, per the shared relay contract.
    static let initialStreamWindow = 4 * 1024 * 1024
    /// A stream whose uplink backs up past this is failed rather than buffered without bound.
    private static let maximumPendingUplink = 8 * 1024 * 1024
    /// Credit is returned in one frame per this much downlink instead of one per socket write. Half
    /// the window leaves the relay a full half to keep sending into while the grant is in flight.
    private static let windowCreditFlushThreshold = WebProxySidecar.initialStreamWindow / 2
    
    public init() {
    }
    
    public func start(hostname: String, secret: Data, bridgeCapability: String, completion: @escaping (Result<Endpoint, Error>) -> Void) {
        self.queue.async {
            self.stopLocked()
            self.startInFlight = true
            self.startBootstrapGeneration &+= 1
            let generation = self.startBootstrapGeneration
            var didComplete = false
            let completeOnce: (Result<Endpoint, Error>) -> Void = { result in
                guard !didComplete else {
                    return
                }
                didComplete = true
                completion(result)
            }
            do {
                let config = URLSessionConfiguration.ephemeral
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                config.urlCache = nil
                config.httpCookieAcceptPolicy = .never
                config.httpShouldSetCookies = false
                config.timeoutIntervalForRequest = 90.0
                config.timeoutIntervalForResource = 300.0
                // false: waitsForConnectivity can leave bootstrap hanging past our watchdog
                // when radio is flapping; we prefer fail + manager retry.
                config.waitsForConnectivity = false
                let urlSession = URLSession(configuration: config)
                let carrier = try WebProxyHttpCarrier(hostname: hostname, session: urlSession, queue: self.queue)
                carrier.onDownlinkBatch = { [weak self] batch in
                    self?.handleDownlinkBatch(batch)
                }
                carrier.onFailure = { [weak self, weak carrier] _ in
                    self?.queue.async {
                        // Only the carrier that is still ours may end the sidecar. Detaching a
                        // superseded carrier is not enough on its own: if it failed just before a
                        // reconnect began, its notification is already sitting on this queue and
                        // will run after the detach.
                        guard let self, let carrier, self.carrier === carrier else {
                            return
                        }
                        self.handleCarrierFailure()
                    }
                }
                
                guard let ephemeralPort = NWEndpoint.Port(rawValue: 0) else {
                    self.startInFlight = false
                    completeOnce(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                    return
                }
                let listener = try NWListener(using: .tcp, on: ephemeralPort)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection: connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else {
                        return
                    }
                    switch state {
                    case .failed:
                        self.queue.async {
                            guard self.listener != nil else {
                                return
                            }
                            self.onFailure?()
                            self.stopLocked()
                        }
                    default:
                        break
                    }
                }
                
                self.urlSession = urlSession
                self.carrier = carrier
                self.listener = listener
                self.hostname = hostname
                self.secret = secret
                self.bridgeCapability = bridgeCapability
                
                listener.start(queue: self.queue)
                
                carrier.start(secret: secret, bridgeCapability: bridgeCapability) { [weak self] result in
                    guard let self else {
                        return
                    }
                    self.queue.async {
                        guard generation == self.startBootstrapGeneration, self.startInFlight else {
                            if case .success = result {
                                self.stopLocked()
                            }
                            return
                        }
                        self.startInFlight = false
                        switch result {
                        case .success:
                            guard let port = listener.port?.rawValue else {
                                completeOnce(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                                self.stopLocked()
                                return
                            }
                            let endpoint = Endpoint(host: "127.0.0.1", port: port)
                            self.endpoint = endpoint
                            completeOnce(.success(endpoint))
                        case let .failure(error):
                            self.stopLocked()
                            completeOnce(.failure(error))
                        }
                    }
                }
                
                self.queue.asyncAfter(deadline: .now() + WebProxySidecar.coldStartTimeout) { [weak self] in
                    guard let self else {
                        return
                    }
                    guard generation == self.startBootstrapGeneration, self.startInFlight else {
                        return
                    }
                    self.startInFlight = false
                    self.stopLocked()
                    completeOnce(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                }
            } catch {
                self.startInFlight = false
                completeOnce(.failure(error))
            }
        }
    }
    
    public func stop() {
        self.queue.async {
            self.stopLocked()
        }
    }
    
    public func setFailureHandler(_ handler: @escaping () -> Void) {
        self.queue.async {
            self.onFailure = handler
        }
    }
    
    private func stopLocked() {
        self.transportReconnectGeneration &+= 1
        self.transportReconnectInFlight = false
        // A reconnect abandoned by a stop still owes its callers an answer; without it a resume
        // that raced a teardown would wait on a completion that never arrives.
        let abandonedReconnects = self.pendingReconnectCompletions
        self.pendingReconnectCompletions.removeAll()
        for abandoned in abandonedReconnects {
            abandoned(.failure(WebProxyHttpCarrierError.carrierClosed))
        }
        self.startBootstrapGeneration &+= 1
        self.startInFlight = false
        // Drop the handler first so listener/carrier cancels cannot re-enter onFailure → stop.
        self.onFailure = nil
        self.carrier?.stop()
        self.carrier = nil
        self.listener?.cancel()
        self.listener = nil
        self.urlSession?.invalidateAndCancel()
        self.urlSession = nil
        for stream in self.streams.values {
            stream.connection.cancel()
        }
        self.streams.removeAll()
        self.nextStreamId = 1
        self.endpoint = nil
        self.hostname = nil
        self.secret = nil
        self.bridgeCapability = nil
    }
    
    /// Rebuild only the HTTPS/WebSocket carrier. The loopback listener port stays the same so
    /// MtProto does not get rebound to 127.0.0.1:1 mid-resume. Existing local streams are
    /// cancelled — Telegram opens fresh TCP connections against the same proxy port.
    public func reconnectTransport(completion: ((Result<Void, Error>) -> Void)? = nil) {
        self.queue.async {
            self.reconnectTransportLocked(reason: "resume", completion: completion)
        }
    }
    
    private func handleCarrierFailure() {
        // A carrier that dies on its own is not the same case as a resume. Here nobody is waiting
        // on a result, so an in-place replacement would run unobserved behind a listener that is
        // still published — and if it failed, MtProto would sit on a loopback port with nothing
        // behind it. Report failure and let the manager rebuild listener and session together,
        // under its own backoff. `reconnectTransport` is for the caller that does wait, and that
        // falls back to exactly this when the attempt does not come up.
        self.onFailure?()
        self.stopLocked()
    }
    
    private func reconnectTransportLocked(reason: String, completion: ((Result<Void, Error>) -> Void)?) {
        guard let hostname = self.hostname,
              let secret = self.secret,
              let bridgeCapability = self.bridgeCapability,
              self.listener != nil else {
            completion?(.failure(WebProxyHttpCarrierError.carrierClosed))
            self.onFailure?()
            self.stopLocked()
            return
        }
        // A carrier failure frequently arrives just before `didBecomeActive`. The old code
        // cancelled the bootstrap already in flight in that case and immediately started a
        // second one. Its stale callbacks could then tear down the listener while the manager
        // still published its loopback endpoint, leaving every MTProto connection on permanent
        // `Connection refused` / Connecting. One reconnect owns the listener at a time; its
        // timeout and failure path already provide recovery if it is genuinely hung.
        //
        // Joining it is not the same as reporting success, though. The caller uses this result
        // to decide whether it still has to rebuild the whole sidecar, so an early `.success`
        // sent it away while the transport was in fact still down.
        if self.transportReconnectInFlight {
            if let completion = completion {
                self.pendingReconnectCompletions.append(completion)
            }
            return
        }
        self.transportReconnectInFlight = true
        self.transportReconnectGeneration &+= 1
        let generation = self.transportReconnectGeneration
        WebProxyLog.log("sidecar transport reconnect (\(reason)), keeping the loopback port")

        // The bootstrap callback and the watchdog race, and callers that joined an in-flight
        // attempt have to hear the same answer exactly once.
        var didFinish = false
        let finish: (Result<Void, Error>) -> Void = { [weak self] result in
            guard !didFinish else {
                return
            }
            didFinish = true
            // Every terminal path releases the transport being replaced, not just the successful
            // one. The timeout and the build failure used to leave it running: `stopLocked` closes
            // `self.carrier` and `self.urlSession`, which by then are the *new* ones, so the old
            // session stayed alive with its long polls in flight and nothing left to invalidate
            // it — a leaked session per attempt, on exactly the bad network that makes attempts
            // time out in the first place.
            previousCarrier?.stop()
            previousSession?.invalidateAndCancel()
            var joined: [(Result<Void, Error>) -> Void] = []
            if let self = self {
                self.transportReconnectInFlight = false
                joined = self.pendingReconnectCompletions
                self.pendingReconnectCompletions.removeAll()
            }
            completion?(result)
            for joinedCompletion in joined {
                joinedCompletion(result)
            }
        }
        
        // Keep existing local streams and the old carrier until the NEW carrier is ready.
        // Dropping streams first made MtProto reconnect into a dead gap → infinite
        // Connecting/Updating, and canceling WebSockets mid-receive correlated with SIGABRT on resume.
        let previousCarrier = self.carrier
        // But detach it. Its long-poll dying is the premise of this reconnect, not news about it:
        // the app was suspended, so that request is already dead and reports so within
        // milliseconds of the resume. Left wired, that arrives as a fresh carrier failure,
        // `handleCarrierFailure` tears the sidecar down mid-reconnect, and the new carrier's
        // bootstrap is aborted as superseded — so the reconnect reports failure and the manager
        // rebuilds the listener on a new port, which is the one thing it was called to avoid. In
        // a tester's log that is what happened on three resumes out of four, 39 to 195 ms after
        // the attempt started. Its downlink is dropped for the same reason: frames from the old
        // relay session carry stream ids the new one knows nothing about.
        previousCarrier?.onFailure = nil
        previousCarrier?.onDownlinkBatch = nil
        self.carrier = nil
        
        // Fresh URLSession; do not cancel individual WS tasks on the old carrier first —
        // invalidate the previous session as a whole after the new one is up.
        let previousSession = self.urlSession
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 90.0
        config.timeoutIntervalForResource = 300.0
        config.waitsForConnectivity = false
        let urlSession = URLSession(configuration: config)
        self.urlSession = urlSession
        
        do {
            let carrier = try WebProxyHttpCarrier(hostname: hostname, session: urlSession, queue: self.queue)
            carrier.onDownlinkBatch = { [weak self] batch in
                self?.handleDownlinkBatch(batch)
            }
            carrier.onFailure = { [weak self, weak carrier] _ in
                self?.queue.async {
                    guard let self, let carrier, self.carrier === carrier else {
                        return
                    }
                    self.handleCarrierFailure()
                }
            }
            self.carrier = carrier
            carrier.start(secret: secret, bridgeCapability: bridgeCapability) { [weak self] result in
                guard let self else {
                    completion?(.failure(WebProxyHttpCarrierError.carrierClosed))
                    return
                }
                self.queue.async {
                    guard generation == self.transportReconnectGeneration else {
                        // Superseded — by a stop, which already answered anyone who had joined
                        // this attempt. Whatever owns the reconnect state now keeps it; answer
                        // only this call's own caller and touch nothing else.
                        completion?(.failure(WebProxyHttpCarrierError.carrierClosed))
                        return
                    }
                    switch result {
                    case .success:
                        // Now drop local streams so MtProto reconnects against a READY carrier.
                        // The relay's stream ids belong to the session that just went away, so
                        // the counter restarts with it.
                        for stream in self.streams.values {
                            stream.connection.cancel()
                        }
                        self.streams.removeAll()
                        self.nextStreamId = 1
                        WebProxyLog.log("sidecar transport reconnect (\(reason)) succeeded, loopback port unchanged")
                        finish(.success(()))
                    case let .failure(error):
                        // No rollback to `previousCarrier`. It is the carrier this reconnect
                        // exists to replace, and a listener left standing in front of a dead one
                        // is exactly the state that puts every MtProto connection on a loopback
                        // port with nothing behind it. Answer the caller — it restarts the whole
                        // sidecar — and then tear this one down.
                        if self.urlSession === urlSession {
                            self.urlSession = previousSession
                        }
                        urlSession.invalidateAndCancel()
                        WebProxyLog.log("sidecar transport reconnect (\(reason)) failed: \(error)")
                        finish(.failure(error))
                        self.onFailure?()
                        self.stopLocked()
                    }
                }
            }
            // Hard timeout: bootstrap must not hang "Connecting" indefinitely after wake.
            self.queue.asyncAfter(deadline: .now() + WebProxySidecar.transportReconnectTimeout) { [weak self] in
                guard let self else {
                    return
                }
                guard generation == self.transportReconnectGeneration, self.transportReconnectInFlight else {
                    return
                }
                self.carrier?.stop()
                self.carrier = nil
                WebProxyLog.log("sidecar transport reconnect (\(reason)) timed out after \(Int(WebProxySidecar.transportReconnectTimeout))s")
                finish(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                self.onFailure?()
                self.stopLocked()
            }
        } catch {
            WebProxyLog.log("sidecar transport reconnect (\(reason)) could not be built: \(error)")
            finish(.failure(error))
            self.onFailure?()
            self.stopLocked()
        }
    }
    
    private func allocateStreamId() -> UInt32 {
        var candidate = self.nextStreamId
        var attempts: UInt32 = 0
        while candidate == 0 || self.streams[candidate] != nil {
            candidate = candidate == WebProxySidecar.maxStreamId ? 1 : candidate &+ 1
            attempts &+= 1
            if attempts > WebProxySidecar.maxStreamId {
                candidate = 1
                break
            }
        }
        self.nextStreamId = candidate == WebProxySidecar.maxStreamId ? 1 : candidate &+ 1
        return candidate
    }
    
    private func accept(connection: NWConnection) {
        // Every stream begins with an OPEN the relay has to see; a carrier that cannot take it
        // yet would leave a stream registered here and unknown there, and its later DATA frames
        // rejected. Refuse the connection instead — MtProto redials, and by then the carrier is
        // either up or the sidecar is gone.
        guard let carrier = self.carrier, carrier.isAcceptingFrames else {
            connection.cancel()
            return
        }
        let streamId = self.allocateStreamId()
        let stream = WebProxyStream(id: streamId, connection: connection)
        self.streams[streamId] = stream
        carrier.sendFrames(WebProxyFrameCodec.encodeBatch([WebProxyFrame(type: .open, streamId: streamId, payload: Data())]))
        
        connection.stateUpdateHandler = { [weak self, weak stream] state in
            guard let self, let stream else {
                return
            }
            switch state {
            case .ready:
                self.receive(from: stream)
            case .failed, .cancelled:
                // Connection callbacks are delivered on the queue passed to `connection.start`,
                // which is `self.queue`, so these handlers do not hop - an extra dispatch per
                // received segment is pure overhead on the sidecar's hottest path. The `.ready`
                // case already assumed this.
                self.closeStream(streamId, notifyRemote: true)
            default:
                break
            }
        }
        connection.start(queue: self.queue)
    }
    
    private func receive(from stream: WebProxyStream) {
        stream.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak stream] data, _, isComplete, error in
            guard let self, let stream else {
                return
            }
            if stream.isClosed {
                return
            }
            if let data = data, !data.isEmpty {
                self.sendStreamData(streamId: stream.id, data: data)
            }
            if isComplete || error != nil {
                self.closeStream(stream.id, notifyRemote: true)
                return
            }
            self.receive(from: stream)
        }
    }
    
    private func sendStreamData(streamId: UInt32, data: Data) {
        guard let stream = self.streams[streamId], !stream.isClosed else {
            return
        }
        if stream.pendingUplinkCount + data.count > WebProxySidecar.maximumPendingUplink {
            // The relay has stopped granting credit and this stream has buffered more than the
            // contract allows. Failing it here keeps one stalled socket from growing without
            // bound; MTProto reconnects the session like any other dropped connection.
            self.closeStream(streamId, notifyRemote: true)
            return
        }
        stream.pendingUplink.append(data)
        self.flushUplink(stream: stream)
    }
    
    /// Emits queued uplink as `DATA` frames while the relay's credit lasts, in chunks of at most
    /// 64 KiB. Whatever credit does not cover stays queued until a `WINDOW` frame grants more.
    private func flushUplink(stream: WebProxyStream) {
        // A carrier still bootstrapping its relay session throws away whatever it is handed. That
        // matters during a resume reconnect, where the listener stays live and MtProto keeps
        // writing into streams that were never interrupted: draining the buffer and spending the
        // send credit into a carrier that cannot take it loses those bytes outright instead of
        // delaying them, which corrupts the stream rather than stalling it. Hold them here; the
        // per-stream ceiling in `sendStreamData` bounds how long that can go on.
        guard let carrier = self.carrier, carrier.isAcceptingFrames else {
            return
        }
        var frames: [WebProxyFrame] = []
        while stream.pendingUplinkCount > 0, stream.sendCredit > 0 {
            let chunkSize = min(min(WebProxyFrameCodec.maxDataChunkSize, stream.sendCredit), stream.pendingUplinkCount)
            let start = stream.pendingUplink.startIndex + stream.pendingUplinkOffset
            let chunk = Data(stream.pendingUplink[start ..< (start + chunkSize)])
            stream.pendingUplinkOffset += chunkSize
            stream.sendCredit -= chunkSize
            frames.append(WebProxyFrame(type: .data, streamId: stream.id, payload: chunk))
        }
        stream.compactPendingUplink()
        if !frames.isEmpty {
            carrier.sendFrames(WebProxyFrameCodec.encodeBatch(frames))
        }
    }
    
    private func sendFrames(_ frames: [WebProxyFrame]) {
        guard let carrier = self.carrier else {
            return
        }
        carrier.sendFrames(WebProxyFrameCodec.encodeBatch(frames))
    }
    
    private func handleDownlinkBatch(_ batch: Data) {
        guard let frames = try? WebProxyFrameCodec.decodeBatch(batch) else {
            self.onFailure?()
            self.stopLocked()
            return
        }
        for frame in frames {
            switch frame.type {
            case .data:
                self.write(streamId: frame.streamId, data: frame.payload)
            case .close:
                self.closeStream(frame.streamId, notifyRemote: false)
            case .window:
                self.grantUplinkCredit(streamId: frame.streamId, payload: frame.payload)
            case .ping:
                // `PONG` is the exact response to a `PING`, payload included, whatever its size —
                // the previous four-byte requirement dropped keepalives the relay would then time
                // out on.
                self.sendFrames([WebProxyFrame(type: .pong, streamId: frame.streamId, payload: frame.payload)])
            case .bye:
                // The relay is closing the carrier: fail every logical stream and tear down, so the
                // manager reports the failure instead of leaving sockets hanging on a dead session.
                self.onFailure?()
                self.stopLocked()
                return
            default:
                break
            }
        }
    }
    
    private func grantUplinkCredit(streamId: UInt32, payload: Data) {
        guard payload.count == 4, let stream = self.streams[streamId], !stream.isClosed else {
            return
        }
        let base = payload.startIndex
        let delta = (Int(payload[base]) << 24) | (Int(payload[base + 1]) << 16) | (Int(payload[base + 2]) << 8) | Int(payload[base + 3])
        guard delta > 0 else {
            return
        }
        stream.sendCredit += delta
        self.flushUplink(stream: stream)
    }
    
    private func write(streamId: UInt32, data: Data) {
        guard let stream = self.streams[streamId], !stream.isClosed else {
            return
        }
        stream.pendingWrite.append(data)
        self.flushWrite(stream: stream)
    }
    
    private func flushWrite(stream: WebProxyStream) {
        if stream.isWriting || stream.pendingWrite.isEmpty || stream.isClosed {
            return
        }
        stream.isWriting = true
        let chunk = stream.pendingWrite
        stream.pendingWrite = Data()
        stream.connection.send(content: chunk, completion: .contentProcessed { [weak self, weak stream] error in
            guard let self, let stream else {
                return
            }
            stream.isWriting = false
            if error != nil {
                self.closeStream(stream.id, notifyRemote: true)
                return
            }
            // Downlink credit is returned only once the bytes have actually reached the local
            // socket, which is what bounds unread data per stream. Without this the relay
            // spends its implicit 4 MiB window and then stops sending — a large download
            // stalled part-way with the connection still nominally up.
            if !stream.isClosed, !chunk.isEmpty {
                stream.pendingWindowCredit += chunk.count
                // Flush once enough has piled up to be worth a frame, or as soon as the socket has
                // caught up. The second condition is what keeps a stream that goes quiet part-way
                // through the window from stalling on credit that was never announced.
                self.flushWindowCredit(stream: stream, force: stream.pendingWrite.isEmpty)
            }
            self.flushWrite(stream: stream)
        })
    }
    
    private func flushWindowCredit(stream: WebProxyStream, force: Bool) {
        guard stream.pendingWindowCredit > 0, !stream.isClosed else {
            return
        }
        if !force, stream.pendingWindowCredit < WebProxySidecar.windowCreditFlushThreshold {
            return
        }
        // Same rule as the uplink: a carrier that cannot take the frame must not be charged for
        // it. Zeroing the counter into a dropped WINDOW loses the grant for good — the relay goes
        // on believing those bytes are still outstanding, spends its implicit window and stops
        // sending, and the download stalls part-way with the connection nominally up. The credit
        // stays pending until there is a carrier to announce it to.
        guard let carrier = self.carrier, carrier.isAcceptingFrames else {
            return
        }
        let delta = stream.pendingWindowCredit
        stream.pendingWindowCredit = 0
        self.sendWindowCredit(carrier: carrier, streamId: stream.id, bytes: delta)
    }
    
    private func sendWindowCredit(carrier: WebProxyHttpCarrier, streamId: UInt32, bytes: Int) {
        let delta = UInt32(clamping: bytes)
        var payload = Data(capacity: 4)
        payload.append(UInt8((delta >> 24) & 0xff))
        payload.append(UInt8((delta >> 16) & 0xff))
        payload.append(UInt8((delta >> 8) & 0xff))
        payload.append(UInt8(delta & 0xff))
        carrier.sendFrames(WebProxyFrameCodec.encodeBatch([WebProxyFrame(type: .window, streamId: streamId, payload: payload)]))
    }
    
    private func closeStream(_ streamId: UInt32, notifyRemote: Bool) {
        guard let stream = self.streams.removeValue(forKey: streamId) else {
            return
        }
        if stream.isClosed {
            return
        }
        stream.isClosed = true
        stream.pendingUplink = Data()
        stream.pendingUplinkOffset = 0
        stream.pendingWindowCredit = 0
        stream.pendingWrite = Data()
        stream.connection.cancel()
        if notifyRemote {
            self.sendFrames([WebProxyFrame(type: .close, streamId: streamId, payload: Data())])
        }
    }
}
