import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext

public enum ArchiveUnlockResult {
    case unlocked
    case cancelled
    /// Archive is not password-protected.
    case notProtected
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
        guard settings.isPasswordProtected else {
            completion(.notProtected)
            return
        }
        if ArchiveLockSession.shared.isUnlocked {
            completion(.unlocked)
            return
        }
        
        presentArchivePasswordAlert(
            context: context,
            title: "Archive Password",
            message: "Enter the password to open Archive",
            confirmTitle: "Unlock",
            expectedSettings: settings,
            onSuccess: {
                ArchiveLockSession.shared.unlock()
                completion(.unlocked)
            },
            onCancel: {
                completion(.cancelled)
            }
        )
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
        guard group == .archive, settings.isPasswordProtected else {
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
    expectedSettings: ChatArchiveSettings?,
    onSuccess: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    capturePassword: ((String) -> Void)? = nil
) {
    var attemptsLeft = 5
    
    func show(messageOverride: String?) {
        let alert = UIAlertController(title: title, message: messageOverride ?? message, preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "Password"
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            onCancel()
        }))
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default, handler: { _ in
            let trimmed = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let expectedSettings {
                if expectedSettings.matchesPassword(trimmed) {
                    onSuccess()
                } else {
                    attemptsLeft -= 1
                    if attemptsLeft <= 0 {
                        onCancel()
                    } else {
                        Queue.mainQueue().after(0.3) {
                            show(messageOverride: "Incorrect password. \(attemptsLeft) attempts left.")
                        }
                    }
                }
            } else if let capturePassword {
                if trimmed.isEmpty {
                    onCancel()
                } else {
                    Queue.mainQueue().after(0.2) {
                        let confirm = UIAlertController(title: "Confirm Password", message: "Re-enter the Archive password", preferredStyle: .alert)
                        confirm.addTextField { field in
                            field.isSecureTextEntry = true
                            field.placeholder = "Password"
                            field.autocorrectionType = .no
                            field.autocapitalizationType = .none
                        }
                        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                            onCancel()
                        }))
                        confirm.addAction(UIAlertAction(title: "Done", style: .default, handler: { _ in
                            let confirmValue = (confirm.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if confirmValue == trimmed {
                                capturePassword(trimmed)
                                onSuccess()
                            } else {
                                Queue.mainQueue().after(0.3) {
                                    show(messageOverride: "Passwords did not match. Try again.")
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
        title: "Set Archive Password",
        message: "Archived chats stay muted and hidden from folders",
        confirmTitle: "Continue",
        expectedSettings: nil,
        onSuccess: {
            ArchiveLockSession.shared.unlock()
            completion(true)
        },
        onCancel: {
            completion(false)
        },
        capturePassword: { password in
            let hash = archivePasswordHash(password)
            let _ = updateChatArchiveSettings(engine: context.engine) { current in
                current.withUpdatedLockPasswordHash(hash)
            }.startStandalone()
        }
    )
}

public func removeArchivePassword(context: AccountContext, present: @escaping (ViewController) -> Void, completion: @escaping (Bool) -> Void) {
    let _ = (context.engine.data.get(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> deliverOnMainQueue).startStandalone(next: { preference in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        guard settings.isPasswordProtected else {
            completion(true)
            return
        }
        presentArchivePasswordAlert(
            context: context,
            title: "Remove Archive Password",
            message: "Enter the current password to disable the lock",
            confirmTitle: "Remove",
            expectedSettings: settings,
            onSuccess: {
                let _ = updateChatArchiveSettings(engine: context.engine) { current in
                    current.withUpdatedLockPasswordHash(nil)
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
public func dismissOpenArchiveControllers(from navigationController: UINavigationController?) {
    guard let navigationController else {
        return
    }
    let filtered = navigationController.viewControllers.filter { controller in
        if let chatList = controller as? ChatListControllerImpl {
            if case .chatList(groupId: .archive) = chatList.location {
                return false
            }
        }
        return true
    }
    if filtered.count != navigationController.viewControllers.count {
        navigationController.setViewControllers(filtered, animated: true)
    }
}
