import Foundation
import TelegramCore
import SwiftSignalKit

/// Extra fork features (Ghost Mode, instant lock, notification filters, etc.).
public struct ForkExtrasSettings: Codable, Equatable {
    public var ghostMode: Bool
    public var instantPasscodeLock: Bool
    public var hideMentionNotifications: Bool
    public var hidePinnedNotifications: Bool
    public var formattingPanel: Bool
    public var sessionKeychainBackup: Bool
    
    public static var defaultSettings: ForkExtrasSettings {
        return ForkExtrasSettings(
            ghostMode: false,
            instantPasscodeLock: false,
            hideMentionNotifications: false,
            hidePinnedNotifications: false,
            formattingPanel: true,
            sessionKeychainBackup: true
        )
    }
    
    public init(
        ghostMode: Bool,
        instantPasscodeLock: Bool,
        hideMentionNotifications: Bool,
        hidePinnedNotifications: Bool,
        formattingPanel: Bool,
        sessionKeychainBackup: Bool
    ) {
        self.ghostMode = ghostMode
        self.instantPasscodeLock = instantPasscodeLock
        self.hideMentionNotifications = hideMentionNotifications
        self.hidePinnedNotifications = hidePinnedNotifications
        self.formattingPanel = formattingPanel
        self.sessionKeychainBackup = sessionKeychainBackup
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.ghostMode = try container.decodeIfPresent(Bool.self, forKey: "ghostMode") ?? false
        self.instantPasscodeLock = try container.decodeIfPresent(Bool.self, forKey: "instantPasscodeLock") ?? false
        self.hideMentionNotifications = try container.decodeIfPresent(Bool.self, forKey: "hideMentionNotifications") ?? false
        self.hidePinnedNotifications = try container.decodeIfPresent(Bool.self, forKey: "hidePinnedNotifications") ?? false
        self.formattingPanel = try container.decodeIfPresent(Bool.self, forKey: "formattingPanel") ?? true
        self.sessionKeychainBackup = try container.decodeIfPresent(Bool.self, forKey: "sessionKeychainBackup") ?? true
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.ghostMode, forKey: "ghostMode")
        try container.encode(self.instantPasscodeLock, forKey: "instantPasscodeLock")
        try container.encode(self.hideMentionNotifications, forKey: "hideMentionNotifications")
        try container.encode(self.hidePinnedNotifications, forKey: "hidePinnedNotifications")
        try container.encode(self.formattingPanel, forKey: "formattingPanel")
        try container.encode(self.sessionKeychainBackup, forKey: "sessionKeychainBackup")
    }
}

public func updateForkExtrasSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (ForkExtrasSettings) -> ForkExtrasSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.forkExtrasSettings, { entry in
            let current: ForkExtrasSettings
            if let entry = entry?.get(ForkExtrasSettings.self) {
                current = entry
            } else {
                current = .defaultSettings
            }
            let updated = f(current)
            ForkExtrasNotificationBridge.sync(updated)
            return SharedPreferencesEntry(updated)
        })
    }
}

public func forkExtrasSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<ForkExtrasSettings, NoError> {
    return accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.forkExtrasSettings])
    |> map { sharedData -> ForkExtrasSettings in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.forkExtrasSettings]?.get(ForkExtrasSettings.self) ?? .defaultSettings
    }
}

/// NSE-readable flags (App Group / standard UserDefaults). AccountManager is not available in NSE.
public enum ForkExtrasNotificationBridge {
    private static let suiteHintKey = "ForkExtras.AppGroupSuite"
    private static let hideMentionsKey = "ForkExtras.hideMentionNotifications"
    private static let hidePinnedKey = "ForkExtras.hidePinnedNotifications"
    
    public static func sync(_ settings: ForkExtrasSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.hideMentionNotifications, forKey: hideMentionsKey)
        defaults.set(settings.hidePinnedNotifications, forKey: hidePinnedKey)
        if let suite = Bundle.main.object(forInfoDictionaryKey: "AppGroupName") as? String
            ?? Bundle.main.bundleIdentifier.map({ "group.\($0)" }) {
            defaults.set(suite, forKey: suiteHintKey)
            if let shared = UserDefaults(suiteName: suite) {
                shared.set(settings.hideMentionNotifications, forKey: hideMentionsKey)
                shared.set(settings.hidePinnedNotifications, forKey: hidePinnedKey)
            }
        }
    }
    
    public static var hideMentionNotifications: Bool {
        if let suite = UserDefaults.standard.string(forKey: suiteHintKey),
           let shared = UserDefaults(suiteName: suite) {
            return shared.bool(forKey: hideMentionsKey)
        }
        return UserDefaults.standard.bool(forKey: hideMentionsKey)
    }
    
    public static var hidePinnedNotifications: Bool {
        if let suite = UserDefaults.standard.string(forKey: suiteHintKey),
           let shared = UserDefaults(suiteName: suite) {
            return shared.bool(forKey: hidePinnedKey)
        }
        return UserDefaults.standard.bool(forKey: hidePinnedKey)
    }
}
