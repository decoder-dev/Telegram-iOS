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
    /// Legacy single Ghost Mode toggle. Still encoded for older builds; granular flags are source of truth.
    /// When true in old prefs (no granular keys), it seeds dont-read / dont-online / dont-typing.
    public var ghostMode: Bool
    /// AyuGram: Don't Read Messages — suppress read receipts / seen reactions while browsing.
    public var ghostDontReadMessages: Bool
    /// AyuGram: Don't Read Stories — suppress story view increments.
    public var ghostDontReadStories: Bool
    /// AyuGram: Don't Send Online — never report online status.
    public var ghostDontSendOnline: Bool
    /// AyuGram: Don't Send Typing — suppress typing / upload / sticker activity.
    public var ghostDontSendTyping: Bool
    /// AyuGram: Go Offline Automatically — after any online blink, immediately go offline again.
    public var ghostGoOfflineAutomatically: Bool
    /// AyuGram: Read on Interact — when dont-read is on, mark read (and briefly appear online) after send/react.
    public var ghostReadOnInteract: Bool
    /// AyuGram: Alert Before Opening Story — confirm before opening any story viewer.
    public var ghostAlertBeforeOpeningStory: Bool
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
    /// AyuGram AyuForward: re-upload noforwards / deleted messages as new content (no author). Default on.
    public var ayuForward: Bool

    public static var defaultSettings: ForkExtrasSettings {
        return ForkExtrasSettings(
            ghostMode: false,
            ghostDontReadMessages: false,
            ghostDontReadStories: false,
            ghostDontSendOnline: false,
            ghostDontSendTyping: false,
            ghostGoOfflineAutomatically: false,
            ghostReadOnInteract: false,
            ghostAlertBeforeOpeningStory: false,
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
            saveMedia: true,
            ayuForward: true
        )
    }

    public init(
        ghostMode: Bool,
        ghostDontReadMessages: Bool,
        ghostDontReadStories: Bool,
        ghostDontSendOnline: Bool,
        ghostDontSendTyping: Bool,
        ghostGoOfflineAutomatically: Bool,
        ghostReadOnInteract: Bool,
        ghostAlertBeforeOpeningStory: Bool,
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
        saveMedia: Bool = true,
        ayuForward: Bool = true
    ) {
        self.ghostMode = ghostMode
        self.ghostDontReadMessages = ghostDontReadMessages
        self.ghostDontReadStories = ghostDontReadStories
        self.ghostDontSendOnline = ghostDontSendOnline
        self.ghostDontSendTyping = ghostDontSendTyping
        self.ghostGoOfflineAutomatically = ghostGoOfflineAutomatically
        self.ghostReadOnInteract = ghostReadOnInteract
        self.ghostAlertBeforeOpeningStory = ghostAlertBeforeOpeningStory
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
        self.ayuForward = ayuForward
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let legacyGhost = try container.decodeIfPresent(Bool.self, forKey: "ghostMode") ?? false
        self.ghostDontReadMessages = try container.decodeIfPresent(Bool.self, forKey: "ghostDontReadMessages") ?? legacyGhost
        self.ghostDontReadStories = try container.decodeIfPresent(Bool.self, forKey: "ghostDontReadStories") ?? false
        self.ghostDontSendOnline = try container.decodeIfPresent(Bool.self, forKey: "ghostDontSendOnline") ?? legacyGhost
        self.ghostDontSendTyping = try container.decodeIfPresent(Bool.self, forKey: "ghostDontSendTyping") ?? legacyGhost
        self.ghostGoOfflineAutomatically = try container.decodeIfPresent(Bool.self, forKey: "ghostGoOfflineAutomatically") ?? false
        self.ghostReadOnInteract = try container.decodeIfPresent(Bool.self, forKey: "ghostReadOnInteract") ?? false
        self.ghostAlertBeforeOpeningStory = try container.decodeIfPresent(Bool.self, forKey: "ghostAlertBeforeOpeningStory") ?? false
        // Keep legacy field in sync so older readers / encodings stay coherent.
        self.ghostMode = self.ghostDontReadMessages && self.ghostDontSendOnline && self.ghostDontSendTyping
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
        self.ayuForward = try container.decodeIfPresent(Bool.self, forKey: "ayuForward") ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        // Legacy: true only when the original three core flags are all on.
        try container.encode(self.ghostDontReadMessages && self.ghostDontSendOnline && self.ghostDontSendTyping, forKey: "ghostMode")
        try container.encode(self.ghostDontReadMessages, forKey: "ghostDontReadMessages")
        try container.encode(self.ghostDontReadStories, forKey: "ghostDontReadStories")
        try container.encode(self.ghostDontSendOnline, forKey: "ghostDontSendOnline")
        try container.encode(self.ghostDontSendTyping, forKey: "ghostDontSendTyping")
        try container.encode(self.ghostGoOfflineAutomatically, forKey: "ghostGoOfflineAutomatically")
        try container.encode(self.ghostReadOnInteract, forKey: "ghostReadOnInteract")
        try container.encode(self.ghostAlertBeforeOpeningStory, forKey: "ghostAlertBeforeOpeningStory")
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
        try container.encode(self.ayuForward, forKey: "ayuForward")
    }

    /// Whether message/reaction read receipts should be suppressed right now.
    public var suppressesMessageReads: Bool {
        return self.ghostDontReadMessages
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
