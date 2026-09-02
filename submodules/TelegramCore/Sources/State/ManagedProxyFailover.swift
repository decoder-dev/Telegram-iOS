import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

private let proxyRotationProbeCacheInterval: Double = 2.0 * 60.0
private let proxyRotationCooldownSeconds: Double = 30.0
private let proxyRotationProbeTimeout: Double = 30.0

private func proxyRotationRotatableServers(from settings: ProxySettings) -> [ProxyServerSettings] {
    return settings.servers.filter { server in
        if settings.automaticServers.contains(server) {
            return false
        }
        if server.connection.isWebProxy {
            return false
        }
        return true
    }
}

private func probeProxyRotationServersOnce(network: Network, servers: [ProxyServerSettings], queue: Queue) -> Signal<[ProxyServerSettings: ProxyServerStatus], NoError> {
    let probeTargets = servers.filter { server in
        !server.connection.isWebProxy && server.mtProxySettings != nil
    }
    if probeTargets.isEmpty {
        return .single([:])
    }
    return Signal { subscriber in
        var results: [ProxyServerSettings: ProxyServerStatus] = [:]
        var remaining = probeTargets.count
        let lock = NSLock()
        var disposables: [Disposable] = []
        for server in probeTargets {
            guard let settings = server.mtProxySettings else {
                lock.lock()
                remaining -= 1
                let done = remaining == 0
                lock.unlock()
                if done {
                    subscriber.putNext(results)
                    subscriber.putCompletion()
                }
                continue
            }
            let token = MTProxyConnectivity.pingProxy(with: network.context, datacenterId: network.datacenterId, settings: settings).start(next: { status in
                lock.lock()
                if let status = status as? MTProxyConnectivityStatus {
                    if status.reachable {
                        results[server] = .available(status.roundTripTime)
                    } else {
                        results[server] = .notAvailable
                    }
                }
                remaining -= 1
                let done = remaining == 0
                let snapshot = done ? results : nil
                lock.unlock()
                if let snapshot {
                    subscriber.putNext(snapshot)
                    subscriber.putCompletion()
                }
            })
            disposables.append(ActionDisposable {
                token?.dispose()
            })
        }
        return ActionDisposable {
            for disposable in disposables {
                disposable.dispose()
            }
        }
    }
    |> runOn(queue)
}

private final class ProxyFailoverContext {
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let network: Network
    private let queue = Queue()
    
    private var settingsDisposable: Disposable?
    private var connectionStatusDisposable: Disposable?
    private var probeDisposable: Disposable?
    private var connectingTimer: SwiftSignalKit.Timer?
    
    private var currentSettings: ProxySettings = .defaultSettings
    private var isChecking = false
    private var isConnectingViaProxy = false
    private var lastCheckedAt: [ProxyServerSettings: Double] = [:]
    private var lastCheckedStatus: [ProxyServerSettings: ProxyServerStatus] = [:]
    private var lastRotateAt: Double = 0.0
    
    init(accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network) {
        self.accountManager = accountManager
        self.network = network
    }
    
    func start() {
        let settingsSignal = self.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> map { sharedData -> ProxySettings in
            return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
        }
        
        self.settingsDisposable = (settingsSignal
        |> deliverOn(self.queue)).start(next: { [weak self] settings in
            guard let self else {
                return
            }
            self.currentSettings = settings
            self.cancelConnectingTimer()
            self.probeDisposable?.dispose()
            self.probeDisposable = nil
            self.isChecking = false
        })
        
        self.connectionStatusDisposable = (self.network.connectionStatus
        |> deliverOn(self.queue)).start(next: { [weak self] status in
            self?.connectionStatusUpdated(status)
        })
    }
    
    func dispose() {
        self.settingsDisposable?.dispose()
        self.connectionStatusDisposable?.dispose()
        self.probeDisposable?.dispose()
        self.cancelConnectingTimer()
    }
    
    private func cancelConnectingTimer() {
        self.connectingTimer?.invalidate()
        self.connectingTimer = nil
    }
    
    private func connectionStatusUpdated(_ status: ConnectionStatus) {
        guard self.shouldManageRotation else {
            self.cancelConnectingTimer()
            return
        }
        switch status {
        case let .connecting(proxyAddress, _):
            if proxyAddress != nil {
                self.isConnectingViaProxy = true
                self.scheduleConnectingTimer()
            } else {
                self.isConnectingViaProxy = false
                self.cancelConnectingTimer()
            }
        default:
            self.isConnectingViaProxy = false
            self.cancelConnectingTimer()
            self.isChecking = false
        }
    }
    
