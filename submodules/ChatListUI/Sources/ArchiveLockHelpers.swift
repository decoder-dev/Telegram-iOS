import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import LocalAuth
import GalleryUI
import StoryContainerScreen

public enum ArchiveUnlockResult {
    case unlocked
    case cancelled
    /// Archive is not password-protected.
    case notProtected
}

private func migrateAndResolvePasswordProtected(context: AccountContext, settings: ChatArchiveSettings) -> Bool {
    let peerId = context.account.peerId
    let protected = archiveIsPasswordProtected(peerId: peerId, settings: settings)
    if settings.legacyLockPasswordHash != nil || (protected && !settings.isPasswordConfigured) {
        // Also backfills isPasswordConfigured for accounts that set a password before that
        // flag existed, so the notification/CallKit redaction check (which only has Postbox,
        // not Keychain, access in the Notification Service Extension) stays correct.
        let _ = updateChatArchiveSettings(engine: context.engine) { current in
            current.clearingLegacyPasswordHash().withUpdatedIsPasswordConfigured(true)
        }.startStandalone()
    }
    return protected
}

/// Remove any OS notifications already sitting in Notification Center for peers that just
/// became password-locked-archived — otherwise a banner delivered before the lock was set stays
/// visible (with sender name/text) until manually dismissed, undermining the point of hiding
/// the conversation. Matches on the "peerId" key the Notification Service Extension already
/// stamps into each notification's userInfo (Telegram/NotificationService/Sources/NotificationService.swift).
private func clearDeliveredNotifications(forPeerIds peerIds: Set<Int64>) {
    guard !peerIds.isEmpty else {
        return
    }
    UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { notifications in
        let matchingIdentifiers = notifications.compactMap { notification -> String? in
            guard let peerIdValue = notificationPeerIdValue(notification.request.content.userInfo), peerIds.contains(peerIdValue) else {
                return nil
            }
            return notification.request.identifier
        }
        guard !matchingIdentifiers.isEmpty else {
            return
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: matchingIdentifiers)
    })
}

private func notificationPeerIdValue(_ userInfo: [AnyHashable: Any]) -> Int64? {
    if let peerId = userInfo["peerId"] as? Int64 {
        return peerId
    }
    if let number = userInfo["peerId"] as? NSNumber {
        return number.int64Value
    }
    if let peerIdString = userInfo["peerId"] as? String {
        return Int64(peerIdString)
    }
    return nil
}

/// Sweep currently-delivered notifications for peers in a password-protected Archive.
/// Call after password-protection turns on, and after moving chats into Archive while a password is set.
public func clearStaleArchiveNotifications(context: AccountContext, peerIds: [EnginePeer.Id]? = nil) {
    let _ = (context.account.postbox.transaction { transaction -> Set<Int64> in
        let settings = transaction.getPreferencesEntry(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)?.get(ChatArchiveSettings.self) ?? .default
        guard settings.isPasswordConfigured else {
            return []
        }
        if let peerIds {
            return Set(peerIds.compactMap { peerId -> Int64? in
                guard archiveNotificationShouldRedact(transaction: transaction, peerId: peerId) else {
                    return nil
                }
                return peerId.toInt64()
            })
        }
        return Set(transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive).map { $0.toInt64() })
    }
    |> deliverOnMainQueue).startStandalone(next: { peerIds in
        clearDeliveredNotifications(forPeerIds: peerIds)
    })
}

