// Fork: "Bypass sticker restrictions" (Extras > Messages > Sending). A sticker for a chat that bans stickers but allows
// videos is converted on the device into a short silent H.264 video (a static sticker into a one-second one) and sent as
// that. Ported from Donutgram (kittenello/Donutgram ChatController+DonutgramStickerMedia.swift at 768d2d6985: 9b62a5089c,
// b20587e7ec, 7d709e2b44, 2bb06f2f2f, 03a3160707, 6d9f7030b8, 9337a2183a, ee069f97b3, 9c20de22e5, 8ff878e02a).
import Foundation
import UIKit
import AVFoundation
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import AnimationCache
import EmojiTextAttachmentView
import PresentationDataUtils
import ChatPresentationInterfaceState
import TelegramUIPreferences
import WebPBinding

private let forkStickerExportQueue = DispatchQueue(label: "fork.sticker-export", qos: .userInitiated)
private let forkStickerSignalQueue = Queue(queue: forkStickerExportQueue)

/// Main-queue state: a fast conversion can finish while the overlay is still being presented.
private final class ForkStickerMediaProgress {
    private(set) var isFinished = false
    private var controller: ViewController?
    private var isPresented = false

    func show(_ controller: ViewController, present: (ViewController, @escaping () -> Void) -> Void) {
        guard !self.isFinished else {
            return
        }
        self.controller = controller
        present(controller, {
            self.isPresented = true
            if self.isFinished {
                self.dismiss()
            }
        })
    }

    func finish() {
        self.isFinished = true
        if self.isPresented {
            self.dismiss()
        }
    }

    private func dismiss() {
        self.controller?.dismiss()
        self.controller = nil
    }
}

/// The frame on white: an H.264 video has no alpha channel.
private func forkStickerFrameImage(_ frame: AnimationCacheItemFrame) -> UIImage? {
    guard case let .rgba(data, width, height, bytesPerRow) = frame.format,
        width > 0, height > 0, bytesPerRow >= width * 4, data.count >= height * bytesPerRow,
        let context = DrawingContext(size: CGSize(width: width, height: height), scale: 1.0, opaque: false, bytesPerRow: bytesPerRow) else {
        return nil
    }
    data.withUnsafeBytes { bytes in
        if let base = bytes.baseAddress {
            memcpy(context.bytes, base, height * bytesPerRow)
        }
    }
    guard let image = context.generateImage()?.cgImage else {
        return nil
    }
    // `contextGenerator` draws in Core Graphics coordinates, where `draw` keeps the frame upright. The y axis of
    // `rotatedContext` is flipped, so the same `draw` there sends the sticker upside down.
    return generateImage(CGSize(width: width, height: height), contextGenerator: { size, context in
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(image, in: CGRect(origin: .zero, size: size))
    }, opaque: true, scale: 1.0)
}

