import Foundation
import SwiftSignalKit

/// Which camera a round video message opens with. Adapted from Donutgram's round video camera choice: the chat
/// composer used to always open the front camera.
public enum BananaRoundVideoCamera {
    private struct State {
        var startsWithRear = false
        var remembersLast = false
    }

    private static let state = Atomic<State>(value: State())
    private static let lastWasRearKey = "BananaRoundVideoCamera.lastWasRear"

    /// Open with the rear camera.
    public static var startsWithRear: Bool {
        get { return state.with { $0.startsWithRear } }
        set { let _ = state.modify { var value = $0; value.startsWithRear = newValue; return value } }
    }

    /// Open with whichever camera the last round video used; `startsWithRear` decides until there is one.
    public static var remembersLast: Bool {
        get { return state.with { $0.remembersLast } }
        set { let _ = state.modify { var value = $0; value.remembersLast = newValue; return value } }
    }

    /// The camera the last round video was recorded with; nil before the first.
    public static var lastWasRear: Bool? {
        get {
            return UserDefaults.standard.object(forKey: lastWasRearKey) as? Bool
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: lastWasRearKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastWasRearKey)
            }
        }
    }

    public static var opensWithRear: Bool {
        let (startsWithRear, remembersLast) = state.with { ($0.startsWithRear, $0.remembersLast) }
        if remembersLast, let lastWasRear = self.lastWasRear {
            return lastWasRear
        }
        return startsWithRear
    }

    /// Called whenever the camera in use is known, including when it is flipped.
    public static func noteCameraInUse(isRear: Bool) {
        if self.remembersLast {
            self.lastWasRear = isRear
        }
    }
}
