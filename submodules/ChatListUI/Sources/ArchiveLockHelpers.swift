import Foundation
import UIKit
import UserNotifications
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import LocalAuth

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
            guard let peerIdString = notification.request.content.userInfo["peerId"] as? String, let peerIdValue = Int64(peerIdString), peerIds.contains(peerIdValue) else {
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

/// Sweep currently-delivered notifications for every peer presently in the Archive. Call this
/// right after Archive password-protection turns on, since chats already archived at that point
/// need their pre-existing notifications cleared too, not just future ones.
public func clearStaleArchiveNotifications(context: AccountContext) {
    let _ = (context.account.postbox.transaction { transaction -> Set<Int64> in
        return Set(transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive).map { $0.toInt64() })
    }
    |> deliverOnMainQueue).startStandalone(next: { peerIds in
        clearDeliveredNotifications(forPeerIds: peerIds)
    })
}

/// Align server-side keepArchivedUnmuted with local force-mute: unmuted
/// archived chats (if any) should stay in Archive rather than auto-unarchiving.
func alignKeepArchivedUnmutedIfNeeded(context: AccountContext) {
    guard ArchiveLockSession.shared.claimKeepArchivedAlign() else {
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
    ArchiveLockSession.shared.bindBackgroundRelock(applicationIsActive: context.sharedContext.applicationBindings.applicationIsActive)
    
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
    ArchiveLockSession.shared.bindBackgroundRelock(applicationIsActive: context.sharedContext.applicationBindings.applicationIsActive)
    
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
                presentUIAlert(context: context, alert: cooldownAlert)
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
                        presentUIAlert(context: context, alert: confirm)
                    }
                }
            } else {
                onCancel()
            }
        }))
        presentUIAlert(context: context, alert: alert)
    }
    
    show(messageOverride: nil)
}

private func presentUIAlert(context: AccountContext, alert: UIAlertController) {
    if let host = context.sharedContext.applicationBindings.getTopWindow()?.rootViewController {
        var presenter = host
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
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
                ArchiveLockSession.shared.relock()
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
    guard ArchiveLockSession.shared.claimMuteSweep() else {
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

/// Pop any Archive chat-list controllers currently on the navigation stack.
/// Safe to call multiple times; never animates (avoids races with swipe/context completions).
public func dismissOpenArchiveControllers(from navigationController: UINavigationController?) {
    guard let navigationController else {
        return
    }
    // Must run on main; callers may bounce from signal completions.
    let work = {
        let controllers = navigationController.viewControllers
        let filtered = controllers.filter { controller in
            if let chatList = controller as? ChatListControllerImpl {
                if case .chatList(groupId: .archive) = chatList.location {
                    return false
                }
            }
            return true
        }
        guard filtered.count != controllers.count else {
            return
        }
        // Prefer a single pop when Archive is on top — cheaper and less crash-prone
        // than replacing the whole stack mid-transition.
        if controllers.count == filtered.count + 1,
           let top = controllers.last as? ChatListControllerImpl,
           case .chatList(groupId: .archive) = top.location {
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

/// After moving a chat out of Archive: hide the folder again, clear the
/// password session, and leave the Archive screen. Unarchived peers become
/// searchable again automatically (search filters on live group membership).
public func lockArchiveAfterUnarchive(navigationController: UINavigationController?) {
    ArchiveLockSession.shared.relock()
    // Defer navigation mutation until after the unarchive swipe/context
    // completion finishes — tearing down Archive VC synchronously was crashing.
    Queue.mainQueue().after(0.3, {
        dismissOpenArchiveControllers(from: navigationController)
    })
}
