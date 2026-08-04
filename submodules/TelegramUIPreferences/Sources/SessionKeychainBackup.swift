import Foundation
import Security
import TelegramCore

/// Device-local Keychain mirror of `AccountBackupData` for same-bundle E-Sign reinstalls.
/// Does NOT sync to iCloud. Changing Bundle ID loses access to these items.
public enum SessionKeychainBackup {
    private static var service: String {
        let bundle = Bundle.main.bundleIdentifier ?? "ph.teleg.Telegrapf"
        return "\(bundle).sessionsbackup"
    }
    
    public static func save(accountId: String, data: AccountBackupData) throws {
        let encoded = try JSONEncoder().encode(data)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountId
            ]
            let attrs: [String: Any] = [kSecValueData as String: encoded]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
            if updateStatus != errSecSuccess {
                throw SessionKeychainBackupError.osStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw SessionKeychainBackupError.osStatus(status)
        }
    }
    
    public static func loadAll() -> [AccountBackupData] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let items = result as? [Data] else {
            return []
        }
        return items.compactMap { try? JSONDecoder().decode(AccountBackupData.self, from: $0) }
    }
    
    public static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum SessionKeychainBackupError: Error {
    case osStatus(OSStatus)
}
