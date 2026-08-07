import Foundation
import Postbox
import SwiftSignalKit

/// Kind of locally saved message snapshot (AyuGram-style anti-recall / edit history).
public enum MessageSavingKind: String, Codable {
    case deleted
    case edited
}

/// Text-only snapshot persisted outside Postbox (matches AyuGram Desktop's current scope).
public struct MessageSavingRecord: Codable, Equatable {
    public let id: String
    public let accountPeerId: Int64
    public let peerId: Int64
    public let messageId: Int32
    public let namespace: Int32
    public let date: Int32
    public let authorId: Int64?
    public let authorName: String
    public let text: String
    public let kind: MessageSavingKind
    public let savedAt: Int32
    public let topicId: Int64

    public init(
        id: String,
        accountPeerId: Int64,
        peerId: Int64,
        messageId: Int32,
        namespace: Int32,
        date: Int32,
        authorId: Int64?,
        authorName: String,
        text: String,
        kind: MessageSavingKind,
        savedAt: Int32,
        topicId: Int64
    ) {
        self.id = id
        self.accountPeerId = accountPeerId
        self.peerId = peerId
        self.messageId = messageId
        self.namespace = namespace
        self.date = date
        self.authorId = authorId
        self.authorName = authorName
        self.text = text
        self.kind = kind
        self.savedAt = savedAt
        self.topicId = topicId
    }
}

public struct MessageSavingBridgeSettings: Equatable {
    public var saveDeleted: Bool
    public var saveEdits: Bool
    public var saveForBots: Bool

    public init(saveDeleted: Bool, saveEdits: Bool, saveForBots: Bool) {
        self.saveDeleted = saveDeleted
        self.saveEdits = saveEdits
        self.saveForBots = saveForBots
    }

    /// Matches ForkExtrasSettings.defaultSettings so deletes are captured before
    /// SharedAccountContext's async sharedData subscription applies persisted prefs.
    public static let defaults = MessageSavingBridgeSettings(saveDeleted: true, saveEdits: true, saveForBots: false)

    public static let disabled = MessageSavingBridgeSettings(saveDeleted: false, saveEdits: false, saveForBots: false)
}

/// TelegramCore cannot import TelegramUIPreferences; SharedAccountContext pushes settings + append sink here.
public enum MessageSavingBridge {
    public static let settings = Atomic(value: MessageSavingBridgeSettings.defaults)
    public static let append = Atomic<((MessageSavingRecord) -> Void)?>(value: nil)

    /// Prefer a textual body; fall back to a short media placeholder so media-only
    /// deletes still appear in View Deleted (AyuGram is text-only, but empty skips
    /// looked like "saving is broken" for photo/sticker/voice messages).
    private static func displayText(for message: Message) -> String? {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        for media in message.media {
            if media is TelegramMediaImage {
                return "[Photo]"
            }
            if let file = media as? TelegramMediaFile {
                if file.isAnimatedSticker || file.isSticker {
                    return "[Sticker]"
                }
                if file.isInstantVideo {
                    return "[Video message]"
                }
                if file.isVoice {
                    return "[Voice message]"
                }
                if file.isMusic {
                    return "[Music]"
                }
                if file.isVideo {
                    return "[Video]"
                }
                if file.isAnimated {
                    return "[GIF]"
                }
                if let name = file.fileName, !name.isEmpty {
                    return "[\(name)]"
                }
                return "[File]"
            }
            if media is TelegramMediaWebpage {
                return "[Link]"
            }
            if media is TelegramMediaMap {
                return "[Location]"
            }
            if media is TelegramMediaContact {
                return "[Contact]"
            }
            if media is TelegramMediaPoll {
                return "[Poll]"
            }
            if media is TelegramMediaDice {
                return "[Dice]"
            }
            if media is TelegramMediaGame {
                return "[Game]"
            }
            if media is TelegramMediaInvoice {
                return "[Invoice]"
            }
            if media is TelegramMediaAction {
                return nil
            }
        }
        return nil
    }

