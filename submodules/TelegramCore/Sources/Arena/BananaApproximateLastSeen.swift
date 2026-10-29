import Foundation
import SwiftSignalKit

/// Fork (Donutgram): a person who hides their last seen is shown with the time of their latest activity that
/// reached this client, "last seen at ~14:22:05", instead of "last seen recently".
///
/// The activity is `TelegramUserPresence.lastActivity`, which the state replay already moves forward for an
/// incoming message (not an away or greeting one) and for the read of one of our messages. Only a presence the
/// server gave exists to be moved, so nothing here stores anything: it decides whether `lastActivity` may be shown.
public enum BananaApproximateLastSeen {
    private static let sinceDefaultsKey = "Banana.approximateLastSeenSince"
    private static let state = Atomic<Int32>(value: 0)

    /// How long the activity stays shown. Older, "recently" is the honest answer again.
    public static let maximumAge: Int32 = 3 * 24 * 60 * 60

    /// The moment the option was switched on, 0 while it is off. An activity from before it was recorded
    /// without the option, so it is not known to be the latest one the person has.
    public static var since: Int32 {
        return state.with { $0 }
    }

    /// Called whenever the settings change. Switching on remembers the moment; switching off forgets it,
    /// so a later switch-on does not trust what was seen in between.
    public static func update(enabled: Bool) {
        let defaults = UserDefaults.standard
        if enabled {
            var value = Int32(clamping: defaults.integer(forKey: self.sinceDefaultsKey))
            if value == 0 {
                value = Int32(clamping: Int(Date().timeIntervalSince1970))
                defaults.set(Int(value), forKey: self.sinceDefaultsKey)
            }
            let _ = state.swap(value)
        } else {
            defaults.removeObject(forKey: self.sinceDefaultsKey)
            let _ = state.swap(0)
        }
    }

    /// The activity time to show for a presence the server reports only as "recently", or nil.
    public static func timestamp(status: EnginePeer.Presence.Status, lastActivity: Int32, relativeTo now: Int32) -> Int32? {
        let since = self.since
        guard since != 0, case .recently = status else {
            return nil
        }
        let age = Int64(now) - Int64(lastActivity)
        guard lastActivity > since, age >= 0, age < Int64(self.maximumAge) else {
            return nil
        }
        return lastActivity
    }

    /// Seconds until the shown text changes: the next local midnight (the day in it changes) or the moment
    /// the activity gets too old, whichever is first.
    public static func refreshTimeout(activity: Int32, relativeTo now: Int32) -> Double {
        let nowDate = Date(timeIntervalSince1970: TimeInterval(now))
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: nowDate)) ?? nowDate.addingTimeInterval(24 * 60 * 60)
        let expiry = Double(activity) + Double(self.maximumAge) - Double(now)
        return max(1.0, min(midnight.timeIntervalSince(nowDate) + 1.0, expiry))
    }
}
