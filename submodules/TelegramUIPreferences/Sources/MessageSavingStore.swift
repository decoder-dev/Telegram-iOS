import Foundation
import UIKit
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

    private static var pendingPersist = false
    private static var observerInstalled = false

    /// Coalesce disk writes. Previously every single saved record triggered a full JSON
    /// re-encode of the entire store plus an atomic file write, all while holding the lock —
    /// so a burst of deletions (channel spam cleanup, bulk admin delete) meant hundreds of
    /// full re-serializations back to back, and main-thread readers blocked on each one.
    private static func schedulePersistLocked() {
        guard !self.pendingPersist else { return }
        self.pendingPersist = true
        queue.asyncAfter(deadline: .now() + 5.0) {
            self.persistNow()
        }
    }

    private static func persistNow() {
        lock.lock()
        self.pendingPersist = false
        let snapshot = self.memory
        lock.unlock()
        // Encode outside the lock: serialization is the expensive part, and holding the lock
        // through it is what stalled main-thread reads (hasDeleted/hasEdits in context menus).
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: self.fileURL, options: .atomic)
    }

    /// Force any coalesced write out to disk (called when the app leaves the foreground).
    public static func flush() {
        self.persistNow()
    }

    /// Bumped after every mutation so open screens (View Deleted) can refresh when a late
    /// attachment lands. Signal-based rather than a callback so subscribers get main-queue
    /// delivery of their own choosing; never fired while the lock is held.
    public static let changes = ValuePromise<Int>(0, ignoreRepeated: false)
    private static var changeCounter: Int = 0

    private static func notifyChanged() {
        lock.lock()
        self.changeCounter += 1
        let value = self.changeCounter
        lock.unlock()
        changes.set(value)
    }

    /// Link a durable attachment copied after the record was already stored.
    public static func attachMediaPath(
        accountPeerId: Int64,
        peerId: Int64,
        messageId: Int32,
        namespace: Int32,
        mediaPath: String
    ) {
        loadIfNeeded()
        lock.lock()
        var didChange = false
        for index in memory.indices {
            let record = memory[index]
            if record.kind == .deleted
                && record.accountPeerId == accountPeerId
                && record.peerId == peerId
                && record.messageId == messageId
                && record.namespace == namespace
                && record.mediaPath != mediaPath
            {
                memory[index] = record.withMediaPath(mediaPath)
                didChange = true
            }
        }
        if didChange {
            schedulePersistLocked()
        }
        lock.unlock()
        if didChange {
            notifyChanged()
        }
    }

    public static func installBridge() {
        if !self.observerInstalled {
            self.observerInstalled = true
            // Process-lifetime singleton observer — deliberately never removed.
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil, using: { _ in
                MessageSavingStore.flush()
            })
        }
        let _ = MessageSavingBridge.append.swap({ record in
            queue.async {
                append(record)
            }
        })
        let _ = MessageSavingBridge.updateMediaPath.swap({ accountPeerId, peerId, messageId, namespace, mediaPath in
            queue.async {
                attachMediaPath(accountPeerId: accountPeerId, peerId: peerId, messageId: messageId, namespace: namespace, mediaPath: mediaPath)
            }
        })
    }

    public static func append(_ record: MessageSavingRecord) {
        loadIfNeeded()
        lock.lock()
        // Deduplicate consecutive identical deleted snapshots for the same message. A repeat
        // snapshot must not be dropped outright: the first one is often taken while the file is
        // still downloading (mediaPath nil) and a later one carries the durable path, so merge
        // the path into the existing record instead of losing it.
        if record.kind == .deleted,
           let existingIndex = memory.firstIndex(where: {
               $0.kind == .deleted
                   && $0.accountPeerId == record.accountPeerId
                   && $0.peerId == record.peerId
                   && $0.messageId == record.messageId
                   && $0.namespace == record.namespace
                   && $0.text == record.text
           }) {
            var merged = false
            if memory[existingIndex].mediaPath == nil, let newPath = record.mediaPath {
                memory[existingIndex] = memory[existingIndex].withMediaPath(newPath)
                schedulePersistLocked()
                merged = true
            }
            lock.unlock()
            if merged {
                notifyChanged()
            }
            return
        }
        memory.append(record)
        // Soft cap to keep the JSON store bounded.
        if memory.count > 5000 {
            memory.removeFirst(memory.count - 5000)
        }
        schedulePersistLocked()
        lock.unlock()
        notifyChanged()
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
        lock.unlock()
        // User-initiated and rare — write through immediately so it survives a kill.
        persistNow()
        notifyChanged()
    }

    public static func applySettings(_ settings: ForkExtrasSettings) {
        let _ = MessageSavingBridge.settings.swap(MessageSavingBridgeSettings(
            saveDeleted: settings.saveDeletedMessages,
            saveEdits: settings.saveMessagesHistory,
            saveForBots: settings.saveForBots,
            saveMedia: settings.saveMedia
        ))
    }
}
