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

    /// Hash and store a plaintext password with PBKDF2-HMAC-SHA256 and a random per-password salt.
    @discardableResult
    public static func store(password: String, peerId: EnginePeer.Id) -> Bool {
        guard let blob = makePBKDF2StoredBlob(password: password) else {
            return false
        }
        return self.storeHash(blob, peerId: peerId)
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
        if let blob = decodePBKDF2StoredBlob(stored) {
            guard let expected = pbkdf2HexHash(password: password, saltHex: blob.salt, iterations: blob.iterations) else {
                return false
            }
            return hexStringsEqual(expected, blob.hash)
        }
        // Upgrade a hash stored before PBKDF2 (per-account SHA-256 salt, then unsalted SHA-256).
        if stored == saltedArchivePasswordHash(password, peerId: peerId) || stored == archivePasswordHash(password) {
            _ = self.store(password: password, peerId: peerId)
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

/// Per-account-salted SHA-256 (pre-PBKDF2). Kept only so `matchesPassword` can verify and
/// transparently upgrade hashes stored after the v1 salt but before PBKDF2.
public func saltedArchivePasswordHash(_ password: String, peerId: EnginePeer.Id) -> String {
    return archivePasswordHash("archive-lock-salt-v1:\(peerId.toInt64()):\(password)")
}

private let archivePasswordPBKDF2Iterations = 100_000
private let archivePasswordPBKDF2SaltLength = 16
private let archivePasswordPBKDF2DerivedKeyLength = 32

private struct ArchivePasswordPBKDF2Blob: Codable {
    var salt: String
    var hash: String
    var iterations: Int
}

private func archivePasswordHexString(_ data: Data) -> String {
    return data.map { String(format: "%02x", $0) }.joined()
}

private func archivePasswordDataFromHex(_ hex: String) -> Data? {
    let chars = Array(hex.utf8)
    guard chars.count >= 2, chars.count % 2 == 0 else {
        return nil
    }
    var data = Data(capacity: chars.count / 2)
    var index = 0
    while index < chars.count {
        func nibble(_ value: UInt8) -> UInt8? {
            switch value {
            case 48...57:
                return value - 48
            case 97...102:
                return value - 97 + 10
            case 65...70:
                return value - 65 + 10
            default:
                return nil
            }
        }
        guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else {
            return nil
        }
        data.append((high << 4) | low)
        index += 2
    }
    return data
}

private func hexStringsEqual(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var diff: UInt8 = left.count == right.count ? 0 : 1
    let count = min(left.count, right.count)
    var index = 0
    while index < count {
        diff |= left[index] ^ right[index]
        index += 1
    }
    return diff == 0
}

private func decodePBKDF2StoredBlob(_ stored: String) -> ArchivePasswordPBKDF2Blob? {
    guard let data = stored.data(using: .utf8) else {
        return nil
    }
    guard let blob = try? JSONDecoder().decode(ArchivePasswordPBKDF2Blob.self, from: data) else {
        return nil
    }
    guard blob.iterations > 0, blob.iterations <= 500_000, !blob.salt.isEmpty, !blob.hash.isEmpty else {
        return nil
    }
    return blob
}

private func pbkdf2HexHash(password: String, saltHex: String, iterations: Int) -> String? {
    guard let salt = archivePasswordDataFromHex(saltHex), !salt.isEmpty else {
        return nil
    }
    return pbkdf2HexHash(password: password, salt: salt, iterations: iterations)
}

private func pbkdf2HexHash(password: String, salt: Data, iterations: Int) -> String? {
    guard iterations > 0, iterations <= 500_000, !salt.isEmpty, salt.count <= 64 else {
        return nil
    }
    let passwordData = Data(password.utf8)
    guard let derived = CryptoPBKDF2HMACSHA256(passwordData, salt, Int32(iterations), Int32(archivePasswordPBKDF2DerivedKeyLength)) else {
        return nil
    }
    return archivePasswordHexString(derived)
}

private func makePBKDF2StoredBlob(password: String) -> String? {
    var salt = Data(count: archivePasswordPBKDF2SaltLength)
    let randomStatus = salt.withUnsafeMutableBytes { buffer -> OSStatus in
        guard let pointer = buffer.baseAddress else {
            return errSecParam
        }
        return SecRandomCopyBytes(kSecRandomDefault, archivePasswordPBKDF2SaltLength, pointer)
    }
    guard randomStatus == errSecSuccess else {
        return nil
    }
    guard let hash = pbkdf2HexHash(password: password, salt: salt, iterations: archivePasswordPBKDF2Iterations) else {
        return nil
    }
    let blob = ArchivePasswordPBKDF2Blob(salt: archivePasswordHexString(salt), hash: hash, iterations: archivePasswordPBKDF2Iterations)
    guard let data = try? JSONEncoder().encode(blob), let string = String(data: data, encoding: .utf8) else {
        return nil
    }
    return string
}
