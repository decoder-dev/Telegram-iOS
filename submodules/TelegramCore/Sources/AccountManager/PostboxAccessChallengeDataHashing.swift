import Foundation
import CryptoUtils

/// PBKDF2 passcode hashing for `PostboxAccessChallengeData`.
///
/// Historically the app-lock passcode was stored as the raw string inside the (SQLCipher-encrypted)
/// postbox metadata, so anyone who recovers the database key can read the passcode directly with no
/// brute force at all. New and upgraded challenges store only a PBKDF2-HMAC-SHA256 digest — the same
/// scheme the Archive lock uses (`ArchivePasswordKeychain`): 100 000 iterations, a random 16-byte
/// salt, a 32-byte derived key, and the identical JSON blob format:
///
/// `{"salt":"<hex>","hash":"<hex>","iterations":100000}`
///
/// Legacy plaintext values continue to verify with their exact previous comparison semantics and are
/// transparently upgraded to the hashed form at the first successful unlock (see `PasscodeEntryController`
/// and `passcodeOptionsAccessController`), so no explicit migration step or forced passcode reset is needed.
///
/// Digest comparison is constant-time; the salt comes from `SystemRandomNumberGenerator`, which is a
/// cryptographically secure generator on Apple platforms.
public extension PostboxAccessChallengeData {
    /// Whether this challenge still carries the raw passcode (pre-hashing storage). A successfully
    /// verified challenge of this shape should be rewritten via `upgradedWithPasscode(_:)`.
    var isLegacyPlaintextPasscode: Bool {
        switch self {
            case .numericalPassword, .plaintextPassword:
                return true
            case .none, .numericalPasswordHash, .plaintextPasswordHash:
                return false
        }
    }

    /// Whether the entry UI should present a numeric keypad instead of the alphanumeric field.
    var isNumericalPasscode: Bool {
        switch self {
            case .numericalPassword, .numericalPasswordHash:
                return true
            case .none, .plaintextPassword, .plaintextPasswordHash:
                return false
        }
    }

    /// The digit count a numerical passcode was set with (4 or 6); selects between the digits4 and
    /// digits6 entry fields. Non-numerical challenges return 0.
    var numericalPasscodeDigitCount: Int {
        switch self {
            case let .numericalPassword(value):
                return value.count
            case let .numericalPasswordHash(_, digits):
                return Int(digits)
            case .none, .plaintextPassword, .plaintextPasswordHash:
                return 0
        }
    }

    /// Verifies a candidate passcode against this challenge.
    ///
    /// - Hashed challenges normalize numerical candidates to western digits, derive PBKDF2-HMAC-SHA256,
    ///   and compare the digests in constant time.
    /// - Legacy plaintext challenges keep the exact pre-hashing comparison semantics (the stored numerical
    ///   value is normalized to western digits before comparing; plaintext values compare as-is).
    func isValidPasscode(_ passcode: String) -> Bool {
        switch self {
            case .none:
                return true
            case let .numericalPassword(code):
                return passcode == PasscodeHashing.normalizeDigits(code)
            case let .plaintextPassword(code):
                return passcode == code
            case let .numericalPasswordHash(value, _):
                guard let blob = PasscodeHashing.decodeBlob(value) else {
                    return false
                }
                return PasscodeHashing.verify(passcode: PasscodeHashing.normalizeDigits(passcode), against: blob)
            case let .plaintextPasswordHash(value):
                guard let blob = PasscodeHashing.decodeBlob(value) else {
                    return false
                }
                return PasscodeHashing.verify(passcode: passcode, against: blob)
        }
    }

    /// The same challenge with the passcode stored as a PBKDF2 digest instead of plaintext.
    /// Returns nil for `.none` and for already-hashed challenges (nothing to upgrade), or when
    /// digest derivation fails — callers should then keep the existing stored value.
    func upgradedWithPasscode(_ passcode: String) -> PostboxAccessChallengeData? {
        switch self {
            case .numericalPassword:
                return PostboxAccessChallengeData.makeHashedPasscode(passcode: passcode, numerical: true)
            case .plaintextPassword:
                return PostboxAccessChallengeData.makeHashedPasscode(passcode: passcode, numerical: false)
            case .none, .numericalPasswordHash, .plaintextPasswordHash:
                return nil
        }
    }

