import Foundation
import Security
import TelegramCore

/// What is left of the Keychain mirror of `AccountBackupData` (auth keys) that an Extras switch wrote until 12 Oct:
/// only its removal. The copies were never read back, outlived deleting the app and were readable after first unlock,
/// so the writer and reader are gone (31 Oct audit, C-3) and the copies an account still has are deleted.
public enum SessionKeychainBackup {
    private static var service: String {
        let bundle = Bundle.main.bundleIdentifier ?? "ph.teleg.Telegrapf"
        return "\(bundle).sessionsbackup"
    }
    
    /// Drops one account's copy. Called on logout: the auth keys of a session that no longer
    /// exists must not outlive it in the Keychain (items also survive deleting the app).
    public static func delete(accountId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    public static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
