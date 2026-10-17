import Foundation
import TelegramCore
import Postbox

/// Fork (Regram): last opened chats, per account. Stored in UserDefaults like `ForkLastChatListFilter`; this is a
/// local convenience list, not a chat backup.
public enum ForkRecentChats {
    public static let limit = 50

    private static func key(accountPeerId: EnginePeer.Id) -> String {
        return "ForkExtras.recentChats.\(accountPeerId.toInt64())"
    }

    /// Newest first. Entries are "peerId" or "peerId:threadId".
    public static func items(accountPeerId: EnginePeer.Id) -> [(peerId: EnginePeer.Id, threadId: Int64?)] {
        let raw = UserDefaults.standard.stringArray(forKey: key(accountPeerId: accountPeerId)) ?? []
        var result: [(peerId: EnginePeer.Id, threadId: Int64?)] = []
        for entry in raw {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard let first = parts.first, let peerValue = Int64(first) else {
                continue
            }
            var threadId: Int64?
            if parts.count > 1 {
                threadId = Int64(parts[1])
            }
            result.append((EnginePeer.Id(peerValue), threadId))
        }
        return result
    }

    public static func record(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, threadId: Int64?) {
        let entry: String
        if let threadId {
            entry = "\(peerId.toInt64()):\(threadId)"
        } else {
            entry = "\(peerId.toInt64())"
        }
        let accountKey = key(accountPeerId: accountPeerId)
        var raw = UserDefaults.standard.stringArray(forKey: accountKey) ?? []
        if raw.first == entry {
            return
        }
        raw.removeAll(where: { $0 == entry })
        raw.insert(entry, at: 0)
        if raw.count > limit {
            raw = Array(raw.prefix(limit))
        }
        UserDefaults.standard.set(raw, forKey: accountKey)
    }

    public static func clear(accountPeerId: EnginePeer.Id) {
        UserDefaults.standard.removeObject(forKey: key(accountPeerId: accountPeerId))
    }
}

/// Fork (Regram): a local-only name for a group or channel. Peer ids are unique across accounts, so the table is global.
/// `isEnabled` mirrors the Extras switch; with it off, titles are exactly the server ones.
public enum ForkLocalGroupAlias {
    private static let defaultsKey = "ForkExtras.localGroupAliases"
    private static let lock = NSLock()
    private static var enabled = false
    private static var cache: [Int64: String]?

    public static var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            enabled = newValue
            lock.unlock()
        }
    }

    private static func loadedCache() -> [Int64: String] {
        if let cache {
            return cache
        }
        var loaded: [Int64: String] = [:]
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            for (key, value) in stored {
                if let id = Int64(key) {
                    loaded[id] = value
                }
            }
        }
        cache = loaded
        return loaded
    }

    /// The alias to show instead of the server title, or nil.
    public static func alias(for peerId: EnginePeer.Id) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if !enabled {
            return nil
        }
        return loadedCache()[peerId.toInt64()]
    }

    /// The stored alias regardless of the switch (for the editor).
    public static func storedAlias(for peerId: EnginePeer.Id) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return loadedCache()[peerId.toInt64()]
    }

    /// An empty (after trimming) alias removes the entry and restores the server title.
    public static func setAlias(_ alias: String?, for peerId: EnginePeer.Id) {
        lock.lock()
        defer { lock.unlock() }
        var table = loadedCache()
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            table.removeValue(forKey: peerId.toInt64())
        } else {
            table[peerId.toInt64()] = trimmed
        }
        cache = table
        var stored: [String: String] = [:]
        for (key, value) in table {
            stored[String(key)] = value
        }
        UserDefaults.standard.set(stored, forKey: defaultsKey)
    }
}

/// Fork (Regram): a bookmarked message with free-form tags, kept on this device per account. It stores the message
/// position and a text snippet only; a deleted message is not recoverable from it.
public struct ForkMessageBookmark: Codable, Equatable {
    public var peerId: Int64
    public var threadId: Int64?
    public var messageNamespace: Int32
    public var messageId: Int32
    public var chatTitle: String
    public var snippet: String
    public var tags: [String]
    public var messageDate: Int32
    public var createdAt: Int32

    public init(peerId: Int64, threadId: Int64?, messageNamespace: Int32, messageId: Int32, chatTitle: String, snippet: String, tags: [String], messageDate: Int32, createdAt: Int32) {
        self.peerId = peerId
        self.threadId = threadId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.chatTitle = chatTitle
        self.snippet = snippet
        self.tags = tags
        self.messageDate = messageDate
        self.createdAt = createdAt
    }

    public var identity: String {
        return "\(self.peerId):\(self.messageNamespace):\(self.messageId)"
    }
}

public enum ForkMessageBookmarks {
    private static func key(accountPeerId: EnginePeer.Id) -> String {
        return "ForkExtras.messageBookmarks.\(accountPeerId.toInt64())"
    }

    /// Newest bookmark first.
    public static func all(accountPeerId: EnginePeer.Id) -> [ForkMessageBookmark] {
        guard let data = UserDefaults.standard.data(forKey: key(accountPeerId: accountPeerId)),
              let items = try? JSONDecoder().decode([ForkMessageBookmark].self, from: data) else {
            return []
        }
        return items
    }

    private static func store(_ items: [ForkMessageBookmark], accountPeerId: EnginePeer.Id) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key(accountPeerId: accountPeerId))
        }
    }

    public static func find(accountPeerId: EnginePeer.Id, peerId: Int64, messageNamespace: Int32, messageId: Int32) -> ForkMessageBookmark? {
        return all(accountPeerId: accountPeerId).first(where: { $0.peerId == peerId && $0.messageNamespace == messageNamespace && $0.messageId == messageId })
    }

    /// Adds, or replaces the tags and snippet of, the bookmark for the same message.
    public static func upsert(accountPeerId: EnginePeer.Id, _ bookmark: ForkMessageBookmark) {
        var items = all(accountPeerId: accountPeerId)
        items.removeAll(where: { $0.identity == bookmark.identity })
        items.insert(bookmark, at: 0)
        store(items, accountPeerId: accountPeerId)
    }

    public static func remove(accountPeerId: EnginePeer.Id, identity: String) {
        var items = all(accountPeerId: accountPeerId)
        items.removeAll(where: { $0.identity == identity })
        store(items, accountPeerId: accountPeerId)
    }

    /// Splits "a, b；c" style input into trimmed, unique, non-empty tags.
    public static func parseTags(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;，；\n")
        var result: [String] = []
        for part in text.components(separatedBy: separators) {
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty && !result.contains(tag) {
                result.append(tag)
            }
        }
        return result
    }
}
