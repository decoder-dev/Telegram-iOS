import Foundation
import Postbox
import SwiftSignalKit

/// Display and send preferences that decide what a message shows (paid reactions, the "via @bot" label) and whether
/// outgoing messages carry a link preview. Atomic, so layout and send queues read it without touching settings storage.
public enum ForkMessageVisibility {
    public struct State: Equatable {
        public var hidePaidReactions: Bool = false
        public var hideViaBot: Bool = false
        public var removeLinkPreviews: Bool = false

        public init(hidePaidReactions: Bool = false, hideViaBot: Bool = false, removeLinkPreviews: Bool = false) {
            self.hidePaidReactions = hidePaidReactions
            self.hideViaBot = hideViaBot
            self.removeLinkPreviews = removeLinkPreviews
        }
    }

    private static let state = Atomic<State>(value: State())

    public static var current: State {
        return state.with { $0 }
    }

    public static func update(_ next: State) {
        let _ = state.swap(next)
    }

    public static var hidePaidReactions: Bool {
        return state.with { $0.hidePaidReactions }
    }

    public static var hideViaBot: Bool {
        return state.with { $0.hideViaBot }
    }

    public static var removeLinkPreviews: Bool {
        return state.with { $0.removeLinkPreviews }
    }
}

/// The merged reactions of a message without paid (star) reactions when they are hidden.
public func forkVisibleMessageReactions(attributes: [MessageAttribute], isTags: Bool) -> ReactionsMessageAttribute? {
    guard let attribute = mergedMessageReactions(attributes: attributes, isTags: isTags) else {
        return nil
    }
    guard ForkMessageVisibility.hidePaidReactions else {
        return attribute
    }
    return ReactionsMessageAttribute(
        canViewList: attribute.canViewList,
        isTags: attribute.isTags,
        reactions: attribute.reactions.filter { $0.value != .stars },
        recentPeers: attribute.recentPeers.filter { $0.value != .stars },
        topPeers: []
    )
}

/// Outgoing attributes without link previews when they are turned off.
public func forkOutgoingMessageAttributes(_ attributes: [MessageAttribute]) -> [MessageAttribute] {
    guard ForkMessageVisibility.removeLinkPreviews else {
        return attributes
    }
    var result = attributes.filter { !($0 is WebpagePreviewMessageAttribute) }
    if let index = result.firstIndex(where: { $0 is OutgoingContentInfoMessageAttribute }), let contentInfo = result[index] as? OutgoingContentInfoMessageAttribute {
        result[index] = contentInfo.withUpdatedFlags(contentInfo.flags.union(.disableLinkPreviews))
    } else {
        result.append(OutgoingContentInfoMessageAttribute(flags: [.disableLinkPreviews]))
    }
    return result
}
