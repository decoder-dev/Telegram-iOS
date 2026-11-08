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

/// The three screens of the protected Archive (BananaGram iOS 27 handoff, scenes 42, 43 and 26): the Archive itself
/// (status, settings, quick actions), what the password protects, and the accounts it hides. They share one state and
/// one set of actions; the two inner pages are pushed from the first.
enum ArchiveSettingsPage {
    case main
    case scope
    case hiddenAccounts
}

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
    let openPage: (ArchiveSettingsPage) -> Void
    let openArchive: () -> Void

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
        hiddenAccountContext: @escaping (Int64) -> AccountContext?,
        openPage: @escaping (ArchiveSettingsPage) -> Void,
        openArchive: @escaping () -> Void
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
        self.openPage = openPage
        self.openArchive = openArchive
    }
}

private enum ArchiveSettingsSection: Int32 {
    case status
    case settings
    case quick
    case password
    case scopeIntro
    case scope
    case scopeConfirm
    case hiddenIntro
    case hiddenAccounts
    case hiddenProtection
    case unmuted
    case folders
    case unknown
}

private enum ArchiveSettingsControllerEntry: ItemListNodeEntry {
    // Scene 42: the Archive.
    case status(title: String, text: String, isOn: Bool)
    case settingsHeader
    case scopeRow(label: String)
    case hiddenAccountsRow(label: String)
    case biometricsValue(isOn: Bool, isFaceId: Bool)
    case changePassword
    case openArchive
    case quickHeader
    case lockNow
    case quickFooter
    case setPassword
    case passwordOffFooter
    case removePassword

    // Scene 43: what the password protects.
    case scopeIntro
    case scopeHeader
    case lockTargetArchive(isOn: Bool, savedMessagesOn: Bool)
    case lockTargetSavedMessages(isOn: Bool, archiveOn: Bool)
    case scopeConfirm

    // Scene 26: the accounts it hides.
    case hiddenIntro
    case hiddenAccountsHeader
    case hiddenAccount(index: Int32, row: ArchiveHiddenAccountRow)
    case hiddenAccountsFooter
    case protectionHeader
    case changeArchivePassword
    case protectionLockNow

    // Telegram's own Archive settings, kept under the lock on the first page.
    case unmutedHeader
    case unmutedValue(Bool)
    case unmutedFooter
    case unknownHeader
    case unknownValue(isOn: Bool, isLocked: Bool)
    case unknownFooter

    var section: ItemListSectionId {
        switch self {
        case .status:
            return ArchiveSettingsSection.status.rawValue
        case .settingsHeader, .scopeRow, .hiddenAccountsRow, .biometricsValue, .changePassword, .openArchive, .setPassword, .passwordOffFooter:
            return ArchiveSettingsSection.settings.rawValue
        case .quickHeader, .lockNow, .quickFooter:
            return ArchiveSettingsSection.quick.rawValue
        case .removePassword:
            return ArchiveSettingsSection.password.rawValue
        case .scopeIntro:
            return ArchiveSettingsSection.scopeIntro.rawValue
        case .scopeHeader, .lockTargetArchive, .lockTargetSavedMessages:
            return ArchiveSettingsSection.scope.rawValue
        case .scopeConfirm:
            return ArchiveSettingsSection.scopeConfirm.rawValue
        case .hiddenIntro:
            return ArchiveSettingsSection.hiddenIntro.rawValue
        case .hiddenAccountsHeader, .hiddenAccount:
            return ArchiveSettingsSection.hiddenAccounts.rawValue
        case .protectionHeader, .changeArchivePassword, .protectionLockNow, .hiddenAccountsFooter:
            return ArchiveSettingsSection.hiddenProtection.rawValue
        case .unmutedHeader, .unmutedValue, .unmutedFooter:
            return ArchiveSettingsSection.unmuted.rawValue
        case .unknownHeader, .unknownValue, .unknownFooter:
            return ArchiveSettingsSection.unknown.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .status: return 0
        case .settingsHeader: return 10
        case .scopeRow: return 11
        case .hiddenAccountsRow: return 12
        case .biometricsValue: return 13
        case .changePassword: return 14
        case .openArchive: return 15
        case .setPassword: return 16
        case .passwordOffFooter: return 17
        case .quickHeader: return 20
        case .lockNow: return 21
        case .quickFooter: return 22
        case .removePassword: return 30
        case .scopeIntro: return 40
        case .scopeHeader: return 41
        case .lockTargetArchive: return 42
        case .lockTargetSavedMessages: return 43
        case .scopeConfirm: return 44
        case .hiddenIntro: return 50
        case .hiddenAccountsHeader: return 51
        case let .hiddenAccount(index, _): return 100 + index
        case .protectionHeader: return 5000
        case .changeArchivePassword: return 5001
        case .protectionLockNow: return 5002
        case .hiddenAccountsFooter: return 5003
        case .unmutedHeader: return 6000
        case .unmutedValue: return 6001
        case .unmutedFooter: return 6002
        case .unknownHeader: return 6010
        case .unknownValue: return 6011
        case .unknownFooter: return 6012
        }
    }
        
