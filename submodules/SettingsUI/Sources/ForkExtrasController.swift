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
            "ForkExtras.FormattingPanel": "Formatting Panel",
            "ForkExtras.FormattingPanelFooter": "Show Bold / Italic / Monospace / Link buttons above the keyboard.",
            "ForkExtras.SessionBackup": "Keychain Session Backup",
            "ForkExtras.SessionBackupFooter": "Mirror account session data to the device Keychain for same-bundle reinstalls.",
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
            "ForkExtras.FormattingPanel": "Панель форматирования",
            "ForkExtras.FormattingPanelFooter": "Показывать кнопки Жирный / Курсив / Моно / Ссылка над клавиатурой.",
            "ForkExtras.SessionBackup": "Резерв сессии в Keychain",
            "ForkExtras.SessionBackupFooter": "Дублировать данные сессии в Keychain для переустановки с тем же Bundle ID.",
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
    static var formattingPanel: String { string(forKey: "ForkExtras.FormattingPanel") }
    static var formattingPanelFooter: String { string(forKey: "ForkExtras.FormattingPanelFooter") }
    static var sessionBackup: String { string(forKey: "ForkExtras.SessionBackup") }
    static var sessionBackupFooter: String { string(forKey: "ForkExtras.SessionBackupFooter") }
}

private final class ForkExtrasControllerArguments {
    let updateGhostMode: (Bool) -> Void
    let updateInstantPasscode: (Bool) -> Void
    let updateHideMentions: (Bool) -> Void
    let updateHidePinned: (Bool) -> Void
    let updateFormattingPanel: (Bool) -> Void
    let updateSessionBackup: (Bool) -> Void
    
    init(
        updateGhostMode: @escaping (Bool) -> Void,
        updateInstantPasscode: @escaping (Bool) -> Void,
        updateHideMentions: @escaping (Bool) -> Void,
        updateHidePinned: @escaping (Bool) -> Void,
        updateFormattingPanel: @escaping (Bool) -> Void,
        updateSessionBackup: @escaping (Bool) -> Void
    ) {
        self.updateGhostMode = updateGhostMode
        self.updateInstantPasscode = updateInstantPasscode
        self.updateHideMentions = updateHideMentions
        self.updateHidePinned = updateHidePinned
        self.updateFormattingPanel = updateFormattingPanel
        self.updateSessionBackup = updateSessionBackup
    }
}

private enum ForkExtrasSection: Int32 {
    case ghost
    case lock
    case notifications
    case formatting
    case backup
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
    case formattingPanel(Bool)
    case formattingPanelFooter
    case sessionBackup(Bool)
    case sessionBackupFooter
    
    var section: ItemListSectionId {
        switch self {
        case .ghostMode, .ghostModeFooter:
            return ForkExtrasSection.ghost.rawValue
        case .instantPasscode, .instantPasscodeFooter:
            return ForkExtrasSection.lock.rawValue
        case .hideMentions, .hideMentionsFooter, .hidePinned, .hidePinnedFooter:
            return ForkExtrasSection.notifications.rawValue
        case .formattingPanel, .formattingPanelFooter:
            return ForkExtrasSection.formatting.rawValue
        case .sessionBackup, .sessionBackupFooter:
            return ForkExtrasSection.backup.rawValue
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
        case .formattingPanel: return 8
        case .formattingPanelFooter: return 9
        case .sessionBackup: return 10
        case .sessionBackupFooter: return 11
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
        case let .formattingPanel(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.formattingPanel, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateFormattingPanel(value)
            })
        case .formattingPanelFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.formattingPanelFooter), sectionId: self.section)
        case let .sessionBackup(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.sessionBackup, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSessionBackup(value)
            })
        case .sessionBackupFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.sessionBackupFooter), sectionId: self.section)
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
        .formattingPanel(settings.formattingPanel),
        .formattingPanelFooter,
        .sessionBackup(settings.sessionKeychainBackup),
        .sessionBackupFooter,
    ]
}

public func forkExtrasController(context: AccountContext) -> ViewController {
    let updateDisposable = MetaDisposable()
    
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
        updateFormattingPanel: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.formattingPanel = value
                return updated
            }.start())
        },
        updateSessionBackup: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.sessionKeychainBackup = value
                return updated
            }.start())
        }
    )
    
    let signal = combineLatest(
        queue: .mainQueue(),
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
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: forkExtrasControllerEntries(settings: settings),
            style: .blocks,
            emptyStateItem: nil,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    return controller
}
