import Foundation

public enum WebProxyHttpCarrierError: Error {
    case invalidHostname
    case bridgeRequestFailed
    case bootstrapTokenMissing
    case sessionCreationFailed
    case welcomeMissing
    case uplinkRejected
    case downlinkRejected
    case carrierClosed
    case unsupportedCarrierMode
}

/// Native HTTPS / WebSocket carrier for tproxy-server: no WKWebView required.
///
/// - `https`: one serialized uplink sequence and one downlink long-poll for the whole session.
/// - `https-lanes`: independent uplink sequence, downlink cursor, and long-poll per logical stream
///   (`X-Lane-ID`). Lane 0 is reserved for session-level PONG; every non-zero lane must begin with
///   OPEN and carries only frames with that stream id (PROTOCOL.md).
/// - `websocket`: one multiplexed `wss://H/api/v1/ws` with subprotocol `tproxy-v1.<token>`.
/// - `websocket-lanes`: one WebSocket per nonzero stream, subprotocol
///   `tproxy-lane-v1.<token>.<stream_id>`; first binary message must begin with OPEN. Lane socket
///   failure closes only that stream; failure to establish a new lane fails the parent carrier.
final class WebProxyHttpCarrier {
    private enum CarrierMode {
        case https
        case httpsLanes
        case websocket
        case websocketLanes
    }
    
    /// Per-lane state used only in `https-lanes`. Mirrors the serialized buffers of the single-path
    /// `https` mode so both modes share the same batching / pacing rules.
    private final class LaneState {
        var upSequence: Int = 1
        var downCursor: String = "0"
        var uplinkBuffer = Data()
        var uplinkBufferOffset = 0
        var uplinkRunning = false
        /// True while a downlink long-poll for this lane is in flight or scheduled.
        var downlinkPolling = false
        /// Set when the relay returns `X-Lane-Closed: 1` after the stream has drained.
        var closed = false
        /// The relay only creates a lane on the first uplink that begins with OPEN.
        /// Polling `/down` before that admission races and returns a decoy 404
        /// (ManagerError::Protocol → serve_decoy). Start downlink only after the first
        /// uplink is ACKed. Lane 0 is session control and is polled from session start.
        var uplinkAdmitted = false
        var fastEmptyDownlinkStreak = 0
        
        var pendingUplinkCount: Int {
            return self.uplinkBuffer.count - self.uplinkBufferOffset
        }
    }
    
    private let hostname: String
    private let origin: URL
    private let session: URLSession
    private let queue: DispatchQueue
    
    private var sessionToken: String = ""
    private var carrierMode: CarrierMode = .https
    private var closed = false
    /// True only while `stop()` is tearing the carrier down. Unexpected URLSession
    /// cancellations (background freeze, radio drop) must still fail the carrier so the
    /// manager restarts — ignoring *all* cancels left a live endpoint with a dead WebSocket
    /// and media hung until the user toggled the proxy.
    private var intentionalTeardown = false
    /// Bumped on every stop/fail so in-flight URLSession / WebSocket callbacks from a
    /// torn-down generation cannot call fail() or completion again (wake/resume crash source).
    private var transportEpoch: UInt64 = 0
    /// The relay must open with `WELCOME` before any stream traffic. Until it does, an ordinary
    /// 200 from a site that is not a relay at all is indistinguishable from a working carrier —
    /// which is how a mistyped hostname used to sit in `connecting` forever.
    private var awaitingWelcome = true
    
    // MARK: - Serialized `https` path (single lane)
    
    private var downCursor: String = "0"
    private var upSequence: Int = 1
    private var uplinkBuffer = Data()
    private var uplinkBufferOffset = 0
    private var uplinkRunning = false
    private var fastEmptyDownlinkStreak = 0
    
    // MARK: - `https-lanes` path
    
    private var lanes: [UInt32: LaneState] = [:]
    
    // MARK: - `websocket` / `websocket-lanes` path
    
    /// One multiplexed socket for `websocket` mode.
    private var multiplexWebSocket: URLSessionWebSocketTask?
    private var multiplexWsOpen = false
    private var multiplexWsUplink = Data()
    private var multiplexWsUplinkOffset = 0
    private var multiplexWsSending = false
    private var multiplexReceiveArmed = false
    
    /// Per-stream sockets for `websocket-lanes` (no lane 0 — bootstrap is HTTPS).
    private final class WsLaneState {
        var task: URLSessionWebSocketTask?
        var open = false
        var connecting = false
        var closed = false
        var uplinkBuffer = Data()
        var uplinkBufferOffset = 0
        var sending = false
        var receiveArmed = false
        
        var pendingUplinkCount: Int {
            return self.uplinkBuffer.count - self.uplinkBufferOffset
        }
    }
    private var wsLanes: [UInt32: WsLaneState] = [:]
    /// iOS / CFNetwork quietly stalls when many WebSocket handshakes start at once (Telegram
    /// opens several MTProto sockets together). Cap in-flight upgrades and queue the rest.
    private static let maxConcurrentWsLaneConnects = 4
    private static let wsLaneConnectTimeout: Double = 20.0
    private var wsLaneConnectInFlight = 0
    private var wsLaneConnectQueue: [UInt32] = []
    
