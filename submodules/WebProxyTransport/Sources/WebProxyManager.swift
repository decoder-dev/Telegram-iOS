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
    /// Retained across a brief restart so ProxySettings does not fall through to 127.0.0.1:1
    /// (unreachable) while the new sidecar is still bootstrapping.
    private var lastGoodEndpoint: LoopbackEndpoint?
    private var startingConfiguration: WebProxyConfiguration?
    private var startingSince: Double = 0.0
    private var startGeneration: UInt64 = 0
    private var lastFailedConfiguration: WebProxyConfiguration?
    private var lastFailureTime: Double = 0.0
    private var consecutiveFailureCount: Int = 0
    private var sidecarReadySince: Double = 0.0

    /// Debounce foreground restarts so rapid active/resign cycles do not stack tear-downs.
    private var lastBecomeActiveRestart: Double = 0.0
    private static let becomeActiveRestartMinInterval: Double = 3.0
    /// Set from `applicationDidEnterBackground`. A carrier session is foreground-only: iOS may
    /// suspend its URLSession/WebSocket work at any point after this transition.
    private var enteredBackgroundAt: Double = 0.0

    /// The configuration the app currently wants running, as opposed to the one that happens to
    /// be up. A retry armed by the cooldown must not resurrect a proxy the user has since turned
    /// off, and `configuration` is nil from the moment a carrier dies, so it cannot answer that.
    private var desiredConfiguration: WebProxyConfiguration?
    /// Whether a cooldown retry is already armed, so a burst of re-applies arms only one.
    private var isRetryScheduled: Bool = false
    
    private var nextSidecarEventToken: SidecarEventToken = 0
    private var sidecarEventHandlers: [SidecarEventToken: () -> Void] = [:]
    
    private init() {
    }
    
    public var activeLoopbackEndpoint: LoopbackEndpoint? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.endpoint ?? self.lastGoodEndpoint
    }
    
    public var activeConfiguration: WebProxyConfiguration? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.configuration
    }
    
    public func isReady(for configuration: WebProxyConfiguration) -> Bool {
        self.lock.lock()
        let live = self.configuration == configuration && self.endpoint != nil
        let hasFallback = self.lastGoodEndpoint != nil
        self.lock.unlock()
        if live {
            return true
        }
        // Sequential restart / cold bootstrap briefly clears `endpoint`. Keep lastGood visible
        // so ProxySettings does not publish 127.0.0.1:1 (236 refused connects in one session).
        self.startLock.lock()
        let starting = self.startingConfiguration == configuration
        self.startLock.unlock()
        return starting && hasFallback
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
            self.desiredConfiguration = nil
            self.startGeneration &+= 1
            self.startingConfiguration = nil
            // Turning the proxy off is an explicit user action — don't make re-enabling the same
            // server wait out a cooldown left over from an earlier failure.
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
            self.startLock.unlock()
            
            self.lock.lock()
            self.stopLocked()
            self.lastGoodEndpoint = nil
            self.lock.unlock()
            return true
        }
        
        self.startLock.lock()
        self.desiredConfiguration = server
        self.startLock.unlock()
        
        self.lock.lock()
        if server == self.configuration, self.endpoint != nil {
            self.lock.unlock()
            return true
        }
        self.lock.unlock()
        
        self.scheduleStart(configuration: server)
        return self.isReady(for: server)
    }
    
    /// Call from `applicationWillEnterForeground` / `applicationDidBecomeActive`.
    ///
    /// The WEB carrier is foreground-only. After entering background, iOS can suspend its
    /// URLSession/WebSocket work without delivering a useful failure callback. The relay contract
    /// also closes WebSocket sessions rather than resuming their streams. Recreate the complete
    /// sidecar on return instead of reusing its listener or trying to revive its old session.
    /// Call from `applicationDidEnterBackground` so resume can tell a real sleep from a flicker.
    public func applicationDidEnterBackground() {
        self.startLock.lock()
        self.enteredBackgroundAt = CFAbsoluteTimeGetCurrent()
        self.startLock.unlock()
    }
    
    public func applicationDidBecomeActive() {
        let now = CFAbsoluteTimeGetCurrent()
        self.startLock.lock()
        if now - self.lastBecomeActiveRestart < WebProxyManager.becomeActiveRestartMinInterval {
            self.startLock.unlock()
            return
        }
        let backgroundedAt = self.enteredBackgroundAt
        let starting = self.startingConfiguration
        // `configuration` is cleared as soon as a failed sidecar is stopped, but the desired
        // server still represents the enabled proxy. Keep it as a recovery target so a stale
        // lastGoodEndpoint cannot leave all Networks waiting on a dead listener indefinitely.
        let desired = self.desiredConfiguration
        self.startLock.unlock()
        
        self.lock.lock()
        let active = self.configuration
        let hasEndpoint = self.endpoint != nil
        self.lock.unlock()
        
        let target = active ?? starting ?? desired
        guard let target = target else {
            return
        }

        // Consume the background stamp only once there is a concrete configuration to restart.
        // Otherwise a transient empty state between stopping and starting would discard the
        // foreground recovery event.
        self.startLock.lock()
        self.enteredBackgroundAt = 0
        self.lastBecomeActiveRestart = now
        self.lastFailedConfiguration = nil
        self.consecutiveFailureCount = 0
        self.startLock.unlock()
        
        // Missing endpoint → always try to start (cold path / previous failure).
        if !hasEndpoint {
            self.scheduleStart(configuration: target)
            return
        }
        
        if backgroundedAt > 0 {
            self.sequentialRestart(configuration: target)
        }
    }
    
    /// Stop the current sidecar, then schedule a fresh one. Used when there is no live endpoint
    /// or in-place transport reconnect failed. Not overlapping — only one listener at a time.
    private func sequentialRestart(configuration: WebProxyConfiguration) {
        // Invalidate a previous asynchronous start before replacing the sidecar. Do not mark
        // this replacement as started here: scheduleStart treats that marker as an existing
        // bootstrap and would return without creating the new carrier.
        self.startLock.lock()
        self.startGeneration &+= 1
        self.startingConfiguration = nil
        self.startingSince = 0.0
        self.startLock.unlock()
        
        self.lock.lock()
        if let previous = self.sidecar {
            previous.setFailureHandler { }
            self.sidecar = nil
            self.configuration = nil
            self.endpoint = nil
            self.sidecarReadySince = 0.0
            DispatchQueue.global(qos: .utility).async {
                previous.stop()
            }
        } else {
            self.configuration = nil
            self.endpoint = nil
            self.sidecarReadySince = 0.0
        }
        self.lock.unlock()
        
        self.scheduleStart(configuration: configuration)
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
        if self.lastFailedConfiguration == configuration, self.consecutiveFailureCount > 0 {
            let backoff = self.currentBackoffLocked()
            let elapsed = CFAbsoluteTimeGetCurrent() - self.lastFailureTime
            if elapsed < backoff {
                // Nothing here used to arm a retry — the caller was simply told to come back
                // later, and the only things that come back later are a foreground, a network
                // change or a settings edit. So a carrier that died mid-session stayed dead until
                // one of those happened: in one day's log, four deaths out of five went unretried
                // for between forty minutes and twelve hours, with the app on cellular the whole
                // time. The cooldown is still honoured; it just brings itself back now.
                self.scheduleRetryLocked(configuration: configuration, after: backoff - elapsed)
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
    
    /// The cooldown currently owed for `lastFailedConfiguration`. Must be called with
    /// `startLock` held.
    private func currentBackoffLocked() -> Double {
        return min(
            WebProxyManager.maximumRetryInterval,
            WebProxyManager.minimumRetryInterval * pow(2.0, Double(max(1, self.consecutiveFailureCount) - 1))
        )
    }

    /// Bring the cooldown back to `scheduleStart` when it expires, instead of waiting for an
    /// outside event that may never come. Must be called with `startLock` held.
    ///
    /// The retry checks two things before it acts, because both can change while it waits: that
    /// this configuration is still the one the app wants — the user may have turned the proxy off
    /// or switched servers — and that a carrier is not already up for it.
    private func scheduleRetryLocked(configuration: WebProxyConfiguration, after delay: Double) {
        if self.isRetryScheduled {
            return
        }
        self.isRetryScheduled = true

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.1, delay)) { [weak self] in
            guard let self = self else {
                return
            }

            self.startLock.lock()
            self.isRetryScheduled = false
            let isStillWanted = self.desiredConfiguration == configuration
            self.startLock.unlock()

            guard isStillWanted else {
                return
            }

            self.lock.lock()
            let isAlreadyRunning = self.configuration == configuration && self.endpoint != nil
            self.lock.unlock()

            guard !isAlreadyRunning else {
                return
            }

            self.scheduleStart(configuration: configuration)
        }
    }

    private func startAsync(configuration: WebProxyConfiguration, generation: UInt64) {
        guard let bridgeCapability = WebProxyBridgeCapability.derive(hostname: configuration.hostname, secret: configuration.secret) else {
            // Refused before a single byte left the device: the hostname is not a DNS name, or the
            // secret is not one of the two forms a WEB relay accepts. Worth naming, because it is
            // indistinguishable from a dead relay in every later signal.
            WebProxyLog.log("bootstrap refused for \(configuration.hostname): hostname or secret unusable (secret \(configuration.secret.count) bytes)")
            self.finishStart(generation: generation, configuration: configuration, sidecar: nil, result: .failure(WebProxyHttpCarrierError.sessionCreationFailed))
            return
        }
        WebProxyLog.log("bootstrap starting for \(configuration.hostname)")
        
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
            WebProxyLog.log("carrier ready for \(configuration.hostname) on \(endpoint.host):\(endpoint.port)")
            self.lock.lock()
            let previous = self.sidecar
            previous?.setFailureHandler { }
            self.sidecar = sidecar
            self.configuration = configuration
            self.endpoint = LoopbackEndpoint(host: endpoint.host, port: endpoint.port)
            self.lastGoodEndpoint = self.endpoint
            self.sidecarReadySince = CFAbsoluteTimeGetCurrent()
            sidecar?.setFailureHandler { [weak self, weak sidecar] in
                guard let self, let sidecar else {
                    return
                }
                self.lock.lock()
                let isCurrent = self.sidecar === sidecar
                self.lock.unlock()
                guard isCurrent else {
                    return
                }
                self.handleSidecarFailure()
            }
            self.lock.unlock()
            
            self.startLock.lock()
            if self.startingConfiguration == configuration {
                self.startingConfiguration = nil
            }
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
            self.startLock.unlock()

            self.notifySidecarEvent()

            if let previous = previous {
                DispatchQueue.global(qos: .utility).async {
                    previous.stop()
                }
            }
            // case .failure:
        case let .failure(error):
            // The reason a WEB proxy failed used to end here: the branch did not even bind the
            // error, so "my proxy does not connect" had no answer short of reading the source.
            WebProxyLog.log("bootstrap failed for \(configuration.hostname): \(error)")

            sidecar?.stop()
            self.startLock.lock()
            if generation == self.startGeneration {
                self.startingConfiguration = nil
            }
            if self.lastFailedConfiguration == configuration {
                self.consecutiveFailureCount += 1
            } else {
                self.lastFailedConfiguration = configuration
                self.consecutiveFailureCount = 1
            }
            self.lastFailureTime = CFAbsoluteTimeGetCurrent()
            // Same reason as the death path: without this, a bootstrap that fails while nothing
            // is listening leaves the proxy down until an unrelated event happens to poke it.
            self.scheduleRetryLocked(configuration: configuration, after: self.currentBackoffLocked())
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
        WebProxyLog.log("carrier died after becoming ready")
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
            // Arm the retry here as well as in `scheduleStart`: the listeners are what would
            // otherwise carry the news back, and a death that nobody happens to be listening for
            // would leave the proxy down for good.
            self.scheduleRetryLocked(configuration: failedConfiguration, after: self.currentBackoffLocked())
        }
        let failureCountSnapshot = self.consecutiveFailureCount
        let generationAtFail = self.startGeneration
        self.startLock.unlock()
        
        self.lock.lock()
        self.stopLocked()
        self.lock.unlock()
        
        self.notifySidecarEvent()
        
        // Auto-retry after the backoff window. Without this, a failure that is not followed by
        // another settings re-apply (the common case: long-poll death in background) leaves the
        // manager stopped forever once the cooldown expires with nobody calling configure.
        if let failedConfiguration = failedConfiguration {
            let backoff = min(
                WebProxyManager.maximumRetryInterval,
                WebProxyManager.minimumRetryInterval * pow(2.0, Double(max(failureCountSnapshot, 1) - 1))
            )
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + backoff + 0.05) { [weak self] in
                guard let self else {
                    return
                }
                self.startLock.lock()
                let stillSameGeneration = self.startGeneration == generationAtFail
                let stillSameFailure = self.lastFailedConfiguration == failedConfiguration
                self.startLock.unlock()
                // A newer start/stop/applicationDidBecomeActive owns recovery now.
                guard stillSameGeneration, stillSameFailure else {
                    return
                }
                self.scheduleStart(configuration: failedConfiguration)
            }
        }
    }
    
    private func stopLocked() {
        self.sidecar?.stop()
        self.sidecar = nil
        self.configuration = nil
        self.endpoint = nil
        self.sidecarReadySince = 0.0
        // lastGoodEndpoint intentionally retained for resolution during the next bootstrap.
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
