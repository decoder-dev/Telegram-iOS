// Fork: send GIFs as silent looping videos in chats that ban GIFs but still allow videos.
// Ported from Donutgram c7bb578 ("DonutgramGifVideo.swift"); gated by the
// `ForkExtrasHotFlags.sendBannedGifsAsVideo` hot flag (Fork Extras ▸ "Send banned GIFs as video").
import Foundation
import Postbox
import SwiftSignalKit

/// The file name stamped on a converted GIF. It survives delivery, so the converted video can
/// be recognised (and looped like a GIF) after a restart and by other fork clients.
private let forkBannedGifVideoFileName = "gif-video.mp4"

/// True when the setting is on and `peer` bans GIFs while still allowing videos, so a GIF can go
/// out as a silent video instead. Admins and creators are never banned, so they never convert.
public func forkCanSendGifAsVideo(peer: Peer?) -> Bool {
    guard ForkExtrasHotFlags.sendBannedGifsAsVideo else {
        return false
    }
    if let peer = peer as? TelegramChannel {
        return peer.hasBannedPermission(.banSendGifs) != nil && peer.hasBannedPermission(.banSendVideos) == nil && peer.hasBannedPermission(.banSendMedia) == nil && peer.hasBannedPermission(.banReadMessages) == nil
    } else if let peer = peer as? TelegramGroup {
        return peer.hasBannedPermission(.banSendGifs) && !peer.hasBannedPermission(.banSendVideos) && !peer.hasBannedPermission(.banSendMedia) && !peer.hasBannedPermission(.banReadMessages)
    }
    return false
}

private func forkIsSilentVideo(_ file: TelegramMediaFile) -> Bool {
    for attribute in file.attributes {
        if case let .Video(_, _, flags, _, _, _) = attribute, flags.contains(.isSilent) {
            return true
        }
    }
    return false
}

/// True for a GIF this feature converted into a silent video (by file name, so ordinary silent
/// videos are not affected).
public func forkIsBannedGifVideo(_ file: TelegramMediaFile) -> Bool {
    return !file.isAnimated && file.fileName == forkBannedGifVideoFileName && forkIsSilentVideo(file)
}

private func forkIsConvertibleGif(_ file: TelegramMediaFile) -> Bool {
    return file.isAnimated && !file.isSticker && !file.isCustomEmoji && !file.isAnimatedSticker && !file.isVideoSticker
}

/// Copies the GIF's data into a fresh local resource and re-labels it as a silent streaming video.
private func forkLocalGifVideo(account: Account, peerId: PeerId, reference: AnyMediaReference, file: TelegramMediaFile) -> Signal<AnyMediaReference?, NoError> {
    let signal: Signal<AnyMediaReference?, NoError> = Signal { subscriber in
        let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
        let fetchDisposable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(peerId), userContentType: .video, reference: reference.resourceReference(file.resource)).start(error: { _ in
            subscriber.putNext(nil)
            subscriber.putCompletion()
        })
        let dataDisposable = (account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: true))
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            account.postbox.mediaBox.copyResourceData(from: file.resource.id, to: resource.id, synchronous: true)
            var attributes = file.attributes.filter { attribute in
                switch attribute {
                case .Animated, .Video, .Audio, .FileName:
                    return false
                default:
                    return true
                }
            }
            attributes.append(.FileName(fileName: forkBannedGifVideoFileName))
            attributes.append(.Video(duration: file.duration ?? 0.0, size: file.dimensions ?? PixelDimensions(width: 128, height: 128), flags: [.isSilent, .supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil))
            // An image/gif payload keeps its MIME type here; the UI-side transformOutgoingMessageMedia
            // re-encodes it to MP4 (see TransformOutgoingMessageMedia.swift).
            let mimeType = file.mimeType == "image/gif" ? "image/gif" : "video/mp4"
            let converted = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: resource.fileId), partialReference: nil, resource: resource, previewRepresentations: file.previewRepresentations, videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData, mimeType: mimeType, size: data.size, attributes: attributes, alternativeRepresentations: [])
            subscriber.putNext(.standalone(media: converted))
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetchDisposable.dispose()
            dataDisposable.dispose()
        }
    }
    return signal
    |> timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
}

/// Rewrites outgoing GIFs into silent videos when the setting is on and the target chat bans
/// GIFs. Every other message (and every chat that allows GIFs) passes through unchanged.
func forkPrepareBannedGifVideos(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {
    guard ForkExtrasHotFlags.sendBannedGifsAsVideo, messages.contains(where: { message in
        if case let .message(_, _, _, reference, _, _, _, _, _, _) = message, let file = reference?.media as? TelegramMediaFile {
            return forkIsConvertibleGif(file)
        }
        return false
    }) else {
        return .single(messages)
    }
    return account.postbox.transaction { transaction -> Bool in
        return forkCanSendGifAsVideo(peer: transaction.getPeer(peerId))
    }
    |> mapToSignal { enabled -> Signal<[EnqueueMessage], NoError> in
        if !enabled {
            return .single(messages)
        }
        return combineLatest(messages.map { message -> Signal<EnqueueMessage, NoError> in
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, let reference = mediaReference, let file = reference.media as? TelegramMediaFile, forkIsConvertibleGif(file) else {
                return .single(message)
            }
            return forkLocalGifVideo(account: account, peerId: peerId, reference: reference, file: file)
            |> map { converted -> EnqueueMessage in
                guard let converted = converted else {
                    return message
                }
                // Sending as an inline-bot result would keep the server's GIF classification.
                let filteredAttributes = attributes.filter { !($0 is OutgoingChatContextResultMessageAttribute) && !($0 is InlineBotMessageAttribute) }
                return .message(text: text, attributes: filteredAttributes, inlineStickers: inlineStickers, mediaReference: converted, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
            }
        })
    }
}
