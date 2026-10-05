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
    
    public func isShadowBanRevealed(chatPeerId: Int64) -> Bool {
        return defaults.bool(forKey: "shadowBanRevealed_\(chatPeerId)")
    }
    
    public func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64) {
        defaults.set(revealed, forKey: "shadowBanRevealed_\(chatPeerId)")
        NotificationCenter.default.post(name: ArenaSettings.shadowBanDidChangeNotification, object: nil)
    }
    
    public var semiTransparentDeletedMessages: Bool { return true }
}
