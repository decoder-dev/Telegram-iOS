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

    /// Hash and store a plaintext password, salted per-account so a Keychain/backup
    /// extraction can't be attacked with one precomputed table shared across accounts.
    @discardableResult
    public static func store(password: String, peerId: EnginePeer.Id) -> Bool {
        return self.storeHash(saltedArchivePasswordHash(password, peerId: peerId), peerId: peerId)
    }

    @discardableResult
    public static func clear(peerId: EnginePeer.Id) -> Bool {
        let status = SecItemDelete(self.query(peerId: peerId) as CFDictionary)
        self.clearFailureState(peerId: peerId)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func matchesPassword(_ password: String, peerId: EnginePeer.Id) -> Bool {
        guard let stored = self.loadHash(peerId: peerId) else {
            return false
        }
        if stored == saltedArchivePasswordHash(password, peerId: peerId) {
            return true
        }
        // Upgrade a hash stored before per-account salting was introduced.
        if stored == archivePasswordHash(password) {
            _ = self.storeHash(saltedArchivePasswordHash(password, peerId: peerId), peerId: peerId)
            return true
        }
        return false
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

    // MARK: - Brute-force throttling
    //
    // `attemptsLeft` in the password-entry UI is a local variable that resets to 5 the
    // moment the alert is dismissed and reopened, so it needs Keychain-backed state to
    // mean anything as an actual guard against repeated guessing.

    private static let failureService = "ph.teleg.Telegrapf.ArchiveLockFailures"

    // Guards the failure-state read-modify-write below. `recordFailure` reads the current
    // count, increments it, and writes it back — without this lock, two concurrent calls
    // (e.g. a rapid double-submit of the password alert) can both read the same count and
    // one increment is lost, silently weakening the brute-force cooldown. Also serializes
    // against `clearFailureState`/`clear(peerId:)` so a concurrent clear can't race a
    // failure recording and leave a stale or resurrected count.
    private static let failureLock = NSLock()

    private struct FailureState: Codable {
        var count: Int
        var lastFailureTimestamp: Double
    }

    private static func failureQuery(peerId: EnginePeer.Id) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.failureService,
            kSecAttrAccount as String: self.accountKey(for: peerId),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    private static func loadFailureState(peerId: EnginePeer.Id) -> FailureState? {
        var query = self.failureQuery(peerId: peerId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(FailureState.self, from: data)
    }

    private static func storeFailureState(_ state: FailureState, peerId: EnginePeer.Id) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        var query = self.failureQuery(peerId: peerId)
        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existingStatus == errSecSuccess {
            _ = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            query[kSecValueData as String] = data
            _ = SecItemAdd(query as CFDictionary, nil)
        }
    }

    /// Escalating cooldown: 0 for the first few misses, then a growing delay per extra miss.
    private static func cooldown(forFailureCount count: Int) -> Double {
        switch count {
        case ..<5:
            return 0
        default:
            return min(300, 5 * pow(2.0, Double(count - 5)))
        }
    }

    /// Seconds still remaining before another attempt is allowed (0 if none).
    public static func remainingCooldown(peerId: EnginePeer.Id) -> Double {
        self.failureLock.lock()
        defer { self.failureLock.unlock() }
        guard let state = self.loadFailureState(peerId: peerId) else {
            return 0
        }
        let cooldown = self.cooldown(forFailureCount: state.count)
        guard cooldown > 0 else {
            return 0
        }
        let elapsed = Date().timeIntervalSince1970 - state.lastFailureTimestamp
        return max(0, cooldown - elapsed)
    }

    /// Total recorded failures since the last success (persists across dialog dismissal).
    public static func failureCount(peerId: EnginePeer.Id) -> Int {
        self.failureLock.lock()
        defer { self.failureLock.unlock() }
        return self.loadFailureState(peerId: peerId)?.count ?? 0
    }

    public static func recordFailure(peerId: EnginePeer.Id) {
        self.failureLock.lock()
        defer { self.failureLock.unlock() }
        let previous = self.loadFailureState(peerId: peerId)?.count ?? 0
        self.storeFailureState(FailureState(count: previous + 1, lastFailureTimestamp: Date().timeIntervalSince1970), peerId: peerId)
    }

    public static func clearFailureState(peerId: EnginePeer.Id) {
        self.failureLock.lock()
        defer { self.failureLock.unlock() }
        _ = SecItemDelete(self.failureQuery(peerId: peerId) as CFDictionary)
    }
}

/// Legacy (pre-salt) hash, kept only to (a) verify passwords stored before the salted
/// scheme was introduced and transparently upgrade them, and (b) decode very old
/// plaintext-password preferences during migration.
public func archivePasswordHash(_ password: String) -> String {
    let data = Data(password.utf8)
    let digest: Data = data.withUnsafeBytes { buffer -> Data in
        let pointer = buffer.baseAddress ?? UnsafeRawPointer(bitPattern: 0x1)!
        return CryptoSHA256(pointer, Int32(buffer.count)) as Data
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// Per-account-salted password hash: prevents one precomputed table from working against
/// every account's stored hash if the Keychain is ever extracted (jailbreak/backup exploit).
public func saltedArchivePasswordHash(_ password: String, peerId: EnginePeer.Id) -> String {
    return archivePasswordHash("archive-lock-salt-v1:\(peerId.toInt64()):\(password)")
}
