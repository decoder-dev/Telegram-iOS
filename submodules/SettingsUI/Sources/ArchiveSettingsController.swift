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
import UndoUI
import ChatListUI

private final class ArchiveSettingsControllerArguments {
    let updateUnmuted: (Bool) -> Void
    let updateFolders: (Bool) -> Void
    let updateUnknown: (Bool?) -> Void
    let togglePassword: (Bool) -> Void
    let lockNow: () -> Void
    
    init(
        updateUnmuted: @escaping (Bool) -> Void,
        updateFolders: @escaping (Bool) -> Void,
        updateUnknown: @escaping (Bool?) -> Void,
        togglePassword: @escaping (Bool) -> Void,
        lockNow: @escaping () -> Void
    ) {
        self.updateUnmuted = updateUnmuted
        self.updateFolders = updateFolders
        self.updateUnknown = updateUnknown
        self.togglePassword = togglePassword
        self.lockNow = lockNow
    }
}

private enum ArchiveSettingsSection: Int32 {
    case unmuted
    case folders
    case unknown
    case password
}

private enum ArchiveSettingsControllerEntry: ItemListNodeEntry {
    case unmutedHeader
    case unmutedValue(Bool)
    case unmutedFooter
    
    case foldersHeader
    case foldersValue(Bool)
    case foldersFooter
    
    case unknownHeader
    case unknownValue(isOn: Bool, isLocked: Bool)
    case unknownFooter
    
    case passwordHeader
    case passwordValue(Bool)
    case passwordLockNow
    case passwordFooter
    
    var section: ItemListSectionId {
        switch self {
        case .unmutedHeader, .unmutedValue, .unmutedFooter:
            return ArchiveSettingsSection.unmuted.rawValue
        case .foldersHeader, .foldersValue, .foldersFooter:
            return ArchiveSettingsSection.folders.rawValue
        case .unknownHeader, .unknownValue, .unknownFooter:
            return ArchiveSettingsSection.unknown.rawValue
        case .passwordHeader, .passwordValue, .passwordLockNow, .passwordFooter:
            return ArchiveSettingsSection.password.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .unmutedHeader:
            return 0
        case .unmutedValue:
            return 1
        case .unmutedFooter:
            return 2
        case .foldersHeader:
            return 3
        case .foldersValue:
            return 4
        case .foldersFooter:
            return 5
        case .unknownHeader:
            return 6
        case .unknownValue:
            return 7
        case .unknownFooter:
            return 8
        case .passwordHeader:
            return 9
        case .passwordValue:
            return 10
        case .passwordLockNow:
            return 11
        case .passwordFooter:
            return 12
        }
    }
        
    static func <(lhs: ArchiveSettingsControllerEntry, rhs: ArchiveSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArchiveSettingsControllerArguments
        switch self {
        case .unmutedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: presentationData.strings.ArchiveSettings_UnmutedChatsHeader, sectionId: self.section)
        case let .unmutedValue(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: presentationData.strings.ArchiveSettings_KeepArchived, value: value, enableInteractiveChanges: false, enabled: false, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateUnmuted(value)
            })
        case .unmutedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .markdown(presentationData.strings.ArchiveSettings_UnmutedChatsFooter), sectionId: self.section)
        case .foldersHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: presentationData.strings.ArchiveSettings_FolderChatsHeader, sectionId: self.section)
        case let .foldersValue(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: presentationData.strings.ArchiveSettings_KeepArchived, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateFolders(value)
            })
        case .foldersFooter:
            return ItemListTextItem(presentationData: presentationData, text: .markdown(presentationData.strings.ArchiveSettings_FolderChatsFooter), sectionId: self.section)
        case .unknownHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: presentationData.strings.ArchiveSettings_UnknownChatsHeader, sectionId: self.section)
        case let .unknownValue(isOn, isLocked):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: presentationData.strings.ArchiveSettings_AutomaticallyArchive, value: isOn, enableInteractiveChanges: !isLocked, enabled: true, displayLocked: isLocked, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateUnknown(value)
            }, activatedWhileDisabled: {
                arguments.updateUnknown(nil)
            })
        case .unknownFooter:
            return ItemListTextItem(presentationData: presentationData, text: .markdown(presentationData.strings.ArchiveSettings_UnknownChatsFooter), sectionId: self.section)
        case .passwordHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.passwordSection, sectionId: self.section)
        case let .passwordValue(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockArchive, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.togglePassword(value)
            })
        case .passwordLockNow:
            return ItemListActionItem(presentationData: presentationData, title: ArchiveLockLocalizedString.lockNow, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.lockNow()
            })
        case .passwordFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.footer), sectionId: self.section)
        }
    }
}

