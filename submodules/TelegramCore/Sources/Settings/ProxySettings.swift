import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

public func updateProxySettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (ProxySettings) -> ProxySettings) -> Signal<Bool, NoError> {
    return accountManager.transaction { transaction -> Bool in
        return updateProxySettingsInteractively(transaction: transaction, f)
    }
}

extension ProxyServerSettings {
    var mtProxySettings: MTSocksProxySettings {
        switch self.connection {
            case let .socks5(username, password):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: username, password: password, secret: nil)
            case let .mtp(secret):
                return MTSocksProxySettings(ip: self.host, port: UInt16(clamping: self.port), username: nil, password: nil, secret: secret)
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
    let updated = settings.effectiveActiveServer.flatMap { activeServer -> MTSocksProxySettings? in
        return activeServer.mtProxySettings
    }
    network.context.updateApiEnvironment { environment in
        let current = environment?.socksProxySettings
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
