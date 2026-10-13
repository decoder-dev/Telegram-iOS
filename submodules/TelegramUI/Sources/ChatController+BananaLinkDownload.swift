import Foundation
import UIKit
import SwiftSignalKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import UndoUI
import ChatPresentationInterfaceState
import TelegramUIPreferences
import BananaLinkDownloader

/// `UndoOverlayController.tag` of every link-download toast, so a new one can replace the old one.
private let bananaLinkDownloadToastTag = "bananagram.linkDownload"

/// Bottom toast of one link download: progress ring, "4,2 МБ из 9,8 МБ" and «Отмена». Re-rendered four times a
/// second, which also keeps UndoUI's `.progress` toast from timing out while the job runs.
private final class BananaLinkDownloadToast {
    private let link: BananaLinkDownloadLink
    private let presentationData: PresentationData
    private let russian = ForkPresentationLanguage.prefersRussianStrings
    weak var controller: UndoOverlayController?
    private var status: BananaLinkDownloadJob.Status?
    private var timer: SwiftSignalKit.Timer?

    init(link: BananaLinkDownloadLink, presentationData: PresentationData) {
        self.link = link
        self.presentationData = presentationData
    }

    var content: UndoOverlayContent {
        return .progress(progress: self.progressValue, title: self.title, text: self.text, undoText: russian ? "Отмена" : "Cancel")
    }

    func start() {
        let timer = SwiftSignalKit.Timer(timeout: 0.25, repeat: true, completion: { [weak self] in
            self?.render()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }

    func update(_ status: BananaLinkDownloadJob.Status) {
        self.status = status
    }

    func finish() {
        self.timer?.invalidate()
        self.timer = nil
        self.controller?.dismiss()
    }

    private func render() {
        guard let controller = self.controller else {
            self.timer?.invalidate()
            self.timer = nil
            return
        }
        controller.content = self.content
    }

    private var title: String {
        switch self.link {
        case .youtubeShorts:
            return russian ? "Скачиваю Shorts" : "Downloading Shorts"
        case .tiktok:
            return self.status?.kind == .photos ? (russian ? "Скачиваю фото из TikTok" : "Downloading photos from TikTok") : (russian ? "Скачиваю видео из TikTok" : "Downloading a video from TikTok")
        }
    }

    private var text: String {
        guard let stage = self.status?.stage else {
            return russian ? "Получаю ссылку…" : "Getting the link…"
        }
        switch stage {
        case .resolving:
            return russian ? "Получаю ссылку…" : "Getting the link…"
        case let .downloading(received, total):
            let formatting = DataSizeStringFormatting(presentationData: self.presentationData)
            if let total {
                return "\(dataSizeString(received, forceDecimal: true, formatting: formatting)) \(russian ? "из" : "of") \(dataSizeString(total, forceDecimal: true, formatting: formatting))"
            } else {
                return dataSizeString(received, forceDecimal: true, formatting: formatting)
            }
        case .processing:
            if case .youtubeShorts = self.link {
                return russian ? "Склеиваю видео…" : "Merging the video…"
            } else {
                return russian ? "Обрабатываю…" : "Processing…"
            }
        }
    }

    private var progressValue: CGFloat {
        guard let stage = self.status?.stage else {
            return 0.0
        }
        switch stage {
        case .resolving:
            return 0.0
        case let .downloading(received, total):
            guard let total, total > 0 else {
                return 0.0
            }
            return CGFloat(min(1.0, Double(received) / Double(total)))
        case .processing:
            return 1.0
        }
    }
}

/// Keeps the app running for a while (iOS gives about 30 s) when the user switches apps right after
/// sending, so the download can finish. On expiry the job is cancelled, which sends the link instead.
private final class BananaLinkDownloadBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin(expiration: @escaping () -> Void) {
        self.identifier = UIApplication.shared.beginBackgroundTask(withName: "BananaLinkDownload", expirationHandler: { [weak self] in
            expiration()
            self?.end()
        })
    }

    func end() {
        if self.identifier != .invalid {
            UIApplication.shared.endBackgroundTask(self.identifier)
            self.identifier = .invalid
        }
    }
}

extension ChatControllerImpl {
    /// Composer send hook. When the message is a bare TikTok / YouTube Shorts link and downloads are enabled,
    /// downloads the media and sends it instead of the link; the link itself goes out if the download fails
    /// or is cancelled. Returns false when the message should be sent as usual.
    func bananaInterceptLinkSend(_ messages: [EnqueueMessage], peerId: EnginePeer.Id) -> Bool {
        guard messages.count == 1, case let .message(text, _, inlineStickers, mediaReference, _, _, _, _, _, _) = messages[0], inlineStickers.isEmpty else {
            return false
        }
        if let mediaReference, !(mediaReference.media is TelegramMediaWebpage) {
            return false
        }
        guard let link = BananaLinkDownloadLink.parse(text) else {
            return false
        }
        switch link {
        case .tiktok:
            if !ForkExtrasHotFlags.downloadTikTok {
                return false
            }
        case .youtubeShorts:
            if !ForkExtrasHotFlags.downloadYouTubeShorts {
                return false
            }
        }
        if peerId.namespace == Namespaces.Peer.SecretChat || self.presentationInterfaceState.sendPaidMessageStars != nil || self.bananaIsMediaBanned(for: link) {
            return false
        }

        let template = messages[0]
        let context = self.context
        let signCaption = ForkExtrasHotFlags.signDownloadedMedia
        let isSlowmode = (self.presentationInterfaceState.renderedPeer?.peer as? TelegramChannel)?.isRestrictedBySlowmode ?? false

        self.bananaFlushPendingSendAction()
        self.updateChatPresentationInterfaceState(interactive: true, { $0.updatedShowCommands(false) })

        let job = BananaLinkDownloadJob(link: link, maxPhotos: isSlowmode ? 10 : nil)
        let toast = BananaLinkDownloadToast(link: link, presentationData: self.presentationData)
        let controller = UndoOverlayController(presentationData: self.presentationData, content: toast.content, elevatedLayout: false, position: .bottom, action: { [weak job] action in
            if case .undo = action {
                job?.cancel()
            }
            return false
        })
        toast.controller = controller
        self.bananaPresentLinkDownloadToast(controller)
        toast.start()

        let backgroundTask = BananaLinkDownloadBackgroundTask()
        backgroundTask.begin(expiration: { [weak job] in
            job?.cancel()
        })
        job.start(status: { status in
            toast.update(status)
        }, completion: { [weak self] result in
            toast.finish()
            let outgoing: [EnqueueMessage]
            switch result {
            case let .success(output):
                let media = bananaLinkDownloadMessages(output: output, template: template, link: link, sign: signCaption, context: context)
                outgoing = media.isEmpty ? [template] : media
            case let .failure(error):
                outgoing = [template]
                if error != .cancelled {
                    self?.bananaShowLinkDownloadError(error)
                }
            }
            let _ = (enqueueMessages(account: context.account, peerId: peerId, messages: outgoing)
            |> deliverOnMainQueue).startStandalone(next: { [weak self] _ in
                backgroundTask.end()
                guard let self else {
                    return
                }
                if self.presentationInterfaceState.subject != .scheduledMessages {
                    self.chatDisplayNode.historyNode.scrollToEndOfHistory()
                }
            })
        })
        return true
    }

