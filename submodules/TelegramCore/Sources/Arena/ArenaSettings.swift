import Foundation

public class ArenaSettings {
    public static let shared = ArenaSettings()
    public static let didChangeNotification = Notification.Name("ArenaSettings_didChangeNotification")
    public static let shadowBanDidChangeNotification = Notification.Name("ArenaSettings_shadowBanDidChangeNotification")
    
    private let defaults: UserDefaults
    private let lock = NSRecursiveLock()

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ph.teleg.Telegrapf") ?? UserDefaults.standard) {
        self.defaults = defaults
    }

    private func locked<T>(_ body: () -> T) -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body()
    }

    public var shadowBanSnapshot: (bannedPeerIds: [Int64], revealedChatIds: [Int64]) {
        return self.locked { (self.shadowBannedPeerIds, self.shadowBanRevealedChatIds) }
    }
    
    public var shadowBannedPeerIds: [Int64] {
        get { return self.locked { defaults.array(forKey: "shadowBannedPeerIds") as? [Int64] ?? [] } }
        set { self.locked { defaults.set(newValue, forKey: "shadowBannedPeerIds") } }
    }
    
    public var hasShadowBans: Bool {
        return !shadowBannedPeerIds.isEmpty
    }
    
    public func isShadowBanned(_ peerId: Int64) -> Bool {
        return shadowBannedPeerIds.contains(peerId)
    }
    
    public func setShadowBanned(_ banned: Bool, peerId: Int64) {
        self.lock.lock()
        var list = shadowBannedPeerIds
        if banned {
            if !list.contains(peerId) { list.append(peerId) }
        } else {
            list.removeAll(where: { $0 == peerId })
        }
        shadowBannedPeerIds = list
        self.lock.unlock()
        NotificationCenter.default.post(name: ArenaSettings.shadowBanDidChangeNotification, object: nil)
    }
    
    public var shadowBanRevealedChatIds: [Int64] {
        get { return self.locked { defaults.array(forKey: "shadowBanRevealedChatIds") as? [Int64] ?? [] } }
        set { self.locked { defaults.set(newValue, forKey: "shadowBanRevealedChatIds") } }
    }
    
    public func isShadowBanRevealed(chatPeerId: Int64) -> Bool {
        return shadowBanRevealedChatIds.contains(chatPeerId)
    }
    
    public func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64) {
        self.lock.lock()
        var list = shadowBanRevealedChatIds
        if revealed {
            if !list.contains(chatPeerId) { list.append(chatPeerId) }
        } else {
            list.removeAll(where: { $0 == chatPeerId })
        }
        shadowBanRevealedChatIds = list
        self.lock.unlock()
        NotificationCenter.default.post(name: ArenaSettings.shadowBanDidChangeNotification, object: nil)
    }
    
    public var semiTransparentDeletedMessages: Bool { return true }
    // Runtime projection of ForkExtrasSettings. Do not re-read shared defaults here:
    // another process or an unavailable app-group suite must not override the UI choice.
    private var avatarGlowValue = false
    private var reactionGlowValue = false

    public var avatarGlow: Bool {
        get { self.locked { self.avatarGlowValue } }
        set {
            let changed = self.locked { () -> Bool in
                guard self.avatarGlow != newValue else { return false }
                self.avatarGlowValue = newValue
                return true
            }
            if changed { NotificationCenter.default.post(name: Self.didChangeNotification, object: nil) }
        }
    }
    public var reactionGlow: Bool {
        get { self.locked { self.reactionGlowValue } }
        set {
            let changed = self.locked { () -> Bool in
                guard self.reactionGlow != newValue else { return false }
                self.reactionGlowValue = newValue
                return true
            }
            if changed { NotificationCenter.default.post(name: Self.didChangeNotification, object: nil) }
        }
    }
    /// Reply decorations (Donutgram): colours = 1, emoji pattern = 2, background = 4. These mirror the
    /// "hide" switches in Extras; the chat reloads its messages when any of them changes.
    private var hideStickerReplyColorsValue = false
    private var hideStickerReplyEmojiValue = false
    private var hideStickerReplyBackgroundValue = false
    private var hidePremiumReplyEmojiValue = false

    public func setReplyDecorations(hideStickerColors: Bool, hideStickerEmoji: Bool, hideStickerBackground: Bool, hidePremiumEmoji: Bool) {
        self.locked {
            self.hideStickerReplyColorsValue = hideStickerColors
            self.hideStickerReplyEmojiValue = hideStickerEmoji
            self.hideStickerReplyBackgroundValue = hideStickerBackground
            self.hidePremiumReplyEmojiValue = hidePremiumEmoji
        }
    }

    public var hidesStickerReplyEmoji: Bool { return self.locked { self.hideStickerReplyEmojiValue } }
    public var hidesPremiumReplyEmoji: Bool { return self.locked { self.hidePremiumReplyEmojiValue } }

    public func replyDecorationOptions(isSticker: Bool) -> Int {
        return self.locked { () -> Int in
            var options = 7
            if isSticker {
                if self.hideStickerReplyColorsValue { options &= ~1 }
                if self.hideStickerReplyEmojiValue { options &= ~2 }
                if self.hideStickerReplyBackgroundValue { options &= ~4 }
            }
            if self.hidePremiumReplyEmojiValue { options &= ~2 }
            return options
        }
    }
}

