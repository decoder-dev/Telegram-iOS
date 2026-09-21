import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit
import WebProxyTransport
import TelegramVLESS

public func updateProxySettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (ProxySettings) -> ProxySettings) -> Signal<Bool, NoError> {
    return accountManager.transaction { transaction -> Bool in
        return updateProxySettingsInteractively(transaction: transaction, f)
    }
}

/// Whether a hostname is usable as a WEB proxy relay: a real multi-label DNS name, never an IP
/// literal or one of WHATWG's numeric shorthands for one. Re-exported from `WebProxyTransport` so
/// the settings editor and the `tg://webproxy` link parser validate against the same rule the
/// carrier does, instead of saving a proxy that can only fail later.
public func isValidWebProxyHostname(_ host: String) -> Bool {
    return WebProxyHostname.isValid(host)
}

/// Whether an MTProxy secret is one a WEB proxy can use. `ee` TLS-emulation secrets are not:
/// the relay speaks raw bytes to a stock MTProxy and adds no inner TLS-emulation record.
public func isSupportedWebProxySecret(_ secret: Data) -> Bool {
    return WebProxySecret.isSupported(secret)
}

extension ProxyServerSettings {
    var webProxyConfiguration: WebProxyConfiguration? {
        guard case let .web(secret) = self.connection else {
            return nil
        }
        return WebProxyConfiguration(hostname: self.host, secret: secret)
    }

    public var vlessProxyURL: String? {
        guard case let .vless(secret) = self.connection else {
            return nil
        }
        return String(data: secret, encoding: .utf8)
    }

    var mtProxySettings: MTSocksProxySettings? {
        switch self.connection {
            case let .socks5(username, password):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: username, password: password, secret: nil)
            case let .mtp(secret):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: nil, password: nil, secret: secret)
            case .web:
                guard let configuration = self.webProxyConfiguration else {
                    return nil
                }
                guard let endpoint = WebProxyManager.shared.activeLoopbackEndpoint else {
                    return nil
                }
                return MTSocksProxySettings(ip: endpoint.host, port: endpoint.port, username: nil, password: nil, secret: configuration.secret)
            case .vless:
                guard let url = self.vlessProxyURL, VlessManager.shared.isReady(for: url),
                      let endpoint = VlessManager.shared.activeLoopbackEndpoint else {
                    return nil
                }
                return MTSocksProxySettings(ip: endpoint.host, port: UInt16(clamping: endpoint.port), username: endpoint.user, password: endpoint.password, secret: nil)
        }
    }
}

/// Whether a `vless://` share link is fully supported by the embedded runtime (strict
/// allowlist parsing). Re-exported so the settings editor validates against the same
/// rule the runtime applies.
public func isValidVlessProxyURL(_ url: String) -> Bool {
    if case .success = VlessProfileParser.parse(url) {
        return true
    }
    return false
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

func applySharedProxySettingsToNetwork(settings: ProxySettings, network: Network, forceTransportReconnect: Bool = false) {
    let previousForceLocalDNS = network.context.forceLocalDNS
    network.context.forceLocalDNS = settings.useLocalDNSForProxyHosts

    let activeServer = settings.effectiveActiveServer
    let isActiveWebProxy = activeServer?.connection.isWebProxy ?? false
    if isActiveWebProxy, let configuration = activeServer?.webProxyConfiguration {
        WebProxyManager.shared.configure(activeWebProxy: configuration)
    } else {
        WebProxyManager.shared.configure(activeWebProxy: nil)
    }
    
    let isActiveVlessProxy = activeServer?.connection.isVlessProxy ?? false
    if isActiveVlessProxy, let url = activeServer?.vlessProxyURL {
        VlessManager.shared.configure(activeProfileURL: url)
    } else {
        VlessManager.shared.configure(activeProfileURL: nil)
    }

    let resolvedProxySettings = activeServer?.mtProxySettings

    if (isActiveWebProxy || isActiveVlessProxy), resolvedProxySettings == nil {
        network.context.updateApiEnvironment { _ in
            network.pauseForWebProxyBootstrap()
            return nil
        }
        return
    }
    
    network.context.updateApiEnvironment { environment in
        let current = environment?.socksProxySettings
        let updated: MTSocksProxySettings?
        if isActiveWebProxy {
            if let resolvedProxySettings = resolvedProxySettings {
                updated = resolvedProxySettings
            } else if let current = current {
                // Sidecar not ready yet (bootstrap / resume) — keep the previous endpoint
                // rather than falling back to a direct connection.
                updated = current
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

    // MTContext serializes these blocks. The first block must finish notifying MTProto
    // listeners (enqueueing their route updates) before we enqueue a resume. Resuming
    // before updateApiEnvironment could briefly dial the previous/direct route.
    network.context.updateApiEnvironment { _ in
        network.resumeIfWebProxyBootstrapPaused()
        return nil
    }

    if forceTransportReconnect,
       let configuration = activeServer?.webProxyConfiguration,
       WebProxyManager.shared.isReady(for: configuration) {
        network.dropConnectionStatus()
        network.rebuildTransport()
    }
}

/// `currentSettings` returns nil until the account's shared-data subscription has delivered real
/// settings. Reapplying a placeholder in that window would look like "no active server" and tear
/// down the process-wide sidecar out from under every other account.
public func registerWebProxySidecarReapply(network: Network, currentSettings: @escaping () -> ProxySettings?) -> Disposable {
    // Every account Network must observe sidecar readiness. A single overwritten
    // callback left secondary accounts stuck on the fail-closed 127.0.0.1:1 route.
    let token = WebProxyManager.shared.addSidecarEventHandler { [weak network] event in
        guard let network = network, let settings = currentSettings() else {
            return
        }
        applySharedProxySettingsToNetwork(
            settings: settings,
            network: network,
            forceTransportReconnect: event == .carrierResumedInPlace
        )
    }
    return ActionDisposable {
        WebProxyManager.shared.removeSidecarEventHandler(token)
    }
}

public func registerVlessManagerReapply(network: Network, currentSettings: @escaping () -> ProxySettings?) -> Disposable {
    return (VlessManager.shared.stateEvents |> deliverOnMainQueue).start(next: { [weak network] _ in
        guard let network = network, let settings = currentSettings() else {
            return
        }
        applySharedProxySettingsToNetwork(settings: settings, network: network)
    })
}
