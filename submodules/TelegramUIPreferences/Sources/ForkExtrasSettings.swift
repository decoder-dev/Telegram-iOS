import Foundation
import TelegramCore
import SwiftSignalKit
import Postbox

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
    /// Whether recently-used emoji feed the reaction picker. Off leaves the picker's top group as
    /// the standard reaction set — or, in a channel that limits reactions, exactly that set.
    public var useRecentEmojiInReactions: Bool
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
    /// AyuGram Android: actively fetch not-yet-local media before TTL/delete can race the cache.
    public var proactiveSaveMedia: Bool
    /// Customizable deleted-message mark (default 🧹).
    public var deletedMessageMark: String
    /// Customizable edited-message mark. Empty keeps Telegram's default "edited" label.
    public var editedMessageMark: String
    /// AyuGram AyuForward: re-upload noforwards / deleted messages as new content (no author). Default on.
    public var ayuForward: Bool
    /// AyuGram Desktop: No Copy & Download Restrictions — save stories / protected media without Premium.
    public var bypassDownloadRestrictions: Bool
    /// AyuGram Local Telegram Premium: unlock client-side Premium-gated UX (stealth mode, HD stories,
    /// sticker/emoji cosmetics) without touching the account's real Premium status. Default off — opt-in.
    public var localPremium: Bool
    /// Hide sponsored / recommended ads in chats (AyuGram disableAds).
    public var hideAds: Bool
    /// AyuGram Message Filters: hide messages (and typing) from blocked users.
    public var hideBlockedMessages: Bool
    /// AyuGram: allow screenshots in secret chats / secret media and suppress peer notify.
    public var allowSecretScreenshots: Bool
    /// AyuGram: tap the TTL flame in the secret-media viewer to expire (delete) now.
    public var expireTtlButton: Bool
    /// AyuGram: keep banned/kicked chats in the chat list / cache.
    public var keepBannedChats: Bool
    /// AyuGram Message Filters: enable global regex filters.
    public var regexMessageFiltersEnabled: Bool
    /// AyuGram Message Filters: case-insensitive regex matching (default on).
    public var regexMessageFiltersCaseInsensitive: Bool
    /// AyuGram Message Filters: one NSRegularExpression pattern per entry.
    public var regexMessageFilterPatterns: [String]
    /// AyuGram Ghost Schedule Messages: delay-send via scheduled messages when full Ghost Mode is on.
    public var ghostScheduleMessages: Bool
    /// Hide the "All Chats" folder tab when other folders exist.
    public var hideAllChats: Bool
    /// Restore the last opened chat-list folder after launch / account switch.
    public var rememberLastFolder: Bool
    /// Hide the root tab bar (Chats / Contacts / Settings).
    public var hideTabBar: Bool
    /// Append seconds to message timestamps in chat.
    public var showMessageSeconds: Bool
    /// Use a wider bubble fill factor (channel / group posts).
    public var wideChannelPosts: Bool
    /// Sticker display size as a percent of the default 184pt (50...150).
    public var stickerSizePercent: Int32
    /// Double-tap an outgoing message to edit instead of reacting.
    public var doubleTapToEdit: Bool
    /// Always offer Translate in the message menu, even if chat-level translate is off.
    public var quickTranslateButton: Bool
    /// Extra context-menu item: copy a message into Saved Messages.
    public var saveToCloudMenu: Bool
    /// Extra context-menu item: start selection of loaded messages from the same author.
    public var selectFromAuthor: Bool
    /// Larger FetchV2 parts / more in-flight chunks for faster downloads.
    public var downloadSpeedBoost: Bool
    /// Outgoing photo send quality: 0 = Telegram default (1280), 1 = better (1920), 2 = maximum (2560).
    public var outgoingPhotoQuality: Int32
    /// Hide own phone number and @username on profile and the Settings header (AyuGram Streamer Mode).
    public var streamerMode: Bool

    public static var defaultSettings: ForkExtrasSettings {
        return ForkExtrasSettings(
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
            sessionKeychainBackup: false,
            compactChatList: false,
            compactMessagePreview: false,
            compactFolderNames: false,
            hideReactionsBar: false,
            useRecentEmojiInReactions: true,
            showDC: false,
            showProfileId: false,
            accentColorSaturation: 100,
            confirmBeforeCall: false,
            sendWithReturnKey: false,
            forceBuiltInMic: false,
            translationBackend: .default,
            transcriptionBackend: .default,
            scrollToNextChatDisabled: false,
            saveDeletedMessages: false,
            saveMessagesHistory: false,
            saveForBots: false,
            saveMedia: false,
            proactiveSaveMedia: false,
            deletedMessageMark: MessageSavingBridge.defaultDeletedMark,
            editedMessageMark: "",
            ayuForward: true,
            bypassDownloadRestrictions: false,
            localPremium: false,
            hideAds: true,
            hideBlockedMessages: false,
            allowSecretScreenshots: false,
            expireTtlButton: true,
            keepBannedChats: true,
            regexMessageFiltersEnabled: false,
            regexMessageFiltersCaseInsensitive: true,
            regexMessageFilterPatterns: [],
            ghostScheduleMessages: false,
            hideAllChats: false,
            rememberLastFolder: false,
            hideTabBar: false,
            showMessageSeconds: false,
            wideChannelPosts: false,
            stickerSizePercent: 100,
            doubleTapToEdit: false,
            quickTranslateButton: false,
            saveToCloudMenu: true,
            selectFromAuthor: true,
            downloadSpeedBoost: false,
            outgoingPhotoQuality: 0,
            streamerMode: false
        )
    }

    public init(
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
        useRecentEmojiInReactions: Bool,
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
        saveMedia: Bool = false,
        proactiveSaveMedia: Bool = false,
        deletedMessageMark: String = MessageSavingBridge.defaultDeletedMark,
        editedMessageMark: String = "",
        ayuForward: Bool = true,
        bypassDownloadRestrictions: Bool = false,
        localPremium: Bool = false,
        hideAds: Bool = true,
        hideBlockedMessages: Bool = false,
        allowSecretScreenshots: Bool = false,
        expireTtlButton: Bool = true,
        keepBannedChats: Bool = true,
        regexMessageFiltersEnabled: Bool = false,
        regexMessageFiltersCaseInsensitive: Bool = true,
        regexMessageFilterPatterns: [String] = [],
        ghostScheduleMessages: Bool = false,
        hideAllChats: Bool = false,
        rememberLastFolder: Bool = false,
        hideTabBar: Bool = false,
        showMessageSeconds: Bool = false,
        wideChannelPosts: Bool = false,
        stickerSizePercent: Int32 = 100,
        doubleTapToEdit: Bool = false,
        quickTranslateButton: Bool = false,
        saveToCloudMenu: Bool = true,
        selectFromAuthor: Bool = true,
        downloadSpeedBoost: Bool = false,
        outgoingPhotoQuality: Int32 = 0,
        streamerMode: Bool = false
    ) {
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
        self.useRecentEmojiInReactions = useRecentEmojiInReactions
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
        self.proactiveSaveMedia = proactiveSaveMedia
        self.deletedMessageMark = deletedMessageMark
        self.editedMessageMark = editedMessageMark
        self.ayuForward = ayuForward
        self.bypassDownloadRestrictions = bypassDownloadRestrictions
        self.localPremium = localPremium
        self.hideAds = hideAds
        self.hideBlockedMessages = hideBlockedMessages
        self.allowSecretScreenshots = allowSecretScreenshots
        self.expireTtlButton = expireTtlButton
        self.keepBannedChats = keepBannedChats
        self.regexMessageFiltersEnabled = regexMessageFiltersEnabled
        self.regexMessageFiltersCaseInsensitive = regexMessageFiltersCaseInsensitive
        self.regexMessageFilterPatterns = regexMessageFilterPatterns
        self.ghostScheduleMessages = ghostScheduleMessages
        self.hideAllChats = hideAllChats
        self.rememberLastFolder = rememberLastFolder
        self.hideTabBar = hideTabBar
        self.showMessageSeconds = showMessageSeconds
        self.wideChannelPosts = wideChannelPosts
        self.stickerSizePercent = min(150, max(50, stickerSizePercent))
        self.doubleTapToEdit = doubleTapToEdit
        self.quickTranslateButton = quickTranslateButton
        self.saveToCloudMenu = saveToCloudMenu
        self.selectFromAuthor = selectFromAuthor
        self.downloadSpeedBoost = downloadSpeedBoost
        self.outgoingPhotoQuality = min(2, max(0, outgoingPhotoQuality))
        self.streamerMode = streamerMode
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
        self.instantPasscodeLock = try container.decodeIfPresent(Bool.self, forKey: "instantPasscodeLock") ?? false
        self.hideMentionNotifications = try container.decodeIfPresent(Bool.self, forKey: "hideMentionNotifications") ?? false
        self.hidePinnedNotifications = try container.decodeIfPresent(Bool.self, forKey: "hidePinnedNotifications") ?? false
        self.sessionKeychainBackup = try container.decodeIfPresent(Bool.self, forKey: "sessionKeychainBackup") ?? false
        self.compactChatList = try container.decodeIfPresent(Bool.self, forKey: "compactChatList") ?? false
        self.compactMessagePreview = try container.decodeIfPresent(Bool.self, forKey: "compactMessagePreview") ?? false
        self.compactFolderNames = try container.decodeIfPresent(Bool.self, forKey: "compactFolderNames") ?? false
        self.hideReactionsBar = try container.decodeIfPresent(Bool.self, forKey: "hideReactionsBar") ?? false
        self.useRecentEmojiInReactions = try container.decodeIfPresent(Bool.self, forKey: "useRecentEmojiInReactions") ?? true
        self.showDC = try container.decodeIfPresent(Bool.self, forKey: "showDC") ?? false
        self.showProfileId = try container.decodeIfPresent(Bool.self, forKey: "showProfileId") ?? false
        self.accentColorSaturation = try container.decodeIfPresent(Int32.self, forKey: "accentColorSaturation") ?? 100
        self.confirmBeforeCall = try container.decodeIfPresent(Bool.self, forKey: "confirmBeforeCall") ?? false
        self.sendWithReturnKey = try container.decodeIfPresent(Bool.self, forKey: "sendWithReturnKey") ?? false
        self.forceBuiltInMic = try container.decodeIfPresent(Bool.self, forKey: "forceBuiltInMic") ?? false
        self.translationBackend = (try container.decodeIfPresent(String.self, forKey: "translationBackend")).flatMap(ForkTranslationBackend.init(rawValue:)) ?? .default
        self.transcriptionBackend = (try container.decodeIfPresent(String.self, forKey: "transcriptionBackend")).flatMap(ForkTranscriptionBackend.init(rawValue:)) ?? .default
        self.scrollToNextChatDisabled = try container.decodeIfPresent(Bool.self, forKey: "scrollToNextChatDisabled") ?? false
        self.saveDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: "saveDeletedMessages") ?? false
        self.saveMessagesHistory = try container.decodeIfPresent(Bool.self, forKey: "saveMessagesHistory") ?? false
        self.saveForBots = try container.decodeIfPresent(Bool.self, forKey: "saveForBots") ?? false
        self.saveMedia = try container.decodeIfPresent(Bool.self, forKey: "saveMedia") ?? false
        // Default off: proactive gallery fetch on every open was a major thermal/IO load.
        self.proactiveSaveMedia = try container.decodeIfPresent(Bool.self, forKey: "proactiveSaveMedia") ?? false
        self.deletedMessageMark = try container.decodeIfPresent(String.self, forKey: "deletedMessageMark") ?? MessageSavingBridge.defaultDeletedMark
        self.editedMessageMark = try container.decodeIfPresent(String.self, forKey: "editedMessageMark") ?? ""
        self.ayuForward = try container.decodeIfPresent(Bool.self, forKey: "ayuForward") ?? true
        self.bypassDownloadRestrictions = try container.decodeIfPresent(Bool.self, forKey: "bypassDownloadRestrictions") ?? false
        self.localPremium = try container.decodeIfPresent(Bool.self, forKey: "localPremium") ?? false
        self.hideAds = try container.decodeIfPresent(Bool.self, forKey: "hideAds") ?? true
        self.hideBlockedMessages = try container.decodeIfPresent(Bool.self, forKey: "hideBlockedMessages") ?? false
        self.allowSecretScreenshots = try container.decodeIfPresent(Bool.self, forKey: "allowSecretScreenshots") ?? false
        self.expireTtlButton = try container.decodeIfPresent(Bool.self, forKey: "expireTtlButton") ?? true
        self.keepBannedChats = try container.decodeIfPresent(Bool.self, forKey: "keepBannedChats") ?? true
        self.regexMessageFiltersEnabled = try container.decodeIfPresent(Bool.self, forKey: "regexMessageFiltersEnabled") ?? false
        self.regexMessageFiltersCaseInsensitive = try container.decodeIfPresent(Bool.self, forKey: "regexMessageFiltersCaseInsensitive") ?? true
        self.regexMessageFilterPatterns = try container.decodeIfPresent([String].self, forKey: "regexMessageFilterPatterns") ?? []
        self.ghostScheduleMessages = try container.decodeIfPresent(Bool.self, forKey: "ghostScheduleMessages") ?? false
        self.hideAllChats = try container.decodeIfPresent(Bool.self, forKey: "hideAllChats") ?? false
        self.rememberLastFolder = try container.decodeIfPresent(Bool.self, forKey: "rememberLastFolder") ?? false
        self.hideTabBar = try container.decodeIfPresent(Bool.self, forKey: "hideTabBar") ?? false
        self.showMessageSeconds = try container.decodeIfPresent(Bool.self, forKey: "showMessageSeconds") ?? false
        self.wideChannelPosts = try container.decodeIfPresent(Bool.self, forKey: "wideChannelPosts") ?? false
        self.stickerSizePercent = min(150, max(50, try container.decodeIfPresent(Int32.self, forKey: "stickerSizePercent") ?? 100))
        self.doubleTapToEdit = try container.decodeIfPresent(Bool.self, forKey: "doubleTapToEdit") ?? false
        self.quickTranslateButton = try container.decodeIfPresent(Bool.self, forKey: "quickTranslateButton") ?? false
        self.saveToCloudMenu = try container.decodeIfPresent(Bool.self, forKey: "saveToCloudMenu") ?? true
        self.selectFromAuthor = try container.decodeIfPresent(Bool.self, forKey: "selectFromAuthor") ?? true
        self.downloadSpeedBoost = try container.decodeIfPresent(Bool.self, forKey: "downloadSpeedBoost") ?? false
        self.outgoingPhotoQuality = min(2, max(0, try container.decodeIfPresent(Int32.self, forKey: "outgoingPhotoQuality") ?? 0))
        self.streamerMode = try container.decodeIfPresent(Bool.self, forKey: "streamerMode") ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        // Legacy: true when full Ghost Mode (5 flags including stories + go-offline) is on.
        try container.encode(self.ghostMode, forKey: "ghostMode")
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
        try container.encode(self.useRecentEmojiInReactions, forKey: "useRecentEmojiInReactions")
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
        try container.encode(self.proactiveSaveMedia, forKey: "proactiveSaveMedia")
        try container.encode(self.deletedMessageMark, forKey: "deletedMessageMark")
        try container.encode(self.editedMessageMark, forKey: "editedMessageMark")
        try container.encode(self.ayuForward, forKey: "ayuForward")
        try container.encode(self.bypassDownloadRestrictions, forKey: "bypassDownloadRestrictions")
        try container.encode(self.localPremium, forKey: "localPremium")
        try container.encode(self.hideAds, forKey: "hideAds")
        try container.encode(self.hideBlockedMessages, forKey: "hideBlockedMessages")
        try container.encode(self.allowSecretScreenshots, forKey: "allowSecretScreenshots")
        try container.encode(self.expireTtlButton, forKey: "expireTtlButton")
        try container.encode(self.keepBannedChats, forKey: "keepBannedChats")
        try container.encode(self.regexMessageFiltersEnabled, forKey: "regexMessageFiltersEnabled")
        try container.encode(self.regexMessageFiltersCaseInsensitive, forKey: "regexMessageFiltersCaseInsensitive")
        try container.encode(self.regexMessageFilterPatterns, forKey: "regexMessageFilterPatterns")
        try container.encode(self.ghostScheduleMessages, forKey: "ghostScheduleMessages")
        try container.encode(self.hideAllChats, forKey: "hideAllChats")
        try container.encode(self.rememberLastFolder, forKey: "rememberLastFolder")
        try container.encode(self.hideTabBar, forKey: "hideTabBar")
        try container.encode(self.showMessageSeconds, forKey: "showMessageSeconds")
        try container.encode(self.wideChannelPosts, forKey: "wideChannelPosts")
        try container.encode(self.stickerSizePercent, forKey: "stickerSizePercent")
        try container.encode(self.doubleTapToEdit, forKey: "doubleTapToEdit")
        try container.encode(self.quickTranslateButton, forKey: "quickTranslateButton")
        try container.encode(self.saveToCloudMenu, forKey: "saveToCloudMenu")
        try container.encode(self.selectFromAuthor, forKey: "selectFromAuthor")
        try container.encode(self.downloadSpeedBoost, forKey: "downloadSpeedBoost")
        try container.encode(self.outgoingPhotoQuality, forKey: "outgoingPhotoQuality")
        try container.encode(self.streamerMode, forKey: "streamerMode")
    }

    /// Whether message/reaction read receipts should be suppressed right now.
    public var suppressesMessageReads: Bool {
        return self.ghostDontReadMessages
    }

    /// Full Ghost Mode (AyuGram `setGhostMode`): dont-read messages + stories + dont-online + dont-typing + go-offline.
    ///
    /// The single definition. `ghostMode` was a stored mirror of this expression, re-derived by
    /// hand in six places — decode, encode, the memberwise init and three settings mutations —
    /// and read by nothing: Ghost Mode itself is driven from the raw flags in
    /// `SharedAccountContext`. A stored copy of a derived value is only ever one forgotten
    /// assignment away from disagreeing with what it mirrors, so it is computed now.
    public var isFullGhostMode: Bool {
        return self.ghostDontReadMessages && self.ghostDontReadStories && self.ghostDontSendOnline && self.ghostDontSendTyping && self.ghostGoOfflineAutomatically
    }

    /// AyuGram `setGhostMode`: flip the five master flags together. Other ghost options are left alone.
    public mutating func setFullGhostMode(_ enabled: Bool) {
        self.ghostDontReadMessages = enabled
        self.ghostDontReadStories = enabled
        self.ghostDontSendOnline = enabled
        self.ghostDontSendTyping = enabled
        self.ghostGoOfflineAutomatically = enabled
    }

    /// Legacy encoding key, kept so a build that predates the granular ghost flags still
    /// reads a coherent value out of the stored blob. Never a source of truth.
    public var ghostMode: Bool {
        return self.isFullGhostMode
    }

    /// Own-identity mask used on profile / Settings header when Streamer Mode is on.
    public static var streamerHiddenLabel: String {
        return ForkPresentationLanguage.prefersRussianStrings ? "Скрыто" : "Hidden"
    }

    /// AyuGram "Add filter": escape selected text as a literal regex pattern, enable filters, append if new.
    public func appendingRegexFilterPattern(fromSelectedText selectedText: String, maxPatterns: Int = 64) -> (settings: ForkExtrasSettings, added: Bool) {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (self, false)
        }
        let pattern = NSRegularExpression.escapedPattern(for: trimmed)
        guard !pattern.isEmpty, pattern.utf16.count <= 512 else {
            return (self, false)
        }
        var updated = self
        updated.regexMessageFiltersEnabled = true
        if updated.regexMessageFilterPatterns.contains(pattern) {
            return (updated, false)
        }
        var patterns = updated.regexMessageFilterPatterns
        patterns.append(pattern)
        if patterns.count > maxPatterns {
            patterns = Array(patterns.suffix(maxPatterns))
        }
        updated.regexMessageFilterPatterns = patterns
        return (updated, true)
    }
}

