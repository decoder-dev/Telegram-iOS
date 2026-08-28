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
    private var consecutiveTransportReconnects = 0
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
                carrier.onFailure = { [weak self] _ in
                    self?.queue.async {
                        self?.handleCarrierFailure()
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
        self.consecutiveTransportReconnects = 0
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
            // Explicit resume always gets a full reconnect budget.
            self.consecutiveTransportReconnects = 0
            self.reconnectTransportLocked(reason: "explicit", completion: completion)
        }
    }
    
    private func handleCarrierFailure() {
        // The relay does not resume a lost WebSocket carrier session. Keeping this listener while
        // attempting an in-place replacement can leave MtProto on a loopback port whose carrier
        // is already gone. Report failure and let the manager create a new listener and session
        // together.
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
        if self.transportReconnectInFlight {
            completion?(.success(()))
            return
        }
        self.transportReconnectInFlight = true
        self.consecutiveTransportReconnects += 1
        self.transportReconnectGeneration &+= 1
        let generation = self.transportReconnectGeneration
        
        // Keep existing local streams and the old carrier until the NEW carrier is ready.
        // Dropping streams first made MtProto reconnect into a dead gap → infinite
        // Connecting/Updating, and canceling WebSockets mid-receive correlated with SIGABRT on resume.
        let previousCarrier = self.carrier
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
            carrier.onFailure = { [weak self] _ in
                self?.queue.async {
                    self?.handleCarrierFailure()
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
                        completion?(.failure(WebProxyHttpCarrierError.carrierClosed))
                        return
                    }
                    self.transportReconnectInFlight = false
                    switch result {
                    case .success:
                        self.consecutiveTransportReconnects = 0
                        // Now drop local streams so MtProto reconnects against a READY carrier.
                        for stream in self.streams.values {
                            stream.connection.cancel()
                        }
                        self.streams.removeAll()
                        self.nextStreamId = 1
                        previousCarrier?.stop()
                        previousSession?.invalidateAndCancel()
                        completion?(.success(()))
                    case let .failure(error):
                        // Roll back to previous carrier if we still have it.
                        if self.carrier === carrier {
                            self.carrier = previousCarrier
                        }
                        if self.urlSession === urlSession {
                            self.urlSession = previousSession
                            urlSession.invalidateAndCancel()
                        }
                        if reason == "explicit" {
                            completion?(.failure(error))
                        } else {
                            self.onFailure?()
                            self.stopLocked()
                            completion?(.failure(error))
                        }
                    }
                }
            }
            // Hard timeout: bootstrap must not hang "Connecting" indefinitely after wake.
            self.queue.asyncAfter(deadline: .now() + 45.0) { [weak self] in
                guard let self else {
                    return
                }
                guard generation == self.transportReconnectGeneration, self.transportReconnectInFlight else {
                    return
                }
                self.transportReconnectInFlight = false
                self.carrier?.stop()
                self.carrier = nil
                if reason == "explicit" {
                    completion?(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                } else {
                    self.onFailure?()
                    self.stopLocked()
                    completion?(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                }
            }
        } catch {
            self.transportReconnectInFlight = false
            self.onFailure?()
            self.stopLocked()
            completion?(.failure(error))
        }
        _ = reason
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
        let streamId = self.allocateStreamId()
        let stream = WebProxyStream(id: streamId, connection: connection)
        self.streams[streamId] = stream
        self.sendFrames([WebProxyFrame(type: .open, streamId: streamId, payload: Data())])
        
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
            self.sendFrames(frames)
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
        let delta = stream.pendingWindowCredit
        stream.pendingWindowCredit = 0
        self.sendWindowCredit(streamId: stream.id, bytes: delta)
    }
    
    private func sendWindowCredit(streamId: UInt32, bytes: Int) {
        let delta = UInt32(clamping: bytes)
        var payload = Data(capacity: 4)
        payload.append(UInt8((delta >> 24) & 0xff))
        payload.append(UInt8((delta >> 16) & 0xff))
        payload.append(UInt8((delta >> 8) & 0xff))
        payload.append(UInt8(delta & 0xff))
        self.sendFrames([WebProxyFrame(type: .window, streamId: streamId, payload: payload)])
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
