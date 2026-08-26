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
}

/// Native HTTPS carrier for tproxy-server (`https` mode): no WKWebView required.
final class WebProxyHttpCarrier {
    private let hostname: String
    private let origin: URL
    private let session: URLSession
    private let queue: DispatchQueue
    
    private var sessionToken: String = ""
    private var downCursor: String = "0"
    private var upSequence: Int = 1
    private var closed = false
    /// The relay must open with `WELCOME` before any stream traffic. Until it does, an ordinary
    /// 200 from a site that is not a relay at all is indistinguishable from a working carrier —
    /// which is how a mistyped hostname used to sit in `connecting` forever.
    private var awaitingWelcome = true
    
    /// One buffer rather than a queue of batches: consecutive `sendFrames` calls are concatenated
    /// frame streams, so while a POST is in flight the next one can carry everything that piled up
    /// behind it. Without this a 64 KiB socket read became its own round trip, which is what made
    /// the carrier RTT-bound on uploads.
    private var uplinkBuffer = Data()
    /// Read cursor into `uplinkBuffer`. Consuming a batch used to re-base the buffer with
    /// `dropFirst`, which copies the whole remainder on every turn — quadratic in the buffer size,
    /// and the buffer is largest exactly when the link is slow. Draining 64 MiB in 2 MiB batches
    /// that way moves about a gigabyte through memcpy; with a cursor it moves the batches only.
    private var uplinkBufferOffset = 0
    private var uplinkRunning = false
    
    /// Matches the hosted bridge's 2 MiB batch. Anything above it waits for the next POST.
    private static let maximumUplinkBatchSize = 2 * 1024 * 1024
    /// Hard ceiling on data queued for the carrier. Past this the carrier fails instead of growing
    /// without bound: `AbstractSocket`-style writes have no backpressure to push back with.
    private static let maximumUplinkBufferSize = 64 * 1024 * 1024
    /// Most already-sent bytes the buffer may keep in front of the read cursor before compacting.
    private static let maximumRetainedUplinkPrefix = 8 * 1024 * 1024
    
