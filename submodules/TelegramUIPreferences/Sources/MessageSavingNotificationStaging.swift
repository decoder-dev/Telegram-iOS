import Foundation
import TelegramCore

/// Hand-off between the notification extension and the app for Save Messages from Notifications.
///
/// The extension polls the difference and applies delete pushes into the shared Postbox. It has neither the app's
/// settings nor its store, so until now every deletion it saw was a hard delete, and a message removed before the app
/// was opened was gone for good. With the switch on, the extension keeps such deletions as small JSON files in the
/// app group, and the app folds those into MessageSavingStore when it starts or comes back to the foreground.
///
/// Files keep both processes free of locks: the extension writes each batch atomically under a name of its own, and
/// the app removes a file once it has merged it. A history clear can delete a couple of thousand messages in one
/// transaction, so the records are collected in memory and written as one file per batch, not one per message.
public enum MessageSavingNotificationStaging {
    /// How long the text of a push the extension could not fetch is kept in case a delete push for it follows.
    private static let pushedMessageLifetime: TimeInterval = 7 * 24 * 60 * 60

    private static let lock = NSLock()
    private static var unwrittenRecords: [MessageSavingRecord] = []
    private static var preparedRootPath: String?

    private static func directory(rootPath: String, name: String) -> URL {
        return URL(fileURLWithPath: rootPath).appendingPathComponent("message-saving", isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    /// Creates the folders the extension writes to, once per process.
    private static func prepareDirectories(rootPath: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.preparedRootPath == rootPath {
            return
        }
        var base = URL(fileURLWithPath: rootPath).appendingPathComponent("message-saving", isDirectory: true)
        for name in ["staged", "pending"] {
            try? FileManager.default.createDirectory(at: base.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
        // Message text stays out of iCloud and computer backups, as the app's own store does.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        self.preparedRootPath = rootPath
    }

    /// Called by the extension for every push, before it touches Postbox. Mirrors the user's switches into
    /// MessageSavingBridge, so the delete push handler and replayed difference deletions keep the message (in the chat
    /// as deleted, as the app does) instead of removing it. With the switch off the extension behaves as it always did.
    public static func configureExtension(rootPath: String) {
        guard ForkExtrasNotificationBridge.savesMessagesFromNotifications else {
            let _ = MessageSavingBridge.settings.swap(.disabled)
            let _ = MessageSavingBridge.append.swap(nil)
            return
        }
        // No attachment copies and no edit history here: Saved Attachments lives in the app's own container, and the
        // extension has a tight memory budget.
        let _ = MessageSavingBridge.settings.swap(MessageSavingBridgeSettings(
            saveDeleted: true,
            saveEdits: false,
            saveForBots: ForkExtrasNotificationBridge.saveForBots
        ))
        self.prepareDirectories(rootPath: rootPath)
        let _ = MessageSavingBridge.append.swap({ record in
            if record.kind == .deleted {
                self.stage(record)
            }
        })
    }

    /// The bridge hands records over one at a time from inside a Postbox transaction. They are held here and written
    /// together: right after a delete push's transaction, when the extension hands over the notification, or a moment
    /// after the first one arrives, whichever comes first.
    private static func stage(_ record: MessageSavingRecord) {
        self.lock.lock()
        let startsBatch = self.unwrittenRecords.isEmpty
        self.unwrittenRecords.append(record)
        self.lock.unlock()
        if startsBatch {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: {
                self.writeStagedRecords()
            })
        }
    }

    /// Writes whatever has been staged as one file. Synchronous, since the extension can be suspended as soon as it
    /// hands over the notification. Does nothing when there is nothing to write, so it is safe to call on every push.
    public static func writeStagedRecords() {
        self.lock.lock()
        let records = self.unwrittenRecords
        self.unwrittenRecords = []
        let rootPath = self.preparedRootPath
        self.lock.unlock()
        guard !records.isEmpty, let rootPath, let data = try? JSONEncoder().encode(records) else {
            return
        }
        let url = self.directory(rootPath: rootPath, name: "staged").appendingPathComponent("batch_\(UUID().uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    private struct PushedMessage: Codable {
        let accountPeerId: Int64
        let peerId: Int64
        let messageId: Int32
        let date: Int32
        let authorName: String
        let text: String
    }

    private static func pushedFileName(accountPeerId: EnginePeer.Id, messageId: EngineMessage.Id) -> String {
        return "\(accountPeerId.toInt64())_\(messageId.peerId.toInt64())_\(messageId.id).json"
    }

    /// Keeps what a push said about a message the extension's poll did not manage to fetch (offline, or out of time).
    /// Normally the poll stores the message in Postbox and this is never needed.
    public static func rememberPushedMessage(rootPath: String, accountPeerId: EnginePeer.Id, messageId: EngineMessage.Id, authorName: String, text: String) {
        guard ForkExtrasNotificationBridge.savesMessagesFromNotifications, messageId.namespace == Namespaces.Message.Cloud else {
            return
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return
        }
        self.prepareDirectories(rootPath: rootPath)
        let pendingDirectory = self.directory(rootPath: rootPath, name: "pending")
        self.removeExpiredPushedMessages(rootPath: rootPath)
        let pushed = PushedMessage(
            accountPeerId: accountPeerId.toInt64(),
            peerId: messageId.peerId.toInt64(),
            messageId: messageId.id,
            date: Int32(Date().timeIntervalSince1970),
            authorName: authorName,
            text: text
        )
        if let data = try? JSONEncoder().encode(pushed) {
            try? data.write(to: pendingDirectory.appendingPathComponent(pushedFileName(accountPeerId: accountPeerId, messageId: messageId)), options: .atomic)
        }
    }

    /// A delete push arrived. Messages it names that Postbox has no copy of are saved from what their push said; the
    /// rest were kept through MessageSavingBridge already. Either way their pushes are forgotten. The caller writes
    /// the batch with `writeStagedRecords()` once the deletion itself has run.
    public static func saveDeletedPushedMessages(rootPath: String, accountPeerId: EnginePeer.Id, ids: [EngineMessage.Id], missingIds: Set<EngineMessage.Id>) {
        guard ForkExtrasNotificationBridge.savesMessagesFromNotifications else {
            return
        }
        self.prepareDirectories(rootPath: rootPath)
        let pendingDirectory = self.directory(rootPath: rootPath, name: "pending")
        let now = Int32(Date().timeIntervalSince1970)
        for id in ids {
            let url = pendingDirectory.appendingPathComponent(pushedFileName(accountPeerId: accountPeerId, messageId: id))
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
            guard missingIds.contains(id), let pushed = try? JSONDecoder().decode(PushedMessage.self, from: data) else {
                continue
            }
            self.stage(MessageSavingRecord(
                id: UUID().uuidString,
                accountPeerId: pushed.accountPeerId,
                peerId: pushed.peerId,
                messageId: pushed.messageId,
                namespace: Namespaces.Message.Cloud,
                date: pushed.date,
                authorId: nil,
                authorName: pushed.authorName,
                text: pushed.text,
                kind: .deleted,
                savedAt: now,
                topicId: 0
            ))
        }
    }

    /// Pushed text is plaintext on disk, so it does not outlive the chance of a delete push for it. Run by the
    /// extension on every remembered push and by the app on every merge, so it expires even when no push comes.
    public static func removeExpiredPushedMessages(rootPath: String) {
        let cutoff = Date().addingTimeInterval(-self.pushedMessageLifetime)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: self.directory(rootPath: rootPath, name: "pending"), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for url in urls {
            if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// The app side, for when Save Messages from Notifications or Save Deleted Messages is off: nothing the extension
    /// kept is wanted any more. Only the files go; the folders stay, since an extension process that is still alive
    /// has already created them and will write there again if the switch comes back on.
    public static func removeAll(rootPath: String) {
        for name in ["staged", "pending"] {
            guard let urls = try? FileManager.default.contentsOfDirectory(at: self.directory(rootPath: rootPath, name: name), includingPropertiesForKeys: nil, options: []) else {
                continue
            }
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// The app side: every file the extension staged, with its records. A batch file holds an array; files from
    /// builds that wrote one record per message hold a single record. A file that decodes as neither is removed here,
    /// since nothing will ever read it.
    public static func stagedBatches(rootPath: String) -> [(URL, [MessageSavingRecord])] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: self.directory(rootPath: rootPath, name: "staged"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        let decoder = JSONDecoder()
        var result: [(URL, [MessageSavingRecord])] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            if let records = try? decoder.decode([MessageSavingRecord].self, from: data) {
                result.append((url, records))
            } else if let record = try? decoder.decode(MessageSavingRecord.self, from: data) {
                result.append((url, [record]))
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return result
    }
}
