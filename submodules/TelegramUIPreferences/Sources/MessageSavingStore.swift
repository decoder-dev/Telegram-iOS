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

    /// hasDeleted / hasEdits are called while building context menus, where a linear scan over
    /// up to 5000 records ran on the main thread for every menu open. These indexes make the
    /// existence checks a dictionary lookup instead.
    struct DeletedIndexKey: Hashable {
        let accountPeerId: Int64
        let peerId: Int64
    }

    struct EditIndexKey: Hashable {
        let accountPeerId: Int64
        let peerId: Int64
        let namespace: Int32
        let messageId: Int32
    }

    private static var deletedIndex: [DeletedIndexKey: Int] = [:]
    private static var editIndex: [EditIndexKey: Int] = [:]

    private static func indexKeys(for record: MessageSavingRecord) -> (DeletedIndexKey?, EditIndexKey?) {
        switch record.kind {
        case .deleted:
            return (DeletedIndexKey(accountPeerId: record.accountPeerId, peerId: record.peerId), nil)
        case .edited:
            return (nil, EditIndexKey(accountPeerId: record.accountPeerId, peerId: record.peerId, namespace: record.namespace, messageId: record.messageId))
        }
    }

    private static func indexAddLocked(_ record: MessageSavingRecord) {
        let (deletedKey, editKey) = indexKeys(for: record)
        if let deletedKey {
            deletedIndex[deletedKey, default: 0] += 1
        }
        if let editKey {
            editIndex[editKey, default: 0] += 1
        }
    }

    private static func indexRemoveLocked(_ record: MessageSavingRecord) {
        let (deletedKey, editKey) = indexKeys(for: record)
        if let deletedKey, let count = deletedIndex[deletedKey] {
            if count <= 1 {
                deletedIndex.removeValue(forKey: deletedKey)
            } else {
                deletedIndex[deletedKey] = count - 1
            }
        }
        if let editKey, let count = editIndex[editKey] {
            if count <= 1 {
                editIndex.removeValue(forKey: editKey)
            } else {
                editIndex[editKey] = count - 1
            }
        }
    }

    /// Versions retained per edited message.
    ///
    /// Without a per-message limit, one chatty message — a bot rewriting a counter, a live score,
    /// a progress line — accumulates a version per edit and pushes everything else out through the
    /// shared 5000-record cap, silently destroying other peers' saved deleted messages, which is
    /// the thing this feature exists to keep. 32 is well past what anyone reads and small enough
    /// that a runaway editor cannot dominate the store.
    private static let editHistoryLimitPerMessage = 32

    private static func editKey(for record: MessageSavingRecord) -> EditIndexKey {
        return EditIndexKey(
            accountPeerId: record.accountPeerId,
            peerId: record.peerId,
            namespace: record.namespace,
            messageId: record.messageId
        )
    }

    private static func isEdit(_ candidate: MessageSavingRecord, of key: EditIndexKey) -> Bool {
        return candidate.kind == .edited
            && candidate.accountPeerId == key.accountPeerId
            && candidate.peerId == key.peerId
            && candidate.messageId == key.messageId
            && candidate.namespace == key.namespace
    }

    private static func isDuplicateOfLatestEditLocked(_ record: MessageSavingRecord) -> Bool {
        let key = editKey(for: record)
        // The index answers "are there any versions at all" in O(1), so the first edit of a
        // message — the common case — never pays for the scan below.
        guard editIndex[key] != nil else {
            return false
        }
        guard let latest = memory.last(where: { isEdit($0, of: key) }) else {
            return false
        }
        return latest.text == record.text
    }

    /// Drop the oldest versions of one message once it exceeds the limit. `memory` is in insertion
    /// order, so scanning from the front removes oldest first.
    private static func enforceEditHistoryLimitLocked(for record: MessageSavingRecord) {
        let key = editKey(for: record)
        guard let count = editIndex[key], count > editHistoryLimitPerMessage else {
            return
        }
        var remaining = count - editHistoryLimitPerMessage
        var index = 0
        while index < memory.count && remaining > 0 {
            if isEdit(memory[index], of: key) {
                indexRemoveLocked(memory[index])
                memory.remove(at: index)
                remaining -= 1
                // Deliberately not advancing: the remaining elements shifted down by one.
                continue
            }
            index += 1
        }
    }

    private static func rebuildIndexesLocked() {
        deletedIndex.removeAll(keepingCapacity: true)
        editIndex.removeAll(keepingCapacity: true)
        for record in memory {
            indexAddLocked(record)
        }
    }

    /// Overridden by tests so they neither read nor overwrite the real store. Nil in the app.
    private static var overrideDirectory: URL?

    private static var fileURL: URL {
        let dir: URL
        if let overrideDirectory = self.overrideDirectory {
            dir = overrideDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("MessageSaving", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("records.json")
    }

    /// Point the store at `directory` and drop all in-memory state, so each test starts clean.
    /// `loaded` is cleared rather than set, so the next access reads whatever is in `directory` —
    /// a fresh directory yields an empty store, and pointing two runs at the same directory
    /// exercises the load path.
    ///
    /// Test-only: the app never calls this, and calling it at runtime would discard unsaved
    /// records.
    public static func resetForTesting(directory: URL) {
        lock.lock()
        self.overrideDirectory = directory
        self.memory = []
        self.deletedIndex.removeAll()
        self.editIndex.removeAll()
        self.storeGeneration = 0
        self.pendingPersist = false
        self.loaded = false
        lock.unlock()
        writeLock.lock()
        self.lastWrittenGeneration = 0
        writeLock.unlock()
    }

    /// Number of retained versions of one message, for tests asserting the per-message cap.
    public static func editCountForTesting(accountPeerId: Int64, peerId: Int64, messageId: Int32, namespace: Int32) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return editIndex[EditIndexKey(accountPeerId: accountPeerId, peerId: peerId, namespace: namespace, messageId: messageId)] ?? 0
    }

    /// Total retained records, for tests asserting eviction.
    public static var recordCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return memory.count
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
        rebuildIndexesLocked()
    }

    private static var pendingPersist = false
    private static var observerInstalled = false

    /// Bumped under `lock` on every mutation of `memory`, so a snapshot can be ordered against
    /// the snapshots other threads took. Only meaningful while holding `lock`.
    private static var storeGeneration: Int = 0
    /// Serializes the file write and guards `lastWrittenGeneration`. Deliberately separate from
    /// `lock`: the encode must not hold the reader lock, but two encodes finishing out of order
    /// still have to write in order.
    private static let writeLock = NSLock()
    private static var lastWrittenGeneration: Int = 0

    /// Coalesce disk writes. Previously every single saved record triggered a full JSON
    /// re-encode of the entire store plus an atomic file write, all while holding the lock —
    /// so a burst of deletions (channel spam cleanup, bulk admin delete) meant hundreds of
    /// full re-serializations back to back, and main-thread readers blocked on each one.
    private static func schedulePersistLocked() {
        self.storeGeneration += 1
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
        let generation = self.storeGeneration
        lock.unlock()
        // Encode outside the lock: serialization is the expensive part, and holding the lock
        // through it is what stalled main-thread reads (hasDeleted/hasEdits in context menus).
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Encoding outside the lock means two persists can be in flight at once — the 5s
        // coalesced one and a flush() triggered by backgrounding, which runs on whatever thread
        // the notification arrives on. Without ordering, the slower encode of the *older*
        // snapshot lands last and silently drops every record added in between. The generation
        // is compared and committed under writeLock so the check cannot race the write itself.
        writeLock.lock()
        defer { writeLock.unlock() }
        guard generation > self.lastWrittenGeneration else { return }
        try? data.write(to: self.fileURL, options: .atomic)
        self.lastWrittenGeneration = generation
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

    /// Ask open screens to rebuild without changing any record. Needed because a durable copy can
    /// finish after its record was already written with that exact path: nothing in the store
    /// changes when the bytes land, but what the screen renders does.
    public static func refresh() {
        notifyChanged()
    }

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
        // The same guard for edits. A message can legitimately go A -> B -> A, so only a snapshot
        // identical to the message's most recent one is dropped, not any earlier match.
        if record.kind == .edited, isDuplicateOfLatestEditLocked(record) {
            lock.unlock()
            return
        }
        memory.append(record)
        indexAddLocked(record)
        if record.kind == .edited {
            enforceEditHistoryLimitLocked(for: record)
        }
        // Soft cap to keep the JSON store bounded.
        if memory.count > 5000 {
            let overflow = memory.count - 5000
            for dropped in memory.prefix(overflow) {
                indexRemoveLocked(dropped)
            }
            memory.removeFirst(overflow)
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

    /// O(1) index lookup — called from context-menu construction on the main thread.
    public static func hasEdits(
        accountPeerId: Int64,
        peerId: Int64,
        messageId: Int32,
        namespace: Int32
    ) -> Bool {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return editIndex[EditIndexKey(accountPeerId: accountPeerId, peerId: peerId, namespace: namespace, messageId: messageId)] != nil
    }

    /// O(1) for the common (whole-peer) case. A topic-scoped query still needs the filter,
    /// but that path is only reached from forum chats.
    public static func hasDeleted(accountPeerId: Int64, peerId: Int64, topicId: Int64? = nil) -> Bool {
        if let topicId, topicId != 0 {
            return !deleted(accountPeerId: accountPeerId, peerId: peerId, topicId: topicId).isEmpty
        }
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return deletedIndex[DeletedIndexKey(accountPeerId: accountPeerId, peerId: peerId)] != nil
    }

    public static func clearDeleted(accountPeerId: Int64, peerId: Int64, topicId: Int64? = nil) {
        loadIfNeeded()
        lock.lock()
        var removedPaths: [String] = []
        memory.removeAll { record in
            let matches = record.kind == .deleted
                && record.accountPeerId == accountPeerId
                && record.peerId == peerId
                && (topicId == nil || topicId == 0 || record.topicId == topicId)
            if matches {
                if let path = record.mediaPath {
                    removedPaths.append(path)
                }
                indexRemoveLocked(record)
            }
            return matches
        }
        let remaining = memory
        // Bumped here rather than through schedulePersistLocked, which this path deliberately
        // skips — without it persistNow would see an unchanged generation and refuse to write.
        self.storeGeneration += 1
        lock.unlock()
        // User-initiated and rare — write through immediately so it survives a kill.
        persistNow()
        removeOrphanedAttachments(candidates: removedPaths, remaining: remaining)
        notifyChanged()
    }

    /// Delete durable copies that no surviving record references any more. Deliberately
    /// conservative: a file is only ever removed when it sits strictly inside our own
    /// Saved Attachments directory, compared by path components after standardizing, so a
    /// crafted or corrupted stored path cannot escape it (".." or a sibling directory whose
    /// name merely shares a prefix).
    private static func removeOrphanedAttachments(candidates: [String], remaining: [MessageSavingRecord]) {
        guard !candidates.isEmpty else { return }
        let stillReferenced = Set(remaining.compactMap { $0.mediaPath })
        let root = MessageSavingBridge.savedAttachmentsDirectory
        for path in Set(candidates) where !stillReferenced.contains(path) {
            guard isPath(path, strictlyInside: root) else {
                continue
            }
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
    }

    /// Whether `path` names something strictly below `root`.
    ///
    /// Compared by path component after standardizing, which is what makes the check safe: a
    /// prefix comparison on the raw string would accept a sibling directory whose name merely
    /// starts the same way ("…/Saved Attachments Backup"), and skipping standardization would
    /// accept a path escaping through "..". `root` itself is not inside itself, so a stored path
    /// equal to the directory can never delete the whole folder.
    ///
    /// Exposed for tests: this guard is the only thing standing between a corrupted stored path
    /// and `FileManager.removeItem`, so it is worth asserting directly rather than through the
    /// filesystem.
    public static func isPath(_ path: String, strictlyInside root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count > rootComponents.count else {
            return false
        }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }

    public static func applySettings(_ settings: ForkExtrasSettings) {
        let _ = MessageSavingBridge.settings.swap(MessageSavingBridgeSettings(
            saveDeleted: settings.saveDeletedMessages,
            saveEdits: settings.saveMessagesHistory,
            saveForBots: settings.saveForBots,
            saveMedia: settings.saveMedia,
            proactiveSaveMedia: settings.proactiveSaveMedia,
            deletedMark: settings.deletedMessageMark,
            editedMark: settings.editedMessageMark
        ))
    }

    /// Total retained snapshots (deleted + edited). Used by the Extras export/import UI.
    public static var recordCount: Int {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return memory.count
    }

    /// Encode the current store as a JSON array of `MessageSavingRecord` (AyuGram-style DB export).
    /// Records-only, no attachment bytes — see `exportBundle()` for a folder that also includes
    /// Saved Attachments.
    public static func exportJSONData() -> Data? {
        loadIfNeeded()
        lock.lock()
        let snapshot = memory
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    public enum ImportError: Error {
        case invalidData
    }

    /// Import a previously exported JSON array. When `replace` is true the store is wiped first;
    /// otherwise records are merged by `id` (duplicates skipped). Soft-capped at 5000.
    @discardableResult
    public static func importJSONData(_ data: Data, replace: Bool) -> Result<Int, ImportError> {
        guard let incoming = try? JSONDecoder().decode([MessageSavingRecord].self, from: data) else {
            return .failure(.invalidData)
        }
        loadIfNeeded()
        lock.lock()
        if replace {
            memory = []
            rebuildIndexesLocked()
        }
        var existingIds = Set(memory.map(\.id))
        var added = 0
        for record in incoming {
            if existingIds.contains(record.id) {
                continue
            }
            memory.append(record)
            indexAddLocked(record)
            existingIds.insert(record.id)
            added += 1
            if record.kind == .edited {
                enforceEditHistoryLimitLocked(for: record)
            }
        }
        if memory.count > 5000 {
            let overflow = memory.count - 5000
            for dropped in memory.prefix(overflow) {
                indexRemoveLocked(dropped)
            }
            memory.removeFirst(overflow)
        }
        if added > 0 || replace {
            schedulePersistLocked()
        }
        lock.unlock()
        if added > 0 || replace {
            notifyChanged()
        }
        return .success(added)
    }

    private static let bundleRecordsFileName = "records.json"
    private static let bundleAttachmentsFolderName = "Saved Attachments"

    /// Build a self-contained export folder — `records.json` + a copy of Saved Attachments
    /// (AyuGram DB backup parity: "zip or folder of MessageSaving JSON store + Saved
    /// Attachments"). Returned as a folder rather than a zip: Foundation has no built-in archive
    /// writer, and both AirDrop and Files "Save to Files" accept a folder directly (users who
    /// want an actual .zip can use Files' own "Compress" action afterwards).
    public static func exportBundle() -> URL? {
        guard let data = exportJSONData() else {
            return nil
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AyuGram Saved Messages", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        guard (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        do {
            try data.write(to: root.appendingPathComponent(bundleRecordsFileName), options: .atomic)
        } catch {
            return nil
        }
        let attachmentsSource = MessageSavingBridge.savedAttachmentsDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: attachmentsSource, includingPropertiesForKeys: nil), !contents.isEmpty {
            let attachmentsDest = root.appendingPathComponent(bundleAttachmentsFolderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: attachmentsDest, withIntermediateDirectories: true)
            for file in contents {
                try? FileManager.default.copyItem(at: file, to: attachmentsDest.appendingPathComponent(file.lastPathComponent))
            }
        }
        return root
    }

    /// Import either a bare `records.json` (simple export) or a folder produced by
    /// `exportBundle()` (`records.json` + `Saved Attachments/`). Attachments are merged by
    /// filename; a name already present locally is left untouched rather than overwritten.
    @discardableResult
    public static func importBundle(from url: URL, replace: Bool) -> Result<Int, ImportError> {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure(.invalidData)
        }
        let recordsURL: URL
        var attachmentsURL: URL?
        if isDirectory.boolValue {
            recordsURL = url.appendingPathComponent(bundleRecordsFileName)
            let candidate = url.appendingPathComponent(bundleAttachmentsFolderName, isDirectory: true)
            var candidateIsDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &candidateIsDirectory), candidateIsDirectory.boolValue {
                attachmentsURL = candidate
            }
        } else {
            recordsURL = url
        }
        guard let data = try? Data(contentsOf: recordsURL) else {
            return .failure(.invalidData)
        }
        let result = importJSONData(data, replace: replace)
        if case .success = result, let attachmentsURL, let files = try? FileManager.default.contentsOfDirectory(at: attachmentsURL, includingPropertiesForKeys: nil) {
            let dest = MessageSavingBridge.savedAttachmentsDirectory
            for file in files {
                let destFile = dest.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destFile.path) {
                    try? FileManager.default.copyItem(at: file, to: destFile)
                }
            }
        }
        return result
    }
}