/// Last opened chat-list folder. Stored in UserDefaults so swiping folders does not rewrite AccountManager prefs.
public enum ForkLastChatListFilter {
    private static let legacyKey = "ForkExtras.lastChatListFilterId"
    
    private static func key(accountPeerId: EnginePeer.Id) -> String {
        return "ForkExtras.lastChatListFilterId.\(accountPeerId.toInt64())"
    }
    
    /// `0` = All Chats, otherwise the folder id.
    public static func storedId(accountPeerId: EnginePeer.Id) -> Int32 {
        let accountKey = key(accountPeerId: accountPeerId)
        if UserDefaults.standard.object(forKey: accountKey) != nil {
            return Int32(UserDefaults.standard.integer(forKey: accountKey))
        }
        // One-shot migrate the pre-account-scoped value so a single-account install keeps its folder.
        if UserDefaults.standard.object(forKey: legacyKey) != nil {
            let migrated = Int32(UserDefaults.standard.integer(forKey: legacyKey))
            UserDefaults.standard.set(Int(migrated), forKey: accountKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return migrated
        }
        return 0
    }
    
    public static func setStoredId(_ id: Int32, accountPeerId: EnginePeer.Id) {
        let accountKey = key(accountPeerId: accountPeerId)
        let current = storedId(accountPeerId: accountPeerId)
        guard current != id else {
            return
        }
        UserDefaults.standard.set(Int(id), forKey: accountKey)
    }
}

/// Mask own phone / @username at display sites. Chat titles are intentionally not gated.
public func forkHidesOwnIdentity(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, settings: ForkExtrasSettings) -> Bool {
    return accountPeerId == peerId && (ForkExtrasHotFlags.streamerMode || settings.streamerMode)
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
            // NSE bridge sync is owned by SharedAccountContext (single writer, change-gated).
            return SharedPreferencesEntry(f(current))
        })
    }
}