    /// Matches the hosted bridge's 2 MiB batch. Anything above it waits for the next POST.
    private static let maximumUplinkBatchSize = 2 * 1024 * 1024
    /// Hard ceiling on data queued for the carrier. Past this the carrier fails instead of growing
    /// without bound: `AbstractSocket`-style writes have no backpressure to push back with.
    private static let maximumUplinkBufferSize = 64 * 1024 * 1024
    /// Most already-sent bytes the buffer may keep in front of the read cursor before compacting.
    private static let maximumRetainedUplinkPrefix = 8 * 1024 * 1024
    /// Per-lane ceiling in `https-lanes` (PROTOCOL / telemt: 8 MiB per lane).
    private static let maximumLaneUplinkBufferSize = 8 * 1024 * 1024
    
    /// Downlink pacing. The relay is expected to hold `/api/v1/down` open until it has something to
    /// send, but nothing in the protocol guarantees it, and a relay — or a CDN in front of one —
    /// that answers 204 promptly turns the poll into an unbounded loop of HTTPS requests: hundreds
    /// per second, each waking the radio, with no user traffic at all. So an *empty* response that
    /// comes back faster than a long poll plausibly could is paced, with exponential backoff and
    /// jitter. A response that took a while, or one that carried data, re-polls immediately — a
    /// correctly long-polling relay is never slowed down by this.
    private static let minimumDownlinkInterval: Double = 0.5
    private static let maximumDownlinkInterval: Double = 5.0
    
    var onDownlinkBatch: ((Data) -> Void)?
    var onFailure: ((Error) -> Void)?
    
    init(hostname: String, session: URLSession, queue: DispatchQueue) throws {
        let normalized = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard WebProxyHostname.isValid(normalized), let origin = URL(string: "https://\(normalized)") else {
            throw WebProxyHttpCarrierError.invalidHostname
        }
        self.hostname = normalized
        self.origin = origin
        self.session = session
        self.queue = queue
    }
    
    func start(secret: Data, bridgeCapability: String, completion: @escaping (Result<Void, Error>) -> Void) {
        self.queue.async {
            guard !self.closed else {
                completion(.failure(WebProxyHttpCarrierError.carrierClosed))
                return
            }
            // Chained rather than blocking: both legs used to `DispatchSemaphore.wait()` on this
            // queue, parking it for up to 30s and 90s respectively while nothing else could run on it.
            self.fetchBootstrapToken(bridgeCapability: bridgeCapability) { result in
                switch result {
                case let .success(bootstrap):
                    self.createSession(bootstrapToken: bootstrap) { result in
                        switch result {
                        case .success:
                            self.startCarrierTransport(completion: completion)
                        case let .failure(error):
                            completion(.failure(error))
                        }
                    }
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func stop() {
        // `WebProxySidecar` owns this carrier and calls `stop()` on the same serial queue it
        // supplied at construction. This must therefore tear down synchronously: scheduling the
        // work asynchronously let the sidecar invalidate the URLSession first, then this block
        // attempted to create the DELETE task and CFNetwork aborted the process with
        // "Task created in a session that has been invalidated".
        guard !self.closed else {
            return
        }
        self.intentionalTeardown = true
        self.closed = true
        self.transportEpoch &+= 1
        let token = self.sessionToken
        self.sessionToken = ""
        self.lanes.removeAll()
        self.tearDownAllWebSockets()
        if !token.isEmpty, let url = URL(string: "/api/v1/session", relativeTo: self.origin) {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let task = self.session.dataTask(with: request)
            task.resume()
        }
    }
    
    func sendFrames(_ batch: Data) {
        self.queue.async {
            guard !self.closed, !self.sessionToken.isEmpty else {
                return
            }
            switch self.carrierMode {
            case .https:
                self.enqueueSerializedUplink(batch)
            case .httpsLanes:
                self.enqueueLanedUplink(batch)
            case .websocket:
                self.enqueueMultiplexWsUplink(batch)
            case .websocketLanes:
                self.enqueueWsLanedUplink(batch)
            }
        }
    }
    
    // MARK: - Session bootstrap
    
    private func fetchBootstrapToken(bridgeCapability: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard !self.closed else {
            completion(.failure(WebProxyHttpCarrierError.carrierClosed))
            return
        }
        var components = URLComponents(url: self.origin, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "bridge", value: bridgeCapability)]
        guard let url = components.url else {
            completion(.failure(WebProxyHttpCarrierError.bridgeRequestFailed))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30.0
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        
        let task = self.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                completion(.failure(WebProxyHttpCarrierError.carrierClosed))
                return
            }
            self.queue.async {
                guard !self.closed else {
                    completion(.failure(WebProxyHttpCarrierError.carrierClosed))
                    return
                }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    completion(.failure(WebProxyHttpCarrierError.bridgeRequestFailed))
                    return
                }
                guard let html = data.flatMap({ String(data: $0, encoding: .utf8) }),
                      let token = Self.parseBootstrapToken(from: html) else {
                    completion(.failure(WebProxyHttpCarrierError.bootstrapTokenMissing))
                    return
                }
                completion(.success(token))
            }
        }
        task.resume()
    }
    
    static func parseBootstrapToken(from html: String) -> String? {
        let patterns = [
            #"const bootstrap="([^"]+)""#,
            #"const bootstrap='([^']+)'"#,
            #"bootstrap\s*=\s*"([^"]+)""#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: html) {
                let token = String(html[range])
                if !token.isEmpty {
                    return token
                }
            }
        }
        return nil
    }
    
