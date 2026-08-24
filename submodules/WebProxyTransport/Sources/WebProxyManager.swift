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
    
    public typealias SidecarEventToken = UInt64
    
    private let lock = NSLock()
    private let startLock = NSLock()
    private var sidecar: WebProxySidecar?
    private var configuration: WebProxyConfiguration?
    private var endpoint: LoopbackEndpoint?
    private var startingConfiguration: WebProxyConfiguration?
    private var startGeneration: UInt64 = 0
    
    private var nextSidecarEventToken: SidecarEventToken = 0
    private var sidecarEventHandlers: [SidecarEventToken: () -> Void] = [:]
    
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
    
    /// Registers a handler invoked on the main queue when the sidecar becomes ready, fails, or stops.
    /// Multi-account: every Network must register — a single overwritten callback left other accounts stuck on the fail-closed loopback.
    @discardableResult
    public func addSidecarEventHandler(_ handler: @escaping () -> Void) -> SidecarEventToken {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.nextSidecarEventToken &+= 1
        let token = self.nextSidecarEventToken
        self.sidecarEventHandlers[token] = handler
        return token
    }
    
    public func removeSidecarEventHandler(_ token: SidecarEventToken) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.sidecarEventHandlers.removeValue(forKey: token)
    }
    
    /// Starts or reuses the sidecar for the given WEB proxy without blocking the caller.
    /// Returns true when the loopback endpoint is already available for this configuration.
    @discardableResult
    public func configure(activeWebProxy server: WebProxyConfiguration?) -> Bool {
        guard let server else {
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
        self.lock.lock()
        let handlers = Array(self.sidecarEventHandlers.values)
        self.lock.unlock()
        DispatchQueue.main.async {
            for handler in handlers {
                handler()
            }
        }
    }
}
