import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum ForkExtrasLocalizedString {
    private static let translations: [String: [String: String]] = [
        "en": [
            "ForkExtras.Title": "Extras",
            "ForkExtras.GhostDontReadMessages": "Don't Read Messages",
            "ForkExtras.GhostDontReadStories": "Don't Read Stories",
            "ForkExtras.GhostDontSendOnline": "Don't Send Online",
            "ForkExtras.GhostDontSendTyping": "Don't Send Typing",
            "ForkExtras.GhostGoOfflineAutomatically": "Go Offline Automatically",
            "ForkExtras.GhostGoOfflineAutomaticallyFooter": "After briefly appearing online, immediately go offline again.",
            "ForkExtras.GhostReadOnInteract": "Read on Interact",
            "ForkExtras.GhostReadOnInteractFooter": "When Don't Read Messages is on, mark chats read and blink online after you send a message.",
            "ForkExtras.GhostAlertBeforeOpeningStory": "Alert Before Opening Story",
            "ForkExtras.GhostAlertBeforeOpeningStoryFooter": "Ask before opening any story. Tap outside to dismiss without opening.",
            "ForkExtras.GhostModeFooter": "AyuGram-style Ghost Mode. Each option can be toggled independently.",
            "ForkExtras.InstantPasscode": "Instant Passcode Lock",
            "ForkExtras.InstantPasscodeFooter": "Lock the app as soon as it leaves the foreground.",
            "ForkExtras.HideMentions": "Hide Mention Notifications",
            "ForkExtras.HideMentionsFooter": "Suppress push notifications for mentions.",
            "ForkExtras.HidePinned": "Hide Pinned Notifications",
            "ForkExtras.HidePinnedFooter": "Suppress push notifications for pinned messages.",
            "ForkExtras.SessionBackup": "Keychain Session Backup",
            "ForkExtras.SessionBackupFooter": "Mirror account session data to the device Keychain for same-bundle reinstalls.",
            "ForkExtras.CompactChatList": "Compact Chat List",
            "ForkExtras.CompactMessagePreview": "Compact Message Preview",
            "ForkExtras.CompactFolderNames": "Compact Folder Names",
            "ForkExtras.UIDensityFooter": "Reduce row heights, preview line count, and folder tab label size.",
            "ForkExtras.HideReactionsBar": "Hide Reactions",
            "ForkExtras.HideReactionsBarFooter": "Hide the reaction bar under messages.",
            "ForkExtras.ShowDC": "Show Data Center & Registration Date",
            "ForkExtras.ShowProfileId": "Show Profile ID",
            "ForkExtras.PrivacyFooter": "Add extra diagnostic rows to profile screens.",
            "ForkExtras.AccentSaturation": "Accent Color Saturation",
            "ForkExtras.ConfirmBeforeCall": "Confirm Before Calling",
            "ForkExtras.SendWithReturnKey": "Send With Return Key",
            "ForkExtras.SendWithReturnKeyFooter": "Tapping Return on the keyboard sends the message instead of adding a new line.",
            "ForkExtras.ForceBuiltInMic": "Force Built-in Microphone",
            "ForkExtras.ForceBuiltInMicFooter": "Use the device's built-in microphone instead of a connected Bluetooth device for calls and voice messages.",
            "ForkExtras.CallsFooter": "Ask for confirmation before dialing a call.",
            "ForkExtras.TranslationBackend": "Translation",
            "ForkExtras.TranscriptionBackend": "Voice Transcription",
            "ForkExtras.TranslationFooter": "Choose an alternative translation or voice-transcription engine, independent of Telegram Premium.",
            "ForkExtras.ScrollToNextChat": "Swipe to Next Chat",
            "ForkExtras.ScrollToNextChatFooter": "Swiping up on the last message jumps to the next unread chat or topic.",
            "ForkExtras.BackendDefault": "Default",
            "ForkExtras.BackendSystem": "System (Apple)",
            "ForkExtras.BackendApple": "On-Device (Apple)",
            "ForkExtras.SaveDeletedMessages": "Save Deleted Messages",
            "ForkExtras.SaveDeletedMessagesFooter": "Keep deleted messages (yours and others), including one-time media, visible in chat (🧹). Also under View Deleted.",
            "ForkExtras.SaveMessagesHistory": "Save Edit History",
            "ForkExtras.SaveMessagesHistoryFooter": "Keep previous text when a message is edited. Open Edit History from the message menu.",
            "ForkExtras.SaveMedia": "Save Media",
            "ForkExtras.SaveMediaFooter": "Copy attachments into local Saved Attachments on delete/TTL (own and others; AyuGram Android parity).",
            "ForkExtras.SaveForBots": "Also Save Bot Messages",
            "ForkExtras.AyuForward": "AyuForward",
            "ForkExtras.AyuForwardFooter": "Forward from noforwards channels and deleted messages by re-uploading media without an author (AyuGram Android).",
            "ForkExtras.HideAds": "Hide Ads",
            "ForkExtras.HideAdsFooter": "Hide sponsored and recommended messages in chats (AyuGram Message Filters).",
            "ForkExtras.HideBlockedMessages": "Hide Blocked Users",
            "ForkExtras.HideBlockedMessagesFooter": "Hide messages and typing from users you've blocked.",
            "ForkExtras.ViewDeleted": "View Deleted",
            "ForkExtras.EditHistory": "Edit History",
            "ForkExtras.ClearDeleted": "Clear Deleted",
            "ForkExtras.NoDeleted": "No deleted messages saved yet.",
            "ForkExtras.NoEdits": "No previous versions saved.",
        ],
        "ru": [
            "ForkExtras.Title": "Дополнительно",
            "ForkExtras.GhostDontReadMessages": "Не читать сообщения",
            "ForkExtras.GhostDontReadStories": "Не читать истории",
            "ForkExtras.GhostDontSendOnline": "Не отправлять онлайн",
            "ForkExtras.GhostDontSendTyping": "Не отправлять набор",
            "ForkExtras.GhostGoOfflineAutomatically": "Сразу уходить в офлайн",
            "ForkExtras.GhostGoOfflineAutomaticallyFooter": "После короткого появления онлайн сразу снова уходить в офлайн.",
            "ForkExtras.GhostReadOnInteract": "Читать при взаимодействии",
            "ForkExtras.GhostReadOnInteractFooter": "Если включено «Не читать сообщения», отмечать прочтение и кратко показывать онлайн после отправки.",
            "ForkExtras.GhostAlertBeforeOpeningStory": "Спрашивать перед открытием истории",
            "ForkExtras.GhostAlertBeforeOpeningStoryFooter": "Показывать предупреждение перед открытием истории. Нажатие снаружи закрывает без открытия.",
            "ForkExtras.GhostModeFooter": "Режим призрака в стиле AyuGram. Каждую опцию можно включать отдельно.",
            "ForkExtras.InstantPasscode": "Мгновенная блокировка",
            "ForkExtras.InstantPasscodeFooter": "Блокировать приложение сразу при уходе в фон.",
            "ForkExtras.HideMentions": "Скрыть уведомления об упоминаниях",
            "ForkExtras.HideMentionsFooter": "Не показывать push-уведомления об упоминаниях.",
            "ForkExtras.HidePinned": "Скрыть уведомления о закреплении",
            "ForkExtras.HidePinnedFooter": "Не показывать push-уведомления о закреплённых сообщениях.",
            "ForkExtras.SessionBackup": "Резерв сессии в Keychain",
            "ForkExtras.SessionBackupFooter": "Дублировать данные сессии в Keychain для переустановки с тем же Bundle ID.",
            "ForkExtras.CompactChatList": "Компактный список чатов",
            "ForkExtras.CompactMessagePreview": "Компактное превью сообщений",
            "ForkExtras.CompactFolderNames": "Компактные названия папок",
            "ForkExtras.UIDensityFooter": "Уменьшить высоту строк, число строк превью и размер названий папок.",
            "ForkExtras.HideReactionsBar": "Скрыть реакции",
            "ForkExtras.HideReactionsBarFooter": "Скрыть панель реакций под сообщениями.",
            "ForkExtras.ShowDC": "Показать DC и дату регистрации",
            "ForkExtras.ShowProfileId": "Показать ID профиля",
            "ForkExtras.PrivacyFooter": "Добавить дополнительные диагностические строки на экраны профиля.",
            "ForkExtras.AccentSaturation": "Насыщенность акцентного цвета",
            "ForkExtras.ConfirmBeforeCall": "Подтверждать перед звонком",
            "ForkExtras.SendWithReturnKey": "Отправка по Enter",
            "ForkExtras.SendWithReturnKeyFooter": "Нажатие Enter на клавиатуре отправляет сообщение вместо новой строки.",
            "ForkExtras.ForceBuiltInMic": "Только встроенный микрофон",
            "ForkExtras.ForceBuiltInMicFooter": "Использовать встроенный микрофон устройства вместо подключённого Bluetooth-устройства для звонков и голосовых сообщений.",
            "ForkExtras.CallsFooter": "Запрашивать подтверждение перед началом звонка.",
            "ForkExtras.TranslationBackend": "Перевод",
            "ForkExtras.TranscriptionBackend": "Расшифровка голоса",
            "ForkExtras.TranslationFooter": "Выбрать альтернативный движок перевода или расшифровки голоса, независимо от Telegram Premium.",
            "ForkExtras.ScrollToNextChat": "Свайп к следующему чату",
            "ForkExtras.ScrollToNextChatFooter": "Смахивание вверх на последнем сообщении переходит к следующему непрочитанному чату или теме.",
            "ForkExtras.BackendDefault": "По умолчанию",
            "ForkExtras.BackendSystem": "Системный (Apple)",
            "ForkExtras.BackendApple": "На устройстве (Apple)",
            "ForkExtras.SaveDeletedMessages": "Сохранять удалённые",
            "ForkExtras.SaveDeletedMessagesFooter": "Свои и чужие удалённые, включая одноразовые медиа, остаются в чате (🧹). Также в «Удалённые».",
            "ForkExtras.SaveMessagesHistory": "История правок",
            "ForkExtras.SaveMessagesHistoryFooter": "Хранить предыдущий текст при редактировании. Открывается из меню сообщения.",
            "ForkExtras.SaveMedia": "Сохранять медиа",
            "ForkExtras.SaveMediaFooter": "Копировать вложения в Saved Attachments при удалении/TTL (свои и чужие; как в AyuGram Android).",
            "ForkExtras.SaveForBots": "Также сохранять ботов",
            "ForkExtras.AyuForward": "AyuForward",
            "ForkExtras.AyuForwardFooter": "Пересылать из каналов с запретом пересылки и удалённые сообщения: медиа загружается заново без автора (AyuGram Android).",
            "ForkExtras.HideAds": "Скрыть рекламу",
            "ForkExtras.HideAdsFooter": "Скрывать спонсорские и рекомендованные сообщения в чатах (фильтры AyuGram).",
            "ForkExtras.HideBlockedMessages": "Скрыть заблокированных",
            "ForkExtras.HideBlockedMessagesFooter": "Скрывать сообщения и набор текста от заблокированных пользователей.",
            "ForkExtras.ViewDeleted": "Удалённые",
            "ForkExtras.EditHistory": "История правок",
            "ForkExtras.ClearDeleted": "Очистить удалённые",
            "ForkExtras.NoDeleted": "Пока нет сохранённых удалённых сообщений.",
            "ForkExtras.NoEdits": "Предыдущих версий нет.",
        ],
    ]
    
    private static func languageCode() -> String {
        let candidates = Locale.preferredLanguages + Bundle.main.preferredLocalizations
        for candidate in candidates {
            let code = String(candidate.prefix(2)).lowercased()
            if translations[code] != nil {
                return code
            }
        }
        return "en"
    }
    
    static func string(forKey key: String) -> String {
        let code = languageCode()
        if let value = translations[code]?[key] {
            return value
        }
        return translations["en"]?[key] ?? key
    }
    
    static var title: String { string(forKey: "ForkExtras.Title") }
    static var ghostDontReadMessages: String { string(forKey: "ForkExtras.GhostDontReadMessages") }
    static var ghostDontReadStories: String { string(forKey: "ForkExtras.GhostDontReadStories") }
    static var ghostDontSendOnline: String { string(forKey: "ForkExtras.GhostDontSendOnline") }
    static var ghostDontSendTyping: String { string(forKey: "ForkExtras.GhostDontSendTyping") }
    static var ghostGoOfflineAutomatically: String { string(forKey: "ForkExtras.GhostGoOfflineAutomatically") }
    static var ghostGoOfflineAutomaticallyFooter: String { string(forKey: "ForkExtras.GhostGoOfflineAutomaticallyFooter") }
    static var ghostReadOnInteract: String { string(forKey: "ForkExtras.GhostReadOnInteract") }
    static var ghostReadOnInteractFooter: String { string(forKey: "ForkExtras.GhostReadOnInteractFooter") }
    static var ghostAlertBeforeOpeningStory: String { string(forKey: "ForkExtras.GhostAlertBeforeOpeningStory") }
    static var ghostAlertBeforeOpeningStoryFooter: String { string(forKey: "ForkExtras.GhostAlertBeforeOpeningStoryFooter") }
    static var ghostModeFooter: String { string(forKey: "ForkExtras.GhostModeFooter") }
    static var instantPasscode: String { string(forKey: "ForkExtras.InstantPasscode") }
    static var instantPasscodeFooter: String { string(forKey: "ForkExtras.InstantPasscodeFooter") }
    static var hideMentions: String { string(forKey: "ForkExtras.HideMentions") }
    static var hideMentionsFooter: String { string(forKey: "ForkExtras.HideMentionsFooter") }
    static var hidePinned: String { string(forKey: "ForkExtras.HidePinned") }
    static var hidePinnedFooter: String { string(forKey: "ForkExtras.HidePinnedFooter") }
    static var sessionBackup: String { string(forKey: "ForkExtras.SessionBackup") }
    static var sessionBackupFooter: String { string(forKey: "ForkExtras.SessionBackupFooter") }
    static var compactChatList: String { string(forKey: "ForkExtras.CompactChatList") }
    static var compactMessagePreview: String { string(forKey: "ForkExtras.CompactMessagePreview") }
    static var compactFolderNames: String { string(forKey: "ForkExtras.CompactFolderNames") }
    static var uiDensityFooter: String { string(forKey: "ForkExtras.UIDensityFooter") }
    static var hideReactionsBar: String { string(forKey: "ForkExtras.HideReactionsBar") }
    static var hideReactionsBarFooter: String { string(forKey: "ForkExtras.HideReactionsBarFooter") }
    static var showDC: String { string(forKey: "ForkExtras.ShowDC") }
    static var showProfileId: String { string(forKey: "ForkExtras.ShowProfileId") }
    static var privacyFooter: String { string(forKey: "ForkExtras.PrivacyFooter") }
    static var accentSaturation: String { string(forKey: "ForkExtras.AccentSaturation") }
    static var confirmBeforeCall: String { string(forKey: "ForkExtras.ConfirmBeforeCall") }
    static var sendWithReturnKey: String { string(forKey: "ForkExtras.SendWithReturnKey") }
    static var sendWithReturnKeyFooter: String { string(forKey: "ForkExtras.SendWithReturnKeyFooter") }
    static var forceBuiltInMic: String { string(forKey: "ForkExtras.ForceBuiltInMic") }
    static var forceBuiltInMicFooter: String { string(forKey: "ForkExtras.ForceBuiltInMicFooter") }
    static var callsFooter: String { string(forKey: "ForkExtras.CallsFooter") }
    static var translationBackend: String { string(forKey: "ForkExtras.TranslationBackend") }
    static var transcriptionBackend: String { string(forKey: "ForkExtras.TranscriptionBackend") }
    static var translationFooter: String { string(forKey: "ForkExtras.TranslationFooter") }
    static var scrollToNextChat: String { string(forKey: "ForkExtras.ScrollToNextChat") }
    static var scrollToNextChatFooter: String { string(forKey: "ForkExtras.ScrollToNextChatFooter") }
    static var saveDeletedMessages: String { string(forKey: "ForkExtras.SaveDeletedMessages") }
    static var saveDeletedMessagesFooter: String { string(forKey: "ForkExtras.SaveDeletedMessagesFooter") }
    static var saveMessagesHistory: String { string(forKey: "ForkExtras.SaveMessagesHistory") }
    static var saveMessagesHistoryFooter: String { string(forKey: "ForkExtras.SaveMessagesHistoryFooter") }
    static var saveMedia: String { string(forKey: "ForkExtras.SaveMedia") }
    static var saveMediaFooter: String { string(forKey: "ForkExtras.SaveMediaFooter") }
    static var saveForBots: String { string(forKey: "ForkExtras.SaveForBots") }
    static var ayuForward: String { string(forKey: "ForkExtras.AyuForward") }
    static var ayuForwardFooter: String { string(forKey: "ForkExtras.AyuForwardFooter") }
    static var hideAds: String { string(forKey: "ForkExtras.HideAds") }
    static var hideAdsFooter: String { string(forKey: "ForkExtras.HideAdsFooter") }
    static var hideBlockedMessages: String { string(forKey: "ForkExtras.HideBlockedMessages") }
    static var hideBlockedMessagesFooter: String { string(forKey: "ForkExtras.HideBlockedMessagesFooter") }
    static var viewDeleted: String { string(forKey: "ForkExtras.ViewDeleted") }
    static var editHistory: String { string(forKey: "ForkExtras.EditHistory") }
    static var clearDeleted: String { string(forKey: "ForkExtras.ClearDeleted") }
    static var noDeleted: String { string(forKey: "ForkExtras.NoDeleted") }
    static var noEdits: String { string(forKey: "ForkExtras.NoEdits") }
    static var backendDefault: String { string(forKey: "ForkExtras.BackendDefault") }
    static var backendSystem: String { string(forKey: "ForkExtras.BackendSystem") }
    static var backendApple: String { string(forKey: "ForkExtras.BackendApple") }
}

