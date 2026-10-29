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
    public var removePings: Bool
    public var sendTelegramStatistics: Bool
    public var bananaIslandEnabled: Bool
    public var bananaIslandShowsName: Bool
    /// Fork (Donutgram): the island takes the colours of the current app icon instead of the theme's accent.
    public var bananaIslandFollowsIcon: Bool
    public var wideTabBar: Bool
    public var integratedTabSearch: Bool
    public var tabSearchOnLeft: Bool
    public var bottomChatFoldersEnabled: Bool
    public var avatarGlowEnabled: Bool
    public var snowEnabled: Bool
    public var showChannelForwardCount: Bool
    public var reactionGlowEnabled: Bool
    public var showContactsTab: Bool
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
    public var keepAliveInBackground: Bool
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
    /// Remove known tracking parameters from ordinary outgoing text links. Opt-in.
    public var stripTrackingParameters: Bool
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
    /// Fork (Donutgram): no time or delivery ticks over a sticker; a sticker that carries reactions keeps them.
    public var hideStickerStatus: Bool
    /// Donutgram: reply decorations on stickers (colours, emoji pattern, background) and the pattern in replies to premium contacts.
    public var hideStickerReplyColors: Bool
    /// Regram: after joining a group or channel, offer to add it to a chat folder. Off by default.
    public var chooseFolderAfterJoin: Bool
    /// Regram: the chat back button remembers the last 50 opened chats and lists them on long press. Off by default.
    public var recentChatsMenu: Bool
    /// Regram: "Bookmark" in the message menu, with tags, kept on this device. Off by default.
    public var messageBookmarks: Bool
    /// Regram: a local-only name for a group or channel, set from its profile menu. Off by default.
    public var localGroupAlias: Bool
    /// Donutgram: a swipe to the right on the chat list, and pulling the stories row past its start, no longer open
    /// the story camera. The other ways to post a story are unchanged. Off by default.
    public var disableStoryCameraSwipe: Bool
    /// Donutgram: "Jump to start" in the menu of a chat's (or forum topic's) avatar. On by default.
    public var jumpToStartInChatMenu: Bool
    /// Donutgram: leave joins, leaves and edits of the chat (title, photo, pin, timers, polls, to-do lists) out of the history. Off by default.
    public var hideServiceMessages: Bool
    /// Donutgram: ask before adding a reaction in a channel or group the account has not joined. Off by default.
    public var confirmReactionsInUnjoinedChats: Bool
    /// Donutgram: ask before a link that opens inside Telegram (t.me, tg:) is followed from a message, a bio or another app. Off by default.
    public var confirmTelegramLinks: Bool
    /// Ask before a `tg://msg_url`, `tg://msg` or `t.me/share` link opens its prefilled message (on by default: such links are
    /// how a worm spreads itself through a user's contacts).
    public var confirmShareLinks: Bool
    /// Donutgram: ask before a tap on a previewed chat (long press in the list) opens it. Off by default.
    public var confirmChatPreviewEntry: Bool
    public var disableGiftStarsRedirect: Bool
    public var visualLabels: [Int64: Int32]
    public var hideStickerReplyEmoji: Bool
    public var hideStickerReplyBackground: Bool
    public var hidePremiumReplyEmoji: Bool
    /// Fork (Donutgram): profile and identity display switches. Display only; peer data is never changed.
    public var showChatCreationDate: Bool
    public var profileIdBotApiFormat: Bool
    public var showMutualContact: Bool
    public var hidePremiumStatuses: Bool
    public var hideVerification: Bool
    public var hideGiftButton: Bool
    public var visualPhoneEnabled: Bool
    public var visualPhoneNumber: String
    /// Donutgram: ghost send silently, suggest Don't Read Stories before a story, hide the stories row / archive row, screenshots in copy-protected chats.
    public var ghostSendWithoutSound: Bool
    public var ghostSuggestForStories: Bool
    public var hideStories: Bool
    public var hideArchive: Bool
    public var allowProtectedScreenshots: Bool
    /// Fork (Donutgram): media, sticker and playback options, projected into `BananaMediaTweaks`.
    public var accelerateUpload: Bool
    public var infiniteRecentStickers: Bool
    public var onlyAddedStickers: Bool
    public var autoPauseMediaInBackground: Bool
    /// 0, 5, 10, 15 or 30; 0 turns double-tap seeking off.
    public var doubleTapSeekSeconds: Int32
    /// Regram port: show the message id in the status line of group and channel messages.
    public var showMessageId: Bool
    /// Regram port: text spoilers, spoiler media and gallery captions are shown without a tap.
    public var autoRevealSpoilers: Bool
    /// Regram port: what a double tap on a message does. 0 off (the stock reaction), 1 react, 2 reply,
    /// 3 repeat, 4 translate, 6 edit. Replaces `doubleTapToEdit`, which is still read (and written) for older builds.
    public var doubleTapAction: Int32
    /// Regram port: "Repeat", "Repeat without quote" and "Forward without author" in the message menu.
    public var repeatMessageMenu: Bool
    public var staticRoundVideoZoom: Bool
    /// 0: stock, 1: rounded, 2: more rounded.
    public var stickerShape: Int32
    /// Donutgram chat appearance: ", " after an autocompleted non-bot mention; reply headers without
    /// name colours; no read checks on stickers; avatars drawn in mentions; profile last-seen kept
    /// relative; per-chat wallpapers/themes ignored; channel bottom bar shows Discuss or nothing;
    /// no quick share button beside messages.
    public var commaAfterMention: Bool
    public var disableColoredReplies: Bool
    public var hideStickerChecks: Bool
    public var mentionAvatars: Bool
    public var relativeLastSeen: Bool
    /// Fork (Donutgram): a person who hides their last seen shows the time of their latest activity, `last seen at ~14:22`.
    public var approximateLastSeen: Bool
    /// Fork (Donutgram): a sticker goes out without the reference to its set, so the recipient cannot open the set.
    public var anonymousStickers: Bool
    /// The profile grows out of the chat's header when opened from it (Telegram 13.1.1's expansion). Off: the plain slide.
    public var profileExpansionAnimation: Bool
    public var disableCustomBackgrounds: Bool
    public var channelBottomDiscuss: Bool
    public var hideChannelBottomButton: Bool
    public var hideShareButton: Bool
    /// Fork (Glassgram port): chat bubbles are drawn as iOS 26 Liquid Glass tinted with the theme's bubble
    /// colour. Off by default; below iOS 26 the switch has no effect. The levels are percentages.
    public var glassBubbles: Bool
    public var glassBubbleTint: Int32
    public var glassBubbleRimTop: Int32
    public var glassBubbleRimSides: Int32
    public var glassBubbleRimBottom: Int32
    /// Fork (Donutgram): remember another profile's gifts and show the ones that later disappeared (BananaSpyStorage).
    public var showDisappearedGifts: Bool
    /// Fork (Donutgram): round video messages open with the rear camera, or with the one the last one used.
    public var roundVideoStartsWithRear: Bool
    public var roundVideoRemembersCamera: Bool
    /// Fork (Donutgram): the chat list title is never replaced by "Connecting…", and carries no emoji status.
    public var chatListHidesConnectionStatus: Bool
    public var chatListHidesEmojiStatus: Bool
    public var chatListCentersTitle: Bool
    public var chatListHidesSearch: Bool
    /// Fork (Donutgram): a poll shows its results before the viewer has voted and can still be voted in.
    public var pollResultsBeforeVoting: Bool
    /// Fork (Donutgram): last seen shows the time of day instead of "N minutes ago", and offline contacts get a grey dot.
    public var exactLastSeen: Bool
    /// Fork (Donutgram): a message that is only a TikTok or YouTube Shorts link is sent as the downloaded media.
    public var downloadTikTok: Bool
    public var downloadYouTubeShorts: Bool
    public var signDownloadedMedia: Bool
    /// Fork (Donutgram): a reply to a deleted message that only this client keeps goes out with a quote of it.
    public var quoteRepliesToDeleted: Bool
    public var exactCounts: Bool
    public var confirmVoiceSend: Bool
    public var hideTypingText: Bool
    public var hideTypingVoice: Bool
    public var hideTypingFiles: Bool
    /// Fork (MadGram): adds a "Screenshot" action to the message menu that renders the messages as an image. A menu entry only, so it defaults on.
    public var messageShot: Bool
    /// Fork (MadGram): applies Telegram's own power-saving profile (EnergyUsageSettings.powerSavingDefault) regardless of battery level. Off by default.
    public var powerSaving: Bool
    public var showsOfflineDot: Bool
    /// Hide paid (star) reactions from messages and the reaction picker.
    public var hidePaidReactions: Bool
    /// Hide the "via @bot" label on messages sent through inline bots.
    public var hideViaBot: Bool
    /// Send messages without link previews.
    public var removeLinkPreviews: Bool
    public var hideBirthdayNotifications: Bool
    public var hideBotAutomation: Bool
    public var showPinnedWithBot: Bool
    public var stopAfterVoice: Bool
    public var stopAfterRoundVideo: Bool
    public var hideGreetingSticker: Bool
    public var hashtagsPreferCurrentChat: Bool
    public var showOriginalForwardDate: Bool
    public var sendBannedGifsAsVideo: Bool
    public var showSensitiveContent: Bool
    /// WhiteGram: the story camera never opens (every Add Story entry point is inert). Viewing stays.
    public var disableStoryCreation: Bool
    /// WhiteGram: no reactions under posts in broadcast channels (groups and private chats keep theirs).
    public var hideChannelPostReactions: Bool
    /// Regram "input, links, media" block (all default off).
    /// Formatting applied to the plain parts of an outgoing text message: 0 off, 1 bold, 2 italic,
    /// 3 underline, 4 strikethrough, 5 spoiler. Manual formatting, code, quotes and custom emoji keep theirs.
    public var defaultSendFormatting: Int32
    /// A long press on a sender's avatar in a chat inserts a mention of them under their full name.
    public var avatarLongPressMention: Bool
    /// Link previews for X/Twitter, Instagram, TikTok, Reddit, Bluesky and Pixiv are requested from embed-friendly
    /// mirrors; the link in the message stays as typed.
    public var fixLinkPreviews: Bool
    /// "Save to Photos" in a sticker message's menu (static: PNG, animated/video: GIF).
    public var saveStickerToPhotos: Bool
    /// "Media Info" in a photo/video/file message's menu, read from what is already on the device.
    public var showMediaInfo: Bool
    /// "Revoke all" / "Revoke expired" under a group or channel's additional invite links.
    public var inviteLinksBulkRevoke: Bool
    /// The folder tabs show no unread badge; the counts themselves are untouched.
    public var hideFolderUnreadCount: Bool
    /// Unpinning a message, or all pinned messages, asks first even when Telegram would not.
    public var confirmUnpin: Bool
    /// No "typing..." style status in the list or title of private and secret chats.
    public var hidePrivateChatActivities: Bool
    /// A chat history reload that began at the newest message stays at the newest message.
    public var stayAtLatestMessageAfterRefresh: Bool
    /// The quality a gallery video starts in when the player offers several: 0 auto, 1 highest, 2 lowest.
    public var defaultVideoQuality: Int32

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
            keepAliveInBackground: false,
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
            stripTrackingParameters: false,
            wideChannelPosts: false,
            stickerSizePercent: 100,
            doubleTapToEdit: false,
            quickTranslateButton: false,
            saveToCloudMenu: true,
            selectFromAuthor: true,
            downloadSpeedBoost: false,
            outgoingPhotoQuality: 0,
            streamerMode: false,
            hideStickerStatus: false,
            showDisappearedGifts: false,
            roundVideoStartsWithRear: false,
            roundVideoRemembersCamera: false,
            chatListHidesConnectionStatus: false,
            chatListHidesEmojiStatus: false,
            chatListCentersTitle: false,
            chatListHidesSearch: false,
            pollResultsBeforeVoting: false,
            exactLastSeen: false,
            showsOfflineDot: false,
            downloadTikTok: false,
            downloadYouTubeShorts: false,
            signDownloadedMedia: false,
            quoteRepliesToDeleted: false,
            exactCounts: false,
            confirmVoiceSend: false,
            hideTypingText: false,
            hideTypingVoice: false,
            hideTypingFiles: false
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
        keepAliveInBackground: Bool,
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
        stripTrackingParameters: Bool = false,
        wideChannelPosts: Bool = false,
        stickerSizePercent: Int32 = 100,
        doubleTapToEdit: Bool = false,
        quickTranslateButton: Bool = false,
        saveToCloudMenu: Bool = true,
        selectFromAuthor: Bool = true,
        downloadSpeedBoost: Bool = false,
        outgoingPhotoQuality: Int32 = 0,
        streamerMode: Bool = false,
        hideStickerStatus: Bool = false,
        showDisappearedGifts: Bool = false,
        roundVideoStartsWithRear: Bool = false,
        roundVideoRemembersCamera: Bool = false,
        chatListHidesConnectionStatus: Bool = false,
        chatListHidesEmojiStatus: Bool = false,
        chatListCentersTitle: Bool = false,
        chatListHidesSearch: Bool = false,
        pollResultsBeforeVoting: Bool = false,
        exactLastSeen: Bool = false,
        showsOfflineDot: Bool = false,
        downloadTikTok: Bool = false,
        downloadYouTubeShorts: Bool = false,
        signDownloadedMedia: Bool = false,
        quoteRepliesToDeleted: Bool = false,
        exactCounts: Bool = false,
        confirmVoiceSend: Bool = false,
        hideTypingText: Bool = false,
        hideTypingVoice: Bool = false,
        hideTypingFiles: Bool = false
    ) {
        self.wideTabBar = false
        self.integratedTabSearch = false
        self.tabSearchOnLeft = false
        self.bottomChatFoldersEnabled = false
        self.avatarGlowEnabled = true
        self.snowEnabled = false
        self.showChannelForwardCount = false
        self.reactionGlowEnabled = false
        self.showContactsTab = true
        self.hidePaidReactions = false
        self.hideViaBot = false
        self.removeLinkPreviews = false
        self.hideBirthdayNotifications = false
        self.hideBotAutomation = false
        self.showPinnedWithBot = false
        self.stopAfterVoice = false
        self.stopAfterRoundVideo = false
        self.hideGreetingSticker = false
        self.removePings = false
        self.sendTelegramStatistics = false
        self.bananaIslandEnabled = true
        self.bananaIslandShowsName = true
        self.bananaIslandFollowsIcon = true
        self.hashtagsPreferCurrentChat = false
        self.showOriginalForwardDate = false
        self.sendBannedGifsAsVideo = false
        self.showSensitiveContent = false
        self.disableStoryCreation = false
        self.hideChannelPostReactions = false
        self.defaultSendFormatting = 0
        self.avatarLongPressMention = false
        self.fixLinkPreviews = false
        self.saveStickerToPhotos = false
        self.showMediaInfo = false
        self.inviteLinksBulkRevoke = false
        self.hideFolderUnreadCount = false
        self.confirmUnpin = false
        self.hidePrivateChatActivities = false
        self.stayAtLatestMessageAfterRefresh = false
        self.defaultVideoQuality = 0
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
        self.keepAliveInBackground = keepAliveInBackground
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
        self.stripTrackingParameters = stripTrackingParameters
        self.wideChannelPosts = wideChannelPosts
        self.stickerSizePercent = min(150, max(50, stickerSizePercent))
        self.doubleTapToEdit = doubleTapToEdit
        self.quickTranslateButton = quickTranslateButton
        self.saveToCloudMenu = saveToCloudMenu
        self.selectFromAuthor = selectFromAuthor
        self.downloadSpeedBoost = downloadSpeedBoost
        self.outgoingPhotoQuality = min(2, max(0, outgoingPhotoQuality))
        self.streamerMode = streamerMode
        self.hideStickerStatus = hideStickerStatus
        self.messageShot = true
        self.powerSaving = false
        self.hideStickerReplyColors = false
        self.chooseFolderAfterJoin = false
        self.recentChatsMenu = false
        self.messageBookmarks = false
        self.localGroupAlias = false
        self.disableStoryCameraSwipe = false
        self.jumpToStartInChatMenu = true
        self.hideServiceMessages = false
        self.confirmReactionsInUnjoinedChats = false
        self.confirmTelegramLinks = false
        self.confirmShareLinks = true
        self.confirmChatPreviewEntry = false
        self.disableGiftStarsRedirect = false
        self.visualLabels = [:]
        self.hideStickerReplyEmoji = false
        self.hideStickerReplyBackground = false
        self.hidePremiumReplyEmoji = false
        self.showChatCreationDate = false
        self.profileIdBotApiFormat = false
        self.showMutualContact = false
        self.hidePremiumStatuses = false
        self.hideVerification = false
        self.hideGiftButton = false
        self.visualPhoneEnabled = false
        self.visualPhoneNumber = ""
        self.ghostSendWithoutSound = false
        self.ghostSuggestForStories = false
        self.hideStories = false
        self.hideArchive = false
        self.allowProtectedScreenshots = false
        self.accelerateUpload = false
        self.infiniteRecentStickers = false
        self.onlyAddedStickers = false
        self.autoPauseMediaInBackground = false
        self.doubleTapSeekSeconds = 15
        self.showMessageId = false
        self.autoRevealSpoilers = false
        self.doubleTapAction = doubleTapToEdit ? 6 : 0
        self.repeatMessageMenu = false
        self.staticRoundVideoZoom = false
        self.stickerShape = 0
        self.commaAfterMention = false
        self.disableColoredReplies = false
        self.hideStickerChecks = false
        self.mentionAvatars = false
        self.relativeLastSeen = false
        self.approximateLastSeen = false
        self.anonymousStickers = false
        self.profileExpansionAnimation = false
        self.disableCustomBackgrounds = false
        self.channelBottomDiscuss = false
        self.hideChannelBottomButton = false
        self.hideShareButton = false
        self.glassBubbles = false
        self.glassBubbleTint = 25
        self.glassBubbleRimTop = 95
        self.glassBubbleRimSides = 20
        self.glassBubbleRimBottom = 55
        self.showDisappearedGifts = showDisappearedGifts
        self.roundVideoStartsWithRear = roundVideoStartsWithRear
        self.roundVideoRemembersCamera = roundVideoRemembersCamera
        self.chatListHidesConnectionStatus = chatListHidesConnectionStatus
        self.chatListHidesEmojiStatus = chatListHidesEmojiStatus
        self.chatListCentersTitle = chatListCentersTitle
        self.chatListHidesSearch = chatListHidesSearch
        self.pollResultsBeforeVoting = pollResultsBeforeVoting
        self.exactLastSeen = exactLastSeen
        self.showsOfflineDot = showsOfflineDot
        self.downloadTikTok = downloadTikTok
        self.downloadYouTubeShorts = downloadYouTubeShorts
        self.signDownloadedMedia = signDownloadedMedia
        self.quoteRepliesToDeleted = quoteRepliesToDeleted
        self.exactCounts = exactCounts
        self.confirmVoiceSend = confirmVoiceSend
        self.hideTypingText = hideTypingText
        self.hideTypingVoice = hideTypingVoice
        self.hideTypingFiles = hideTypingFiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.wideTabBar = try container.decodeIfPresent(Bool.self, forKey: "wideTabBar") ?? false
        self.integratedTabSearch = try container.decodeIfPresent(Bool.self, forKey: "integratedTabSearch") ?? false
        self.tabSearchOnLeft = try container.decodeIfPresent(Bool.self, forKey: "tabSearchOnLeft") ?? false
        self.bottomChatFoldersEnabled = try container.decodeIfPresent(Bool.self, forKey: "bottomChatFoldersEnabled") ?? false
        self.hidePaidReactions = try container.decodeIfPresent(Bool.self, forKey: "hidePaidReactions") ?? false
        self.hideViaBot = try container.decodeIfPresent(Bool.self, forKey: "hideViaBot") ?? false
        self.removeLinkPreviews = try container.decodeIfPresent(Bool.self, forKey: "removeLinkPreviews") ?? false
        self.hideBirthdayNotifications = try container.decodeIfPresent(Bool.self, forKey: "hideBirthdayNotifications") ?? false
        self.hideBotAutomation = try container.decodeIfPresent(Bool.self, forKey: "hideBotAutomation") ?? false
        self.showPinnedWithBot = try container.decodeIfPresent(Bool.self, forKey: "showPinnedWithBot") ?? false
        self.stopAfterVoice = try container.decodeIfPresent(Bool.self, forKey: "stopAfterVoice") ?? false
        self.stopAfterRoundVideo = try container.decodeIfPresent(Bool.self, forKey: "stopAfterRoundVideo") ?? false
        self.hideGreetingSticker = try container.decodeIfPresent(Bool.self, forKey: "hideGreetingSticker") ?? false
        self.removePings = try container.decodeIfPresent(Bool.self, forKey: "removePings") ?? false
        self.sendTelegramStatistics = try container.decodeIfPresent(Bool.self, forKey: "sendTelegramStatistics") ?? false
        self.bananaIslandEnabled = try container.decodeIfPresent(Bool.self, forKey: "bananaIslandEnabled") ?? true
        self.bananaIslandShowsName = try container.decodeIfPresent(Bool.self, forKey: "bananaIslandShowsName") ?? true
        self.bananaIslandFollowsIcon = try container.decodeIfPresent(Bool.self, forKey: "bananaIslandFollowsIcon") ?? true
        self.hashtagsPreferCurrentChat = try container.decodeIfPresent(Bool.self, forKey: "hashtagsPreferCurrentChat") ?? false
        self.showOriginalForwardDate = try container.decodeIfPresent(Bool.self, forKey: "showOriginalForwardDate") ?? false
        self.sendBannedGifsAsVideo = try container.decodeIfPresent(Bool.self, forKey: "sendBannedGifsAsVideo") ?? false
        self.showSensitiveContent = try container.decodeIfPresent(Bool.self, forKey: "showSensitiveContent") ?? false
        self.disableStoryCreation = try container.decodeIfPresent(Bool.self, forKey: "disableStoryCreation") ?? false
        self.hideChannelPostReactions = try container.decodeIfPresent(Bool.self, forKey: "hideChannelPostReactions") ?? false
        let decodedSendFormatting = try container.decodeIfPresent(Int32.self, forKey: "defaultSendFormatting") ?? 0
        self.defaultSendFormatting = (0 ... 5).contains(decodedSendFormatting) ? decodedSendFormatting : 0
        self.avatarLongPressMention = try container.decodeIfPresent(Bool.self, forKey: "avatarLongPressMention") ?? false
        self.fixLinkPreviews = try container.decodeIfPresent(Bool.self, forKey: "fixLinkPreviews") ?? false
        self.saveStickerToPhotos = try container.decodeIfPresent(Bool.self, forKey: "saveStickerToPhotos") ?? false
        self.showMediaInfo = try container.decodeIfPresent(Bool.self, forKey: "showMediaInfo") ?? false
        self.inviteLinksBulkRevoke = try container.decodeIfPresent(Bool.self, forKey: "inviteLinksBulkRevoke") ?? false
        self.hideFolderUnreadCount = try container.decodeIfPresent(Bool.self, forKey: "hideFolderUnreadCount") ?? false
        self.confirmUnpin = try container.decodeIfPresent(Bool.self, forKey: "confirmUnpin") ?? false
        self.hidePrivateChatActivities = try container.decodeIfPresent(Bool.self, forKey: "hidePrivateChatActivities") ?? false
        self.stayAtLatestMessageAfterRefresh = try container.decodeIfPresent(Bool.self, forKey: "stayAtLatestMessageAfterRefresh") ?? false
        let decodedVideoQuality = try container.decodeIfPresent(Int32.self, forKey: "defaultVideoQuality") ?? 0
        self.defaultVideoQuality = (0 ... 2).contains(decodedVideoQuality) ? decodedVideoQuality : 0
        self.avatarGlowEnabled = try container.decodeIfPresent(Bool.self, forKey: "avatarGlowEnabled") ?? true
        self.snowEnabled = try container.decodeIfPresent(Bool.self, forKey: "snowEnabled") ?? false
        self.showChannelForwardCount = try container.decodeIfPresent(Bool.self, forKey: "showChannelForwardCount") ?? false
        self.reactionGlowEnabled = try container.decodeIfPresent(Bool.self, forKey: "reactionGlowEnabled") ?? false
        self.showContactsTab = try container.decodeIfPresent(Bool.self, forKey: "showContactsTab") ?? true
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
        self.keepAliveInBackground = try container.decodeIfPresent(Bool.self, forKey: "keepAliveInBackground") ?? false
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
        self.stripTrackingParameters = try container.decodeIfPresent(Bool.self, forKey: "stripTrackingParameters") ?? false
        self.wideChannelPosts = try container.decodeIfPresent(Bool.self, forKey: "wideChannelPosts") ?? false
        self.stickerSizePercent = min(150, max(50, try container.decodeIfPresent(Int32.self, forKey: "stickerSizePercent") ?? 100))
        self.doubleTapToEdit = try container.decodeIfPresent(Bool.self, forKey: "doubleTapToEdit") ?? false
        self.quickTranslateButton = try container.decodeIfPresent(Bool.self, forKey: "quickTranslateButton") ?? false
        self.saveToCloudMenu = try container.decodeIfPresent(Bool.self, forKey: "saveToCloudMenu") ?? true
        self.selectFromAuthor = try container.decodeIfPresent(Bool.self, forKey: "selectFromAuthor") ?? true
        self.downloadSpeedBoost = try container.decodeIfPresent(Bool.self, forKey: "downloadSpeedBoost") ?? false
        self.outgoingPhotoQuality = min(2, max(0, try container.decodeIfPresent(Int32.self, forKey: "outgoingPhotoQuality") ?? 0))
        self.streamerMode = try container.decodeIfPresent(Bool.self, forKey: "streamerMode") ?? false
        self.hideStickerStatus = try container.decodeIfPresent(Bool.self, forKey: "hideStickerStatus") ?? false
        self.hideStickerReplyColors = try container.decodeIfPresent(Bool.self, forKey: "hideStickerReplyColors") ?? false
        self.chooseFolderAfterJoin = try container.decodeIfPresent(Bool.self, forKey: "chooseFolderAfterJoin") ?? false
        self.recentChatsMenu = try container.decodeIfPresent(Bool.self, forKey: "recentChatsMenu") ?? false
        self.messageBookmarks = try container.decodeIfPresent(Bool.self, forKey: "messageBookmarks") ?? false
        self.localGroupAlias = try container.decodeIfPresent(Bool.self, forKey: "localGroupAlias") ?? false
        self.disableStoryCameraSwipe = try container.decodeIfPresent(Bool.self, forKey: "disableStoryCameraSwipe") ?? false
        self.jumpToStartInChatMenu = try container.decodeIfPresent(Bool.self, forKey: "jumpToStartInChatMenu") ?? true
        self.hideServiceMessages = try container.decodeIfPresent(Bool.self, forKey: "hideServiceMessages") ?? false
        self.confirmReactionsInUnjoinedChats = try container.decodeIfPresent(Bool.self, forKey: "confirmReactionsInUnjoinedChats") ?? false
        self.confirmTelegramLinks = try container.decodeIfPresent(Bool.self, forKey: "confirmTelegramLinks") ?? false
        self.confirmShareLinks = try container.decodeIfPresent(Bool.self, forKey: "confirmShareLinks") ?? true
        self.confirmChatPreviewEntry = try container.decodeIfPresent(Bool.self, forKey: "confirmChatPreviewEntry") ?? false
        self.disableGiftStarsRedirect = try container.decodeIfPresent(Bool.self, forKey: "disableGiftStarsRedirect") ?? false
        self.visualLabels = (try container.decodeIfPresent([Int64: Int32].self, forKey: "visualLabels") ?? [:]).filter { (1...4).contains($0.value) }
        self.hideStickerReplyEmoji = try container.decodeIfPresent(Bool.self, forKey: "hideStickerReplyEmoji") ?? false
        self.hideStickerReplyBackground = try container.decodeIfPresent(Bool.self, forKey: "hideStickerReplyBackground") ?? false
        self.hidePremiumReplyEmoji = try container.decodeIfPresent(Bool.self, forKey: "hidePremiumReplyEmoji") ?? false
        self.showChatCreationDate = try container.decodeIfPresent(Bool.self, forKey: "showChatCreationDate") ?? false
        self.profileIdBotApiFormat = try container.decodeIfPresent(Bool.self, forKey: "profileIdBotApiFormat") ?? false
        // The mutual-contact row used to ride on Show Profile ID; a stored blob without its own key keeps that.
        self.showMutualContact = try container.decodeIfPresent(Bool.self, forKey: "showMutualContact") ?? self.showProfileId
        self.hidePremiumStatuses = try container.decodeIfPresent(Bool.self, forKey: "hidePremiumStatuses") ?? false
        self.hideVerification = try container.decodeIfPresent(Bool.self, forKey: "hideVerification") ?? false
        self.hideGiftButton = try container.decodeIfPresent(Bool.self, forKey: "hideGiftButton") ?? false
        self.visualPhoneEnabled = try container.decodeIfPresent(Bool.self, forKey: "visualPhoneEnabled") ?? false
        self.visualPhoneNumber = try container.decodeIfPresent(String.self, forKey: "visualPhoneNumber") ?? ""
        self.ghostSendWithoutSound = try container.decodeIfPresent(Bool.self, forKey: "ghostSendWithoutSound") ?? false
        self.ghostSuggestForStories = try container.decodeIfPresent(Bool.self, forKey: "ghostSuggestForStories") ?? false
        self.hideStories = try container.decodeIfPresent(Bool.self, forKey: "hideStories") ?? false
        self.hideArchive = try container.decodeIfPresent(Bool.self, forKey: "hideArchive") ?? false
        self.allowProtectedScreenshots = try container.decodeIfPresent(Bool.self, forKey: "allowProtectedScreenshots") ?? false
        self.accelerateUpload = try container.decodeIfPresent(Bool.self, forKey: "accelerateUpload") ?? false
        self.infiniteRecentStickers = try container.decodeIfPresent(Bool.self, forKey: "infiniteRecentStickers") ?? false
        self.onlyAddedStickers = try container.decodeIfPresent(Bool.self, forKey: "onlyAddedStickers") ?? false
        self.autoPauseMediaInBackground = try container.decodeIfPresent(Bool.self, forKey: "autoPauseMediaInBackground") ?? false
        let decodedSeekSeconds = try container.decodeIfPresent(Int32.self, forKey: "doubleTapSeekSeconds") ?? 15
        self.doubleTapSeekSeconds = [0, 5, 10, 15, 30].contains(decodedSeekSeconds) ? decodedSeekSeconds : 15
        self.showMessageId = try container.decodeIfPresent(Bool.self, forKey: "showMessageId") ?? false
        self.autoRevealSpoilers = try container.decodeIfPresent(Bool.self, forKey: "autoRevealSpoilers") ?? false
        let decodedDoubleTapAction = try container.decodeIfPresent(Int32.self, forKey: "doubleTapAction") ?? (self.doubleTapToEdit ? 6 : 0)
        self.doubleTapAction = [0, 1, 2, 3, 4, 6].contains(decodedDoubleTapAction) ? decodedDoubleTapAction : 0
        self.repeatMessageMenu = try container.decodeIfPresent(Bool.self, forKey: "repeatMessageMenu") ?? false
        self.staticRoundVideoZoom = try container.decodeIfPresent(Bool.self, forKey: "staticRoundVideoZoom") ?? false
        self.stickerShape = min(2, max(0, try container.decodeIfPresent(Int32.self, forKey: "stickerShape") ?? 0))
        self.commaAfterMention = try container.decodeIfPresent(Bool.self, forKey: "commaAfterMention") ?? false
        self.disableColoredReplies = try container.decodeIfPresent(Bool.self, forKey: "disableColoredReplies") ?? false
        self.hideStickerChecks = try container.decodeIfPresent(Bool.self, forKey: "hideStickerChecks") ?? false
        self.mentionAvatars = try container.decodeIfPresent(Bool.self, forKey: "mentionAvatars") ?? false
        self.relativeLastSeen = try container.decodeIfPresent(Bool.self, forKey: "relativeLastSeen") ?? false
        self.approximateLastSeen = try container.decodeIfPresent(Bool.self, forKey: "approximateLastSeen") ?? false
        self.anonymousStickers = try container.decodeIfPresent(Bool.self, forKey: "anonymousStickers") ?? false
        self.profileExpansionAnimation = try container.decodeIfPresent(Bool.self, forKey: "profileExpansionAnimation") ?? false
        self.disableCustomBackgrounds = try container.decodeIfPresent(Bool.self, forKey: "disableCustomBackgrounds") ?? false
        self.channelBottomDiscuss = try container.decodeIfPresent(Bool.self, forKey: "channelBottomDiscuss") ?? false
        self.hideChannelBottomButton = try container.decodeIfPresent(Bool.self, forKey: "hideChannelBottomButton") ?? false
        self.hideShareButton = try container.decodeIfPresent(Bool.self, forKey: "hideShareButton") ?? false
        self.glassBubbles = try container.decodeIfPresent(Bool.self, forKey: "glassBubbles") ?? false
        self.glassBubbleTint = try container.decodeIfPresent(Int32.self, forKey: "glassBubbleTint") ?? 25
        self.glassBubbleRimTop = try container.decodeIfPresent(Int32.self, forKey: "glassBubbleRimTop") ?? 95
        self.glassBubbleRimSides = try container.decodeIfPresent(Int32.self, forKey: "glassBubbleRimSides") ?? 20
        self.glassBubbleRimBottom = try container.decodeIfPresent(Int32.self, forKey: "glassBubbleRimBottom") ?? 55
        self.showDisappearedGifts = try container.decodeIfPresent(Bool.self, forKey: "showDisappearedGifts") ?? false
        self.roundVideoStartsWithRear = try container.decodeIfPresent(Bool.self, forKey: "roundVideoStartsWithRear") ?? false
        self.roundVideoRemembersCamera = try container.decodeIfPresent(Bool.self, forKey: "roundVideoRemembersCamera") ?? false
        self.chatListHidesConnectionStatus = try container.decodeIfPresent(Bool.self, forKey: "chatListHidesConnectionStatus") ?? false
        self.chatListHidesEmojiStatus = try container.decodeIfPresent(Bool.self, forKey: "chatListHidesEmojiStatus") ?? false
        self.chatListCentersTitle = try container.decodeIfPresent(Bool.self, forKey: "chatListCentersTitle") ?? false
        self.chatListHidesSearch = try container.decodeIfPresent(Bool.self, forKey: "chatListHidesSearch") ?? false
        self.pollResultsBeforeVoting = try container.decodeIfPresent(Bool.self, forKey: "pollResultsBeforeVoting") ?? false
        self.exactLastSeen = try container.decodeIfPresent(Bool.self, forKey: "exactLastSeen") ?? false
        self.showsOfflineDot = try container.decodeIfPresent(Bool.self, forKey: "showsOfflineDot") ?? false
        self.downloadTikTok = try container.decodeIfPresent(Bool.self, forKey: "downloadTikTok") ?? false
        self.downloadYouTubeShorts = try container.decodeIfPresent(Bool.self, forKey: "downloadYouTubeShorts") ?? false
        self.signDownloadedMedia = try container.decodeIfPresent(Bool.self, forKey: "signDownloadedMedia") ?? false
        self.quoteRepliesToDeleted = try container.decodeIfPresent(Bool.self, forKey: "quoteRepliesToDeleted") ?? false
        self.exactCounts = try container.decodeIfPresent(Bool.self, forKey: "exactCounts") ?? false
        self.confirmVoiceSend = try container.decodeIfPresent(Bool.self, forKey: "confirmVoiceSend") ?? false
        self.hideTypingText = try container.decodeIfPresent(Bool.self, forKey: "hideTypingText") ?? false
        self.hideTypingVoice = try container.decodeIfPresent(Bool.self, forKey: "hideTypingVoice") ?? false
        self.hideTypingFiles = try container.decodeIfPresent(Bool.self, forKey: "hideTypingFiles") ?? false
        self.messageShot = try container.decodeIfPresent(Bool.self, forKey: "messageShot") ?? true
        self.powerSaving = try container.decodeIfPresent(Bool.self, forKey: "powerSaving") ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        // Legacy: true when full Ghost Mode (5 flags including stories + go-offline) is on.
        try container.encode(self.wideTabBar, forKey: "wideTabBar")
        try container.encode(self.integratedTabSearch, forKey: "integratedTabSearch")
        try container.encode(self.tabSearchOnLeft, forKey: "tabSearchOnLeft")
        try container.encode(self.bottomChatFoldersEnabled, forKey: "bottomChatFoldersEnabled")
        try container.encode(self.hidePaidReactions, forKey: "hidePaidReactions")
        try container.encode(self.hideViaBot, forKey: "hideViaBot")
        try container.encode(self.removeLinkPreviews, forKey: "removeLinkPreviews")
        try container.encode(self.hideBirthdayNotifications, forKey: "hideBirthdayNotifications")
        try container.encode(self.hideBotAutomation, forKey: "hideBotAutomation")
        try container.encode(self.showPinnedWithBot, forKey: "showPinnedWithBot")
        try container.encode(self.stopAfterVoice, forKey: "stopAfterVoice")
        try container.encode(self.stopAfterRoundVideo, forKey: "stopAfterRoundVideo")
        try container.encode(self.hideGreetingSticker, forKey: "hideGreetingSticker")
        try container.encode(self.removePings, forKey: "removePings")
        try container.encode(self.sendTelegramStatistics, forKey: "sendTelegramStatistics")
        try container.encode(self.bananaIslandEnabled, forKey: "bananaIslandEnabled")
        try container.encode(self.bananaIslandShowsName, forKey: "bananaIslandShowsName")
        try container.encode(self.bananaIslandFollowsIcon, forKey: "bananaIslandFollowsIcon")
        try container.encode(self.hashtagsPreferCurrentChat, forKey: "hashtagsPreferCurrentChat")
        try container.encode(self.showOriginalForwardDate, forKey: "showOriginalForwardDate")
        try container.encode(self.sendBannedGifsAsVideo, forKey: "sendBannedGifsAsVideo")
        try container.encode(self.showSensitiveContent, forKey: "showSensitiveContent")
        try container.encode(self.disableStoryCreation, forKey: "disableStoryCreation")
        try container.encode(self.hideChannelPostReactions, forKey: "hideChannelPostReactions")
        try container.encode(self.defaultSendFormatting, forKey: "defaultSendFormatting")
        try container.encode(self.avatarLongPressMention, forKey: "avatarLongPressMention")
        try container.encode(self.fixLinkPreviews, forKey: "fixLinkPreviews")
        try container.encode(self.saveStickerToPhotos, forKey: "saveStickerToPhotos")
        try container.encode(self.showMediaInfo, forKey: "showMediaInfo")
        try container.encode(self.inviteLinksBulkRevoke, forKey: "inviteLinksBulkRevoke")
        try container.encode(self.hideFolderUnreadCount, forKey: "hideFolderUnreadCount")
        try container.encode(self.confirmUnpin, forKey: "confirmUnpin")
        try container.encode(self.hidePrivateChatActivities, forKey: "hidePrivateChatActivities")
        try container.encode(self.stayAtLatestMessageAfterRefresh, forKey: "stayAtLatestMessageAfterRefresh")
        try container.encode(self.defaultVideoQuality, forKey: "defaultVideoQuality")
        try container.encode(self.avatarGlowEnabled, forKey: "avatarGlowEnabled")
        try container.encode(self.snowEnabled, forKey: "snowEnabled")
        try container.encode(self.showChannelForwardCount, forKey: "showChannelForwardCount")
        try container.encode(self.reactionGlowEnabled, forKey: "reactionGlowEnabled")
        try container.encode(self.showContactsTab, forKey: "showContactsTab")
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
        try container.encode(self.keepAliveInBackground, forKey: "keepAliveInBackground")
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
        try container.encode(self.stripTrackingParameters, forKey: "stripTrackingParameters")
        try container.encode(self.wideChannelPosts, forKey: "wideChannelPosts")
        try container.encode(self.stickerSizePercent, forKey: "stickerSizePercent")
        try container.encode(self.doubleTapAction == 6, forKey: "doubleTapToEdit")
        try container.encode(self.quickTranslateButton, forKey: "quickTranslateButton")
        try container.encode(self.saveToCloudMenu, forKey: "saveToCloudMenu")
        try container.encode(self.selectFromAuthor, forKey: "selectFromAuthor")
        try container.encode(self.downloadSpeedBoost, forKey: "downloadSpeedBoost")
        try container.encode(self.outgoingPhotoQuality, forKey: "outgoingPhotoQuality")
        try container.encode(self.streamerMode, forKey: "streamerMode")
        try container.encode(self.hideStickerStatus, forKey: "hideStickerStatus")
        try container.encode(self.hideStickerReplyColors, forKey: "hideStickerReplyColors")
        try container.encode(self.chooseFolderAfterJoin, forKey: "chooseFolderAfterJoin")
        try container.encode(self.recentChatsMenu, forKey: "recentChatsMenu")
        try container.encode(self.messageBookmarks, forKey: "messageBookmarks")
        try container.encode(self.localGroupAlias, forKey: "localGroupAlias")
        try container.encode(self.disableStoryCameraSwipe, forKey: "disableStoryCameraSwipe")
        try container.encode(self.jumpToStartInChatMenu, forKey: "jumpToStartInChatMenu")
        try container.encode(self.hideServiceMessages, forKey: "hideServiceMessages")
        try container.encode(self.confirmReactionsInUnjoinedChats, forKey: "confirmReactionsInUnjoinedChats")
        try container.encode(self.confirmTelegramLinks, forKey: "confirmTelegramLinks")
        try container.encode(self.confirmShareLinks, forKey: "confirmShareLinks")
        try container.encode(self.confirmChatPreviewEntry, forKey: "confirmChatPreviewEntry")
        try container.encode(self.disableGiftStarsRedirect, forKey: "disableGiftStarsRedirect")
        try container.encode(self.visualLabels, forKey: "visualLabels")
        try container.encode(self.hideStickerReplyEmoji, forKey: "hideStickerReplyEmoji")
        try container.encode(self.hideStickerReplyBackground, forKey: "hideStickerReplyBackground")
        try container.encode(self.hidePremiumReplyEmoji, forKey: "hidePremiumReplyEmoji")
        try container.encode(self.showChatCreationDate, forKey: "showChatCreationDate")
        try container.encode(self.profileIdBotApiFormat, forKey: "profileIdBotApiFormat")
        try container.encode(self.showMutualContact, forKey: "showMutualContact")
        try container.encode(self.hidePremiumStatuses, forKey: "hidePremiumStatuses")
        try container.encode(self.hideVerification, forKey: "hideVerification")
        try container.encode(self.hideGiftButton, forKey: "hideGiftButton")
        try container.encode(self.visualPhoneEnabled, forKey: "visualPhoneEnabled")
        try container.encode(self.visualPhoneNumber, forKey: "visualPhoneNumber")
        try container.encode(self.ghostSendWithoutSound, forKey: "ghostSendWithoutSound")
        try container.encode(self.ghostSuggestForStories, forKey: "ghostSuggestForStories")
        try container.encode(self.hideStories, forKey: "hideStories")
        try container.encode(self.hideArchive, forKey: "hideArchive")
        try container.encode(self.allowProtectedScreenshots, forKey: "allowProtectedScreenshots")
        try container.encode(self.accelerateUpload, forKey: "accelerateUpload")
        try container.encode(self.infiniteRecentStickers, forKey: "infiniteRecentStickers")
        try container.encode(self.onlyAddedStickers, forKey: "onlyAddedStickers")
        try container.encode(self.autoPauseMediaInBackground, forKey: "autoPauseMediaInBackground")
        try container.encode(self.doubleTapSeekSeconds, forKey: "doubleTapSeekSeconds")
        try container.encode(self.showMessageId, forKey: "showMessageId")
        try container.encode(self.autoRevealSpoilers, forKey: "autoRevealSpoilers")
        try container.encode(self.doubleTapAction, forKey: "doubleTapAction")
        try container.encode(self.repeatMessageMenu, forKey: "repeatMessageMenu")
        try container.encode(self.staticRoundVideoZoom, forKey: "staticRoundVideoZoom")
        try container.encode(self.stickerShape, forKey: "stickerShape")
        try container.encode(self.commaAfterMention, forKey: "commaAfterMention")
        try container.encode(self.disableColoredReplies, forKey: "disableColoredReplies")
        try container.encode(self.hideStickerChecks, forKey: "hideStickerChecks")
        try container.encode(self.mentionAvatars, forKey: "mentionAvatars")
        try container.encode(self.relativeLastSeen, forKey: "relativeLastSeen")
        try container.encode(self.approximateLastSeen, forKey: "approximateLastSeen")
        try container.encode(self.anonymousStickers, forKey: "anonymousStickers")
        try container.encode(self.profileExpansionAnimation, forKey: "profileExpansionAnimation")
        try container.encode(self.disableCustomBackgrounds, forKey: "disableCustomBackgrounds")
        try container.encode(self.channelBottomDiscuss, forKey: "channelBottomDiscuss")
        try container.encode(self.hideChannelBottomButton, forKey: "hideChannelBottomButton")
        try container.encode(self.hideShareButton, forKey: "hideShareButton")
        try container.encode(self.glassBubbles, forKey: "glassBubbles")
        try container.encode(self.glassBubbleTint, forKey: "glassBubbleTint")
        try container.encode(self.glassBubbleRimTop, forKey: "glassBubbleRimTop")
        try container.encode(self.glassBubbleRimSides, forKey: "glassBubbleRimSides")
        try container.encode(self.glassBubbleRimBottom, forKey: "glassBubbleRimBottom")
        try container.encode(self.showDisappearedGifts, forKey: "showDisappearedGifts")
        try container.encode(self.roundVideoStartsWithRear, forKey: "roundVideoStartsWithRear")
        try container.encode(self.roundVideoRemembersCamera, forKey: "roundVideoRemembersCamera")
        try container.encode(self.chatListHidesConnectionStatus, forKey: "chatListHidesConnectionStatus")
        try container.encode(self.chatListHidesEmojiStatus, forKey: "chatListHidesEmojiStatus")
        try container.encode(self.chatListCentersTitle, forKey: "chatListCentersTitle")
        try container.encode(self.chatListHidesSearch, forKey: "chatListHidesSearch")
        try container.encode(self.pollResultsBeforeVoting, forKey: "pollResultsBeforeVoting")
        try container.encode(self.exactLastSeen, forKey: "exactLastSeen")
        try container.encode(self.showsOfflineDot, forKey: "showsOfflineDot")
        try container.encode(self.downloadTikTok, forKey: "downloadTikTok")
        try container.encode(self.downloadYouTubeShorts, forKey: "downloadYouTubeShorts")
        try container.encode(self.signDownloadedMedia, forKey: "signDownloadedMedia")
        try container.encode(self.quoteRepliesToDeleted, forKey: "quoteRepliesToDeleted")
        try container.encode(self.exactCounts, forKey: "exactCounts")
        try container.encode(self.confirmVoiceSend, forKey: "confirmVoiceSend")
        try container.encode(self.hideTypingText, forKey: "hideTypingText")
        try container.encode(self.hideTypingVoice, forKey: "hideTypingVoice")
        try container.encode(self.hideTypingFiles, forKey: "hideTypingFiles")
        try container.encode(self.messageShot, forKey: "messageShot")
        try container.encode(self.powerSaving, forKey: "powerSaving")
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
            return Int32(clamping: UserDefaults.standard.integer(forKey: accountKey))
        }
        // One-shot migrate the pre-account-scoped value so a single-account install keeps its folder.
        if UserDefaults.standard.object(forKey: legacyKey) != nil {
            let migrated = Int32(clamping: UserDefaults.standard.integer(forKey: legacyKey))
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

/// Fork (Donutgram): the phone number displayed for the account's own profile. With the visual number on it is the
/// typed one; anyone else's number, and every action (call, copy, change number), keeps the real one.
public func forkDisplayedPhone(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, phone: String, settings: ForkExtrasSettings) -> String {
    if accountPeerId == peerId && settings.visualPhoneEnabled {
        let visual = settings.visualPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !visual.isEmpty {
            return visual
        }
    }
    return phone
}

/// Fork (Donutgram): the profile id row's text. Telegram API form is the bare id; Bot API form negates basic groups
/// and writes the channel namespace (channels, supergroups) as -100<id>.
public func forkProfileIdText(peerId: EnginePeer.Id, botApiFormat: Bool) -> String {
    let rawId = peerId.id._internalGetInt64Value()
    if botApiFormat {
        if peerId.namespace == Namespaces.Peer.CloudGroup {
            return "\(-rawId)"
        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
            return "\(-1_000_000_000_000 - rawId)"
        }
    }
    return "\(rawId)"
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

    /// Patterns that will never match anything, so the settings screen can say so instead of a typo looking like a dead
    /// switch: not valid regular expressions, longer than the size bound, or past the cap on how many are used.
    public static func unusablePatternCount(_ patterns: [String]) -> Int {
        var count = 0
        var used = 0
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if used >= maxPatterns || trimmed.utf16.count > 512 || (try? NSRegularExpression(pattern: trimmed, options: [])) == nil {
                count += 1
            } else {
                used += 1
            }
        }
        return count
    }

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
        // A rich message sends `text: ""` and keeps its text in the instant page.
        var body = message.text
        if body.isEmpty, let richText = message.attributes.first(where: { $0 is RichTextMessageAttribute }) as? RichTextMessageAttribute {
            body = richText.instantPage.fullPlainText
        }
        var input = boundedPrefix(body, utf16Limit: maxMessageTextMatchUTF16Length)
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
    private static let removePingsKey = "ForkExtras.removePings"
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
    
    private static let lastSynced = Atomic<(hideMentions: Bool, hidePinned: Bool, removePings: Bool)?>(value: nil)

    /// Project notification-hide flags into App Group / standard defaults for NSE.
    /// Change-gated and without `synchronize()` — `set` is enough and avoids main-thread disk stalls.
    public static func sync(_ settings: ForkExtrasSettings) {
        let next = (hideMentions: settings.hideMentionNotifications, hidePinned: settings.hidePinnedNotifications, removePings: settings.removePings)
        var shouldWrite = false
        let _ = lastSynced.modify { previous in
            if previous?.hideMentions == next.hideMentions, previous?.hidePinned == next.hidePinned, previous?.removePings == next.removePings {
                return previous
            }
            shouldWrite = true
            return next
        }
        guard shouldWrite else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(next.removePings, forKey: removePingsKey)
        defaults.set(next.hideMentions, forKey: hideMentionsKey)
        defaults.set(next.hidePinned, forKey: hidePinnedKey)
        for suite in candidateSuites() {
            defaults.set(suite, forKey: suiteHintKey)
            if let shared = UserDefaults(suiteName: suite) {
                shared.set(next.removePings, forKey: removePingsKey)
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
    
    public static var removePings: Bool { return bool(forKey: removePingsKey) }

    public static var hideMentionNotifications: Bool {
        return bool(forKey: hideMentionsKey)
    }
    
    public static var hidePinnedNotifications: Bool {
        return bool(forKey: hidePinnedKey)
    }
}

/// Projects the Donutgram chat-appearance switches into the runtime holders the chat modules read
/// (`ArenaSettings.shared`, `BananaPresenceDisplay` is set separately in SharedAccountContext).
public func applyForkChatAppearanceSettings(_ settings: ForkExtrasSettings) {
    ArenaSettings.shared.setChatAppearance(
        commaAfterMention: settings.commaAfterMention,
        disableColoredReplies: settings.disableColoredReplies,
        hideStickerChecks: settings.hideStickerChecks,
        mentionAvatars: settings.mentionAvatars,
        disableCustomBackgrounds: settings.disableCustomBackgrounds,
        channelBottomDiscuss: settings.channelBottomDiscuss,
        hideChannelBottomButton: settings.hideChannelBottomButton,
        hideShareButton: settings.hideShareButton
    )
    ArenaSettings.shared.setGlassBubbles(
        enabled: settings.glassBubbles,
        tint: settings.glassBubbleTint,
        rimTop: settings.glassBubbleRimTop,
        rimSides: settings.glassBubbleRimSides,
        rimBottom: settings.glassBubbleRimBottom
    )
}

public enum BananaForwardCountSettings {
    private static let value = Atomic<Bool>(value: false)
    public static var enabled: Bool {
        get { return value.with { $0 } }
        set { let _ = value.swap(newValue) }
    }
}
