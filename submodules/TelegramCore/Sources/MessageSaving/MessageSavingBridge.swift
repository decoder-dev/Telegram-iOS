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

    public static let disabled = MessageSavingBridgeSettings(saveDeleted: false, saveEdits: false, saveForBots: false)
}

/// TelegramCore cannot import TelegramUIPreferences; SharedAccountContext pushes settings + append sink here.
public enum MessageSavingBridge {
    public static let settings = Atomic(value: MessageSavingBridgeSettings.disabled)
    public static let append = Atomic<((MessageSavingRecord) -> Void)?>(value: nil)

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
            // message.id.peerId is the CHAT the message lives in, not its author — it only
            // equals accountPeerId for the Saved Messages self-chat. Use the Incoming flag to
            // correctly exclude the local account's own outgoing messages in every chat.
            if !message.flags.contains(.Incoming) {
                continue
            }
            if let author = message.author as? TelegramUser, author.botInfo != nil, !current.saveForBots {
                continue
            }
            if let peer = message.peers[message.id.peerId] as? TelegramUser, peer.botInfo != nil, !current.saveForBots {
                continue
            }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let author = message.author
            let authorName: String
            if let user = author as? TelegramUser {
                authorName = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            } else if let peer = author {
                authorName = peer.debugDisplayTitle
            } else {
                authorName = ""
            }

            let record = MessageSavingRecord(
                id: UUID().uuidString,
                accountPeerId: accountPeerId.toInt64(),
                peerId: message.id.peerId.toInt64(),
                messageId: message.id.id,
                namespace: message.id.namespace,
                date: message.timestamp,
                authorId: author.map { $0.id.toInt64() },
                authorName: authorName.isEmpty ? "Unknown" : authorName,
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
        // Same fix as snapshotMessages: check authorship via the Incoming flag, not whether
        // the chat itself is the Saved Messages self-chat.
        if !message.flags.contains(.Incoming) {
            return
        }
        if let author = message.author as? TelegramUser, author.botInfo != nil, !current.saveForBots {
            return
        }
        if let peer = message.peers[message.id.peerId] as? TelegramUser, peer.botInfo != nil, !current.saveForBots {
            return
        }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let author = message.author
        let authorName: String
        if let user = author as? TelegramUser {
            authorName = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        } else if let peer = author {
            authorName = peer.debugDisplayTitle
        } else {
            authorName = ""
        }

        let record = MessageSavingRecord(
            id: UUID().uuidString,
            accountPeerId: accountPeerId.toInt64(),
            peerId: message.id.peerId.toInt64(),
            messageId: message.id.id,
            namespace: message.id.namespace,
            date: message.timestamp,
            authorId: author.map { $0.id.toInt64() },
            authorName: authorName.isEmpty ? "Unknown" : authorName,
            text: text,
            kind: kind,
            savedAt: Int32(Date().timeIntervalSince1970),
            topicId: message.threadId ?? 0
        )
        sink(record)
    }
}
