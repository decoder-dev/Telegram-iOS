import Foundation
import Postbox

/// Local anti-recall marker: message stays in chat history after a remote delete.
/// Matches AyuGram Android's `ayuDeleted` flag on retained messages.
public final class DeletedMessageAttribute: MessageAttribute {
    public let date: Int32
    /// Local copy of an attachment under MessageSaving/Saved Attachments (Android parity).
    public let mediaPath: String?

    public init(date: Int32, mediaPath: String? = nil) {
        self.date = date
        self.mediaPath = mediaPath
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
        self.mediaPath = decoder.decodeOptionalStringForKey("m")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
        if let mediaPath = self.mediaPath {
            encoder.encodeString(mediaPath, forKey: "m")
        } else {
            encoder.encodeNil(forKey: "m")
        }
    }
}

public extension Message {
    var isLocallyDeleted: Bool {
        for attribute in self.attributes {
            if attribute is DeletedMessageAttribute {
                return true
            }
        }
        return false
    }

    var locallyDeletedMediaPath: String? {
        for attribute in self.attributes {
            if let attribute = attribute as? DeletedMessageAttribute {
                return attribute.mediaPath
            }
        }
        return nil
    }
}
