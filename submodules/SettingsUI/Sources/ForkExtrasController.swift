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
            "ForkExtras.GhostMode": "Ghost Mode",
            "ForkExtras.GhostModeFooter": "Do not mark chats as read while browsing.",
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
            "ForkExtras.ViewDeleted": "View Deleted",
            "ForkExtras.EditHistory": "Edit History",
            "ForkExtras.ClearDeleted": "Clear Deleted",
            "ForkExtras.NoDeleted": "No deleted messages saved yet.",
            "ForkExtras.NoEdits": "No previous versions saved.",
        ],
        "ru": [
            "ForkExtras.Title": "Дополнительно",
            "ForkExtras.GhostMode": "Режим призрака",
            "ForkExtras.GhostModeFooter": "Не отмечать чаты прочитанными при просмотре.",
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
    static var ghostMode: String { string(forKey: "ForkExtras.GhostMode") }
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
    let updateGhostMode: (Bool) -> Void
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

    init(
        updateGhostMode: @escaping (Bool) -> Void,
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
        updateSaveForBots: @escaping (Bool) -> Void
    ) {
        self.updateGhostMode = updateGhostMode
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
    case ghostMode(Bool)
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

    var section: ItemListSectionId {
        switch self {
        case .ghostMode, .ghostModeFooter:
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
        case .saveDeletedMessages, .saveDeletedMessagesFooter, .saveMessagesHistory, .saveMessagesHistoryFooter, .saveMedia, .saveMediaFooter, .saveForBots:
            return ForkExtrasSection.messageSaving.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostMode: return 0
        case .ghostModeFooter: return 1
        case .instantPasscode: return 2
        case .instantPasscodeFooter: return 3
        case .hideMentions: return 4
        case .hideMentionsFooter: return 5
        case .hidePinned: return 6
        case .hidePinnedFooter: return 7
        case .sessionBackup: return 8
        case .sessionBackupFooter: return 9
        case .compactChatList: return 10
        case .compactMessagePreview: return 11
        case .compactFolderNames: return 12
        case .uiDensityFooter: return 13
        case .hideReactionsBar: return 14
        case .showDC: return 15
        case .showProfileId: return 16
        case .accentSaturation: return 17
        case .privacyFooter: return 18
        case .confirmBeforeCall: return 19
        case .sendWithReturnKey: return 20
        case .sendWithReturnKeyFooter: return 21
        case .forceBuiltInMic: return 22
        case .callsFooter: return 23
        case .translationBackend: return 24
        case .transcriptionBackend: return 25
        case .translationFooter: return 26
        case .scrollToNextChat: return 27
        case .scrollToNextChatFooter: return 28
        case .saveDeletedMessages: return 29
        case .saveDeletedMessagesFooter: return 30
        case .saveMessagesHistory: return 31
        case .saveMessagesHistoryFooter: return 32
        case .saveMedia: return 33
        case .saveMediaFooter: return 34
        case .saveForBots: return 35
        }
    }

    static func <(lhs: ForkExtrasEntry, rhs: ForkExtrasEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkExtrasControllerArguments
        switch self {
        case let .ghostMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostMode, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostMode(value)
            })
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
        }
    }
}

private func forkExtrasControllerEntries(settings: ForkExtrasSettings) -> [ForkExtrasEntry] {
    return [
        .ghostMode(settings.ghostMode),
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
        updateGhostMode: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostMode = value
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
