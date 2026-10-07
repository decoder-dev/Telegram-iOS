import Foundation
import Postbox
import SwiftSignalKit

/// Local shadow ban. Messages of the peers in `ArenaSettings.shadowBannedPeerIds` are hidden in groups, channels,
/// comments and the Replies chat, with their typing, reaction avatars and stories. Private chats are never filtered,
/// and nothing goes to the server: the person never learns about it.
public enum TelegramShadowBan {
    private static let stateQueue = Queue(name: "TelegramShadowBan.State")
    /// The ban list and the chats with В«РџРѕРєР°Р·Р°С‚СЊ СЃРєСЂС‹С‚С‹РµВ» on, read once for a whole computation.
    public struct State: Equatable {
        public var bannedPeerIds: Set<Int64>
        public var revealedChatIds: Set<Int64>

        public init(bannedPeerIds: Set<Int64>, revealedChatIds: Set<Int64>) {
            self.bannedPeerIds = bannedPeerIds
            self.revealedChatIds = revealedChatIds
        }

        public static var current: State {
            let snapshot = ArenaSettings.shared.shadowBanSnapshot
            return State(bannedPeerIds: Set(snapshot.bannedPeerIds), revealedChatIds: Set(snapshot.revealedChatIds))
        }
    }

    /// The current state, then every change of the list or of В«РџРѕРєР°Р·Р°С‚СЊ СЃРєСЂС‹С‚С‹РµВ».
    public static func stateSignal() -> Signal<State, NoError> {
        return Signal<State, NoError> { subscriber in
            // Subscribe before the initial read; serialize reads and delivery without
            // invoking subscribers while holding the settings lock.
            let observer = NotificationCenter.default.addObserver(forName: ArenaSettings.shadowBanDidChangeNotification, object: nil, queue: nil, using: { _ in
                stateQueue.async {
                    subscriber.putNext(State.current)
                }
            })
            stateQueue.async {
                subscriber.putNext(State.current)
            }
            return ActionDisposable {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        |> distinctUntilChanged
    }

    /// Groups, supergroups, forums, channels with their discussions, and the Replies chat. Private chats, bots, secret
    /// chats, Saved Messages and direct messages to a channel (monoforum) are never filtered.
    public static func appliesToChat(_ chatPeerId: PeerId, chatPeer: Peer?) -> Bool {
        if chatPeerId.namespace == Namespaces.Peer.CloudGroup {
            return true
        } else if chatPeerId.namespace == Namespaces.Peer.CloudChannel {
            if let chatPeer, chatPeer.isMonoForum {
                return false
            }
            return true
        } else if chatPeerId.namespace == Namespaces.Peer.CloudUser {
            return chatPeerId.isReplies
        } else {
            return false
        }
    }

    public static func appliesToChat(_ chatPeer: EnginePeer) -> Bool {
        return self.appliesToChat(chatPeer.id, chatPeer: chatPeer._asPeer())
    }

    /// Whether `message` comes from a banned author in a filtered chat, ignoring В«РџРѕРєР°Р·Р°С‚СЊ СЃРєСЂС‹С‚С‹РµВ»: the sender, the
    /// forwarded author or source, or the inline bot. The chat itself never counts, so a banned channel's own posts stay
    /// visible in that channel.
    public static func isBannedContent(_ message: Message, bannedPeerIds: Set<Int64>) -> Bool {
        if bannedPeerIds.isEmpty {
            return false
        }
        let chatPeerId = message.id.peerId
        if !message.flags.contains(.Incoming) || !self.appliesToChat(chatPeerId, chatPeer: message.peers[chatPeerId]) {
            return false
        }
        let isBanned: (PeerId?) -> Bool = { peerId in
            guard let peerId, peerId != chatPeerId else {
                return false
            }
            return bannedPeerIds.contains(peerId.toInt64())
        }
        if isBanned(message.author?.id) {
            return true
        }
        if let forwardInfo = message.forwardInfo, isBanned(forwardInfo.author?.id) || isBanned(forwardInfo.source?.id) {
            return true
        }
        for attribute in message.attributes {
            if let attribute = attribute as? InlineBotMessageAttribute, isBanned(attribute.peerId) {
                return true
            }
        }
        return false
    }

    public static func isBannedContent(_ message: Message) -> Bool {
        return self.isBannedContent(message, bannedPeerIds: Set(ArenaSettings.shared.shadowBannedPeerIds))
    }

    /// Whether `message` is hidden: banned content in a chat without В«РџРѕРєР°Р·Р°С‚СЊ СЃРєСЂС‹С‚С‹РµВ».
    public static func isHidden(_ message: Message, state: State) -> Bool {
        if state.bannedPeerIds.isEmpty || state.revealedChatIds.contains(message.id.peerId.toInt64()) {
            return false
        }
        return self.isBannedContent(message, bannedPeerIds: state.bannedPeerIds)
    }

    public static func isHidden(_ message: Message) -> Bool {
        if !ArenaSettings.shared.hasShadowBans {
            return false
        }
        return self.isHidden(message, state: State.current)
    }

    public static func isHidden(_ message: EngineMessage) -> Bool {
        return self.isHidden(message._asMessage())
    }

    /// Whether to hide `peerId`'s typing and avatars in a chat. Decided by the chat's id alone, so a monoforum counts as a
    /// channel here.
    public static func isPeerHidden(_ peerId: PeerId, inChat chatPeerId: PeerId, state: State = State.current) -> Bool {
        if state.bannedPeerIds.isEmpty || peerId == chatPeerId || state.revealedChatIds.contains(chatPeerId.toInt64()) {
            return false
        }
        if !self.appliesToChat(chatPeerId, chatPeer: nil) {
            return false
        }
        return state.bannedPeerIds.contains(peerId.toInt64())
    }

    /// Whether the reply header of `message` must turn into a placeholder: it quotes a hidden message or, for a reply to
    /// another chat where only the author is known, a banned author. The reply itself stays visible.
    public static func hidesReplyHeader(in message: Message) -> Bool {
        if !ArenaSettings.shared.hasShadowBans {
            return false
        }
        return self.hidesReplyHeader(in: message, state: State.current)
    }

    public static func hidesReplyHeader(in message: Message, state: State) -> Bool {
        for attribute in message.attributes {
            if let attribute = attribute as? ReplyMessageAttribute {
                if let replyMessage = message.associatedMessages[attribute.messageId] {
                    return self.isHidden(replyMessage, state: state)
                }
            } else if let attribute = attribute as? QuotedReplyMessageAttribute, let authorId = attribute.peerId {
                return self.isPeerHidden(authorId, inChat: message.id.peerId, state: state)
            }
        }
        return false
    }

    /// Who a message's ban applies to: the sender, or the reply's author in the Replies chat.
    public static func banTarget(of message: Message) -> Peer? {
        if message.id.peerId.isReplies {
            return message.forwardInfo?.author
        }
        return message.author
    }

    /// People, bots and channels can be banned; groups and the account itself can't.
    public static func canBan(_ peer: EnginePeer, accountPeerId: PeerId) -> Bool {
        if peer.id == accountPeerId {
            return false
        }
        switch peer {
        case .user:
            return true
        case let .channel(channel):
            if case .broadcast = channel.info {
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Search results without hidden messages; the total shrinks by the dropped ones.
    public static func filteringHidden(_ result: SearchMessagesResult) -> SearchMessagesResult {
        if !ArenaSettings.shared.hasShadowBans {
            return result
        }
        let state = State.current
        let messages = result.messages.filter { !self.isHidden($0, state: state) }
        if messages.count == result.messages.count {
            return result
        }
        let dropped = Int32(result.messages.count - messages.count)
        return SearchMessagesResult(messages: messages, readStates: result.readStates, threadInfo: result.threadInfo, totalCount: max(0, result.totalCount - dropped), completed: result.completed)
    }

    /// Story subscriptions without banned peers; the account's own stories stay.
    public static func filteringHidden(_ subscriptions: EngineStorySubscriptions, state: State) -> EngineStorySubscriptions {
        if state.bannedPeerIds.isEmpty {
            return subscriptions
        }
        let items = subscriptions.items.filter { !state.bannedPeerIds.contains($0.peer.id.toInt64()) }
        if items.count == subscriptions.items.count {
            return subscriptions
        }
        return EngineStorySubscriptions(accountItem: subscriptions.accountItem, items: items, hasMoreToken: subscriptions.hasMoreToken)
    }

    /// The read index moved over hidden messages: the last index in `windowIndices` above `index` and below the first
    /// visible index above `index`, or up to the window's end when nothing visible follows. Both arrays are ascending.
    public static func readIndexPastHidden(_ index: MessageIndex, visibleIndices: [MessageIndex], windowIndices: [MessageIndex]) -> MessageIndex {
        let nextVisibleIndex = visibleIndices.first(where: { $0 > index })
        var result = index
        for windowIndex in windowIndices {
            if windowIndex <= result {
                continue
            }
            if let nextVisibleIndex, windowIndex >= nextVisibleIndex {
                break
            }
            result = windowIndex
        }
        return result
    }

    /// The most messages a history window asks for on each side when hidden messages make it grow.
    public static let maxHistoryWindowCount = 2000

    /// The message count of a history window around hidden messages: the stock count plus twice the hidden ones, so the
    /// window reaches past a run of hidden messages to visible ones (at the bottom of a chat too, where the list re-anchors
    /// on the newest messages). Without hidden messages it's the stock count.
    public static func historyWindowCount(_ baseCount: Int, hiddenCount: Int) -> Int {
        if hiddenCount <= 0 {
            return baseCount
        }
        let grown = baseCount + 2 * min(hiddenCount, self.maxHistoryWindowCount)
        return min(grown, max(baseCount, self.maxHistoryWindowCount))
    }

    public enum HiddenWindowDirection: Equatable {
        case earlier
        case later
    }

    /// Walks the history past windows where every message is hidden, so a chat doesn't show В«no messagesВ» while it has
    /// visible ones elsewhere. It keeps one direction (newer when there is something newer, otherwise older) and turns
    /// around once at that end; nil means nothing is left to load, so the chat has no visible messages.
    public struct HiddenWindowWalk: Equatable {
        /// Steps without reaching a visible message before giving up, so a run of hidden messages longer than the windows
        /// can bridge never makes the list reload forever.
        public static let maxSteps = 30

        public private(set) var direction: HiddenWindowDirection?
        private var hasTurned = false
        private var steps = 0

        public init() {
        }

        public mutating func next(canLoadEarlier: Bool, canLoadLater: Bool) -> HiddenWindowDirection? {
            if self.steps >= HiddenWindowWalk.maxSteps {
                return nil
            }
            self.steps += 1
            let canLoad: (HiddenWindowDirection) -> Bool = { direction in
                switch direction {
                case .earlier:
                    return canLoadEarlier
                case .later:
                    return canLoadLater
                }
            }
            let direction = self.direction ?? (canLoadLater ? .later : .earlier)
            if canLoad(direction) {
                self.direction = direction
                return direction
            }
            if self.hasTurned {
                return nil
            }
            self.hasTurned = true
            let turned: HiddenWindowDirection = direction == .earlier ? .later : .earlier
            self.direction = turned
            return canLoad(turned) ? turned : nil
        }
    }
}
