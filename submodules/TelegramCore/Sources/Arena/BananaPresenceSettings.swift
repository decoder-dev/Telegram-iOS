import Foundation
import SwiftSignalKit
import Postbox

public final class BananaPresenceSettings {
    public static let shared = BananaPresenceSettings()
    public static let didChangeNotification = ForkGhostModeSettings.didChangeNotification
    public static let lastOnlineDidChangeNotification = Notification.Name("BananaPresence.changed")
    public static let requestOfflineNotification = Notification.Name("BananaPresence.requestOffline")
    public static let serverReportedOfflineNotification = Notification.Name("BananaPresence.serverOffline")
    public static let serverReportedStatusNotification = Notification.Name("BananaPresence.serverStatus")
    public static let requestOfflineAccountPeerIdKey = "accountPeerId"
    public static let requestOfflineServerOnlineExpiresKey = "serverOnlineExpires"
    public static let serverOfflineWasOnlineKey = "serverOfflineWasOnline"
    private let defaults = UserDefaults.standard
    public var ghostModeEnabled: Bool { ForkGhostModeSettings.suppressOnline || ForkGhostModeSettings.goOfflineAutomatically }
    /// For a request not tied to one account: any open Read on Interact window lifts it.
    public var ghostAutomaticOffline: Bool { ForkGhostModeSettings.goOfflineAutomatically && !ForkGhostModeSettings.interactOverrideActive }
    public var ghostHidesOnline: Bool { ForkGhostModeSettings.shouldSuppressOnline || self.ghostAutomaticOffline }
    /// For one account: only a Read on Interact window opened in that account lifts it, so an action in one account does
    /// not show another one online (31 Oct audit, C-7).
    public func ghostAutomaticOffline(accountPeerId: PeerId) -> Bool {
        return ForkGhostModeSettings.goOfflineAutomatically && !ForkGhostModeSettings.interactOverrideActive(accountPeerId: accountPeerId)
    }
    public func ghostHidesOnline(accountPeerId: PeerId) -> Bool {
        return ForkGhostModeSettings.shouldSuppressOnline(accountPeerId: accountPeerId) || self.ghostAutomaticOffline(accountPeerId: accountPeerId)
    }
    private func accountKey(_ key: String, accountId: Int64) -> String { "BananaPresence.\(accountId).\(key)" }
    private func integer(_ key: String) -> Int { self.defaults.integer(forKey: key) }
    func requestGhostOffline(network: Network) {
        guard self.ghostAutomaticOffline else { return }
        NotificationCenter.default.post(name: Self.requestOfflineNotification, object: self, userInfo: ["network": network])
    }
    public func requestGhostOffline(accountPeerId: Int64? = nil, serverOnlineExpires: Int32? = nil) {
        guard self.ghostModeEnabled && self.ghostAutomaticOffline else { return }
        var userInfo: [AnyHashable: Any] = [:]
        if let accountPeerId {
            userInfo[BananaPresenceSettings.requestOfflineAccountPeerIdKey] = accountPeerId
        }
        if let serverOnlineExpires {
            userInfo[BananaPresenceSettings.requestOfflineServerOnlineExpiresKey] = serverOnlineExpires
        }
        NotificationCenter.default.post(name: BananaPresenceSettings.requestOfflineNotification, object: self, userInfo: userInfo)
    }

    /// Tells ghost mode the server reported the account offline, for the account with `accountPeerId`
    /// (`PeerId.toInt64()`), last online at `wasOnline`. Does nothing unless ghost mode's automatic offline is on.
    public func reportGhostServerOffline(accountPeerId: Int64, wasOnline: Int32) {
        guard self.ghostModeEnabled && self.ghostAutomaticOffline else { return }
        NotificationCenter.default.post(name: BananaPresenceSettings.serverReportedOfflineNotification, object: self, userInfo: [
            BananaPresenceSettings.requestOfflineAccountPeerIdKey: accountPeerId,
            BananaPresenceSettings.serverOfflineWasOnlineKey: wasOnline
        ])
    }

    /// Tells presence the server reported the status of the account with `accountPeerId` (`PeerId.toInt64()`):
    /// online until `onlineExpires`, or offline since `wasOnline`. The own profile shows it while ghost mode hides
    /// online, so another client's online is not lost. Does nothing otherwise.
    public func reportServerStatus(accountPeerId: Int64, onlineExpires: Int32? = nil, wasOnline: Int32? = nil) {
        guard self.ghostHidesOnline else { return }
        var userInfo: [AnyHashable: Any] = [BananaPresenceSettings.requestOfflineAccountPeerIdKey: accountPeerId]
        if let onlineExpires {
            userInfo[BananaPresenceSettings.requestOfflineServerOnlineExpiresKey] = onlineExpires
        }
        if let wasOnline {
            userInfo[BananaPresenceSettings.serverOfflineWasOnlineKey] = wasOnline
        }
        NotificationCenter.default.post(name: BananaPresenceSettings.serverReportedStatusNotification, object: self, userInfo: userInfo)
    }

    public func lastOnlineTimestamp(accountId: Int64) -> Int32? {
        let value = integer(accountKey("lastOnlineTimestamp", accountId: accountId))
        guard value > 0, let timestamp = Int32(exactly: value) else { return nil }
        return timestamp
    }

    public func setLastOnlineTimestamp(_ timestamp: Int32, accountId: Int64) {
        let key = accountKey("lastOnlineTimestamp", accountId: accountId)
        guard timestamp > 0, integer(key) != Int(timestamp) else { return }
        self.defaults.set(Int(timestamp), forKey: key)
        // Presence updates must not trigger another account.updateStatus request.
        NotificationCenter.default.post(name: BananaPresenceSettings.lastOnlineDidChangeNotification, object: self)
    }

    public func serverOnlineUntil(accountId: Int64) -> Int32? {
        let value = integer(accountKey("serverOnlineUntil", accountId: accountId))
        guard value > 0, let timestamp = Int32(exactly: value) else { return nil }
        return timestamp
    }

    public func setServerOnlineUntil(_ timestamp: Int32?, accountId: Int64) {
        let key = accountKey("serverOnlineUntil", accountId: accountId)
        let value = timestamp.flatMap { $0 > 0 ? Int($0) : nil } ?? 0
        guard integer(key) != value else { return }
        if value == 0 {
            self.defaults.removeObject(forKey: key)
        } else {
            self.defaults.set(value, forKey: key)
        }
        NotificationCenter.default.post(name: BananaPresenceSettings.lastOnlineDidChangeNotification, object: self)
    }

}
