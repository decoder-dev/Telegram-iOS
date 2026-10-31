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
import LocalAuth
import ItemListPeerItem

private final class ArchiveSettingsControllerArguments {
    let updateUnmuted: (Bool) -> Void
    let updateFolders: (Bool) -> Void
    let updateUnknown: (Bool?) -> Void
    let togglePassword: (Bool) -> Void
    let toggleBiometrics: (Bool) -> Void
    let changePassword: () -> Void
    let lockNow: () -> Void
    let toggleHiddenAccount: (Int64, Bool) -> Void
    let updateLockTargets: (Bool, Bool) -> Void
    let hiddenAccountContext: (Int64) -> AccountContext?

    init(
        updateUnmuted: @escaping (Bool) -> Void,
        updateFolders: @escaping (Bool) -> Void,
        updateUnknown: @escaping (Bool?) -> Void,
        togglePassword: @escaping (Bool) -> Void,
        toggleBiometrics: @escaping (Bool) -> Void,
        changePassword: @escaping () -> Void,
        lockNow: @escaping () -> Void,
        toggleHiddenAccount: @escaping (Int64, Bool) -> Void,
        updateLockTargets: @escaping (Bool, Bool) -> Void,
        hiddenAccountContext: @escaping (Int64) -> AccountContext?
    ) {
        self.updateUnmuted = updateUnmuted
        self.updateFolders = updateFolders
        self.updateUnknown = updateUnknown
        self.togglePassword = togglePassword
        self.toggleBiometrics = toggleBiometrics
        self.changePassword = changePassword
        self.lockNow = lockNow
        self.toggleHiddenAccount = toggleHiddenAccount
        self.updateLockTargets = updateLockTargets
        self.hiddenAccountContext = hiddenAccountContext
    }
}

private enum ArchiveSettingsSection: Int32 {
    case unmuted
    case folders
    case unknown
    case password
    case lockTargets
    case hideAccount
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
    case biometricsValue(isOn: Bool, isFaceId: Bool)
    case changePassword
    case passwordLockNow
    case passwordFooter
    case lockTargetsHeader
    case lockTargetArchive(isOn: Bool, savedMessagesOn: Bool)
    case lockTargetSavedMessages(isOn: Bool, archiveOn: Bool)
    case lockTargetsFooter
    case hiddenAccountsHeader
    case hiddenAccount(index: Int32, row: ArchiveHiddenAccountRow)
    case hiddenAccountsFooter

    var section: ItemListSectionId {
        switch self {
        case .unmutedHeader, .unmutedValue, .unmutedFooter:
            return ArchiveSettingsSection.unmuted.rawValue
        case .foldersHeader, .foldersValue, .foldersFooter:
            return ArchiveSettingsSection.folders.rawValue
        case .unknownHeader, .unknownValue, .unknownFooter:
            return ArchiveSettingsSection.unknown.rawValue
        case .passwordHeader, .passwordValue, .biometricsValue, .changePassword, .passwordLockNow, .passwordFooter:
            return ArchiveSettingsSection.password.rawValue
        case .lockTargetsHeader, .lockTargetArchive, .lockTargetSavedMessages, .lockTargetsFooter:
            return ArchiveSettingsSection.lockTargets.rawValue
        case .hiddenAccountsHeader, .hiddenAccount, .hiddenAccountsFooter:
            return ArchiveSettingsSection.hideAccount.rawValue
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
        case .biometricsValue:
            return 11
        case .changePassword:
            return 12
        case .passwordLockNow:
            return 13
        case .passwordFooter:
            return 14
        case .lockTargetsHeader:
            return 20
        case .lockTargetArchive:
            return 21
        case .lockTargetSavedMessages:
            return 22
        case .lockTargetsFooter:
            return 23
        case .hiddenAccountsHeader:
            return 30
        case let .hiddenAccount(index, _):
            return 100 + index
        case .hiddenAccountsFooter:
            return 10000
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
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.keepArchivedPolicy), sectionId: self.section)
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
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockArchive, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.togglePassword(value)
            })
        case let .biometricsValue(isOn, isFaceId):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: isFaceId ? ArchiveLockLocalizedString.useFaceId : ArchiveLockLocalizedString.useTouchId, value: isOn, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBiometrics(value)
            })
        case .changePassword:
            return ItemListActionItem(presentationData: presentationData, title: ArchiveLockLocalizedString.changePassword, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.changePassword()
            })
        case .passwordLockNow:
            return ItemListActionItem(presentationData: presentationData, title: ArchiveLockLocalizedString.lockNow, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.lockNow()
            })
        case .passwordFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.footer), sectionId: self.section)
        case .lockTargetsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.lockTargetsHeader, sectionId: self.section)
        case let .lockTargetArchive(isOn, savedMessagesOn):
            // The last thing still locked cannot be switched off: turn the other one on first.
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockTargetArchive, value: isOn, enabled: !isOn || savedMessagesOn, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateLockTargets(value, savedMessagesOn)
            })
        case let .lockTargetSavedMessages(isOn, archiveOn):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockTargetSavedMessages, value: isOn, enabled: !isOn || archiveOn, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateLockTargets(archiveOn, value)
            })
        case .lockTargetsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.lockTargetsFooter), sectionId: self.section)
        case .hiddenAccountsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.hiddenAccountsHeader, sectionId: self.section)
        case let .hiddenAccount(_, row):
            guard let accountContext = arguments.hiddenAccountContext(row.accountId) else {
                return ItemListTextItem(presentationData: presentationData, text: .plain(""), sectionId: self.section)
            }
            let accountId = row.accountId
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: PresentationDateTimeFormat(), nameDisplayOrder: .firstLast, context: accountContext, peer: row.peer, height: .generic, aliasHandling: .standard, nameStyle: .plain, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), revealOptions: nil, switchValue: ItemListPeerItemSwitch(value: row.isHidden, style: .standard), enabled: true, selectable: false, sectionId: self.section, action: nil, setPeerIdWithRevealedOptions: { _, _ in }, removePeer: { _ in }, toggleUpdated: { value in
                arguments.toggleHiddenAccount(accountId, value)
            })
        case .hiddenAccountsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.hiddenAccountsFooter), sectionId: self.section)
        }
    }
}