    static func <(lhs: ArchiveSettingsControllerEntry, rhs: ArchiveSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ArchiveSettingsControllerArguments
        switch self {
        case let .status(_, text, _):
            // The state is said in plain text above the settings, not on a card that looks like a row and does nothing.
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .settingsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.settingsHeader, sectionId: self.section)
        case let .scopeRow(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.scopeRow, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openPage(.scope)
            })
        case let .hiddenAccountsRow(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.hiddenAccountsRow, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openPage(.hiddenAccounts)
            })
        case let .biometricsValue(isOn, isFaceId):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: isFaceId ? ArchiveLockLocalizedString.useFaceId : ArchiveLockLocalizedString.useTouchId, value: isOn, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBiometrics(value)
            })
        case .changePassword:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.changePassword, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.changePassword()
            })
        case .openArchive:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.openArchive, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openArchive()
            })
        case .quickHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.quickHeader, sectionId: self.section)
        case .lockNow:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockNow, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.lockNow()
            })
        case .quickFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.quickFooter), sectionId: self.section)
        case .setPassword:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.setPassword, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.togglePassword(true)
            })
        case .passwordOffFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.footer), sectionId: self.section)
        case .removePassword:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.removePassword, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.togglePassword(false)
            })
        case .scopeIntro:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.scopeIntro), sectionId: self.section)
        case .scopeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.scopeHeader, sectionId: self.section)
        case let .lockTargetArchive(isOn, savedMessagesOn):
            // The last thing still locked cannot be switched off: turn the other one on first.
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.scopeArchive, value: isOn, enabled: !isOn || savedMessagesOn, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateLockTargets(value, savedMessagesOn)
            })
        case let .lockTargetSavedMessages(isOn, archiveOn):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockTargetSavedMessages, value: isOn, enabled: !isOn || archiveOn, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateLockTargets(archiveOn, value)
            })
        case .scopeConfirm:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.scopeConfirmText), sectionId: self.section)
        case .hiddenIntro:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.hiddenIntro), sectionId: self.section)
        case .hiddenAccountsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.hiddenAccountsListHeader, sectionId: self.section)
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
        case .protectionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ArchiveLockLocalizedString.protectionHeader, sectionId: self.section)
        case .changeArchivePassword:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.changeArchivePassword, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.changePassword()
            })
        case .protectionLockNow:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.lockNow, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.lockNow()
            })
        case .unmutedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: presentationData.strings.ArchiveSettings_UnmutedChatsHeader, sectionId: self.section)
        case let .unmutedValue(value):
            // The policy is fixed (the footer says why), so it is a row with its state, not a switch that cannot be
            // switched (Apple HIG: don't show a control people can't use).
            let russian = ForkPresentationLanguage.prefersRussianStrings
            let state = value ? (russian ? "Всегда" : "Always") : (russian ? "Выкл." : "Off")
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ArchiveLockLocalizedString.keepInArchive, label: state, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .unmutedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ArchiveLockLocalizedString.keepArchivedPolicy), sectionId: self.section)
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
    page: ArchiveSettingsPage,
    settings: GlobalPrivacySettings,
    isPasswordProtected: Bool,
    passwordLockOverride: Bool?,
    isPremium: Bool,
    isPremiumEnabled: Bool,
    biometricAuthentication: LocalAuthBiometricAuthentication?,
    useBiometrics: Bool,
    lockTargets: ArchiveLockTargets,
    hiddenAccountRows: [ArchiveHiddenAccountRow]
) -> [ArchiveSettingsControllerEntry] {
    var entries: [ArchiveSettingsControllerEntry] = []
    let passwordOn = passwordLockOverride ?? isPasswordProtected

    switch page {
    case .main:
        if passwordOn {
            let statusText: String
            if lockTargets.archive && lockTargets.savedMessages {
                statusText = ArchiveLockLocalizedString.statusOnBoth
            } else if lockTargets.archive {
                statusText = ArchiveLockLocalizedString.statusOnArchive
            } else {
                statusText = ArchiveLockLocalizedString.statusOnSaved
            }
            entries.append(.status(title: ArchiveLockLocalizedString.statusOnTitle, text: statusText, isOn: true))

            entries.append(.settingsHeader)
            let scopeLabel: String
            if lockTargets.archive && lockTargets.savedMessages {
                scopeLabel = ArchiveLockLocalizedString.scopeCountBoth
            } else if lockTargets.archive {
                scopeLabel = ArchiveLockLocalizedString.lockTargetArchive
            } else {
                scopeLabel = ArchiveLockLocalizedString.lockTargetSavedMessages
            }
            entries.append(.scopeRow(label: scopeLabel))
            // Hiding needs another signed-in account; a hidden account hides nobody (the rows are empty then).
            if !hiddenAccountRows.isEmpty {
                let hiddenCount = hiddenAccountRows.filter { $0.isHidden }.count
                entries.append(.hiddenAccountsRow(label: hiddenCount == 0 ? ArchiveLockLocalizedString.hiddenAccountsNone : "\(hiddenCount)"))
            }
            if let biometricAuthentication {
                let isFaceId: Bool
                if case .faceId = biometricAuthentication {
                    isFaceId = true
                } else {
                    isFaceId = false
                }
                entries.append(.biometricsValue(isOn: useBiometrics, isFaceId: isFaceId))
            }
            // No "Open Archive" row: these settings open only from inside the Archive, so it would push a second copy.
            entries.append(.changePassword)

            entries.append(.quickHeader)
            entries.append(.lockNow)
            entries.append(.quickFooter)

            entries.append(.removePassword)
        } else {
            entries.append(.status(title: ArchiveLockLocalizedString.statusOffTitle, text: ArchiveLockLocalizedString.statusOffText, isOn: false))
            entries.append(.setPassword)
            entries.append(.passwordOffFooter)
        }

        entries.append(.unmutedHeader)
        // Force-mute policy: keep archived even if manually unmuted later.
        entries.append(.unmutedValue(true))
        entries.append(.unmutedFooter)

        if isPremium || isPremiumEnabled {
            entries.append(.unknownHeader)
            entries.append(.unknownValue(isOn: isPremium && settings.automaticallyArchiveAndMuteNonContacts, isLocked: !isPremium))
            entries.append(.unknownFooter)
        }
    case .scope:
        entries.append(.scopeIntro)
        entries.append(.scopeHeader)
        entries.append(.lockTargetArchive(isOn: lockTargets.archive, savedMessagesOn: lockTargets.savedMessages))
        entries.append(.lockTargetSavedMessages(isOn: lockTargets.savedMessages, archiveOn: lockTargets.archive))
        entries.append(.scopeConfirm)
    case .hiddenAccounts:
        entries.append(.hiddenIntro)
        if !hiddenAccountRows.isEmpty {
            entries.append(.hiddenAccountsHeader)
            for (index, row) in hiddenAccountRows.enumerated() {
                entries.append(.hiddenAccount(index: Int32(index), row: row))
            }
        }
        entries.append(.protectionHeader)
        entries.append(.changeArchivePassword)
        entries.append(.protectionLockNow)
        entries.append(.hiddenAccountsFooter)
    }

    return entries
}

