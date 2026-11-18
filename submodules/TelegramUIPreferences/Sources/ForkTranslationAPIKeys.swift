import Foundation
import Security
import SwiftSignalKit
import TelegramCore

/// The translators' API keys (Extras › Translation: DeepL, Yandex). They are the user's secrets and were kept in the
/// account manager database with the other Extras settings, which is not encrypted; they live in the Keychain now.
/// `ForkExtrasSettings.deeplApiKey`/`yandexApiKey` are only read once, to move a key stored there by an older build
/// (`migrateFromSettings`).
public enum ForkTranslationAPIKeys {
    public enum Service: String, CaseIterable {
        case deepl
        case yandex
    }

    private static let service = "ph.teleg.Telegrapf.TranslationAPIKeys"
    private static let cache = Atomic<[Service: String]?>(value: nil)

    private static func query(_ service: Service) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue,
            // Translation also runs while the app is in the background (sending a scheduled translated draft).
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }

    private static func load(_ service: Service) -> String {
        var query = self.query(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    public static func key(_ service: Service) -> String {
        if let cached = self.cache.with({ $0 }) {
            return cached[service] ?? ""
        }
        var loaded: [Service: String] = [:]
        for service in Service.allCases {
            loaded[service] = self.load(service)
        }
        let _ = self.cache.swap(loaded)
        return loaded[service] ?? ""
    }

    public static func hasKey(_ service: Service) -> Bool {
        return !self.key(service).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func setKey(_ value: String, for service: Service) {
        let query = self.query(service)
        if value.isEmpty {
            let _ = SecItemDelete(query as CFDictionary)
        } else if let data = value.data(using: .utf8) {
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
                let _ = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            } else {
                var addQuery = query
                addQuery[kSecValueData as String] = data
                let _ = SecItemAdd(addQuery as CFDictionary, nil)
            }
        }
        // Read back on the next use: the cache only ever holds what the Keychain has.
        let _ = self.cache.swap(nil)
    }

    /// Keys an older build stored in the settings database: moved into the Keychain, then cleared there. Call from the
    /// main app whenever the settings change.
    public static func migrateFromSettings(_ settings: ForkExtrasSettings, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        if settings.deeplApiKey.isEmpty && settings.yandexApiKey.isEmpty {
            return
        }
        if !settings.deeplApiKey.isEmpty {
            self.setKey(settings.deeplApiKey, for: .deepl)
        }
        if !settings.yandexApiKey.isEmpty {
            self.setKey(settings.yandexApiKey, for: .yandex)
        }
        let _ = updateForkExtrasSettingsInteractively(accountManager: accountManager, { current in
            var updated = current
            updated.deeplApiKey = ""
            updated.yandexApiKey = ""
            return updated
        }).start()
    }
}