/// Whether this account's Archive is password-protected, re-evaluated whenever the archive
/// preferences change. `setArchivePassword` / `removeArchivePassword` both write
/// `isPasswordConfigured` alongside the Keychain, so the preference is what makes this reactive.
///
/// Both sources are consulted, and either one alone means protected. The Keychain is the authority
/// but its items are `WhenUnlockedThisDeviceOnly`, so a read that lands while the device is locked
/// — a preference write from a background push, say — answers "no password" for a protected
/// account, and this signal decides whether the Archive folder is listed at all. The Postbox mirror
/// is readable in that state and holds it closed; the Keychain covers the reverse case, an account
/// that set its password before the mirror existed and has not been migrated yet.
public func archivePasswordProtectionSignal(context: AccountContext) -> Signal<Bool, NoError> {
    let peerId = context.account.peerId
    return context.engine.data.subscribe(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> map { preference -> Bool in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        if settings.isPasswordConfigured {
            return true
        }
        return archiveIsPasswordProtected(peerId: peerId, settings: settings)
    }
    |> distinctUntilChanged
}

private weak var archiveSwitcherCoveringView: WindowCoveringView?

private func navigationContainsArchiveUI(_ navigationController: NavigationController, archivedPeerIds: Set<EnginePeer.Id>) -> Bool {
    let check: (UIViewController) -> Bool = { controller in
        return archiveLockShouldDismiss(controller, archivedPeerIds: archivedPeerIds)
    }
    if navigationController.viewControllers.contains(where: check) {
        return true
    }
    if navigationController.overlayControllers.contains(where: check) {
        return true
    }
    if navigationController.globalOverlayControllers.contains(where: check) {
        return true
    }
    if let tabController = navigationController.viewControllers.first as? TabBarController {
        if tabController.controllers.contains(where: check) {
            return true
        }
    }
    return false
}

/// Whether App Switcher would currently snapshot Archive contents: unlocked session plus either
/// the revealed folder row (names/previews on the main list) or an archive chat/folder/peer-info
/// controller on the navigation stack.
private func archiveLockSwitcherCoverNeeded(context: AccountContext) -> Bool {
    guard ArchiveLockSession.shared.isPasswordConfigured else {
        return false
    }
    guard ArchiveLockSession.shared.isUnlocked else {
        return false
    }
    if ArchiveLockSession.shared.isRevealed {
        return true
    }
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return true
    }
    return navigationContainsArchiveUI(navigationController, archivedPeerIds: ArchiveLockSession.shared.currentLockedPeerIds())
}

/// Solid cover on `mainWindow` so the App Switcher snapshot cannot show Archive contents.
/// Skips if App Lock (or anything else) already owns `coveringView`. Weak-ref stored so
/// foreground cleanup only removes *this* cover.
public func applyArchiveLockSwitcherCover(context: AccountContext) {
    guard archiveLockSwitcherCoverNeeded(context: context) else {
        return
    }
    guard let window = context.sharedContext.mainWindow else {
        return
    }
    if window.coveringView != nil {
        return
    }
    let coveringView = WindowCoveringView()
    coveringView.backgroundColor = context.sharedContext.currentPresentationData.with({ $0 }).theme.chatList.backgroundColor
    window.coveringView = coveringView
    archiveSwitcherCoveringView = coveringView
}

private func archiveControllersRemainOnStack(context: AccountContext) -> Bool {
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return false
    }
    return navigationContainsArchiveUI(navigationController, archivedPeerIds: ArchiveLockSession.shared.currentLockedPeerIds())
}

private func archiveNavigationController(context: AccountContext) -> UINavigationController? {
    return context.sharedContext.mainWindow?.viewController as? UINavigationController
}

/// Cover Archive UI, then dismiss Archive controllers on the current runloop so the
/// App Switcher snapshot cannot show them after the cover is later removed.
public func prepareArchivePrivacyOnResignActive(context: AccountContext) {
    applyArchiveLockSwitcherCover(context: context)
    guard ArchiveLockSession.shared.isLockActive else {
        return
    }
    dismissOpenArchiveControllers(from: archiveNavigationController(context: context), context: context)
}

/// Drop remaining Archive surfaces, then remove the switcher cover only once they are gone.
public func restoreArchivePrivacyOnBecomeActive(context: AccountContext) {
    if ArchiveLockSession.shared.isLockActive {
        dismissOpenArchiveControllers(from: archiveNavigationController(context: context), context: context)
    }
    removeArchiveLockSwitcherCover(context: context)
}

/// Drop the Archive cover on foreground unless App Lock has replaced it, or Archive
/// controllers are still on the stack (cover must outlive dismiss).
public func removeArchiveLockSwitcherCover(context: AccountContext) {
    guard let coveringView = archiveSwitcherCoveringView else {
        return
    }
    if archiveControllersRemainOnStack(context: context) {
        return
    }
    archiveSwitcherCoveringView = nil
    guard let window = context.sharedContext.mainWindow else {
        return
    }
    if window.coveringView === coveringView {
        window.coveringView = nil
    }
}