private final class ForkExtrasControllerArguments {
    let updateGhostDontReadMessages: (Bool) -> Void
    let updateGhostDontReadStories: (Bool) -> Void
    let updateGhostDontSendOnline: (Bool) -> Void
    let updateGhostDontSendTyping: (Bool) -> Void
    let updateGhostGoOfflineAutomatically: (Bool) -> Void
    let updateGhostReadOnInteract: (Bool) -> Void
    let updateGhostAlertBeforeOpeningStory: (Bool) -> Void
    let updateInstantPasscode: (Bool) -> Void
    let updateHideMentions: (Bool) -> Void
    let updateHidePinned: (Bool) -> Void
    let updateSessionBackup: (Bool) -> Void
    let updateCompactChatList: (Bool) -> Void
    let updateCompactMessagePreview: (Bool) -> Void
    let updateCompactFolderNames: (Bool) -> Void
    let updateHideReactionsBar: (Bool) -> Void
    let updateShowDC: (Bool) -> Void
    let updateShowProfileId: (Bool) -> Void
    let openAccentSaturation: () -> Void
    let updateConfirmBeforeCall: (Bool) -> Void
    let updateSendWithReturnKey: (Bool) -> Void
    let updateForceBuiltInMic: (Bool) -> Void
    let openTranslationBackend: () -> Void
    let openTranscriptionBackend: () -> Void
    let updateScrollToNextChatDisabled: (Bool) -> Void
    let updateSaveDeletedMessages: (Bool) -> Void
    let updateSaveMessagesHistory: (Bool) -> Void
    let updateSaveMedia: (Bool) -> Void
    let updateSaveForBots: (Bool) -> Void
    let updateAyuForward: (Bool) -> Void
    let updateHideAds: (Bool) -> Void
    let updateHideBlockedMessages: (Bool) -> Void

