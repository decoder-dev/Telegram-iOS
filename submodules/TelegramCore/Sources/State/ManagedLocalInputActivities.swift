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
    private static let value = Atomic<Bool>(value: true)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// AyuGram Desktop "No Copy & Download Restrictions": allow saving stories / protected media
/// without Telegram Premium and despite `noforwards` / isForwardingDisabled.
public enum ForkBypassDownloadRestrictionsSettings {
    private static let value = Atomic<Bool>(value: true)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// AyuGram Local Telegram Premium: unlock client-side Premium-gated UX (stealth mode, HD stories,
/// sticker/emoji picker cosmetics, etc.) without touching the account's real, server-issued
/// Premium status. Never use this to alter anything the server itself enforces or verifies.
public enum ForkLocalPremiumSettings {
    private static let value = Atomic<Bool>(value: false)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// Client-only Premium check for UI gates: true when the account actually has Premium, or the
/// user opted into AyuGram's Local Telegram Premium. Use only at UI decision points that merely
/// show/hide a lock — never for anything the server verifies (sends, quotas, badges to others).
public func forkEffectiveIsPremium(accountIsPremium: Bool) -> Bool {
    return accountIsPremium || ForkLocalPremiumSettings.enabled
}

/// AyuGram: allow screenshots in secret chats / secret media and suppress peer notify.
public enum ForkSecretScreenshotSettings {
    private static let value = Atomic<Bool>(value: true)
    public static var allow: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// AyuGram: expire-now button on TTL / secret media viewer.
public enum ForkExpireTtlSettings {
    private static let value = Atomic<Bool>(value: true)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// AyuGram: keep banned/kicked chats in the chat list instead of dropping them.
public enum ForkKeepBannedChatsSettings {
    private static let value = Atomic<Bool>(value: true)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// AyuGram Ghost Schedule Messages — delay-send when full Ghost Mode is active.
public enum ForkGhostScheduleSettings {
    private static let value = Atomic<Bool>(value: false)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}

/// Bool flags read on scroll / bubble-layout paths. Atomic so Postbox/UI queues never race.
public enum ForkExtrasHotFlags {
    public struct State: Equatable {
        public var hideAds: Bool = false
        public var hideBlockedMessages: Bool = false
        public var hideReactionsBar: Bool = false
        public var compactChatList: Bool = false
        public var compactMessagePreview: Bool = false

        public init(
            hideAds: Bool = false,
            hideBlockedMessages: Bool = false,
            hideReactionsBar: Bool = false,
            compactChatList: Bool = false,
            compactMessagePreview: Bool = false
        ) {
            self.hideAds = hideAds
            self.hideBlockedMessages = hideBlockedMessages
            self.hideReactionsBar = hideReactionsBar
            self.compactChatList = compactChatList
            self.compactMessagePreview = compactMessagePreview
        }
    }

    private static let state = Atomic<State>(value: State())

    public static var current: State {
        return state.with { $0 }
    }

    public static func update(_ next: State) {
        let _ = state.swap(next)
    }

    public static var hideAds: Bool {
        get { return state.with { $0.hideAds } }
        set { let _ = state.modify { var s = $0; s.hideAds = newValue; return s } }
    }
    public static var hideBlockedMessages: Bool {
        get { return state.with { $0.hideBlockedMessages } }
        set { let _ = state.modify { var s = $0; s.hideBlockedMessages = newValue; return s } }
    }
    public static var hideReactionsBar: Bool {
        get { return state.with { $0.hideReactionsBar } }
        set { let _ = state.modify { var s = $0; s.hideReactionsBar = newValue; return s } }
    }
    public static var compactChatList: Bool {
        get { return state.with { $0.compactChatList } }
        set { let _ = state.modify { var s = $0; s.compactChatList = newValue; return s } }
    }
    public static var compactMessagePreview: Bool {
        get { return state.with { $0.compactMessagePreview } }
        set { let _ = state.modify { var s = $0; s.compactMessagePreview = newValue; return s } }
    }
}

/// Account-scoped blocked peers used by AyuGram message filters.
/// A revision lets UI caches invalidate without copying the full set on every row layout.
public enum ForkBlockedPeersFilter {
    private struct Snapshot {
        var peerIds: Set<PeerId>
        var revision: UInt64
    }

    private static let snapshots = Atomic<[PeerId: Snapshot]>(value: [:])
    private static let updatesRevision = Atomic<UInt64>(value: 0)
    private static let updatesPromise = ValuePromise<UInt64>(0, ignoreRepeated: true)

    public static func update(accountPeerId: PeerId, peerIds: Set<PeerId>) {
        var didChange = false
        let _ = snapshots.modify { current in
            var next = current
            if let previous = current[accountPeerId], previous.peerIds == peerIds {
                return current
            }
            didChange = true
            let revision = (current[accountPeerId]?.revision ?? 0) &+ 1
            next[accountPeerId] = Snapshot(peerIds: peerIds, revision: revision)
            return next
        }
        if didChange {
            var revision: UInt64 = 0
            let _ = updatesRevision.modify { current in
                revision = current &+ 1
                return revision
            }
            updatesPromise.set(revision)
        }
    }

    public static var updates: Signal<UInt64, NoError> {
        return updatesPromise.get()
    }

    public static func snapshot(accountPeerId: PeerId) -> (peerIds: Set<PeerId>, revision: UInt64) {
        return snapshots.with { snapshots in
            guard let snapshot = snapshots[accountPeerId] else {
                return ([], 0)
            }
            return (snapshot.peerIds, snapshot.revision)
        }
    }

    public static func contains(accountPeerId: PeerId, peerId: PeerId) -> Bool {
        return snapshots.with { $0[accountPeerId]?.peerIds.contains(peerId) ?? false }
    }

