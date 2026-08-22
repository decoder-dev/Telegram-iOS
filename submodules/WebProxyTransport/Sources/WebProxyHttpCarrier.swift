import Foundation

public enum WebProxyHttpCarrierError: Error {
    case invalidHostname
    case bridgeRequestFailed
    case bootstrapTokenMissing
    case sessionCreationFailed
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
    
    private var uplinkQueue: [Data] = []
    private var uplinkRunning = false
    
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
            do {
                let bootstrap = try self.fetchBootstrapToken(bridgeCapability: bridgeCapability)
                try self.createSession(bootstrapToken: bootstrap)
                self.pollDownlink()
                completion(.success(()))
            } catch {
                completion(.failure(error))
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
            self.uplinkQueue.append(batch)
            self.runUplinkIfNeeded()
        }
    }
    
    private func fetchBootstrapToken(bridgeCapability: String) throws -> String {
        var components = URLComponents(url: self.origin, resolvingAgainstBaseURL: false)!
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "bridge", value: bridgeCapability)]
        guard let url = components.url else {
            throw WebProxyHttpCarrierError.bridgeRequestFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30.0
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        let task = self.session.dataTask(with: request) { data, response, error in
            if let error = error {
                responseError = error
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                responseError = WebProxyHttpCarrierError.bridgeRequestFailed
            } else {
                responseData = data
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        if let responseError = responseError {
            throw responseError
        }
        guard let html = responseData.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw WebProxyHttpCarrierError.bootstrapTokenMissing
        }
        if let token = Self.parseBootstrapToken(from: html) {
            return token
        }
        throw WebProxyHttpCarrierError.bootstrapTokenMissing
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
    
    private func createSession(bootstrapToken: String) throws {
        guard let url = URL(string: "/api/v1/session", relativeTo: self.origin) else {
            throw WebProxyHttpCarrierError.sessionCreationFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = WebProxyFrameCodec.encode(.hello())
        request.setValue("Bearer \(bootstrapToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 90.0
        
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var response: HTTPURLResponse?
        var responseError: Error?
        let task = self.session.dataTask(with: request) { data, urlResponse, error in
            responseError = error
            responseData = data
            response = urlResponse as? HTTPURLResponse
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        if let responseError = responseError {
            throw responseError
        }
        guard let response = response, response.statusCode == 200 else {
            throw WebProxyHttpCarrierError.sessionCreationFailed
        }
        guard let token = response.value(forHTTPHeaderField: "X-Session-Token"), !token.isEmpty else {
            throw WebProxyHttpCarrierError.sessionCreationFailed
        }
        let carrierMode = response.value(forHTTPHeaderField: "X-Carrier-Mode") ?? "https"
        if carrierMode != "https" {
            throw WebProxyHttpCarrierError.sessionCreationFailed
        }
        self.sessionToken = token
        self.downCursor = response.value(forHTTPHeaderField: "X-Down-Cursor") ?? "0"
        if let body = responseData, !body.isEmpty {
            _ = try WebProxyFrameCodec.decodeBatch(body)
        }
    }
    
    private func runUplinkIfNeeded() {
        if self.uplinkRunning || self.closed || self.sessionToken.isEmpty || self.uplinkQueue.isEmpty {
            return
        }
        self.uplinkRunning = true
        let batch = self.uplinkQueue.removeFirst()
        let sequence = self.upSequence
        self.upSequence += 1
        
        guard let url = URL(string: "/api/v1/up", relativeTo: self.origin) else {
            self.fail(WebProxyHttpCarrierError.uplinkRejected)
            return
        }
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
                    if !self.uplinkQueue.isEmpty {
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
                    self.pollDownlink()
                    return
                }
                guard http.statusCode == 200,
                      let nextCursor = http.value(forHTTPHeaderField: "X-Down-Cursor"),
                      let data = data, !data.isEmpty else {
                    self.fail(WebProxyHttpCarrierError.downlinkRejected)
                    return
                }
                self.downCursor = nextCursor
                self.onDownlinkBatch?(data)
                self.pollDownlink()
            }
        }
        task.resume()
    }
    
    private func fail(_ error: Error) {
        if self.closed {
            return
        }
        self.closed = true
        self.onFailure?(error)
    }
}