    init(
        updateGhostDontReadMessages: @escaping (Bool) -> Void,
        updateGhostDontReadStories: @escaping (Bool) -> Void,
        updateGhostDontSendOnline: @escaping (Bool) -> Void,
        updateGhostDontSendTyping: @escaping (Bool) -> Void,
        updateGhostGoOfflineAutomatically: @escaping (Bool) -> Void,
        updateGhostReadOnInteract: @escaping (Bool) -> Void,
        updateGhostAlertBeforeOpeningStory: @escaping (Bool) -> Void,
        updateInstantPasscode: @escaping (Bool) -> Void,
        updateHideMentions: @escaping (Bool) -> Void,
        updateHidePinned: @escaping (Bool) -> Void,
        updateSessionBackup: @escaping (Bool) -> Void,
        updateCompactChatList: @escaping (Bool) -> Void,
        updateCompactMessagePreview: @escaping (Bool) -> Void,
        updateCompactFolderNames: @escaping (Bool) -> Void,
        updateHideReactionsBar: @escaping (Bool) -> Void,
        updateShowDC: @escaping (Bool) -> Void,
        updateShowProfileId: @escaping (Bool) -> Void,
        openAccentSaturation: @escaping () -> Void,
        updateConfirmBeforeCall: @escaping (Bool) -> Void,
        updateSendWithReturnKey: @escaping (Bool) -> Void,
        updateForceBuiltInMic: @escaping (Bool) -> Void,
        openTranslationBackend: @escaping () -> Void,
        openTranscriptionBackend: @escaping () -> Void,
        updateScrollToNextChatDisabled: @escaping (Bool) -> Void,
        updateSaveDeletedMessages: @escaping (Bool) -> Void,
        updateSaveMessagesHistory: @escaping (Bool) -> Void,
        updateSaveMedia: @escaping (Bool) -> Void,
        updateSaveForBots: @escaping (Bool) -> Void,
        updateAyuForward: @escaping (Bool) -> Void,
        updateHideAds: @escaping (Bool) -> Void,
        updateHideBlockedMessages: @escaping (Bool) -> Void
    ) {
        self.updateGhostDontReadMessages = updateGhostDontReadMessages
        self.updateGhostDontReadStories = updateGhostDontReadStories
        self.updateGhostDontSendOnline = updateGhostDontSendOnline
        self.updateGhostDontSendTyping = updateGhostDontSendTyping
        self.updateGhostGoOfflineAutomatically = updateGhostGoOfflineAutomatically
        self.updateGhostReadOnInteract = updateGhostReadOnInteract
        self.updateGhostAlertBeforeOpeningStory = updateGhostAlertBeforeOpeningStory
        self.updateInstantPasscode = updateInstantPasscode
        self.updateHideMentions = updateHideMentions
        self.updateHidePinned = updateHidePinned
        self.updateSessionBackup = updateSessionBackup
        self.updateCompactChatList = updateCompactChatList
        self.updateCompactMessagePreview = updateCompactMessagePreview
        self.updateCompactFolderNames = updateCompactFolderNames
        self.updateHideReactionsBar = updateHideReactionsBar
        self.updateShowDC = updateShowDC
        self.updateShowProfileId = updateShowProfileId
        self.openAccentSaturation = openAccentSaturation
        self.updateConfirmBeforeCall = updateConfirmBeforeCall
        self.updateSendWithReturnKey = updateSendWithReturnKey
        self.updateForceBuiltInMic = updateForceBuiltInMic
        self.openTranslationBackend = openTranslationBackend
        self.openTranscriptionBackend = openTranscriptionBackend
        self.updateScrollToNextChatDisabled = updateScrollToNextChatDisabled
        self.updateSaveDeletedMessages = updateSaveDeletedMessages
        self.updateSaveMessagesHistory = updateSaveMessagesHistory
        self.updateSaveMedia = updateSaveMedia
        self.updateSaveForBots = updateSaveForBots
        self.updateAyuForward = updateAyuForward
        self.updateHideAds = updateHideAds
        self.updateHideBlockedMessages = updateHideBlockedMessages
    }
}

