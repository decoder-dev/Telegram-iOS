import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import AccountContext
import PromptUI

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
    let _ = (context.engine.data.get(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> deliverOnMainQueue).startStandalone(next: { preference in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        guard settings.isPasswordProtected, let expectedPassword = settings.lockPassword else {
            completion(.notProtected)
            return
        }
        if ArchiveLockSession.shared.isUnlocked {
            completion(.unlocked)
            return
        }
        
        presentArchivePasswordPrompt(
            context: context,
            present: present,
            title: "Archive Password",
            subtitle: "Enter the password to open Archive",
            expectedPassword: expectedPassword,
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

public func presentArchivePasswordPrompt(
    context: AccountContext,
    present: @escaping (ViewController) -> Void,
    title: String,
    subtitle: String?,
    expectedPassword: String?,
    onSuccess: @escaping () -> Void,
    onCancel: @escaping () -> Void
) {
    var attemptsLeft = 5
    
    func showPrompt(message: String?) {
        let prompt = promptController(
            context: context,
            text: title,
            titleFont: .bold,
            subtitle: message ?? subtitle,
            value: "",
            placeholder: "Password",
            characterLimit: 64,
            displayCharacterLimit: false,
            apply: { value in
                guard let value else {
                    onCancel()
                    return
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let expectedPassword {
                    if trimmed == expectedPassword {
                        onSuccess()
                    } else {
                        attemptsLeft -= 1
                        if attemptsLeft <= 0 {
                            onCancel()
                        } else {
                            Queue.mainQueue().after(0.35) {
                                showPrompt(message: "Incorrect password. \(attemptsLeft) attempts left.")
                            }
                        }
                    }
                } else {
                    if trimmed.isEmpty {
                        onCancel()
                    } else {
                        Queue.mainQueue().after(0.2) {
                            let confirm = promptController(
                                context: context,
                                text: "Confirm Password",
                                titleFont: .bold,
                                subtitle: "Re-enter the Archive password",
                                value: "",
                                placeholder: "Password",
                                characterLimit: 64,
                                apply: { confirmValue in
                                    guard let confirmValue else {
                                        onCancel()
                                        return
                                    }
                                    if confirmValue.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
                                        let _ = updateChatArchiveSettings(engine: context.engine) { current in
                                            current.withUpdatedLockPassword(trimmed)
                                        }.startStandalone()
                                        ArchiveLockSession.shared.unlock()
                                        onSuccess()
                                    } else {
                                        Queue.mainQueue().after(0.35) {
                                            showPrompt(message: "Passwords did not match. Try again.")
                                        }
                                    }
                                },
                                dismissed: {
                                    onCancel()
                                }
                            )
                            present(confirm)
                        }
                    }
                }
            },
            dismissed: {
                onCancel()
            }
        )
        present(prompt)
    }
    
    showPrompt(message: nil)
}

public func setArchivePassword(context: AccountContext, present: @escaping (ViewController) -> Void, completion: @escaping (Bool) -> Void) {
    presentArchivePasswordPrompt(
        context: context,
        present: present,
        title: "Set Archive Password",
        subtitle: "Chats in Archive stay muted and hidden from folders",
        expectedPassword: nil,
        onSuccess: { completion(true) },
        onCancel: { completion(false) }
    )
}

public func removeArchivePassword(context: AccountContext, present: @escaping (ViewController) -> Void, completion: @escaping (Bool) -> Void) {
    let _ = (context.engine.data.get(
        TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)
    )
    |> deliverOnMainQueue).startStandalone(next: { preference in
        let settings = preference?.get(ChatArchiveSettings.self) ?? .default
        guard let expectedPassword = settings.lockPassword, settings.isPasswordProtected else {
            completion(true)
            return
        }
        presentArchivePasswordPrompt(
            context: context,
            present: present,
            title: "Remove Archive Password",
            subtitle: "Enter the current password to disable the lock",
            expectedPassword: expectedPassword,
            onSuccess: {
                let _ = updateChatArchiveSettings(engine: context.engine) { current in
                    current.withUpdatedLockPassword(nil)
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
/// Covers chats archived before auto-mute was introduced.
public func muteAllArchivedChats(context: AccountContext) {
    let _ = (context.account.postbox.transaction { transaction -> [EnginePeer.Id] in
        let peerIds = transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive)
        var toMute: [EnginePeer.Id] = []
        for peerId in peerIds {
            let settings = transaction.getPeerNotificationSettings(id: peerId) as? TelegramPeerNotificationSettings
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
