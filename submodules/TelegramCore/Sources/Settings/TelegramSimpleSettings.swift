import Foundation
import Postbox
import SwiftSignalKit

public final class TelegramSimpleSettings {
    public static let shared = TelegramSimpleSettings()

    private let defaults: UserDefaults

    private enum Key {
        static let saveDeletedMessages = "telegram.mod.saveDeletedMessages"
        static let saveEditHistory = "telegram.mod.saveEditHistory"
        static let saveViewOnceMedia = "telegram.mod.saveViewOnceMedia"
        static let saveInBotChats = "telegram.mod.saveInBotChats"
        static let allowCopyProtectedMedia = "telegram.mod.allowCopyProtectedMedia"
        static let showExactOfflineTime = "telegram.ghost.showExactOfflineTime"
        static let bottomChatFolders = "telegram.ui.bottomChatFolders"
        static let channelForwardCounter = "telegram.ui.channelForwardCounter"
        static let glowEffectsEnabled = "telegram.ui.glowEffectsEnabled"
        static let avatarMentionsEnabled = "telegram.ui.avatarMentionsEnabled"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func getBool(_ key: String, defaultValue: Bool = true) -> Bool {
        if self.defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return self.defaults.bool(forKey: key)
    }

    private func setBool(_ value: Bool, forKey key: String) {
        self.defaults.set(value, forKey: key)
        self.defaults.synchronize()
    }

    public var saveDeletedMessages: Bool {
        get { self.getBool(Key.saveDeletedMessages, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveDeletedMessages) }
    }

    public var saveEditHistory: Bool {
        get { self.getBool(Key.saveEditHistory, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveEditHistory) }
    }

    public var saveViewOnceMedia: Bool {
        get { self.getBool(Key.saveViewOnceMedia, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveViewOnceMedia) }
    }

    public var saveInBotChats: Bool {
        get { self.getBool(Key.saveInBotChats, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.saveInBotChats) }
    }

    public var allowCopyProtectedMedia: Bool {
        get { self.getBool(Key.allowCopyProtectedMedia, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.allowCopyProtectedMedia) }
    }

    public var showExactOfflineTime: Bool {
        get { self.getBool(Key.showExactOfflineTime, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.showExactOfflineTime) }
    }

    public var bottomChatFolders: Bool {
        get { self.getBool(Key.bottomChatFolders, defaultValue: false) }
        set { self.setBool(newValue, forKey: Key.bottomChatFolders) }
    }

    public var channelForwardCounter: Bool {
        get { self.getBool(Key.channelForwardCounter, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.channelForwardCounter) }
    }

    public var glowEffectsEnabled: Bool {
        get { self.getBool(Key.glowEffectsEnabled, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.glowEffectsEnabled) }
    }

    public var avatarMentionsEnabled: Bool {
        get { self.getBool(Key.avatarMentionsEnabled, defaultValue: true) }
        set { self.setBool(newValue, forKey: Key.avatarMentionsEnabled) }
    }
}
