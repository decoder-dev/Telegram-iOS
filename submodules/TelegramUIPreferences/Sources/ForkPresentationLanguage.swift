import Foundation
import SwiftSignalKit

/// The language the app is actually presenting in.
///
/// The fork carries several of its own string tables — the Archive lock, the extras settings
/// screen, the saved-messages history screen, a few menu entries — because those strings have no
/// entry in the localisation catalogue. Every one of them picked Russian or English by reading
/// `Locale.preferredLanguages`, which is the *device* language.
///
/// Telegram carries its own language setting, independent of iOS. So a user running iOS in English
/// with Telegram set to Russian got the fork's screens in English among Russian ones, and the
/// reverse for the opposite pairing. This holds the presentation language instead, pushed here
/// from `SharedAccountContext` whenever the presentation data changes, the same way the fork's
/// other cross-module values are pushed down.
///
/// Nil until the first push, which is why every reader still falls back to its old device-language
/// lookup rather than assuming a value is present.
public enum ForkPresentationLanguage {
    private static let value = Atomic<String?>(value: nil)

    /// Two-letter code of the app's current language, or nil before the first push.
    public static var languageCode: String? {
        get {
            return self.value.with { $0 }
        }
        set {
            let _ = self.value.swap(newValue.map { String($0.prefix(2)).lowercased() })
        }
    }

    /// True when the app is presenting in a language that should get the fork's Russian strings.
    /// Falls back to the device language while the override is still nil.
    public static var prefersRussianStrings: Bool {
        let code = self.languageCode ?? String((Locale.preferredLanguages.first ?? "en").prefix(2)).lowercased()
        switch code {
        case "ru", "uk", "be":
            return true
        default:
            return false
        }
    }
}

/// Strings for the fork's WEB proxy, shared by the proxy list, the add/edit form, the settings row
/// and the proxy preview sheet.
///
/// These deliberately do not go through `presentationData.strings`: the repository only ships
/// `en.lproj/Localizable.strings`, every other locale is served by Telegram at runtime, and a
/// fork-private key is never in that server-side catalogue. Routing them through `strings` compiles
/// fine but silently falls back to English for Russian users — which is exactly what happened.
public enum ForkWebProxyStrings {
    /// Connection-type name, e.g. the "WEB Proxy" row and the add-proxy menu entry.
    public static var proxyType: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "WEB-прокси" : "WEB Proxy"
    }

    /// Field label for the tproxy-server domain the traffic is disguised as.
    public static var maskingSite: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Сайт маскировки" : "Masking site"
    }

    /// Title of the WEB proxy catalog picker sheet.
    public static var catalogTitle: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Каталог WEB-прокси" : "WEB Proxy catalog"
    }

    /// Section label for curated catalog entries in the picker sheet.
    public static var catalogPick: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Из каталога…" : "From catalog…"
    }

    /// Action that opens the manual WEB proxy form instead of a catalog entry.
    public static var catalogManual: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Ввести вручную…" : "Enter manually…"
    }
}

/// Menu titles for the fork's saved-deleted-messages screens. Same reason as
/// `ForkWebProxyStrings`: these keys are not in Telegram's localisation catalogue.
public enum ForkMessageSavingStrings {
    public static var viewDeleted: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Удалённые" : "View Deleted"
    }
}