private func archiveLockedPeerIdsSignal(context: AccountContext) -> Signal<Set<EnginePeer.Id>, NoError> {
    let passwordConfigured = context.engine.data.subscribe(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> map { preference -> Bool in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        return settings.isPasswordConfigured
    }
    |> distinctUntilChanged
    
    return combineLatest(
        passwordConfigured,
        context.engine.messages.chatList(group: .archive, count: 100)
    )
    |> mapToSignal { configured, _ -> Signal<Set<EnginePeer.Id>, NoError> in
        if !configured {
            return .single([])
        }
        return context.account.postbox.transaction { transaction in
            return archiveLockedPeerIds(transaction: transaction)
        }
    }
    |> distinctUntilChanged
}

/// Sync Peer Info gate: false when a password is configured, the session is locked, and the
/// peer lives in Archive (or the locked-peer cache has not been read yet — fail closed).
public func archivePeerInfoAllowed(context: AccountContext, peerId: EnginePeer.Id) -> Bool {
    bindArchiveLockSession(context: context)
    return !ArchiveLockSession.shared.isLockedArchivedPeer(peerId)
}

/// Unlock if needed, then `makePeerInfoController` + push. Use at ungated `fromChat: false`
/// call sites so the central gate returning nil is not a dead end.
public func presentPeerInfoEnsuringArchiveAccess(
    context: AccountContext,
    peer: EnginePeer,
    updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil,
    avatarInitiallyExpanded: Bool = false,
    presentUnlock: @escaping (ViewController) -> Void,
    push: @escaping (ViewController) -> Void
) {
    ensureArchivedPeerAccessible(context: context, peerId: peer.id, present: presentUnlock, completion: { result in
        switch result {
        case .cancelled:
            return
        case .unlocked, .notProtected:
            break
        }
        if let infoController = context.sharedContext.makePeerInfoController(
            context: context,
            updatedPresentationData: updatedPresentationData,
            peer: peer,
            mode: .generic,
            avatarInitiallyExpanded: avatarInitiallyExpanded,
            fromChat: false,
            requestsContext: nil
        ) {
            push(infoController)
        }
    })
}

/// Relock when the last Archive folder / archived chat / archived Peer Info leaves the stack.
/// Safe to call from `viewWillLeaveNavigation` (`isLeavingNavigation: true`) and
/// `viewDidDisappear` (`isLeavingNavigation: false`); matches the folder-leave helper.
public func relockArchiveSessionIfLeavingArchivedSurface(
    leavingController: UIViewController,
    isLeavingNavigation: Bool,
    context: AccountContext
) {
    guard ArchiveLockSession.shared.isPasswordConfigured else {
        return
    }
    guard ArchiveLockSession.shared.isUnlocked || ArchiveLockSession.shared.isRevealed else {
        return
    }
    if let chatList = leavingController as? ChatListControllerImpl, chatList.previewing {
        return
    }
    
    let apply: (Set<EnginePeer.Id>) -> Void = { archivedPeerIds in
        guard ArchiveLockSession.shared.isPasswordConfigured else {
            return
        }
        guard ArchiveLockSession.shared.isUnlocked || ArchiveLockSession.shared.isRevealed else {
            return
        }
        guard archiveLockShouldDismiss(leavingController, archivedPeerIds: archivedPeerIds) else {
            return
        }
        
        if let navigationController = leavingController.navigationController {
            let controllers = navigationController.viewControllers
            if let index = controllers.firstIndex(where: { $0 === leavingController }), index + 1 < controllers.count {
                return
            }
            let otherArchiveRemains = controllers.contains { controller in
                if controller === leavingController {
                    return false
                }
                return archiveLockShouldDismiss(controller, archivedPeerIds: archivedPeerIds)
            }
            if otherArchiveRemains {
                return
            }
            if !isLeavingNavigation, controllers.contains(where: { $0 === leavingController }) {
                return
            }
        } else if !isLeavingNavigation {
            return
        }
        
        ArchiveLockSession.shared.relock()
    }
    
    if ArchiveLockSession.shared.areLockedPeerIdsResolved {
        apply(ArchiveLockSession.shared.currentLockedPeerIds())
    } else {
        let _ = (context.account.postbox.transaction { transaction -> Set<EnginePeer.Id> in
            return archiveLockedPeerIds(transaction: transaction)
        }
        |> deliverOnMainQueue).startStandalone(next: apply)
    }
}

/// Wires the shared `ArchiveLockSession` to this account: re-lock on background, and keep its
/// notion of "this account has an Archive password" current. Without the latter every gate stays
/// fail-closed, which would hide the Archive from accounts that never set a password.
/// Both bindings are idempotent, so call this from anywhere that is about to consult the session.
public func bindArchiveLockSession(context: AccountContext) {
    ArchiveLockSession.shared.bindBackgroundRelock(
        applicationIsActive: context.sharedContext.applicationBindings.applicationIsActive,
        willRelock: { [weak context] in
            guard let context else {
                return
            }
            prepareArchivePrivacyOnResignActive(context: context)
        },
        didBecomeActive: { [weak context] in
            guard let context else {
                return
            }
            restoreArchivePrivacyOnBecomeActive(context: context)
        }
    )
    ArchiveLockSession.shared.bindPasswordProtection(accountId: context.account.id.int64, isPasswordConfigured: archivePasswordProtectionSignal(context: context))
    ArchiveLockSession.shared.bindLockedPeerIds(accountId: context.account.id.int64, lockedPeerIds: archiveLockedPeerIdsSignal(context: context))
}

/// Align server-side keepArchivedUnmuted with local force-mute: unmuted
/// archived chats (if any) should stay in Archive rather than auto-unarchiving.
func alignKeepArchivedUnmutedIfNeeded(context: AccountContext) {
    guard ArchiveLockSession.shared.claimKeepArchivedAlign(accountPeerId: context.account.peerId) else {
        return
    }
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.GlobalPrivacy())
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { settings in
        if !settings.keepArchivedUnmuted {
            let _ = context.engine.privacy.updateAccountKeepArchivedUnmuted(value: true).startStandalone()
        }
    })
}

