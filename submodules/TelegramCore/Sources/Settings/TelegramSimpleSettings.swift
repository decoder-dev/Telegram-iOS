import Foundation
import Postbox
import SwiftSignalKit

public final class TelegramSimpleSettings {
    public static let shared = TelegramSimpleSettings()

    private let defaults: UserDefaults

    private enum Key {
        static let saveDeletedMessages = "telegram.mod.saveDeletedMessages"
        static let saveEditHistory = "telegram.mod.saveEditHistory"
        static let saveViewOnceMedia = "telegram.mod.saveViewOnceMedia"
        static let saveInBotChats = "telegram.mod.saveInBotChats"
        static let allowCopyProtectedMedia = "telegram.mod.allowCopyProtectedMedia"
        static let showExactOfflineTime = "telegram.ghost.showExactOfflineTime"
        static let bottomChatFolders = "telegram.ui.bottomChatFolders"
        static let channelForwardCounter = "telegram.ui.channelForwardCounter"
        static let glowEffectsEnabled = "telegram.ui.glowEffectsEnabled"
        static let avatarMentionsEnabled = "telegram.ui.avatarMentionsEnabled"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func getBool(_ key: String, defaultValue: Bool = true) -> Bool {
        if self.defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return self.defaults.bool(forKey: key)
    }

    private func setBool(_ value: Bool, forKey key: String) {
        self.defaults.set(value, forKey: key)
        self.defaults.synchronize()
    }

    public var saveDeletedMessages: Bool {
        get { self.getBool(Key.saveDeletedMessages, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveDeletedMessages) }
    }

    public var saveEditHistory: Bool {
        get { self.getBool(Key.saveEditHistory, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveEditHistory) }
    }

    public var saveViewOnceMedia: Bool {
        get { self.getBool(Key.saveViewOnceMedia, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveViewOnceMedia) }
    }

    public var saveInBotChats: Bool {
        get { self.getBool(Key.saveInBotChats, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveInBotChats) }
    }

    public var allowCopyProtectedMedia: Bool {
        get { self.getBool(Key.allowCopyProtectedMedia, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.allowCopyProtectedMedia) }
    }

    public var showExactOfflineTime: Bool {
        get { self.getBool(Key.showExactOfflineTime, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.showExactOfflineTime) }
    }

    public var bottomChatFolders: Bool {
        get { self.getBool(Key.bottomChatFolders, defaultValue: false) }
        set { self.setBool(newValue, forKey: Key.bottomChatFolders) }
    }

    public var channelForwardCounter: Bool {
        get { self.getBool(Key.channelForwardCounter, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.channelForwardCounter) }
    }

    public var glowEffectsEnabled: Bool {
        get { self.getBool(Key.glowEffectsEnabled, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.glowEffectsEnabled) }
    }

    public var avatarMentionsEnabled: Bool {
        get { self.getBool(Key.avatarMentionsEnabled, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.avatarMentionsEnabled) }
    }
    /// A chat that ghost mode read only on this device: the server, and so the senders, still
    /// see it unread. Stored per account (`PeerId.toInt64()` keys) by TelegramCore, together
    /// with the server's read state the local read was made on top of.
    public struct GhostLocalRead: Equatable {
        /// Read here up to this id.
        public var maxIncomingReadId: Int32
        /// The server's read state.
        public var serverMaxIncomingReadId: Int32
        public var serverMarkedUnread: Bool
        /// The server's unread mark is read here as well.
        public var readsServerMark: Bool
        /// Messages the server counts as unread that are read here; nil when that is not known
        /// (the server read part of them on another device).
        public var readCount: Int32?

        public init(maxIncomingReadId: Int32, serverMaxIncomingReadId: Int32, serverMarkedUnread: Bool, readsServerMark: Bool, readCount: Int32?) {
            self.maxIncomingReadId = maxIncomingReadId
            self.serverMaxIncomingReadId = serverMaxIncomingReadId
            self.serverMarkedUnread = serverMarkedUnread
            self.readsServerMark = readsServerMark
            self.readCount = readCount
        }
    }

    private let ghostLocalReadLock = NSLock()
    private var ghostLocalReadCache: [Int64: [Int64: GhostLocalRead]] = [:]

    private func ghostLocalReadsKey(accountPeerId: Int64) -> String {
        return "banana.ghost.localReads.\(accountPeerId)"
    }

    // Call with ghostLocalReadLock held.
    private func ghostLocalReadsLocked(accountPeerId: Int64) -> [Int64: GhostLocalRead] {
        if let cached = self.ghostLocalReadCache[accountPeerId] {
            return cached
        }
        var reads: [Int64: GhostLocalRead] = [:]
        for (key, value) in self.defaults.dictionary(forKey: ghostLocalReadsKey(accountPeerId: accountPeerId)) ?? [:] {
            guard let peerId = Int64(key), let values = value as? [Int], values.count == 5 else {
                continue
            }
            let ids = values.prefix(3).compactMap { Int32(exactly: $0) }
            guard ids.count == 3 else {
                continue
            }
            reads[peerId] = GhostLocalRead(maxIncomingReadId: ids[0], serverMaxIncomingReadId: ids[1], serverMarkedUnread: values[3] != 0, readsServerMark: values[4] != 0, readCount: ids[2] >= 0 ? ids[2] : nil)
        }
        self.ghostLocalReadCache[accountPeerId] = reads
        return reads
    }

    public func hasGhostLocalReads(accountPeerId: Int64) -> Bool {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        return !self.ghostLocalReadsLocked(accountPeerId: accountPeerId).isEmpty
    }

    public func ghostLocalRead(accountPeerId: Int64, peerId: Int64) -> GhostLocalRead? {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        return self.ghostLocalReadsLocked(accountPeerId: accountPeerId)[peerId]
    }

    public func ghostLocalReads(accountPeerId: Int64) -> [Int64: GhostLocalRead] {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        return self.ghostLocalReadsLocked(accountPeerId: accountPeerId)
    }

    /// Records the chat's local read, or forgets it (`nil`).
    public func setGhostLocalRead(_ read: GhostLocalRead?, accountPeerId: Int64, peerId: Int64) {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        var reads = self.ghostLocalReadsLocked(accountPeerId: accountPeerId)
        guard reads[peerId] != read else {
            return
        }
        reads[peerId] = read
        self.ghostLocalReadCache[accountPeerId] = reads
        var stored: [String: [Int]] = [:]
        for (peerId, read) in reads {
            stored[String(peerId)] = [Int(read.maxIncomingReadId), Int(read.serverMaxIncomingReadId), Int(read.readCount ?? -1), read.serverMarkedUnread ? 1 : 0, read.readsServerMark ? 1 : 0]
        }
        self.defaults.set(stored, forKey: ghostLocalReadsKey(accountPeerId: accountPeerId))
    }

}
