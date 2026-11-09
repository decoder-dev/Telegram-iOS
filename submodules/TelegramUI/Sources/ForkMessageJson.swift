import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UndoUI

// "Message JSON" from the message menu (Swiftgram). The dictionary is built by hand from the fields worth reading;
// Postbox types are not encodable, and dumping them generically would pull in caches and peer graphs.

private func forkMessageJsonPeer(_ peerId: PeerId, peer: Peer?) -> [String: Any] {
    var result: [String: Any] = ["id": Int64(forkProfileIdText(peerId: peerId, botApiFormat: true)) ?? peerId.toInt64()]
    if let channel = peer as? TelegramChannel {
        if case .broadcast = channel.info {
            result["type"] = "channel"
        } else {
            result["type"] = "supergroup"
        }
    } else if peer is TelegramGroup {
        result["type"] = "group"
    } else if peer is TelegramSecretChat {
        result["type"] = "secret"
    } else if let user = peer as? TelegramUser {
        result["type"] = user.botInfo != nil ? "bot" : "user"
    }
    if let peer {
        result["title"] = peer.debugDisplayTitle
        if let addressName = peer.addressName {
            result["username"] = addressName
        }
    }
    return result
}

private func forkMessageJsonFlags(_ flags: MessageFlags) -> [String] {
    let names: [(MessageFlags, String)] = [
        (.Incoming, "incoming"),
        (.Unsent, "unsent"),
        (.Sending, "sending"),
        (.Failed, "failed"),
        (.WasScheduled, "was_scheduled"),
        (.CopyProtected, "copy_protected"),
        (.IsForumTopic, "forum_topic"),
        (.ReactionsArePossible, "reactions_possible")
    ]
    return names.filter { flags.contains($0.0) }.map { $0.1 }
}

private func forkMessageJsonEntity(_ entity: MessageTextEntity) -> [String: Any] {
    var result: [String: Any] = ["offset": entity.range.lowerBound, "length": entity.range.count]
    switch entity.type {
    case let .Pre(language):
        result["type"] = "pre"
        if let language {
            result["language"] = language
        }
    case let .TextUrl(url):
        result["type"] = "text_link"
        result["url"] = url
    case let .TextMention(peerId):
        result["type"] = "text_mention"
        result["user_id"] = peerId.toInt64()
    case let .CustomEmoji(_, fileId):
        result["type"] = "custom_emoji"
        result["custom_emoji_id"] = "\(fileId)"
    case let .BlockQuote(isCollapsed):
        result["type"] = isCollapsed ? "expandable_blockquote" : "blockquote"
    case let .FormattedDate(_, date):
        result["type"] = "date_time"
        result["unix_time"] = date
    case let .Custom(customType):
        result["type"] = "custom"
        result["custom_type"] = customType
    default:
        // The remaining cases carry no values, so the case name is the type, in Bot API spelling: "BotCommand" is "bot_command".
        var name = ""
        for character in "\(entity.type)" {
            if character.isUppercase && !name.isEmpty {
                name.append("_")
            }
            name += character.lowercased()
        }
        result["type"] = name
    }
    return result
}

private func forkMessageJsonMedia(_ media: Media) -> [String: Any] {
    var result: [String: Any] = [:]
    if let id = media.id {
        result["id"] = "\(id.id)"
    }
    switch media {
    case let image as TelegramMediaImage:
        result["type"] = "photo"
        result["sizes"] = image.representations.count
        if let largest = largestImageRepresentation(image.representations) {
            result["width"] = largest.dimensions.width
            result["height"] = largest.dimensions.height
        }
    case let file as TelegramMediaFile:
        if file.isInstantVideo {
            result["type"] = "video_note"
        } else if file.isVoice {
            result["type"] = "voice"
        } else if file.isMusic {
            result["type"] = "audio"
        } else if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
            result["type"] = "sticker"
        } else if file.isAnimated {
            result["type"] = "animation"
        } else if file.isVideo {
            result["type"] = "video"
        } else {
            result["type"] = "document"
        }
        result["mime_type"] = file.mimeType
        if let size = file.size {
            result["file_size"] = size
        }
        if let fileName = file.fileName {
            result["file_name"] = fileName
        }
        if let duration = file.duration {
            result["duration"] = duration
        }
        if let dimensions = file.dimensions {
            result["width"] = dimensions.width
            result["height"] = dimensions.height
        }
    case let webpage as TelegramMediaWebpage:
        result["type"] = "webpage"
        if case let .Loaded(content) = webpage.content {
            result["url"] = content.url
        }
    case let poll as TelegramMediaPoll:
        result["type"] = "poll"
        result["question"] = poll.text
        result["options"] = poll.options.count
        result["is_closed"] = poll.isClosed
    case let map as TelegramMediaMap:
        result["type"] = "location"
        result["latitude"] = map.latitude
        result["longitude"] = map.longitude
    case let contact as TelegramMediaContact:
        result["type"] = "contact"
        result["first_name"] = contact.firstName
        result["phone_number"] = contact.phoneNumber
    case let dice as TelegramMediaDice:
        result["type"] = "dice"
        result["emoji"] = dice.emoji
        if let value = dice.value {
            result["value"] = value
        }
    case let action as TelegramMediaAction:
        result["type"] = "service"
        // Only the case name: the associated values can hold whole gift or payment structures.
        result["action"] = String("\(action.action)".prefix(while: { $0 != "(" }))
    case is TelegramMediaStory:
        result["type"] = "story"
    default:
        result["type"] = String(describing: type(of: media))
    }
    return result
}

