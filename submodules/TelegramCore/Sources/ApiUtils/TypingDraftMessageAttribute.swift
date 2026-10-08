import Foundation
import Postbox

public final class TypingDraftMessageAttribute: MessageAttribute {
    public let id: Int64
    public let canStop: Bool
    public let keepOnStop: Bool

    public init(id: Int64 = 0, canStop: Bool = false, keepOnStop: Bool = false) {
        self.id = id
        self.canStop = canStop
        self.keepOnStop = keepOnStop
    }

    public init(decoder: PostboxDecoder) {
        self.id = decoder.decodeInt64ForKey("id", orElse: 0)
        self.canStop = decoder.decodeBoolForKey("canStop", orElse: false)
        self.keepOnStop = decoder.decodeBoolForKey("keepOnStop", orElse: false)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.id, forKey: "id")
        encoder.encodeBool(self.canStop, forKey: "canStop")
        encoder.encodeBool(self.keepOnStop, forKey: "keepOnStop")
    }
}
