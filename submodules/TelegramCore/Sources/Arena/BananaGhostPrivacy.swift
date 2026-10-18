// Adapted from kittenello/Donutgram PR79; existing BananaGram ghost policies remain authoritative.
import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

public enum ForkTelegramStatisticsSettings {
    /// Mirrored to UserDefaults like the other Ghost flags: the real setting arrives through an asynchronous read, and
    /// until then messages sent right after a cold launch would go out immediately instead of being delayed.
    private static let persistedKey = "ForkTelegramStatisticsSettings.enabled.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

func bananaRequestGhostOfflineAfterAction(network: Network) {
    BananaPresenceSettings.shared.requestGhostOffline(network: network)
}

func bananaGhostDropsScreenshotNotifications(_ messages: [(Bool, EnqueueMessage)]) -> Bool {
    guard !messages.isEmpty, ForkGhostModeSettings.shouldSuppressMessageReads else { return false }
    return messages.allSatisfy { entry in
        if case let .message(_, _, _, mediaReference, _, _, _, _, _, _) = entry.1,
           let action = mediaReference?.media as? TelegramMediaAction, case .historyScreenshot = action.action { return true }
        return false
    }
}

func bananaGhostScheduleAllowed(peerNamespace: PeerId.Namespace, hasUserSchedule: Bool, isQuickReply: Bool) -> Bool {
    return peerNamespace != Namespaces.Peer.SecretChat && !hasUserSchedule && !isQuickReply
        && ForkGhostScheduleSettings.enabled && ForkGhostModeSettings.suppressMessageReads
        && ForkGhostModeSettings.suppressStoryViews && ForkGhostModeSettings.suppressOutgoingActivity
        && ForkGhostModeSettings.suppressOnline && ForkGhostModeSettings.goOfflineAutomatically
}

/// Donutgram "ghostSendWithoutSound": while full Ghost Mode is on, outgoing messages go out without a notification.
public enum ForkGhostSilentSendSettings {
    /// Mirrored to UserDefaults like the other Ghost flags, so a send right after a cold launch is already silent.
    private static let persistedKey = "ForkGhostSilentSendSettings.enabled.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
            }
        }
    }
}

/// Full Ghost Mode is the same five flags `bananaGhostScheduleAllowed` requires.
func bananaGhostSendsSilently() -> Bool {
    return ForkGhostSilentSendSettings.enabled && ForkGhostModeSettings.suppressMessageReads
        && ForkGhostModeSettings.suppressStoryViews && ForkGhostModeSettings.suppressOutgoingActivity
        && ForkGhostModeSettings.suppressOnline && ForkGhostModeSettings.goOfflineAutomatically
}

public enum ForkRemovePingsSettings {
    /// Mirrored to UserDefaults like the other Ghost flags: the real setting arrives through an asynchronous read, and
    /// until then messages sent right after a cold launch would go out immediately instead of being delayed.
    private static let persistedKey = "ForkRemovePingsSettings.enabled.v1"
    private static let value = Atomic<Bool>(value: UserDefaults.standard.bool(forKey: persistedKey))
    public static let changed = Notification.Name("ForkRemovePingsSettings.changed")
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set {
            let previous = value.swap(newValue)
            if previous != newValue {
                UserDefaults.standard.set(newValue, forKey: persistedKey)
                NotificationCenter.default.post(name: changed, object: nil)
            }
        }
    }
}

public func bananaRemovePingsEnabled() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: ForkRemovePingsSettings.changed, object: nil, queue: nil) { _ in subscriber.putNext(ForkRemovePingsSettings.enabled) }
        subscriber.putNext(ForkRemovePingsSettings.enabled)
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    } |> distinctUntilChanged
}
