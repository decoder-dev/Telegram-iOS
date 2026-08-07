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

    /// Copy the best available local media file for `message`. Returns the destination path, or nil.
    static func copyIfAvailable(message: Message, mediaBox: MediaBox) -> String? {
        guard let source = sourcePath(message: message, mediaBox: mediaBox) else {
            return nil
        }
        let ext: String
        if let fileExtension = (source as NSString).pathExtension as String?, !fileExtension.isEmpty {
            ext = fileExtension
        } else {
            ext = "bin"
        }
        // Deterministic name so snapshot + convert-in-place share one copy (Android Saved Attachments).
        let name = "\(message.id.peerId.toInt64())_\(message.id.namespace)_\(message.id.id).\(ext)"
        let dest = directoryURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest.path
        }
        do {
            try FileManager.default.copyItem(atPath: source, toPath: dest.path)
            return dest.path
        } catch {
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
