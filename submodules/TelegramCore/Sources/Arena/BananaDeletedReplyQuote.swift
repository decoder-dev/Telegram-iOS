import Foundation
import Postbox
import SwiftSignalKit

/// A reply to a message that only this client still shows (one deleted for everybody and kept by "Save deleted
/// messages") cannot reach the other person as a reply: the server no longer has the message. So the reply goes out
/// as an ordinary message that starts with a quote of the deleted one. Adapted from Donutgram's pseudo-replies,
/// without the local reply header: the sent message simply carries the quote as its first lines.
public enum BananaDeletedReplyQuote {
    private static let enabledValue = Atomic<Bool>(value: false)

    public static var enabled: Bool {
        get { return enabledValue.with { $0 } }
        set { let _ = enabledValue.swap(newValue) }
    }

    /// How much of the deleted message the quote shows.
    static let maxQuoteLength = 200

    /// Whether the text of a message with this media still reaches the other person. An inline-bot result is sent
    /// without text, and stickers, dice and round videos have no caption, so those keep the regular reply.
    static func canCarryQuote(attributes: [MessageAttribute], media: [Media]) -> Bool {
        if attributes.contains(where: { $0 is OutgoingChatContextResultMessageAttribute }) {
            return false
        }
        for item in media {
            if let file = item as? TelegramMediaFile {
                if file.isSticker || file.isAnimatedSticker || file.isInstantVideo {
                    return false
                }
            } else if !(item is TelegramMediaImage || item is TelegramMediaWebpage || item is TelegramMediaPoll || item is TelegramMediaPaidContent) {
                return false
            }
        }
        return true
    }

    /// `message` as an ordinary message with the quote in front, or nil when it is not a reply to a deleted message
    /// or cannot carry the quote.
    static func quotedMessage(transaction: Transaction, peerId: PeerId, message: EnqueueMessage) -> EnqueueMessage? {
        guard self.enabled, peerId.namespace != Namespaces.Peer.SecretChat else {
            return nil
        }
        guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message,
              let replyToMessageId, replyToMessageId.messageId.namespace == Namespaces.Message.Cloud, replyToMessageId.messageId.peerId == peerId,
              replyToStoryId == nil,
              let source = transaction.getMessage(replyToMessageId.messageId),
              source.attributes.contains(where: { $0 is DeletedMessageAttribute }),
              self.canCarryQuote(attributes: attributes, media: mediaReference.flatMap { [$0.media] } ?? []) else {
            return nil
        }

        let author = source.author?.debugDisplayTitle ?? ""
        var quoted = replyToMessageId.quote?.text ?? source.text
        if quoted.isEmpty {
            quoted = "…"
        }
        var quotedNS = quoted as NSString
        if quotedNS.length > self.maxQuoteLength {
            quotedNS = (quotedNS.substring(to: self.maxQuoteLength) + "…") as NSString
        }
        let quoteText = author.isEmpty ? (quotedNS as String) : "\(author)\n\(quotedNS as String)"
        let quoteLength = (quoteText as NSString).length
        // The quote and the message are separated by a line break that belongs to neither.
        let prefix = text.isEmpty ? quoteText : quoteText + "\n"
        let prefixLength = (prefix as NSString).length

        var entities: [MessageTextEntity] = [MessageTextEntity(range: 0 ..< quoteLength, type: .BlockQuote(isCollapsed: false))]
        var otherAttributes: [MessageAttribute] = []
        for attribute in attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                entities.append(contentsOf: attribute.entities.map { entity in
                    MessageTextEntity(range: (entity.range.lowerBound + prefixLength) ..< (entity.range.upperBound + prefixLength), type: entity.type)
                })
            } else {
                otherAttributes.append(attribute)
            }
        }
        otherAttributes.append(TextEntitiesMessageAttribute(entities: entities))

        return .message(text: prefix + text, attributes: otherAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
    }
}