private enum ForkExtrasSection: Int32 {
    case ghost
    case lock
    case notifications
    case backup
    case uiDensity
    case privacy
    case calls
    case translation
    case navigation
    case messageSaving
}

private enum ForkExtrasEntry: ItemListNodeEntry {
    case ghostDontReadMessages(Bool)
    case ghostDontReadStories(Bool)
    case ghostDontSendOnline(Bool)
    case ghostDontSendTyping(Bool)
    case ghostGoOfflineAutomatically(Bool)
    case ghostGoOfflineAutomaticallyFooter
    case ghostReadOnInteract(Bool)
    case ghostReadOnInteractFooter
    case ghostAlertBeforeOpeningStory(Bool)
    case ghostAlertBeforeOpeningStoryFooter
    case ghostModeFooter
    case instantPasscode(Bool)
    case instantPasscodeFooter
    case hideMentions(Bool)
    case hideMentionsFooter
    case hidePinned(Bool)
    case hidePinnedFooter
    case sessionBackup(Bool)
    case sessionBackupFooter
    case compactChatList(Bool)
    case compactMessagePreview(Bool)
    case compactFolderNames(Bool)
    case uiDensityFooter
    case hideReactionsBar(Bool)
    case showDC(Bool)
    case showProfileId(Bool)
    case accentSaturation(Int32)
    case privacyFooter
    case confirmBeforeCall(Bool)
    case sendWithReturnKey(Bool)
    case sendWithReturnKeyFooter
    case forceBuiltInMic(Bool)
    case callsFooter
    case translationBackend(ForkTranslationBackend)
    case transcriptionBackend(ForkTranscriptionBackend)
    case translationFooter
    case scrollToNextChat(Bool)
    case scrollToNextChatFooter
    case saveDeletedMessages(Bool)
    case saveDeletedMessagesFooter
    case saveMessagesHistory(Bool)
    case saveMessagesHistoryFooter
    case saveMedia(Bool)
    case saveMediaFooter
    case saveForBots(Bool)
    case ayuForward(Bool)
    case ayuForwardFooter
    case hideAds(Bool)
    case hideAdsFooter
    case hideBlockedMessages(Bool)
    case hideBlockedMessagesFooter

