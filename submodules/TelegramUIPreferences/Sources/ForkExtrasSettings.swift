import Foundation
import TelegramCore
import SwiftSignalKit

public enum ForkTranslationBackend: String, Codable {
    case `default`
    case system
}

public enum ForkTranscriptionBackend: String, Codable {
    case `default`
    case apple
}

/// Extra fork features (Ghost Mode, instant lock, notification filters, etc.).
public struct ForkExtrasSettings: Codable, Equatable {
    public var ghostMode: Bool
    public var instantPasscodeLock: Bool
    public var hideMentionNotifications: Bool
    public var hidePinnedNotifications: Bool
    public var sessionKeychainBackup: Bool
    public var compactChatList: Bool
    public var compactMessagePreview: Bool
    public var compactFolderNames: Bool
    public var hideReactionsBar: Bool
    public var showDC: Bool
    public var showProfileId: Bool
    public var accentColorSaturation: Int32
    public var confirmBeforeCall: Bool
    public var sendWithReturnKey: Bool
    public var forceBuiltInMic: Bool
    public var translationBackend: ForkTranslationBackend
    public var transcriptionBackend: ForkTranscriptionBackend
    public var scrollToNextChatDisabled: Bool
    /// AyuGram-style: keep text of remotely deleted messages (View Deleted).
    public var saveDeletedMessages: Bool
    /// AyuGram-style: keep previous text when a message is edited.
    public var saveMessagesHistory: Bool
    /// Also snapshot messages from bots when saving deleted/edited.
    public var saveForBots: Bool
    /// AyuGram Android parity: copy attachments into Saved Attachments on delete.
    public var saveMedia: Bool

    public static var defaultSettings: ForkExtrasSettings {
        return ForkExtrasSettings(
            ghostMode: false,
            instantPasscodeLock: false,
            hideMentionNotifications: false,
            hidePinnedNotifications: false,
            sessionKeychainBackup: true,
            compactChatList: false,
            compactMessagePreview: false,
            compactFolderNames: false,
            hideReactionsBar: false,
            showDC: false,
            showProfileId: false,
            accentColorSaturation: 100,
            confirmBeforeCall: false,
            sendWithReturnKey: false,
            forceBuiltInMic: false,
            translationBackend: .default,
            transcriptionBackend: .default,
            scrollToNextChatDisabled: false,
            saveDeletedMessages: true,
            saveMessagesHistory: true,
            saveForBots: false,
            saveMedia: true
        )
    }

