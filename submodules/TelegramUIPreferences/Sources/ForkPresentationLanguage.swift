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

    /// Action that opens the manual WEB proxy form instead of a catalog entry.
    public static var catalogManual: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Ввести вручную…" : "Enter manually…"
    }

    /// Footnote about calls, shown under the WEB mode in the add/edit form and as the help text
    /// of the "Use for calls" toggle when a WEB proxy is active. tgcalls cannot speak MTProto,
    /// so a WEB proxy routes calls through the sidecar's loopback SOCKS5 bridge — but only when
    /// the relay has advertised arbitrary stream targets (`docs/webproxy-socks-bridge.md`).
    /// On relays without that capability the call goes direct, which is what the note says.
    public static var callsNote: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Звонки проходят через WEB-прокси, только если релей поддерживает туннелирование звонков. Иначе во время звонка ваш IP-адрес виден серверам Telegram." : "Calls go through the WEB proxy only if the relay supports call tunneling. Otherwise your IP address is visible to Telegram servers during a call."
    }
}

/// Shared value strings for the Settings rows that summarize the active proxy mode (the
/// Data & Storage row and the peer-info settings row). Same reason as `ForkWebProxyStrings`:
/// fork-private keys are never in Telegram's localisation catalogue.
public enum ForkProxySettingsStrings {
    /// Value shown when public MTProxy auto-fetch owns the connection.
    public static var autoFetchValue: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Авто" : "Auto"
    }
}

/// Menu titles and screen copy for the fork's saved-deleted-messages feature. Same reason as
/// `ForkWebProxyStrings`: these keys are not in Telegram's localisation catalogue. The context
/// menus, the history screens and the clear action all read from here so the feature is spelled
/// identically everywhere.
public enum ForkMessageSavingStrings {
    public static var viewDeleted: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Удалённые" : "View Deleted"
    }

    public static var editHistory: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "История правок" : "Edit History"
    }

    public static var clearDeleted: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Очистить удалённые" : "Clear Deleted"
    }

    public static var noDeleted: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Пока нет сохранённых удалённых сообщений." : "No deleted messages saved yet."
    }

    public static var noEdits: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Предыдущих версий нет." : "No previous versions saved."
    }
}