/// Ensures the Archive folder can be opened. If a password is set and the
/// current session is locked, presents a prompt; otherwise proceeds immediately.
public func ensureArchiveUnlocked(
    context: AccountContext,
    present: @escaping (ViewController) -> Void,
    completion: @escaping (ArchiveUnlockResult) -> Void
) {
    bindArchiveLockSession(context: context)
    
    let _ = (context.engine.data.get(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> deliverOnMainQueue).startStandalone(next: { preference in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        guard migrateAndResolvePasswordProtected(context: context, settings: settings) else {
            completion(.notProtected)
            return
        }
        if ArchiveLockSession.shared.isUnlocked {
            completion(.unlocked)
            return
        }

        func showPasswordPrompt() {
            presentArchivePasswordAlert(
                context: context,
                title: ArchiveLockLocalizedString.enterTitle,
                message: ArchiveLockLocalizedString.enterText,
                confirmTitle: ArchiveLockLocalizedString.unlock,
                verifyPassword: true,
                onSuccess: {
                    ArchiveLockSession.shared.unlock()
                    completion(.unlocked)
                },
                onCancel: {
                    completion(.cancelled)
                }
            )
        }

        // Face ID/Touch ID is a convenience on top of the password, not a replacement for
        // it: it only ever grants access this way when the account already has a password
        // set (checked above) and the user opted in per-account. A cancel/failure always
        // falls through to the password prompt — never a dead end.
        if settings.useBiometrics, LocalAuth.biometricAuthentication != nil {
            let _ = (LocalAuth.auth(reason: ArchiveLockLocalizedString.biometricReason)
            |> deliverOnMainQueue).start(next: { success, _ in
                if success {
                    // Same reset the password path does on success. Both outcomes mean the owner
                    // proved who they are, and the counter throttles guessing, not the owner — but
                    // only one of the two was clearing it, so unlocking with Face ID left the
                    // cooldown standing and the next password entry could still be refused.
                    ArchivePasswordKeychain.clearFailureState(peerId: context.account.peerId)
                    ArchiveLockSession.shared.unlock()
                    completion(.unlocked)
                } else {
                    showPasswordPrompt()
                }
            })
        } else {
            showPasswordPrompt()
        }
    })
}

/// Gate for opening a specific peer that may live in the Archive.
public func ensureArchivedPeerAccessible(
    context: AccountContext,
    peerId: EnginePeer.Id,
    present: @escaping (ViewController) -> Void,
    completion: @escaping (ArchiveUnlockResult) -> Void
) {
    bindArchiveLockSession(context: context)
    
    let _ = (combineLatest(
        context.engine.data.get(TelegramEngine.EngineData.Item.Messages.ChatListGroup(id: peerId)),
        context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings))
    )
    |> deliverOnMainQueue).startStandalone(next: { group, preference in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        let protected = migrateAndResolvePasswordProtected(context: context, settings: settings)
        guard group == .archive, protected else {
            completion(.notProtected)
            return
        }
        if ArchiveLockSession.shared.isUnlocked {
            completion(.unlocked)
            return
        }
        ensureArchiveUnlocked(context: context, present: present, completion: completion)
    })
}

