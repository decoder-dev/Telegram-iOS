import Foundation
import Network

public struct WebProxyConfiguration: Equatable {
    public let hostname: String
    public let secret: Data
    
    public init(hostname: String, secret: Data) {
        self.hostname = hostname
        self.secret = secret
    }
}

/// Why the sidecar changed — handlers should not guess from `isReady` alone.
public enum WebProxySidecarEvent: Equatable {
    /// Sidecar published a loopback endpoint (cold bootstrap or full restart).
    case becameReady
    /// HTTPS carrier rebuilt in place after foreground; loopback host:port unchanged.
    case carrierResumedInPlace
    /// Sidecar stopped or bootstrap failed; endpoint is gone until the next start.
    case stopped
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
    /// If the WEB sidecar exchanged frames this recently, a foreground resume skips rebuilding
    /// the HTTPS carrier — a background keepalive ping keeps the session in this window.
    private static let recentActivitySkipRebuild: Double = 45.0

    private let lock = NSLock()
    private let startLock = NSLock()
    private var sidecar: WebProxySidecar?
    private var configuration: WebProxyConfiguration?
    /// Retained only while a sidecar is live — never published to MtProto after stop.
    private var endpoint: LoopbackEndpoint?
    private var startingConfiguration: WebProxyConfiguration?
    private var startingSince: Double = 0.0
    private var startGeneration: UInt64 = 0
    private var lastFailedConfiguration: WebProxyConfiguration?
    private var lastFailureTime: Double = 0.0
    private var consecutiveFailureCount: Int = 0
    private var sidecarReadySince: Double = 0.0

    /// Set from `applicationDidEnterBackground`. The WEB carrier is foreground-only.
    private var enteredBackgroundAt: Double = 0.0
    /// Last uplink/downlink/keepalive activity, used to skip a healthy carrier rebuild.
    private var lastActivityAt: Double = 0.0

    /// The configuration the app currently wants running, as opposed to the one that happens to
    /// be up. A retry armed by the cooldown must not resurrect a proxy the user has since turned
    /// off, and `configuration` is nil from the moment a carrier dies, so it cannot answer that.
    private var desiredConfiguration: WebProxyConfiguration?
    /// The configuration a cooldown retry is currently armed for, so a burst of re-applies arms
    /// only one — but switching servers still re-arms rather than inheriting the old target's slot.
    private var scheduledRetryConfiguration: WebProxyConfiguration?
    /// Stamped onto each armed retry so a superseded one drops out when it fires.
    private var retryGeneration: UInt64 = 0
    
    /// Whether there is a network at all, and the monitor that says so.
    ///
    /// A bootstrap attempted with no path cannot succeed, but it still counted as a failure and
    /// still advanced the cooldown — so after the radio came back the proxy sat out a backoff it
    /// had earned entirely while offline. In one tester's log 34 of 55 bootstrap failures were
    /// `NSURLErrorNotConnectedToInternet`. Starts now wait for a path, and the path returning is
    /// itself the trigger to start, because conditions genuinely changed and the cooldown was
    /// measuring the wrong thing.
    ///
    /// Optimistic until told otherwise: a manager that never hears from the monitor must still
    /// try, rather than refuse to connect for the life of the process.
    private var isNetworkAvailable = true
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?

    private var nextSidecarEventToken: SidecarEventToken = 0
    private var sidecarEventHandlers: [SidecarEventToken: (WebProxySidecarEvent) -> Void] = [:]
    
    private init() {
    }
    
    public var activeLoopbackEndpoint: LoopbackEndpoint? {
        self.lock.lock()
        defer { self.lock.unlock() }
        // Only the sidecar that is currently listening may publish a loopback port.
        // Fail-closed nil during bootstrap; MtProto must not dial a stale port.
        guard self.sidecar != nil, let endpoint = self.endpoint else {
            return nil
        }
        return endpoint
    }
    
