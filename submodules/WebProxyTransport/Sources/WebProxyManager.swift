import Foundation

public struct WebProxyConfiguration: Equatable {
    public let hostname: String
    public let secret: Data
    
    public init(hostname: String, secret: Data) {
        self.hostname = hostname
        self.secret = secret
    }
}

public final class WebProxyManager {
    public static let shared = WebProxyManager()
    
    public struct LoopbackEndpoint: Equatable {
        public let host: String
        public let port: UInt16
        
        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }
    
    private let lock = NSLock()
    // Serializes start(configuration:), which blocks for up to 45s. Without this, two
    // overlapping configure() calls for a changing configuration would both pass the
    // fast-path check (self.configuration is only updated once a start finishes) and
    // race to bootstrap their own sidecar in parallel.
    private let startLock = NSLock()
    private var sidecar: WebProxySidecar?
    private var configuration: WebProxyConfiguration?
    private var endpoint: LoopbackEndpoint?
    
    private init() {
    }
    
    public var activeLoopbackEndpoint: LoopbackEndpoint? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.endpoint
    }
    
    public var activeConfiguration: WebProxyConfiguration? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.configuration
    }
    
    /// Starts or reuses the sidecar for the given WEB proxy. Returns false on failure (fail-closed).
    @discardableResult
    public func configure(activeWebProxy server: WebProxyConfiguration?) -> Bool {
        self.lock.lock()
        if server == self.configuration, self.endpoint != nil {
            self.lock.unlock()
            return true
        }
        self.lock.unlock()

        if let server = server {
            self.startLock.lock()
            defer { self.startLock.unlock() }

            // Another call may have already started this exact configuration while we
            // were waiting for startLock.
            self.lock.lock()
            if server == self.configuration, self.endpoint != nil {
                self.lock.unlock()
                return true
            }
            self.lock.unlock()

            return self.start(configuration: server)
        } else {
            self.startLock.lock()
            defer { self.startLock.unlock() }
            self.stop()
            return true
        }
    }

    public func stop() {
        self.lock.lock()
        self.sidecar?.stop()
        self.sidecar = nil
        self.configuration = nil
        self.endpoint = nil
        self.lock.unlock()
    }
    
    private func start(configuration: WebProxyConfiguration) -> Bool {
        guard let bridgeCapability = WebProxyBridgeCapability.derive(hostname: configuration.hostname, secret: configuration.secret) else {
            self.stop()
            return false
        }
        
        let sidecar = WebProxySidecar()
        let semaphore = DispatchSemaphore(value: 0)
        var startResult: Result<WebProxySidecar.Endpoint, Error>?
        
        sidecar.start(hostname: configuration.hostname, secret: configuration.secret, bridgeCapability: bridgeCapability) { result in
            startResult = result
            semaphore.signal()
        }
        
        let waitResult = semaphore.wait(timeout: .now() + 45.0)
        if waitResult == .timedOut {
            sidecar.stop()
            self.stop()
            return false
        }
        
        guard case let .success(endpoint) = startResult else {
            sidecar.stop()
            self.stop()
            return false
        }
        
        self.lock.lock()
        self.sidecar?.stop()
        self.sidecar = sidecar
        self.configuration = configuration
        self.endpoint = LoopbackEndpoint(host: endpoint.host, port: endpoint.port)
        sidecar.setFailureHandler { [weak self] in
            self?.stop()
        }
        self.lock.unlock()
        return true
    }
}