    var section: ItemListSectionId {
        switch self {
        case .ghostDontReadMessages, .ghostDontReadStories, .ghostDontSendOnline, .ghostDontSendTyping, .ghostGoOfflineAutomatically, .ghostGoOfflineAutomaticallyFooter, .ghostReadOnInteract, .ghostReadOnInteractFooter, .ghostAlertBeforeOpeningStory, .ghostAlertBeforeOpeningStoryFooter, .ghostModeFooter:
            return ForkExtrasSection.ghost.rawValue
        case .instantPasscode, .instantPasscodeFooter:
            return ForkExtrasSection.lock.rawValue
        case .hideMentions, .hideMentionsFooter, .hidePinned, .hidePinnedFooter:
            return ForkExtrasSection.notifications.rawValue
        case .sessionBackup, .sessionBackupFooter:
            return ForkExtrasSection.backup.rawValue
        case .compactChatList, .compactMessagePreview, .compactFolderNames, .uiDensityFooter:
            return ForkExtrasSection.uiDensity.rawValue
        case .hideReactionsBar, .showDC, .showProfileId, .accentSaturation, .privacyFooter:
            return ForkExtrasSection.privacy.rawValue
        case .confirmBeforeCall, .sendWithReturnKey, .sendWithReturnKeyFooter, .forceBuiltInMic, .callsFooter:
            return ForkExtrasSection.calls.rawValue
        case .translationBackend, .transcriptionBackend, .translationFooter:
            return ForkExtrasSection.translation.rawValue
        case .scrollToNextChat, .scrollToNextChatFooter:
            return ForkExtrasSection.navigation.rawValue
        case .saveDeletedMessages, .saveDeletedMessagesFooter, .saveMessagesHistory, .saveMessagesHistoryFooter, .saveMedia, .saveMediaFooter, .saveForBots, .ayuForward, .ayuForwardFooter, .hideAds, .hideAdsFooter, .hideBlockedMessages, .hideBlockedMessagesFooter:
            return ForkExtrasSection.messageSaving.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostDontReadMessages: return 0
        case .ghostDontReadStories: return 1
        case .ghostDontSendOnline: return 2
        case .ghostDontSendTyping: return 3
        case .ghostGoOfflineAutomatically: return 4
        case .ghostGoOfflineAutomaticallyFooter: return 5
        case .ghostReadOnInteract: return 6
        case .ghostReadOnInteractFooter: return 7
        case .ghostAlertBeforeOpeningStory: return 8
        case .ghostAlertBeforeOpeningStoryFooter: return 9
        case .ghostModeFooter: return 10
        case .instantPasscode: return 11
        case .instantPasscodeFooter: return 12
        case .hideMentions: return 13
        case .hideMentionsFooter: return 14
        case .hidePinned: return 15
        case .hidePinnedFooter: return 16
        case .sessionBackup: return 17
        case .sessionBackupFooter: return 18
        case .compactChatList: return 19
        case .compactMessagePreview: return 20
        case .compactFolderNames: return 21
        case .uiDensityFooter: return 22
        case .hideReactionsBar: return 23
        case .showDC: return 24
        case .showProfileId: return 25
        case .accentSaturation: return 26
        case .privacyFooter: return 27
        case .confirmBeforeCall: return 28
        case .sendWithReturnKey: return 29
        case .sendWithReturnKeyFooter: return 30
        case .forceBuiltInMic: return 31
        case .callsFooter: return 32
        case .translationBackend: return 33
        case .transcriptionBackend: return 34
        case .translationFooter: return 35
        case .scrollToNextChat: return 36
        case .scrollToNextChatFooter: return 37
        case .saveDeletedMessages: return 38
        case .saveDeletedMessagesFooter: return 39
        case .saveMessagesHistory: return 40
        case .saveMessagesHistoryFooter: return 41
        case .saveMedia: return 42
        case .saveMediaFooter: return 43
        case .saveForBots: return 44
        case .ayuForward: return 45
        case .ayuForwardFooter: return 46
        case .hideAds: return 47
        case .hideAdsFooter: return 48
        case .hideBlockedMessages: return 49
        case .hideBlockedMessagesFooter: return 50
        }
    }