    /// After a probe finds no better proxy (or cooldown blocks a switch), schedule another
    /// wait-and-probe cycle while the link is still stuck on `.connecting`. Without this the
    /// timer only fires once per connecting stint because `connectionStatus` is distinct-until-changed.
    private func rescheduleConnectingTimerIfNeeded() {
        guard self.isConnectingViaProxy, self.shouldManageRotation, !self.isChecking else {
            return
        }
        self.scheduleConnectingTimer()
    }
    
    private var shouldManageRotation: Bool {
        let settings = self.currentSettings
        guard !settings.autoFetchPublicMtProxy else {
            return false
        }
        guard settings.autoRotateProxies, settings.enabled else {
            return false
        }
        guard proxyRotationRotatableServers(from: settings).count > 1 else {
            return false
        }
        guard let active = settings.activeServer, !active.connection.isWebProxy, !settings.automaticServers.contains(active) else {
            return false
        }
        return true
    }
    
    private func scheduleConnectingTimer() {
        guard self.shouldManageRotation, !self.isChecking else {
            return
        }
        if self.connectingTimer != nil {
            return
        }
        let timeout = ProxyRotationTimeouts.timeoutSeconds(at: self.currentSettings.proxyRotationTimeoutIndex)
        self.connectingTimer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
            self?.connectingTimer = nil
            self?.checkProxiesAndSwitch()
        }, queue: self.queue)
        self.connectingTimer?.start()
    }
    
    private func checkProxiesAndSwitch() {
        guard self.shouldManageRotation, !self.isChecking else {
            self.rescheduleConnectingTimerIfNeeded()
            return
        }
        let settings = self.currentSettings
        let rotatableServers = proxyRotationRotatableServers(from: settings)
        guard rotatableServers.count > 1, let active = settings.activeServer else {
            self.rescheduleConnectingTimerIfNeeded()
            return
        }
        self.isChecking = true
        
        let now = CFAbsoluteTimeGetCurrent()
        var cachedStatuses: [ProxyServerSettings: ProxyServerStatus] = [:]
        var serversToProbe: [ProxyServerSettings] = []
        for server in rotatableServers {
            if let lastChecked = self.lastCheckedAt[server], now - lastChecked < proxyRotationProbeCacheInterval, let status = self.lastCheckedStatus[server] {
                cachedStatuses[server] = status
            } else {
                serversToProbe.append(server)
            }
        }
        
        if serversToProbe.isEmpty {
            self.isChecking = false
            self.switchToAvailable(active: active, statuses: cachedStatuses)
            return
        }
        
        self.probeDisposable?.dispose()
        self.probeDisposable = (probeProxyRotationServersOnce(network: self.network, servers: serversToProbe, queue: self.queue)
        |> timeout(proxyRotationProbeTimeout, queue: self.queue, alternate: .single([:]))
        |> deliverOn(self.queue)).start(next: { [weak self] probed in
            guard let self else {
                return
            }
            let finishedAt = CFAbsoluteTimeGetCurrent()
            for (server, status) in probed {
                self.lastCheckedAt[server] = finishedAt
                self.lastCheckedStatus[server] = status
            }
            var merged = cachedStatuses
            for (server, status) in probed {
                merged[server] = status
            }
            self.isChecking = false
            self.switchToAvailable(active: active, statuses: merged)
        })
    }
    
    private func switchToAvailable(active: ProxyServerSettings, statuses: [ProxyServerSettings: ProxyServerStatus]) {
        guard self.shouldManageRotation else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - self.lastRotateAt < proxyRotationCooldownSeconds {
            self.rescheduleConnectingTimerIfNeeded()
            return
        }
        
        var available: [(ProxyServerSettings, Double)] = []
        for (server, status) in statuses {
            if case let .available(rtt) = status {
                available.append((server, rtt))
            }
        }
        available.sort { $0.1 < $1.1 }
        
        guard let best = available.first(where: { $0.0 != active })?.0 else {
            self.rescheduleConnectingTimerIfNeeded()
            return
        }
        
        self.lastRotateAt = now
        let _ = updateProxySettingsInteractively(accountManager: self.accountManager, { current in
            var current = current
            if current.servers.contains(best) {
                current.activeServer = best
                current.enabled = true
                if !best.connection.isWebProxy, case .mtp = best.connection {
                    current.useForCalls = false
                }
            }
            return current
        }).start()
    }
}

/// Ping-based proxy rotation while stuck connecting via the active proxy.
/// Mirrors Android `ProxyRotationController` (probe RTT, switch to the fastest live server).
func managedProxyFailover(accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network) -> Signal<Never, NoError> {
    return Signal { subscriber in
        let context = ProxyFailoverContext(accountManager: accountManager, network: network)
        context.start()
        return ActionDisposable {
            context.dispose()
        }
    }
}