    private func createSession(bootstrapToken: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !self.closed else {
            completion(.failure(WebProxyHttpCarrierError.carrierClosed))
            return
        }
        guard let url = URL(string: "/api/v1/session", relativeTo: self.origin) else {
            completion(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = WebProxyFrameCodec.encode(.hello())
        request.setValue("Bearer \(bootstrapToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 90.0
        
        let task = self.session.dataTask(with: request) { [weak self] data, urlResponse, error in
            guard let self else {
                completion(.failure(WebProxyHttpCarrierError.carrierClosed))
                return
            }
            self.queue.async {
                guard !self.closed else {
                    completion(.failure(WebProxyHttpCarrierError.carrierClosed))
                    return
                }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                guard let response = urlResponse as? HTTPURLResponse, response.statusCode == 200 else {
                    completion(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                    return
                }
                guard let token = response.value(forHTTPHeaderField: "X-Session-Token"), !token.isEmpty else {
                    completion(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                    return
                }

                let modeHeader = (response.value(forHTTPHeaderField: "X-Carrier-Mode") ?? "https")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                switch modeHeader {
                case "https", "":
                    self.carrierMode = .https
                case "https-lanes":
                    self.carrierMode = .httpsLanes
                case "websocket":
                    self.carrierMode = .websocket
                case "websocket-lanes":
                    self.carrierMode = .websocketLanes
                default:
                    completion(.failure(WebProxyHttpCarrierError.unsupportedCarrierMode))
                    return
                }

                WebProxyLog.log("session opened with \(self.hostname), relay reports carrier mode \(response.value(forHTTPHeaderField: "X-Carrier-Mode") ?? "unset")")

                self.sessionToken = token
                self.downCursor = response.value(forHTTPHeaderField: "X-Down-Cursor") ?? "0"
                if let body = data, !body.isEmpty {
                    do {
                        let frames = try WebProxyFrameCodec.decodeBatch(body)
                        try self.consumeWelcome(in: frames)
                    } catch {
                        completion(.failure(error))
                        return
                    }
                    // Frames trailing the handshake are ordinary downlink; the reader ignores `WELCOME`.
                    self.onDownlinkBatch?(body)
                }
                completion(.success(()))
            }
        }
        task.resume()
    }
    
    /// The first relay frame of the session must be `WELCOME` on stream zero.
    private func consumeWelcome(in frames: [WebProxyFrame]) throws {
        guard self.awaitingWelcome else {
            return
        }
        guard let first = frames.first, first.type == .welcome, first.streamId == 0 else {
            throw WebProxyHttpCarrierError.welcomeMissing
        }
        self.awaitingWelcome = false
    }
    
    private func startCarrierTransport(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !self.closed else {
            completion(.failure(WebProxyHttpCarrierError.carrierClosed))
            return
        }
        switch self.carrierMode {
        case .https:
            self.pollDownlinkSerialized()
            completion(.success(()))
        case .httpsLanes:
            // Lane 0 is reserved for session-level control (PONG). Poll it from the start so
            // session keepalives are not blocked on the first data stream.
            let lane = self.laneState(for: 0)
            self.pollDownlinkLane(laneId: 0, lane: lane)
            completion(.success(()))
        case .websocket:
            self.openMultiplexWebSocket(completion: completion)
        case .websocketLanes:
            // Lanes open on demand when the first OPEN for a stream arrives.
            completion(.success(()))
        }
    }
    
    // MARK: - Frame splitting helpers
    
    /// Largest prefix of `buffer` that ends on a frame boundary and is at most `limit` bytes.
    /// A carrier message has to carry whole frames, so a batch can only be cut here.
    /// Offsets are relative to `buffer.startIndex`, so a slice may be passed in.
    static func frameBoundaryOffset(in buffer: Data, notExceeding limit: Int) -> Int {
        var offset = 0
        var lastBoundary = 0
        while offset + 8 <= buffer.count {
            let base = buffer.startIndex + offset
            let payloadSize = (Int(buffer[base + 4]) << 24) | (Int(buffer[base + 5]) << 16) | (Int(buffer[base + 6]) << 8) | Int(buffer[base + 7])
            let end = offset + 8 + payloadSize
            if end > buffer.count {
                break
            }
            if end > limit {
                break
            }
            lastBoundary = end
            offset = end
        }
        // A single frame larger than the limit still has to go out whole, so never return zero
        // while there is a complete frame to send.
        if lastBoundary == 0 {
            return buffer.count
        }
        return lastBoundary
    }
    
    /// Demultiplexes a shared-frame batch into per-stream contiguous sub-batches, preserving order
    /// within each stream. Incomplete trailing bytes are dropped (caller must only pass complete
    /// frames from the sidecar).
    static func splitBatchByStreamId(_ batch: Data) -> [UInt32: Data] {
        var buckets: [UInt32: Data] = [:]
        var offset = 0
        let base = batch.startIndex
        while offset + 8 <= batch.count {
            let header = base + offset
            let streamId = (UInt32(batch[header + 1]) << 16) | (UInt32(batch[header + 2]) << 8) | UInt32(batch[header + 3])
            let payloadSize = (Int(batch[header + 4]) << 24) | (Int(batch[header + 5]) << 16) | (Int(batch[header + 6]) << 8) | Int(batch[header + 7])
            let end = offset + 8 + payloadSize
            if end > batch.count {
                break
            }
            let frameSlice = batch[(base + offset) ..< (base + end)]
            if buckets[streamId] == nil {
                buckets[streamId] = Data(frameSlice)
            } else {
                buckets[streamId]!.append(frameSlice)
            }
            offset = end
        }
        return buckets
    }
    
    private func compactBuffer(_ buffer: inout Data, offset: inout Int) {
        if offset == 0 {
            return
        }
        if offset >= buffer.count {
            buffer = Data()
            offset = 0
            return
        }
        if offset * 2 >= buffer.count || offset >= WebProxyHttpCarrier.maximumRetainedUplinkPrefix {
            buffer = Data(buffer[(buffer.startIndex + offset)...])
            offset = 0
        }
    }
    
    // MARK: - Serialized `https` uplink / downlink
    
    private var pendingUplinkCount: Int {
        return self.uplinkBuffer.count - self.uplinkBufferOffset
    }
    
    private func enqueueSerializedUplink(_ batch: Data) {
        if self.pendingUplinkCount + batch.count > WebProxyHttpCarrier.maximumUplinkBufferSize {
            self.fail(WebProxyHttpCarrierError.uplinkRejected)
            return
        }
        self.uplinkBuffer.append(batch)
        self.runUplinkSerializedIfNeeded()
    }
    
    private func runUplinkSerializedIfNeeded() {
        if self.uplinkRunning || self.closed || self.sessionToken.isEmpty || self.pendingUplinkCount <= 0 {
            return
        }
        guard let url = URL(string: "/api/v1/up", relativeTo: self.origin) else {
            self.fail(WebProxyHttpCarrierError.uplinkRejected)
            return
        }
        self.uplinkRunning = true
        let remaining = self.uplinkBuffer[(self.uplinkBuffer.startIndex + self.uplinkBufferOffset)...]
        let splitOffset = WebProxyHttpCarrier.frameBoundaryOffset(in: remaining, notExceeding: WebProxyHttpCarrier.maximumUplinkBatchSize)
        let batchStart = remaining.startIndex
        let batch = Data(remaining[batchStart ..< (batchStart + splitOffset)])
        self.uplinkBufferOffset += splitOffset
        self.compactBuffer(&self.uplinkBuffer, offset: &self.uplinkBufferOffset)
        let sequence = self.upSequence
        self.upSequence += 1
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = batch
        request.setValue("Bearer \(self.sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(sequence), forHTTPHeaderField: "X-Up-Seq")
        request.timeoutInterval = 90.0
        
        let task = self.session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else {
                return
            }
            self.queue.async {
                defer {
                    self.uplinkRunning = false
                    if self.pendingUplinkCount > 0 {
                        self.runUplinkSerializedIfNeeded()
                    }
                }
                if self.closed {
                    return
                }
                if error != nil {
                    self.fail(WebProxyHttpCarrierError.uplinkRejected)
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 204,
                      http.value(forHTTPHeaderField: "X-Up-Ack") == String(sequence) else {
                    self.fail(WebProxyHttpCarrierError.uplinkRejected)
                    return
                }
            }
        }
        task.resume()
    }
    
    private func scheduleDownlinkPollSerialized(requestStartedAt: Double, wasEmpty: Bool) {
        if self.closed {
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - requestStartedAt
        if !wasEmpty || elapsed >= WebProxyHttpCarrier.minimumDownlinkInterval {
            self.fastEmptyDownlinkStreak = 0
            self.pollDownlinkSerialized()
            return
        }
        self.fastEmptyDownlinkStreak += 1
        let step = min(self.fastEmptyDownlinkStreak - 1, 8)
        let backoff = min(WebProxyHttpCarrier.maximumDownlinkInterval, WebProxyHttpCarrier.minimumDownlinkInterval * pow(2.0, Double(step)))
        let delay = backoff * Double.random(in: 0.85 ... 1.15)
        self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollDownlinkSerialized()
        }
    }
    
    private func pollDownlinkSerialized() {
        guard !self.closed, !self.sessionToken.isEmpty else {
            return
        }
        guard let url = URL(string: "/api/v1/down", relativeTo: self.origin) else {
            self.fail(WebProxyHttpCarrierError.downlinkRejected)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(self.sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(self.downCursor, forHTTPHeaderField: "X-Down-Cursor")
        request.timeoutInterval = 120.0
        
        let startedAt = CFAbsoluteTimeGetCurrent()
        let task = self.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }
            self.queue.async {
                if self.closed {
                    return
                }
                if error != nil {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                if http.statusCode == 204 {
                    self.scheduleDownlinkPollSerialized(requestStartedAt: startedAt, wasEmpty: true)
                    return
                }
                guard http.statusCode == 200,
                      let nextCursor = http.value(forHTTPHeaderField: "X-Down-Cursor"),
                      let data = data, !data.isEmpty else {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                if self.awaitingWelcome {
                    do {
                        try self.consumeWelcome(in: WebProxyFrameCodec.decodeBatch(data))
                    } catch {
                        self.fail(WebProxyHttpCarrierError.welcomeMissing)
                        return
                    }
                }
                self.downCursor = nextCursor
                self.onDownlinkBatch?(data)
                self.scheduleDownlinkPollSerialized(requestStartedAt: startedAt, wasEmpty: false)
            }
        }
        task.resume()
    }
    
    // MARK: - `https-lanes` uplink / downlink
    
    private func laneState(for laneId: UInt32) -> LaneState {
        if let existing = self.lanes[laneId] {
            return existing
        }
        let lane = LaneState()
        self.lanes[laneId] = lane
        return lane
    }
    
    private func enqueueLanedUplink(_ batch: Data) {
        let buckets = WebProxyHttpCarrier.splitBatchByStreamId(batch)
        guard !buckets.isEmpty else {
            return
        }
        for (streamId, frames) in buckets {
            // PROTOCOL: lane 0 accepts only session PONG. Sidecar already emits PONG with the
            // stream_id of the matching PING; non-zero streams never use lane 0 for DATA/OPEN.
            let lane = self.laneState(for: streamId)
            if lane.closed {
                continue
            }
            if lane.pendingUplinkCount + frames.count > WebProxyHttpCarrier.maximumLaneUplinkBufferSize {
                self.fail(WebProxyHttpCarrierError.uplinkRejected)
                return
            }
            lane.uplinkBuffer.append(frames)
            self.runUplinkLaneIfNeeded(laneId: streamId, lane: lane)
            // Do NOT start downlink here. The relay admits a non-zero lane only when the
            // first uplink (must begin with OPEN) is accepted. A concurrent /down before
            // that races into serve_decoy() → 404 and used to kill the whole carrier.
            // Downlink starts from the uplink completion handler once uplinkAdmitted is set.
        }
    }
    
    private func runUplinkLaneIfNeeded(laneId: UInt32, lane: LaneState) {
        if lane.uplinkRunning || lane.closed || self.closed || self.sessionToken.isEmpty || lane.pendingUplinkCount <= 0 {
            return
        }
        guard let url = URL(string: "/api/v1/up", relativeTo: self.origin) else {
            self.fail(WebProxyHttpCarrierError.uplinkRejected)
            return
        }
        lane.uplinkRunning = true
        let remaining = lane.uplinkBuffer[(lane.uplinkBuffer.startIndex + lane.uplinkBufferOffset)...]
        let splitOffset = WebProxyHttpCarrier.frameBoundaryOffset(in: remaining, notExceeding: WebProxyHttpCarrier.maximumUplinkBatchSize)
        let batchStart = remaining.startIndex
        let batch = Data(remaining[batchStart ..< (batchStart + splitOffset)])
        lane.uplinkBufferOffset += splitOffset
        self.compactBuffer(&lane.uplinkBuffer, offset: &lane.uplinkBufferOffset)
        let sequence = lane.upSequence
        lane.upSequence += 1
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = batch
        request.setValue("Bearer \(self.sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(sequence), forHTTPHeaderField: "X-Up-Seq")
        request.setValue(String(laneId), forHTTPHeaderField: "X-Lane-ID")
        request.timeoutInterval = 90.0
        
        let task = self.session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else {
                return
            }
            self.queue.async {
                defer {
                    lane.uplinkRunning = false
                    if !lane.closed, lane.pendingUplinkCount > 0 {
                        self.runUplinkLaneIfNeeded(laneId: laneId, lane: lane)
                    }
                }
                if self.closed || lane.closed {
                    return
                }
                if error != nil {
                    self.fail(WebProxyHttpCarrierError.uplinkRejected)
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 204,
                      http.value(forHTTPHeaderField: "X-Up-Ack") == String(sequence) else {
                    self.fail(WebProxyHttpCarrierError.uplinkRejected)
                    return
                }
                // First successful uplink admits the lane on the relay. Only then is it
                // safe to long-poll /down for this X-Lane-ID.
                if !lane.uplinkAdmitted {
                    lane.uplinkAdmitted = true
                    if !lane.downlinkPolling, !lane.closed {
                        self.pollDownlinkLane(laneId: laneId, lane: lane)
                    }
                }
            }
        }
        task.resume()
    }
    
    private func scheduleDownlinkPollLane(laneId: UInt32, lane: LaneState, requestStartedAt: Double, wasEmpty: Bool) {
        if self.closed || lane.closed {
            lane.downlinkPolling = false
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - requestStartedAt
        if !wasEmpty || elapsed >= WebProxyHttpCarrier.minimumDownlinkInterval {
            lane.fastEmptyDownlinkStreak = 0
            self.pollDownlinkLane(laneId: laneId, lane: lane)
            return
        }
        lane.fastEmptyDownlinkStreak += 1
        let step = min(lane.fastEmptyDownlinkStreak - 1, 8)
        let backoff = min(WebProxyHttpCarrier.maximumDownlinkInterval, WebProxyHttpCarrier.minimumDownlinkInterval * pow(2.0, Double(step)))
        let delay = backoff * Double.random(in: 0.85 ... 1.15)
        self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            if self.closed || lane.closed {
                lane.downlinkPolling = false
                return
            }
            self.pollDownlinkLane(laneId: laneId, lane: lane)
        }
    }
    
    private func pollDownlinkLane(laneId: UInt32, lane: LaneState) {
        guard !self.closed, !lane.closed, !self.sessionToken.isEmpty else {
            lane.downlinkPolling = false
            return
        }
        guard let url = URL(string: "/api/v1/down", relativeTo: self.origin) else {
            self.fail(WebProxyHttpCarrierError.downlinkRejected)
            return
        }
        lane.downlinkPolling = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(self.sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(lane.downCursor, forHTTPHeaderField: "X-Down-Cursor")
        request.setValue(String(laneId), forHTTPHeaderField: "X-Lane-ID")
        request.timeoutInterval = 120.0
        
        let startedAt = CFAbsoluteTimeGetCurrent()
        let task = self.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }
            self.queue.async {
                if self.closed || lane.closed {
                    lane.downlinkPolling = false
                    return
                }
                if error != nil {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                
                // Decoy 404 is what the relay returns for Protocol errors (e.g. /down on a
                // lane that was never OPEN'd). Must not fail the whole carrier — that was
                // the freeze after a couple of chats loaded. Drop this lane's poll; if the
                // race is fixed upstream this path is rare, but keep it non-fatal.
                if http.statusCode == 404 {
                    lane.downlinkPolling = false
                    if !lane.uplinkAdmitted {
                        // Lost the race that should no longer happen; uplink completion will
                        // start a clean poll once OPEN is ACKed.
                        return
                    }
                    // Unexpected after admission: stop this lane only.
                    self.closeLane(laneId: laneId, lane: lane)
                    return
                }
                
                // Relay signals that this lane has finished after CLOSE + drain.
                let laneClosed = (http.value(forHTTPHeaderField: "X-Lane-Closed") ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                
                if http.statusCode == 204 {
                    if let nextCursor = http.value(forHTTPHeaderField: "X-Down-Cursor") {
                        lane.downCursor = nextCursor
                    }
                    if laneClosed {
                        self.closeLane(laneId: laneId, lane: lane)
                        return
                    }
                    self.scheduleDownlinkPollLane(laneId: laneId, lane: lane, requestStartedAt: startedAt, wasEmpty: true)
                    return
                }
                
                guard http.statusCode == 200 else {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                
                if let nextCursor = http.value(forHTTPHeaderField: "X-Down-Cursor") {
                    lane.downCursor = nextCursor
                }
                
                if let data = data, !data.isEmpty {
                    if self.awaitingWelcome {
                        do {
                            try self.consumeWelcome(in: WebProxyFrameCodec.decodeBatch(data))
                        } catch {
                            self.fail(WebProxyHttpCarrierError.welcomeMissing)
                            return
                        }
                    }
                    self.onDownlinkBatch?(data)
                }
                
                if laneClosed {
                    self.closeLane(laneId: laneId, lane: lane)
                    return
                }
                
                let wasEmpty = data == nil || data!.isEmpty
                self.scheduleDownlinkPollLane(laneId: laneId, lane: lane, requestStartedAt: startedAt, wasEmpty: wasEmpty)
            }
        }
        task.resume()
    }
    
    private func closeLane(laneId: UInt32, lane: LaneState) {
        lane.closed = true
        lane.downlinkPolling = false
        lane.uplinkBuffer = Data()
        lane.uplinkBufferOffset = 0
        // Keep the LaneState entry so late uplink from a racing close is ignored rather than
        // recreating the lane; tombstones are bounded by stream churn in the sidecar.
        _ = laneId
    }
    
    // MARK: - Failure
    
    private func isCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return true
        }
        // URLSessionWebSocketTask surfaces some cancels as NSPOSIXErrorDomain ECANCELED.
        if ns.domain == NSPOSIXErrorDomain && ns.code == 89 {
            return true
        }
        return false
    }
    
    private func fail(_ error: Error) {
        if self.closed {
            return
        }

        // Only swallow cancels from our own stop(). Background/radio cancels are real failures.
        if self.isCancellation(error), self.intentionalTeardown {
            return
        }

        WebProxyLog.log("carrier failed against \(self.hostname): \(error)")

        self.closed = true
        self.transportEpoch &+= 1
        self.lanes.removeAll()
        self.tearDownAllWebSockets()
        self.onFailure?(error)
    }
    
    // MARK: - WebSocket helpers
    
    private func wsURL() -> URL? {
        return URL(string: "wss://\(self.hostname)/api/v1/ws")
    }
    
    private func tearDownAllWebSockets() {
        // Do not call cancel(with:) on each URLSessionWebSocketTask while a receive is pending —
        // that path has produced SIGABRT on resume under CFNetwork. Drop references and let the
        // owning URLSession invalidateAndCancel() from the sidecar finish teardown.
        self.multiplexWebSocket = nil
        self.multiplexWsOpen = false
        self.multiplexReceiveArmed = false
        self.multiplexWsUplink = Data()
        self.multiplexWsUplinkOffset = 0
        self.multiplexWsSending = false
        for lane in self.wsLanes.values {
            lane.task = nil
            lane.open = false
            lane.closed = true
            lane.connecting = false
            lane.sending = false
            lane.receiveArmed = false
        }
        self.wsLanes.removeAll()
        self.wsLaneConnectInFlight = 0
        self.wsLaneConnectQueue.removeAll()
    }
    
    private func makeWebSocketTask(subprotocol: String) -> URLSessionWebSocketTask? {
        guard !self.closed, let url = self.wsURL() else {
            return nil
        }
        // Subprotocol carries the session bearer (PROTOCOL.md). Prefer the protocols:
        // form so URLSession negotiates Sec-WebSocket-Protocol correctly. Never log it.
        let task = self.session.webSocketTask(with: url, protocols: [subprotocol])
        return task
    }
    
    // MARK: - Multiplexed `websocket`
    
    private func openMultiplexWebSocket(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !self.closed, !self.sessionToken.isEmpty else {
            completion(.failure(WebProxyHttpCarrierError.carrierClosed))
            return
        }
        let epoch = self.transportEpoch
        let subprotocol = "tproxy-v1.\(self.sessionToken)"
        guard let task = self.makeWebSocketTask(subprotocol: subprotocol) else {
            completion(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
            return
        }
        self.multiplexWebSocket = task
        task.resume()
        // Do not gate on sendPing: a cancelled ping during foreground restart used to call
        // fail()+completion and race the next generation. Mark open after resume; the receive
        // loop and first send surface a real upgrade failure.
        self.multiplexWsOpen = true
        self.armMultiplexReceive()
        self.flushMultiplexWsUplink()
        if epoch == self.transportEpoch, !self.closed {
            completion(.success(()))
        } else {
            completion(.failure(WebProxyHttpCarrierError.carrierClosed))
        }
    }
    
    private func armMultiplexReceive() {
        guard !self.multiplexReceiveArmed, let task = self.multiplexWebSocket, !self.closed else {
            return
        }
        self.multiplexReceiveArmed = true
        let epoch = self.transportEpoch
        self.receiveWebSocket(task, epoch: epoch) { [weak self] data in
            guard let self, !self.closed, epoch == self.transportEpoch else {
                return
            }
            if self.awaitingWelcome {
                do {
                    try self.consumeWelcome(in: WebProxyFrameCodec.decodeBatch(data))
                } catch {
                    // WELCOME was already consumed from the HTTPS session body when present.
                }
            }
            self.onDownlinkBatch?(data)
        } onError: { [weak self] error in
            guard let self else {
                return
            }
            guard epoch == self.transportEpoch else {
                return
            }
            self.multiplexReceiveArmed = false
            if self.closed || self.isCancellation(error) {
                return
            }
            self.fail(error)
        }
    }
    
    private func receiveWebSocket(_ task: URLSessionWebSocketTask, epoch: UInt64, onMessage: @escaping (Data) -> Void, onError: @escaping (Error) -> Void) {
        task.receive { [weak self] result in
            guard let self else {
                return
            }
            self.queue.async {
                guard !self.closed, epoch == self.transportEpoch else {
                    return
                }
                switch result {
                case let .failure(error):
                    onError(error)
                case let .success(message):
                    switch message {
                    case let .data(data):
                        if !data.isEmpty {
                            onMessage(data)
                        }
                        // Re-arm only while this task is still the active generation.
                        self.receiveWebSocket(task, epoch: epoch, onMessage: onMessage, onError: onError)
                    case .string:
                        // Text messages are rejected by the relay contract.
                        onError(WebProxyHttpCarrierError.downlinkRejected)
                    @unknown default:
                        self.receiveWebSocket(task, epoch: epoch, onMessage: onMessage, onError: onError)
                    }
                }
            }
        }
    }
    
    private func enqueueMultiplexWsUplink(_ batch: Data) {
        if (self.multiplexWsUplink.count - self.multiplexWsUplinkOffset) + batch.count > WebProxyHttpCarrier.maximumUplinkBufferSize {
            self.fail(WebProxyHttpCarrierError.uplinkRejected)
            return
        }
        self.multiplexWsUplink.append(batch)
        self.flushMultiplexWsUplink()
    }
    
    private func flushMultiplexWsUplink() {
        if self.multiplexWsSending || !self.multiplexWsOpen || self.closed {
            return
        }
        guard let task = self.multiplexWebSocket else {
            return
        }
        let pending = self.multiplexWsUplink.count - self.multiplexWsUplinkOffset
        if pending <= 0 {
            return
        }
        let remaining = self.multiplexWsUplink[(self.multiplexWsUplink.startIndex + self.multiplexWsUplinkOffset)...]
        let splitOffset = WebProxyHttpCarrier.frameBoundaryOffset(in: remaining, notExceeding: WebProxyHttpCarrier.maximumUplinkBatchSize)
        let batchStart = remaining.startIndex
        let batch = Data(remaining[batchStart ..< (batchStart + splitOffset)])
        self.multiplexWsUplinkOffset += splitOffset
        self.compactBuffer(&self.multiplexWsUplink, offset: &self.multiplexWsUplinkOffset)
        self.multiplexWsSending = true
        task.send(.data(batch)) { [weak self] error in
            guard let self else {
                return
            }
            self.queue.async {
                self.multiplexWsSending = false
                if self.closed {
                    return
                }
                if let err = error {
                    self.fail(err)
                    return
                }
                self.flushMultiplexWsUplink()
            }
        }
    }
    
    // MARK: - `websocket-lanes`
    
    private func enqueueWsLanedUplink(_ batch: Data) {
        let buckets = WebProxyHttpCarrier.splitBatchByStreamId(batch)
        for (streamId, frames) in buckets {
            if streamId == 0 {
                // No lane-zero WebSocket; session control is HTTPS bootstrap only.
                continue
            }
            let lane = self.wsLaneState(for: streamId)
            if lane.closed {
                continue
            }
            if lane.pendingUplinkCount + frames.count > WebProxyHttpCarrier.maximumLaneUplinkBufferSize {
                // Per-lane ceiling: close only this stream instead of killing the parent carrier
                // (media open-storm used to trip the global fail and freeze every lane).
                self.closeWsLane(laneId: streamId, lane: lane, notifyApp: true)
                continue
            }
            lane.uplinkBuffer.append(frames)
            if lane.open {
                self.flushWsLaneUplink(laneId: streamId, lane: lane)
            } else if !lane.connecting {
                self.requestWsLaneOpen(laneId: streamId)
            }
        }
    }
    
    private func wsLaneState(for laneId: UInt32) -> WsLaneState {
        if let existing = self.wsLanes[laneId] {
            return existing
        }
        let lane = WsLaneState()
        self.wsLanes[laneId] = lane
        return lane
    }
    
    private func requestWsLaneOpen(laneId: UInt32) {
        guard !self.closed else {
            return
        }
        if self.wsLaneConnectInFlight >= WebProxyHttpCarrier.maxConcurrentWsLaneConnects {
            if !self.wsLaneConnectQueue.contains(laneId) {
                self.wsLaneConnectQueue.append(laneId)
            }
            return
        }
        guard let lane = self.wsLanes[laneId], !lane.connecting, !lane.open, !lane.closed else {
            return
        }
        self.openWsLane(laneId: laneId, lane: lane)
    }
    
    private func pumpWsLaneConnectQueue() {
        while self.wsLaneConnectInFlight < WebProxyHttpCarrier.maxConcurrentWsLaneConnects,
              !self.wsLaneConnectQueue.isEmpty,
              !self.closed {
            let laneId = self.wsLaneConnectQueue.removeFirst()
            guard let lane = self.wsLanes[laneId], !lane.connecting, !lane.open, !lane.closed else {
                continue
            }
            self.openWsLane(laneId: laneId, lane: lane)
        }
    }
    
    private func openWsLane(laneId: UInt32, lane: WsLaneState) {
        guard !self.closed, !self.sessionToken.isEmpty, !lane.connecting, !lane.open, !lane.closed else {
            return
        }
        let epoch = self.transportEpoch
        let subprotocol = "tproxy-lane-v1.\(self.sessionToken).\(laneId)"
        guard let task = self.makeWebSocketTask(subprotocol: subprotocol) else {
            self.fail(WebProxyHttpCarrierError.sessionCreationFailed)
            return
        }
        lane.connecting = true
        lane.task = task
        self.wsLaneConnectInFlight += 1
        task.resume()
        // Optimistic open after resume (same rationale as multiplex). A connect timeout
        // recovers lanes that never finish upgrading under CFNetwork pressure.
        lane.connecting = false
        lane.open = true
        self.wsLaneConnectInFlight = max(0, self.wsLaneConnectInFlight - 1)
        self.armWsLaneReceive(laneId: laneId, lane: lane, task: task, epoch: epoch)
        self.flushWsLaneUplink(laneId: laneId, lane: lane)
        self.pumpWsLaneConnectQueue()
        
        self.queue.asyncAfter(deadline: .now() + WebProxyHttpCarrier.wsLaneConnectTimeout) { [weak self] in
            guard let self else {
                return
            }
            // If the socket never delivered any traffic and receive already failed, lane is closed.
            // If still "open" but task is nil, nothing to do.
            guard epoch == self.transportEpoch, !self.closed else {
                return
            }
            guard let lane = self.wsLanes[laneId], !lane.closed else {
                return
            }
            // Soft check: if task exists but we never got a successful send and buffer is full of
            // OPEN only stuck — receive errors will close. No extra action required here beyond
            // ensuring connecting cannot stick (already cleared above).
            _ = lane
        }
    }
    
    private func armWsLaneReceive(laneId: UInt32, lane: WsLaneState, task: URLSessionWebSocketTask, epoch: UInt64) {
        guard !lane.receiveArmed, !lane.closed, !self.closed else {
            return
        }
        lane.receiveArmed = true
        self.receiveWebSocket(task, epoch: epoch) { [weak self] data in
            guard let self, !self.closed, !lane.closed, epoch == self.transportEpoch else {
                return
            }
            self.onDownlinkBatch?(data)
        } onError: { [weak self] error in
            guard let self else {
                return
            }
            guard epoch == self.transportEpoch else {
                return
            }
            lane.receiveArmed = false
            if self.closed || self.isCancellation(error) {
                return
            }
            // Established lane failure closes only that stream (PROTOCOL.md).
            if lane.open {
                self.closeWsLane(laneId: laneId, lane: lane, notifyApp: true)
            } else {
                self.fail(error)
            }
        }
    }
    
    private func flushWsLaneUplink(laneId: UInt32, lane: WsLaneState) {
        if lane.sending || !lane.open || lane.closed || self.closed {
            return
        }
        guard let task = lane.task else {
            return
        }
        if lane.pendingUplinkCount <= 0 {
            return
        }
        let remaining = lane.uplinkBuffer[(lane.uplinkBuffer.startIndex + lane.uplinkBufferOffset)...]
        let splitOffset = WebProxyHttpCarrier.frameBoundaryOffset(in: remaining, notExceeding: WebProxyHttpCarrier.maximumUplinkBatchSize)
        let batchStart = remaining.startIndex
        let batch = Data(remaining[batchStart ..< (batchStart + splitOffset)])
        lane.uplinkBufferOffset += splitOffset
        self.compactBuffer(&lane.uplinkBuffer, offset: &lane.uplinkBufferOffset)
        lane.sending = true
        task.send(.data(batch)) { [weak self] error in
            guard let self else {
                return
            }
            self.queue.async {
                lane.sending = false
                if self.closed || lane.closed {
                    return
                }
                if error != nil {
                    self.closeWsLane(laneId: laneId, lane: lane, notifyApp: true)
                    return
                }
                self.flushWsLaneUplink(laneId: laneId, lane: lane)
            }
        }
    }
    
    private func closeWsLane(laneId: UInt32, lane: WsLaneState, notifyApp: Bool) {
        guard !lane.closed else {
            return
        }
        lane.closed = true
        lane.open = false
        lane.connecting = false
        lane.receiveArmed = false
        lane.uplinkBuffer = Data()
        lane.uplinkBufferOffset = 0
        lane.task = nil
        // Avoid cancel(with:) here; the task ends when the session is invalidated or the peer closes.
        if notifyApp {
            // Synthesize CLOSE so the sidecar tears down the local MTProto socket for this stream.
            let closeFrame = WebProxyFrameCodec.encode(WebProxyFrame(type: .close, streamId: laneId, payload: Data()))
            self.onDownlinkBatch?(closeFrame)
        }
        self.pumpWsLaneConnectQueue()
    }
}