    public var activeConfiguration: WebProxyConfiguration? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.configuration
    }
    
    public func isReady(for configuration: WebProxyConfiguration) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.configuration == configuration && self.endpoint != nil && self.sidecar != nil
    }
    
    /// Registers a handler invoked on the main queue when the sidecar becomes ready, fails, or stops.
    /// Multi-account: every Network must register — a single overwritten callback left other accounts stuck on the fail-closed loopback.
    @discardableResult
    public func addSidecarEventHandler(_ handler: @escaping (WebProxySidecarEvent) -> Void) -> SidecarEventToken {
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
            self.retryGeneration &+= 1
            self.scheduledRetryConfiguration = nil
            self.startingConfiguration = nil
            // Turning the proxy off is an explicit user action — don't make re-enabling the same
            // server wait out a cooldown left over from an earlier failure.
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
            self.startLock.unlock()
            
            self.lock.lock()
            self.stopLocked()
            self.lock.unlock()
            self.removePathMonitorIfNeeded()
            return true
        }
        
        self.startLock.lock()
        self.desiredConfiguration = server
        self.startLock.unlock()

        self.installPathMonitorIfNeeded()
        
        self.lock.lock()
        if server == self.configuration, self.endpoint != nil {
            self.lock.unlock()
            return true
        }
        self.lock.unlock()

        self.startLock.lock()
        let bootstrapInFlight = self.startingConfiguration == server
            && CFAbsoluteTimeGetCurrent() - self.startingSince < WebProxyManager.startTimeout
        self.startLock.unlock()
        if bootstrapInFlight {
            return self.isReady(for: server)
        }
        
        self.scheduleStart(configuration: server)
        return self.isReady(for: server)
    }
    
    /// Call from `applicationDidEnterBackground`.
    public func applicationDidEnterBackground() {
        self.startLock.lock()
        self.enteredBackgroundAt = CFAbsoluteTimeGetCurrent()
        self.startLock.unlock()
    }

    /// Sends a keepalive PING on the active sidecar (if any) and returns true.
    /// Returns false when there is no ready WEB proxy sidecar.
    /// Intended to be called from an `UIBackgroundTask` so the carrier stays alive briefly.
    public func sendKeepalivePing() -> Bool {
        self.lock.lock()
        let sidecar = self.sidecar
        self.lock.unlock()
        guard let sidecar = sidecar else { return false }
        sidecar.sendKeepalivePing()
        self.lock.lock()
        self.lastActivityAt = CFAbsoluteTimeGetCurrent()
        self.lock.unlock()
        return true
    }

    /// True when a live sidecar recently carried traffic (or we just keepalive-pinged it), so a
    /// foreground resume can leave the carrier alone instead of rebuilding.
    private func shouldSkipCarrierRebuildDueToRecentActivity(sidecar: WebProxySidecar?, hasEndpoint: Bool) -> Bool {
        guard hasEndpoint, let sidecar else {
            return false
        }
        let sidecarAge = sidecar.secondsSinceLastActivity()
        self.lock.lock()
        let managerStamp = self.lastActivityAt
        self.lock.unlock()
        let managerAge = managerStamp > 0 ? CFAbsoluteTimeGetCurrent() - managerStamp : Double.infinity
        return min(sidecarAge, managerAge) < 45.0
    }
    
    /// Call from `applicationWillEnterForeground`. If the sidecar is still ready and recently
    /// active, skip the later carrier rebuild by clearing `enteredBackgroundAt` only.
    public func applicationWillEnterForeground() {
        self.startLock.lock()
        let backgroundedAt = self.enteredBackgroundAt
        self.startLock.unlock()
        guard backgroundedAt > 0 else {
            return
        }
        
        self.lock.lock()
        let sidecar = self.sidecar
        let hasEndpoint = self.endpoint != nil
        self.lock.unlock()
        
        if self.shouldSkipCarrierRebuildDueToRecentActivity(sidecar: sidecar, hasEndpoint: hasEndpoint) {
            self.startLock.lock()
            self.enteredBackgroundAt = 0
            self.startLock.unlock()
            WebProxyLog.log("foreground: sidecar recently active, skipping carrier rebuild")
        }
    }
    
    /// Sends a session keepalive PING while the app is backgrounded. Returns false when there is
    /// no live WEB sidecar. `expirationHandler` is invoked shortly after the ping is queued so the
    /// caller can end its `beginBackgroundTask`.
    public func beginBackgroundKeepalive(expirationHandler: @escaping () -> Void) -> Bool {
        guard self.sendKeepalivePing() else {
            return false
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: expirationHandler)
        return true
    }
    
    /// Call from `applicationDidBecomeActive` only (AppDelegate). Rebuilds the HTTPS carrier
    /// in place when the app was backgrounded long enough for URLSession to die; skips Control
    /// Center / quick flickers that set `enteredBackgroundAt` for under a few seconds.
    public func applicationDidBecomeActive() {
        self.startLock.lock()
        let backgroundedAt = self.enteredBackgroundAt
        let starting = self.startingConfiguration
        let desired = self.desiredConfiguration
        self.startLock.unlock()
        
        self.lock.lock()
        let active = self.configuration
        let sidecar = self.sidecar
        let hasEndpoint = self.endpoint != nil
        self.lock.unlock()
        
        guard let target = active ?? starting ?? desired else {
            return
        }

        if !hasEndpoint {
            self.startLock.lock()
            self.enteredBackgroundAt = 0
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
            self.startLock.unlock()
            // Force past a stale `startingConfiguration` left by a failed bootstrap / carrier
            // death — otherwise the cooldown retry and this resume both no-op for up to 180s.
            self.scheduleStart(configuration: target, replacingCurrentStart: true)
            return
        }

        guard backgroundedAt > 0 else {
            return
        }
        
        let dwell = CFAbsoluteTimeGetCurrent() - backgroundedAt
        // Control Center / notification shade can briefly enter background. Rebuilding a healthy
        // carrier every time causes Connecting flicker; only rebuild after a real suspension.
        if dwell < 5.0 {
            self.startLock.lock()
            self.enteredBackgroundAt = 0
            self.startLock.unlock()
            return
        }

        if self.shouldSkipCarrierRebuildDueToRecentActivity(sidecar: sidecar, hasEndpoint: hasEndpoint) {
            self.startLock.lock()
            self.enteredBackgroundAt = 0
            self.startLock.unlock()
            WebProxyLog.log("becomeActive: sidecar recently active, skipping carrier rebuild")
            return
        }

        self.startLock.lock()
        self.enteredBackgroundAt = 0
        self.lastFailedConfiguration = nil
        self.consecutiveFailureCount = 0
        self.startLock.unlock()

        guard let sidecar = sidecar else {
            self.sequentialRestart(configuration: target)
            return
        }
        self.performInPlaceCarrierResume(sidecar: sidecar, configuration: target)
    }
    
    private func performInPlaceCarrierResume(sidecar: WebProxySidecar, configuration: WebProxyConfiguration) {
        // Rebuild the carrier behind the listener that is already published. On failure the
        // sidecar has already torn itself down, so there is nothing left to salvage and the
        // port has to change after all.
        sidecar.reconnectTransport { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success:
                WebProxyLog.log("resume transport reconnect succeeded, notifying networks")
                self.notifySidecarEvent(.carrierResumedInPlace)
            case let .failure(error):
                WebProxyLog.log("resume transport reconnect failed, rebuilding the sidecar: \(error)")
                self.sequentialRestart(configuration: configuration)
            }
        }
    }
    
    /// Stop the current sidecar, then schedule a fresh one. Used when there is no live endpoint
    /// or in-place transport reconnect failed. Not overlapping — only one listener at a time.
    private func sequentialRestart(configuration: WebProxyConfiguration) {
        // Invalidate a previous asynchronous start before replacing the sidecar, and mark this
        // replacement as in-flight BEFORE clearing the live endpoint so concurrent `configure`
        // calls coalesce on `startingConfiguration` instead of spawning parallel bootstraps.
        // The call below opts out of the "already starting" check.
        self.startLock.lock()
        self.startGeneration &+= 1
        self.startingConfiguration = configuration
        self.startingSince = CFAbsoluteTimeGetCurrent()
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
        
        // MtProto still has the old loopback socks settings until a `.stopped` / `.becameReady`
        // re-apply. Without this it dials a dead port for the whole next bootstrap.
        self.notifySidecarEvent(.stopped)
        
        self.scheduleStart(configuration: configuration, replacingCurrentStart: true)
    }
    
    /// `replacingCurrentStart` is for callers that have already torn the sidecar down and marked
    /// their own replacement in flight. They must not be answered with "a bootstrap is already
    /// running" (it is theirs) or held off by a cooldown (they are the recovery).
    private func scheduleStart(configuration: WebProxyConfiguration, replacingCurrentStart: Bool = false) {
        self.startLock.lock()
        if !replacingCurrentStart, self.startingConfiguration == configuration, CFAbsoluteTimeGetCurrent() - self.startingSince < WebProxyManager.startTimeout {
            // Every account resolves the same shared proxy settings, so with several accounts
            // this is called once per Network for one and the same server. Re-scheduling would
            // supersede the in-flight start, tearing down a sidecar that is midway through its
            // HTTPS bootstrap and restarting the wait from zero for all of them.
            self.startLock.unlock()
            return
        }
        if !replacingCurrentStart, self.lastFailedConfiguration == configuration, self.consecutiveFailureCount > 0 {
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
        if !self.isNetworkAvailable {
            // No path: the bootstrap would fail on its first request and charge the cooldown for
            // it. `handlePathUpdate` starts this the moment a path exists.
            WebProxyLog.log("holding bootstrap for \(configuration.hostname): no network path")
            self.startLock.unlock()
            return
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
    
    private func installPathMonitorIfNeeded() {
        self.startLock.lock()
        if self.pathMonitor != nil {
            self.startLock.unlock()
            return
        }
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        self.startLock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces.map { String(describing: $0.type) }.sorted().joined(separator: ",")
            let signature = "\(String(describing: path.status))-\(interfaces)"
            self?.handlePathUpdate(isSatisfied: path.status == .satisfied, signature: signature)
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func removePathMonitorIfNeeded() {
        self.startLock.lock()
        let monitor = self.pathMonitor
        self.pathMonitor = nil
        self.lastPathSignature = nil
        self.isNetworkAvailable = true
        self.startLock.unlock()
        monitor?.cancel()
    }

    private func handlePathUpdate(isSatisfied: Bool, signature: String) {
        self.startLock.lock()
        let wasAvailable = self.isNetworkAvailable
        self.isNetworkAvailable = isSatisfied
        let desired = self.desiredConfiguration
        let previousSignature = self.lastPathSignature
        self.lastPathSignature = signature
        if isSatisfied, !wasAvailable {
            // The cooldown was earned offline. Whatever it was counting, it was not this server
            // refusing us.
            self.lastFailedConfiguration = nil
            self.consecutiveFailureCount = 0
        }
        self.startLock.unlock()

        guard isSatisfied, let desired = desired else {
            return
        }

        self.lock.lock()
        let hasEndpoint = self.configuration == desired && self.endpoint != nil
        let sidecar = self.sidecar
        self.lock.unlock()

        if hasEndpoint, let sidecar = sidecar {
            // Wi‑Fi↔cellular / VPN while the path stays satisfied: MtProto rebuilds loopback,
            // but the URLSession/WS to the relay is still bound to the old interface. Rebuild
            // the carrier in place whenever the interface set actually changed.
            let pathChanged = previousSignature != nil && previousSignature != signature
            let returnedFromOffline = !wasAvailable
            guard pathChanged || returnedFromOffline else {
                return
            }
            WebProxyLog.log("network path changed while WEB endpoint live (\(previousSignature ?? "nil") → \(signature)), reconnecting carrier in place")
            self.performInPlaceCarrierResume(sidecar: sidecar, configuration: desired)
            return
        }

        guard !wasAvailable else {
            return
        }

        self.startLock.lock()
        let bootstrapInFlight = self.startingConfiguration == desired
            && CFAbsoluteTimeGetCurrent() - self.startingSince < WebProxyManager.startTimeout
        self.startLock.unlock()
        guard !bootstrapInFlight else {
            return
        }
        WebProxyLog.log("network path returned, starting \(desired.hostname) without waiting out the offline cooldown")
        // Forced: a start held back for want of a path leaves `startingConfiguration` set — by
        // `sequentialRestart`, or by an attempt that never got off the ground — and the ordinary
        // path would read that marker as a bootstrap already running and return, stranding the
        // proxy for as long as the marker lives.
        self.scheduleStart(configuration: desired, replacingCurrentStart: true)
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
        // A retry already owns this target. Anything else — no retry at all, or one armed for a
        // server the user has since switched away from — has to be replaced: a single boolean
        // flag let the stale target hold the only slot, and the new one was dropped on the floor
        // and never retried at all.
        if self.scheduledRetryConfiguration == configuration {
            return
        }
        self.retryGeneration &+= 1
        let generation = self.retryGeneration
        self.scheduledRetryConfiguration = configuration

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.1, delay)) { [weak self] in
            guard let self = self else {
                return
            }

            self.startLock.lock()
            let isCurrent = generation == self.retryGeneration
            if isCurrent {
                self.scheduledRetryConfiguration = nil
            }
            let isStillWanted = self.desiredConfiguration == configuration
            self.startLock.unlock()

            guard isCurrent, isStillWanted else {
                return
            }

            self.lock.lock()
            let isAlreadyRunning = self.configuration == configuration && self.endpoint != nil
            self.lock.unlock()

            guard !isAlreadyRunning else {
                return
            }

            self.scheduleStart(configuration: configuration, replacingCurrentStart: true)
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
            self.sidecarReadySince = CFAbsoluteTimeGetCurrent()
            self.lastActivityAt = CFAbsoluteTimeGetCurrent()
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

            self.notifySidecarEvent(.becameReady)

            if let previous = previous {
                DispatchQueue.global(qos: .utility).async {
                    previous.stop()
                }
            }
        case let .failure(error):
            // The reason a WEB proxy failed used to end here: the branch did not even bind the
            // error, so "my proxy does not connect" had no answer short of reading the source.
            WebProxyLog.log("bootstrap failed for \(configuration.hostname): \(error)")

            sidecar?.stop()
            self.startLock.lock()
            // Clear the in-flight marker before arming the retry. Leaving it set made
            // `scheduleRetryLocked` → `scheduleStart` hit the "already starting" gate and return
            // without starting — so a failed bootstrap never came back without a path flap.
            if self.startingConfiguration == configuration {
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
            
            self.notifySidecarEvent(.stopped)
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
        if let failedConfiguration = failedConfiguration {
            // Do not leave `startingConfiguration` set — that made the armed retry's
            // `scheduleStart` no-op inside the 180s window (carrier deaths never recovered).
            if self.startingConfiguration == failedConfiguration {
                self.startingConfiguration = nil
            }
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
        self.startLock.unlock()
        
        self.lock.lock()
        self.stopLocked()
        self.lock.unlock()
        
        self.notifySidecarEvent(.stopped)
        
        // The auto-retry that used to be duplicated here — a second `asyncAfter` on the same
        // backoff, guarded on `startGeneration` — could never run: `scheduleRetryLocked` above
        // fires 50ms earlier and its `scheduleStart` bumps that generation first.
    }
    
    private func stopLocked() {
        self.sidecar?.stop()
        self.sidecar = nil
        self.configuration = nil
        self.endpoint = nil
        self.sidecarReadySince = 0.0
    }
    
    private func notifySidecarEvent(_ event: WebProxySidecarEvent) {
        self.lock.lock()
        let handlers = Array(self.sidecarEventHandlers.values)
        self.lock.unlock()
        DispatchQueue.main.async {
            for handler in handlers {
                handler(event)
            }
        }
    }
}
