import Foundation
import TelegramUIPreferences

/// Extras settings to a JSON file and back (Regram, Nekogram, exteraGram). The file holds a small header and the
/// settings as ForkExtrasSettings encodes them, so a file from an older or newer build still imports: keys this
/// build doesn't know are ignored, missing ones keep their current value.
enum BananaSettingsBackup {
    static let appName = "BananaGram"

    /// Never written to the file and never taken from one:
    /// - localVerificationBadges (stored as the "Ids"/"Values" pair): keyed by the account's local record id, which
    ///   means nothing on another device;
    /// - the duress passcode's action and its account ids: also local record ids, and a file must never be able to
    ///   arm "Erase All Data" without the confirmation the Duress Passcode page asks for;
    /// - enhancedPowerSaving and its snapshot: they describe this device's saved animation settings;
    /// - sessionKeychainBackup: an old switch that was about this device's Keychain;
    /// - anything named like an API key, token or password (the translators' keys, say): those are the user's secrets.
    /// Passcodes and hidden accounts are not Extras settings at all, so they are never in the file.
    private static let excludedKeys: Set<String> = [
        "localVerificationBadges",
        "localVerificationBadgesIds",
        "localVerificationBadgesValues",
        "duressPasscodeAction",
        "duressLogOutAccountIds",
        "enhancedPowerSaving",
        "enhancedPowerSavingSnapshot",
        "sessionKeychainBackup",
    ]

    static func isExcluded(_ key: String) -> Bool {
        if excludedKeys.contains(key) {
            return true
        }
        let lowercased = key.lowercased()
        return lowercased.contains("apikey") || lowercased.contains("token") || lowercased.contains("password")
    }

    private static func jsonObject(_ settings: ForkExtrasSettings) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(settings) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func settings(from object: [String: Any]) -> ForkExtrasSettings? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(ForkExtrasSettings.self, from: data)
    }

    static func exportData(_ settings: ForkExtrasSettings) -> Data? {
        guard var object = jsonObject(settings) else {
            return nil
        }
        for key in object.keys where isExcluded(key) {
            object.removeValue(forKey: key)
        }
        let file: [String: Any] = [
            "app": appName,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "settings": object
        ]
        return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
    }

    /// The settings part of a BananaGram settings file, without the keys that are never imported; nil if it isn't one.
    static func importedValues(from data: Data) -> [String: Any]? {
        guard let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], file["app"] as? String == appName, let values = file["settings"] as? [String: Any] else {
            return nil
        }
        return values.filter { !isExcluded($0.key) }
    }

    /// `current` with the imported values laid over it. A value of the wrong type (a hand-edited file) is skipped
    /// rather than failing the whole import.
    static func apply(_ values: [String: Any], to current: ForkExtrasSettings) -> ForkExtrasSettings {
        guard var object = jsonObject(current) else {
            return current
        }
        let known = Set(object.keys)
        for (key, value) in values where known.contains(key) {
            var candidate = object
            candidate[key] = value
            if settings(from: candidate) != nil {
                object = candidate
            }
        }
        return settings(from: object) ?? current
    }

    /// How many settings differ, as stored, between two values.
    static func changeCount(from current: ForkExtrasSettings, to updated: ForkExtrasSettings) -> Int {
        guard let lhs = jsonObject(current), let rhs = jsonObject(updated) else {
            return 0
        }
        return Set(lhs.keys).union(rhs.keys).filter { key in
            return (lhs[key] as? NSObject) != (rhs[key] as? NSObject)
        }.count
    }
}