public func archiveSettingsController(context: AccountContext) -> ViewController {
    return archiveSettingsController(context: context, page: .main)
}

func archiveSettingsController(context: AccountContext, page: ArchiveSettingsPage) -> ViewController {
    let updateDisposable = MetaDisposable()
    
    updateDisposable.set(context.engine.privacy.requestAccountPrivacySettings().start())
    
    var presentUndoImpl: ((UndoOverlayContent) -> Void)?
    var presentPremiumImpl: (() -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?
    var pushControllerImpl: ((ViewController) -> Void)?
    
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
        },
        openPage: { page in
            guard case .hiddenAccounts = page else {
                pushControllerImpl?(archiveSettingsController(context: context, page: page))
                return
            }
            // The hidden accounts are behind the password whatever it locks. With only Saved Messages locked the
            // Archive (and these settings in it) opens without it, so the list asks for it here; with the Archive
            // locked the session is already open and this goes straight through.
            let _ = (context.engine.data.get(
                TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
            )
            |> deliverOnMainQueue).startStandalone(next: { preference in
                let settings = preference?.get(ChatArchiveSettings.self) ?? .default
                ensureArchiveUnlocked(context: context, forSavedMessages: !settings.locksArchive, present: { controller in
                    presentControllerImpl?(controller)
                }, completion: { result in
                    switch result {
                    case .cancelled:
                        return
                    case .unlocked, .notProtected:
                        pushControllerImpl?(archiveSettingsController(context: context, page: page))
                    }
                })
            })
        },
        openArchive: {
            // The password first (or nothing, when the Archive is not locked), then the Archive itself, as the
            // chat list opens it.
            ensureArchiveUnlocked(context: context, present: { controller in
                presentControllerImpl?(controller)
            }, completion: { result in
                switch result {
                case .cancelled:
                    return
                case .unlocked, .notProtected:
                    let chatListController = ChatListControllerImpl(context: context, location: .chatList(groupId: .archive), controlsHistoryPreload: false, enableDebugActions: false)
                    chatListController.navigationPresentation = .master
                    pushControllerImpl?(chatListController)
                }
            })
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
    |> map { presentationData, settings, appConfiguration, accountPeer, archiveSettingsPreference, passwordOverride, _, hiddenAccountRows, lockTargetsOverride -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData

        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let title: String
        switch page {
        case .main:
            title = ArchiveLockLocalizedString.screenTitle
        case .scope:
            title = ArchiveLockLocalizedString.scopeTitle
        case .hiddenAccounts:
            title = ArchiveLockLocalizedString.hiddenAccountsRow
        }
        
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

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: archiveSettingsControllerEntries(
            page: page,
            settings: settings,
            isPasswordProtected: isPasswordProtected,
            passwordLockOverride: passwordOverride,
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
    // Every page of these settings (the hidden accounts' list among them) closes with the Archive when it locks again,
    // whichever way it was opened: the Archive's "…" menu, its "How it works" sheet, or another page of these settings.
    markArchiveLockProtected(controller)
    if case .main = page {
        controller.navigationPresentation = .modal
    }
    
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
    pushControllerImpl = { [weak controller] pushed in
        (controller?.navigationController as? NavigationController)?.pushViewController(pushed)
    }
    
    if case .main = page {
        muteAllArchivedChatsIfNeeded(context: context)
    }
    
    return controller
}
