import Foundation
import Security
import SwiftSignalKit
import TelegramCore

/// What the duress passcode does before it opens the app (Extras › Protection › Duress Passcode). Every choice also
/// does what `hideSecrets` does.
public enum DuressPasscodeAction: Int32 {
    /// Hidden accounts and the locked Archive close, and Settings × 10 shows nothing until the real passcode is entered.
    case hideSecrets = 0
    /// The chosen accounts are logged out of this device.
    case logOut = 1
    /// Every account is removed from this device together with its chats, media and caches.
    case eraseAll = 2
}

/// The duress passcode: a second app passcode. Only a PBKDF2 verifier is kept, in the Keychain beside the Archive
/// passwords, together with the kind of code it is: the lock screen keypad takes only codes of the passcode's own kind.
public enum DuressPasscodeKeychain {
    private static let service = "ph.teleg.Telegrapf.DuressPasscode"

    private struct Record: Codable {
        var kind: PostboxAccessChallengeData.Kind
        var verifier: String
    }

    private static var query: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: "duress-passcode",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    private static func load() -> Record? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// The kind of the stored duress passcode, nil when none is set.
    public static func kind() -> PostboxAccessChallengeData.Kind? {
        return self.load()?.kind
    }

    @discardableResult
    public static func store(_ code: String, kind: PostboxAccessChallengeData.Kind) -> Bool {
        guard let verifier = makeLocalSecretVerifier(self.normalized(code, kind: kind)), let data = try? JSONEncoder().encode(Record(kind: kind, verifier: verifier)) else {
            return false
        }
        var query = self.query
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        } else {
            query[kSecValueData as String] = data
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
    }

    public static func matches(_ code: String, kind: PostboxAccessChallengeData.Kind) -> Bool {
        guard let record = self.load(), record.kind == kind else {
            return false
        }
        return localSecretMatchesVerifier(self.normalized(code, kind: kind), verifier: record.verifier)
    }

    @discardableResult
    public static func clear() -> Bool {
        let status = SecItemDelete(self.query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // The same normalization the app passcode gets (PasscodeKind.normalize): digits typed from another script count as
    // their ASCII value.
    private static func normalized(_ code: String, kind: PostboxAccessChallengeData.Kind) -> String {
        if kind == .alphanumeric {
            return code.precomposedStringWithCanonicalMapping
        }
        return String(code.map { character -> Character in
            if let value = character.wholeNumberValue, value < 10 {
                return Character(String(value))
            }
            return character
        })
    }
}

/// Carry out the configured duress action, then the caller unlocks the app as usual. Nothing here shows on screen.
/// Call on the main queue.
public func performDuressPasscodeAction(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Never, NoError> {
    HiddenAccountsSession.shared.blockReveal()
    ArchiveLockSession.shared.relock()

    return accountManager.transaction { transaction -> (DuressPasscodeAction, [AccountRecordId]) in
        let settings = transaction.getSharedData(ApplicationSpecificSharedDataKeys.forkExtrasSettings)?.get(ForkExtrasSettings.self) ?? .defaultSettings
        let action = DuressPasscodeAction(rawValue: settings.duressPasscodeAction) ?? .hideSecrets
        let records = transaction.getRecords()
        switch action {
        case .hideSecrets:
            return (action, [])
        case .logOut:
            let chosen = Set(settings.duressLogOutAccountIds)
            return (action, records.map(\.id).filter { chosen.contains($0.int64) })
        case .eraseAll:
            return (action, records.map(\.id))
        }
    }
    |> mapToSignal { action, accountIds -> Signal<Never, NoError> in
        if accountIds.isEmpty {
            return .complete()
        }
        // Erasing drops the records at once, so the account folders are deleted now rather than after a network
        // logout that may never come (no connection). Logging out goes the usual way and ends the sessions too.
        return combineLatest(accountIds.map { id in
            return logoutFromAccount(id: id, accountManager: accountManager, alreadyLoggedOutRemotely: action == .eraseAll)
        })
        |> ignoreValues
    }
}
