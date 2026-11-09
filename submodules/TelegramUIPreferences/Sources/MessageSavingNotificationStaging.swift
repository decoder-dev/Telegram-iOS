import Foundation
import TelegramCore

/// Hand-off between the notification extension and the app for Save Messages from Notifications.
///
/// The extension polls the difference and applies delete pushes into the shared Postbox. It has neither the app's
/// settings nor its store, so until now every deletion it saw was a hard delete, and a message removed before the app
/// was opened was gone for good. With the switch on, the extension keeps such a deletion as one small JSON file in the
/// app group, and the app folds those into MessageSavingStore when it starts or comes back to the foreground.
///
/// One file per message keeps both processes free of locks: the extension writes atomically, a repeat for the same
/// message overwrites the same file, and the app removes each file once it has merged it.
public enum MessageSavingNotificationStaging {
    /// How long the text of a push the extension could not fetch is kept in case a delete push for it follows.
    private static let pushedMessageLifetime: TimeInterval = 7 * 24 * 60 * 60

    private static func directory(rootPath: String, name: String) -> URL {
        var base = URL(fileURLWithPath: rootPath).appendingPathComponent("message-saving", isDirectory: true)
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Message text stays out of iCloud and computer backups, as the app's own store does.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
        return url
    }

    private static func stagedFileName(accountPeerId: Int64, peerId: Int64, namespace: Int32, messageId: Int32) -> String {
        return "\(accountPeerId)_\(peerId)_\(namespace)_\(messageId).json"
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
        let stagedDirectory = self.directory(rootPath: rootPath, name: "staged")
        let _ = MessageSavingBridge.append.swap({ record in
            guard record.kind == .deleted, let data = try? JSONEncoder().encode(record) else {
                return
            }
            // Written synchronously: the extension can be suspended as soon as it hands over the notification.
            let name = stagedFileName(accountPeerId: record.accountPeerId, peerId: record.peerId, namespace: record.namespace, messageId: record.messageId)
            try? data.write(to: stagedDirectory.appendingPathComponent(name), options: .atomic)
        })
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
        let pendingDirectory = self.directory(rootPath: rootPath, name: "pending")
        self.removeExpiredPushedMessages(in: pendingDirectory)
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
    /// rest were kept through MessageSavingBridge already. Either way their pushes are forgotten.
    public static func saveDeletedPushedMessages(rootPath: String, accountPeerId: EnginePeer.Id, ids: [EngineMessage.Id], missingIds: Set<EngineMessage.Id>) {
        guard ForkExtrasNotificationBridge.savesMessagesFromNotifications else {
            return
        }
        let pendingDirectory = self.directory(rootPath: rootPath, name: "pending")
        let stagedDirectory = self.directory(rootPath: rootPath, name: "staged")
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
            let record = MessageSavingRecord(
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
            )
            if let recordData = try? JSONEncoder().encode(record) {
                let name = stagedFileName(accountPeerId: record.accountPeerId, peerId: record.peerId, namespace: record.namespace, messageId: record.messageId)
                try? recordData.write(to: stagedDirectory.appendingPathComponent(name), options: .atomic)
            }
        }
    }

    private static func removeExpiredPushedMessages(in directory: URL) {
        let cutoff = Date().addingTimeInterval(-self.pushedMessageLifetime)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        for url in urls {
            if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// The app side: every record the extension staged, with the file it came from. A file that no longer decodes is
    /// removed here, since nothing will ever read it.
    public static func stagedRecords(rootPath: String) -> [(URL, MessageSavingRecord)] {
        let stagedDirectory = self.directory(rootPath: rootPath, name: "staged")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: stagedDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var result: [(URL, MessageSavingRecord)] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(MessageSavingRecord.self, from: data) {
                result.append((url, record))
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return result
    }
}
