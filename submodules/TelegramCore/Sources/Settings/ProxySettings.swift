import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit
import WebProxyTransport

public func updateProxySettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (ProxySettings) -> ProxySettings) -> Signal<Bool, NoError> {
    return accountManager.transaction { transaction -> Bool in
        return updateProxySettingsInteractively(transaction: transaction, f)
    }
}

extension ProxyServerSettings {
    var mtProxySettings: MTSocksProxySettings? {
        switch self.connection {
            case let .socks5(username, password):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: username, password: password, secret: nil)
            case let .mtp(secret):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: nil, password: nil, secret: secret)
            case let .web(secret):
                let configuration = WebProxyConfiguration(hostname: self.host, secret: secret)
                guard WebProxyManager.shared.configure(activeWebProxy: configuration),
                      let endpoint = WebProxyManager.shared.activeLoopbackEndpoint else {
                    return nil
                }
                return MTSocksProxySettings(ip: endpoint.host, port: endpoint.port, username: nil, password: nil, secret: secret)
        }
    }
}

public func updateProxySettingsInteractively(transaction: AccountManagerModifier<TelegramAccountManagerTypes>, _ f: @escaping (ProxySettings) -> ProxySettings) -> Bool {
    var hasChanges = false
    transaction.updateSharedData(SharedDataKeys.proxySettings, { current in
        let previous = current?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
        let updated = f(previous)
        hasChanges = previous != updated
        return PreferencesEntry(updated)
    })
    return hasChanges
}

func applySharedProxySettingsToNetwork(settings: ProxySettings, network: Network) {
    let previousForceLocalDNS = network.context.forceLocalDNS
    network.context.forceLocalDNS = settings.useLocalDNSForProxyHosts

    let activeServer = settings.effectiveActiveServer
    let isActiveWebProxy = activeServer?.connection.isWebProxy ?? false
    if !isActiveWebProxy {
        WebProxyManager.shared.configure(activeWebProxy: nil)
    }

    // mtProxySettings configures (or reuses) the WEB proxy sidecar as a side effect;
    // calling it here as well as above would start it twice.
    let resolvedProxySettings = activeServer?.mtProxySettings

    network.context.updateApiEnvironment { environment in
        let current = environment?.socksProxySettings
        let updated: MTSocksProxySettings?
        if isActiveWebProxy {
            if let resolvedProxySettings = resolvedProxySettings {
                updated = resolvedProxySettings
            } else if let current = current {
                // Sidecar failed while switching proxies — keep the previous endpoint
                // rather than falling back to a direct connection.
                updated = current
            } else if let activeServer = activeServer, case let .web(secret) = activeServer.connection {
                // First enable with a dead sidecar: route to an unreachable loopback port
                // with the MTProxy code path so traffic never goes out unproxied.
                updated = MTSocksProxySettings(ip: "127.0.0.1", port: 1, username: nil, password: nil, secret: secret)
            } else {
                updated = nil
            }
        } else {
            updated = resolvedProxySettings
        }
        let updateNetwork: Bool
        if previousForceLocalDNS != settings.useLocalDNSForProxyHosts {
            updateNetwork = true
        } else if let current = current, let updated = updated {
            updateNetwork = !current.isEqual(updated)
        } else {
            updateNetwork = (current != nil) != (updated != nil)
        }
        if updateNetwork {
            network.dropConnectionStatus()
            return environment?.withUpdatedSocksProxySettings(updated)
        } else {
            return nil
        }
    }
}