func forkMessageJson(_ message: Message) -> String {
    var json: [String: Any] = [
        "id": message.id.id,
        "namespace": message.id.namespace,
        "chat": forkMessageJsonPeer(message.id.peerId, peer: message.peers[message.id.peerId]),
        "date": message.timestamp,
        "date_iso": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(message.timestamp))),
        "flags": forkMessageJsonFlags(message.flags),
        "text": message.text,
        "media": message.media.map(forkMessageJsonMedia)
    ]
    if let author = message.author {
        json["from"] = forkMessageJsonPeer(author.id, peer: author)
    }
    if let threadId = message.threadId {
        json["thread_id"] = threadId
    }
    if let groupingKey = message.groupingKey {
        json["media_group_id"] = "\(groupingKey)"
    }
    if let forwardInfo = message.forwardInfo {
        var forward: [String: Any] = ["date": forwardInfo.date]
        if let author = forwardInfo.author {
            forward["from"] = forkMessageJsonPeer(author.id, peer: author)
        }
        if let source = forwardInfo.source {
            forward["chat"] = forkMessageJsonPeer(source.id, peer: source)
        }
        if let sourceMessageId = forwardInfo.sourceMessageId {
            forward["message_id"] = sourceMessageId.id
        }
        if let authorSignature = forwardInfo.authorSignature {
            forward["signature"] = authorSignature
        }
        if let psaType = forwardInfo.psaType {
            forward["psa_type"] = psaType
        }
        json["forward"] = forward
    }

    var attributeNames: [String] = []
    for attribute in message.attributes {
        attributeNames.append(String(describing: type(of: attribute)))
        switch attribute {
        case let attribute as TextEntitiesMessageAttribute:
            json["entities"] = attribute.entities.map(forkMessageJsonEntity)
        case let attribute as ReplyMessageAttribute:
            var reply: [String: Any] = ["message_id": attribute.messageId.id]
            if attribute.messageId.peerId != message.id.peerId {
                reply["chat"] = forkMessageJsonPeer(attribute.messageId.peerId, peer: message.peers[attribute.messageId.peerId])
            }
            if let quote = attribute.quote {
                reply["quote"] = quote.text
            }
            json["reply_to"] = reply
        case let attribute as ViewCountMessageAttribute:
            json["views"] = attribute.count
        case let attribute as ForwardCountMessageAttribute:
            json["forwards"] = attribute.count
        case let attribute as EditedMessageAttribute:
            json["edit_date"] = attribute.date
        case let attribute as ReplyThreadMessageAttribute:
            json["replies"] = attribute.count
        case let attribute as AuthorSignatureMessageAttribute:
            json["author_signature"] = attribute.signature
        case let attribute as InlineBotMessageAttribute:
            if let peerId = attribute.peerId {
                json["via_bot"] = forkMessageJsonPeer(peerId, peer: message.peers[peerId])
            }
        case let attribute as AutoremoveTimeoutMessageAttribute:
            json["self_destruct_timeout"] = attribute.timeout
        default:
            break
        }
    }
    json["attributes"] = attributeNames

    guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

final class ForkMessageJsonController: ViewController {
    private let presentationData: PresentationData
    private let text: String
    private let canCopy: Bool
    private let textView = UITextView()

    init(presentationData: PresentationData, title: String, text: String, canCopy: Bool) {
        self.presentationData = presentationData
        self.text = text
        self.canCopy = canCopy

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))

        self.title = title
        // A copy-protected message can be read here but not copied out.
        if canCopy {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: presentationData.strings.Conversation_ContextMenuCopy, style: .plain, target: self, action: #selector(self.copyPressed))
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor

        self.textView.backgroundColor = .clear
        self.textView.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.textView.font = .monospacedSystemFont(ofSize: 12.0, weight: .regular)
        self.textView.text = self.text
        self.textView.isEditable = false
        self.textView.isSelectable = self.canCopy
        self.textView.alwaysBounceVertical = true
        self.textView.textContainerInset = UIEdgeInsets(top: 12.0, left: 12.0, bottom: 12.0, right: 12.0)
        self.textView.contentInsetAdjustmentBehavior = .never
        self.displayNode.view.addSubview(self.textView)

        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.textView.frame = CGRect(x: layout.safeInsets.left, y: top, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: max(0.0, layout.size.height - top - layout.intrinsicInsets.bottom))
    }

    @objc private func copyPressed() {
        UIPasteboard.general.string = self.text
        self.present(UndoOverlayController(presentationData: self.presentationData, content: .copy(text: self.presentationData.strings.Conversation_TextCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }), in: .current)
    }
}
