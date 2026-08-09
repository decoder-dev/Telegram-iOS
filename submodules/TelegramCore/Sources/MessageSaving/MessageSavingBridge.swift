import Foundation
import Postbox
import SwiftSignalKit

/// Kind of locally saved message snapshot (AyuGram-style anti-recall / edit history).
public enum MessageSavingKind: String, Codable {
    case deleted
    case edited
}

/// Snapshot persisted outside Postbox. AyuGram Android also keeps `mediaPath` for attachments.
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
    /// Durable local copy under MessageSaving/Saved Attachments (optional).
    public let mediaPath: String?

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
        topicId: Int64,
        mediaPath: String? = nil
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
        self.mediaPath = mediaPath
    }

    /// Records are immutable; this produces the same record carrying a durable attachment path.
    public func withMediaPath(_ mediaPath: String?) -> MessageSavingRecord {
        return MessageSavingRecord(
            id: self.id,
            accountPeerId: self.accountPeerId,
            peerId: self.peerId,
            messageId: self.messageId,
            namespace: self.namespace,
            date: self.date,
            authorId: self.authorId,
            authorName: self.authorName,
            text: self.text,
            kind: self.kind,
            savedAt: self.savedAt,
            topicId: self.topicId,
            mediaPath: mediaPath
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountPeerId, peerId, messageId, namespace, date, authorId, authorName, text, kind, savedAt, topicId, mediaPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.accountPeerId = try container.decode(Int64.self, forKey: .accountPeerId)
        self.peerId = try container.decode(Int64.self, forKey: .peerId)
        self.messageId = try container.decode(Int32.self, forKey: .messageId)
        self.namespace = try container.decode(Int32.self, forKey: .namespace)
        self.date = try container.decode(Int32.self, forKey: .date)
        self.authorId = try container.decodeIfPresent(Int64.self, forKey: .authorId)
        self.authorName = try container.decode(String.self, forKey: .authorName)
        self.text = try container.decode(String.self, forKey: .text)
        self.kind = try container.decode(MessageSavingKind.self, forKey: .kind)
        self.savedAt = try container.decode(Int32.self, forKey: .savedAt)
        self.topicId = try container.decode(Int64.self, forKey: .topicId)
        self.mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.accountPeerId, forKey: .accountPeerId)
        try container.encode(self.peerId, forKey: .peerId)
        try container.encode(self.messageId, forKey: .messageId)
        try container.encode(self.namespace, forKey: .namespace)
        try container.encode(self.date, forKey: .date)
        try container.encodeIfPresent(self.authorId, forKey: .authorId)
        try container.encode(self.authorName, forKey: .authorName)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.kind, forKey: .kind)
        try container.encode(self.savedAt, forKey: .savedAt)
        try container.encode(self.topicId, forKey: .topicId)
        try container.encodeIfPresent(self.mediaPath, forKey: .mediaPath)
    }
}

public struct MessageSavingBridgeSettings: Equatable {
    public var saveDeleted: Bool
    public var saveEdits: Bool
    public var saveForBots: Bool
    public var saveMedia: Bool

    public init(saveDeleted: Bool, saveEdits: Bool, saveForBots: Bool, saveMedia: Bool = true) {
        self.saveDeleted = saveDeleted
        self.saveEdits = saveEdits
        self.saveForBots = saveForBots
        self.saveMedia = saveMedia
    }

    /// Matches ForkExtrasSettings.defaultSettings so deletes are captured before
    /// SharedAccountContext's async sharedData subscription applies persisted prefs.
    public static let defaults = MessageSavingBridgeSettings(saveDeleted: true, saveEdits: true, saveForBots: false, saveMedia: true)

    public static let disabled = MessageSavingBridgeSettings(saveDeleted: false, saveEdits: false, saveForBots: false, saveMedia: false)
}

/// TelegramCore cannot import TelegramUIPreferences; SharedAccountContext pushes settings + append sink here.
public enum MessageSavingBridge {
    /// AyuGram Android default deleted mark (`AyuConstants.DEFAULT_DELETED_MARK`).
    public static let defaultDeletedMark = "🧹"

    public static let settings = Atomic(value: MessageSavingBridgeSettings.defaults)
    public static let append = Atomic<((MessageSavingRecord) -> Void)?>(value: nil)
    /// (accountPeerId, peerId, messageId, namespace, mediaPath) — links a durable copy that
    /// finished after the record was already stored. Installed by MessageSavingStore.
    public static let updateMediaPath = Atomic<((Int64, Int64, Int32, Int32, String) -> Void)?>(value: nil)

    /// Canonical durable-attachment directory. Exposed so the store can verify that anything it
    /// is about to delete really lives inside it.
    public static var savedAttachmentsDirectory: URL {
        return MessageSavingAttachments.directoryURL
    }