private func presentArchivePasswordAlert(
    context: AccountContext,
    title: String,
    message: String?,
    confirmTitle: String,
    verifyPassword: Bool,
    onSuccess: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    capturePassword: ((String) -> Void)? = nil
) {
    let peerId = context.account.peerId
    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings

    func cooldownMessage(_ remaining: Double) -> String {
        return ArchiveLockLocalizedString.tooManyAttempts(seconds: max(1, Int(remaining.rounded(.up))))
    }

    func show(messageOverride: String?) {
        // The failure/cooldown counter is Keychain-backed (ArchivePasswordKeychain), not a
        // local variable, so cancelling and reopening this prompt can't be used to reset an
        // attempt limit — see ArchivePasswordKeychain's brute-force throttling section.
        if verifyPassword {
            let remaining = ArchivePasswordKeychain.remainingCooldown(peerId: peerId)
            if remaining > 0 {
                let cooldownAlert = UIAlertController(title: title, message: cooldownMessage(remaining), preferredStyle: .alert)
                cooldownAlert.addAction(UIAlertAction(title: strings.Common_OK, style: .cancel, handler: { _ in
                    onCancel()
                }))
                presentUIAlert(context: context, alert: cooldownAlert, onUnavailableHost: onCancel)
                return
            }
        }

        let alert = UIAlertController(title: title, message: messageOverride ?? message, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = ArchiveLockLocalizedString.passwordPlaceholder
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: { _ in
            onCancel()
        }))
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default, handler: { _ in
            let trimmed = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if verifyPassword {
                if ArchivePasswordKeychain.matchesPassword(trimmed, peerId: peerId) {
                    ArchivePasswordKeychain.clearFailureState(peerId: peerId)
                    onSuccess()
                } else {
                    ArchivePasswordKeychain.recordFailure(peerId: peerId)
                    let remaining = ArchivePasswordKeychain.remainingCooldown(peerId: peerId)
                    Queue.mainQueue().after(0.3) {
                        if remaining > 0 {
                            show(messageOverride: cooldownMessage(remaining))
                        } else {
                            let attemptsLeft = max(0, 5 - ArchivePasswordKeychain.failureCount(peerId: peerId))
                            show(messageOverride: ArchiveLockLocalizedString.incorrectPassword(attemptsLeft: attemptsLeft))
                        }
                    }
                }
            } else if let capturePassword {
                if trimmed.isEmpty {
                    onCancel()
                } else {
                    Queue.mainQueue().after(0.2) {
                        let confirm = UIAlertController(title: ArchiveLockLocalizedString.confirmTitle, message: ArchiveLockLocalizedString.confirmText, preferredStyle: .alert)
                        confirm.addTextField { field in
                            field.isSecureTextEntry = true
                            field.placeholder = ArchiveLockLocalizedString.passwordPlaceholder
                            field.autocorrectionType = .no
                            field.autocapitalizationType = .none
                        }
                        confirm.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: { _ in
                            onCancel()
                        }))
                        confirm.addAction(UIAlertAction(title: strings.Common_Done, style: .default, handler: { _ in
                            let confirmValue = (confirm.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if confirmValue == trimmed {
                                capturePassword(trimmed)
                                onSuccess()
                            } else {
                                Queue.mainQueue().after(0.3) {
                                    show(messageOverride: ArchiveLockLocalizedString.passwordsDoNotMatch)
                                }
                            }
                        }))
                        presentUIAlert(context: context, alert: confirm, onUnavailableHost: onCancel)
                    }
                }
            } else {
                onCancel()
            }
        }))
        presentUIAlert(context: context, alert: alert, onUnavailableHost: onCancel)
    }
    
    show(messageOverride: nil)
}

