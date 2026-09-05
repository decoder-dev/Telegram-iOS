import Foundation
import AppBundle
import TelegramUIPreferences

/// Localized Archive-lock copy.
///
/// Telegram's in-app language often differs from the main bundle locale
/// (`NSLocalizedString` stays on English), and from the device language too. Prefer an explicit
/// RU/EN table keyed by the app's own presentation language, then by the device's, then fall back
/// to `en.lproj`.
public enum ArchiveLockLocalizedString {
    private static let translations: [String: [String: String]] = [
        "en": [
            "ArchiveLock.PasswordSection": "PASSWORD",
            "ArchiveLock.LockArchive": "Lock Archive",
            "ArchiveLock.LockNow": "Lock Now",
            "ArchiveLock.Footer": "When enabled, opening Archive requires a password. Archived chats are muted and hidden from folders, search, and frequent contacts.",
            "ArchiveLock.EnterTitle": "Archive Password",
            "ArchiveLock.EnterText": "Enter the password to open Archive",
            "ArchiveLock.Unlock": "Unlock",
            "ArchiveLock.PasswordPlaceholder": "Password",
            "ArchiveLock.SetTitle": "Set Archive Password",
            "ArchiveLock.SetText": "Archived chats stay muted and hidden from folders",
            "ArchiveLock.Continue": "Continue",
            "ArchiveLock.ConfirmTitle": "Confirm Password",
            "ArchiveLock.ConfirmText": "Re-enter the Archive password",
            "ArchiveLock.RemoveTitle": "Remove Archive Password",
            "ArchiveLock.RemoveText": "Enter the current password to disable the lock",
            "ArchiveLock.Remove": "Remove",
            "ArchiveLock.IncorrectPassword": "Incorrect password. %d attempts left.",
            "ArchiveLock.PasswordsDoNotMatch": "Passwords did not match. Try again.",
            "ArchiveLock.SetPassword": "Set Archive Password",
            "ArchiveLock.RemovePassword": "Remove Archive Password",
            "ArchiveLock.LockArchiveAction": "Lock Archive",
            "ArchiveLock.ChangePassword": "Change Password",
            "ArchiveLock.ChangeCurrentText": "Enter the current password to change it",
            "ArchiveLock.PasswordChanged": "Archive password changed",
            "ArchiveLock.TooManyAttempts": "Too many incorrect attempts. Try again in %d s.",
            "ArchiveLock.BiometricReason": "Unlock Archive",
            "ArchiveLock.UseFaceId": "Unlock with Face ID",
            "ArchiveLock.UseTouchId": "Unlock with Touch ID",
        ],
        "ru": [
            "ArchiveLock.PasswordSection": "ПАРОЛЬ",
            "ArchiveLock.LockArchive": "Блокировать архив",
            "ArchiveLock.LockNow": "Заблокировать сейчас",
            "ArchiveLock.Footer": "При включении для открытия архива нужен пароль. Архивированные чаты без звука и скрыты из папок, поиска и частых контактов.",
            "ArchiveLock.EnterTitle": "Пароль архива",
            "ArchiveLock.EnterText": "Введите пароль, чтобы открыть архив",
            "ArchiveLock.Unlock": "Разблокировать",
            "ArchiveLock.PasswordPlaceholder": "Пароль",
            "ArchiveLock.SetTitle": "Задать пароль архива",
            "ArchiveLock.SetText": "Архивированные чаты остаются без звука и скрыты из папок",
            "ArchiveLock.Continue": "Продолжить",
            "ArchiveLock.ConfirmTitle": "Подтвердите пароль",
            "ArchiveLock.ConfirmText": "Введите пароль архива ещё раз",
            "ArchiveLock.RemoveTitle": "Удалить пароль архива",
            "ArchiveLock.RemoveText": "Введите текущий пароль, чтобы отключить блокировку",
            "ArchiveLock.Remove": "Удалить",
            "ArchiveLock.IncorrectPassword": "Неверный пароль. Осталось попыток: %d.",
            "ArchiveLock.PasswordsDoNotMatch": "Пароли не совпадают. Попробуйте снова.",
            "ArchiveLock.SetPassword": "Задать пароль архива",
            "ArchiveLock.RemovePassword": "Удалить пароль архива",
            "ArchiveLock.LockArchiveAction": "Заблокировать архив",
            "ArchiveLock.ChangePassword": "Изменить пароль",
            "ArchiveLock.ChangeCurrentText": "Введите текущий пароль, чтобы изменить его",
            "ArchiveLock.PasswordChanged": "Пароль архива изменён",
            "ArchiveLock.TooManyAttempts": "Слишком много неверных попыток. Повторите через %d с.",
            "ArchiveLock.BiometricReason": "Разблокировать архив",
            "ArchiveLock.UseFaceId": "Разблокировать Face ID",
            "ArchiveLock.UseTouchId": "Разблокировать Touch ID",
        ],
    ]
    
    private static func languageCode() -> String {
        // The app's language first — Telegram's own setting is independent of the device's.
        // The device list stays as the fallback for the window before the first push. The fork
        // serves Russian to ru/uk/be everywhere else (`ForkPresentationLanguage`), so the table
        // follows the same rule instead of dropping those users to English mid-screen.
        if let appLanguage = ForkPresentationLanguage.languageCode {
            switch appLanguage {
                case "ru", "uk", "be":
                    return "ru"
                case "en":
                    return "en"
                default:
                    break
            }
        }
        let candidates = Locale.preferredLanguages + Bundle.main.preferredLocalizations
        for candidate in candidates {
            let code = String(candidate.prefix(2)).lowercased()
            if code == "ru" || code == "uk" || code == "be" {
                return "ru"
            }
            if code == "en" {
                return "en"
            }
        }
        return "en"
    }
    
    public static func string(forKey key: String) -> String {
        let code = languageCode()
        if let value = translations[code]?[key] {
            return value
        }
        if let value = translations["en"]?[key] {
            return value
        }
        let bundle = getAppBundle()
        let value = NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: "", comment: "")
        if !value.isEmpty && value != key {
            return value
        }
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
    public static var changePassword: String { string(forKey: "ArchiveLock.ChangePassword") }
    public static var changeCurrentText: String { string(forKey: "ArchiveLock.ChangeCurrentText") }
    public static var passwordChanged: String { string(forKey: "ArchiveLock.PasswordChanged") }
    public static var biometricReason: String { string(forKey: "ArchiveLock.BiometricReason") }
    public static var useFaceId: String { string(forKey: "ArchiveLock.UseFaceId") }
    public static var useTouchId: String { string(forKey: "ArchiveLock.UseTouchId") }

    public static func incorrectPassword(attemptsLeft: Int) -> String {
        return String(format: string(forKey: "ArchiveLock.IncorrectPassword"), attemptsLeft)
    }

    public static func tooManyAttempts(seconds: Int) -> String {
        return String(format: string(forKey: "ArchiveLock.TooManyAttempts"), seconds)
    }

    public static var passwordsDoNotMatch: String { string(forKey: "ArchiveLock.PasswordsDoNotMatch") }
}
