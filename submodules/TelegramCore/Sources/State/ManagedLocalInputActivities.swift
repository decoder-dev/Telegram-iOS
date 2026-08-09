import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit


public struct PeerActivitySpace: Hashable {
    public enum Category: Equatable, Hashable {
        case global
        case thread(Int64)
        case voiceChat
    }
    
    public var peerId: PeerId
    public var category: Category
    
    public init(peerId: PeerId, category: Category) {
        self.peerId = peerId
        self.category = category
    }
}

struct PeerInputActivityRecord: Equatable {
    let activity: PeerInputActivity
    let updateId: Int32
}

/// AyuGram AyuForward — pushed down from SharedAccountContext (TelegramCore has no ForkExtrasSettings).
/// When enabled, copy-protected / locally-deleted messages are re-uploaded as new content (no author)
/// instead of `messages.forwardMessages` (which the server rejects for noforwards).
public enum ForkAyuForwardSettings {
    public static var enabled: Bool = true
}

/// AyuGram: allow screenshots in secret chats / secret media and suppress peer notify.
public enum ForkSecretScreenshotSettings {
    public static var allow: Bool = true
}

/// AyuGram: expire-now button on TTL / secret media viewer.
public enum ForkExpireTtlSettings {
    public static var enabled: Bool = true
}

/// AyuGram: keep banned/kicked chats in the chat list instead of dropping them.
public enum ForkKeepBannedChatsSettings {
    public static var enabled: Bool = true
}

/// AyuGram Ghost Schedule Messages — delay-send when full Ghost Mode is active.
public enum ForkGhostScheduleSettings {
    public static var enabled: Bool = false
}

/// Bool flags read on scroll / bubble-layout paths. Plain statics so callers never copy
/// a preferences struct (which may embed regex pattern strings) per frame.
public enum ForkExtrasHotFlags {
    public static var hideAds: Bool = false
    public static var hideBlockedMessages: Bool = false
    public static var hideReactionsBar: Bool = false
}

/// Pushed down from SharedAccountContext.swift's ForkExtrasSettings subscription — this module
/// has no visibility into ForkExtrasSettings, same pattern as ManagedAudioSessionImpl.forceBuiltInMic.
/// Mirrors AyuGram's granular Ghost Mode toggles.
public enum ForkGhostModeSettings {
    /// Don't Send Typing — suppress typing / upload / sticker activity.
    public static var suppressOutgoingActivity: Bool = false
    /// Don't Send Online — never report online (unless briefly overridden by read-on-interact).
    public static var suppressOnline: Bool = false
    /// Don't Read Messages — suppress read receipts / seen reactions while browsing.
    public static var suppressMessageReads: Bool = false
    /// Don't Read Stories — suppress story view increments.
    public static var suppressStoryViews: Bool = false
    /// Go Offline Automatically — after reporting online, immediately flip back to offline.
    public static var goOfflineAutomatically: Bool = false
    /// Read on Interact — when set with dont-read, interactions briefly allow reads + online blink.
    public static var readOnInteract: Bool = false
    /// Temporary override window opened by `beginReadOnInteractOverride()`.
    public static var interactOverrideActive: Bool = false

    /// Call when the user sends/reacts and Read on Interact is enabled.
    public static func beginReadOnInteractOverride(duration: TimeInterval = 1.5) {
        guard readOnInteract else {
            return
        }
        interactOverrideActive = true
        interactOverrideGeneration += 1
        let generation = interactOverrideGeneration
        Queue.mainQueue().after(duration) {
            if interactOverrideGeneration == generation {
                interactOverrideActive = false
            }
        }
    }

    private static var interactOverrideGeneration: Int = 0

    /// True when dont-read is on and the read-on-interact override window is closed.
    public static var shouldSuppressMessageReads: Bool {
        if interactOverrideActive {
            return false
        }
        return suppressMessageReads
    }

    public static var shouldSuppressOnline: Bool {
        if interactOverrideActive {
            return false
        }
        return suppressOnline
    }
}

private final class ManagedLocalTypingActivitiesContext {
    private var disposables: [PeerActivitySpace: (PeerInputActivityRecord, MetaDisposable)] = [:]
    
    func update(activities: [PeerActivitySpace: [(PeerId, PeerInputActivityRecord)]]) -> (start: [(PeerActivitySpace, PeerInputActivityRecord?, MetaDisposable)], dispose: [MetaDisposable]) {
        var start: [(PeerActivitySpace, PeerInputActivityRecord?, MetaDisposable)] = []
        var dispose: [MetaDisposable] = []
        
        var validPeerIds = Set<PeerActivitySpace>()
        for (peerId, record) in activities {
            if let activity = record.first?.1 {
                validPeerIds.insert(peerId)
                
                let currentRecord = self.disposables[peerId]
                if currentRecord == nil || currentRecord!.0 != activity {
                    if let disposable = currentRecord?.1 {
                        dispose.append(disposable)
                    }
                    
                    let disposable = MetaDisposable()
                    start.append((peerId, activity, disposable))
                    
                    self.disposables[peerId] = (activity, disposable)
                }
            }
        }
        
        var removePeerIds: [PeerActivitySpace] = []
        for key in self.disposables.keys {
            if !validPeerIds.contains(key) {
                removePeerIds.append(key)
            }
        }
        
        for peerId in removePeerIds {
            dispose.append(self.disposables[peerId]!.1)
            self.disposables.removeValue(forKey: peerId)
        }
        
        return (start, dispose)
    }
    