/// What the password locks, as the switches show it.
struct ArchiveLockTargets: Equatable {
    let archive: Bool
    let savedMessages: Bool
}

/// One other signed-in account in the "Hidden accounts" section.
struct ArchiveHiddenAccountRow: Equatable {
    let accountId: Int64
    let peer: EnginePeer
    let isHidden: Bool
}

private func archiveSettingsControllerEntries(
    presentationData: PresentationData,
    settings: GlobalPrivacySettings,
    isPasswordProtected: Bool,
    passwordLockOverride: Bool?,
    sessionUnlocked: Bool,
    isPremium: Bool,
    isPremiumEnabled: Bool,
    biometricAuthentication: LocalAuthBiometricAuthentication?,
    useBiometrics: Bool,
    lockTargets: ArchiveLockTargets,
    hiddenAccountRows: [ArchiveHiddenAccountRow]
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
    if passwordOn {
        if let biometricAuthentication {
            let isFaceId: Bool
            if case .faceId = biometricAuthentication {
                isFaceId = true
            } else {
                isFaceId = false
            }
            entries.append(.biometricsValue(isOn: useBiometrics, isFaceId: isFaceId))
        }
        entries.append(.changePassword)
        if sessionUnlocked {
            entries.append(.passwordLockNow)
        }
    }
    entries.append(.passwordFooter)

    if passwordOn {
        entries.append(.lockTargetsHeader)
        entries.append(.lockTargetArchive(isOn: lockTargets.archive, savedMessagesOn: lockTargets.savedMessages))
        entries.append(.lockTargetSavedMessages(isOn: lockTargets.savedMessages, archiveOn: lockTargets.archive))
        entries.append(.lockTargetsFooter)
    }

    // The other signed-in accounts this password can hide.
    if passwordOn, !hiddenAccountRows.isEmpty {
        entries.append(.hiddenAccountsHeader)
        for (index, row) in hiddenAccountRows.enumerated() {
            entries.append(.hiddenAccount(index: Int32(index), row: row))
        }
        entries.append(.hiddenAccountsFooter)
    }

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
    // Same role as `passwordLockOverride` for a hidden-account switch while its password sheet is open.
    let hiddenAccountOverrides = ValuePromise<[Int64: Bool]>([:], ignoreRepeated: true)
    var hiddenAccountOverridesValue: [Int64: Bool] = [:]
    let updateHiddenAccountOverride: (Int64, Bool?) -> Void = { accountId, value in
        hiddenAccountOverridesValue[accountId] = value
        hiddenAccountOverrides.set(hiddenAccountOverridesValue)
    }
    // Same role for the lock target switches.
    let lockTargetsOverride = ValuePromise<ArchiveLockTargets?>(nil, ignoreRepeated: true)
    // The other accounts, kept for the rows' avatars and for hiding them.
    var otherAccountContexts: [Int64: AccountContext] = [:]
    
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
        toggleBiometrics: { enabled in
            setArchiveUseBiometrics(context: context, enabled: enabled)
        },
        changePassword: {
            changeArchivePassword(context: context, present: { controller in
                presentControllerImpl?(controller)
            }, completion: { success in
                if success {
                    presentUndoImpl?(.info(title: nil, text: ArchiveLockLocalizedString.passwordChanged, timeout: nil, customUndoText: nil))
                }
            })
        },
        lockNow: {
            ArchiveLockSession.shared.relock()
            HiddenAccountsSession.shared.relock()
            sessionUnlockedPromise.set(false)
            Queue.mainQueue().after(0.3, {
                dismissOpenArchiveControllers(from: navigationControllerImpl?(), context: context)
            })
        },
        toggleHiddenAccount: { accountId, hidden in
            guard let hiddenAccount = otherAccountContexts[accountId] else {
                return
            }
            updateHiddenAccountOverride(accountId, hidden)
            setAccountHidden(context: context, hiddenAccount: hiddenAccount, hidden: hidden, present: { controller in
                presentControllerImpl?(controller)
            }, completion: { success in
                if success {
                    updateHiddenAccountOverride(accountId, nil)
                } else {
                    updateHiddenAccountOverride(accountId, !hidden)
                    Queue.mainQueue().after(0.05) {
                        updateHiddenAccountOverride(accountId, nil)
                    }
                }
            })
        },
        updateLockTargets: { archive, savedMessages in
            lockTargetsOverride.set(ArchiveLockTargets(archive: archive, savedMessages: savedMessages))
            setArchiveLockTargets(context: context, archive: archive, savedMessages: savedMessages, present: { controller in
                presentControllerImpl?(controller)
            }, completion: { _ in
                // Back to the stored value either way: a cancelled password leaves it unchanged.
                Queue.mainQueue().after(0.05) {
                    lockTargetsOverride.set(nil)
                }
            })
        },
        hiddenAccountContext: { accountId in
            return otherAccountContexts[accountId]
        }
    )

    // Every other signed-in account, except ones another account hides (a hidden account belongs to its owner).
    let ownerId = context.account.id.int64
    let otherAccounts: Signal<[(AccountContext, EnginePeer)], NoError> = context.sharedContext.activeAccountContexts
    |> mapToSignal { _, accounts, _ -> Signal<[(AccountContext, EnginePeer)], NoError> in
        let others = accounts.filter { $0.1.account.id != context.account.id }.map { $0.1 }
        if others.isEmpty {
            return .single([])
        }
        return combineLatest(others.map { accountContext -> Signal<(AccountContext, EnginePeer)?, NoError> in
            return accountContext.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: accountContext.account.peerId))
            |> map { peer -> (AccountContext, EnginePeer)? in
                return peer.flatMap { (accountContext, $0) }
            }
        })
        |> map { list in
            return list.compactMap { $0 }
        }
    }
    let hiddenAccountRows: Signal<[ArchiveHiddenAccountRow], NoError> = combineLatest(queue: .mainQueue(),
        otherAccounts,
        hiddenAccountsSettings(accountManager: context.sharedContext.accountManager),
        hiddenAccountOverrides.get()
    )
    |> map { accounts, hiddenSettings, overrides -> [ArchiveHiddenAccountRow] in
        // A hidden account (this one) hides nobody: its own Archive could only be opened from inside it.
        if hiddenSettings.isHidden(ownerId) {
            return []
        }
        var rows: [ArchiveHiddenAccountRow] = []
        for (accountContext, peer) in accounts {
            let accountId = accountContext.account.id.int64
            otherAccountContexts[accountId] = accountContext
            if let owner = hiddenSettings.owner(of: accountId), owner != ownerId {
                continue
            }
            rows.append(ArchiveHiddenAccountRow(accountId: accountId, peer: peer, isHidden: overrides[accountId] ?? (hiddenSettings.owner(of: accountId) == ownerId)))
        }
        return rows
    }
    
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.GlobalPrivacy()),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App()),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)),
        passwordLockOverride.get(),
        sessionUnlockedPromise.get(),
        hiddenAccountRows,
        lockTargetsOverride.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, appConfiguration, accountPeer, archiveSettingsPreference, passwordOverride, sessionUnlocked, hiddenAccountRows, lockTargetsOverride -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData

        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)
        
        let isPremium = accountPeer?.isPremium ?? false
        let isPremiumDisabled = PremiumConfiguration.with(appConfiguration: appConfiguration).isPremiumDisabled
        let archiveSettings = archiveSettingsPreference?.get(ChatArchiveSettings.self) ?? .default
        let isPasswordProtected = archiveIsPasswordProtected(peerId: context.account.peerId, settings: archiveSettings)
        // archiveIsPasswordProtected deliberately stays fail-closed when a legacy
        // hash cannot be migrated. Do not discard the only credential in that case.
        if archiveSettings.legacyLockPasswordHash != nil, ArchivePasswordKeychain.hasPassword(peerId: context.account.peerId) {
            let _ = updateChatArchiveSettings(engine: context.engine) { current in
                current.clearingLegacyPasswordHash().withUpdatedIsPasswordConfigured(true)
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
            isPremiumEnabled: !isPremiumDisabled,
            biometricAuthentication: LocalAuth.biometricAuthentication,
            useBiometrics: archiveSettings.useBiometrics,
            lockTargets: lockTargetsOverride ?? ArchiveLockTargets(archive: archiveSettings.locksArchive, savedMessages: archiveSettings.locksSavedMessages),
            hiddenAccountRows: hiddenAccountRows
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
