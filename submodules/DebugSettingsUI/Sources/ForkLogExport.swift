import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import OverlayStatusController
import ZipArchive
import MessageUI

/// Packaging of the on-disk logs for export.
///
/// The point of this helper is that the export never exists in memory as a whole. The
/// straightforward version — append every log file to one `Data`, write it, zip it, read
/// the zip back — asks for two contiguous allocations the size of the entire export at
/// exactly the moment a tester is trying to report a problem. With the retention raised
/// for multi-day collection that is hundreds of megabytes, and iOS answers such a request
/// with a jetsam kill: the app dies during "send logs", which is the one operation that
/// has to survive.
///
/// Nothing here reads the export as a whole: the archive is built by hard-linking the log
/// files into a staging directory and letting `SSZipArchive` compress them from disk, the
/// finished archive is handed to the media box by moving the file rather than by reading
/// its bytes, and the one path that does concatenate (the short log, two files) streams a
/// chunk at a time. Packaging also runs off the main thread, since at this size it takes
/// long enough for the watchdog to notice.
enum ForkLogExport {
    private static let chunkSize: Int = 1 * 1024 * 1024

    /// Packaging runs here, never on the main thread: at the extended retention it is
    /// hundreds of megabytes of reading, deflating and writing, and the main-thread
    /// watchdog kills the app long before that finishes.
    private static let queue = Queue(name: "org.telegram.ForkLogExport", qos: .userInitiated)

    /// How the caller shows the packaging HUD. Nothing is shown when it is nil.
    typealias PresentController = (ViewController) -> Void

    /// An open output file that bytes are appended to, one bounded chunk per call.
    private final class Sink {
        private let fd: Int32

        init?(path: String) {
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
            if fd < 0 {
                return nil
            }
            self.fd = fd
        }

        deinit {
            close(self.fd)
        }

        func append(_ string: String) {
            self.append(Data(string.utf8))
        }

        func append(_ data: Data) {
            data.withUnsafeBytes { buffer -> Void in
                guard var pointer = buffer.baseAddress else {
                    return
                }
                var remaining = buffer.count
                while remaining > 0 {
                    let written = write(self.fd, pointer, remaining)
                    if written < 0 {
                        if errno == EINTR {
                            continue
                        }
                        return
                    }
                    if written == 0 {
                        return
                    }
                    pointer = pointer.advanced(by: written)
                    remaining -= written
                }
            }
        }

