import Foundation
import Security
import TelegramCore
import CryptoUtils

/// Stores the Archive password hash in the system Keychain (not app preferences).
public enum ArchivePasswordKeychain {
    private static let service = "ph.teleg.Telegrapf.ArchiveLock"
    
    private static func accountKey(for peerId: EnginePeer.Id) -> String {
        return "archive-password-hash-\(peerId.toInt64())"
    }
    
    private static func query(peerId: EnginePeer.Id) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.accountKey(for: peerId),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
    
    public static func hasPassword(peerId: EnginePeer.Id) -> Bool {
        return self.loadHash(peerId: peerId) != nil
    }
    
    public static func loadHash(peerId: EnginePeer.Id) -> String? {
        var query = self.query(peerId: peerId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let hash = String(data: data, encoding: .utf8), !hash.isEmpty else {
            return nil
        }
        return hash
    }
    
    @discardableResult
    public static func storeHash(_ hash: String, peerId: EnginePeer.Id) -> Bool {
        let data = Data(hash.utf8)
        var query = self.query(peerId: peerId)
        
        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existingStatus == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        } else {
            query[kSecValueData as String] = data
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
    }
    
    @discardableResult
    public static func clear(peerId: EnginePeer.Id) -> Bool {
        let status = SecItemDelete(self.query(peerId: peerId) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    public static func matchesPassword(_ password: String, peerId: EnginePeer.Id) -> Bool {
        guard let stored = self.loadHash(peerId: peerId) else {
            return false
        }
        return stored == archivePasswordHash(password)
    }
    
    /// Move a legacy prefs-stored hash into Keychain and return whether a password exists afterwards.
    public static func migrateFromPreferencesIfNeeded(peerId: EnginePeer.Id, legacyHash: String?) -> Bool {
        if self.hasPassword(peerId: peerId) {
            return true
        }
        if let legacyHash, !legacyHash.isEmpty {
            _ = self.storeHash(legacyHash, peerId: peerId)
            return true
        }
        return false
    }
}

public func archivePasswordHash(_ password: String) -> String {
    let data = Data(password.utf8)
    let digest: Data = data.withUnsafeBytes { buffer -> Data in
        let pointer = buffer.baseAddress ?? UnsafeRawPointer(bitPattern: 0x1)!
        return CryptoSHA256(pointer, Int32(buffer.count)) as Data
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}