private func forkStickerVideo(context: AccountContext, size: CGSize, frameCount: Int, nextFrame: @escaping () -> (image: UIImage, duration: Double)?) -> Signal<AnyMediaReference?, NoError> {
    return Signal { subscriber in
        let temporary = EngineTempBox.shared.tempFile(fileName: "sticker-video.mp4")
        guard let writer = try? AVAssetWriter(outputURL: URL(fileURLWithPath: temporary.path), fileType: .mp4) else {
            EngineTempBox.shared.dispose(temporary)
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else {
            EngineTempBox.shared.dispose(temporary)
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        writer.add(input)
        guard writer.startWriting() else {
            EngineTempBox.shared.dispose(temporary)
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        writer.startSession(atSourceTime: .zero)
        let cancelled = Atomic<Bool>(value: false)
        var index = 0
        var duration = 0.0
        var finished = false
        var thumbnail: Data?
        input.requestMediaDataWhenReady(on: forkStickerExportQueue) {
            guard !finished, !cancelled.with({ $0 }) else {
                return
            }
            while input.isReadyForMoreMediaData && index < frameCount {
                let appended = autoreleasepool { () -> Bool in
                    guard let frame = nextFrame(),
                        let cgImage = frame.image.cgImage,
                        let pool = adaptor.pixelBufferPool else {
                        return false
                    }
                    if thumbnail == nil {
                        thumbnail = frame.image.jpegData(compressionQuality: 0.7)
                    }
                    var optionalBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess, let buffer = optionalBuffer else {
                        return false
                    }
                    CVPixelBufferLockBaseAddress(buffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                    guard let bitmap = CGContext(
                        data: CVPixelBufferGetBaseAddress(buffer),
                        width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                    ) else {
                        return false
                    }
                    bitmap.draw(cgImage, in: CGRect(origin: .zero, size: size))
                    guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: duration, preferredTimescale: 60_000)) else {
                        return false
                    }
                    duration += frame.duration.isFinite && frame.duration > 0 ? frame.duration : 1.0 / 30.0
                    return true
                }
                guard appended, duration <= 60.0 else {
                    finished = true
                    writer.cancelWriting()
                    EngineTempBox.shared.dispose(temporary)
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                index += 1
                if cancelled.with({ $0 }) {
                    return
                }
            }
            if index == frameCount {
                finished = true
                writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 60_000))
                input.markAsFinished()
                writer.finishWriting {
                    defer { EngineTempBox.shared.dispose(temporary) }
                    guard !cancelled.with({ $0 }), writer.status == .completed,
                        let data = try? Data(contentsOf: URL(fileURLWithPath: temporary.path)) else {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
                    var previews: [TelegramMediaImageRepresentation] = []
                    if let thumbnail {
                        let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: thumbnail)
                        previews.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(size), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                    }
                    let file = TelegramMediaFile(
                        fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: resource.fileId),
                        partialReference: nil, resource: resource, previewRepresentations: previews,
                        videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: Int64(data.count),
                        attributes: [
                            .FileName(fileName: "sticker-video.mp4"),
                            .Video(duration: duration, size: PixelDimensions(size), flags: [.isSilent, .supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil)
                        ], alternativeRepresentations: []
                    )
                    subscriber.putNext(.standalone(media: file))
                    subscriber.putCompletion()
                }
            }
        }
        return ActionDisposable {
            let _ = cancelled.swap(true)
            forkStickerExportQueue.async {
                if writer.status == .writing {
                    writer.cancelWriting()
                }
                EngineTempBox.shared.dispose(temporary)
            }
        }
    }
}

private func forkStaticStickerMedia(context: AccountContext, peerId: EnginePeer.Id, file: FileMediaReference, size: CGSize) -> Signal<AnyMediaReference?, NoError> {
    let resource = file.media.resource
    let reference: FileMediaReference
    if case .standalone = file {
        reference = stickerPackFileReference(file.media)
    } else {
        reference = file
    }
    let data = Signal<EngineMediaResource.ResourceData?, NoError> { subscriber in
        let read = (context.engine.resources.data(resource: EngineMediaResource(resource))
        |> filter { $0.isComplete }
        |> take(1)).start(next: { data in
            subscriber.putNext(data)
            subscriber.putCompletion()
        })
        let fetch = context.engine.resources.fetch(reference: reference.abstract.resourceReference(resource), userLocation: .peer(peerId), userContentType: .sticker).start(error: { _ in
            subscriber.putNext(nil)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            read.dispose()
            fetch.dispose()
        }
    }
    return data
    |> take(1)
    |> deliverOn(forkStickerSignalQueue)
    |> mapToSignal { resourceData -> Signal<AnyMediaReference?, NoError> in
        guard let resourceData,
            let sourceData = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path)),
            let sourceImage = UIImage(data: sourceData) ?? WebP.convert(fromWebP: sourceData),
            let cgImage = sourceImage.cgImage,
            let image = generateImage(size, contextGenerator: { size, context in
                context.setFillColor(UIColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }, opaque: true, scale: 1.0) else {
            return .single(nil)
        }
        return forkStickerVideo(context: context, size: size, frameCount: 2, nextFrame: {
            return (image, 0.5)
        })
    }
    |> then(.single(nil))
    |> take(1)
    |> timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
}

private func forkStickerMedia(context: AccountContext, peerId: EnginePeer.Id, file: FileMediaReference) -> Signal<AnyMediaReference?, NoError> {
    let sourceSize = file.media.dimensions?.cgSize ?? CGSize(width: 512.0, height: 512.0)
    let dimensions = (sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize : CGSize(width: 512.0, height: 512.0)).aspectFitted(CGSize(width: 512.0, height: 512.0))
    let size = CGSize(width: CGFloat(max(2, Int(dimensions.width) / 2 * 2)), height: CGFloat(max(2, Int(dimensions.height) / 2 * 2)))
    if !file.media.isAnimatedSticker && !file.media.isVideoSticker {
        return forkStaticStickerMedia(context: context, peerId: peerId, file: file, size: size)
    }
    let fetch = animationCacheFetchFile(context: context, userLocation: .peer(peerId), userContentType: .sticker, resource: file.abstract.resourceReference(file.media.resource), type: AnimationCacheAnimationType(file: file.media), keyframeOnly: false, customColor: nil)
    return context.animationCache.get(sourceId: file.media.resource.id.stringRepresentation, size: size, fetch: fetch)
    |> filter { $0.isFinal }
    |> take(1)
    |> deliverOn(forkStickerSignalQueue)
    |> mapToSignal { result -> Signal<AnyMediaReference?, NoError> in
        guard let item = result.item, item.numFrames > 0, item.numFrames <= 1800 else {
            return .single(nil)
        }
        item.reset()
        return forkStickerVideo(context: context, size: size, frameCount: item.numFrames, nextFrame: {
            guard let frame = item.advance(advance: .frames(1), requestedFormat: .rgba)?.frame,
                let image = forkStickerFrameImage(frame) else {
                return nil
            }
            return (image, frame.duration)
        })
    }
    |> timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
}

private func forkStickerFile(_ message: EnqueueMessage) -> FileMediaReference? {
    if case let .message(_, _, _, reference?, _, _, _, _, _, _) = message, let fileReference = reference.concrete(TelegramMediaFile.self), fileReference.media.isSticker {
        return fileReference
    }
    return nil
}

/// Whether `messages` hold a sticker that `peer` takes only as a video.
func forkStickerMessagesNeedMedia(peer: EngineRawPeer?, messages: [EnqueueMessage]) -> Bool {
    guard let peer, forkCanSendStickerAsMedia(peer: peer) else {
        return false
    }
    return messages.contains(where: { forkStickerFile($0) != nil })
}

enum ForkStickerMediaResult {
    /// The messages to enqueue, and the stickers that went out as videos.
    case ready(messages: [EnqueueMessage], convertedStickers: [FileMediaReference])
    /// The chat bans videos, including the one-second video made from a static sticker.
    case notAllowed
    case failed
}

func forkPrepareStickerMedia(context: AccountContext, peer: EngineRawPeer, messages: [EnqueueMessage]) -> Signal<ForkStickerMediaResult, NoError> {
    if messages.contains(where: { message in
        if let file = forkStickerFile(message) {
            return !forkCanSendStickerAsMedia(peer: peer, file: file.media)
        }
        return false
    }) {
        return .single(.notAllowed)
    }
    return combineLatest(messages.map { message -> Signal<ForkPreparedStickerMessage?, NoError> in
        guard case let .message(text, attributes, inlineStickers, _, threadId, replyId, storyId, groupingKey, correlationId, bubbleUp) = message, let fileReference = forkStickerFile(message) else {
            return .single(ForkPreparedStickerMessage(message: message, convertedSticker: nil))
        }
        return forkStickerMedia(context: context, peerId: peer.id, file: fileReference)
        |> map { converted -> ForkPreparedStickerMessage? in
            guard let converted else {
                return nil
            }
            // The emoji-search query belongs to a sticker; the pack still moves up, as after a usual sticker.
            let attributes = attributes.filter { !($0 is EmojiSearchQueryMessageAttribute) }
            let convertedMessage: EnqueueMessage = .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: converted, threadId: threadId, replyToMessageId: replyId, replyToStoryId: storyId, localGroupingKey: groupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUp)
            return ForkPreparedStickerMessage(message: convertedMessage, convertedSticker: fileReference)
        }
    })
    |> map { results -> ForkStickerMediaResult in
        var messages: [EnqueueMessage] = []
        var convertedStickers: [FileMediaReference] = []
        for result in results {
            guard let result else {
                return .failed
            }
            messages.append(result.message)
            if let convertedSticker = result.convertedSticker {
                convertedStickers.append(convertedSticker)
            }
        }
        return .ready(messages: messages, convertedStickers: convertedStickers)
    }
}