        /// Appends the contents of another file without ever holding more than one chunk
        /// of it. The source is mapped rather than read, so the pages stay clean and the
        /// kernel can evict them under pressure.
        func appendContents(ofFileAt path: String) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else {
                return
            }
            var offset = data.startIndex
            while offset < data.endIndex {
                let end = data.index(offset, offsetBy: ForkLogExport.chunkSize, limitedBy: data.endIndex) ?? data.endIndex
                self.append(data[offset ..< end])
                offset = end
            }
        }
    }

    /// Writes `logs` into a single text file at `path`, each preceded by its
    /// `------ File: <name> ------` banner and separated by a blank line.
    static func writeConcatenatedLogs(_ logs: [(String, String)], additionalInfo: String = "", to path: String) {
        guard let sink = Sink(path: path) else {
            return
        }

        var isFirst = true
        for (name, logPath) in logs {
            if !isFirst {
                sink.append("\n\n")
            }
            isFirst = false

            sink.append("------ File: \(name) ------\n")
            sink.appendContents(ofFileAt: logPath)
        }

        if !additionalInfo.isEmpty {
            sink.append("------ Additional Info ------\n")
            sink.append(additionalInfo)
        }
    }

    /// Enqueues a file that already exists on disk as a document.
    ///
    /// Ownership of `file` passes to the media box, which *moves* it in — so the caller
    /// must not dispose it, and must not expect it to still be there afterwards.
    static func enqueueFile(_ file: EngineTempBox.File, fileName: String, mimeType: String, to peerId: EnginePeer.Id, context: AccountContext) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let fileSize = (attributes?[.size] as? NSNumber)?.int64Value, fileSize > 0 else {
            return
        }

        let id = Int64.random(in: Int64.min ... Int64.max)
        let fileResource = LocalFileMediaResource(fileId: id, size: fileSize, isSecretRelated: false)
        context.engine.resources.moveResourceData(id: EngineMediaResource.Id(fileResource.id), fromTempPath: file.path)

        let media = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: fileResource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: fileSize, attributes: [.FileName(fileName: fileName)], alternativeRepresentations: [])
        let message: EnqueueMessage = .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])

        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [message]).start()
    }

    /// Compresses the log files into one archive, each group in its own subdirectory. The
    /// caller owns the result: dispose it, or hand it to `enqueueFile`, which takes
    /// ownership.
    ///
    /// The files are hard-linked into a staging directory rather than concatenated into
    /// one text, so the export needs no second copy of the logs on disk — at the extended
    /// retention that would be hundreds of megabytes, on a device that is quite possibly
    /// short of space already. Every entry keeps its own timestamped file name, which is
    /// what the `------ File: … ------` banners of the old single-file export stood in for,
    /// and the subdirectories keep same-named files from different processes apart.
    static func makeArchive(_ groups: [(type: String, logs: [(String, String)])], additionalInfo: String = "") -> EngineTempBox.File {
        let staging = EngineTempBox.shared.tempDirectory()

        for (type, logs) in groups {
            let directory = type.isEmpty ? staging.path : staging.path + "/" + type
            let _ = try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)

            for (name, path) in logs {
                let destination = directory + "/" + name.replacingOccurrences(of: "/", with: "_")
                do {
                    try FileManager.default.linkItem(atPath: path, toPath: destination)
                } catch {
                    // A hard link only works within one volume; copying is the fallback.
                    let _ = try? FileManager.default.copyItem(atPath: path, toPath: destination)
                }
            }
        }

        if !additionalInfo.isEmpty {
            let _ = try? additionalInfo.write(toFile: staging.path + "/AdditionalInfo.txt", atomically: true, encoding: .utf8)
        }

        let tempZip = EngineTempBox.shared.tempFile(fileName: "destination.zip")
        SSZipArchive.createZipFile(atPath: tempZip.path, withContentsOfDirectory: staging.path)
        EngineTempBox.shared.dispose(staging)

        return tempZip
    }

    /// Runs `perform` off the main thread behind a HUD and delivers the result back on it.
    /// Must be called from the main queue.
    private static func package(sharedContext: SharedAccountContext, presentProgress: PresentController?, _ perform: @escaping () -> EngineTempBox.File, completion: @escaping (EngineTempBox.File) -> Void) {
        var progress: ViewController?
        if let presentProgress = presentProgress {
            let presentationData = sharedContext.currentPresentationData.with { $0 }
            let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
            presentProgress(controller)
            progress = controller
        }

        self.queue.async {
            let file = perform()
            Queue.mainQueue().async {
                progress?.dismiss()
                completion(file)
            }
        }
    }

    /// Packages `logs` and sends them to `peerId`: an archive when `compressed`, a single
    /// concatenated text file otherwise.
    static func sendLogs(_ logs: [(String, String)], additionalInfo: String = "", compressed: Bool, fileName: String, mimeType: String = "application/text", to peerId: EnginePeer.Id, context: AccountContext, presentProgress: PresentController? = nil) {
        self.package(sharedContext: context.sharedContext, presentProgress: presentProgress, {
            if compressed {
                return self.makeArchive([(type: "", logs: logs)], additionalInfo: additionalInfo)
            } else {
                let tempSource = EngineTempBox.shared.tempFile(fileName: "Log.txt")
                self.writeConcatenatedLogs(logs, additionalInfo: additionalInfo, to: tempSource.path)
                return tempSource
            }
        }, completion: { file in
            self.enqueueFile(file, fileName: fileName, mimeType: mimeType, to: peerId, context: context)
        })
    }

    /// Same, but each group becomes its own subdirectory inside one archive.
    static func sendLogGroups(_ groups: [(type: String, logs: [(String, String)])], fileName: String, mimeType: String = "application/zip", to peerId: EnginePeer.Id, context: AccountContext, presentProgress: PresentController? = nil) {
        self.package(sharedContext: context.sharedContext, presentProgress: presentProgress, {
            return self.makeArchive(groups)
        }, completion: { file in
            self.enqueueFile(file, fileName: fileName, mimeType: mimeType, to: peerId, context: context)
        })
    }

    /// Zips the log files as they are — one entry per file, no concatenation — and hands
    /// the archive to `completion`. The caller owns the result and must dispose it.
    static func saveArchive(_ logs: [(String, String)], fileName: String, sharedContext: SharedAccountContext, presentProgress: PresentController? = nil, completion: @escaping (EngineTempBox.File) -> Void) {
        self.package(sharedContext: sharedContext, presentProgress: presentProgress, {
            let tempZip = EngineTempBox.shared.tempFile(fileName: fileName)
            SSZipArchive.createZipFile(atPath: tempZip.path, withFilesAtPaths: logs.map { $0.1 })
            return tempZip
        }, completion: completion)
    }

    /// Builds a mail draft with the logs attached as a single archive and hands it to
    /// `present`. One attachment rather than one per file: the mail composer holds every
    /// attachment in memory, and with the extended retention there are hundreds of files
    /// behind a "send logs" tap.
    static func composeMail(_ logs: [(String, String)], fileName: String, subject: String = "Telegram Logs", delegate: MFMailComposeViewControllerDelegate?, sharedContext: SharedAccountContext, presentProgress: PresentController? = nil, present: @escaping (MFMailComposeViewController) -> Void) {
        self.package(sharedContext: sharedContext, presentProgress: presentProgress, {
            return self.makeArchive([(type: "", logs: logs)])
        }, completion: { archive in
            let composeController = MFMailComposeViewController()
            composeController.mailComposeDelegate = delegate
            composeController.setSubject(subject)
            // Mapped, so the attachment does not cost dirty memory. Unlinking the file
            // afterwards is safe while the mapping is alive.
            if let data = try? Data(contentsOf: URL(fileURLWithPath: archive.path), options: .mappedIfSafe) {
                composeController.addAttachmentData(data, mimeType: "application/zip", fileName: fileName)
            }
            EngineTempBox.shared.dispose(archive)

            present(composeController)
        })
    }
}