public func forkExtrasSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<ForkExtrasSettings, NoError> {
    return accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.forkExtrasSettings])
    |> map { sharedData -> ForkExtrasSettings in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.forkExtrasSettings]?.get(ForkExtrasSettings.self) ?? .defaultSettings
    }
}

/// Compiled AyuGram-style regex message filters.
/// Patterns are compiled once when Extras settings change — never on the chat-history rebuild path.
public enum ForkRegexMessageFilters {
    private struct Fingerprint: Equatable {
        var enabled: Bool
        var caseInsensitive: Bool
        var patterns: [String]
    }

    private struct Snapshot {
        var fingerprint: Fingerprint
        var regexes: [NSRegularExpression]
        var revision: UInt64
    }

    /// Cap matching input to keep pathological patterns from burning CPU/heat on huge messages.
    private static let maxMatchUTF16Length = 4096
    /// Per-part budgets for the input `matches(message:)` synthesises. They must sum to less than
    /// `maxMatchUTF16Length` (plus room for the short `<type>N</type>` tail) so that every part —
    /// most importantly the trailing tag — lands inside the window ICU actually searches.
    private static let maxMessageTextMatchUTF16Length = 3072
    private static let maxButtonPayloadMatchUTF16Length = 768
    /// Soft cap so a huge pasted list cannot explode compile / match cost.
    private static let maxPatterns = 64