    public init(
        ghostMode: Bool,
        instantPasscodeLock: Bool,
        hideMentionNotifications: Bool,
        hidePinnedNotifications: Bool,
        sessionKeychainBackup: Bool,
        compactChatList: Bool,
        compactMessagePreview: Bool,
        compactFolderNames: Bool,
        hideReactionsBar: Bool,
        showDC: Bool,
        showProfileId: Bool,
        accentColorSaturation: Int32,
        confirmBeforeCall: Bool,
        sendWithReturnKey: Bool,
        forceBuiltInMic: Bool,
        translationBackend: ForkTranslationBackend,
        transcriptionBackend: ForkTranscriptionBackend,
        scrollToNextChatDisabled: Bool,
        saveDeletedMessages: Bool,
        saveMessagesHistory: Bool,
        saveForBots: Bool,
        saveMedia: Bool = true
    ) {
        self.ghostMode = ghostMode
        self.instantPasscodeLock = instantPasscodeLock
        self.hideMentionNotifications = hideMentionNotifications
        self.hidePinnedNotifications = hidePinnedNotifications
        self.sessionKeychainBackup = sessionKeychainBackup
        self.compactChatList = compactChatList
        self.compactMessagePreview = compactMessagePreview
        self.compactFolderNames = compactFolderNames
        self.hideReactionsBar = hideReactionsBar
        self.showDC = showDC
        self.showProfileId = showProfileId
        self.accentColorSaturation = accentColorSaturation
        self.confirmBeforeCall = confirmBeforeCall
        self.sendWithReturnKey = sendWithReturnKey
        self.forceBuiltInMic = forceBuiltInMic
        self.translationBackend = translationBackend
        self.transcriptionBackend = transcriptionBackend
        self.scrollToNextChatDisabled = scrollToNextChatDisabled
        self.saveDeletedMessages = saveDeletedMessages
        self.saveMessagesHistory = saveMessagesHistory
        self.saveForBots = saveForBots
        self.saveMedia = saveMedia
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.ghostMode = try container.decodeIfPresent(Bool.self, forKey: "ghostMode") ?? false
        self.instantPasscodeLock = try container.decodeIfPresent(Bool.self, forKey: "instantPasscodeLock") ?? false
        self.hideMentionNotifications = try container.decodeIfPresent(Bool.self, forKey: "hideMentionNotifications") ?? false
        self.hidePinnedNotifications = try container.decodeIfPresent(Bool.self, forKey: "hidePinnedNotifications") ?? false
        // formattingPanel removed — ignore if present in older prefs.
        self.sessionKeychainBackup = try container.decodeIfPresent(Bool.self, forKey: "sessionKeychainBackup") ?? true
        self.compactChatList = try container.decodeIfPresent(Bool.self, forKey: "compactChatList") ?? false
        self.compactMessagePreview = try container.decodeIfPresent(Bool.self, forKey: "compactMessagePreview") ?? false
        self.compactFolderNames = try container.decodeIfPresent(Bool.self, forKey: "compactFolderNames") ?? false
        self.hideReactionsBar = try container.decodeIfPresent(Bool.self, forKey: "hideReactionsBar") ?? false
        self.showDC = try container.decodeIfPresent(Bool.self, forKey: "showDC") ?? false
        self.showProfileId = try container.decodeIfPresent(Bool.self, forKey: "showProfileId") ?? false
        self.accentColorSaturation = try container.decodeIfPresent(Int32.self, forKey: "accentColorSaturation") ?? 100
        self.confirmBeforeCall = try container.decodeIfPresent(Bool.self, forKey: "confirmBeforeCall") ?? false
        self.sendWithReturnKey = try container.decodeIfPresent(Bool.self, forKey: "sendWithReturnKey") ?? false
        self.forceBuiltInMic = try container.decodeIfPresent(Bool.self, forKey: "forceBuiltInMic") ?? false
        self.translationBackend = (try container.decodeIfPresent(String.self, forKey: "translationBackend")).flatMap(ForkTranslationBackend.init(rawValue:)) ?? .default
        self.transcriptionBackend = (try container.decodeIfPresent(String.self, forKey: "transcriptionBackend")).flatMap(ForkTranscriptionBackend.init(rawValue:)) ?? .default
        self.scrollToNextChatDisabled = try container.decodeIfPresent(Bool.self, forKey: "scrollToNextChatDisabled") ?? false
        self.saveDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: "saveDeletedMessages") ?? true
        self.saveMessagesHistory = try container.decodeIfPresent(Bool.self, forKey: "saveMessagesHistory") ?? true
        self.saveForBots = try container.decodeIfPresent(Bool.self, forKey: "saveForBots") ?? false
        self.saveMedia = try container.decodeIfPresent(Bool.self, forKey: "saveMedia") ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.ghostMode, forKey: "ghostMode")
        try container.encode(self.instantPasscodeLock, forKey: "instantPasscodeLock")
        try container.encode(self.hideMentionNotifications, forKey: "hideMentionNotifications")
        try container.encode(self.hidePinnedNotifications, forKey: "hidePinnedNotifications")
        try container.encode(self.sessionKeychainBackup, forKey: "sessionKeychainBackup")
        try container.encode(self.compactChatList, forKey: "compactChatList")
        try container.encode(self.compactMessagePreview, forKey: "compactMessagePreview")
        try container.encode(self.compactFolderNames, forKey: "compactFolderNames")
        try container.encode(self.hideReactionsBar, forKey: "hideReactionsBar")
        try container.encode(self.showDC, forKey: "showDC")
        try container.encode(self.showProfileId, forKey: "showProfileId")
        try container.encode(self.accentColorSaturation, forKey: "accentColorSaturation")
        try container.encode(self.confirmBeforeCall, forKey: "confirmBeforeCall")
        try container.encode(self.sendWithReturnKey, forKey: "sendWithReturnKey")
        try container.encode(self.forceBuiltInMic, forKey: "forceBuiltInMic")
        try container.encode(self.translationBackend.rawValue, forKey: "translationBackend")
        try container.encode(self.transcriptionBackend.rawValue, forKey: "transcriptionBackend")
        try container.encode(self.scrollToNextChatDisabled, forKey: "scrollToNextChatDisabled")
        try container.encode(self.saveDeletedMessages, forKey: "saveDeletedMessages")
        try container.encode(self.saveMessagesHistory, forKey: "saveMessagesHistory")
        try container.encode(self.saveForBots, forKey: "saveForBots")
        try container.encode(self.saveMedia, forKey: "saveMedia")
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
    
    private static func candidateSuites() -> [String] {
        var suites: [String] = []
        if let suite = Bundle.main.object(forInfoDictionaryKey: "AppGroupName") as? String {
            suites.append(suite)
        }
        if let bundleId = Bundle.main.bundleIdentifier {
            suites.append("group.\(bundleId)")
        }
        if let hinted = UserDefaults.standard.string(forKey: suiteHintKey) {
            suites.append(hinted)
        }
        var seen = Set<String>()
        return suites.filter { seen.insert($0).inserted }
    }
    
    public static func sync(_ settings: ForkExtrasSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.hideMentionNotifications, forKey: hideMentionsKey)
        defaults.set(settings.hidePinnedNotifications, forKey: hidePinnedKey)
        for suite in candidateSuites() {
            defaults.set(suite, forKey: suiteHintKey)
            if let shared = UserDefaults(suiteName: suite) {
                shared.set(settings.hideMentionNotifications, forKey: hideMentionsKey)
                shared.set(settings.hidePinnedNotifications, forKey: hidePinnedKey)
                shared.synchronize()
            }
        }
        defaults.synchronize()
    }
    
    private static func bool(forKey key: String) -> Bool {
        // OR across stores — sideload often lacks a working App Group; NSE may only
        // see one of the suites. Prefer "hide if any store says hide".
        if UserDefaults.standard.bool(forKey: key) {
            return true
        }
        for suite in candidateSuites() {
            if let shared = UserDefaults(suiteName: suite), shared.bool(forKey: key) {
                return true
            }
        }
        return false
    }
    
    public static var hideMentionNotifications: Bool {
        return bool(forKey: hideMentionsKey)
    }
    
    public static var hidePinnedNotifications: Bool {
        return bool(forKey: hidePinnedKey)
    }
}
