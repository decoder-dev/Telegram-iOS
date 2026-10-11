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
    /// Managed proxies connect through their current loopback endpoint, not the
    /// public profile hostname. A stale/direct online state must not confirm a switch.
    public func matchesConnectedProxyAddress(_ address: String?) -> Bool {
        guard let address, let settings = self.mtProxySettings else { return false }
        return settings.ip == address
    }

    /// A closed local endpoint keeps every MTContext consumer, including download
    /// workers, off a direct route while a managed proxy is unavailable.
    static var managedBootstrapProxySettings: MTSocksProxySettings {
        return MTSocksProxySettings(ip: "127.0.0.1", port: 1, username: nil, password: nil, secret: nil)
    }

    var legacyWebProxyConfiguration: LegacyWebProxyConfiguration? {
        guard case let .web(secret, path) = self.connection, path.isEmpty,
              let configuration = self.webProxyConfiguration else { return nil }
        return LegacyWebProxyConfiguration(hostname: configuration.host, secret: secret)
    }

    public var vlessProxyURL: String? {
        guard case let .vless(secret) = self.connection else {
            return nil
        }
        return String(data: secret, encoding: .utf8)
    }

    var isWebProxy: Bool {
        if case .web = self.connection {
            return true
        } else {
            return false
        }
    }

    var mtProxySettings: MTSocksProxySettings? {
        switch self.connection {
            case let .socks5(username, password):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: username, password: password, secret: nil)
            case let .mtp(secret):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: nil, password: nil, secret: secret)
            case let .web(secret, _):
                return MTSocksProxySettings(ip: WebProxyConfiguration.canonicalHost(self.host) ?? self.host, port: WebProxyConfiguration.port, username: nil, password: nil, secret: secret, webProxy: true)
            case .vless:
                guard let url = self.vlessProxyURL,
                      let endpoint = VlessManager.shared.loopbackEndpoint(for: url) else {
                    return nil
                }
                return MTSocksProxySettings(ip: endpoint.host, port: UInt16(clamping: endpoint.port), username: endpoint.user, password: endpoint.password, secret: nil)
        }
    }

    var webProxyConfiguration: WebProxyConfiguration? {
        guard case let .web(secret, path) = self.connection else {
            return nil
        }
        return WebProxyConfiguration(host: self.host, path: path, secret: secret)
    }
}

extension ProxyServerSettings {
    public var webProxyAddress: String? {
        guard case let .web(_, path) = self.connection else {
            return nil
        }
        return path.isEmpty ? self.host : "\(self.host)/\(path)"
    }
}

public func canonicalWebProxyHost(_ value: String) -> String? {
    return WebProxyConfiguration.canonicalHost(value)
}

public func canonicalWebProxyAddress(_ value: String) -> (host: String, path: String)? {
    return WebProxyConfiguration.canonicalAddress(value)
}

public func parseWebProxySecret(_ value: String) -> Data? {
    return WebProxyConfiguration.parseSecret(value)
}

public func webProxySecretString(_ secret: Data) -> String {
    return secret.map { String(format: "%02x", $0) }.joined()
}

public func makeWebProxySettings(address: String, secret: String) -> ProxyServerSettings? {
    guard let address = canonicalWebProxyAddress(address), let data = parseWebProxySecret(secret) else {
        return nil
    }
    return ProxyServerSettings(host: address.host, port: Int32(WebProxyConfiguration.port), connection: .web(secret: data, path: address.path))
}

/// Decodes the `server` and `secret` parameters of a `webproxy` link.
///
/// A link that carries a base path **must** mark its secret with the leading `0x70` byte;
/// an unmarked secret there is rejected (BASE_PATH.md §3). The rule exists so that no link
/// can be silently accepted by a client without base-path support, which would normalize
/// `host/path` to an empty host and offer to connect to a pathless proxy. Hand entry in the
/// editor is not bound by it - the hazard is specific to a shared link - so
/// `makeWebProxySettings(address:secret:)` stays lenient.
/// The `webproxy` query rule, so that every entry point accepts exactly the same set of
/// links. `host` is a legacy input alias for `server` (ANDROID.md); generated links always
/// use `server`, and exactly one of the two must appear alongside exactly one `secret`.
/// Items with any other name are ignored, so a trailing `&`, which `URLComponents` keeps
/// as an empty-name item, or a tracking parameter does not make a shared link dead.
/// Keeping this in one place matters: when `UrlHandling` had its own laxer loop, a link
/// with both `server` and `host` was rejected in the proxy editor and accepted from a
/// chat, resolving to whichever came last.
public func parseWebProxyLinkQueryItems(_ items: [URLQueryItem]) -> (host: String, path: String, secret: Data)? {
    let hostItems = items.filter { $0.name == "server" || $0.name == "host" }
    let secretItems = items.filter { $0.name == "secret" }
    guard hostItems.count == 1,
          secretItems.count == 1,
          let address = hostItems[0].value,
          let secret = secretItems[0].value else {
        return nil
    }
    return parseWebProxyLinkComponents(address: address, secret: secret)
}