    /// Downlink pacing. The relay is expected to hold `/api/v1/down` open until it has something to
    /// send, but nothing in the protocol guarantees it, and a relay — or a CDN in front of one —
    /// that answers 204 promptly turns the poll into an unbounded loop of HTTPS requests: hundreds
    /// per second, each waking the radio, with no user traffic at all. So an *empty* response that
    /// comes back faster than a long poll plausibly could is paced, with exponential backoff and
    /// jitter. A response that took a while, or one that carried data, re-polls immediately — a
    /// correctly long-polling relay is never slowed down by this.
    ///
    /// The ceiling is deliberately low. Against a relay that really does answer 204 immediately the
    /// client cannot have both low latency and a quiet radio, and 5s caps the added latency at
    /// something a user will not file a bug about while still turning a 100+ requests/second loop
    /// into one request every five seconds.
    private static let minimumDownlinkInterval: Double = 0.5
    private static let maximumDownlinkInterval: Double = 5.0
    private var fastEmptyDownlinkStreak = 0
    
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
            // Chained rather than blocking: both legs used to `DispatchSemaphore.wait()` on this
            // queue, parking it for up to 30s and 90s respectively while nothing else could run on it.
            self.fetchBootstrapToken(bridgeCapability: bridgeCapability) { result in
                switch result {
                case let .success(bootstrap):
                    self.createSession(bootstrapToken: bootstrap) { result in
                        switch result {
                        case .success:
                            self.pollDownlink()
                            completion(.success(()))
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
        self.queue.async {
            guard !self.closed else {
                return
            }
            self.closed = true
            let token = self.sessionToken
            self.sessionToken = ""
            if !token.isEmpty, let url = URL(string: "/api/v1/session", relativeTo: self.origin) {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                let task = self.session.dataTask(with: request)
                task.resume()
            }
        }
    }
    
    func sendFrames(_ batch: Data) {
        self.queue.async {
            guard !self.closed, !self.sessionToken.isEmpty else {
                return
            }
            if self.pendingUplinkCount + batch.count > WebProxyHttpCarrier.maximumUplinkBufferSize {
                self.fail(WebProxyHttpCarrierError.uplinkRejected)
                return
            }
            self.uplinkBuffer.append(batch)
            self.runUplinkIfNeeded()
        }
    }
    
    private var pendingUplinkCount: Int {
        return self.uplinkBuffer.count - self.uplinkBufferOffset
    }
    
    /// Drops the consumed prefix once it is at least half the buffer, which keeps the amortised
    /// copy cost linear in the bytes sent rather than quadratic in the buffer size.
    private func compactUplinkBufferIfNeeded() {
        if self.uplinkBufferOffset == 0 {
            return
        }
        if self.uplinkBufferOffset >= self.uplinkBuffer.count {
            self.uplinkBuffer = Data()
            self.uplinkBufferOffset = 0
            return
        }
        // Half-consumed keeps the amortised copy cost linear; the absolute ceiling keeps the
        // consumed prefix from holding a second copy of a large buffer - without it a 64 MiB
        // backlog would sit on ~128 MiB of memory.
        if self.uplinkBufferOffset * 2 >= self.uplinkBuffer.count || self.uplinkBufferOffset >= WebProxyHttpCarrier.maximumRetainedUplinkPrefix {
            self.uplinkBuffer = Data(self.uplinkBuffer[(self.uplinkBuffer.startIndex + self.uplinkBufferOffset)...])
            self.uplinkBufferOffset = 0
        }
    }
    
    private func fetchBootstrapToken(bridgeCapability: String, completion: @escaping (Result<String, Error>) -> Void) {
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
                if let error = error {
                    completion(.failure(error))
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
                if let error = error {
                    completion(.failure(error))
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
                // `X-Carrier-Mode` is deliberately not gated on. Refusing every value but `https`
                // assumed the header names the wire format, and nothing here is written down: this
                // client always dials `https://<host>` regardless of it, and never varies a single
                // byte of the protocol by it — the value was only ever read to be compared. If the
                // relay instead reports how it is deployed (own TLS, plain HTTP behind a terminator,
                // a particular image), then every deployment but one was refused for a label while
                // speaking a protocol this client understands perfectly.
                //
                // Compatibility is settled by the handshake instead, which is both stronger and not
                // a guess: the relay must open with a decodable `WELCOME` frame on stream zero,
                // checked here when the session POST carries a body and on the first downlink batch
                // when it does not. That catches a relay whose wire format we would misread — and
                // also one that claims `https` and is not, which a string comparison never could.
                //
                // It is still worth recording: when a relay does turn out to be incompatible, the
                // mode it named is the first thing anyone will want to know.
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
    
    private func runUplinkIfNeeded() {
        if self.uplinkRunning || self.closed || self.sessionToken.isEmpty || self.pendingUplinkCount <= 0 {
            return
        }
        // Resolved before anything is committed: taking the batch first and failing here left
        // `uplinkRunning` latched true with the batch already consumed off the buffer.
        guard let url = URL(string: "/api/v1/up", relativeTo: self.origin) else {
            self.fail(WebProxyHttpCarrierError.uplinkRejected)
            return
        }
        self.uplinkRunning = true
        // Split on a frame boundary: a POST body must contain whole frames, so the cut point is the
        // last frame header that ends at or before the batch limit.
        let remaining = self.uplinkBuffer[(self.uplinkBuffer.startIndex + self.uplinkBufferOffset)...]
        let splitOffset = WebProxyHttpCarrier.frameBoundaryOffset(in: remaining, notExceeding: WebProxyHttpCarrier.maximumUplinkBatchSize)
        let batchStart = remaining.startIndex
        let batch = Data(remaining[batchStart ..< (batchStart + splitOffset)])
        self.uplinkBufferOffset += splitOffset
        self.compactUplinkBufferIfNeeded()
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
                        self.runUplinkIfNeeded()
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
    
    /// Re-polls at once when the relay held the request or returned data, and paces the poll when an
    /// empty response comes back immediately — see `minimumDownlinkInterval`.
    private func scheduleDownlinkPoll(requestStartedAt: Double, wasEmpty: Bool) {
        if self.closed {
            return
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - requestStartedAt
        if !wasEmpty || elapsed >= WebProxyHttpCarrier.minimumDownlinkInterval {
            self.fastEmptyDownlinkStreak = 0
            self.pollDownlink()
            return
        }
        self.fastEmptyDownlinkStreak += 1
        let step = min(self.fastEmptyDownlinkStreak - 1, 8)
        let backoff = min(WebProxyHttpCarrier.maximumDownlinkInterval, WebProxyHttpCarrier.minimumDownlinkInterval * pow(2.0, Double(step)))
        // Jitter so several accounts sharing one relay do not line their polls up.
        let delay = backoff * Double.random(in: 0.85 ... 1.15)
        self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollDownlink()
        }
    }
    
    private func pollDownlink() {
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
                    self.scheduleDownlinkPoll(requestStartedAt: startedAt, wasEmpty: true)
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
                self.scheduleDownlinkPoll(requestStartedAt: startedAt, wasEmpty: false)
            }
        }
        task.resume()
    }
    
    private func fail(_ error: Error) {
        if self.closed {
            return
        }
        WebProxyLog.log("carrier failed against \(self.hostname): \(error)")
        self.closed = true
        self.onFailure?(error)
    }
}
