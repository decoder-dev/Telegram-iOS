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
/// "Hide AI features" (Extras > Messages > Input panel; Donutgram 9b62a5089c): besides the AI buttons of the composers,
/// message summaries are not offered or shown, and Copy takes the original text. Read by the bubble nodes at layout time.
public enum ForkAIFeaturesSettings {
    private static let persistedKey = "ForkAIFeaturesSettings.hidden.v1"
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

/// Chat header switches projected from Extras (Donutgram 9b62a5089c): "Hide phone number in chat title".
public enum ForkChatTitleSettings {
    private static let persistedKey = "ForkChatTitleSettings.hidesPhoneNumber.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var hidesPhoneNumber: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

/// "Show hidden admin badges" (Extras > Messages; Donutgram 69259e6c30). Display only: the server's title is untouched.
public enum ForkAdminTitles {
    private static let persistedKey = "ForkAdminTitles.showsHiddenBadges.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var showsHiddenBadges: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }

    /// The title to show for a known admin or owner: nil, so the caller falls back to the standard badge, when the
    /// switch is on and the title has nothing visible in it (whitespace, control, default-ignorable or braille-blank
    /// characters, which some admins use to hide that they are admins).
    public static func visibleTitle(_ title: String?) -> String? {
        guard self.showsHiddenBadges, let title else {
            return title
        }
        let hasVisibleContent = title.unicodeScalars.contains { scalar in
            return !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
                && !scalar.properties.isDefaultIgnorableCodePoint
                && scalar.value != 0x2800 // Braille pattern blank is not Unicode whitespace.
        }
        return hasVisibleContent ? title : nil
    }
}

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
