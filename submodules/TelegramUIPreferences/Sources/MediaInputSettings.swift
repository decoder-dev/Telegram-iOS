import Foundation
import TelegramCore
import SwiftSignalKit

public struct MediaInputSettings: Codable, Equatable {
    public let enableRaiseToSpeak: Bool
    public let pauseMusicOnRecording: Bool
    public let pauseMusicOnVoiceRecording: Bool
    public let pauseMusicOnVoicePlayback: Bool
    
    public static var defaultSettings: MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: true, pauseMusicOnRecording: true)
    }
    
    public init(enableRaiseToSpeak: Bool, pauseMusicOnRecording: Bool, pauseMusicOnVoiceRecording: Bool = true, pauseMusicOnVoicePlayback: Bool = true) {
        self.enableRaiseToSpeak = enableRaiseToSpeak
        self.pauseMusicOnRecording = pauseMusicOnRecording
        self.pauseMusicOnVoiceRecording = pauseMusicOnVoiceRecording
        self.pauseMusicOnVoicePlayback = pauseMusicOnVoicePlayback
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.pauseMusicOnVoiceRecording = try container.decodeIfPresent(Bool.self, forKey: "pauseMusicOnVoiceRecording") ?? true
        self.pauseMusicOnVoicePlayback = try container.decodeIfPresent(Bool.self, forKey: "pauseMusicOnVoicePlayback") ?? true
        self.enableRaiseToSpeak = (try container.decode(Int32.self, forKey: "enableRaiseToSpeak")) != 0
        self.pauseMusicOnRecording = (try container.decodeIfPresent(Int32.self, forKey: "pauseMusicOnRecording_v2") ?? 1) != 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.pauseMusicOnVoiceRecording, forKey: "pauseMusicOnVoiceRecording")
        try container.encode(self.pauseMusicOnVoicePlayback, forKey: "pauseMusicOnVoicePlayback")
        try container.encode((self.enableRaiseToSpeak ? 1 : 0) as Int32, forKey: "enableRaiseToSpeak")
        try container.encode((self.pauseMusicOnRecording ? 1 : 0) as Int32, forKey: "pauseMusicOnRecording_v2")
    }
    
    public static func ==(lhs: MediaInputSettings, rhs: MediaInputSettings) -> Bool {
        return lhs.enableRaiseToSpeak == rhs.enableRaiseToSpeak && lhs.pauseMusicOnRecording == rhs.pauseMusicOnRecording && lhs.pauseMusicOnVoiceRecording == rhs.pauseMusicOnVoiceRecording && lhs.pauseMusicOnVoicePlayback == rhs.pauseMusicOnVoicePlayback
    }
    
    public func withUpdatedEnableRaiseToSpeak(_ enableRaiseToSpeak: Bool) -> MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: enableRaiseToSpeak, pauseMusicOnRecording: self.pauseMusicOnRecording, pauseMusicOnVoiceRecording: self.pauseMusicOnVoiceRecording, pauseMusicOnVoicePlayback: self.pauseMusicOnVoicePlayback)
    }
    
    public func withUpdatedPauseMusicOnRecording(_ pauseMusicOnRecording: Bool) -> MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: self.enableRaiseToSpeak, pauseMusicOnRecording: pauseMusicOnRecording, pauseMusicOnVoiceRecording: self.pauseMusicOnVoiceRecording, pauseMusicOnVoicePlayback: self.pauseMusicOnVoicePlayback)
    }

    public func withUpdatedVoiceMusicPolicy(recording: Bool? = nil, playback: Bool? = nil) -> MediaInputSettings {
        return MediaInputSettings(enableRaiseToSpeak: self.enableRaiseToSpeak, pauseMusicOnRecording: self.pauseMusicOnRecording, pauseMusicOnVoiceRecording: recording ?? self.pauseMusicOnVoiceRecording, pauseMusicOnVoicePlayback: playback ?? self.pauseMusicOnVoicePlayback)
    }
}

public func updateMediaInputSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (MediaInputSettings) -> MediaInputSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.mediaInputSettings, { entry in
            let currentSettings: MediaInputSettings
            if let entry = entry?.get(MediaInputSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = MediaInputSettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}

// Shared preferences are global across accounts. Audio queues read one atomic snapshot.
public enum BananaAudioPolicy {
    private static let value = Atomic<MediaInputSettings>(value: .defaultSettings)
    public static var current: MediaInputSettings {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}