    private static let snapshot = Atomic<Snapshot>(value: Snapshot(
        fingerprint: Fingerprint(enabled: false, caseInsensitive: true, patterns: []),
        regexes: [],
        revision: 0
    ))

    public static func apply(enabled: Bool, caseInsensitive: Bool, patterns: [String]) {
        let fingerprint = Fingerprint(enabled: enabled, caseInsensitive: caseInsensitive, patterns: patterns)
        // Skip compile if fingerprint unchanged (read outside any write lock).
        if snapshot.with({ $0.fingerprint == fingerprint }) {
            return
        }
        guard enabled else {
            let _ = snapshot.modify { current in
                return Snapshot(fingerprint: fingerprint, regexes: [], revision: current.revision &+ 1)
            }
            return
        }
        // Compile outside the Atomic lock so matching readers are never blocked on ICU.
        var options: NSRegularExpression.Options = []
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }
        var regexes: [NSRegularExpression] = []
        regexes.reserveCapacity(min(patterns.count, maxPatterns))
        for pattern in patterns.prefix(maxPatterns) {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            // Bound pattern size — pathological lengths are a free DoS of the main process.
            guard trimmed.utf16.count <= 512 else {
                continue
            }
            if let regex = try? NSRegularExpression(pattern: trimmed, options: options) {
                regexes.append(regex)
            }
        }
        // Last writer wins — a superseded compile is rare (settings edits) and harmless.
        let _ = snapshot.modify { current in
            return Snapshot(fingerprint: fingerprint, regexes: regexes, revision: current.revision &+ 1)
        }
    }

    /// Immutable snapshot for one history rebuild (take once before the message loop).
    public static func currentSnapshot() -> (active: Bool, regexes: [NSRegularExpression], revision: UInt64) {
        return snapshot.with { current in
            let active = current.fingerprint.enabled && !current.regexes.isEmpty
            return (active, active ? current.regexes : [], current.revision)
        }
    }

    /// True when filters are enabled and at least one compiled pattern is ready.
    public static var isActive: Bool {
        return snapshot.with { !$0.regexes.isEmpty && $0.fingerprint.enabled }
    }

    /// Returns true if `text` matches any compiled filter (AyuGram `Pattern.matcher.find()`).
    public static func matches(_ text: String, regexes: [NSRegularExpression]? = nil) -> Bool {
        let expressions: [NSRegularExpression]
        if let regexes {
            expressions = regexes
        } else {
            let current = currentSnapshot()
            guard current.active else {
                return false
            }
            expressions = current.regexes
        }
        guard !expressions.isEmpty, !text.isEmpty else {
            return false
        }
        let nsText = text as NSString
        let length = min(nsText.length, maxMatchUTF16Length)
        guard length > 0 else {
            return false
        }
        let range = NSRange(location: 0, length: length)
        for regex in expressions {
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// Match the same useful payload AyuGram exposes to filters: message text plus inline-button
    /// titles and links, plus a trailing `<type>N</type>` tag (AyuGram Android's
    /// `MessageObject.TYPE_*` constants). The resulting input is still bounded by `matches`
    /// before ICU sees it.
    public static func matches(message: EngineMessage, regexes: [NSRegularExpression]? = nil) -> Bool {
        var buttons = ""
        for attribute in message.attributes {
            guard let replyMarkup = attribute as? ReplyMarkupMessageAttribute else {
                continue
            }
            for row in replyMarkup.rows {
                for button in row.buttons {
                    buttons.append("\n<button>")
                    buttons.append(button.title)
                    switch button.action {
                    case let .url(url):
                        buttons.append("\n")
                        buttons.append(url)
                    case let .urlAuth(url, _):
                        buttons.append("\n")
                        buttons.append(url)
                    default:
                        break
                    }
                    buttons.append("</button>")
                }
            }
        }
        // Bound the text and button payloads separately, before concatenating. `matches(_:)` only
        // searches the first `maxMatchUTF16Length` UTF-16 units, so bounding at the end would let a
        // long message push the `<type>N</type>` tag — the whole point of the synthesised input —
        // past the search window and silently disable every `<type>` filter on exactly the
        // messages a user is most likely to filter.
        var input = boundedPrefix(message.text, utf16Limit: maxMessageTextMatchUTF16Length)
        input.append(boundedPrefix(buttons, utf16Limit: maxButtonPayloadMatchUTF16Length))
        input.append("\n<type>")
        input.append(String(ayuMessageTypeConstant(for: message)))
        input.append("</type>")
        return matches(input, regexes: regexes)
    }

    /// UTF-16-bounded prefix that never splits a composed character sequence (or a surrogate pair).
    private static func boundedPrefix(_ text: String, utf16Limit: Int) -> String {
        let nsText = text as NSString
        guard nsText.length > utf16Limit else {
            return text
        }
        var end = utf16Limit
        let composed = nsText.rangeOfComposedCharacterSequence(at: end)
        if composed.location < end {
            end = composed.location
        }
        guard end > 0 else {
            return ""
        }
        return nsText.substring(to: end)
    }

    /// Approximate AyuGram Android `MessageObject.TYPE_*` constant for `<type>N</type>` filters.
    /// Not a byte-for-byte port of `MessageObject.updateMessageType()` — just enough of the common
    /// cases (photo/video/round-video/voice/gif/sticker/music/file/geo/contact/poll) that
    /// AyuGram-style `<type>N</type>` patterns copied from another client remain useful here.
    private static func ayuMessageTypeConstant(for message: EngineMessage) -> Int {
        for media in message.media {
            if media is TelegramMediaImage {
                return 1 // TYPE_PHOTO
            }
            if let file = media as? TelegramMediaFile {
                if file.isVoice {
                    return 2 // TYPE_VOICE
                }
                if file.isInstantVideo {
                    return 5 // TYPE_ROUND_VIDEO
                }
                if file.isVideo {
                    return 3 // TYPE_VIDEO
                }
                if file.isAnimated {
                    return 8 // TYPE_GIF
                }
                if file.isAnimatedSticker {
                    return 15 // TYPE_ANIMATED_STICKER
                }
                if file.isSticker {
                    return 13 // TYPE_STICKER
                }
                if file.isMusic {
                    return 14 // TYPE_MUSIC
                }
                return 9 // TYPE_FILE
            }
            if media is TelegramMediaMap {
                return 4 // TYPE_GEO
            }
            if media is TelegramMediaContact {
                return 12 // TYPE_CONTACT
            }
            if media is TelegramMediaPoll {
                return 17 // TYPE_POLL
            }
        }
        return 0 // TYPE_TEXT
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
            // The NSE's bundle id is "<app bundle id>.NotificationService", and the extension
            // itself derives its app group by stripping the last path component (see
            // NotificationService.swift's baseAppBundleId) — which is also what the main app's
            // plain "group.<bundleId>" candidate computes to. Mirror that derivation so both
            // processes land on the SAME suite: without the stripped candidate the extension
            // only looked in "group.<…>.NotificationService", which the app never writes, and
            // the hide-mention/hide-pinned flags never reached the NSE. The raw candidate is
            // kept too (it is the app-side target, and empty elsewhere).
            if let lastDotRange = bundleId.range(of: ".", options: [.backwards]) {
                suites.append("group.\(bundleId[..<lastDotRange.lowerBound])")
            }
            suites.append("group.\(bundleId)")
        }
        if let hinted = UserDefaults.standard.string(forKey: suiteHintKey) {
            suites.append(hinted)
        }
        var seen = Set<String>()
        return suites.filter { seen.insert($0).inserted }
    }
    
    private static let lastSynced = Atomic<(hideMentions: Bool, hidePinned: Bool)?>(value: nil)

    /// Project notification-hide flags into App Group / standard defaults for NSE.
    /// Change-gated and without `synchronize()` — `set` is enough and avoids main-thread disk stalls.
    public static func sync(_ settings: ForkExtrasSettings) {
        let next = (hideMentions: settings.hideMentionNotifications, hidePinned: settings.hidePinnedNotifications)
        var shouldWrite = false
        let _ = lastSynced.modify { previous in
            if previous?.hideMentions == next.hideMentions, previous?.hidePinned == next.hidePinned {
                return previous
            }
            shouldWrite = true
            return next
        }
        guard shouldWrite else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(next.hideMentions, forKey: hideMentionsKey)
        defaults.set(next.hidePinned, forKey: hidePinnedKey)
        for suite in candidateSuites() {
            defaults.set(suite, forKey: suiteHintKey)
            if let shared = UserDefaults(suiteName: suite) {
                shared.set(next.hideMentions, forKey: hideMentionsKey)
                shared.set(next.hidePinned, forKey: hidePinnedKey)
            }
        }
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
