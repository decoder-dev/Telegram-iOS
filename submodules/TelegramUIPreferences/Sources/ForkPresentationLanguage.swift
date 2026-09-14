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

/// Per-type proxy descriptions shown across the proxy settings UI (edit form,
/// add-proxy menu and the preview card). Every proxy type carries a short
/// explanation of what it tunnels and how calls behave, so no type is a mystery
/// label. Localized the same way as `ForkWebProxyStrings`.
public enum ForkProxyDescriptionStrings {
    public static var socks5: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Классический SOCKS5-прокси. Через него идёт трафик приложения, а звонки — если включить «Использовать для звонков»." : "A classic SOCKS5 proxy. Carries app traffic; calls too when 'Use for calls' is enabled."
    }

    public static var mtp: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Прокси собственного протокола Telegram. Помогает там, где SOCKS5 и HTTP заблокированы. Звонки через него не маршрутизируются." : "Telegram's own proxy protocol. Works where SOCKS5 and HTTP are blocked. Calls are not routed through it."
    }

    public static var web: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Трафик маскируется под обычный HTTPS к сайту-маскировщику и проходит через WebView-мост. Обходит DPI-блокировки." : "Traffic is disguised as plain HTTPS to a masking site and goes through a WebView bridge. Works around DPI blocks."
    }

    public static var vless: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "VLESS со встроенным Xray: вставьте ссылку vless:// — весь трафик приложения пойдёт через туннель (TLS/Reality), звонки — без утечек IP." : "VLESS with an embedded Xray core: paste a vless:// link and all app traffic goes through the tunnel (TLS/Reality); calls never leak your IP."
    }

    /// Short one-liners for the add-proxy action sheet.
    public enum Menu {
        public static var socks5: String {
            return ForkPresentationLanguage.prefersRussianStrings ? "Универсальный, нужен сервер и порт" : "Universal; needs a server and port"
        }
        public static var mtp: String {
            return ForkPresentationLanguage.prefersRussianStrings ? "Протокол Telegram, устойчив к блокировкам" : "Telegram protocol, block-resistant"
        }
        public static var web: String {
            return ForkPresentationLanguage.prefersRussianStrings ? "Маскировка под HTTPS-трафик" : "Disguised as HTTPS traffic"
        }
        public static var vless: String {
            return ForkPresentationLanguage.prefersRussianStrings ? "Туннель со встроенным Xray (Reality)" : "Tunnel with an embedded Xray core (Reality)"
        }
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