    /// Re-link a record whose durable copy exists on disk but whose stored `mediaPath` is nil.
    /// The retry chain lives only in memory, so a copy that completed just before the app was
    /// killed — or a record written before linking existed — would otherwise never be connected.
    /// Called lazily for the records actually being displayed, never as a global scan.
    /// Returns the path when a link was made.
    @discardableResult
    public static func reconcileStoredAttachment(
        accountPeerId: PeerId,
        peerId: PeerId,
        namespace: Int32,
        messageId: Int32,
        mediaBox: MediaBox
    ) -> String? {
        guard let path = MessageSavingAttachments.existingCopyPath(
            peerId: peerId.toInt64(),
            namespace: namespace,
            messageId: messageId,
            mediaBox: mediaBox
        ) else {
            return nil
        }
        guard let update = updateMediaPath.with({ $0 }) else { return nil }
        update(accountPeerId.toInt64(), peerId.toInt64(), messageId, namespace, path)
        log("reconcile: relinked existing durable copy for \(messageId)")
        return path
    }

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[MessageSaving] \(message())")
        #endif
    }

    /// Prefer a textual body; fall back to a short media placeholder so media-only
    /// deletes still appear in View Deleted.
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

    private static func authorName(for message: Message, accountPeer: Peer? = nil) -> String {
        if let user = message.author as? TelegramUser {
            let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? "Unknown" : name
        }
        if let peer = message.author {
            let title = peer.debugDisplayTitle
            return title.isEmpty ? "Unknown" : title
        }
        // Outgoing cloud messages sometimes omit author; use the local account peer.
        if !message.flags.contains(.Incoming), let accountPeer {
            let title = accountPeer.debugDisplayTitle
            if !title.isEmpty {
                return title
            }
        }
        return "Unknown"
    }

    private static func shouldSave(message: Message, settings: MessageSavingBridgeSettings) -> Bool {
        if message.isLocallyDeleted {
            return false
        }
        // AyuGram Android saves outgoing/own messages too — no Incoming-only filter.
        if let author = message.author as? TelegramUser, author.botInfo != nil, !settings.saveForBots {
            return false
        }
        if let peer = message.peers[message.id.peerId] as? TelegramUser, peer.botInfo != nil, !settings.saveForBots {
            return false
        }
        return true
    }

    /// Whether a remote / TTL delete should keep the bubble in chat (anti-recall) instead of removing it.
    public static func shouldRetainInChat(message: Message) -> Bool {
        let current = settings.with { $0 }
        guard current.saveDeleted else { return false }
        guard shouldSave(message: message, settings: current) else { return false }
        if message.media.contains(where: { $0 is TelegramMediaAction }) && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return displayText(for: message) != nil || !message.media.isEmpty
    }

    /// AyuGram Android: when Save Deleted is on, skip secret/view-once TTL countdown and media wipe.
    public static var shouldProtectSecretMedia: Bool {
        return settings.with { $0.saveDeleted }
    }

    private static let preserveQueue = DispatchQueue(label: "MessageSavingBridge.preserve", qos: .utility)

    /// Identifies an in-flight preserve so a message that is opened / re-delivered repeatedly
    /// does not accumulate parallel retry chains all copying the same file.
    private struct PreserveKey: Hashable {
        let accountScope: String
        let peerId: Int64
        let namespace: Int32
        let messageId: Int32
    }

    private static let pendingPreserves = Atomic<Set<PreserveKey>>(value: Set())

    /// Copy attachments early (on open / consume) so TTL can't race the cache eviction.
    /// `accountPeerId` is only needed to link a late copy back to an already-stored record;
    /// the copy itself is account-scoped through `mediaBox`.
    public static func preserveMediaIfNeeded(message: Message, accountPeerId: PeerId? = nil, mediaBox: MediaBox) {
        let current = settings.with { $0 }
        guard current.saveDeleted, current.saveMedia else { return }
        if let path = MessageSavingAttachments.copyIfAvailable(message: message, mediaBox: mediaBox) {
            log("preserve: durable copy available immediately \(message.id.id)")
            linkMediaPath(path, message: message, accountPeerId: accountPeerId)
            return
        }
        // The resource is only copyable once fully downloaded, and one-time media is typically
        // still downloading at the moment the user opens it — giving up here is what loses
        // exactly the media this feature exists to keep. Retry on a backoff instead.
        let key = PreserveKey(
            accountScope: mediaBox.basePath,
            peerId: message.id.peerId.toInt64(),
            namespace: message.id.namespace,
            messageId: message.id.id
        )
        // Insert-if-absent under the lock: only the first caller starts a retry chain.
        var shouldStart = false
        let _ = pendingPreserves.modify { current -> Set<PreserveKey> in
            if current.contains(key) {
                return current
            }
            shouldStart = true
            var updated = current
            updated.insert(key)
            return updated
        }
        guard shouldStart else {
            log("preserve: retry already pending for \(message.id.id)")
            return
        }
        retryPreserve(message: message, accountPeerId: accountPeerId, mediaBox: mediaBox, key: key, attemptsRemaining: 6, delay: 1.0)
    }

    private static func finishPreserve(_ key: PreserveKey) {
        let _ = pendingPreserves.modify { current -> Set<PreserveKey> in
            var updated = current
            updated.remove(key)
            return updated
        }
    }

    private static func retryPreserve(message: Message, accountPeerId: PeerId?, mediaBox: MediaBox, key: PreserveKey, attemptsRemaining: Int, delay: Double) {
        guard attemptsRemaining > 0 else {
            log("preserve: retries exhausted for \(message.id.id) — source never became available")
            finishPreserve(key)
            return
        }
        preserveQueue.asyncAfter(deadline: .now() + delay) {
            guard settings.with({ $0.saveDeleted && $0.saveMedia }) else {
                finishPreserve(key)
                return
            }
            if let path = MessageSavingAttachments.copyIfAvailable(message: message, mediaBox: mediaBox) {
                log("preserve: late copy succeeded for \(message.id.id)")
                linkMediaPath(path, message: message, accountPeerId: accountPeerId)
                finishPreserve(key)
                return
            }
            retryPreserve(message: message, accountPeerId: accountPeerId, mediaBox: mediaBox, key: key, attemptsRemaining: attemptsRemaining - 1, delay: min(delay * 2.0, 16.0))
        }
    }

    /// Attach a durable path to an already-stored deleted record. Without this a record created
    /// while the file was still downloading keeps `mediaPath == nil` forever, so View Deleted
    /// never learns about the file the retry eventually copied.
    private static func linkMediaPath(_ path: String, message: Message, accountPeerId: PeerId?) {
        guard let accountPeerId else { return }
        guard let update = updateMediaPath.with({ $0 }) else { return }
        update(accountPeerId.toInt64(), message.id.peerId.toInt64(), message.id.id, message.id.namespace, path)
        log("preserve: linked media path to stored record \(message.id.id)")
    }

    public static func snapshotMessages(
        transaction: Transaction,
        accountPeerId: PeerId,
        messageIds: [MessageId],
        kind: MessageSavingKind,
        mediaBox: MediaBox? = nil
    ) {
        let current = settings.with { $0 }
        switch kind {
        case .deleted:
            guard current.saveDeleted else { return }
        case .edited:
            guard current.saveEdits else { return }
        }
        guard let sink = append.with({ $0 }) else { return }

        let accountPeer = transaction.getPeer(accountPeerId)
        let now = Int32(Date().timeIntervalSince1970)
        for id in messageIds {
            guard let message = transaction.getMessage(id) else { continue }
            guard shouldSave(message: message, settings: current) else { continue }
            guard let text = displayText(for: message) else { continue }

            var mediaPath: String?
            if kind == .deleted, current.saveMedia, let mediaBox {
                mediaPath = MessageSavingAttachments.copyIfAvailable(message: message, mediaBox: mediaBox)
            }

            let record = MessageSavingRecord(
                id: UUID().uuidString,
                accountPeerId: accountPeerId.toInt64(),
                peerId: message.id.peerId.toInt64(),
                messageId: message.id.id,
                namespace: message.id.namespace,
                date: message.timestamp,
                authorId: message.author.map { $0.id.toInt64() } ?? (message.flags.contains(.Incoming) ? nil : accountPeerId.toInt64()),
                authorName: authorName(for: message, accountPeer: accountPeer),
                text: text,
                kind: kind,
                savedAt: now,
                topicId: message.threadId ?? 0,
                mediaPath: mediaPath
            )
            sink(record)
        }
    }

    public static func snapshotMessage(
        message: Message,
        accountPeerId: PeerId,
        kind: MessageSavingKind,
        mediaBox: MediaBox? = nil,
        accountPeer: Peer? = nil
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

        var mediaPath: String?
        if kind == .deleted, current.saveMedia, let mediaBox {
            mediaPath = MessageSavingAttachments.copyIfAvailable(message: message, mediaBox: mediaBox)
        }

        let record = MessageSavingRecord(
            id: UUID().uuidString,
            accountPeerId: accountPeerId.toInt64(),
            peerId: message.id.peerId.toInt64(),
            messageId: message.id.id,
            namespace: message.id.namespace,
            date: message.timestamp,
            authorId: message.author.map { $0.id.toInt64() } ?? (message.flags.contains(.Incoming) ? nil : accountPeerId.toInt64()),
            authorName: authorName(for: message, accountPeer: accountPeer),
            text: text,
            kind: kind,
            savedAt: Int32(Date().timeIntervalSince1970),
            topicId: message.threadId ?? 0,
            mediaPath: mediaPath
        )
        sink(record)
    }

    /// Resolve account peer from the postbox and snapshot before a local delete.
    public static func snapshotDeletedMessages(
        transaction: Transaction,
        messageIds: [MessageId],
        mediaBox: MediaBox? = nil
    ) {
        guard let accountPeerId = (transaction.getState() as? AuthorizedAccountState)?.peerId else {
            return
        }
        snapshotMessages(
            transaction: transaction,
            accountPeerId: accountPeerId,
            messageIds: messageIds,
            kind: .deleted,
            mediaBox: mediaBox
        )
    }
}