    /// Media bans of groups and supergroups (admins are never banned). TikTok posts may turn out to be
    /// photos, so both kinds must be allowed for them.
    private func bananaIsMediaBanned(for link: BananaLinkDownloadLink) -> Bool {
        let rights: [TelegramChatBannedRightsFlags]
        switch link {
        case .tiktok:
            rights = [.banSendVideos, .banSendPhotos]
        case .youtubeShorts:
            rights = [.banSendVideos]
        }
        let peer = self.presentationInterfaceState.renderedPeer?.peer
        for right in rights {
            if let channel = peer as? TelegramChannel, channel.hasBannedPermission(right) != nil {
                return true
            }
            if let group = peer as? TelegramGroup, group.hasBannedPermission(right) {
                return true
            }
        }
        return false
    }

    /// The composer clears itself when the sent message shows up in the history. Nothing shows up yet, so
    /// run that action now (the same flush the scheduled-messages branch does) and drop the pending
    /// "text flies into the bubble" transition.
    private func bananaFlushPendingSendAction() {
        if let layoutActionOnViewTransitionAction = self.layoutActionOnViewTransitionAction {
            self.layoutActionOnViewTransitionAction = nil
            self.chatDisplayNode.historyNode.layoutActionOnViewTransition = nil
            layoutActionOnViewTransitionAction()
        }
        self.chatDisplayNode.messageTransitionNode.add(grouped: [])
    }

    private func bananaShowLinkDownloadError(_ error: BananaLinkDownloadError) {
        var reason = error.localizedReason(russian: ForkPresentationLanguage.prefersRussianStrings)
        if reason.hasSuffix(".") {
            reason.removeLast()
        }
        self.bananaPresentLinkDownloadToast(UndoOverlayController(presentationData: self.presentationData, content: .info(title: ForkPresentationLanguage.prefersRussianStrings ? "Не удалось скачать" : "Couldn’t download", text: ForkPresentationLanguage.prefersRussianStrings ? "\(reason). Отправил ссылку." : "\(reason). Sent the link.", timeout: 5.0, customUndoText: nil), elevatedLayout: false, position: .bottom, action: { _ in
            return false
        }))
    }

