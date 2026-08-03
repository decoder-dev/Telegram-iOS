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

private func migrateAndResolvePasswordProtected(context: AccountContext, settings: ChatArchiveSettings) -> Bool {
    let peerId = context.account.peerId
    let protected = archiveIsPasswordProtected(peerId: peerId, settings: settings)
    if settings.legacyLockPasswordHash != nil {
        let _ = updateChatArchiveSettings(engine: context.engine) { current in
            current.clearingLegacyPasswordHash()
        }.startStandalone()
    }
    return protected
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
    var attemptsLeft = 5
    let peerId = context.account.peerId
    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
    
    func show(messageOverride: String?) {
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
                    onSuccess()
                } else {
                    attemptsLeft -= 1
                    if attemptsLeft <= 0 {
                        onCancel()
                    } else {
                        Queue.mainQueue().after(0.3) {
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
            completion(true)
        },
        onCancel: {
            completion(false)
        },
        capturePassword: { password in
            let hash = archivePasswordHash(password)
            _ = ArchivePasswordKeychain.storeHash(hash, peerId: context.account.peerId)
            let _ = updateChatArchiveSettings(engine: context.engine) { current in
                current.clearingLegacyPasswordHash()
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
                    current.clearingLegacyPasswordHash()
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
