import Foundation
import SwiftSignalKit

/// How other people's presence is drawn. Adapted from Donutgram's presence options.
public struct BananaPresenceDisplay: Equatable {
    public static let didChangeNotification = Notification.Name("BananaPresenceDisplay.didChange")
    private static let state = Atomic<BananaPresenceDisplay>(value: BananaPresenceDisplay(exactLastSeen: false, showsOfflineDot: false))
    public static var current: BananaPresenceDisplay {
        get { state.with { $0 } }
        set {
            let previous = state.swap(newValue)
            if previous != newValue { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        }
    }
    /// "last seen today at 14:22" instead of "last seen 5 minutes ago" or "2 hours ago".
    public let exactLastSeen: Bool
    /// A grey dot on the avatar of a contact who is offline, next to the green one for who is online.
    public let showsOfflineDot: Bool

    public init(exactLastSeen: Bool, showsOfflineDot: Bool) {
        self.exactLastSeen = exactLastSeen
        self.showsOfflineDot = showsOfflineDot
    }
}
