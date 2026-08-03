import Foundation
import AppBundle

/// Localized Archive-lock copy. Keys live in Localizable.strings (`ArchiveLock.*`)
/// and are also picked up by PresentationStrings on the next GenerateStrings pass.
public enum ArchiveLockLocalizedString {
    public static func string(forKey key: String) -> String {
        let bundle = getAppBundle()
        let value = NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: "", comment: "")
        if !value.isEmpty && value != key {
            return value
        }
        // Fallback for simulator / incomplete localization bundles.
        if let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: String],
           let english = dict[key] {
            return english
        }
        return key
    }
    
    public static var passwordSection: String { string(forKey: "ArchiveLock.PasswordSection") }
    public static var lockArchive: String { string(forKey: "ArchiveLock.LockArchive") }
    public static var lockNow: String { string(forKey: "ArchiveLock.LockNow") }
    public static var footer: String { string(forKey: "ArchiveLock.Footer") }
    public static var enterTitle: String { string(forKey: "ArchiveLock.EnterTitle") }
    public static var enterText: String { string(forKey: "ArchiveLock.EnterText") }
    public static var unlock: String { string(forKey: "ArchiveLock.Unlock") }
    public static var passwordPlaceholder: String { string(forKey: "ArchiveLock.PasswordPlaceholder") }
    public static var setTitle: String { string(forKey: "ArchiveLock.SetTitle") }
    public static var setText: String { string(forKey: "ArchiveLock.SetText") }
    public static var continueAction: String { string(forKey: "ArchiveLock.Continue") }
    public static var confirmTitle: String { string(forKey: "ArchiveLock.ConfirmTitle") }
    public static var confirmText: String { string(forKey: "ArchiveLock.ConfirmText") }
    public static var removeTitle: String { string(forKey: "ArchiveLock.RemoveTitle") }
    public static var removeText: String { string(forKey: "ArchiveLock.RemoveText") }
    public static var remove: String { string(forKey: "ArchiveLock.Remove") }
    public static var setPassword: String { string(forKey: "ArchiveLock.SetPassword") }
    public static var removePassword: String { string(forKey: "ArchiveLock.RemovePassword") }
    public static var lockArchiveAction: String { string(forKey: "ArchiveLock.LockArchiveAction") }
    
    public static func incorrectPassword(attemptsLeft: Int) -> String {
        return String(format: string(forKey: "ArchiveLock.IncorrectPassword"), attemptsLeft)
    }
    
    public static var passwordsDoNotMatch: String { string(forKey: "ArchiveLock.PasswordsDoNotMatch") }
}
