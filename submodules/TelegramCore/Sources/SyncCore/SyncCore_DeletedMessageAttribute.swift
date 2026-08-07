import Foundation
import Postbox

/// Local anti-recall marker: message stays in chat history after a remote delete.
public final class DeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
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
}