public func parseWebProxyLinkComponents(address: String, secret: String) -> (host: String, path: String, secret: Data)? {
    guard let address = canonicalWebProxyAddress(address),
          let decoded = WebProxyConfiguration.parseMarkedSecret(secret),
          address.path.isEmpty || decoded.isMarked else {
        return nil
    }
    return (address.host, address.path, decoded.secret)
}

public func parseWebProxySettingsLink(_ value: String) -> ProxyServerSettings? {
    guard let components = URLComponents(string: value),
          components.fragment == nil,
          components.user == nil,
          components.password == nil else {
        return nil
    }

    let scheme = components.scheme?.lowercased()
    let isTelegramLink = scheme == "https"
        && components.host?.lowercased() == "t.me"
        && components.path == "/webproxy"
        && (components.port == nil || components.port == Int(WebProxyConfiguration.port))
    let isTelegramScheme = scheme == "tg"
        && components.host?.lowercased() == "webproxy"
        && (components.path.isEmpty || components.path == "/")
        && components.port == nil
    guard isTelegramLink || isTelegramScheme else {
        return nil
    }

    guard let link = parseWebProxyLinkQueryItems(components.queryItems ?? []) else {
        return nil
    }
    return ProxyServerSettings(host: link.host, port: Int32(WebProxyConfiguration.port), connection: .web(secret: link.secret, path: link.path))
}

public func webProxySettingsLink(_ settings: ProxyServerSettings) -> String? {
    guard case let .web(secret, path) = settings.connection,
          let configuration = WebProxyConfiguration(host: settings.host, path: path, secret: secret) else {
        return nil
    }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "t.me"
    components.path = "/webproxy"
    components.percentEncodedQueryItems = [
        URLQueryItem(name: "server", value: webProxyPercentEncodedAddress(configuration.address)),
        URLQueryItem(name: "secret", value: WebProxyConfiguration.linkSecretString(secret, path: configuration.path))
    ]
    return components.string
}

private func webProxyPercentEncodedAddress(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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
    if isActiveWebProxy, let configuration = activeServer?.legacyWebProxyConfiguration {
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

    network.updateWebSocketTransportSettings(webSocketTransportEnabled: settings.webSocketTransportEnabled, webSocketFallbackToDirect: settings.webSocketFallbackToDirect, hasActiveProxyServer: activeServer != nil)
    network.updateProxySettings(activeServer)
    let resolvedProxySettings = activeServer?.mtProxySettings

    if (isActiveWebProxy || isActiveVlessProxy), resolvedProxySettings == nil {
        network.context.updateApiEnvironment { environment in
            network.pauseForWebProxyBootstrap()
            let current = environment?.socksProxySettings
            // An unresolved managed profile must block every MTContext consumer,
            // including workers that are not covered by the primary MTProto pause.
            // The previous endpoint may belong to a different proxy/profile.
            let blocked = ProxyServerSettings.managedBootstrapProxySettings
            if current?.isEqual(blocked) == true {
                return nil
            }
            network.dropConnectionStatus()
            return environment?.withUpdatedSocksProxySettings(blocked)
        }
        return
    }
    
    network.context.updateApiEnvironment { environment in
        let current = environment?.socksProxySettings
        // Unresolved managed profiles returned through the fail-closed path above.
        let updated = resolvedProxySettings
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

    if forceTransportReconnect, resolvedProxySettings != nil, isActiveVlessProxy {
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
    return (VlessManager.shared.stateEvents |> deliverOnMainQueue).start(next: { [weak network] state in
        guard let network = network, let settings = currentSettings() else {
            return
        }
        // When the runtime transitions to .running its loopback port is fresh and
        // MTProto's route must be rebuilt immediately — pass forceTransportReconnect
        // so the transport is torn down and re-established through the new endpoint.
        // For all other state transitions (preparing, failed, idle) a plain reapply
        // without a forced reconnect is sufficient: the bootstrap-pause logic above
        // will block new dials until the runtime is ready again.
        if case .running = state {
            applySharedProxySettingsToNetwork(settings: settings, network: network, forceTransportReconnect: true)
        } else {
            applySharedProxySettingsToNetwork(settings: settings, network: network)
        }
    })
}