    /// One link-download toast at a time: an older one is closed, its job keeps running and still sends.
    /// Other features' undo toasts are left alone.
    private func bananaPresentLinkDownloadToast(_ controller: UndoOverlayController) {
        self.forEachController({ current in
            if let current = current as? UndoOverlayController, (current.tag as? String) == bananaLinkDownloadToastTag {
                current.dismiss()
            }
            return true
        })
        controller.tag = bananaLinkDownloadToastTag
        self.present(controller, in: .current)
    }
}

/// Media messages built from the transformed link message: reply, thread, silent, schedule, send-as and
/// the other attributes are kept; text entities and link-preview attributes are dropped; the message
/// effect stays on the first message only. Photos go in albums of ten.
private func bananaLinkDownloadMessages(output: BananaLinkDownloadJob.Output, template: EnqueueMessage, link: BananaLinkDownloadLink, sign: Bool, context: AccountContext) -> [EnqueueMessage] {
    guard case let .message(_, attributes, _, _, threadId, replyToMessageId, replyToStoryId, _, _, _) = template else {
        return []
    }
    let firstAttributes = attributes.filter { attribute in
        return !(attribute is TextEntitiesMessageAttribute) && !(attribute is WebpagePreviewMessageAttribute) && !(attribute is OutgoingContentInfoMessageAttribute)
    }
    let otherAttributes = firstAttributes.filter { attribute in
        return !(attribute is EffectMessageAttribute)
    }
    let media: [AnyMediaReference]
    switch output {
    case let .video(video):
        media = [AnyMediaReference.standalone(media: bananaLinkDownloadVideoFile(video, context: context))]
    case let .photos(photos):
        media = photos.map { AnyMediaReference.standalone(media: bananaLinkDownloadImage($0)) }
    }
    let caption = sign ? bananaLinkDownloadCaption(for: link) : nil
    var result: [EnqueueMessage] = []
    var groupingKey: Int64?
    for (index, mediaReference) in media.enumerated() {
        if media.count > 1 && index % 10 == 0 {
            groupingKey = Int64.random(in: Int64.min ... Int64.max)
        }
        var messageAttributes = index == 0 ? firstAttributes : otherAttributes
        var text = ""
        if index == 0, let caption {
            text = caption.text
            messageAttributes.append(TextEntitiesMessageAttribute(entities: caption.entities))
        }
        result.append(.message(text: text, attributes: messageAttributes, inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: media.count > 1 ? groupingKey : nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
    }
    return result
}

/// «Скачано с TikTok» / «Скачано с YouTube», the service name linking to the original post.
private func bananaLinkDownloadCaption(for link: BananaLinkDownloadLink) -> (text: String, entities: [MessageTextEntity]) {
    let service: String
    switch link {
    case .tiktok:
        service = "TikTok"
    case .youtubeShorts:
        service = "YouTube"
    }
    let prefix = ForkPresentationLanguage.prefersRussianStrings ? "Скачано с " : "Downloaded from "
    let start = (prefix as NSString).length
    let entity = MessageTextEntity(range: start ..< start + (service as NSString).length, type: .TextUrl(url: link.url.absoluteString))
    return (prefix + service, [entity])
}

/// The MP4 is referenced in place: Telegram moves it into its cache on upload (no copy, no main-thread I/O).
private func bananaLinkDownloadVideoFile(_ video: BananaLinkDownloadJob.Video, context: AccountContext) -> TelegramMediaFile {
    let resource = LocalFileReferenceMediaResource(localFilePath: video.fileURL.path, randomId: Int64.random(in: Int64.min ... Int64.max), isUniquelyReferencedTemporaryFile: true, size: video.fileSize)
    var previewRepresentations: [TelegramMediaImageRepresentation] = []
    if let thumbnail = video.thumbnail {
        let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: Int64(thumbnail.data.count))
        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnail.data)
        previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: Int32(thumbnail.width), height: Int32(thumbnail.height)), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil))
    }
    let dimensions = PixelDimensions(width: Int32(video.width), height: Int32(video.height))
    return TelegramMediaFile(
        fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)),
        partialReference: nil,
        resource: resource,
        previewRepresentations: previewRepresentations,
        videoThumbnails: [],
        immediateThumbnailData: nil,
        mimeType: "video/mp4",
        size: video.fileSize,
        attributes: [.FileName(fileName: video.fileName), .Video(duration: video.duration, size: dimensions, flags: [.supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil)],
        alternativeRepresentations: []
    )
}

/// Same as the stock media picker (LegacyMediaPickers): the JPEG is referenced from disk.
private func bananaLinkDownloadImage(_ photo: BananaLinkDownloadJob.Photo) -> TelegramMediaImage {
    let resource = LocalFileReferenceMediaResource(localFilePath: photo.fileURL.path, randomId: Int64.random(in: Int64.min ... Int64.max), isUniquelyReferencedTemporaryFile: true, size: photo.fileSize)
    let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: Int32(photo.width), height: Int32(photo.height)), resource: resource, progressiveSizes: [], immediateThumbnailData: nil)
    return TelegramMediaImage(imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
}