private func presentUIAlert(context: AccountContext, alert: UIAlertController, onUnavailableHost: @escaping () -> Void) {
    if let host = context.sharedContext.applicationBindings.getTopWindow()?.rootViewController {
        var presenter = host
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    } else {
        onUnavailableHost()
    }
}

public func setArchivePassword(context: AccountContext, present: @escaping (ViewController) -> Void, completion: @escaping (Bool) -> Void) {
    presentArchivePasswordAlert(
        context: context,
        title: ArchiveLockLocalizedString.setTitle,
        message: ArchiveLockLocalizedString.setText,
        confirmTitle: ArchiveLockLocalizedString.continueAction,
        verifyPassword: false,
        onSuccess: {
            ArchiveLockSession.shared.unlock()
            alignKeepArchivedUnmutedIfNeeded(context: context)
            clearStaleArchiveNotifications(context: context)
            completion(true)
        },
        onCancel: {
            completion(false)
        },
        capturePassword: { password in
            _ = ArchivePasswordKeychain.store(password: password, peerId: context.account.peerId)
            ArchivePasswordKeychain.clearFailureState(peerId: context.account.peerId)
            let _ = updateChatArchiveSettings(engine: context.engine) { current in
                current.clearingLegacyPasswordHash().withUpdatedIsPasswordConfigured(true)
            }.startStandalone()
        }
    )
}

/// Rotate the Archive password: verify the current one, then capture and store a new one.
/// Reuses the same verify → confirm-new-password flow as initial setup.
public func changeArchivePassword(context: AccountContext, present: @escaping (ViewController) -> Void, completion: @escaping (Bool) -> Void) {
    presentArchivePasswordAlert(
        context: context,
        title: ArchiveLockLocalizedString.enterTitle,
        message: ArchiveLockLocalizedString.changeCurrentText,
        confirmTitle: ArchiveLockLocalizedString.continueAction,
        verifyPassword: true,
        onSuccess: {
            presentArchivePasswordAlert(
                context: context,
                title: ArchiveLockLocalizedString.setTitle,
                message: ArchiveLockLocalizedString.setText,
                confirmTitle: ArchiveLockLocalizedString.continueAction,
                verifyPassword: false,
                onSuccess: {
                    completion(true)
                },
                onCancel: {
                    completion(false)
                },
                capturePassword: { password in
                    _ = ArchivePasswordKeychain.store(password: password, peerId: context.account.peerId)
                    ArchivePasswordKeychain.clearFailureState(peerId: context.account.peerId)
                }
            )
        },
        onCancel: {
            completion(false)
        }
    )
}

/// Toggle per-account Face ID/Touch ID as a convenience unlock. Only meaningful while a
/// password is set; the settings UI hides this row otherwise.
public func setArchiveUseBiometrics(context: AccountContext, enabled: Bool) {
    let _ = updateChatArchiveSettings(engine: context.engine) { current in
        current.withUpdatedUseBiometrics(enabled)
    }.startStandalone()
}

