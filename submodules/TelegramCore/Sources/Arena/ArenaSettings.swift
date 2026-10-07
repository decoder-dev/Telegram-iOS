import Foundation

public class ArenaSettings {
    public static let shared = ArenaSettings()
    public static let shadowBanDidChangeNotification = Notification.Name("ArenaSettings_shadowBanDidChangeNotification")
    
    private let defaults = UserDefaults(suiteName: "group.ph.teleg.Telegrapf") ?? UserDefaults.standard
    
    public var shadowBannedPeerIds: [Int64] {
        get { return defaults.array(forKey: "shadowBannedPeerIds") as? [Int64] ?? [] }
        set { defaults.set(newValue, forKey: "shadowBannedPeerIds") }
    }
    
    public var hasShadowBans: Bool {
        return !shadowBannedPeerIds.isEmpty
    }
    
    public func isShadowBanned(_ peerId: Int64) -> Bool {
        return shadowBannedPeerIds.contains(peerId)
    }
    
    public func setShadowBanned(_ banned: Bool, peerId: Int64) {
        var list = shadowBannedPeerIds
        if banned {
            if !list.contains(peerId) { list.append(peerId) }
        } else {
            list.removeAll(where: { $0 == peerId })
        }
        shadowBannedPeerIds = list
        NotificationCenter.default.post(name: ArenaSettings.shadowBanDidChangeNotification, object: nil)
    }
    
    public var shadowBanRevealedChatIds: [Int64] {
        get { return defaults.array(forKey: "shadowBanRevealedChatIds") as? [Int64] ?? [] }
        set { defaults.set(newValue, forKey: "shadowBanRevealedChatIds") }
    }
    
    public func isShadowBanRevealed(chatPeerId: Int64) -> Bool {
        return shadowBanRevealedChatIds.contains(chatPeerId)
    }
    
    public func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64) {
        var list = shadowBanRevealedChatIds
        if revealed {
            if !list.contains(chatPeerId) { list.append(chatPeerId) }
        } else {
            list.removeAll(where: { $0 == chatPeerId })
        }
        shadowBanRevealedChatIds = list
        NotificationCenter.default.post(name: ArenaSettings.shadowBanDidChangeNotification, object: nil)
    }
    
    public var semiTransparentDeletedMessages: Bool { return true }
    public var avatarGlow: Bool { return true }
    public var stickerReplyOptions: Int { return 7 }
}

