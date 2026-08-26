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
    
    /// Upper bound on a sidecar bootstrap (30s bridge request + 90s session creation), after which
    /// an in-flight start is no longer treated as live and a fresh one may supersede it.
    private static let startTimeout: Double = 180.0
    /// Backoff bounds after a failed bootstrap. A failure notifies every account, and each one
    /// re-applies its proxy settings, which lands straight back in `scheduleStart` — without a
    /// cooldown that is an unbounded retry loop, and a hot one when `derive` fails synchronously
    /// (invalid hostname or empty secret), spinning global-queue → main-queue at full speed.
    private static let minimumRetryInterval: Double = 5.0
    private static let maximumRetryInterval: Double = 60.0
    /// A sidecar that dies sooner than this after becoming ready feeds the same cooldown as a
    /// failed bootstrap. One that ran longer starts the count again, so a carrier that worked for
    /// an hour before a network change still reconnects promptly.
    private static let minimumHealthyUptime: Double = 30.0

    private let lock = NSLock()
    private let startLock = NSLock()
    private var sidecar: WebProxySidecar?
    private var configuration: WebProxyConfiguration?
    private var endpoint: LoopbackEndpoint?
    private var startingConfiguration: WebProxyConfiguration?
    private var startingSince: Double = 0.0
    private var startGeneration: UInt64 = 0
    private var lastFailedConfiguration: WebProxyConfiguration?
    private var lastFailureTime: Double = 0.0
    private var consecutiveFailureCount: Int = 0
    /// A configuration whose relay answered with a carrier mode this client cannot speak. The
    /// backoff above is for failures that might come good — a timeout, a 502, a network change —
    /// and it tops out at a minute, so on its own it would re-run the whole bootstrap against such a
    /// relay every minute for as long as the proxy stays selected: two HTTPS requests and a TLS
    /// handshake, forever, for an answer that cannot change. This parks it instead. Turning the
    /// proxy off clears it, which is the recovery path a user reaches for anyway.
    private var unsupportedConfiguration: WebProxyConfiguration?
    private var sidecarReadySince: Double = 0.0
    
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
            self.startGeneration &+= 1
            self.startingConfiguration = nil
            // Turning the proxy off is an explicit user action — don't make re-enabling the same
            // server wait out a cooldown left over from an earlier failure, or a park left over from
            // a relay that has since been reconfigured.
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
            self.unsupportedConfiguration = nil
            self.startLock.unlock()
            
            self.lock.lock()
            self.stopLocked()
            self.lock.unlock()
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
        if self.startingConfiguration == configuration, CFAbsoluteTimeGetCurrent() - self.startingSince < WebProxyManager.startTimeout {
            // Every account resolves the same shared proxy settings, so with several accounts
            // this is called once per Network for one and the same server. Re-scheduling would
            // supersede the in-flight start, tearing down a sidecar that is midway through its
            // HTTPS bootstrap and restarting the wait from zero for all of them.
            self.startLock.unlock()
            return
        }
        if self.unsupportedConfiguration == configuration {
            // This relay speaks a carrier mode we do not implement. Nothing about retrying changes
            // that, so it is left alone until the proxy is switched off or a different one is set.
            self.startLock.unlock()
            return
        }
        if self.lastFailedConfiguration == configuration, self.consecutiveFailureCount > 0 {
            let backoff = min(
                WebProxyManager.maximumRetryInterval,
                WebProxyManager.minimumRetryInterval * pow(2.0, Double(self.consecutiveFailureCount - 1))
            )
            if CFAbsoluteTimeGetCurrent() - self.lastFailureTime < backoff {
                // Still cooling down after a failed bootstrap of this very configuration. The next
                // settings re-apply (foreground, network change, edit) will try again.
                self.startLock.unlock()
                return
            }
        }
        self.startGeneration &+= 1
        let generation = self.startGeneration
        self.startingConfiguration = configuration
        self.startingSince = CFAbsoluteTimeGetCurrent()
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
            self.sidecarReadySince = CFAbsoluteTimeGetCurrent()
            sidecar?.setFailureHandler { [weak self] in
                self?.handleSidecarFailure()
            }
            self.lock.unlock()
            
            self.startLock.lock()
            if self.startingConfiguration == configuration {
                self.startingConfiguration = nil
            }
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
            self.unsupportedConfiguration = nil
            self.startLock.unlock()

            self.notifySidecarEvent()
        case let .failure(error):
            sidecar?.stop()
            self.startLock.lock()
            if generation == self.startGeneration {
                self.startingConfiguration = nil
            }
            if let carrierError = error as? WebProxyHttpCarrierError, case .unsupportedCarrierMode = carrierError {
                self.unsupportedConfiguration = configuration
            }
            if self.lastFailedConfiguration == configuration {
                self.consecutiveFailureCount += 1
            } else {
                self.lastFailedConfiguration = configuration
                self.consecutiveFailureCount = 1
            }
            self.lastFailureTime = CFAbsoluteTimeGetCurrent()
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
        self.lock.lock()
        let failedConfiguration = self.configuration
        let readySince = self.sidecarReadySince
        self.lock.unlock()
        
        self.startLock.lock()
        self.startGeneration &+= 1
        self.startingConfiguration = nil
        if let failedConfiguration = failedConfiguration {
            // The cooldown below used to cover bootstrap failures only. A carrier that bootstraps
            // fine and then dies — a relay that sends `BYE`, a mismatched `X-Up-Ack`, a dropped
            // session — landed here instead, which records nothing: the event fires, every account
            // re-applies its settings, that lands straight back in `scheduleStart`, and with no
            // failure recorded it starts a fresh bootstrap at once. Against a relay that accepts a
            // session and then drops it that is an unthrottled reconnect loop, two HTTPS requests
            // and a TLS handshake per turn.
            let wasHealthy = readySince > 0.0 && CFAbsoluteTimeGetCurrent() - readySince >= WebProxyManager.minimumHealthyUptime
            if self.lastFailedConfiguration == failedConfiguration, !wasHealthy {
                self.consecutiveFailureCount += 1
            } else {
                self.lastFailedConfiguration = failedConfiguration
                self.consecutiveFailureCount = 1
            }
            self.lastFailureTime = CFAbsoluteTimeGetCurrent()
        }
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
        self.sidecarReadySince = 0.0
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