public func removeArchivePassword(context: AccountContext, present: @escaping (ViewController) -> Void, completion: @escaping (Bool) -> Void) {
    let _ = (context.engine.data.get(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> deliverOnMainQueue).startStandalone(next: { preference in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        guard migrateAndResolvePasswordProtected(context: context, settings: settings) else {
            completion(true)
            return
        }
        presentArchivePasswordAlert(
            context: context,
            title: ArchiveLockLocalizedString.removeTitle,
            message: ArchiveLockLocalizedString.removeText,
            confirmTitle: ArchiveLockLocalizedString.remove,
            verifyPassword: true,
            onSuccess: {
                _ = ArchivePasswordKeychain.clear(peerId: context.account.peerId)
                let _ = updateChatArchiveSettings(engine: context.engine) { current in
                    current.clearingLegacyPasswordHash().withUpdatedIsPasswordConfigured(false)
                }.startStandalone()
                completion(true)
            },
            onCancel: {
                completion(false)
            }
        )
    })
}

/// Mute every peer currently in the archive that is not already muted forever.
/// Runs at most once per process lifetime.
public func muteAllArchivedChatsIfNeeded(context: AccountContext) {
    guard ArchiveLockSession.shared.claimMuteSweep(accountPeerId: context.account.peerId) else {
        return
    }
    alignKeepArchivedUnmutedIfNeeded(context: context)
    muteAllArchivedChats(context: context)
}

public func muteAllArchivedChats(context: AccountContext) {
    let _ = (context.account.postbox.transaction { transaction -> [EnginePeer.Id] in
        let peerIds = transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive)
        var toMute: [EnginePeer.Id] = []
        for peerId in peerIds {
            var notificationPeerId = peerId
            if let peer = transaction.getPeer(peerId), peer is TelegramSecretChat, let associatedPeerId = peer.associatedPeerId {
                notificationPeerId = associatedPeerId
            }
            let settings = transaction.getPeerNotificationSettings(id: notificationPeerId) as? TelegramPeerNotificationSettings
            switch settings?.muteState {
            case let .muted(until) where until == Int32.max:
                continue
            default:
                toMute.append(peerId)
            }
        }
        return toMute
    }
    |> mapToSignal { peerIds -> Signal<Never, NoError> in
        if peerIds.isEmpty {
            return .complete()
        }
        return context.engine.peers.updateMultiplePeerMuteSettings(peerIds: peerIds, muted: true)
    }).startStandalone()
}

private func overlayMediaPeerId(from stateOrLoading: SharedMediaPlayerItemPlaybackStateOrLoading) -> EnginePeer.Id? {
    switch stateOrLoading {
    case .loading:
        return nil
    case let .state(state):
        if let playlistId = state.playlistId as? PeerMessagesMediaPlaylistId {
            switch playlistId {
            case let .peer(peerId), let .recentActions(peerId), let .savedMusic(peerId):
                return peerId
            case .feed, .custom:
                break
            }
        }
        if let itemId = state.item.id as? PeerMessagesMediaPlaylistItemId {
            return itemId.messageId.peerId
        }
        if let location = state.playlistLocation as? PeerMessagesPlaylistLocation {
            switch location.playlistId {
            case let .peer(peerId), let .recentActions(peerId), let .savedMusic(peerId):
                return peerId
            case .feed, .custom:
                return nil
            }
        }
        return nil
    }
}

private func stopOverlayMediaForArchivedPeers(context: AccountContext, archivedPeerIds: Set<EnginePeer.Id>) {
    guard !archivedPeerIds.isEmpty else {
        return
    }
    let mediaManager = context.sharedContext.mediaManager
    let _ = (combineLatest(
        mediaManager.globalMediaPlayerState,
        mediaManager.musicMediaPlayerState
    )
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { globalState, musicState in
        if let (_, stateOrLoading, type) = globalState, let peerId = overlayMediaPeerId(from: stateOrLoading), archivedPeerIds.contains(peerId) {
            mediaManager.setPlaylist(nil, type: type, control: .playback(.pause))
        }
        if let (_, stateOrLoading, type) = musicState, let peerId = overlayMediaPeerId(from: stateOrLoading), archivedPeerIds.contains(peerId) {
            mediaManager.setPlaylist(nil, type: type, control: .playback(.pause))
        }
    })
}

private func archiveLockShouldDismiss(_ controller: UIViewController, archivedPeerIds: Set<EnginePeer.Id>) -> Bool {
    if let chatList = controller as? ChatListControllerImpl, case .chatList(groupId: .archive) = chatList.location {
        return true
    }
    if archivedPeerIds.isEmpty {
        return false
    }
    if let chat = controller as? ChatController, let peerId = chat.chatLocation.peerId, archivedPeerIds.contains(peerId) {
        return true
    }
    if let peerInfo = controller as? PeerInfoScreen, archivedPeerIds.contains(peerInfo.peerId) {
        return true
    }
    if let overlayPlayer = controller as? OverlayAudioPlayerController, let peerId = overlayPlayer.chatLocation.peerId, archivedPeerIds.contains(peerId) {
        return true
    }
    if let gallery = controller as? GalleryController, let peerId = gallery.sourcePeerId, archivedPeerIds.contains(peerId) {
        return true
    }
    if let story = controller as? StoryContainerScreen, let peerId = story.focusedPeerId, archivedPeerIds.contains(peerId) {
        return true
    }
    return false
}