private struct ForkPreparedStickerMessage {
    let message: EnqueueMessage
    /// The sticker this message carries as a video instead.
    let convertedSticker: FileMediaReference?
}

extension ChatControllerImpl {
    /// "Bypass sticker restrictions" (Donutgram `stickerUnlock`): a sticker for a chat that bans stickers goes out as a video; other
    /// messages pass at once. While a sticker converts, a progress overlay covers the chat, so a second tap cannot
    /// send it twice and no later message overtakes it. Tapping the overlay cancels the send.
    func forkMessagesWithStickerMedia(_ messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {
        let chatPeer = canBypassRestrictions(chatPresentationInterfaceState: self.presentationInterfaceState) ? nil : self.presentationInterfaceState.renderedPeer?.peer
        guard let peer = chatPeer, forkStickerMessagesNeedMedia(peer: peer, messages: messages) else {
            return .single(messages)
        }
        let context = self.context
        let presentationData = self.presentationData
        let correlationIds = Set(messages.compactMap { message -> Int64? in
            if case let .message(_, _, _, _, _, _, _, _, correlationId, _) = message {
                return correlationId
            }
            return nil
        })
        return Signal<[EnqueueMessage], NoError> { [weak self] subscriber in
            self?.forkIsConvertingSticker = true
            var cancelImpl: (() -> Void)?
            let progress = ForkStickerMediaProgress()
            let progressDisposable = (Signal<Never, NoError> { [weak self] _ in
                guard !progress.isFinished else {
                    return EmptyDisposable
                }
                let controller = textAlertController(
                    context: context,
                    title: nil,
                    text: (ForkPresentationLanguage.prefersRussianStrings ? "Преобразование стикера…" : "Converting the sticker…"),
                    actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                        cancelImpl?()
                    })],
                    dismissOnOutsideTap: false
                )
                progress.show(controller, present: { [weak self] controller, completion in
                    self?.present(controller, in: .current, completion: completion)
                })
                return ActionDisposable {
                    Queue.mainQueue().async {
                        progress.finish()
                    }
                }
            }
            |> runOn(Queue.mainQueue())
            |> delay(0.15, queue: Queue.mainQueue())).startStrict()
            let conversionDisposable = MetaDisposable()
            let isFinished = Atomic<Bool>(value: false)
            let finish: () -> Void = { [weak self] in
                if isFinished.swap(true) {
                    return
                }
                progress.finish()
                progressDisposable.dispose()
                self?.forkIsConvertingSticker = false
            }
            cancelImpl = { [weak self] in
                finish()
                conversionDisposable.dispose()
                self?.forkDropPendingSendAction(correlationIds: correlationIds)
                subscriber.putCompletion()
            }
            conversionDisposable.set((forkPrepareStickerMedia(context: context, peer: peer, messages: messages)
            |> then(.single(.failed))
            |> take(1)
            |> deliverOnMainQueue).startStrict(next: { [weak self] result in
                finish()
                switch result {
                case let .ready(prepared, convertedStickers):
                    // A sent sticker reaches Recent from the sent message; a photo or a video does not, so it is added here.
                    for file in convertedStickers where file.media.fileId.namespace == Namespaces.Media.CloudFile {
                        context.engine.stickers.addRecentlyUsedSticker(fileReference: file)
                    }
                    subscriber.putNext(prepared)
                case .notAllowed:
                    if let self {
                        self.forkDropPendingSendAction(correlationIds: correlationIds)
                        self.interfaceInteraction?.displayRestrictedInfo(.stickers, .alert)
                    }
                case .failed:
                    if let self {
                        self.forkDropPendingSendAction(correlationIds: correlationIds)
                        self.present(textAlertController(context: context, title: nil, text: (ForkPresentationLanguage.prefersRussianStrings ? "Не удалось преобразовать стикер. Попробуйте ещё раз." : "Could not convert the sticker. Please try again."), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                    }
                }
                subscriber.putCompletion()
            }))
            return ActionDisposable {
                conversionDisposable.dispose()
                Queue.mainQueue().async {
                    finish()
                }
            }
        }
        |> runOn(Queue.mainQueue())
    }

    /// The send action that waits for these messages (clearing the reply, collapsing the input) never fires when the
    /// sticker is not sent, so it is dropped and the reply stays for another try.
    private func forkDropPendingSendAction(correlationIds: Set<Int64>) {
        if let (_, pendingCorrelationId) = self.chatDisplayNode.historyNode.layoutActionOnViewTransition, let correlationId = pendingCorrelationId, correlationIds.contains(correlationId) {
            self.chatDisplayNode.historyNode.layoutActionOnViewTransition = nil
            self.layoutActionOnViewTransitionAction = nil
        }
    }
}
