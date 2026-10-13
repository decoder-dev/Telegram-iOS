import Foundation
import SwiftSignalKit

/// What the chat list's title row leaves out. Adapted from Donutgram's chat list appearance options.
public struct BananaChatListHeader: Equatable {
    public static let didChangeNotification = Notification.Name("BananaChatListHeader.didChange")
    private static let state = Atomic<BananaChatListHeader>(value: BananaChatListHeader(hidesConnectionStatus: false, hidesEmojiStatus: false))
    public static var current: BananaChatListHeader {
        get { state.with { $0 } }
        set {
            let previous = state.swap(newValue)
            if previous != newValue { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        }
    }
    /// "Connecting…" and "Updating…" never replace the title.
    public let hidesConnectionStatus: Bool
    /// No emoji or Premium star after the title.
    public let hidesEmojiStatus: Bool

    public init(hidesConnectionStatus: Bool, hidesEmojiStatus: Bool) {
        self.hidesConnectionStatus = hidesConnectionStatus
        self.hidesEmojiStatus = hidesEmojiStatus
    }
}