    func dispose() {
        for (_, record) in self.disposables {
            record.1.dispose()
        }
        self.disposables.removeAll()
    }
}

func managedLocalTypingActivities(activities: Signal<[PeerActivitySpace: [(PeerId, PeerInputActivityRecord)]], NoError>, postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Void, NoError> {
    return Signal { subscriber in
        let context = Atomic(value: ManagedLocalTypingActivitiesContext())
        let disposable = activities.start(next: { activities in
            let (start, dispose) = context.with { context in
                return context.update(activities: activities)
            }
            
            for disposable in dispose {
                disposable.dispose()
            }
            
            for (peerId, activity, disposable) in start {
                var threadId: Int64?
                switch peerId.category {
                case let .thread(id):
                    threadId = id
                default:
                    break
                }
                disposable.set(requestActivity(postbox: postbox, network: network, accountPeerId: accountPeerId, peerId: peerId.peerId, threadId: threadId, activity: activity?.activity).start())
            }
        })
        return ActionDisposable {
            disposable.dispose()
            
            context.with { context -> Void in
                context.dispose()
            }
        }
    }
}

private func actionFromActivity(_ activity: PeerInputActivity?) -> Api.SendMessageAction {
    if let activity = activity {
        switch activity {
            case .typingText:
                return .sendMessageTypingAction
            case .recordingVoice:
                return .sendMessageRecordAudioAction
            case .playingGame:
                return .sendMessageGamePlayAction
            case let .uploadingFile(progress):
                return .sendMessageUploadDocumentAction(.init(progress: progress))
            case let .uploadingPhoto(progress):
                return .sendMessageUploadPhotoAction(.init(progress: progress))
            case let .uploadingVideo(progress):
                return .sendMessageUploadVideoAction(.init(progress: progress))
            case .recordingInstantVideo:
                return .sendMessageRecordRoundAction
            case let .uploadingInstantVideo(progress):
                return .sendMessageUploadRoundAction(.init(progress: progress))
            case .speakingInGroupCall:
                return .speakingInGroupCallAction
            case .choosingSticker:
                return .sendMessageChooseStickerAction
            case let .interactingWithEmoji(emoticon, messageId, interaction):
                return .sendMessageEmojiInteraction(.init(emoticon: emoticon, msgId: messageId.id, interaction: interaction?.apiDataJson ?? .dataJSON(.init(data: ""))))
            case let .seeingEmojiInteraction(emoticon):
                return .sendMessageEmojiInteractionSeen(.init(emoticon: emoticon))
        }
    } else {
        return .sendMessageCancelAction
    }
}

private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {
    if ForkGhostModeSettings.suppressOutgoingActivity {
        return .complete()
    }
    return postbox.transaction { transaction -> Signal<Void, NoError> in
        if let peer = transaction.getPeer(peerId) {
            if peerId == accountPeerId {
                return .complete()
            }
            if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
                if let activity = activity {
                    switch activity {
                    case .speakingInGroupCall:
                        break
                    default:
                        return .complete()
                    }
                }
            }
            if let _ = peer as? TelegramUser {
                if let presence = transaction.getPeerPresence(peerId: peerId) as? TelegramUserPresence {
                    switch presence.status {
                    case .none, .lastWeek, .lastMonth:
                        return .complete()
                    case .recently:
                        break
                    case let .present(statusTimestamp):
                        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
                        if statusTimestamp < timestamp - 30 {
                            return .complete()
                        }
                    }
                } else {
                    return .complete()
                }
            }
            
            if let inputPeer = apiInputPeer(peer) {
                var flags: Int32 = 0
                let topMessageId = threadId.flatMap { Int32(clamping: $0) }
                if topMessageId != nil {
                    flags |= 1 << 0
                }
                return network.request(Api.functions.messages.setTyping(flags: flags, peer: inputPeer, topMsgId: topMessageId, action: actionFromActivity(activity)))
                |> `catch` { _ -> Signal<Api.Bool, NoError> in
                    return .single(.boolFalse)
                }
                |> mapToSignal { _ -> Signal<Void, NoError> in
                    return .complete()
                }
            } else if let peer = peer as? TelegramSecretChat, activity == .typingText {
                let _ = PeerId(peer.id.toInt64())
                return network.request(Api.functions.messages.setEncryptedTyping(peer: .inputEncryptedChat(.init(chatId: Int32(peer.id.id._internalGetInt64Value()), accessHash: peer.accessHash)), typing: .boolTrue))
                |> `catch` { _ -> Signal<Api.Bool, NoError> in
                    return .single(.boolFalse)
                }
                |> mapToSignal { _ -> Signal<Void, NoError> in
                    return .complete()
                }
            } else {
                return .complete()
            }
        } else {
            return .complete()
        }
    } |> switchToLatest
}
