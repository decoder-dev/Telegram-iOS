import Foundation
import TelegramUIPreferences

/// Bilingual strings for Developer Mode / Debug screens.
///
/// These titles never lived in the localisation catalogue (upstream Debug was English-only).
/// Follow the same app-language rule as the rest of the fork: Telegram's language setting,
/// not the device's (`ForkPresentationLanguage`).
enum DebugLocalizedString {
    private static let translations: [String: [String: String]] = [
        "en": [
            "title": "Debug",
            "accountsTitle": "Accounts",
            "loginAnotherAccount": "Login to another account",
            "production": "Production",
            "test": "Test",
            "simulateStickersImport": "Simulate Stickers Import",
            "sendLogs40": "Send Logs (Up to 40 MB)",
            "sendLatestLogs4": "Send Latest Logs (Up to 4 MB)",
            "sendShareLogs40": "Send Share Logs (Up to 40 MB)",
            "sendGroupCallLogs40": "Send Group Call Logs (Up to 40 MB)",
            "sendNotificationLogs40": "Send Notification Logs (Up to 40 MB)",
            "sendCriticalLogs": "Send Critical Logs",
            "sendAllLogs": "Send All Logs",
            "sendStorageStats": "Send Storage Stats",
            "viaTelegram": "Via Telegram",
            "viaEmail": "Via Email",
            "accounts": "Accounts",
            "logToFile": "Log to File",
            "logToConsole": "Log to Console",
            "removeSensitiveData": "Remove Sensitive Data",
            "keepChatStack": "Keep Chat Stack",
            "skipReadHistory": "Skip read history",
            "showTyping": "Show Typing",
            "ratingDebug": "Rating Debug",
            "crashWhenSlow": "Crash when slow",
            "crashOnMemoryPressure": "Crash on memory pressure",
            "clearTips": "Clear Tips",
            "logLanguageRecognition": "Log Language Recognition",
            "resetTranslationStates": "Reset Translation States",
            "resetNotifications": "Reset Notifications",
            "restartAppNow": "Now restart the app",
            "ok": "OK",
            "crash": "Crash",
            "reloadSavedMessages": "Reload Saved Messages",
            "clearDatabase": "Clear Database",
            "clearDatabaseAndCache": "Clear Database and Cache",
            "secretChatsLost": "All secret chats will be lost.",
            "resetHoles": "Reset Holes",
            "resetTagHoles": "Reset Tag Holes",
            "reindexUnread": "Reindex Unread Counters",
            "resetCacheIndex": "Reset Cache Index [!]",
            "reindexCache": "Reindex Cache",
            "resetBiometrics": "Reset Biometrics Data",
            "allowWebViewInspection": "Allow Web View Inspection",
            "clearWebViewCache": "Clear Web View Cache",
            "optimizeDatabase": "Optimize Database",
            "mediaPreviewUpdated": "Media Preview (Updated)",
            "knockoutWallpaper": "Knockout Wallpaper",
            "experimentalCompatibility": "Experimental Compatibility",
            "debugDataDisplay": "Debug Data Display",
            "fakeGlass": "Fake glass",
            "forceClearGlass": "Force clear glass",
            "debugRipple": "Debug Ripple",
            "forceTextFieldV2": "Force Text Field v2",
            "inlineUI": "Inline UI",
            "forumTabsDebug": "Forum Tabs Debug",
            "effectOverrides": "Effect Overrides",
            "compressedEmojiCache": "Compressed Emoji Cache",
            "jpegX": "JPEG X",
            "checkSerializedData": "Check Serialized Data",
            "enableQuickReaction": "Enable Quick Reaction",
            "liveStreamV2": "Live Stream V2",
            "osMicMute": "[WIP] OS mic mute",
            "playerV2": "PlayerV2",
            "devRequests": "DevRequests",
            "enableUpdates": "Enable Updates",
            "pwa": "PWA",
            "localTranslation": "Local Translation",
            "videoCroppingOptimization": "Video Cropping Optimization",
            "networkXRestart": "Network X [Restart App]",
            "downloadXRestart": "Download X [Restart App]",
            "restorePurchases": "Restore Purchases",
            "done": "Done",
            "failed": "Failed",
            "disableReloginTokens": "Disable Relogin Tokens",
            "hostPrefix": "Host:",
        ],
        "ru": [
            "title": "Отладка",
            "accountsTitle": "Аккаунты",
            "loginAnotherAccount": "Войти в другой аккаунт",
            "production": "Production",
            "test": "Test",
            "simulateStickersImport": "Симулировать импорт стикеров",
            "sendLogs40": "Отправить логи (до 40 МБ)",
            "sendLatestLogs4": "Отправить последние логи (до 4 МБ)",
            "sendShareLogs40": "Отправить логи Share (до 40 МБ)",
            "sendGroupCallLogs40": "Отправить логи звонков (до 40 МБ)",
            "sendNotificationLogs40": "Отправить логи уведомлений (до 40 МБ)",
            "sendCriticalLogs": "Отправить критические логи",
            "sendAllLogs": "Отправить все логи",
            "sendStorageStats": "Отправить статистику хранилища",
            "viaTelegram": "Через Telegram",
            "viaEmail": "По email",
            "accounts": "Аккаунты",
            "logToFile": "Лог в файл",
            "logToConsole": "Лог в консоль",
            "removeSensitiveData": "Убирать чувствительные данные",
            "keepChatStack": "Сохранять стек чатов",
            "skipReadHistory": "Не читать историю",
            "showTyping": "Показывать набор",
            "ratingDebug": "Отладка рейтинга",
            "crashWhenSlow": "Краш при тормозах",
            "crashOnMemoryPressure": "Краш при нехватке памяти",
            "clearTips": "Сбросить подсказки",
            "logLanguageRecognition": "Лог распознавания языка",
            "resetTranslationStates": "Сбросить состояния перевода",
            "resetNotifications": "Сбросить уведомления",
            "restartAppNow": "Теперь перезапустите приложение",
            "ok": "OK",
            "crash": "Краш",
            "reloadSavedMessages": "Перезагрузить Избранное",
            "clearDatabase": "Очистить базу",
            "clearDatabaseAndCache": "Очистить базу и кэш",
            "secretChatsLost": "Все секретные чаты будут потеряны.",
            "resetHoles": "Сбросить дыры истории",
            "resetTagHoles": "Сбросить дыры тегов",
            "reindexUnread": "Пересчитать непрочитанные",
            "resetCacheIndex": "Сбросить индекс кэша [!]",
            "reindexCache": "Переиндексировать кэш",
            "resetBiometrics": "Сбросить биометрию",
            "allowWebViewInspection": "Разрешить инспекцию WebView",
            "clearWebViewCache": "Очистить кэш WebView",
            "optimizeDatabase": "Оптимизировать базу",
            "mediaPreviewUpdated": "Превью медиа (обновлённое)",
            "knockoutWallpaper": "Knockout обои",
            "experimentalCompatibility": "Экспериментальная совместимость",
            "debugDataDisplay": "Показ отладочных данных",
            "fakeGlass": "Фейковый glass",
            "forceClearGlass": "Принудительно clear glass",
            "debugRipple": "Отладка ripple",
            "forceTextFieldV2": "Форсировать поле ввода v2",
            "inlineUI": "Inline UI",
            "forumTabsDebug": "Отладка вкладок форума",
            "effectOverrides": "Переопределение эффектов",
            "compressedEmojiCache": "Сжатый кэш эмодзи",
            "jpegX": "JPEG X",
            "checkSerializedData": "Проверять сериализованные данные",
            "enableQuickReaction": "Быстрая реакция",
            "liveStreamV2": "Live Stream V2",
            "osMicMute": "[WIP] Mute микрофона ОС",
            "playerV2": "PlayerV2",
            "devRequests": "DevRequests",
            "enableUpdates": "Включить обновления",
            "pwa": "PWA",
            "localTranslation": "Локальный перевод",
            "videoCroppingOptimization": "Оптимизация кропа видео",
            "networkXRestart": "Network X [перезапуск]",
            "downloadXRestart": "Download X [перезапуск]",
            "restorePurchases": "Восстановить покупки",
            "done": "Готово",
            "failed": "Ошибка",
            "disableReloginTokens": "Отключить Relogin Tokens",
            "hostPrefix": "Хост:",
        ],
    ]

