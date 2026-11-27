import Foundation

/// Profile v2 presentation toggles, persisted per device.
public enum GhostSettings {
    public static var profileV2: Bool {
        get {
            if UserDefaults.standard.object(forKey: "GhostProfileV2") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "GhostProfileV2")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "GhostProfileV2")
        }
    }

    public static var glassProfile: Bool {
        get {
            if UserDefaults.standard.object(forKey: "GhostGlassProfile") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "GhostGlassProfile")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "GhostGlassProfile")
        }
    }
}