private func dismissPresentedArchiveControllers(from navigationController: UINavigationController, archivedPeerIds: Set<EnginePeer.Id>) {
    var toDismiss: [ViewController] = []
    let stackIdentities = Set(navigationController.viewControllers.map { ObjectIdentifier($0) })
    
    let enqueue: (UIViewController) -> Void = { controller in
        guard let controller = controller as? ViewController else {
            return
        }
        guard archiveLockShouldDismiss(controller, archivedPeerIds: archivedPeerIds) else {
            return
        }
        if stackIdentities.contains(ObjectIdentifier(controller)) {
            return
        }
        if !toDismiss.contains(where: { $0 === controller }) {
            toDismiss.append(controller)
        }
    }
    
    let collectFromHost: (ViewController) -> Void = { host in
        host.forEachController { contained in
            if let viewController = contained as? ViewController {
                enqueue(viewController)
            }
            return true
        }
    }
    
    for controller in navigationController.viewControllers {
        if let viewController = controller as? ViewController {
            collectFromHost(viewController)
        }
    }
    
    if let navigationController = navigationController as? NavigationController {
        navigationController.currentWindow?.forEachController { contained in
            if let viewController = contained as? ViewController {
                enqueue(viewController)
            }
        }
        for overlay in navigationController.overlayControllers {
            enqueue(overlay)
        }
        for overlay in navigationController.globalOverlayControllers {
            enqueue(overlay)
        }
    }
    
    for controller in toDismiss {
        controller.dismiss(animated: false)
    }
}

/// Pop Archive chat-list controllers and any open chats / peer-info / gallery / story / overlay
/// audio surfaces whose peer currently lives in Archive. Also stops overlay media playback for
/// those peers. Safe to call multiple times; never animates (avoids races with swipe/context completions).
public func dismissOpenArchiveControllers(from navigationController: UINavigationController?, context: AccountContext? = nil) {
    let apply: (Set<EnginePeer.Id>) -> Void = { archivedPeerIds in
        let work = {
            if let context {
                stopOverlayMediaForArchivedPeers(context: context, archivedPeerIds: archivedPeerIds)
            }
            guard let navigationController else {
                return
            }
            dismissPresentedArchiveControllers(from: navigationController, archivedPeerIds: archivedPeerIds)
            
            let controllers = navigationController.viewControllers
            let filtered = controllers.filter { controller in
                return !archiveLockShouldDismiss(controller, archivedPeerIds: archivedPeerIds)
            }
            guard filtered.count != controllers.count else {
                return
            }
            // Prefer a single pop when only the top controller is leaving — cheaper and less
            // crash-prone than replacing the whole stack mid-transition.
            if controllers.count == filtered.count + 1 {
                navigationController.popViewController(animated: false)
            } else {
                navigationController.setViewControllers(filtered, animated: false)
            }
        }
        if Queue.mainQueue().isCurrent() {
            work()
        } else {
            Queue.mainQueue().async(work)
        }
    }
    if ArchiveLockSession.shared.areLockedPeerIdsResolved {
        apply(ArchiveLockSession.shared.currentLockedPeerIds())
        return
    }
    apply(ArchiveLockSession.shared.currentLockedPeerIds())
    if let context {
        let _ = (context.account.postbox.transaction { transaction -> Set<EnginePeer.Id> in
            return Set(transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive))
        }
        |> deliverOnMainQueue).startStandalone(next: apply)
    }
}

/// After moving a chat out of Archive: hide the folder again, clear the
/// password session, and leave the Archive screen. Unarchived peers become
/// searchable again automatically (search filters on live group membership).
public func lockArchiveAfterUnarchive(navigationController: UINavigationController?, context: AccountContext? = nil) {
    // Without a password the Archive behaves like the stock one: unarchiving a chat from inside it
    // removes that row and nothing else — it must not hide the folder or close the screen.
    guard ArchiveLockSession.shared.isLockActive else {
        return
    }
    ArchiveLockSession.shared.relock()
    // Defer navigation mutation until after the unarchive swipe/context
    // completion finishes — tearing down Archive VC synchronously was crashing.
    Queue.mainQueue().after(0.3, {
        dismissOpenArchiveControllers(from: navigationController, context: context)
    })
}
