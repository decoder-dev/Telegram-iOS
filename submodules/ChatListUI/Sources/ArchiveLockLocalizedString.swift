import Foundation
import AppBundle

/// Localized Archive-lock copy. Keys live in Localizable.strings (`ArchiveLock.*`)
/// and are also picked up by PresentationStrings on the next GenerateStrings pass.
public enum ArchiveLockLocalizedString {
    public static func get(_ key: String) -> String {
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
    
    public static var passwordSection: String { get("ArchiveLock.PasswordSection") }
    public static var lockArchive: String { get("ArchiveLock.LockArchive") }
    public static var lockNow: String { get("ArchiveLock.LockNow") }
    public static var footer: String { get("ArchiveLock.Footer") }
    public static var enterTitle: String { get("ArchiveLock.EnterTitle") }
    public static var enterText: String { get("ArchiveLock.EnterText") }
    public static var unlock: String { get("ArchiveLock.Unlock") }
    public static var passwordPlaceholder: String { get("ArchiveLock.PasswordPlaceholder") }
    public static var setTitle: String { get("ArchiveLock.SetTitle") }
    public static var setText: String { get("ArchiveLock.SetText") }
    public static var continueAction: String { get("ArchiveLock.Continue") }
    public static var confirmTitle: String { get("ArchiveLock.ConfirmTitle") }
    public static var confirmText: String { get("ArchiveLock.ConfirmText") }
    public static var removeTitle: String { get("ArchiveLock.RemoveTitle") }
    public static var removeText: String { get("ArchiveLock.RemoveText") }
    public static var remove: String { get("ArchiveLock.Remove") }
    public static var setPassword: String { get("ArchiveLock.SetPassword") }
    public static var removePassword: String { get("ArchiveLock.RemovePassword") }
    public static var lockArchiveAction: String { get("ArchiveLock.LockArchiveAction") }
    
    public static func incorrectPassword(attemptsLeft: Int) -> String {
        return String(format: get("ArchiveLock.IncorrectPassword"), attemptsLeft)
    }
    
    public static var passwordsDoNotMatch: String { get("ArchiveLock.PasswordsDoNotMatch") }
}