    static func <(lhs: ForkExtrasEntry, rhs: ForkExtrasEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkExtrasControllerArguments
        switch self {
        case let .ghostDontReadMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontReadMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontReadMessages(value)
            })
        case let .ghostDontReadStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontReadStories, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontReadStories(value)
            })
        case let .ghostDontSendOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontSendOnline, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontSendOnline(value)
            })
        case let .ghostDontSendTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontSendTyping, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontSendTyping(value)
            })
        case let .ghostGoOfflineAutomatically(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostGoOfflineAutomatically, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostGoOfflineAutomatically(value)
            })
        case .ghostGoOfflineAutomaticallyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostGoOfflineAutomaticallyFooter), sectionId: self.section)
        case let .ghostReadOnInteract(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostReadOnInteract, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostReadOnInteract(value)
            })
        case .ghostReadOnInteractFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostReadOnInteractFooter), sectionId: self.section)
        case let .ghostAlertBeforeOpeningStory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostAlertBeforeOpeningStory, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostAlertBeforeOpeningStory(value)
            })
        case .ghostAlertBeforeOpeningStoryFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostAlertBeforeOpeningStoryFooter), sectionId: self.section)
        case .ghostModeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostModeFooter), sectionId: self.section)
        case let .instantPasscode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.instantPasscode, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateInstantPasscode(value)
            })
        case .instantPasscodeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.instantPasscodeFooter), sectionId: self.section)
        case let .hideMentions(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideMentions, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideMentions(value)
            })
        case .hideMentionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideMentionsFooter), sectionId: self.section)
        case let .hidePinned(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hidePinned, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidePinned(value)
            })
        case .hidePinnedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hidePinnedFooter), sectionId: self.section)
        case let .sessionBackup(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.sessionBackup, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSessionBackup(value)
            })
        case .sessionBackupFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.sessionBackupFooter), sectionId: self.section)
        case let .compactChatList(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.compactChatList, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactChatList(value)
            })
        case let .compactMessagePreview(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.compactMessagePreview, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactMessagePreview(value)
            })
        case let .compactFolderNames(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.compactFolderNames, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactFolderNames(value)
            })
        case .uiDensityFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.uiDensityFooter), sectionId: self.section)
        case let .hideReactionsBar(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideReactionsBar, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideReactionsBar(value)
            })
        case let .showDC(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.showDC, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowDC(value)
            })
        case let .showProfileId(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.showProfileId, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowProfileId(value)
            })
        case let .accentSaturation(percent):
            return ItemListDisclosureItem(presentationData: presentationData, title: ForkExtrasLocalizedString.accentSaturation, label: "\(percent)%", sectionId: self.section, style: .blocks, action: {
                arguments.openAccentSaturation()
            })
        case .privacyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.privacyFooter), sectionId: self.section)
        case let .confirmBeforeCall(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.confirmBeforeCall, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateConfirmBeforeCall(value)
            })
        case let .sendWithReturnKey(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.sendWithReturnKey, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSendWithReturnKey(value)
            })
        case .sendWithReturnKeyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.sendWithReturnKeyFooter), sectionId: self.section)
        case let .forceBuiltInMic(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.forceBuiltInMic, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateForceBuiltInMic(value)
            })
        case .callsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.forceBuiltInMicFooter + "\n\n" + ForkExtrasLocalizedString.callsFooter), sectionId: self.section)
        case let .translationBackend(backend):
            let label: String
            switch backend {
            case .default:
                label = ForkExtrasLocalizedString.backendDefault
            case .system:
                label = ForkExtrasLocalizedString.backendSystem
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: ForkExtrasLocalizedString.translationBackend, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openTranslationBackend()
            })
        case let .transcriptionBackend(backend):
            let label: String
            switch backend {
            case .default:
                label = ForkExtrasLocalizedString.backendDefault
            case .apple:
                label = ForkExtrasLocalizedString.backendApple
            }
            return ItemListDisclosureItem(presentationData: presentationData, title: ForkExtrasLocalizedString.transcriptionBackend, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openTranscriptionBackend()
            })
        case .translationFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.translationFooter), sectionId: self.section)
        case let .scrollToNextChat(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.scrollToNextChat, value: !value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateScrollToNextChatDisabled(!value)
            })
        case .scrollToNextChatFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.scrollToNextChatFooter), sectionId: self.section)
        case let .saveDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveDeletedMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveDeletedMessages(value)
            })
        case .saveDeletedMessagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveDeletedMessagesFooter), sectionId: self.section)
        case let .saveMessagesHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveMessagesHistory, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveMessagesHistory(value)
            })
        case .saveMessagesHistoryFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveMessagesHistoryFooter), sectionId: self.section)
        case let .saveMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveMedia, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveMedia(value)
            })
        case .saveMediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveMediaFooter), sectionId: self.section)
        case let .saveForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveForBots, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveForBots(value)
            })
        case let .ayuForward(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ayuForward, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAyuForward(value)
            })
        case .ayuForwardFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ayuForwardFooter), sectionId: self.section)
        case let .hideAds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideAds, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideAds(value)
            })
        case .hideAdsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideAdsFooter), sectionId: self.section)
        case let .hideBlockedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideBlockedMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideBlockedMessages(value)
            })
        case .hideBlockedMessagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideBlockedMessagesFooter), sectionId: self.section)
        }
    }
}

