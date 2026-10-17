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
            // "Disable coloured replies": every reply header drops its peer name colours.
            if self.disableColoredRepliesValue { options &= ~1 }
            return options
        }
    }

    /// Chat appearance switches (Donutgram), projected from ForkExtrasSettings by
    /// `applyForkChatAppearanceSettings`. All default off, which is the stock look.
    private var commaAfterMentionValue = false
    private var disableColoredRepliesValue = false
    private var hideStickerChecksValue = false
    private var mentionAvatarsValue = false
    private var disableCustomBackgroundsValue = false
    private var channelBottomDiscussValue = false
    private var hideChannelBottomButtonValue = false
    private var hideShareButtonValue = false

    public func setChatAppearance(commaAfterMention: Bool, disableColoredReplies: Bool, hideStickerChecks: Bool, mentionAvatars: Bool, disableCustomBackgrounds: Bool, channelBottomDiscuss: Bool, hideChannelBottomButton: Bool, hideShareButton: Bool) {
        self.locked {
            self.commaAfterMentionValue = commaAfterMention
            self.disableColoredRepliesValue = disableColoredReplies
            self.hideStickerChecksValue = hideStickerChecks
            self.mentionAvatarsValue = mentionAvatars
            self.disableCustomBackgroundsValue = disableCustomBackgrounds
            self.channelBottomDiscussValue = channelBottomDiscuss
            self.hideChannelBottomButtonValue = hideChannelBottomButton
            self.hideShareButtonValue = hideShareButton
        }
    }

    /// What mention autocomplete puts after the inserted mention: ", " for a person when the
    /// "comma after mention" switch is on, a plain space otherwise (and always for a bot).
    public func mentionSuffix(isBot: Bool) -> String {
        return self.locked { self.commaAfterMentionValue && !isBot ? ", " : " " }
    }
    public var disablesColoredReplies: Bool { return self.locked { self.disableColoredRepliesValue } }
    public var hidesStickerChecks: Bool { return self.locked { self.hideStickerChecksValue } }
    public var showsMentionAvatars: Bool { return self.locked { self.mentionAvatarsValue } }
    public var disablesCustomBackgrounds: Bool { return self.locked { self.disableCustomBackgroundsValue } }
    public var channelBottomButtonDiscusses: Bool { return self.locked { self.channelBottomDiscussValue } }
    public var hidesChannelBottomButton: Bool { return self.locked { self.hideChannelBottomButtonValue } }
    public var hidesShareButton: Bool { return self.locked { self.hideShareButtonValue } }

    /// Liquid Glass message bubbles (Glassgram port), projected from ForkExtrasSettings by
    /// `applyForkChatAppearanceSettings`. Off by default. The levels are percentages; the bubble
    /// item node reads them at layout time and the open chat re-lays out when they change.
    private var glassBubblesValue = false
    private var glassBubbleLevelsValue: (tint: Int32, rimTop: Int32, rimSides: Int32, rimBottom: Int32) = (25, 95, 20, 55)

    public func setGlassBubbles(enabled: Bool, tint: Int32, rimTop: Int32, rimSides: Int32, rimBottom: Int32) {
        self.locked {
            self.glassBubblesValue = enabled
            self.glassBubbleLevelsValue = (tint, rimTop, rimSides, rimBottom)
        }
    }

    public var glassBubblesEnabled: Bool { return self.locked { self.glassBubblesValue } }
    public var glassBubbleLevels: (tint: Int32, rimTop: Int32, rimSides: Int32, rimBottom: Int32) { return self.locked { self.glassBubbleLevelsValue } }
}

