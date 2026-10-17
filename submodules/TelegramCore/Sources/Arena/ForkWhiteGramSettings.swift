import Foundation
import Postbox
import SwiftSignalKit

/// WhiteGram "disable story recording": every entry point that would open the story camera does
/// nothing (the chat list's Add Story button, the Add Story context items, the own-avatar tap that
/// has no story to show, the profile's Add Story, `tg://` camera links). Viewing stays available.
///
/// Read synchronously from those entry points, so it lives here rather than only in
/// `ForkExtrasSettings`, whose read is asynchronous. Mirrored to UserDefaults so the first tap after
/// a cold launch already sees the stored choice.
public enum ForkStoryCreationSettings {
    private static let persistedKey = "ForkStoryCreationSettings.disabled.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var disabled: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

/// WhiteGram "channel post reactions" turned off: reactions are not drawn under posts in broadcast
/// channels. Groups and private chats keep them; `ForkExtrasHotFlags.hideReactionsBar` is the switch
/// that hides them everywhere.
public enum ForkChannelPostReactionsSettings {
    private static let persistedKey = "ForkChannelPostReactionsSettings.hidden.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var hidden: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

/// Whether a message's reactions are left out of its bubble: every message under the global switch,
/// and posts of broadcast channels under the channel-only one.
public func forkHidesMessageReactions(_ message: Message) -> Bool {
    if ForkExtrasHotFlags.hideReactionsBar {
        return true
    }
    if ForkChannelPostReactionsSettings.hidden, let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info {
        return true
    }
    return false
}