private func forkExtrasControllerEntries(settings: ForkExtrasSettings) -> [ForkExtrasEntry] {
    return [
        .ghostDontReadMessages(settings.ghostDontReadMessages),
        .ghostDontReadStories(settings.ghostDontReadStories),
        .ghostDontSendOnline(settings.ghostDontSendOnline),
        .ghostDontSendTyping(settings.ghostDontSendTyping),
        .ghostGoOfflineAutomatically(settings.ghostGoOfflineAutomatically),
        .ghostGoOfflineAutomaticallyFooter,
        .ghostReadOnInteract(settings.ghostReadOnInteract),
        .ghostReadOnInteractFooter,
        .ghostAlertBeforeOpeningStory(settings.ghostAlertBeforeOpeningStory),
        .ghostAlertBeforeOpeningStoryFooter,
        .ghostModeFooter,
        .instantPasscode(settings.instantPasscodeLock),
        .instantPasscodeFooter,
        .hideMentions(settings.hideMentionNotifications),
        .hideMentionsFooter,
        .hidePinned(settings.hidePinnedNotifications),
        .hidePinnedFooter,
        .sessionBackup(settings.sessionKeychainBackup),
        .sessionBackupFooter,
        .compactChatList(settings.compactChatList),
        .compactMessagePreview(settings.compactMessagePreview),
        .compactFolderNames(settings.compactFolderNames),
        .uiDensityFooter,
        .hideReactionsBar(settings.hideReactionsBar),
        .showDC(settings.showDC),
        .showProfileId(settings.showProfileId),
        .accentSaturation(settings.accentColorSaturation),
        .privacyFooter,
        .confirmBeforeCall(settings.confirmBeforeCall),
        .sendWithReturnKey(settings.sendWithReturnKey),
        .sendWithReturnKeyFooter,
        .forceBuiltInMic(settings.forceBuiltInMic),
        .callsFooter,
        .translationBackend(settings.translationBackend),
        .transcriptionBackend(settings.transcriptionBackend),
        .translationFooter,
        .scrollToNextChat(settings.scrollToNextChatDisabled),
        .scrollToNextChatFooter,
        .saveDeletedMessages(settings.saveDeletedMessages),
        .saveDeletedMessagesFooter,
        .saveMessagesHistory(settings.saveMessagesHistory),
        .saveMessagesHistoryFooter,
        .saveMedia(settings.saveMedia),
        .saveMediaFooter,
        .saveForBots(settings.saveForBots),
        .ayuForward(settings.ayuForward),
        .ayuForwardFooter,
        .hideAds(settings.hideAds),
        .hideAdsFooter,
        .hideBlockedMessages(settings.hideBlockedMessages),
        .hideBlockedMessagesFooter,
    ]
}