private func archiveSettingsControllerEntries(
    presentationData: PresentationData,
    settings: GlobalPrivacySettings,
    isPasswordProtected: Bool,
    passwordLockOverride: Bool?,
    sessionUnlocked: Bool,
    isPremium: Bool,
    isPremiumEnabled: Bool
) -> [ArchiveSettingsControllerEntry] {
    var entries: [ArchiveSettingsControllerEntry] = []
    
    entries.append(.unmutedHeader)
    // Force-mute policy: keep archived even if manually unmuted later.
    entries.append(.unmutedValue(true))
    entries.append(.unmutedFooter)
    
    if isPremium || isPremiumEnabled {
        entries.append(.unknownHeader)
        entries.append(.unknownValue(isOn: isPremium && settings.automaticallyArchiveAndMuteNonContacts, isLocked: !isPremium))
        entries.append(.unknownFooter)
    }
    
    let passwordOn = passwordLockOverride ?? isPasswordProtected
    entries.append(.passwordHeader)
    entries.append(.passwordValue(passwordOn))
    if passwordOn && sessionUnlocked {
        entries.append(.passwordLockNow)
    }
    entries.append(.passwordFooter)
    
    return entries
}

public func archiveSettingsController(context: AccountContext) -> ViewController {
    let updateDisposable = MetaDisposable()
    
    updateDisposable.set(context.engine.privacy.requestAccountPrivacySettings().start())
    
    var presentUndoImpl: ((UndoOverlayContent) -> Void)?
    var presentPremiumImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?
    
    // Overrides the switch while a set/remove password sheet is in flight,
    // so cancel snaps the UI back instead of leaving an optimistic ON state.
    let passwordLockOverride = ValuePromise<Bool?>(nil, ignoreRepeated: true)
    let sessionUnlockedPromise = ValuePromise<Bool>(ArchiveLockSession.shared.isUnlocked, ignoreRepeated: true)
    
    let arguments = ArchiveSettingsControllerArguments(
        updateUnmuted: { value in
            // Archived chats are force-muted; always keep them archived if unmuted manually.
            let _ = context.engine.privacy.updateAccountKeepArchivedUnmuted(value: true).start()
        },
        updateFolders: { value in
            let _ = context.engine.privacy.updateAccountKeepArchivedFolders(value: value).start()
        },
        updateUnknown: { value in
            if let value {
                let _ = context.engine.privacy.updateAccountAutoArchiveChats(value: value).start()
            } else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentUndoImpl?(.premiumPaywall(title: nil, text: presentationData.strings.ArchiveSettings_TooltipPremiumRequired, customUndoText: nil, timeout: nil, linkAction: { _ in
                    presentPremiumImpl?()
                }))
            }
        },
        togglePassword: { enabled in
            // Optimistic override mirrors the switch the user just flipped.
            passwordLockOverride.set(enabled)
            if enabled {
                setArchivePassword(context: context, present: { controller in
                    presentControllerImpl?(controller)
                }, completion: { success in
                    if success {
                        passwordLockOverride.set(nil)
                        sessionUnlockedPromise.set(true)
                    } else {
                        // Snap switch back off.
                        passwordLockOverride.set(false)
                        Queue.mainQueue().after(0.05) {
                            passwordLockOverride.set(nil)
                        }
                    }
                })
            } else {
                removeArchivePassword(context: context, present: { controller in
                    presentControllerImpl?(controller)
                }, completion: { success in
                    if success {
                        passwordLockOverride.set(nil)
                        sessionUnlockedPromise.set(false)
                    } else {
                        passwordLockOverride.set(true)
                        Queue.mainQueue().after(0.05) {
                            passwordLockOverride.set(nil)
                        }
                    }
                })
            }
        },
        lockNow: {
            ArchiveLockSession.shared.relock()
            sessionUnlockedPromise.set(false)
            dismissOpenArchiveControllers(from: navigationControllerImpl?())
        }
    )
    
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.GlobalPrivacy()),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App()),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)),
        passwordLockOverride.get(),
        sessionUnlockedPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, appConfiguration, accountPeer, archiveSettingsPreference, passwordOverride, sessionUnlocked -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData

        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)
        
        let isPremium = accountPeer?.isPremium ?? false
        let isPremiumDisabled = PremiumConfiguration.with(appConfiguration: appConfiguration).isPremiumDisabled
        let archiveSettings = archiveSettingsPreference?.get(ChatArchiveSettings.self) ?? .default
        let isPasswordProtected = archiveIsPasswordProtected(peerId: context.account.peerId, settings: archiveSettings)
        if archiveSettings.legacyLockPasswordHash != nil {
            let _ = updateChatArchiveSettings(engine: context.engine) { current in
                current.clearingLegacyPasswordHash()
            }.startStandalone()
        }
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.ArchiveSettings_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: archiveSettingsControllerEntries(
            presentationData: presentationData,
            settings: settings,
            isPasswordProtected: isPasswordProtected,
            passwordLockOverride: passwordOverride,
            sessionUnlocked: sessionUnlocked,
            isPremium: isPremium,
            isPremiumEnabled: !isPremiumDisabled
        ), style: .blocks, animateChanges: true)
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    
    presentUndoImpl = { [weak controller] content in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: content, elevatedLayout: false, action: { _ in
            return false
        }), in: .current)
    }
    presentPremiumImpl = { [weak controller] in
        guard let controller else {
            return
        }
        let premiumController = context.sharedContext.makePremiumIntroController(context: context, source: .settings, forceDark: false, dismissed: nil)
        controller.push(premiumController)
    }
    presentControllerImpl = { [weak controller] presented in
        controller?.present(presented, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    
    muteAllArchivedChatsIfNeeded(context: context)
    
    return controller
}