    /// Builds a challenge that stores only a PBKDF2 digest of the passcode — the representation every
    /// passcode-setting code path should use. Numerical candidates are normalized to western digits
    /// before hashing so the normalization performed at verification time matches.
    ///
    /// Falls back to the legacy plaintext representation only if digest derivation fails (practically
    /// never — it requires the system CSPRNG or the KDF to fail), so that setting a passcode can never
    /// hard-fail and lock the user out of configuring the app lock.
    static func makeHashedPasscode(passcode: String, numerical: Bool) -> PostboxAccessChallengeData {
        let normalized = numerical ? PasscodeHashing.normalizeDigits(passcode) : passcode
        if let blob = PasscodeHashing.makeBlob(passcode: normalized) {
            if numerical {
                return .numericalPasswordHash(value: blob, digits: Int32(normalized.count))
            } else {
                return .plaintextPasswordHash(value: blob)
            }
        } else {
            if numerical {
                return .numericalPassword(value: passcode)
            } else {
                return .plaintextPassword(value: passcode)
            }
        }
    }
}

private enum PasscodeHashing {
    static let iterations = 100_000
    static let saltLength = 16
    static let derivedKeyLength = 32
    static let maximumStoredIterations = 500_000

    struct Blob: Codable {
        var salt: String
        var hash: String
        var iterations: Int
    }

    static func makeBlob(passcode: String) -> String? {
        var salt = Data(count: saltLength)
        var generator = SystemRandomNumberGenerator()
        salt.withUnsafeMutableBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            for index in 0..<saltLength {
                base[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            }
        }
        guard salt.count == saltLength else {
            return nil
        }
        guard let hash = digest(passcode: passcode, salt: salt, iterations: iterations) else {
            return nil
        }
        let blob = Blob(salt: hexString(salt), hash: hash, iterations: iterations)
        guard let data = try? JSONEncoder().encode(blob), let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func decodeBlob(_ stored: String) -> Blob? {
        guard let data = stored.data(using: .utf8), let blob = try? JSONDecoder().decode(Blob.self, from: data) else {
            return nil
        }
        guard blob.iterations > 0, blob.iterations <= maximumStoredIterations, !blob.salt.isEmpty, !blob.hash.isEmpty else {
            return nil
        }
        return blob
    }

    static func verify(passcode: String, against blob: Blob) -> Bool {
        guard let salt = dataFromHex(blob.salt), let expected = digest(passcode: passcode, salt: salt, iterations: blob.iterations) else {
            return false
        }
        return constantTimeEquals(expected, blob.hash)
    }

    private static func digest(passcode: String, salt: Data, iterations: Int) -> String? {
        guard iterations > 0, iterations <= maximumStoredIterations, !salt.isEmpty, salt.count <= 64 else {
            return nil
        }
        let passwordData = Data(passcode.utf8)
        guard let derived = CryptoPBKDF2HMACSHA256(passwordData, salt, Int32(iterations), Int32(derivedKeyLength)) else {
            return nil
        }
        return hexString(derived)
    }

    /// Mirrors `normalizeArabicNumeralString(_, type: .western)` from TelegramStringFormatting, which
    /// TelegramCore cannot depend on (it sits higher in the module graph). Digits only — a passcode
    /// never contains the decimal separators that helper also maps.
    static func normalizeDigits(_ string: String) -> String {
        let numerals: [(western: String, arabic: String, persian: String)] = [
            ("0", "٠", "۰"),
            ("1", "١", "۱"),
            ("2", "٢", "۲"),
            ("3", "٣", "۳"),
            ("4", "٤", "۴"),
            ("5", "٥", "۵"),
            ("6", "٦", "۶"),
            ("7", "٧", "۷"),
            ("8", "٨", "۸"),
            ("9", "٩", "۹")
        ]
        var result = string
        for numeral in numerals {
            result = result.replacingOccurrences(of: numeral.arabic, with: numeral.western)
            result = result.replacingOccurrences(of: numeral.persian, with: numeral.western)
        }
        return result
    }

    private static func hexString(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static func dataFromHex(_ hex: String) -> Data? {
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

    /// Length-independent XOR accumulation, so a wrong digest is rejected without the comparison time
    /// leaking how many leading bytes happened to match.
    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
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
}
