import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

/// Round-robin to the next saved proxy when the active one reports sustained connection issues.
/// Mirrors Android/PC-style failover for the local proxy list (#2225).
func managedProxyFailover(accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network) -> Signal<Never, NoError> {
    let issueHoldSeconds: Double = 12.0
    let cooldownSeconds: Double = 30.0
    
    final class State {
        var issueSince: Double?
        var lastRotateAt: Double = 0
        var lastActive: ProxyServerSettings?
    }
    let state = Atomic(value: State())
    
    let settingsSignal = accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
    |> map { sharedData -> ProxySettings in
        return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
    }
    
    return combineLatest(queue: .mainQueue(), settingsSignal, network.connectionStatus)
    |> mapToSignal { settings, connectionStatus -> Signal<Never, NoError> in
        network.context.forceLocalDNS = settings.useLocalDNSForProxyHosts
        
        // RTT-based auto-fetch owns failover while it is on.
        guard !settings.autoFetchPublicMtProxy else {
            let _ = state.modify { s in
                s.issueSince = nil
                s.lastActive = nil
                return s
            }
            return .complete()
        }
        
        guard settings.autoRotateProxies, settings.enabled, settings.servers.count > 1 else {
            let _ = state.modify { s in
                s.issueSince = nil
                s.lastActive = nil
                return s
            }
            return .complete()
        }
        guard let active = settings.activeServer else {
            let _ = state.modify { s in
                s.issueSince = nil
                s.lastActive = nil
                return s
            }
            return .complete()
        }
        
        let now = CFAbsoluteTimeGetCurrent()
        let hasIssues: Bool
        if case let .connecting(_, proxyHasConnectionIssues) = connectionStatus {
            hasIssues = proxyHasConnectionIssues
        } else {
            hasIssues = false
        }
        
        var shouldRotate = false
        let _ = state.modify { s in
            if s.lastActive != active {
                s.lastActive = active
                s.issueSince = nil
            }
            if hasIssues {
                if s.issueSince == nil {
                    s.issueSince = now
                } else if let since = s.issueSince, now - since >= issueHoldSeconds, now - s.lastRotateAt >= cooldownSeconds {
                    shouldRotate = true
                    s.lastRotateAt = now
                    s.issueSince = nil
                }
            } else {
                s.issueSince = nil
            }
            return s
        }
        
        if !shouldRotate {
            return .complete()
        }
        
        guard let index = settings.servers.firstIndex(of: active) else {
            return .complete()
        }
        let next = settings.servers[(index + 1) % settings.servers.count]
        if next == active {
            return .complete()
        }
        
        return updateProxySettingsInteractively(accountManager: accountManager) { current in
            var current = current
            if current.servers.contains(next) {
                current.activeServer = next
                current.enabled = true
            }
            return current
        }
        |> ignoreValues
    }
}
