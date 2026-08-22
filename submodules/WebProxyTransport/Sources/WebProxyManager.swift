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
    
    /// Called on the main queue when the sidecar endpoint becomes ready, fails to start, or stops at runtime.
    public var onSidecarEvent: (() -> Void)?
    
    private let lock = NSLock()
    private let startLock = NSLock()
    private var sidecar: WebProxySidecar?
    private var configuration: WebProxyConfiguration?
    private var endpoint: LoopbackEndpoint?
    private var startingConfiguration: WebProxyConfiguration?
    private var startGeneration: UInt64 = 0
    
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
    
    public func isReady(for configuration: WebProxyConfiguration) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.configuration == configuration && self.endpoint != nil
    }
    
    /// Starts or reuses the sidecar for the given WEB proxy without blocking the caller.
    /// Returns true when the loopback endpoint is already available for this configuration.
    @discardableResult
    public func configure(activeWebProxy server: WebProxyConfiguration?) -> Bool {
        if server == nil {
            self.startLock.lock()
            defer { self.startLock.unlock() }
            self.startGeneration &+= 1
            self.startingConfiguration = nil
            self.stopLocked()
            return true
        }
        
        self.lock.lock()
        if server == self.configuration, self.endpoint != nil {
            self.lock.unlock()
            return true
        }
        self.lock.unlock()
        
        self.scheduleStart(configuration: server)
        return self.isReady(for: server)
    }
    
    private func scheduleStart(configuration: WebProxyConfiguration) {
        self.startLock.lock()
        self.startGeneration &+= 1
        let generation = self.startGeneration
        self.startingConfiguration = configuration
        self.startLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.startAsync(configuration: configuration, generation: generation)
        }
    }
    
    private func startAsync(configuration: WebProxyConfiguration, generation: UInt64) {
        guard let bridgeCapability = WebProxyBridgeCapability.derive(hostname: configuration.hostname, secret: configuration.secret) else {
            self.finishStart(generation: generation, configuration: configuration, sidecar: nil, result: .failure(WebProxyHttpCarrierError.sessionCreationFailed))
            return
        }
        
        let sidecar = WebProxySidecar()
        sidecar.start(hostname: configuration.hostname, secret: configuration.secret, bridgeCapability: bridgeCapability) { [weak self] result in
            self?.finishStart(generation: generation, configuration: configuration, sidecar: sidecar, result: result)
        }
    }
    
    private func finishStart(generation: UInt64, configuration: WebProxyConfiguration, sidecar: WebProxySidecar?, result: Result<WebProxySidecar.Endpoint, Error>) {
        self.startLock.lock()
        let stillCurrent = generation == self.startGeneration && self.startingConfiguration == configuration
        self.startLock.unlock()
        
        guard stillCurrent else {
            sidecar?.stop()
            return
        }
        
        switch result {
        case let .success(endpoint):
            self.lock.lock()
            self.sidecar?.stop()
            self.sidecar = sidecar
            self.configuration = configuration
            self.endpoint = LoopbackEndpoint(host: endpoint.host, port: endpoint.port)
            sidecar?.setFailureHandler { [weak self] in
                self?.handleSidecarFailure()
            }
            self.lock.unlock()
            
            self.startLock.lock()
            if self.startingConfiguration == configuration {
                self.startingConfiguration = nil
            }
            self.startLock.unlock()
            
            self.notifySidecarEvent()
        case .failure:
            sidecar?.stop()
            self.startLock.lock()
            if generation == self.startGeneration {
                self.startingConfiguration = nil
            }
            self.startLock.unlock()
            
            self.lock.lock()
            if self.configuration == configuration {
                self.stopLocked()
            }
            self.lock.unlock()
            
            self.notifySidecarEvent()
        }
    }
    
    private func handleSidecarFailure() {
        self.startLock.lock()
        self.startGeneration &+= 1
        self.startingConfiguration = nil
        self.startLock.unlock()
        
        self.lock.lock()
        self.stopLocked()
        self.lock.unlock()
        
        self.notifySidecarEvent()
    }
    
    private func stopLocked() {
        self.sidecar?.stop()
        self.sidecar = nil
        self.configuration = nil
        self.endpoint = nil
    }
    
    private func notifySidecarEvent() {
        let handler = self.onSidecarEvent
        DispatchQueue.main.async {
            handler?()
        }
    }
}