    private static func languageCode() -> String {
        if ForkPresentationLanguage.prefersRussianStrings {
            return "ru"
        }
        return "en"
    }

    static func string(_ key: String) -> String {
        let code = languageCode()
        if let value = translations[code]?[key] {
            return value
        }
        return translations["en"]?[key] ?? key
    }

    static var title: String { string("title") }
    static var accountsTitle: String { string("accountsTitle") }
    static var loginAnotherAccount: String { string("loginAnotherAccount") }
    static var production: String { string("production") }
    static var test: String { string("test") }
    static var simulateStickersImport: String { string("simulateStickersImport") }
    static var sendLogs40: String { string("sendLogs40") }
    static var sendLatestLogs4: String { string("sendLatestLogs4") }
    static var sendShareLogs40: String { string("sendShareLogs40") }
    static var sendGroupCallLogs40: String { string("sendGroupCallLogs40") }
    static var sendNotificationLogs40: String { string("sendNotificationLogs40") }
    static var sendCriticalLogs: String { string("sendCriticalLogs") }
    static var sendAllLogs: String { string("sendAllLogs") }
    static var sendStorageStats: String { string("sendStorageStats") }
    static var viaTelegram: String { string("viaTelegram") }
    static var viaEmail: String { string("viaEmail") }
    static var accounts: String { string("accounts") }
    static var logToFile: String { string("logToFile") }
    static var logToConsole: String { string("logToConsole") }
    static var removeSensitiveData: String { string("removeSensitiveData") }
    static var keepChatStack: String { string("keepChatStack") }
    static var skipReadHistory: String { string("skipReadHistory") }
    static var showTyping: String { string("showTyping") }
    static var ratingDebug: String { string("ratingDebug") }
    static var crashWhenSlow: String { string("crashWhenSlow") }
    static var crashOnMemoryPressure: String { string("crashOnMemoryPressure") }
    static var clearTips: String { string("clearTips") }
    static var logLanguageRecognition: String { string("logLanguageRecognition") }
    static var resetTranslationStates: String { string("resetTranslationStates") }
    static var resetNotifications: String { string("resetNotifications") }
    static var restartAppNow: String { string("restartAppNow") }
    static var ok: String { string("ok") }
    static var crash: String { string("crash") }
    static var reloadSavedMessages: String { string("reloadSavedMessages") }
    static var clearDatabase: String { string("clearDatabase") }
    static var clearDatabaseAndCache: String { string("clearDatabaseAndCache") }
    static var secretChatsLost: String { string("secretChatsLost") }
    static var resetHoles: String { string("resetHoles") }
    static var resetTagHoles: String { string("resetTagHoles") }
    static var reindexUnread: String { string("reindexUnread") }
    static var resetCacheIndex: String { string("resetCacheIndex") }
    static var reindexCache: String { string("reindexCache") }
    static var resetBiometrics: String { string("resetBiometrics") }
    static var allowWebViewInspection: String { string("allowWebViewInspection") }
    static var clearWebViewCache: String { string("clearWebViewCache") }
    static var optimizeDatabase: String { string("optimizeDatabase") }
    static var mediaPreviewUpdated: String { string("mediaPreviewUpdated") }
    static var knockoutWallpaper: String { string("knockoutWallpaper") }
    static var experimentalCompatibility: String { string("experimentalCompatibility") }
    static var debugDataDisplay: String { string("debugDataDisplay") }
    static var fakeGlass: String { string("fakeGlass") }
    static var forceClearGlass: String { string("forceClearGlass") }
    static var debugRipple: String { string("debugRipple") }
    static var forceTextFieldV2: String { string("forceTextFieldV2") }
    static var inlineUI: String { string("inlineUI") }
    static var forumTabsDebug: String { string("forumTabsDebug") }
    static var effectOverrides: String { string("effectOverrides") }
    static var compressedEmojiCache: String { string("compressedEmojiCache") }
    static var jpegX: String { string("jpegX") }
    static var checkSerializedData: String { string("checkSerializedData") }
    static var enableQuickReaction: String { string("enableQuickReaction") }
    static var liveStreamV2: String { string("liveStreamV2") }
    static var osMicMute: String { string("osMicMute") }
    static var playerV2: String { string("playerV2") }
    static var devRequests: String { string("devRequests") }
    static var enableUpdates: String { string("enableUpdates") }
    static var pwa: String { string("pwa") }
    static var localTranslation: String { string("localTranslation") }
    static var videoCroppingOptimization: String { string("videoCroppingOptimization") }
    static var networkXRestart: String { string("networkXRestart") }
    static var downloadXRestart: String { string("downloadXRestart") }
    static var restorePurchases: String { string("restorePurchases") }
    static var done: String { string("done") }
    static var failed: String { string("failed") }
    static var disableReloginTokens: String { string("disableReloginTokens") }
    static var hostPrefix: String { string("hostPrefix") }
}
