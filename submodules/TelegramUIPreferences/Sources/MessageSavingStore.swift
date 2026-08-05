import Foundation
import TelegramCore
import SwiftSignalKit

/// File-backed store for AyuGram-style deleted / edited message text snapshots.
public enum MessageSavingStore {
    private static let queue = DispatchQueue(label: "ph.teleg.Telegrapf.MessageSavingStore")
    private static let lock = NSLock()
    private static var memory: [MessageSavingRecord] = []
    private static var loaded = false

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MessageSaving", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("records.json")
    }

    private static func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else {
            memory = []
            return
        }
        memory = (try? JSONDecoder().decode([MessageSavingRecord].self, from: data)) ?? []
    }

    private static func persistLocked() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func installBridge() {
        let _ = MessageSavingBridge.append.swap({ record in
            queue.async {
                append(record)
            }
        })
    }

    public static func append(_ record: MessageSavingRecord) {
        loadIfNeeded()
        lock.lock()
        // Deduplicate consecutive identical deleted snapshots for the same message.
        if record.kind == .deleted,
           memory.contains(where: {
               $0.kind == .deleted
                   && $0.accountPeerId == record.accountPeerId
                   && $0.peerId == record.peerId
                   && $0.messageId == record.messageId
                   && $0.namespace == record.namespace
                   && $0.text == record.text
           }) {
            lock.unlock()
            return
        }
        memory.append(record)
        // Soft cap to keep the JSON store bounded.
        if memory.count > 5000 {
            memory.removeFirst(memory.count - 5000)
        }
        persistLocked()
        lock.unlock()
    }

    public static func deleted(
        accountPeerId: Int64,
        peerId: Int64,
        topicId: Int64? = nil
    ) -> [MessageSavingRecord] {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return memory.filter { record in
            record.kind == .deleted
                && record.accountPeerId == accountPeerId
                && record.peerId == peerId
                && (topicId == nil || topicId == 0 || record.topicId == topicId)
        }
        .sorted { $0.date > $1.date }
    }

    public static func edits(
        accountPeerId: Int64,
        peerId: Int64,
        messageId: Int32,
        namespace: Int32
    ) -> [MessageSavingRecord] {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return memory.filter { record in
            record.kind == .edited
                && record.accountPeerId == accountPeerId
                && record.peerId == peerId
                && record.messageId == messageId
                && record.namespace == namespace
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    public static func hasEdits(
        accountPeerId: Int64,
        peerId: Int64,
        messageId: Int32,
        namespace: Int32
    ) -> Bool {
        return !edits(accountPeerId: accountPeerId, peerId: peerId, messageId: messageId, namespace: namespace).isEmpty
    }

    public static func hasDeleted(accountPeerId: Int64, peerId: Int64, topicId: Int64? = nil) -> Bool {
        return !deleted(accountPeerId: accountPeerId, peerId: peerId, topicId: topicId).isEmpty
    }

    public static func clearDeleted(accountPeerId: Int64, peerId: Int64, topicId: Int64? = nil) {
        loadIfNeeded()
        lock.lock()
        memory.removeAll { record in
            record.kind == .deleted
                && record.accountPeerId == accountPeerId
                && record.peerId == peerId
                && (topicId == nil || topicId == 0 || record.topicId == topicId)
        }
        persistLocked()
        lock.unlock()
    }

    public static func applySettings(_ settings: ForkExtrasSettings) {
        let _ = MessageSavingBridge.settings.swap(MessageSavingBridgeSettings(
            saveDeleted: settings.saveDeletedMessages,
            saveEdits: settings.saveMessagesHistory,
            saveForBots: settings.saveForBots
        ))
    }
}