    private static func authorName(for message: Message) -> String {
        if let user = message.author as? TelegramUser {
            let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "Unknown" : name
        }
        if let peer = message.author {
            let title = peer.debugDisplayTitle
            return title.isEmpty ? "Unknown" : title
        }
        return "Unknown"
    }

    /// Incoming (MTProto `out` unset) or CountedAsIncoming — excludes the local user's
    /// own outgoing messages in every chat type, including channels.
    private static func shouldSave(message: Message, settings: MessageSavingBridgeSettings) -> Bool {
        if message.isLocallyDeleted {
            return false
        }
        if !message.flags.contains(.Incoming) && !message.flags.contains(.CountedAsIncoming) {
            return false
        }
        if let author = message.author as? TelegramUser, author.botInfo != nil, !settings.saveForBots {
            return false
        }
        if let peer = message.peers[message.id.peerId] as? TelegramUser, peer.botInfo != nil, !settings.saveForBots {
            return false
        }
        return true
    }

    /// Whether a remote delete should keep the bubble in chat (anti-recall) instead of removing it.
    public static func shouldRetainInChat(message: Message) -> Bool {
        let current = settings.with { $0 }
        guard current.saveDeleted else { return false }
        guard shouldSave(message: message, settings: current) else { return false }
        if message.media.contains(where: { $0 is TelegramMediaAction }) && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return displayText(for: message) != nil || !message.media.isEmpty
    }

    public static func snapshotMessages(
        transaction: Transaction,
        accountPeerId: PeerId,
        messageIds: [MessageId],
        kind: MessageSavingKind
    ) {
        let current = settings.with { $0 }
        switch kind {
        case .deleted:
            guard current.saveDeleted else { return }
        case .edited:
            guard current.saveEdits else { return }
        }
        guard let sink = append.with({ $0 }) else { return }

        let now = Int32(Date().timeIntervalSince1970)
        for id in messageIds {
            guard let message = transaction.getMessage(id) else { continue }
            guard shouldSave(message: message, settings: current) else { continue }
            guard let text = displayText(for: message) else { continue }

            let record = MessageSavingRecord(
                id: UUID().uuidString,
                accountPeerId: accountPeerId.toInt64(),
                peerId: message.id.peerId.toInt64(),
                messageId: message.id.id,
                namespace: message.id.namespace,
                date: message.timestamp,
                authorId: message.author.map { $0.id.toInt64() },
                authorName: authorName(for: message),
                text: text,
                kind: kind,
                savedAt: now,
                topicId: message.threadId ?? 0
            )
            sink(record)
        }
    }

    public static func snapshotMessage(
        message: Message,
        accountPeerId: PeerId,
        kind: MessageSavingKind
    ) {
        let current = settings.with { $0 }
        switch kind {
        case .deleted:
            guard current.saveDeleted else { return }
        case .edited:
            guard current.saveEdits else { return }
        }
        guard let sink = append.with({ $0 }) else { return }
        guard shouldSave(message: message, settings: current) else { return }
        guard let text = displayText(for: message) else { return }

        let record = MessageSavingRecord(
            id: UUID().uuidString,
            accountPeerId: accountPeerId.toInt64(),
            peerId: message.id.peerId.toInt64(),
            messageId: message.id.id,
            namespace: message.id.namespace,
            date: message.timestamp,
            authorId: message.author.map { $0.id.toInt64() },
            authorName: authorName(for: message),
            text: text,
            kind: kind,
            savedAt: Int32(Date().timeIntervalSince1970),
            topicId: message.threadId ?? 0
        )
        sink(record)
    }

    /// Resolve account peer from the postbox and snapshot before a local delete.
    /// Used by `_internal_deleteMessages` so TTL / interactive / secret-chat paths
    /// are covered even when they never go through `replayFinalState`.
    public static func snapshotDeletedMessages(
        transaction: Transaction,
        messageIds: [MessageId]
    ) {
        guard let accountPeerId = (transaction.getState() as? AuthorizedAccountState)?.peerId else {
            return
        }
        snapshotMessages(
            transaction: transaction,
            accountPeerId: accountPeerId,
            messageIds: messageIds,
            kind: .deleted
        )
    }
}
