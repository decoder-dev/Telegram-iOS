import Foundation
import Postbox

/// AyuGram Android parity: copy attachments into a durable folder outside the Telegram cache
/// (`Download/AyuGram/Saved Attachments` on Android → Application Support here).
enum MessageSavingAttachments {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("MessageSaving", isDirectory: true)
            .appendingPathComponent("Saved Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Stable across launches, unlike String.hashValue which is per-process seeded.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Each account has its own MediaBox directory, so this scopes filenames per account
    /// without having to thread accountPeerId through every delete path.
    private static func accountScope(mediaBox: MediaBox) -> String {
        return String(stableHash(mediaBox.basePath), radix: 36)
    }

    private static func baseName(peerId: Int64, namespace: Int32, messageId: Int32, mediaBox: MediaBox) -> String {
        return "\(accountScope(mediaBox: mediaBox))_\(peerId)_\(namespace)_\(messageId)"
    }

    /// Pre-account-scoping name. Still read so previously saved files keep working.
    private static func legacyBaseName(peerId: Int64, namespace: Int32, messageId: Int32) -> String {
        return "\(peerId)_\(namespace)_\(messageId)"
    }

    private static func firstFile(withBase base: String, in directory: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return nil
        }
        let prefix = base + "."
        for entry in entries where entry.hasPrefix(prefix) {
            return directory.appendingPathComponent(entry).path
        }
        return nil
    }

    /// A durable copy already on disk for this message, whatever extension it was saved with.
    /// Id-based so it also works after a restart, when only a stored record (not a Message) is
    /// at hand.
    static func existingCopyPath(peerId: Int64, namespace: Int32, messageId: Int32, mediaBox: MediaBox) -> String? {
        let directory = self.directoryURL
        if let path = firstFile(withBase: baseName(peerId: peerId, namespace: namespace, messageId: messageId, mediaBox: mediaBox), in: directory) {
            return path
        }
        return firstFile(withBase: legacyBaseName(peerId: peerId, namespace: namespace, messageId: messageId), in: directory)
    }

    static func existingCopyPath(message: Message, mediaBox: MediaBox) -> String? {
        return existingCopyPath(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id, mediaBox: mediaBox)
    }

    /// Copy the best available local media file for `message`. Returns the destination path, or nil.
    static func copyIfAvailable(message: Message, mediaBox: MediaBox) -> String? {
        // Check the durable copy BEFORE asking MediaBox for a source: once the Telegram cache is
        // cleared, completedResourcePath returns nil even though our own saved file is still
        // there, which used to make an already-saved attachment look missing.
        if let existing = existingCopyPath(message: message, mediaBox: mediaBox) {
            return existing
        }
        guard let source = sourcePath(message: message, mediaBox: mediaBox) else {
            return nil
        }
        let ext: String
        let sourceExtension = (source as NSString).pathExtension
        if !sourceExtension.isEmpty {
            ext = sourceExtension
        } else {
            ext = "bin"
        }
        let dest = directoryURL.appendingPathComponent("\(baseName(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id, mediaBox: mediaBox)).\(ext)")
        do {
            try FileManager.default.copyItem(atPath: source, toPath: dest.path)
            return dest.path
        } catch {
            // Lost a race with a concurrent copy of the same message — that is still success.
            if FileManager.default.fileExists(atPath: dest.path) {
                return dest.path
            }
            return nil
        }
    }

    private static func sourcePath(message: Message, mediaBox: MediaBox) -> String? {
        for media in message.media {
            if let image = media as? TelegramMediaImage {
                let reps = image.representations.sorted { ($0.dimensions.width * $0.dimensions.height) > ($1.dimensions.width * $1.dimensions.height) }
                for rep in reps {
                    if let path = mediaBox.completedResourcePath(rep.resource) {
                        return path
                    }
                }
            } else if let file = media as? TelegramMediaFile {
                if let path = mediaBox.completedResourcePath(file.resource, pathExtension: file.fileName.flatMap { ($0 as NSString).pathExtension }) {
                    return path
                }
                if let path = mediaBox.completedResourcePath(file.resource) {
                    return path
                }
                for rep in file.previewRepresentations {
                    if let path = mediaBox.completedResourcePath(rep.resource) {
                        return path
                    }
                }
            }
        }
        return nil
    }
}