public func forkExtrasController(context: AccountContext) -> ViewController {
    let updateDisposable = MetaDisposable()
    var presentControllerImpl: ((ViewController) -> Void)?

    func presentPicker(title: String, options: [(String, () -> Void)]) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
        for (optionTitle, action) in options {
            items.append(ActionSheetButtonItem(title: optionTitle, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                action()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(actionSheet)
    }

    let arguments = ForkExtrasControllerArguments(
        updateGhostDontReadMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontReadMessages = value
                updated.ghostMode = updated.ghostDontReadMessages && updated.ghostDontSendOnline && updated.ghostDontSendTyping
                return updated
            }.start())
        },
        updateGhostDontReadStories: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontReadStories = value
                return updated
            }.start())
        },
        updateGhostDontSendOnline: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontSendOnline = value
                updated.ghostMode = updated.ghostDontReadMessages && updated.ghostDontSendOnline && updated.ghostDontSendTyping
                return updated
            }.start())
        },
        updateGhostDontSendTyping: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontSendTyping = value
                updated.ghostMode = updated.ghostDontReadMessages && updated.ghostDontSendOnline && updated.ghostDontSendTyping
                return updated
            }.start())
        },
        updateGhostGoOfflineAutomatically: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostGoOfflineAutomatically = value
                return updated
            }.start())
        },
        updateGhostReadOnInteract: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostReadOnInteract = value
                return updated
            }.start())
        },
        updateGhostAlertBeforeOpeningStory: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostAlertBeforeOpeningStory = value
                return updated
            }.start())
        },
        updateInstantPasscode: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.instantPasscodeLock = value
                return updated
            }.start())
        },
        updateHideMentions: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideMentionNotifications = value
                return updated
            }.start())
        },
        updateHidePinned: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hidePinnedNotifications = value
                return updated
            }.start())
        },
        updateSessionBackup: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.sessionKeychainBackup = value
                return updated
            }.start())
        },
        updateCompactChatList: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.compactChatList = value
                return updated
            }.start())
        },
        updateCompactMessagePreview: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.compactMessagePreview = value
                return updated
            }.start())
        },
        updateCompactFolderNames: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.compactFolderNames = value
                return updated
            }.start())
        },
        updateHideReactionsBar: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideReactionsBar = value
                return updated
            }.start())
        },
        updateShowDC: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.showDC = value
                return updated
            }.start())
        },
        updateShowProfileId: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.showProfileId = value
                return updated
            }.start())
        },
        openAccentSaturation: {
            let percents: [Int32] = [0, 25, 50, 75, 100]
            presentPicker(title: ForkExtrasLocalizedString.accentSaturation, options: percents.map { percent in
                ("\(percent)%", {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.accentColorSaturation = percent
                        return updated
                    }.start())
                })
            })
        },
        updateConfirmBeforeCall: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.confirmBeforeCall = value
                return updated
            }.start())
        },
        updateSendWithReturnKey: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.sendWithReturnKey = value
                return updated
            }.start())
        },
        updateForceBuiltInMic: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.forceBuiltInMic = value
                return updated
            }.start())
        },
        openTranslationBackend: {
            presentPicker(title: ForkExtrasLocalizedString.translationBackend, options: [
                (ForkExtrasLocalizedString.backendDefault, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.translationBackend = .default
                        return updated
                    }.start())
                }),
                (ForkExtrasLocalizedString.backendSystem, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.translationBackend = .system
                        return updated
                    }.start())
                })
            ])
        },
        openTranscriptionBackend: {
            presentPicker(title: ForkExtrasLocalizedString.transcriptionBackend, options: [
                (ForkExtrasLocalizedString.backendDefault, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.transcriptionBackend = .default
                        return updated
                    }.start())
                }),
                (ForkExtrasLocalizedString.backendApple, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.transcriptionBackend = .apple
                        return updated
                    }.start())
                })
            ])
        },
        updateScrollToNextChatDisabled: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.scrollToNextChatDisabled = value
                return updated
            }.start())
        },
        updateSaveDeletedMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveDeletedMessages = value
                return updated
            }.start())
        },
        updateSaveMessagesHistory: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveMessagesHistory = value
                return updated
            }.start())
        },
        updateSaveMedia: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveMedia = value
                return updated
            }.start())
        },
        updateSaveForBots: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveForBots = value
                return updated
            }.start())
        },
        updateAyuForward: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ayuForward = value
                return updated
            }.start())
        },
        updateHideAds: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideAds = value
                return updated
            }.start())
        },
        updateHideBlockedMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideBlockedMessages = value
                return updated
            }.start())
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: context.sharedContext.accountManager)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(ForkExtrasLocalizedString.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: forkExtrasControllerEntries(settings: settings),
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] presented in
        controller?.present(presented, in: .window(.root))
    }
    return controller
}