    public static func containsSnapshot(accountPeerId: PeerId, peerId: PeerId) -> (contains: Bool, revision: UInt64) {
        return snapshots.with { snapshots in
            guard let snapshot = snapshots[accountPeerId] else {
                return (false, 0)
            }
            return (snapshot.peerIds.contains(peerId), snapshot.revision)
        }
    }
}

/// Pushed down from SharedAccountContext.swift's ForkExtrasSettings subscription — this module
/// has no visibility into ForkExtrasSettings, same pattern as ManagedAudioSessionImpl.forceBuiltInMic.
/// Mirrors AyuGram's granular Ghost Mode toggles.
public enum ForkGhostModeSettings {
    public struct State: Equatable {
        public var suppressOutgoingActivity: Bool = false
        public var suppressOnline: Bool = false
        public var suppressMessageReads: Bool = false
        public var suppressStoryViews: Bool = false
        public var goOfflineAutomatically: Bool = false
        public var readOnInteract: Bool = false
        public var interactOverrideActive: Bool = false
        public var interactOverrideGeneration: Int = 0

        public init(
            suppressOutgoingActivity: Bool = false,
            suppressOnline: Bool = false,
            suppressMessageReads: Bool = false,
            suppressStoryViews: Bool = false,
            goOfflineAutomatically: Bool = false,
            readOnInteract: Bool = false,
            interactOverrideActive: Bool = false,
            interactOverrideGeneration: Int = 0
        ) {
            self.suppressOutgoingActivity = suppressOutgoingActivity
            self.suppressOnline = suppressOnline
            self.suppressMessageReads = suppressMessageReads
            self.suppressStoryViews = suppressStoryViews
            self.goOfflineAutomatically = goOfflineAutomatically
            self.readOnInteract = readOnInteract
            self.interactOverrideActive = interactOverrideActive
            self.interactOverrideGeneration = interactOverrideGeneration
        }
    }

    private static let state = Atomic<State>(value: State())

    public static var current: State {
        return state.with { $0 }
    }

    public static func update(_ f: (State) -> State) {
        let _ = state.modify(f)
    }

    /// Replace preference-backed fields in one atomic write (keeps interact-override intact).
    public static func applyPreferences(
        suppressOutgoingActivity: Bool,
        suppressOnline: Bool,
        suppressMessageReads: Bool,
        suppressStoryViews: Bool,
        goOfflineAutomatically: Bool,
        readOnInteract: Bool
    ) {
        update { current in
            var next = current
            next.suppressOutgoingActivity = suppressOutgoingActivity
            next.suppressOnline = suppressOnline
            next.suppressMessageReads = suppressMessageReads
            next.suppressStoryViews = suppressStoryViews
            next.goOfflineAutomatically = goOfflineAutomatically
            next.readOnInteract = readOnInteract
            return next
        }
    }

    /// Don't Send Typing — suppress typing / upload / sticker activity.
    public static var suppressOutgoingActivity: Bool {
        get { return state.with { $0.suppressOutgoingActivity } }
        set { update { var s = $0; s.suppressOutgoingActivity = newValue; return s } }
    }
    /// Don't Send Online — never report online (unless briefly overridden by read-on-interact).
    public static var suppressOnline: Bool {
        get { return state.with { $0.suppressOnline } }
        set { update { var s = $0; s.suppressOnline = newValue; return s } }
    }
    /// Don't Read Messages — suppress read receipts / seen reactions while browsing.
    public static var suppressMessageReads: Bool {
        get { return state.with { $0.suppressMessageReads } }
        set { update { var s = $0; s.suppressMessageReads = newValue; return s } }
    }
    /// Don't Read Stories — suppress story view increments.
    public static var suppressStoryViews: Bool {
        get { return state.with { $0.suppressStoryViews } }
        set { update { var s = $0; s.suppressStoryViews = newValue; return s } }
    }
    /// Go Offline Automatically — after reporting online, immediately flip back to offline.
    public static var goOfflineAutomatically: Bool {
        get { return state.with { $0.goOfflineAutomatically } }
        set { update { var s = $0; s.goOfflineAutomatically = newValue; return s } }
    }
    /// Read on Interact — when set with dont-read, interactions briefly allow reads + online blink.
    public static var readOnInteract: Bool {
        get { return state.with { $0.readOnInteract } }
        set { update { var s = $0; s.readOnInteract = newValue; return s } }
    }
    /// Temporary override window opened by `beginReadOnInteractOverride()`.
    public static var interactOverrideActive: Bool {
        get { return state.with { $0.interactOverrideActive } }
        set { update { var s = $0; s.interactOverrideActive = newValue; return s } }
    }

    /// Call when the user sends/reacts and Read on Interact is enabled.
    public static func beginReadOnInteractOverride(duration: TimeInterval = 1.5) {
        var generation: Int?
        update { current in
            guard current.readOnInteract else {
                return current
            }
            var next = current
            next.interactOverrideActive = true
            next.interactOverrideGeneration += 1
            generation = next.interactOverrideGeneration
            return next
        }
        guard let generation else {
            return
        }
        Queue.mainQueue().after(duration) {
            update { current in
                guard current.interactOverrideGeneration == generation else {
                    return current
                }
                var next = current
                next.interactOverrideActive = false
                return next
            }
        }
    }

    /// True when dont-read is on and the read-on-interact override window is closed.
    public static var shouldSuppressMessageReads: Bool {
        let current = state.with { $0 }
        if current.interactOverrideActive {
            return false
        }
        return current.suppressMessageReads
    }

    public static var shouldSuppressOnline: Bool {
        let current = state.with { $0 }
        if current.interactOverrideActive {
            return false
        }
        return current.suppressOnline
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
