import Foundation
import Postbox
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private func forkExtrasAnchorPopover(_ controller: UIViewController, window: UIWindow?) {
    guard let window, let popover = controller.popoverPresentationController else {
        return
    }
    popover.sourceView = window
    popover.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
    popover.permittedArrowDirections = []
}

private func forkExtrasKeyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
        if let window = scene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
    }
    return scenes.first?.windows.first
}

private func forkExtrasPresentNativeController(_ controller: UIViewController, context: AccountContext) {
    let window = context.sharedContext.mainWindow?.viewController?.view.window ?? forkExtrasKeyWindow()
    forkExtrasAnchorPopover(controller, window: window)
    context.sharedContext.applicationBindings.presentNativeController(controller)
}

/// Document-picker bridge for MessageSaving JSON import (AyuGram DB import parity).
private final class ForkExtrasMessageSavingImportPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = ForkExtrasMessageSavingImportPresenter()
    private var replace = false
    private var context: AccountContext?
    private var present: ((ViewController) -> Void)?

    func present(replace: Bool, context: AccountContext, present: @escaping (ViewController) -> Void) {
        self.replace = replace
        self.context = context
        self.present = present
        // Includes JSON and folders so we can import either a bare records.json or a
        // full exportBundle() directory.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        forkExtrasPresentNativeController(picker, context: context)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Released as soon as the picker is done: a singleton holding the context kept a logged-out
        // or switched-away account (postbox, network, media box) alive for the rest of the process.
        let replace = self.replace
        let context = self.context
        let present = self.present
        self.context = nil
        self.present = nil
        guard let url = urls.first, let context else {
            return
        }
        // Decoding the records and copying every attachment (possibly out of iCloud Drive) took
        // seconds on the main thread for a large store — enough for the watchdog to kill the app.
        DispatchQueue.global(qos: .userInitiated).async {
            let access = url.startAccessingSecurityScopedResource()
            let result = MessageSavingStore.importBundle(from: url, replace: replace)
            if access {
                url.stopAccessingSecurityScopedResource()
            }
            DispatchQueue.main.async {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                switch result {
                case let .success(count):
                    let text = ForkExtrasLocalizedString.importMessageSavingDone.replacingOccurrences(of: "{count}", with: "\(count)")
                    let alert = textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                    present?(alert)
                case .failure:
                    let alert = textAlertController(context: context, title: nil, text: ForkExtrasLocalizedString.importMessageSavingFailed, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                    present?(alert)
                }
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.context = nil
        self.present = nil
    }
}


private enum ForkExtrasLocalizedString {
    private static let translations: [String: [String: String]] = [
        "en": [
            "ForkExtras.wideTabBar": "Wide tab bar",
            "ForkExtras.integratedTabSearch": "Search inside tab bar",
            "ForkExtras.tabSearchOnLeft": "Search on the left",

            "ForkExtras.BottomFolders": "Folders at the bottom",
            "ForkExtras.AvatarGlow": "Avatar glow",
            "ForkExtras.ReactionGlow": "Reaction glow",
            "ForkExtras.ContactsTab": "Contacts tab",

            "ForkExtras.Title": "Extras",
            "ForkExtras.GhostModeMaster": "Ghost Mode",
            "ForkExtras.GhostDontReadMessages": "Don't Read Messages",
            "ForkExtras.GhostDontReadStories": "Don't Read Stories",
            "ForkExtras.GhostDontSendOnline": "Don't Send Online",
            "ForkExtras.GhostDontSendTyping": "Don't Send Typing",
            "ForkExtras.GhostGoOfflineAutomatically": "Go Offline Automatically",
            "ForkExtras.GhostGoOfflineAutomaticallyFooter": "Go offline again right after appearing online for a moment.",
            "ForkExtras.GhostReadOnInteract": "Read on Interact",
            "ForkExtras.GhostReadOnInteractFooter": "With Don't Read Messages on, replying or reacting marks the chat read and shows you online for a moment.",
            "ForkExtras.GhostAlertBeforeOpeningStory": "Alert Before Opening Story",
            "ForkExtras.GhostAlertBeforeOpeningStoryFooter": "Ask before opening a story.",
            "ForkExtras.GhostModeFooter": "Ghost Mode turns on every “Don't…” option and Go Offline Automatically. You can still change each one.",
            "ForkExtras.InstantPasscode": "Instant Passcode Lock",
            "ForkExtras.InstantPasscodeFooter": "Lock the app as soon as you leave it.",
            "ForkExtras.StreamerMode": "Streamer Mode",
            "ForkExtras.StreamerModeFooter": "Hides your phone number and username in profiles and at the top of Settings.",
            "ForkExtras.HideMentions": "Hide Mention Notifications",
            "ForkExtras.HideMentionsFooter": "No notifications when someone mentions you.",
            "ForkExtras.HidePinned": "Hide Pinned Notifications",
            "ForkExtras.HidePinnedFooter": "No notifications for pinned messages.",
            "ForkExtras.SessionBackup": "Back Up Sign-In to Keychain",
            "ForkExtras.SessionBackupFooter": "Keeps a copy of your sign-in in the iPhone Keychain, so you stay signed in after reinstalling the app.",
            "ForkExtras.CompactChatList": "Compact Chat List",
            "ForkExtras.CompactMessagePreview": "Compact Message Preview",
            "ForkExtras.CompactFolderNames": "Compact Folder Names",
            "ForkExtras.UIDensityFooter": "Fits more on the screen. Rows stay large enough to tap easily.",
            "ForkExtras.HideReactionsBar": "Hide Reactions",
            "ForkExtras.HideReactionsBarFooter": "Hides reactions under messages.",
            "ForkExtras.ShowDC": "Show Data Center & Registration Date",
            "ForkExtras.ShowProfileId": "Show Profile ID",
            "ForkExtras.PrivacyFooter": "Shows extra details on profiles.",
            "ForkExtras.AccentSaturation": "Accent Color Saturation",
            "ForkExtras.ConfirmBeforeCall": "Confirm Before Calling",
            "ForkExtras.SendWithReturnKey": "Send With Return Key",
            "ForkExtras.SendWithReturnKeyFooter": "Return sends the message instead of starting a new line.",
            "ForkExtras.ForceBuiltInMic": "Force Built-in Microphone",
            "ForkExtras.KeepAliveInBackground": "Keep App Alive in Background",
            "ForkExtras.KeepAliveInBackgroundFooter": "A silent sound keeps the app running, so calls and messages arrive while the screen is locked. This build has no push notifications. Uses more battery.",
            "ForkExtras.ForceBuiltInMicFooter": "Calls and voice messages use the iPhone microphone even when Bluetooth headphones are connected.",
            "ForkExtras.CallsFooter": "Ask before starting a call.",
            "ForkExtras.TranslationBackend": "Translation",
            "ForkExtras.TranscriptionBackend": "Voice Transcription",
            "ForkExtras.TranslationFooter": "Choose what translates messages and transcribes voice messages. Works without Telegram Premium.",
            "ForkExtras.ScrollToNextChat": "Swipe to Next Chat",
            "ForkExtras.ScrollToNextChatFooter": "Swipe up at the end of a chat to open the next unread one.",
            "ForkExtras.BackendDefault": "Default",
            "ForkExtras.BackendSystem": "System (Apple)",
            "ForkExtras.BackendApple": "On-Device (Apple)",
            "ForkExtras.SaveDeletedMessages": "Save Deleted Messages",
            "ForkExtras.SaveDeletedMessagesFooter": "Deleted messages, including ones that disappear after viewing, stay in the chat marked with 🧹. They are also in View Deleted.",
            "ForkExtras.SaveMessagesHistory": "Save Edit History",
            "ForkExtras.SaveMessagesHistoryFooter": "Keeps the earlier text when a message is edited. Open it from the message menu.",
            "ForkExtras.SaveMedia": "Save Media",
            "ForkExtras.SaveMediaFooter": "Keeps a copy of photos and files when a message is deleted or disappears. Find them in Saved Attachments.",
            "ForkExtras.SaveForBots": "Also Save Bot Messages",
            "ForkExtras.AyuForward": "Forward Anything",
            "ForkExtras.AyuForwardFooter": "Forward from channels that block forwarding, and forward deleted messages. Media is uploaded again, without the original author.",
            "ForkExtras.BypassDownloadRestrictions": "Save Stories & Protected Media",
            "ForkExtras.ShowSensitiveContent": "Show 18+ Content",
            "ForkExtras.ShowSensitiveContentFooter": "Shows 18+ media and chats without blur or an age check, including channels Telegram hides on iPhone. Applies to this phone only.",
            "ForkExtras.BypassDownloadRestrictionsFooter": "Save stories and protected media without Premium, even where forwarding is off. Protected stories no longer hide from screenshots and screen recording.",
            "ForkExtras.ProactiveSaveMedia": "Proactively Download Media",
            "ForkExtras.ProactiveSaveMediaFooter": "Downloads attachments right away, so they are saved before they can disappear or be deleted.",
            "ForkExtras.DeletedMessageMark": "Deleted Message Mark",
            "ForkExtras.DeletedMessageMarkFooter": "Shown next to the time of a kept deleted message.",
            "ForkExtras.EditedMessageMark": "Edited Message Mark",
            "ForkExtras.EditedMessageMarkFooter": "Shown instead of “edited”. Leave empty to keep the default.",
            "ForkExtras.LocalPremium": "Local Telegram Premium",
            "ForkExtras.LocalPremiumFooter": "Premium features that work on this device only: story Stealth Mode, HD stories, sticker effects. Not a subscription; others see no badge.",
            "ForkExtras.AutoFetchMtProxy": "Auto MTProxy",
            "ForkExtras.AutoFetchMtProxyFooter": "Connects through the fastest public MTProxy automatically. These servers aren't added to your saved list. They can't read your chats but can see your IP address.",
            "ForkExtras.HideAds": "Hide Ads",
            "ForkExtras.HideAdsFooter": "Hides sponsored and recommended messages.",
            "ForkExtras.HideBlockedMessages": "Hide Blocked Users",
            "ForkExtras.HideBlockedMessagesFooter": "Hides messages and typing from people you blocked.",
            "ForkExtras.GhostScheduleMessages": "Delay Sending in Ghost Mode",
            "ForkExtras.GhostScheduleMessagesFooter": "In full Ghost Mode, messages are sent after a short delay (about 12 seconds, longer for media), so you don't appear online.",
            "ForkExtras.AllowSecretScreenshots": "Screenshots in Secret Chats",
            "ForkExtras.AllowSecretScreenshotsFooter": "Take screenshots in secret chats and of disappearing media. The other person isn't notified.",
            "ForkExtras.ExpireTtlButton": "Expire Now Button",
            "ForkExtras.ExpireTtlButtonFooter": "Tap the flame on a disappearing photo or video to make it disappear now.",
            "ForkExtras.KeepBannedChats": "Keep Banned Chats",
            "ForkExtras.KeepBannedChatsFooter": "Chats you were removed or banned from stay in the chat list.",
            "ForkExtras.RegexFilters": "Message Filters",
            "ForkExtras.RegexFiltersCaseInsensitive": "Case Insensitive",
            "ForkExtras.RegexFiltersPatterns": "Patterns (one per line)",
            "ForkExtras.RegexFiltersFooter": "Hides messages whose text, buttons or links match a regular expression; a type matches as <type>N</type>. Import with a tg://ayu/filters/import/… link.",
            "ForkExtras.ExportMessageSaving": "Export Deleted and Edited",
            "ForkExtras.ImportMessageSaving": "Import Deleted and Edited",
            "ForkExtras.ImportMessageSavingMerge": "Merge with existing",
            "ForkExtras.ImportMessageSavingReplace": "Replace existing",
            "ForkExtras.MessageSavingDbFooter": "Save or restore the deleted messages, edit history and attachments kept on this device. Import also accepts a records.json file.",
            "ForkExtras.ExportMessageSavingDone": "Exported {count} records.",
            "ForkExtras.ExportMessageSavingFailed": "Could not create the export bundle.",
            "ForkExtras.ImportMessageSavingDone": "Imported {count} new records.",
            "ForkExtras.ImportMessageSavingFailed": "Could not import this file.",
            "ForkExtras.HubFooter": "All BananaGram features are here.",
            "ForkExtras.HubNinja": "Ninja",
            "ForkExtras.HubNinjaLabel": "Deleted messages, filters, protected media",
            "ForkExtras.HubGhost": "Ghost",
            "ForkExtras.HubGhostLabel": "Reading, online status, typing",
            "ForkExtras.HubPrivacy": "Privacy",
            "ForkExtras.HubPrivacyLabel": "Lock, notifications, backup",
            "ForkExtras.HubChatList": "Chat list and folders",
            "ForkExtras.HubChatListLabel": "List, folders",
            "ForkExtras.HubTabBar": "Tab bar",
            "ForkExtras.HubTabBarLabel": "Tabs, search",
            "ForkExtras.HubMessages": "Messages and composer",
            "ForkExtras.HubMessagesLabel": "Bubbles, sending, translation",
            "ForkExtras.HubMedia": "Calls and audio",
            "ForkExtras.HubMediaLabel": "Calls, voice, music",
            "ForkExtras.HubProfile": "Profile and effects",
            "ForkExtras.HubProfileLabel": "Profile details, glow, Premium",
            "ForkExtras.HubNetwork": "Network",
            "ForkExtras.HubNetworkLabel": "Proxy, downloads, background connection",
            "ForkExtras.HideAllChats": "Hide All Chats Tab",
            "ForkExtras.HideAllChatsFooter": "With folders, hide All Chats and show only your folders.",
            "ForkExtras.RememberLastFolder": "Remember Last Folder",
            "ForkExtras.RememberLastFolderFooter": "Open the last used folder after launch or switching accounts.",
            "ForkExtras.HideTabBar": "Hide Tab Bar",
            "ForkExtras.HideTabBarFooter": "Hides the bar at the bottom on iPhone. Settings then opens from the chat list. iPad always shows the bar.",
            "ForkExtras.ShowMessageSeconds": "Seconds in Timestamps",
            "ForkExtras.ShowMessageSecondsFooter": "Show seconds in message times.",
            "ForkExtras.WideChannelPosts": "Wide Channel Posts",
            "ForkExtras.WideChannelPostsFooter": "Messages use more of the screen width.",
            "ForkExtras.StickerSize": "Sticker Size",
            "ForkExtras.DoubleTapToEdit": "Double-Tap to Edit",
            "ForkExtras.DoubleTapToEditFooter": "Double-tap your own message to edit it.",
            "ForkExtras.QuickTranslate": "Quick Translate",
            "ForkExtras.QuickTranslateFooter": "Always show Translate in the message menu.",
            "ForkExtras.SaveToCloud": "Save to Saved Messages",
            "ForkExtras.SaveToCloudFooter": "Adds Save to Saved Messages to the message menu.",
            "ForkExtras.SelectFromAuthor": "Select from Author",
            "ForkExtras.SelectFromAuthorFooter": "Adds a menu action that selects this sender's loaded messages.",
            "ForkExtras.DownloadSpeedBoost": "Download Speed Boost",
            "ForkExtras.DownloadSpeedBoostFooter": "Downloads faster using more connections. Uses more data and battery.",
            "ForkExtras.OutgoingPhotoQuality": "Outgoing Photo Quality",
            "ForkExtras.OutgoingPhotoQualityDefault": "Default (1280)",
            "ForkExtras.OutgoingPhotoQualityBetter": "Better (1920)",
            "ForkExtras.OutgoingPhotoQualityMax": "Maximum (1920, best quality)",
            "ForkExtras.OutgoingPhotoQualityFooter": "Better and Maximum send photos up to 1920 px; Maximum also compresses less. In Low Power Mode or when the phone is hot, photos are sent at 1280 px.",
        ],
        "ru": [
            "ForkExtras.wideTabBar": "Широкая панель вкладок",
            "ForkExtras.integratedTabSearch": "Поиск внутри панели",
            "ForkExtras.tabSearchOnLeft": "Поиск слева",

            "ForkExtras.BottomFolders": "Папки снизу",
            "ForkExtras.AvatarGlow": "Свечение аватарок",
            "ForkExtras.ReactionGlow": "Свечение реакций",
            "ForkExtras.ContactsTab": "Вкладка Контакты",

            "ForkExtras.Title": "Дополнительно",
            "ForkExtras.GhostModeMaster": "Режим призрака",
            "ForkExtras.GhostDontReadMessages": "Не читать сообщения",
            "ForkExtras.GhostDontReadStories": "Не читать истории",
            "ForkExtras.GhostDontSendOnline": "Не отправлять онлайн",
            "ForkExtras.GhostDontSendTyping": "Не отправлять набор",
            "ForkExtras.GhostGoOfflineAutomatically": "Сразу уходить в офлайн",
            "ForkExtras.GhostGoOfflineAutomaticallyFooter": "Сразу уходить в офлайн после короткого появления в сети.",
            "ForkExtras.GhostReadOnInteract": "Читать при взаимодействии",
            "ForkExtras.GhostReadOnInteractFooter": "Если включено «Не читать сообщения», ответ или реакция отмечает чат прочитанным и ненадолго показывает вас в сети.",
            "ForkExtras.GhostAlertBeforeOpeningStory": "Спрашивать перед открытием истории",
            "ForkExtras.GhostAlertBeforeOpeningStoryFooter": "Спрашивать перед открытием истории.",
            "ForkExtras.GhostModeFooter": "Режим призрака включает все пункты «Не…» и «Сразу уходить в офлайн». Каждый можно изменить отдельно.",
            "ForkExtras.InstantPasscode": "Мгновенная блокировка",
            "ForkExtras.InstantPasscodeFooter": "Блокировать приложение сразу, как только вы из него выходите.",
            "ForkExtras.StreamerMode": "Режим стримера",
            "ForkExtras.StreamerModeFooter": "Скрывает номер телефона и имя пользователя в профилях и вверху Настроек.",
            "ForkExtras.HideMentions": "Скрыть уведомления об упоминаниях",
            "ForkExtras.HideMentionsFooter": "Без уведомлений, когда вас упоминают.",
            "ForkExtras.HidePinned": "Скрыть уведомления о закреплении",
            "ForkExtras.HidePinnedFooter": "Без уведомлений о закреплённых сообщениях.",
            "ForkExtras.SessionBackup": "Резерв входа в Связке ключей",
            "ForkExtras.SessionBackupFooter": "Хранит копию входа в Связке ключей iPhone, чтобы после переустановки не входить заново.",
            "ForkExtras.CompactChatList": "Компактный список чатов",
            "ForkExtras.CompactMessagePreview": "Компактное превью сообщений",
            "ForkExtras.CompactFolderNames": "Компактные названия папок",
            "ForkExtras.UIDensityFooter": "На экране помещается больше. Строки остаются удобными для нажатия.",
            "ForkExtras.HideReactionsBar": "Скрыть реакции",
            "ForkExtras.HideReactionsBarFooter": "Скрывает реакции под сообщениями.",
            "ForkExtras.ShowDC": "Показать DC и дату регистрации",
            "ForkExtras.ShowProfileId": "Показать ID профиля",
            "ForkExtras.PrivacyFooter": "Показывает дополнительные сведения в профилях.",
            "ForkExtras.AccentSaturation": "Насыщенность акцентного цвета",
            "ForkExtras.ConfirmBeforeCall": "Подтверждать перед звонком",
            "ForkExtras.SendWithReturnKey": "Отправка по Enter",
            "ForkExtras.SendWithReturnKeyFooter": "Enter отправляет сообщение, а не переносит строку.",
            "ForkExtras.ForceBuiltInMic": "Только встроенный микрофон",
            "ForkExtras.KeepAliveInBackground": "Держать приложение в фоне",
            "ForkExtras.KeepAliveInBackgroundFooter": "Тихий звук не даёт приложению засыпать, поэтому звонки и сообщения приходят при заблокированном экране. В этой сборке нет push-уведомлений. Расходует больше батареи.",
            "ForkExtras.ForceBuiltInMicFooter": "Звонки и голосовые используют микрофон iPhone, даже если подключены Bluetooth-наушники.",
            "ForkExtras.CallsFooter": "Спрашивать перед началом звонка.",
            "ForkExtras.TranslationBackend": "Перевод",
            "ForkExtras.TranscriptionBackend": "Расшифровка голоса",
            "ForkExtras.TranslationFooter": "Выберите, чем переводить сообщения и расшифровывать голосовые. Работает без Telegram Premium.",
            "ForkExtras.ScrollToNextChat": "Свайп к следующему чату",
            "ForkExtras.ScrollToNextChatFooter": "Смахните вверх в конце чата, чтобы открыть следующий непрочитанный.",
            "ForkExtras.BackendDefault": "По умолчанию",
            "ForkExtras.BackendSystem": "Системный (Apple)",
            "ForkExtras.BackendApple": "На устройстве (Apple)",
            "ForkExtras.SaveDeletedMessages": "Сохранять удалённые",
            "ForkExtras.SaveDeletedMessagesFooter": "Удалённые сообщения, включая исчезающие после просмотра, остаются в чате с пометкой 🧹. Они есть и в «Удалённые».",
            "ForkExtras.SaveMessagesHistory": "История правок",
            "ForkExtras.SaveMessagesHistoryFooter": "Сохраняет прежний текст при правке. Открывается из меню сообщения.",
            "ForkExtras.SaveMedia": "Сохранять медиа",
            "ForkExtras.SaveMediaFooter": "Сохраняет копию фото и файлов, когда сообщение удаляют или оно исчезает. Они в «Сохранённых вложениях».",
            "ForkExtras.SaveForBots": "Также сохранять ботов",
            "ForkExtras.AyuForward": "Пересылать всё",
            "ForkExtras.AyuForwardFooter": "Пересылка из каналов с запретом пересылки и пересылка удалённых сообщений. Медиа загружается заново, без автора.",
            "ForkExtras.BypassDownloadRestrictions": "Сохранять истории и защищённые медиа",
            "ForkExtras.ShowSensitiveContent": "Показывать материалы 18+",
            "ForkExtras.ShowSensitiveContentFooter": "Показывает медиа и чаты 18+ без размытия и проверки возраста, включая каналы, которые Telegram скрывает на iPhone. Только на этом телефоне.",
            "ForkExtras.BypassDownloadRestrictionsFooter": "Сохраняйте истории и защищённые медиа без Premium, даже если пересылка запрещена. Защищённые истории больше не прячутся от скриншотов и записи экрана.",
            "ForkExtras.ProactiveSaveMedia": "Активно скачивать медиа",
            "ForkExtras.ProactiveSaveMediaFooter": "Скачивает вложения сразу, чтобы они сохранились до того, как исчезнут или будут удалены.",
            "ForkExtras.DeletedMessageMark": "Метка удалённого",
            "ForkExtras.DeletedMessageMarkFooter": "Показывается рядом со временем у сохранённого удалённого сообщения.",
            "ForkExtras.EditedMessageMark": "Метка изменённого",
            "ForkExtras.EditedMessageMarkFooter": "Показывается вместо «изменено». Оставьте пустым для стандартной метки.",
            "ForkExtras.LocalPremium": "Локальный Telegram Premium",
            "ForkExtras.LocalPremiumFooter": "Функции Premium, работающие только на этом устройстве: скрытый просмотр историй, HD-истории, эффекты стикеров. Это не подписка, значка у вас никто не увидит.",
            "ForkExtras.AutoFetchMtProxy": "Авто MTProxy",
            "ForkExtras.AutoFetchMtProxyFooter": "Автоматически подключается через самый быстрый публичный MTProxy. Эти серверы не попадают в сохранённые. Они не видят ваши чаты, но видят IP-адрес.",
            "ForkExtras.HideAds": "Скрыть рекламу",
            "ForkExtras.HideAdsFooter": "Скрывает спонсорские и рекомендованные сообщения.",
            "ForkExtras.HideBlockedMessages": "Скрыть заблокированных",
            "ForkExtras.HideBlockedMessagesFooter": "Скрывает сообщения и набор текста от заблокированных.",
            "ForkExtras.GhostScheduleMessages": "Задержка отправки в режиме призрака",
            "ForkExtras.GhostScheduleMessagesFooter": "В полном режиме призрака сообщения уходят с небольшой задержкой (около 12 секунд, для медиа дольше), чтобы вы не появлялись в сети.",
            "ForkExtras.AllowSecretScreenshots": "Скриншоты в секретных чатах",
            "ForkExtras.AllowSecretScreenshotsFooter": "Скриншоты в секретных чатах и исчезающих медиа. Собеседник не получает уведомление.",
            "ForkExtras.ExpireTtlButton": "Кнопка «Удалить сейчас»",
            "ForkExtras.ExpireTtlButtonFooter": "Нажмите на пламя у исчезающего фото или видео, чтобы оно исчезло сразу.",
            "ForkExtras.KeepBannedChats": "Сохранять забаненные чаты",
            "ForkExtras.KeepBannedChatsFooter": "Чаты, из которых вас удалили или заблокировали, остаются в списке.",
            "ForkExtras.RegexFilters": "Фильтры сообщений",
            "ForkExtras.RegexFiltersCaseInsensitive": "Без учёта регистра",
            "ForkExtras.RegexFiltersPatterns": "Шаблоны (по одному в строке)",
            "ForkExtras.RegexFiltersFooter": "Скрывает сообщения, текст, кнопки или ссылки которых подходят под регулярное выражение; тип — как <type>N</type>. Импорт — по ссылке tg://ayu/filters/import/…",
            "ForkExtras.ExportMessageSaving": "Экспорт удалённых и правок",
            "ForkExtras.ImportMessageSaving": "Импорт удалённых и правок",
            "ForkExtras.ImportMessageSavingMerge": "Объединить с текущей",
            "ForkExtras.ImportMessageSavingReplace": "Заменить текущую",
            "ForkExtras.MessageSavingDbFooter": "Сохраните или восстановите удалённые сообщения, историю правок и вложения с этого устройства. Импорт также принимает файл records.json.",
            "ForkExtras.ExportMessageSavingDone": "Экспортировано записей: {count}.",
            "ForkExtras.ExportMessageSavingFailed": "Не удалось создать пакет экспорта.",
            "ForkExtras.ImportMessageSavingDone": "Добавлено новых записей: {count}.",
            "ForkExtras.ImportMessageSavingFailed": "Не удалось импортировать файл.",
            "ForkExtras.HubFooter": "Все функции BananaGram собраны здесь.",
            "ForkExtras.HubNinja": "Ниндзя",
            "ForkExtras.HubNinjaLabel": "Удалённые, фильтры, защищённые медиа",
            "ForkExtras.HubGhost": "Невидимка",
            "ForkExtras.HubGhostLabel": "Прочтение, статус в сети, набор",
            "ForkExtras.HubPrivacy": "Приватность",
            "ForkExtras.HubPrivacyLabel": "Блокировка, уведомления, бэкап",
            "ForkExtras.HubChatList": "Список чатов и папки",
            "ForkExtras.HubChatListLabel": "Список, папки",
            "ForkExtras.HubTabBar": "Панель вкладок",
            "ForkExtras.HubTabBarLabel": "Вкладки, поиск",
            "ForkExtras.HubMessages": "Сообщения и ввод",
            "ForkExtras.HubMessagesLabel": "Пузыри, отправка, перевод",
            "ForkExtras.HubMedia": "Звонки и звук",
            "ForkExtras.HubMediaLabel": "Звонки, голосовые, музыка",
            "ForkExtras.HubProfile": "Профиль и эффекты",
            "ForkExtras.HubProfileLabel": "Сведения профиля, свечение, Premium",
            "ForkExtras.HubNetwork": "Сеть",
            "ForkExtras.HubNetworkLabel": "Прокси, загрузки, работа в фоне",
            "ForkExtras.HideAllChats": "Скрыть «Все чаты»",
            "ForkExtras.HideAllChatsFooter": "Если есть папки, скрыть «Все чаты» и показывать только папки.",
            "ForkExtras.RememberLastFolder": "Запоминать последнюю папку",
            "ForkExtras.RememberLastFolderFooter": "Открывать последнюю папку после запуска или смены аккаунта.",
            "ForkExtras.HideTabBar": "Скрыть панель вкладок",
            "ForkExtras.HideTabBarFooter": "Скрывает нижнюю панель на iPhone. Настройки открываются из списка чатов. На iPad панель видна всегда.",
            "ForkExtras.ShowMessageSeconds": "Секунды во времени",
            "ForkExtras.ShowMessageSecondsFooter": "Показывать секунды во времени сообщений.",
            "ForkExtras.WideChannelPosts": "Широкие посты",
            "ForkExtras.WideChannelPostsFooter": "Сообщения занимают больше ширины экрана.",
            "ForkExtras.StickerSize": "Размер стикеров",
            "ForkExtras.DoubleTapToEdit": "Двойной тап — править",
            "ForkExtras.DoubleTapToEditFooter": "Дважды нажмите своё сообщение, чтобы изменить его.",
            "ForkExtras.QuickTranslate": "Быстрый перевод",
            "ForkExtras.QuickTranslateFooter": "Всегда показывать «Перевести» в меню сообщения.",
            "ForkExtras.SaveToCloud": "В Избранное",
            "ForkExtras.SaveToCloudFooter": "Добавляет в меню сообщения пункт «В Избранное».",
            "ForkExtras.SelectFromAuthor": "Выбрать от автора",
            "ForkExtras.SelectFromAuthorFooter": "Добавляет в меню пункт, который выделяет загруженные сообщения этого отправителя.",
            "ForkExtras.DownloadSpeedBoost": "Ускорить загрузки",
            "ForkExtras.DownloadSpeedBoostFooter": "Загрузка быстрее за счёт нескольких соединений. Расходует больше трафика и батареи.",
            "ForkExtras.OutgoingPhotoQuality": "Качество исходящих фото",
            "ForkExtras.OutgoingPhotoQualityDefault": "Обычное (1280)",
            "ForkExtras.OutgoingPhotoQualityBetter": "Лучше (1920)",
            "ForkExtras.OutgoingPhotoQualityMax": "Максимум (1920, лучшее качество)",
            "ForkExtras.OutgoingPhotoQualityFooter": "«Лучше» и «Максимум» отправляют фото до 1920 px, «Максимум» ещё и сжимает слабее. В режиме энергосбережения или при нагреве фото уходят в 1280 px.",
        ],
    ]
    
    private static func languageCode() -> String {
        return ForkPresentationLanguage.prefersRussianStrings ? "ru" : "en"
    }
    
    static func string(forKey key: String) -> String {
        let code = languageCode()
        if let value = translations[code]?[key] {
            return value
        }
        return translations["en"]?[key] ?? key
    }
    
    static var title: String { string(forKey: "ForkExtras.Title") }
    static var ghostModeMaster: String { string(forKey: "ForkExtras.GhostModeMaster") }
    static var ghostDontReadMessages: String { string(forKey: "ForkExtras.GhostDontReadMessages") }
    static var ghostDontReadStories: String { string(forKey: "ForkExtras.GhostDontReadStories") }
    static var ghostDontSendOnline: String { string(forKey: "ForkExtras.GhostDontSendOnline") }
    static var ghostDontSendTyping: String { string(forKey: "ForkExtras.GhostDontSendTyping") }
    static var ghostGoOfflineAutomatically: String { string(forKey: "ForkExtras.GhostGoOfflineAutomatically") }
    static var ghostGoOfflineAutomaticallyFooter: String { string(forKey: "ForkExtras.GhostGoOfflineAutomaticallyFooter") }
    static var ghostReadOnInteract: String { string(forKey: "ForkExtras.GhostReadOnInteract") }
    static var ghostReadOnInteractFooter: String { string(forKey: "ForkExtras.GhostReadOnInteractFooter") }
    static var ghostAlertBeforeOpeningStory: String { string(forKey: "ForkExtras.GhostAlertBeforeOpeningStory") }
    static var ghostAlertBeforeOpeningStoryFooter: String { string(forKey: "ForkExtras.GhostAlertBeforeOpeningStoryFooter") }
    static var ghostModeFooter: String { string(forKey: "ForkExtras.GhostModeFooter") }
    static var instantPasscode: String { string(forKey: "ForkExtras.InstantPasscode") }
    static var instantPasscodeFooter: String { string(forKey: "ForkExtras.InstantPasscodeFooter") }
    static var streamerMode: String { string(forKey: "ForkExtras.StreamerMode") }
    static var streamerModeFooter: String { string(forKey: "ForkExtras.StreamerModeFooter") }
    static var hideMentions: String { string(forKey: "ForkExtras.HideMentions") }
    static var hideMentionsFooter: String { string(forKey: "ForkExtras.HideMentionsFooter") }
    static var hidePinned: String { string(forKey: "ForkExtras.HidePinned") }
    static var hidePinnedFooter: String { string(forKey: "ForkExtras.HidePinnedFooter") }
    static var sessionBackup: String { string(forKey: "ForkExtras.SessionBackup") }
    static var sessionBackupFooter: String { string(forKey: "ForkExtras.SessionBackupFooter") }
    static var compactChatList: String { string(forKey: "ForkExtras.CompactChatList") }
    static var compactMessagePreview: String { string(forKey: "ForkExtras.CompactMessagePreview") }
    static var compactFolderNames: String { string(forKey: "ForkExtras.CompactFolderNames") }
    static var uiDensityFooter: String { string(forKey: "ForkExtras.UIDensityFooter") }
    static var hideReactionsBar: String { string(forKey: "ForkExtras.HideReactionsBar") }
    static var hideReactionsBarFooter: String { string(forKey: "ForkExtras.HideReactionsBarFooter") }
    static var showDC: String { string(forKey: "ForkExtras.ShowDC") }
    static var showProfileId: String { string(forKey: "ForkExtras.ShowProfileId") }
    static var privacyFooter: String { string(forKey: "ForkExtras.PrivacyFooter") }
    static var accentSaturation: String { string(forKey: "ForkExtras.AccentSaturation") }
    static var confirmBeforeCall: String { string(forKey: "ForkExtras.ConfirmBeforeCall") }
    static var sendWithReturnKey: String { string(forKey: "ForkExtras.SendWithReturnKey") }
    static var sendWithReturnKeyFooter: String { string(forKey: "ForkExtras.SendWithReturnKeyFooter") }
    static var forceBuiltInMic: String { string(forKey: "ForkExtras.ForceBuiltInMic") }
    static var forceBuiltInMicFooter: String { string(forKey: "ForkExtras.ForceBuiltInMicFooter") }
    static var keepAliveInBackground: String { string(forKey: "ForkExtras.KeepAliveInBackground") }
    static var keepAliveInBackgroundFooter: String { string(forKey: "ForkExtras.KeepAliveInBackgroundFooter") }
    static var callsFooter: String { string(forKey: "ForkExtras.CallsFooter") }
    static var translationBackend: String { string(forKey: "ForkExtras.TranslationBackend") }
    static var transcriptionBackend: String { string(forKey: "ForkExtras.TranscriptionBackend") }
    static var translationFooter: String { string(forKey: "ForkExtras.TranslationFooter") }
    static var scrollToNextChat: String { string(forKey: "ForkExtras.ScrollToNextChat") }
    static var scrollToNextChatFooter: String { string(forKey: "ForkExtras.ScrollToNextChatFooter") }
    static var saveDeletedMessages: String { string(forKey: "ForkExtras.SaveDeletedMessages") }
    static var saveDeletedMessagesFooter: String { string(forKey: "ForkExtras.SaveDeletedMessagesFooter") }
    static var saveMessagesHistory: String { string(forKey: "ForkExtras.SaveMessagesHistory") }
    static var saveMessagesHistoryFooter: String { string(forKey: "ForkExtras.SaveMessagesHistoryFooter") }
    static var saveMedia: String { string(forKey: "ForkExtras.SaveMedia") }
    static var saveMediaFooter: String { string(forKey: "ForkExtras.SaveMediaFooter") }
    static var saveForBots: String { string(forKey: "ForkExtras.SaveForBots") }
    static var ayuForward: String { string(forKey: "ForkExtras.AyuForward") }
    static var ayuForwardFooter: String { string(forKey: "ForkExtras.AyuForwardFooter") }
    static var bypassDownloadRestrictions: String { string(forKey: "ForkExtras.BypassDownloadRestrictions") }
    static var showSensitiveContent: String { string(forKey: "ForkExtras.ShowSensitiveContent") }
    static var showSensitiveContentFooter: String { string(forKey: "ForkExtras.ShowSensitiveContentFooter") }
    static var bypassDownloadRestrictionsFooter: String { string(forKey: "ForkExtras.BypassDownloadRestrictionsFooter") }
    static var proactiveSaveMedia: String { string(forKey: "ForkExtras.ProactiveSaveMedia") }
    static var proactiveSaveMediaFooter: String { string(forKey: "ForkExtras.ProactiveSaveMediaFooter") }
    static var deletedMessageMark: String { string(forKey: "ForkExtras.DeletedMessageMark") }
    static var deletedMessageMarkFooter: String { string(forKey: "ForkExtras.DeletedMessageMarkFooter") }
    static var editedMessageMark: String { string(forKey: "ForkExtras.EditedMessageMark") }
    static var editedMessageMarkFooter: String { string(forKey: "ForkExtras.EditedMessageMarkFooter") }
    static var localPremium: String { string(forKey: "ForkExtras.LocalPremium") }
    static var localPremiumFooter: String { string(forKey: "ForkExtras.LocalPremiumFooter") }
    static var autoFetchMtProxy: String { string(forKey: "ForkExtras.AutoFetchMtProxy") }
    static var autoFetchMtProxyFooter: String { string(forKey: "ForkExtras.AutoFetchMtProxyFooter") }
    static var hideAds: String { string(forKey: "ForkExtras.HideAds") }
    static var hideAdsFooter: String { string(forKey: "ForkExtras.HideAdsFooter") }
    static var hideBlockedMessages: String { string(forKey: "ForkExtras.HideBlockedMessages") }
    static var hideBlockedMessagesFooter: String { string(forKey: "ForkExtras.HideBlockedMessagesFooter") }
    static var ghostScheduleMessages: String { string(forKey: "ForkExtras.GhostScheduleMessages") }
    static var ghostScheduleMessagesFooter: String { string(forKey: "ForkExtras.GhostScheduleMessagesFooter") }
    static var allowSecretScreenshots: String { string(forKey: "ForkExtras.AllowSecretScreenshots") }
    static var allowSecretScreenshotsFooter: String { string(forKey: "ForkExtras.AllowSecretScreenshotsFooter") }
    static var expireTtlButton: String { string(forKey: "ForkExtras.ExpireTtlButton") }
    static var expireTtlButtonFooter: String { string(forKey: "ForkExtras.ExpireTtlButtonFooter") }
    static var keepBannedChats: String { string(forKey: "ForkExtras.KeepBannedChats") }
    static var keepBannedChatsFooter: String { string(forKey: "ForkExtras.KeepBannedChatsFooter") }
    static var regexFilters: String { string(forKey: "ForkExtras.RegexFilters") }
    static var regexFiltersCaseInsensitive: String { string(forKey: "ForkExtras.RegexFiltersCaseInsensitive") }
    static var regexFiltersPatterns: String { string(forKey: "ForkExtras.RegexFiltersPatterns") }
    static var regexFiltersFooter: String { string(forKey: "ForkExtras.RegexFiltersFooter") }
    static var exportMessageSaving: String { string(forKey: "ForkExtras.ExportMessageSaving") }
    static var importMessageSaving: String { string(forKey: "ForkExtras.ImportMessageSaving") }
    static var importMessageSavingMerge: String { string(forKey: "ForkExtras.ImportMessageSavingMerge") }
    static var importMessageSavingReplace: String { string(forKey: "ForkExtras.ImportMessageSavingReplace") }
    static var messageSavingDbFooter: String { string(forKey: "ForkExtras.MessageSavingDbFooter") }
    static var exportMessageSavingDone: String { string(forKey: "ForkExtras.ExportMessageSavingDone") }
    static var exportMessageSavingFailed: String { string(forKey: "ForkExtras.ExportMessageSavingFailed") }
    static var importMessageSavingDone: String { string(forKey: "ForkExtras.ImportMessageSavingDone") }
    static var importMessageSavingFailed: String { string(forKey: "ForkExtras.ImportMessageSavingFailed") }
    static var hubFooter: String { string(forKey: "ForkExtras.HubFooter") }
    static var hubNinja: String { string(forKey: "ForkExtras.HubNinja") }
    static var hubNinjaLabel: String { string(forKey: "ForkExtras.HubNinjaLabel") }
    static var hubGhost: String { string(forKey: "ForkExtras.HubGhost") }
    static var hubGhostLabel: String { string(forKey: "ForkExtras.HubGhostLabel") }
    static var hubPrivacy: String { string(forKey: "ForkExtras.HubPrivacy") }
    static var hubPrivacyLabel: String { string(forKey: "ForkExtras.HubPrivacyLabel") }
    static var hubChatList: String { string(forKey: "ForkExtras.HubChatList") }
    static var hubChatListLabel: String { string(forKey: "ForkExtras.HubChatListLabel") }
    static var hubTabBar: String { string(forKey: "ForkExtras.HubTabBar") }
    static var hubTabBarLabel: String { string(forKey: "ForkExtras.HubTabBarLabel") }
    static var hubMessages: String { string(forKey: "ForkExtras.HubMessages") }
    static var hubMessagesLabel: String { string(forKey: "ForkExtras.HubMessagesLabel") }
    static var hubMedia: String { string(forKey: "ForkExtras.HubMedia") }
    static var hubMediaLabel: String { string(forKey: "ForkExtras.HubMediaLabel") }
    static var hubProfile: String { string(forKey: "ForkExtras.HubProfile") }
    static var hubProfileLabel: String { string(forKey: "ForkExtras.HubProfileLabel") }
    static var hubNetwork: String { string(forKey: "ForkExtras.HubNetwork") }
    static var hubNetworkLabel: String { string(forKey: "ForkExtras.HubNetworkLabel") }
    static var hideAllChats: String { string(forKey: "ForkExtras.HideAllChats") }
    static var hideAllChatsFooter: String { string(forKey: "ForkExtras.HideAllChatsFooter") }
    static var rememberLastFolder: String { string(forKey: "ForkExtras.RememberLastFolder") }
    static var rememberLastFolderFooter: String { string(forKey: "ForkExtras.RememberLastFolderFooter") }
    static var hideTabBar: String { string(forKey: "ForkExtras.HideTabBar") }
    static var hideTabBarFooter: String { string(forKey: "ForkExtras.HideTabBarFooter") }
    static var showMessageSeconds: String { string(forKey: "ForkExtras.ShowMessageSeconds") }
    static var showMessageSecondsFooter: String { string(forKey: "ForkExtras.ShowMessageSecondsFooter") }
    static var wideChannelPosts: String { string(forKey: "ForkExtras.WideChannelPosts") }
    static var wideChannelPostsFooter: String { string(forKey: "ForkExtras.WideChannelPostsFooter") }
    static var stickerSize: String { string(forKey: "ForkExtras.StickerSize") }
    static var doubleTapToEdit: String { string(forKey: "ForkExtras.DoubleTapToEdit") }
    static var doubleTapToEditFooter: String { string(forKey: "ForkExtras.DoubleTapToEditFooter") }
    static var quickTranslate: String { string(forKey: "ForkExtras.QuickTranslate") }
    static var quickTranslateFooter: String { string(forKey: "ForkExtras.QuickTranslateFooter") }
    static var saveToCloud: String { string(forKey: "ForkExtras.SaveToCloud") }
    static var saveToCloudFooter: String { string(forKey: "ForkExtras.SaveToCloudFooter") }
    static var selectFromAuthor: String { string(forKey: "ForkExtras.SelectFromAuthor") }
    static var selectFromAuthorFooter: String { string(forKey: "ForkExtras.SelectFromAuthorFooter") }
    static var downloadSpeedBoost: String { string(forKey: "ForkExtras.DownloadSpeedBoost") }
    static var downloadSpeedBoostFooter: String { string(forKey: "ForkExtras.DownloadSpeedBoostFooter") }
    static var outgoingPhotoQuality: String { string(forKey: "ForkExtras.OutgoingPhotoQuality") }
    static var outgoingPhotoQualityDefault: String { string(forKey: "ForkExtras.OutgoingPhotoQualityDefault") }
    static var outgoingPhotoQualityBetter: String { string(forKey: "ForkExtras.OutgoingPhotoQualityBetter") }
    static var outgoingPhotoQualityMax: String { string(forKey: "ForkExtras.OutgoingPhotoQualityMax") }
    static var outgoingPhotoQualityFooter: String { string(forKey: "ForkExtras.OutgoingPhotoQualityFooter") }
    static var backendDefault: String { string(forKey: "ForkExtras.BackendDefault") }
    static var backendSystem: String { string(forKey: "ForkExtras.BackendSystem") }
    static var backendApple: String { string(forKey: "ForkExtras.BackendApple") }
}

private enum ForkExtrasDestination: Equatable {
    case proxy
    case security
    case accountOrder
    /// Scene 40/45: the connection status screen (route, state, the selected server's last response).
    case connectionCheck
    /// The two pages split off Messages and composer, so that screen shows what a chat looks like and links to the rest.
    case messageSending
    case messageActions
    case voiceAndRound
    /// Less used Messages and Profile switches, one level deeper (Apple HIG: few settings up front).
    case messagesMore
    case profileMore
}

private final class ForkExtrasControllerArguments {
    let updateGhostModeMaster: (Bool) -> Void
    let updateGhostReadOnInteract: (Bool) -> Void
    let openAccentSaturation: () -> Void
    let openTranslationBackend: () -> Void
    let openTranscriptionBackend: () -> Void
    let updateScrollToNextChatDisabled: (Bool) -> Void
    let updateDeletedMessageMark: (String) -> Void
    let updateEditedMessageMark: (String) -> Void
    let updateGhostScheduleMessages: (Bool) -> Void
    let updateRegexFilterPatternsText: (String) -> Void
    let exportMessageSavingDatabase: () -> Void
    let importMessageSavingDatabase: () -> Void
    let openDestination: (ForkExtrasDestination) -> Void
    let updateMusicPolicy: (Int32, Bool) -> Void
    let openCategory: (ForkExtrasControllerFocus) -> Void
    let context: AccountContext
    let openBrandTheme: (Bool) -> Void
    let updateCallsTab: (Bool) -> Void
    let updateAppearance: (WritableKeyPath<ForkExtrasSettings, Bool>, Bool) -> Void
    let openStickerSize: () -> Void
    let openOutgoingPhotoQuality: () -> Void
    let openIntChoice: (Int32) -> Void

    init(
        updateGhostModeMaster: @escaping (Bool) -> Void,
        updateGhostReadOnInteract: @escaping (Bool) -> Void,
        openAccentSaturation: @escaping () -> Void,
        openTranslationBackend: @escaping () -> Void,
        openTranscriptionBackend: @escaping () -> Void,
        updateScrollToNextChatDisabled: @escaping (Bool) -> Void,
        updateDeletedMessageMark: @escaping (String) -> Void,
        updateEditedMessageMark: @escaping (String) -> Void,
        updateGhostScheduleMessages: @escaping (Bool) -> Void,
        updateRegexFilterPatternsText: @escaping (String) -> Void,
        exportMessageSavingDatabase: @escaping () -> Void,
        importMessageSavingDatabase: @escaping () -> Void,
        openDestination: @escaping (ForkExtrasDestination) -> Void,
        updateMusicPolicy: @escaping (Int32, Bool) -> Void,
        openCategory: @escaping (ForkExtrasControllerFocus) -> Void,
        context: AccountContext,
        openBrandTheme: @escaping (Bool) -> Void,
        updateCallsTab: @escaping (Bool) -> Void,
        updateAppearance: @escaping (WritableKeyPath<ForkExtrasSettings, Bool>, Bool) -> Void,
        openStickerSize: @escaping () -> Void,
        openOutgoingPhotoQuality: @escaping () -> Void,
        openIntChoice: @escaping (Int32) -> Void
    ) {
        self.updateGhostModeMaster = updateGhostModeMaster
        self.updateGhostReadOnInteract = updateGhostReadOnInteract
        self.openAccentSaturation = openAccentSaturation
        self.openTranslationBackend = openTranslationBackend
        self.openTranscriptionBackend = openTranscriptionBackend
        self.updateScrollToNextChatDisabled = updateScrollToNextChatDisabled
        self.updateDeletedMessageMark = updateDeletedMessageMark
        self.updateEditedMessageMark = updateEditedMessageMark
        self.updateGhostScheduleMessages = updateGhostScheduleMessages
        self.updateRegexFilterPatternsText = updateRegexFilterPatternsText
        self.exportMessageSavingDatabase = exportMessageSavingDatabase
        self.importMessageSavingDatabase = importMessageSavingDatabase
        self.openDestination = openDestination
        self.updateMusicPolicy = updateMusicPolicy
        self.openCategory = openCategory
        self.context = context
        self.openBrandTheme = openBrandTheme
        self.updateCallsTab = updateCallsTab
        self.updateAppearance = updateAppearance
        self.openStickerSize = openStickerSize
        self.openOutgoingPhotoQuality = openOutgoingPhotoQuality
        self.openIntChoice = openIntChoice
    }
}

private enum ForkExtrasSection: Int32 {
    case hub
    case ghost
    case lock
    case notifications
    case backup
    case uiDensity
    case privacy
    case calls
    case translation
    case navigation
    case messageSaving
    case messageFilters
    case smallThings
    case premium
    case proxy
    case folders
    case appearance
    case chatExtras
    case downloads
    case audio
    case developer
    case archive
    case backgroundConnection
    // The Extras hub (scene 37): the header card, then "Sections", then "Interface" (which is `hub`'s second half).
    case hubCard
    case hubLook
    // The Network page's connection card (scene 40).
    case connectionStatus
}

private enum ForkExtrasEntry: ItemListNodeEntry {
    case destination(Int32, String, ForkExtrasDestination)
    case audioHeader
    case musicPolicy(Int32, String, Bool)
    case designHeader(Int32, String)
    case designFooter(Int32, String)
    case brandTheme(Bool)

    /// The Extras screens that are made of explicit blocks, each block listing its rows in display order. A block is a
    /// rounded section: its header (16xx) first, its switches, and the footer that explains them last. Footers used to
    /// sit between switches inside a block, which made the screen read as one run-together list. Rows are grouped by the
    /// window they change, so a setting is where the thing it affects is.
    private static let regroupedCategories: [(focus: ForkExtrasControllerFocus, groups: [[Int32]])] = [
        (.chatList, [
            [1602, 50, 51, 53],
            [1601, 52, 1499, 1546, 1547, 1548, 1549],
            [59, 60],
            [61, 62],
            [1512],
            [1773, 1774, 1790],
            [1930],
            [2038, 2039],
            [1961, 1963]
        ]),
        (.tabBar, [
            [63, 64],
            [1502, 1503, 1504, 1505, 1506],
            [1507]
        ]),
        (.appearance, [[1618, 1531, 1532, 1553, 1619], [1900, 1901, 1902, 1903, 1904, 1905, 1906]]),
        // Scene 38: the input panel opens Messages. Scene 39: round videos and voice open Media, calls follow.
        (.messages, [
            [2200, 2201, 2043],
            [1605, 65, 1557, 1558, 67, 69, 68],
            [1508, 1509, 1735, 54, 1521, 1550, 1519],
            [1720, 1711, 1703, 1713, 1716, 1719, 1717, 1718, 1791],
            [88, 89],
            [85, 86, 87],
            [2036, 2037]
        ]),
        (.messagesMore, [
            [1931],
            [1940, 1941, 1942, 1943],
            [1944],
            [1721, 1542, 1712, 1700, 1701, 1702],
            [1533],
            [1518],
            [1607, 1510, 1513, 1517],
            [1825, 1826, 1827, 1828],
            [1960, 1962, 1964]
        ]),
        (.messageSending, [
            [1850, 2101, 2102, 1851, 1852, 1853],
            [1606, 1710, 81, 82],
            [98, 99],
            [1511, 1520, 2040, 2041]
        ]),
        (.messageActions, [
            [1802],
            [1800, 1801, 1803],
            [92, 93],
            [94, 95],
            [96, 97],
            [1910, 1911]
        ]),
        (.voiceAndRound, [
            [1609, 2110, 2111, 2112, 2113, 2114, 1544, 1545, 2115],
            [2042, 1515, 1516, 1559, 1612]
        ]),
        (.media, [
            [2202],
            [1608, 80, 84],
            [83],
            [1613, 1554, 1555, 1556, 1614, 1982],
            [1750, 1751, 1752, 1753, 1754, 1755, 1756, 2021, 1757, 1758],
            [1860, 1861, 1862, 1863, 1864, 1865],
            [1912, 1913, 1914],
            [2000, 2001, 2002, 2003, 2004]
        ]),
        (.profile, [
            [55, 56, 1551, 1714, 2020, 1552, 1543, 58],
            [1739, 1731, 1732, 1730, 1733, 1734, 1980, 1981, 2106],
            [2034, 2035],
            [2044]
        ]),
        (.profileMore, [
            [1740, 1736, 1737, 1738],
            [1603, 1500, 1501, 1541, 2022, 57],
            [1604, 140, 141]
        ]),
        (.ghost, [[1560, 1561, 1562], [1770, 1771, 1772]]),
        (.privacy, [
            [28, 2032, 29],
            [30, 31],
            [2045, 32, 34],
            [2046, 38, 1775, 40, 39, 41],
            [42, 43],
            [1530, 2030, 2031]
        ])
    ]

    private static let interfaceGroups: [[Int32]] = regroupedCategories.flatMap { $0.groups }

    /// The screen that owns a row after the regrouping, so links and search results made when the rows were spread over
    /// the old Interface and Chats screens still open on the right page.
    static func regroupedOwner(of id: Int32) -> ForkExtrasControllerFocus? {
        return regroupedCategories.first(where: { category in category.groups.contains(where: { $0.contains(id) }) })?.focus
    }

    case hubAppearance
    case hubNinja
    case hubGhost
    case hubPrivacy
    case hubChatList
    case hubTabBar
    case hubMessages
    case hubMedia
    case hubProfile
    case hubNetwork
    case hubCard
    case hubSectionsHeader
    case hubLookHeader
    /// Network page (scene 40): how the app connects right now. `detail` is the proxy's kind and host, never a secret.
    case connectionStatus(title: String, detail: String, viaProxy: Bool)
    case ghostModeMaster(Bool)
    case ghostReadOnInteract(Bool)
    case ghostScheduleMessages(Bool)
    case accentSaturation(Int32)
    case translationBackend(ForkTranslationBackend)
    case transcriptionBackend(ForkTranscriptionBackend)
    case scrollToNextChat(Bool)
    case deletedMessageMark(String)
    case editedMessageMark(String)
    case exportMessageSavingDatabase
    case importMessageSavingDatabase
    case regexFiltersPatterns(String)
    case regexFiltersFooter(Int)
    case tabPreview(BananaTabBarLayout)
    case callsTab(Bool)
    case appearanceToggle(Int32, String, Bool, WritableKeyPath<ForkExtrasSettings, Bool>)
    /// A plain on/off row for one setting: its id (stable: links, search and the screen's grouping use it), the
    /// section it is drawn in outside the regrouped screens, its title, its value and the setting it writes.
    case settingToggle(Int32, ForkExtrasSection, String, Bool, WritableKeyPath<ForkExtrasSettings, Bool>)
    /// The plain explanation under a block: its id, its section outside the regrouped screens, and its text.
    case settingFooter(Int32, ForkExtrasSection, String)
    case stickerSize(Int32)
    /// A row that opens a list of numeric choices (id, title, current value's label); `openIntChoice` picks by id.
    case intChoice(Int32, String, String)
    case outgoingPhotoQuality(Int32)
    case visualPhoneNumber(String)

    var section: ItemListSectionId {
        if let group = Self.interfaceGroups.firstIndex(where: { $0.contains(self.stableId) }) {
            return Int32(100 + group)
        }
        switch self {
        case let .settingToggle(_, section, _, _, _), let .settingFooter(_, section, _):
            return section.rawValue
        case let .destination(_, _, destination):
            switch destination {
            case .proxy: return ForkExtrasSection.proxy.rawValue
            case .security: return ForkExtrasSection.hub.rawValue
            case .accountOrder: return ForkExtrasSection.hubLook.rawValue
            case .connectionCheck: return ForkExtrasSection.proxy.rawValue
            case .messageSending, .messageActions, .voiceAndRound, .messagesMore, .profileMore: return ForkExtrasSection.appearance.rawValue
            }
        case .audioHeader, .musicPolicy: return ForkExtrasSection.audio.rawValue
        case .designHeader, .designFooter, .brandTheme: return 100
        case .hubSectionsHeader, .hubNinja, .hubGhost, .hubPrivacy, .hubMessages, .hubMedia, .hubProfile, .hubNetwork:
            return ForkExtrasSection.hub.rawValue
        case .hubLookHeader, .hubAppearance, .hubChatList, .hubTabBar:
            return ForkExtrasSection.hubLook.rawValue
        case .hubCard:
            return ForkExtrasSection.hubCard.rawValue
        case .connectionStatus:
            return ForkExtrasSection.connectionStatus.rawValue
        case .ghostModeMaster, .ghostReadOnInteract, .ghostScheduleMessages:
            return ForkExtrasSection.ghost.rawValue
        case .accentSaturation:
            return ForkExtrasSection.privacy.rawValue
        case .translationBackend, .transcriptionBackend:
            return ForkExtrasSection.translation.rawValue
        case .scrollToNextChat:
            return ForkExtrasSection.navigation.rawValue
        case .deletedMessageMark, .editedMessageMark, .exportMessageSavingDatabase, .importMessageSavingDatabase:
            return ForkExtrasSection.messageSaving.rawValue
        case .regexFiltersPatterns, .regexFiltersFooter:
            return ForkExtrasSection.messageFilters.rawValue
        case .tabPreview, .callsTab, .appearanceToggle, .visualPhoneNumber, .intChoice, .stickerSize:
            return ForkExtrasSection.appearance.rawValue
        case .outgoingPhotoQuality:
            return ForkExtrasSection.chatExtras.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .destination(id, _, _): return id
        case .audioHeader: return 2000
        case let .musicPolicy(id, _, _): return id
        case let .designHeader(id, _): return id
        case let .designFooter(id, _): return id
        case let .brandTheme(dark): return dark ? 1611 : 1610
        case .tabPreview: return 1507
        case .callsTab: return 1503
        case let .appearanceToggle(id, _, _, _): return id
        case let .settingToggle(id, _, _, _, _): return id
        case let .settingFooter(id, _, _): return id
        case let .intChoice(id, _, _): return id
        case .hubAppearance: return 1540
        case .hubNinja: return 0
        case .hubGhost: return 1
        case .hubPrivacy: return 2
        case .hubChatList: return 3
        case .hubMessages: return 4
        case .hubTabBar: return 7
        case .hubMedia: return 8
        case .hubProfile: return 23
        case .hubNetwork: return 5
        case .hubCard: return 1996
        // Not 2110: that id is the round video countdown, whose block placed this card at the end of the Network page.
        case .connectionStatus: return 2109
        case .hubSectionsHeader: return 1997
        case .hubLookHeader: return 1998
        case .ghostModeMaster: return 9
        case .ghostReadOnInteract: return 16
        case .ghostScheduleMessages: return 20
        case .accentSaturation: return 57
        case .stickerSize: return 69
        case .translationBackend: return 85
        case .transcriptionBackend: return 86
        case .scrollToNextChat: return 88
        case .outgoingPhotoQuality: return 98
        case .visualPhoneNumber: return 1737
        case .deletedMessageMark: return 123
        case .editedMessageMark: return 125
        case .exportMessageSavingDatabase: return 127
        case .importMessageSavingDatabase: return 128
        case .regexFiltersPatterns: return 136
        case .regexFiltersFooter: return 137
        }
    }

    /// Rows added later whose stable id (kept for settings links) does not follow the row they are shown after.
    /// The list diff merges sorted lists, so `<` has to agree with the display order or rows that appear and
    /// disappear (the regex filter rows) get inserted next to stale copies and are drawn twice.
    private static let positionOverrides: [Int32: Double] = [
        // The Extras hub (scene 37): card, Sections (Ninja ... Network), Interface (Chat list ... Appearance), footer.
        1996: -2.0,    // The header card.
        1997: -1.0,    // "Sections".
        1995: 2.5,     // Security follows Privacy on the Extras hub.
        1998: 5.2,     // "Interface" follows Network.
        3: 5.3,        // Chat list and folders opens Interface.
        2100: 5.5,     // Account order.
        2109: 137.0,   // The Network page's connection card opens the page.
        2105: 137.5,
        2103: 144.3,
        2104: 144.5,
        7: 5.4,        // Tab bar follows Chat list and folders.
        8: 4.3,        // Calls and audio follows Messages and composer.
        23: 4.6,       // Profile and effects follows Calls and audio.
        1540: 5.6,     // Appearance closes Interface on the Extras hub.
        // 146 now belongs to Network; its original stable order is appropriate there.
        147: 133.3,     // Show 18+ Content, after Hide Blocked Messages
        148: 133.6,
    ]
    
    private var sortPosition: Double {
        if let index = Self.interfaceGroups.flatMap({ $0 }).firstIndex(of: self.stableId) {
            return Double(1000 + index)
        }
        return Self.positionOverrides[self.stableId] ?? Double(self.stableId)
    }
    
    static func <(lhs: ForkExtrasEntry, rhs: ForkExtrasEntry) -> Bool {
        return lhs.sortPosition < rhs.sortPosition
    }

    /// The row's title for Settings search, or nil for headers, footers and rows search should not offer.
    func searchTitle(strings: PresentationStrings) -> String? {
        switch self {
        case let .musicPolicy(_, title, _), let .appearanceToggle(_, title, _, _), let .settingToggle(_, _, title, _, _), let .intChoice(_, title, _):
            return title
        case .callsTab:
            return strings.Calls_TabTitle
        case .ghostModeMaster: return ForkExtrasLocalizedString.ghostModeMaster
        case .ghostReadOnInteract: return ForkExtrasLocalizedString.ghostReadOnInteract
        case .ghostScheduleMessages: return ForkExtrasLocalizedString.ghostScheduleMessages
        case .accentSaturation: return ForkExtrasLocalizedString.accentSaturation
        case .translationBackend: return ForkExtrasLocalizedString.translationBackend
        case .transcriptionBackend: return ForkExtrasLocalizedString.transcriptionBackend
        case .scrollToNextChat: return ForkExtrasLocalizedString.scrollToNextChat
        case .deletedMessageMark: return ForkExtrasLocalizedString.deletedMessageMark
        case .editedMessageMark: return ForkExtrasLocalizedString.editedMessageMark
        case .exportMessageSavingDatabase: return ForkExtrasLocalizedString.exportMessageSaving
        case .importMessageSavingDatabase: return ForkExtrasLocalizedString.importMessageSaving
        case .stickerSize: return ForkExtrasLocalizedString.stickerSize
        case .outgoingPhotoQuality: return ForkExtrasLocalizedString.outgoingPhotoQuality
        case .visualPhoneNumber: return ForkPresentationLanguage.prefersRussianStrings ? "Показываемый номер" : "Displayed number"
        default:
            return nil
        }
    }


    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkExtrasControllerArguments
        switch self {
        case let .destination(_, title, destination):
            let icon: UIImage?
            let detail: String?
            switch destination {
            // Icons only on the hub (Protection, Account Order), as iOS Settings draws them on its top level; rows that
            // lead on from inside a page (Proxy, Connection check, the Messages and Media sub-pages) have none.
            case .security: icon = renderSettingsSymbolIcon(systemName: "checkmark.shield.fill", color: .systemGreen); detail = nil
            case .accountOrder: icon = renderSettingsSymbolIcon(systemName: "person.2.fill", color: .systemIndigo); detail = nil
            case .proxy, .connectionCheck, .messageSending, .messageActions, .voiceAndRound, .messagesMore, .profileMore: icon = nil; detail = nil
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: "", additionalDetailLabel: detail, sectionId: self.section, style: .blocks, action: {
                arguments.openDestination(destination)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .audioHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ForkPresentationLanguage.prefersRussianStrings ? "ЗВУК И ЗАПИСЬ" : "AUDIO AND RECORDING", sectionId: self.section)
        case let .musicPolicy(id, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateMusicPolicy(id, value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .designFooter(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .designHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title.uppercased(), sectionId: self.section)
        case let .brandTheme(dark):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: dark ? "BananaGram Graphite" : "BananaGram Cream", label: ForkPresentationLanguage.prefersRussianStrings ? "Предпросмотр" : "Preview", sectionId: self.section, style: .blocks, action: { arguments.openBrandTheme(dark) }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .tabPreview(layout):
            return BananaTabBarPreviewItem(context: arguments.context, theme: presentationData.theme, strings: presentationData.strings, sectionId: self.section, layout: layout)
        case let .callsTab(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: presentationData.strings.Calls_TabTitle, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: arguments.updateCallsTab, tag: BananaSettingsItemTag(id: self.stableId))
        case let .settingFooter(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .settingToggle(_, _, title, value, keyPath):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAppearance(keyPath, value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .appearanceToggle(id, title, value, keyPath):
            let description: String?
            switch id {
            case 1518:
                description = ForkPresentationLanguage.prefersRussianStrings ? "Открывает поиск в текущем чате вместо поиска публичных постов." : "Searches the current chat instead of public posts."
            case 1520:
                description = ForkPresentationLanguage.prefersRussianStrings ? "Отправляет GIF беззвучным видео, если GIF запрещены, а видео разрешены." : "Sends GIFs as silent videos where GIFs are banned but videos are allowed."
            case 1530:
                description = ForkPresentationLanguage.prefersRussianStrings ? "Аналитика, время чтения и прослушивания, служебные логи и качество звонков. По умолчанию выключено." : "Usage analytics, reading and listening times, service logs and call quality. Off by default."
            case 1533:
                description = ForkPresentationLanguage.prefersRussianStrings ? "Скрывает значки упоминаний. Их уведомления следуют настройкам чата и темы." : "Hides mention badges. Mention notifications follow chat and topic settings."
            default:
                description = nil
            }
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: description, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAppearance(keyPath, value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubAppearance:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: ForkPresentationLanguage.prefersRussianStrings ? "Оформление" : "Appearance", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.appearance)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubNinja:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.savedMessages, title: ForkExtrasLocalizedString.hubNinja, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.ninja)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubGhost:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.stories, title: ForkExtrasLocalizedString.hubGhost, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.ghost)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubPrivacy:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.security, title: ForkExtrasLocalizedString.hubPrivacy, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.privacy)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubChatList:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.chatFolders, title: ForkExtrasLocalizedString.hubChatList, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.chatList)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubTabBar:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.topics, title: ForkExtrasLocalizedString.hubTabBar, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.tabBar)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubMessages:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.messages, title: ForkExtrasLocalizedString.hubMessages, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.messages)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubMedia:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.voices, title: ForkExtrasLocalizedString.hubMedia, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.media)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubProfile:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.myProfile, title: ForkExtrasLocalizedString.hubProfile, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.profile)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubCard:
            let russian = ForkPresentationLanguage.prefersRussianStrings
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: renderSettingsSymbolIcon(systemName: "sparkles", color: .systemYellow), title: russian ? "Дополнительные функции" : "Extra Features", titleFont: .bold, label: "", additionalDetailLabel: russian ? "Тонкая настройка клиента" : "Fine-tune the client", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil, tag: BananaSettingsItemTag(id: self.stableId))
        case let .connectionStatus(title, detail, viaProxy):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: renderSettingsSymbolIcon(systemName: viaProxy ? "shield.fill" : "wifi", color: viaProxy ? .systemGreen : .systemBlue), title: title, titleFont: .bold, label: "", additionalDetailLabel: detail, sectionId: self.section, style: .blocks, action: {
                arguments.openDestination(.proxy)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case .hubSectionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ForkPresentationLanguage.prefersRussianStrings ? "РАЗДЕЛЫ" : "SECTIONS", sectionId: self.section)
        case .hubLookHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: ForkPresentationLanguage.prefersRussianStrings ? "ИНТЕРФЕЙС" : "INTERFACE", sectionId: self.section)
        case .hubNetwork:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.proxy, title: ForkExtrasLocalizedString.hubNetwork, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.network)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .ghostModeMaster(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostModeMaster, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostModeMaster(value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .ghostReadOnInteract(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostReadOnInteract, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostReadOnInteract(value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .ghostScheduleMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostScheduleMessages, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostScheduleMessages(value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .accentSaturation(percent):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.accentSaturation, label: "\(percent)%", sectionId: self.section, style: .blocks, action: {
                arguments.openAccentSaturation()
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .translationBackend(backend):
            let label: String
            switch backend {
            case .default:
                label = ForkExtrasLocalizedString.backendDefault
            case .system:
                label = ForkExtrasLocalizedString.backendSystem
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.translationBackend, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openTranslationBackend()
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .transcriptionBackend(backend):
            let label: String
            switch backend {
            case .default:
                label = ForkExtrasLocalizedString.backendDefault
            case .apple:
                label = ForkExtrasLocalizedString.backendApple
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.transcriptionBackend, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openTranscriptionBackend()
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .scrollToNextChat(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.scrollToNextChat, value: !value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateScrollToNextChatDisabled(!value)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .deletedMessageMark(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ForkExtrasLocalizedString.deletedMessageMark), text: value, placeholder: "🧹", type: .regular(capitalization: false, autocorrection: false), clearType: .always, maxLength: 8, sectionId: self.section, textUpdated: { value in
                arguments.updateDeletedMessageMark(value)
            }, action: {})
        case let .editedMessageMark(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ForkExtrasLocalizedString.editedMessageMark), text: value, placeholder: "", type: .regular(capitalization: false, autocorrection: false), clearType: .always, maxLength: 8, sectionId: self.section, textUpdated: { value in
                arguments.updateEditedMessageMark(value)
            }, action: {})
        case .exportMessageSavingDatabase:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.exportMessageSaving, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportMessageSavingDatabase()
            })
        case .importMessageSavingDatabase:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.importMessageSaving, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importMessageSavingDatabase()
            })
        case let .regexFiltersPatterns(value):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: value, placeholder: ForkExtrasLocalizedString.regexFiltersPatterns, maxLength: ItemListMultilineInputItemTextLimit(value: 4000, display: false), sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, textUpdated: { value in
                arguments.updateRegexFilterPatternsText(value)
            })
        case let .regexFiltersFooter(unusable):
            var text = ForkExtrasLocalizedString.regexFiltersFooter
            if unusable > 0 {
                text += "\n\n" + (ForkPresentationLanguage.prefersRussianStrings ? "Не работают шаблонов: \(unusable) (неверное выражение, длиннее 512 символов, сверх лимита 64 или слишком медленное — такое отключается до перезапуска)." : "Patterns that will not work: \(unusable) (invalid expression, longer than 512 characters, past the limit of 64, or too slow, which is turned off until restart).")
            }
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .intChoice(id, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openIntChoice(id)
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .stickerSize(percent):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.stickerSize, label: "\(percent)%", sectionId: self.section, style: .blocks, action: {
                arguments.openStickerSize()
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .outgoingPhotoQuality(value):
            // The row shows the short name; the choices, which open from it, keep their pixel sizes.
            let russian = ForkPresentationLanguage.prefersRussianStrings
            let label: String
            switch value {
            case 2:
                label = russian ? "Максимум" : "Maximum"
            case 1:
                label = russian ? "Лучше" : "Better"
            default:
                label = russian ? "Обычное" : "Default"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.outgoingPhotoQuality, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openOutgoingPhotoQuality()
            }, tag: BananaSettingsItemTag(id: self.stableId))
        case let .visualPhoneNumber(value):
            let accountManager = arguments.context.sharedContext.accountManager
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ForkPresentationLanguage.prefersRussianStrings ? "Номер" : "Number"), text: value, placeholder: "+888 0156 2794", type: .regular(capitalization: false, autocorrection: false), clearType: .always, maxLength: 24, tag: BananaSettingsItemTag(id: self.stableId), sectionId: self.section, textUpdated: { value in
                let _ = updateForkExtrasSettingsInteractively(accountManager: accountManager) { current in
                    var updated = current
                    updated.visualPhoneNumber = value
                    return updated
                }.start()
            }, action: {})
        }
    }
}

/// Donutgram's sticker shapes: stock, rounded (12 pt) and more rounded (22 pt).
private func forkVisualLabelOptions(russian: Bool) -> [(String, Int32)] {
    return [(russian ? "Без метки" : "None", 0), ("SCAM", 1), ("FAKE", 2), ("SUPPORT", 3), ("BOT", 4)]
}

private func forkLocalVerificationOptions(russian: Bool) -> [(String, Int32)] {
    return BananaLocalVerificationBadge.allCases.map { badge in
        (badge == .none ? (russian ? "Выключено" : "Off") : badge.title, badge.rawValue)
    }
}

private func forkStickerShapeOptions(russian: Bool) -> [(String, Int32)] {
    return [
        (russian ? "Обычная" : "Default", 0),
        (russian ? "Скруглённая" : "Rounded", 1),
        (russian ? "Сильно скруглённая" : "More rounded", 2),
    ]
}

/// Donutgram's double-tap seek steps; 0 turns double-tap seeking off.
private func forkDoubleTapSeekOptions(russian: Bool) -> [(String, Int32)] {
    return [Int32(0), 5, 10, 15, 30].map { seconds -> (String, Int32) in
        if seconds == 0 {
            return (russian ? "Выключено" : "Off", seconds)
        }
        return (russian ? "\(seconds) с" : "\(seconds) s", seconds)
    }
}

/// What a double tap on a message does (Regram). The values are `ForkExtrasSettings.doubleTapAction`.
private func forkDoubleTapActionOptions(russian: Bool) -> [(String, Int32)] {
    return [
        (russian ? "По умолчанию" : "Default", 0),
        (russian ? "Поставить реакцию" : "React", 1),
        (russian ? "Ответить" : "Reply", 2),
        (russian ? "Повторить" : "Repeat", 3),
        (russian ? "Перевести" : "Translate", 4),
        (russian ? "Изменить" : "Edit", 6),
    ]
}

/// Liquid Glass bubble tint strength, as a percentage of the theme's bubble colour (25 is the default).
private func forkGlassTintOptions(russian: Bool) -> [(String, Int32)] {
    return [
        (russian ? "Почти прозрачное (10%)" : "Barely (10%)", 10),
        (russian ? "Лёгкое (18%)" : "Light (18%)", 18),
        (russian ? "Обычное (25%)" : "Default (25%)", 25),
        (russian ? "Сильное (35%)" : "Strong (35%)", 35),
        (russian ? "Насыщенное (50%)" : "Rich (50%)", 50),
    ]
}

/// Liquid Glass bubble rim brightness for one edge, as a percentage of white (0 hides that part of the rim).
private func forkGlassRimOptions(russian: Bool) -> [(String, Int32)] {
    return [Int32(0), 20, 35, 55, 75, 95].map { percent -> (String, Int32) in
        if percent == 0 {
            return (russian ? "Без блика" : "Off", percent)
        }
        return ("\(percent)%", percent)
    }
}

/// Regram's default send formatting: the style added to the plain parts of an outgoing text message.
private func forkSendFormattingOptions(russian: Bool) -> [(String, Int32)] {
    return [
        (russian ? "Выключено" : "Off", 0),
        (russian ? "Жирный" : "Bold", 1),
        (russian ? "Курсив" : "Italic", 2),
        (russian ? "Подчёркнутый" : "Underline", 3),
        (russian ? "Зачёркнутый" : "Strikethrough", 4),
        (russian ? "Скрытый" : "Spoiler", 5),
    ]
}

/// Regram's default video quality: the version a gallery video starts in when several are offered.
private func forkVideoQualityOptions(russian: Bool) -> [(String, Int32)] {
    return [
        (russian ? "Авто" : "Auto", 0),
        (russian ? "Наилучшее из доступных" : "Highest available", 1),
        (russian ? "Наименьшее из доступных" : "Lowest available", 2),
    ]
}

private func forkIntChoiceLabel(_ options: [(String, Int32)], _ value: Int32) -> String {
    return options.first(where: { $0.1 == value })?.0 ?? ""
}

private func forkExtrasControllerEntries(settings: ForkExtrasSettings, autoFetchPublicMtProxy: Bool, showCallsTab: Bool, mediaInputSettings: MediaInputSettings, focus: ForkExtrasControllerFocus, accountPeerId: Int64? = nil, accountRecordId: Int64? = nil, connectionSummary: (viaProxy: Bool, detail: String)? = nil) -> [ForkExtrasEntry] {
    let category = focus.resolvedCategory
    if category == .top {
        // Scene 37: the header card, the feature sections, then the ones that change the interface.
        return [
            .hubSectionsHeader,
            .hubNinja,
            .hubGhost,
            .hubPrivacy,
            // Security: switches against the ways accounts are stolen (BananaSecurityController).
            .destination(1995, BananaSecurityStrings.title, .security),
            .hubMessages,
            .hubMedia,
            .hubProfile,
            .hubNetwork,
            .hubLookHeader,
            .hubChatList,
            .hubTabBar,
            .destination(2100, ForkPresentationLanguage.prefersRussianStrings ? "Порядок аккаунтов" : "Account Order", .accountOrder),
            .hubAppearance,
            .settingFooter(6, .hubLook, ForkExtrasLocalizedString.hubFooter),
        ]
    }

    let russian = ForkPresentationLanguage.prefersRussianStrings
    var entries: [ForkExtrasEntry] = []
    switch category {
    case .ghost:
        entries = [
            .ghostModeMaster(settings.isFullGhostMode),
            .settingToggle(10, .ghost, ForkExtrasLocalizedString.ghostDontReadMessages, settings.ghostDontReadMessages, \.ghostDontReadMessages),
            .settingToggle(11, .ghost, ForkExtrasLocalizedString.ghostDontReadStories, settings.ghostDontReadStories, \.ghostDontReadStories),
            .settingToggle(12, .ghost, ForkExtrasLocalizedString.ghostDontSendOnline, settings.ghostDontSendOnline, \.ghostDontSendOnline),
            .settingToggle(13, .ghost, ForkExtrasLocalizedString.ghostDontSendTyping, settings.ghostDontSendTyping, \.ghostDontSendTyping),
            .appearanceToggle(1560, russian ? "Скрывать «печатает…»" : "Hide “typing…”", settings.hideTypingText, \.hideTypingText),
            .appearanceToggle(1561, russian ? "Скрывать «записывает голосовое/кружок»" : "Hide “recording voice/round video”", settings.hideTypingVoice, \.hideTypingVoice),
            .appearanceToggle(1562, russian ? "Скрывать «отправляет файл/фото/видео»" : "Hide “sending file/photo/video”", settings.hideTypingFiles, \.hideTypingFiles),
            .settingToggle(14, .ghost, ForkExtrasLocalizedString.ghostGoOfflineAutomatically, settings.ghostGoOfflineAutomatically, \.ghostGoOfflineAutomatically),
            .settingFooter(15, .ghost, ForkExtrasLocalizedString.ghostGoOfflineAutomaticallyFooter),
            .ghostReadOnInteract(settings.ghostReadOnInteract),
            .settingFooter(17, .ghost, ForkExtrasLocalizedString.ghostReadOnInteractFooter),
            .settingToggle(18, .ghost, ForkExtrasLocalizedString.ghostAlertBeforeOpeningStory, settings.ghostAlertBeforeOpeningStory, \.ghostAlertBeforeOpeningStory),
            .ghostScheduleMessages(settings.ghostScheduleMessages),
            .settingFooter(21, .ghost, ForkExtrasLocalizedString.ghostScheduleMessagesFooter),
            .settingFooter(22, .ghost, ForkExtrasLocalizedString.ghostModeFooter),
            .appearanceToggle(1770, russian ? "Отправлять без звука" : "Send without sound", settings.ghostSendWithoutSound, \.ghostSendWithoutSound),
            .appearanceToggle(1771, russian ? "Предлагать «Не читать истории»" : "Suggest Don't Read Stories", settings.ghostSuggestForStories, \.ghostSuggestForStories),
            .designFooter(1772, russian ? "«Без звука» работает только в полном режиме призрака. Перед историей приложение спросит, скрыть ли ваш просмотр." : "Send without sound works only in full Ghost Mode. Before a story opens, you're asked whether to hide your view."),
        ]
    case .privacy:
        entries = [
            .appearanceToggle(1530, russian ? "Отправлять статистику в Telegram" : "Send statistics to Telegram", settings.sendTelegramStatistics, \.sendTelegramStatistics),
            .appearanceToggle(2030, russian ? "Убирать отслеживание из ссылок" : "Remove tracking from sent links", settings.stripTrackingParameters, \.stripTrackingParameters),
            .designFooter(2031, russian ? "Очищать ссылки в текстовых сообщениях. Код и подписанные ссылки сохраняются без изменений." : "Clean links in text messages. Code and signed links remain unchanged."),
            .appearanceToggle(2032, russian ? "Скрыть номер в заголовке чата" : "Hide phone number in chat title", settings.hidePhoneNumberInChatTitle, \.hidePhoneNumberInChatTitle),
            .settingToggle(28, .lock, ForkExtrasLocalizedString.streamerMode, settings.streamerMode, \.streamerMode),
            .settingFooter(29, .lock, ForkExtrasLocalizedString.streamerModeFooter),
            .settingToggle(30, .lock, ForkExtrasLocalizedString.instantPasscode, settings.instantPasscodeLock, \.instantPasscodeLock),
            .settingFooter(31, .lock, ForkExtrasLocalizedString.instantPasscodeFooter),
            .designHeader(2045, russian ? "Уведомления" : "Notifications"),
            .settingToggle(32, .notifications, ForkExtrasLocalizedString.hideMentions, settings.hideMentionNotifications, \.hideMentionNotifications),
            .settingToggle(34, .notifications, ForkExtrasLocalizedString.hidePinned, settings.hidePinnedNotifications, \.hidePinnedNotifications),
            .designHeader(2046, russian ? "Секретные чаты и исчезающие медиа" : "Secret chats and disappearing media"),
            .settingToggle(38, .smallThings, ForkExtrasLocalizedString.allowSecretScreenshots, settings.allowSecretScreenshots, \.allowSecretScreenshots),
            .settingFooter(39, .smallThings, ForkExtrasLocalizedString.allowSecretScreenshotsFooter),
            .appearanceToggle(1775, russian ? "Скриншоты в защищённых чатах" : "Screenshots in protected chats", settings.allowProtectedScreenshots, \.allowProtectedScreenshots),
            .settingToggle(40, .smallThings, ForkExtrasLocalizedString.expireTtlButton, settings.expireTtlButton, \.expireTtlButton),
            .settingFooter(41, .smallThings, ForkExtrasLocalizedString.expireTtlButtonFooter),
            .settingToggle(42, .smallThings, ForkExtrasLocalizedString.keepBannedChats, settings.keepBannedChats, \.keepBannedChats),
            .settingFooter(43, .smallThings, ForkExtrasLocalizedString.keepBannedChatsFooter),
        ]
    case .chatList:
        entries = [
            .designHeader(1602, russian ? "Список чатов" : "Chat list"),
            .settingToggle(50, .uiDensity, ForkExtrasLocalizedString.compactChatList, settings.compactChatList, \.compactChatList),
            .settingToggle(51, .uiDensity, ForkExtrasLocalizedString.compactMessagePreview, settings.compactMessagePreview, \.compactMessagePreview),
            .settingFooter(53, .uiDensity, ForkExtrasLocalizedString.uiDensityFooter),
            .designHeader(1601, russian ? "Папки" : "Folders"),
            .settingToggle(52, .uiDensity, ForkExtrasLocalizedString.compactFolderNames, settings.compactFolderNames, \.compactFolderNames),
            .appearanceToggle(1499, ForkExtrasLocalizedString.string(forKey: "ForkExtras.BottomFolders"), settings.bottomChatFoldersEnabled, \.bottomChatFoldersEnabled),
            .appearanceToggle(1546, russian ? "Скрыть «Соединение…» в заголовке" : "Hide Connecting… in the title", settings.chatListHidesConnectionStatus, \.chatListHidesConnectionStatus),
            .appearanceToggle(1547, russian ? "Скрыть эмодзи-статус в заголовке" : "Hide emoji status in the title", settings.chatListHidesEmojiStatus, \.chatListHidesEmojiStatus),
            .appearanceToggle(1548, russian ? "Заголовок по центру" : "Centered title", settings.chatListCentersTitle, \.chatListCentersTitle),
            .appearanceToggle(1549, russian ? "Скрыть поиск в списке чатов" : "Hide search in the chat list", settings.chatListHidesSearch, \.chatListHidesSearch),
            .settingToggle(59, .folders, ForkExtrasLocalizedString.hideAllChats, settings.hideAllChats, \.hideAllChats),
            .settingFooter(60, .folders, ForkExtrasLocalizedString.hideAllChatsFooter),
            .settingToggle(61, .folders, ForkExtrasLocalizedString.rememberLastFolder, settings.rememberLastFolder, \.rememberLastFolder),
            .settingFooter(62, .folders, ForkExtrasLocalizedString.rememberLastFolderFooter),
            .appearanceToggle(1512, russian ? "Скрыть подсказки о днях рождения" : "Hide birthday banners", settings.hideBirthdayNotifications, \.hideBirthdayNotifications),
            .appearanceToggle(1773, russian ? "Скрыть истории" : "Hide stories", settings.hideStories, \.hideStories),
            .appearanceToggle(1774, russian ? "Скрыть архив" : "Hide archive", settings.hideArchive, \.hideArchive),
            .appearanceToggle(1790, russian ? "Отключить камеру по свайпу" : "No story camera on swipe", settings.disableStoryCameraSwipe, \.disableStoryCameraSwipe),
            .appearanceToggle(1930, russian ? "Отключить создание историй" : "Disable story creation", settings.disableStoryCreation, \.disableStoryCreation),
            .appearanceToggle(2038, russian ? "Скрывать черновик пустого ответа" : "Hide empty reply drafts", settings.hideEmptyReplyDrafts, \.hideEmptyReplyDrafts),
            .designFooter(2039, russian ? "Если выбран ответ, но текст не введён, в списке чатов видно последнее сообщение вместо «Черновик». Выбранный ответ сохраняется." : "When a reply is chosen without any text, the chat list shows the last message instead of Draft. The reply stays chosen."),
            .appearanceToggle(1961, russian ? "Скрыть счётчик непрочитанных на папках" : "Hide unread counts on folders", settings.hideFolderUnreadCount, \.hideFolderUnreadCount),
            .appearanceToggle(1963, russian ? "Скрыть «печатает…» в личных чатах" : "Hide typing status in private chats", settings.hidePrivateChatActivities, \.hidePrivateChatActivities),
        ]
    case .tabBar:
        entries = []
        if UIDevice.current.userInterfaceIdiom != .pad {
            entries.append(.settingToggle(63, .folders, ForkExtrasLocalizedString.hideTabBar, settings.hideTabBar, \.hideTabBar))
            entries.append(.settingFooter(64, .folders, ForkExtrasLocalizedString.hideTabBarFooter))
        }
        entries.append(contentsOf: [
            .appearanceToggle(1502, ForkExtrasLocalizedString.string(forKey: "ForkExtras.ContactsTab"), settings.showContactsTab, \.showContactsTab),
            .callsTab(showCallsTab),
            .appearanceToggle(1504, ForkExtrasLocalizedString.string(forKey: "ForkExtras.wideTabBar"), settings.wideTabBar, \.wideTabBar),
            .appearanceToggle(1505, ForkExtrasLocalizedString.string(forKey: "ForkExtras.integratedTabSearch"), settings.integratedTabSearch, \.integratedTabSearch),
            .appearanceToggle(1506, ForkExtrasLocalizedString.string(forKey: "ForkExtras.tabSearchOnLeft"), settings.tabSearchOnLeft, \.tabSearchOnLeft),
            .tabPreview(BananaTabBarLayout(hidden: ForkExtrasHotFlags.hidesTabBar(settings.hideTabBar, isPad: UIDevice.current.userInterfaceIdiom == .pad), contacts: settings.showContactsTab, calls: showCallsTab, wide: settings.wideTabBar, integratedSearch: settings.integratedTabSearch, searchOnLeft: settings.tabSearchOnLeft)),
        ])
    case .appearance:
        entries = [
            .designHeader(1618, russian ? "Бананчик наверху" : "Banana island"),
            .appearanceToggle(1531, russian ? "Показывать бананчик" : "Show banana island", settings.bananaIslandEnabled, \.bananaIslandEnabled),
            .appearanceToggle(1532, russian ? "Подпись BananaGram" : "BananaGram label", settings.bananaIslandShowsName, \.bananaIslandShowsName),
            .appearanceToggle(1553, russian ? "Остров как у иконки" : "Island matches the app icon", settings.bananaIslandFollowsIcon, \.bananaIslandFollowsIcon),
            .designFooter(1619, russian ? "Значок над экраном приложения на устройствах с Dynamic Island. Цвета соответствуют теме." : "An app badge on devices with Dynamic Island. Colors follow your theme."),
            .designHeader(1900, russian ? "Пузыри сообщений" : "Message bubbles"),
            .appearanceToggle(1901, russian ? "Стеклянные пузыри" : "Glass bubbles", settings.glassBubbles, \.glassBubbles),
            .intChoice(1902, russian ? "Оттенок стекла" : "Glass tint", forkIntChoiceLabel(forkGlassTintOptions(russian: russian), settings.glassBubbleTint)),
            .intChoice(1903, russian ? "Блик сверху" : "Rim: top", forkIntChoiceLabel(forkGlassRimOptions(russian: russian), settings.glassBubbleRimTop)),
            .intChoice(1904, russian ? "Блик по бокам" : "Rim: sides", forkIntChoiceLabel(forkGlassRimOptions(russian: russian), settings.glassBubbleRimSides)),
            .intChoice(1905, russian ? "Блик снизу" : "Rim: bottom", forkIntChoiceLabel(forkGlassRimOptions(russian: russian), settings.glassBubbleRimBottom)),
            .designFooter(1906, russian ? "Пузыри становятся прозрачным стеклом цвета темы, сквозь которое виден фон чата. Нужна iOS 26 или новее." : "Bubbles become see-through glass tinted with the theme color, with the chat wallpaper showing through. Requires iOS 26 or later."),
        ]
    case .messages:
        entries = [
            .destination(2200, russian ? "Ввод и отправка" : "Input and Sending", .messageSending),
            .destination(2201, russian ? "Действия с сообщениями" : "Message Actions", .messageActions),
            .designHeader(1605, russian ? "Отображение" : "Display"),
            .settingToggle(65, .appearance, ForkExtrasLocalizedString.showMessageSeconds, settings.showMessageSeconds, \.showMessageSeconds),
            .settingToggle(67, .appearance, ForkExtrasLocalizedString.wideChannelPosts, settings.wideChannelPosts, \.wideChannelPosts),
            .settingFooter(68, .appearance, ForkExtrasLocalizedString.wideChannelPostsFooter),
            .stickerSize(settings.stickerSizePercent),
            .appearanceToggle(1508, russian ? "Счётчик пересылок в каналах" : "Channel forward count", settings.showChannelForwardCount, \.showChannelForwardCount),
            .appearanceToggle(1557, russian ? "Цитата удалённого сообщения в ответе" : "Quote a deleted message in a reply", settings.quoteRepliesToDeleted, \.quoteRepliesToDeleted),
            .appearanceToggle(1558, russian ? "Точные счётчики (без «1,2K»)" : "Exact counts (no “1.2K”)", settings.exactCounts, \.exactCounts),
            .appearanceToggle(1509, russian ? "Скрыть платные реакции" : "Hide paid reactions", settings.hidePaidReactions, \.hidePaidReactions),
            .appearanceToggle(1735, russian ? "Скрыть кнопку подарка" : "Hide the gift button", settings.hideGiftButton, \.hideGiftButton),
            .settingToggle(54, .privacy, ForkExtrasLocalizedString.hideReactionsBar, settings.hideReactionsBar, \.hideReactionsBar),
            .appearanceToggle(1521, russian ? "Недавние эмодзи в реакциях" : "Recent emoji in reactions", settings.useRecentEmojiInReactions, \.useRecentEmojiInReactions),
            .appearanceToggle(1550, russian ? "Итоги опроса до голосования" : "Poll results before voting", settings.pollResultsBeforeVoting, \.pollResultsBeforeVoting),
            .appearanceToggle(1703, russian ? "Скрыть премиум-эмодзи в ответах" : "Hide premium emoji in replies", settings.hidePremiumReplyEmoji, \.hidePremiumReplyEmoji),
            .appearanceToggle(1519, russian ? "Дата оригинала у пересланных" : "Original date on forwards", settings.showOriginalForwardDate, \.showOriginalForwardDate),
            .designHeader(1720, russian ? "Вид чата" : "Chat look"),
            .appearanceToggle(1711, russian ? "Ответы без цвета имени" : "Replies without name colors", settings.disableColoredReplies, \.disableColoredReplies),
            .appearanceToggle(1713, russian ? "Аватарки в упоминаниях" : "Avatars in mentions", settings.mentionAvatars, \.mentionAvatars),
            .appearanceToggle(1719, russian ? "Скрыть кнопку «Поделиться»" : "Hide the share button", settings.hideShareButton, \.hideShareButton),
            .appearanceToggle(1716, russian ? "Без своих фонов у чатов" : "No custom chat backgrounds", settings.disableCustomBackgrounds, \.disableCustomBackgrounds),
            .appearanceToggle(1717, russian ? "Канал: кнопка «Обсудить»" : "Channel: Discuss button", settings.channelBottomDiscuss, \.channelBottomDiscuss),
            .appearanceToggle(1718, russian ? "Канал: скрыть нижнюю кнопку" : "Channel: hide bottom button", settings.hideChannelBottomButton, \.hideChannelBottomButton),
            .appearanceToggle(1791, russian ? "«В начало чата» в меню аватарки" : "Jump to start in the avatar menu", settings.jumpToStartInChatMenu, \.jumpToStartInChatMenu),
            .scrollToNextChat(settings.scrollToNextChatDisabled),
            .settingFooter(89, .navigation, ForkExtrasLocalizedString.scrollToNextChatFooter),
            .appearanceToggle(2036, russian ? "Показывать скрытых админов" : "Show hidden admin badges", settings.showHiddenAdminBadges, \.showHiddenAdminBadges),
            .designFooter(2037, russian ? "Админ или владелец с невидимым титулом (пробелы или пустые символы) получает обычную метку «админ» или «владелец»." : "An admin or owner whose title is invisible (spaces or blank characters) gets the standard admin or owner badge."),
            .translationBackend(settings.translationBackend),
            .transcriptionBackend(settings.transcriptionBackend),
            .settingFooter(87, .translation, ForkExtrasLocalizedString.translationFooter),
            .destination(2043, russian ? "Ещё о сообщениях" : "More Message Settings", .messagesMore),
        ]
    case .messagesMore:
        entries = [
            .appearanceToggle(1533, russian ? "Убрать пинги" : "Remove mention pings", settings.removePings, \.removePings),
            .appearanceToggle(1542, russian ? "Скрыть время у стикеров" : "Hide time on stickers", settings.hideStickerStatus, \.hideStickerStatus),
            .appearanceToggle(1700, russian ? "Ответ на стикер: скрыть цвета" : "Sticker replies: hide colors", settings.hideStickerReplyColors, \.hideStickerReplyColors),
            .appearanceToggle(1701, russian ? "Ответ на стикер: скрыть эмодзи" : "Sticker replies: hide emoji", settings.hideStickerReplyEmoji, \.hideStickerReplyEmoji),
            .appearanceToggle(1702, russian ? "Ответ на стикер: скрыть фон" : "Sticker replies: hide background", settings.hideStickerReplyBackground, \.hideStickerReplyBackground),
            .appearanceToggle(1825, russian ? "Выбор папки после вступления" : "Choose a folder after joining", settings.chooseFolderAfterJoin, \.chooseFolderAfterJoin),
            .appearanceToggle(1826, russian ? "Недавние чаты (долгое нажатие на «Назад»)" : "Recent chats (long-press Back)", settings.recentChatsMenu, \.recentChatsMenu),
            .appearanceToggle(1827, russian ? "Закладки сообщений с тегами" : "Message bookmarks with tags", settings.messageBookmarks, \.messageBookmarks),
            .appearanceToggle(1828, russian ? "Локальное имя группы или канала" : "Local group or channel name", settings.localGroupAlias, \.localGroupAlias),
            .designHeader(1721, russian ? "Стикеры" : "Stickers"),
            .appearanceToggle(1712, russian ? "Скрыть галочки у стикеров" : "Hide checks on stickers", settings.hideStickerChecks, \.hideStickerChecks),
            .appearanceToggle(1931, russian ? "Канал: скрыть реакции под постами" : "Channel: hide reactions under posts", settings.hideChannelPostReactions, \.hideChannelPostReactions),
            .appearanceToggle(1940, russian ? "Отключить служебные сообщения" : "Hide service messages", settings.hideServiceMessages, \.hideServiceMessages),
            .appearanceToggle(1941, russian ? "Подтверждать реакции без вступления" : "Confirm reactions before joining", settings.confirmReactionsInUnjoinedChats, \.confirmReactionsInUnjoinedChats),
            .appearanceToggle(1942, russian ? "Подтверждать переход по ссылкам Telegram" : "Confirm Telegram link opens", settings.confirmTelegramLinks, \.confirmTelegramLinks),
            .appearanceToggle(1944, russian ? "Подтверждать ссылки «поделиться» (tg://msg_url)" : "Confirm share links (tg://msg_url)", settings.confirmShareLinks, \.confirmShareLinks),
            .appearanceToggle(1943, russian ? "Подтверждать вход из предпросмотра" : "Confirm entering a chat preview", settings.confirmChatPreviewEntry, \.confirmChatPreviewEntry),
            .appearanceToggle(1518, russian ? "Хэштег ищет в этом чате" : "Hashtags search this chat", settings.hashtagsPreferCurrentChat, \.hashtagsPreferCurrentChat),
            .appearanceToggle(1960, russian ? "Отзыв всех пригласительных ссылок" : "Bulk revoke invite links", settings.inviteLinksBulkRevoke, \.inviteLinksBulkRevoke),
            .appearanceToggle(1962, russian ? "Подтверждать открепление сообщений" : "Confirm before unpinning messages", settings.confirmUnpin, \.confirmUnpin),
            .appearanceToggle(1964, russian ? "Оставаться на последнем сообщении после обновления" : "Stay at the latest message after a refresh", settings.stayAtLatestMessageAfterRefresh, \.stayAtLatestMessageAfterRefresh),
            .designHeader(1607, russian ? "Боты и служебные сообщения" : "Bots and service messages"),
            .appearanceToggle(1510, russian ? "Скрыть «через бота»" : "Hide \"via bot\"", settings.hideViaBot, \.hideViaBot),
            .appearanceToggle(1513, russian ? "Скрыть панель автоматизации бота" : "Hide bot automation panel", settings.hideBotAutomation, \.hideBotAutomation),
            .appearanceToggle(1517, russian ? "Без приветственного стикера" : "No greeting sticker", settings.hideGreetingSticker, \.hideGreetingSticker),
        ]
    case .messageSending:
        entries = [
            .appearanceToggle(1710, russian ? "Запятая после упоминания" : "Comma after mention", settings.commaAfterMention, \.commaAfterMention),
            .designHeader(1606, russian ? "Отправка и правка" : "Sending and editing"),
            .settingToggle(81, .calls, ForkExtrasLocalizedString.sendWithReturnKey, settings.sendWithReturnKey, \.sendWithReturnKey),
            .settingFooter(82, .calls, ForkExtrasLocalizedString.sendWithReturnKeyFooter),
            .outgoingPhotoQuality(settings.outgoingPhotoQuality),
            .settingFooter(99, .chatExtras, ForkExtrasLocalizedString.outgoingPhotoQualityFooter),
            .appearanceToggle(1511, russian ? "Отправлять без превью ссылок" : "Send without link previews", settings.removeLinkPreviews, \.removeLinkPreviews),
            .appearanceToggle(1520, russian ? "Запрещённые GIF как видео" : "Send banned GIFs as video", settings.sendBannedGifsAsVideo, \.sendBannedGifsAsVideo),
            .appearanceToggle(2040, russian ? "Обход запрета стикеров" : "Bypass sticker restrictions", settings.bypassStickerRestrictions, \.bypassStickerRestrictions),
            .designFooter(2041, russian ? "Где стикеры запрещены, а видео разрешены, стикер уходит коротким видео без звука: анимированный — целиком, обычный — секундным роликом." : "Where stickers are restricted but videos are allowed, a sticker goes out as a short silent video: an animated one as it plays, a static one as a one-second clip."),
            .designHeader(1850, russian ? "Панель ввода" : "Input panel"),
            .appearanceToggle(2101, russian ? "Скрыть функции ИИ" : "Hide AI features", settings.hideAIButton, \.hideAIButton),
            .appearanceToggle(2102, russian ? "Скрыть разворачивание редактора" : "Hide expanded editor", settings.hideRichTextEditor, \.hideRichTextEditor),
            .intChoice(1851, russian ? "Формат по умолчанию" : "Default formatting", forkIntChoiceLabel(forkSendFormattingOptions(russian: russian), settings.defaultSendFormatting)),
            .appearanceToggle(1852, russian ? "Упоминание долгим нажатием на аватар" : "Mention by long-pressing an avatar", settings.avatarLongPressMention, \.avatarLongPressMention),
            .designFooter(1853, russian ? "При скрытом ИИ копируется исходный текст. Формат по умолчанию применяется только к обычному тексту." : "With AI hidden, Copy takes the original text. Default formatting applies only to plain text."),
        ]
    case .messageActions:
        entries = [
            .intChoice(1802, russian ? "Двойное касание" : "Double-tap action", forkIntChoiceLabel(forkDoubleTapActionOptions(russian: russian), settings.doubleTapAction)),
            .appearanceToggle(1800, russian ? "ID сообщения в группах и каналах" : "Message ID in groups and channels", settings.showMessageId, \.showMessageId),
            .appearanceToggle(1801, russian ? "Раскрывать спойлеры сразу" : "Reveal spoilers automatically", settings.autoRevealSpoilers, \.autoRevealSpoilers),
            .appearanceToggle(1803, russian ? "Меню: повторить и переслать без автора" : "Menu: Repeat and Forward without author", settings.repeatMessageMenu, \.repeatMessageMenu),
            .settingToggle(92, .chatExtras, ForkExtrasLocalizedString.quickTranslate, settings.quickTranslateButton, \.quickTranslateButton),
            .settingFooter(93, .chatExtras, ForkExtrasLocalizedString.quickTranslateFooter),
            .settingToggle(94, .chatExtras, ForkExtrasLocalizedString.saveToCloud, settings.saveToCloudMenu, \.saveToCloudMenu),
            .settingFooter(95, .chatExtras, ForkExtrasLocalizedString.saveToCloudFooter),
            .settingToggle(96, .chatExtras, ForkExtrasLocalizedString.selectFromAuthor, settings.selectFromAuthor, \.selectFromAuthor),
            .settingFooter(97, .chatExtras, ForkExtrasLocalizedString.selectFromAuthorFooter),
            .designHeader(1910, russian ? "Скриншот сообщений" : "Message Shot"),
            .appearanceToggle(1911, russian ? "Пункт «Скриншот» в меню сообщения" : "“Screenshot” in the message menu", settings.messageShot, \.messageShot),
        ]
    case .media:
        entries = [
            .destination(2202, russian ? "Голосовые и кружки" : "Voice and Round Videos", .voiceAndRound),
            .designHeader(1608, russian ? "Звонки" : "Calls"),
            .settingToggle(80, .calls, ForkExtrasLocalizedString.confirmBeforeCall, settings.confirmBeforeCall, \.confirmBeforeCall),
            .settingFooter(84, .calls, ForkExtrasLocalizedString.forceBuiltInMicFooter),
            .settingToggle(83, .calls, ForkExtrasLocalizedString.forceBuiltInMic, settings.forceBuiltInMic, \.forceBuiltInMic),
            .designHeader(1613, russian ? "Ссылки TikTok и Shorts" : "TikTok and Shorts links"),
            .appearanceToggle(1554, russian ? "Скачивать TikTok" : "Download TikTok", settings.downloadTikTok, \.downloadTikTok),
            .designFooter(1982, russian ? "Если TikTok откажет в загрузке, запрос пойдёт через tikwm.com. Сервис увидит ссылку на пост без параметров шаринга и ваш IP." : "If TikTok refuses the download, the request goes through tikwm.com. The service sees the post link without sharing parameters and your IP address."),
            .appearanceToggle(1555, russian ? "Скачивать YouTube Shorts" : "Download YouTube Shorts", settings.downloadYouTubeShorts, \.downloadYouTubeShorts),
            .appearanceToggle(1556, russian ? "Подпись «Скачано с…»" : "“Downloaded from…” caption", settings.signDownloadedMedia, \.signDownloadedMedia),
            .designFooter(1614, russian ? "Сообщение, в котором только ссылка, уходит видео или фото вместо ссылки. Если скачать не удалось, отправляется сама ссылка." : "A message that is only a link goes out as the video or photos instead. If the download fails, the link itself is sent."),
            .designHeader(1750, russian ? "Стикеры и воспроизведение" : "Stickers and playback"),
            .appearanceToggle(1751, russian ? "Только добавленные стикеры" : "Only added stickers", settings.onlyAddedStickers, \.onlyAddedStickers),
            .appearanceToggle(1752, russian ? "Без лимита недавних стикеров" : "Unlimited recent stickers", settings.infiniteRecentStickers, \.infiniteRecentStickers),
            .intChoice(1753, russian ? "Форма стикеров" : "Sticker shape", forkIntChoiceLabel(forkStickerShapeOptions(russian: russian), settings.stickerShape)),
            .appearanceToggle(1754, russian ? "Пауза медиа при сворачивании" : "Pause media in background", settings.autoPauseMediaInBackground, \.autoPauseMediaInBackground),
            .intChoice(1755, russian ? "Перемотка двойным касанием" : "Double-tap seek", forkIntChoiceLabel(forkDoubleTapSeekOptions(russian: russian), settings.doubleTapSeekSeconds)),
            .appearanceToggle(1756, russian ? "Кружок: не сбрасывать зум" : "Round video: keep pinch zoom", settings.staticRoundVideoZoom, \.staticRoundVideoZoom),
            .appearanceToggle(2021, russian ? "Отправлять стикеры анонимно" : "Send stickers anonymously", settings.anonymousStickers, \.anonymousStickers),
            .appearanceToggle(1757, russian ? "Ускорить загрузку файлов" : "Faster uploads", settings.accelerateUpload, \.accelerateUpload),
            .designHeader(1860, russian ? "Ссылки и медиа" : "Links and media"),
            .appearanceToggle(1861, russian ? "Исправлять превью ссылок" : "Fix link previews", settings.fixLinkPreviews, \.fixLinkPreviews),
            .appearanceToggle(1862, russian ? "Сохранять стикеры в Фото" : "Save stickers to Photos", settings.saveStickerToPhotos, \.saveStickerToPhotos),
            .appearanceToggle(1863, russian ? "Сведения о медиа в меню" : "Media info in the menu", settings.showMediaInfo, \.showMediaInfo),
            .intChoice(1864, russian ? "Качество видео по умолчанию" : "Default video quality", forkIntChoiceLabel(forkVideoQualityOptions(russian: russian), settings.defaultVideoQuality)),
            .designFooter(1865, russian ? "Превью X, Instagram, TikTok и других берутся у сервисов-зеркал, ссылка не меняется. Анимированные стикеры сохраняются как GIF." : "Previews for X, Instagram, TikTok and others come from mirror services; the link stays the same. Animated stickers are saved as GIFs."),
            .designFooter(1758, russian ? "«Только добавленные» скрывает популярные наборы. Ускоренная загрузка не действует в секретных чатах." : "Only added stickers hides trending packs. Faster uploads don't apply in secret chats."),
            .audioHeader,
            .musicPolicy(2001, russian ? "Пауза музыки при записи видео" : "Pause music when recording video", mediaInputSettings.pauseMusicOnRecording),
            .musicPolicy(2002, russian ? "Пауза музыки при записи голосового" : "Pause music when recording voice messages", mediaInputSettings.pauseMusicOnVoiceRecording),
            .musicPolicy(2003, russian ? "Пауза музыки при прослушивании голосового" : "Pause music when playing voice messages", mediaInputSettings.pauseMusicOnVoicePlayback),
            .settingFooter(2004, .audio, ForkPresentationLanguage.prefersRussianStrings ? "Выберите, когда ставить музыку на паузу. Звонки всегда важнее." : "Choose when music pauses. Calls always take priority."),
            .designHeader(1912, russian ? "Энергосбережение" : "Power saving"),
            .appearanceToggle(1913, russian ? "Режим энергосбережения всегда" : "Always use power saving", settings.powerSaving, \.powerSaving),
            .designFooter(1914, russian ? "Как «Данные и память → Энергосбережение», но при любом заряде: без автовоспроизведения, анимаций и фоновых загрузок." : "Like Data and Storage → Power Saving, at any battery level: no autoplay, animations or background downloads."),
        ]
    case .voiceAndRound:
        entries = [
            .designHeader(1609, russian ? "Запись кружков" : "Recording round videos"),
            .appearanceToggle(2110, russian ? "Отсчёт перед записью кружка" : "Round video countdown", settings.roundVideoCountdown, \.roundVideoCountdown),
            .appearanceToggle(2111, russian ? "Записывать кружки в 60 FPS" : "Record round videos at 60 FPS", settings.roundVideoRecordAt60FPS, \.roundVideoRecordAt60FPS),
            .appearanceToggle(2112, russian ? "Максимальное качество кружков" : "Maximum round video quality", settings.roundVideoMaximumQuality, \.roundVideoMaximumQuality),
            .appearanceToggle(2113, russian ? "Фокус кружка по нажатию" : "Tap to focus round videos", settings.roundVideoFocusOnTap, \.roundVideoFocusOnTap),
            .appearanceToggle(2114, russian ? "Сбрасывать зум после жеста" : "Reset zoom after pinching", settings.roundVideoAlwaysResetZoom, \.roundVideoAlwaysResetZoom),
            .appearanceToggle(1544, russian ? "Кружок: задняя камера" : "Round video: rear camera", settings.roundVideoStartsWithRear, \.roundVideoStartsWithRear),
            .appearanceToggle(1545, russian ? "Кружок: помнить камеру" : "Round video: remember camera", settings.roundVideoRemembersCamera, \.roundVideoRemembersCamera),
            .designFooter(2115, russian ? "60 FPS нужна поддерживаемая камера, максимальное качество — до 640p. Применится при следующем открытии камеры." : "60 FPS needs a supported camera; maximum quality is up to 640p. Applies the next time you open the camera."),
            .designHeader(2042, russian ? "Прослушивание и отправка" : "Playback and sending"),
            .appearanceToggle(1515, russian ? "Останавливать после голосового" : "Stop after a voice message", settings.stopAfterVoice, \.stopAfterVoice),
            .appearanceToggle(1516, russian ? "Останавливать после кружка" : "Stop after a round video", settings.stopAfterRoundVideo, \.stopAfterRoundVideo),
            .appearanceToggle(1559, russian ? "Подтверждать отправку голосовых и кружков" : "Confirm before sending voice and round video", settings.confirmVoiceSend, \.confirmVoiceSend),
            .designFooter(1612, russian ? "Музыка как голосовое: откройте меню трека в разделе «Вложения → Музыка»." : "To send music as a voice message, open the track's menu in Attach → Music."),
        ]
    case .profile:
        entries = [
            .settingToggle(55, .privacy, ForkExtrasLocalizedString.showDC, settings.showDC, \.showDC),
            .settingToggle(56, .privacy, ForkExtrasLocalizedString.showProfileId, settings.showProfileId, \.showProfileId),
            .appearanceToggle(1551, russian ? "Точное время «был(а) в сети»" : "Exact last seen time", settings.exactLastSeen, \.exactLastSeen),
            .appearanceToggle(1714, russian ? "«Был(а) в сети» в профиле — сколько назад" : "Relative last seen on profiles", settings.relativeLastSeen, \.relativeLastSeen),
            .appearanceToggle(2020, russian ? "Примерное время активности, если «был(а) в сети» скрыто" : "Approximate last seen from activity", settings.approximateLastSeen, \.approximateLastSeen),
            .appearanceToggle(1552, russian ? "Серая точка у тех, кто не в сети" : "Grey dot for offline contacts", settings.showsOfflineDot, \.showsOfflineDot),
            .appearanceToggle(1543, russian ? "Исчезнувшие подарки" : "Disappeared gifts", settings.showDisappearedGifts, \.showDisappearedGifts),
            .appearanceToggle(2034, russian ? "Не включать музыку профиля автоматически" : "Don't autoplay profile music", settings.disableProfileMusicAutoplay, \.disableProfileMusicAutoplay),
            .designFooter(2035, russian ? "Плейлист закреплённой в профиле музыки открывается на паузе. Трек можно включить вручную." : "A profile's pinned music opens its playlist paused. You can start a track yourself."),
            .settingFooter(58, .privacy, ForkExtrasLocalizedString.privacyFooter),
            .designHeader(1739, russian ? "Профиль" : "Profile"),
            .appearanceToggle(1731, russian ? "ID в формате Bot API" : "ID in Bot API format", settings.profileIdBotApiFormat, \.profileIdBotApiFormat),
            .appearanceToggle(1732, russian ? "Взаимный контакт" : "Mutual contact", settings.showMutualContact, \.showMutualContact),
            .appearanceToggle(1730, russian ? "Дата создания чата" : "Chat creation date", settings.showChatCreationDate, \.showChatCreationDate),
            .appearanceToggle(1733, russian ? "Скрыть премиум-статусы" : "Hide premium statuses", settings.hidePremiumStatuses, \.hidePremiumStatuses),
            .appearanceToggle(1734, russian ? "Скрыть верификацию" : "Hide verification", settings.hideVerification, \.hideVerification),
            .appearanceToggle(1980, russian ? "Не открывать звёзды после продажи подарка" : "Keep the current screen after selling a gift", settings.disableGiftStarsRedirect, \.disableGiftStarsRedirect),
            .intChoice(1981, russian ? "Визуальная метка (только у вас)" : "Visual label (only visible to you)", forkIntChoiceLabel(forkVisualLabelOptions(russian: russian), settings.visualLabels[accountPeerId ?? 0] ?? 0)),
            .intChoice(2106, russian ? "Локальный значок верификации" : "Local verification badge", forkIntChoiceLabel(forkLocalVerificationOptions(russian: russian), accountRecordId.flatMap { settings.localVerificationBadges[$0] } ?? 0)),
            .destination(2044, russian ? "Ещё о профиле" : "More Profile Settings", .profileMore),
        ]
    case .profileMore:
        entries = [
            .designHeader(1740, russian ? "Мой номер" : "My number"),
            .appearanceToggle(1736, russian ? "Показывать другой номер" : "Show a different number", settings.visualPhoneEnabled, \.visualPhoneEnabled),
            .visualPhoneNumber(settings.visualPhoneNumber),
            .designFooter(1738, russian ? "Меняется только номер, показанный в вашем профиле на этом устройстве. Настоящий номер не меняется." : "Only the number shown in your own profile on this device changes. Your real number stays the same."),
            .designHeader(1603, russian ? "Эффекты" : "Effects"),
            .appearanceToggle(1500, ForkExtrasLocalizedString.string(forKey: "ForkExtras.AvatarGlow"), settings.avatarGlowEnabled, \.avatarGlowEnabled),
            .appearanceToggle(1501, ForkExtrasLocalizedString.string(forKey: "ForkExtras.ReactionGlow"), settings.reactionGlowEnabled, \.reactionGlowEnabled),
            .appearanceToggle(1541, russian ? "Снег" : "Snow", settings.snowEnabled, \.snowEnabled),
            .appearanceToggle(2022, russian ? "Профиль раскрывается из шапки чата" : "Profile expands out of the chat header", settings.profileExpansionAnimation, \.profileExpansionAnimation),
            .accentSaturation(settings.accentColorSaturation),
            .designHeader(1604, russian ? "Локальные функции Premium" : "Local Premium features"),
            .settingToggle(140, .premium, ForkExtrasLocalizedString.localPremium, settings.localPremium, \.localPremium),
            .settingFooter(141, .premium, ForkExtrasLocalizedString.localPremiumFooter),
        ]
    case .ninja, .messageSaving, .messageFilters:
        entries = [
            .settingToggle(110, .messageSaving, ForkExtrasLocalizedString.saveDeletedMessages, settings.saveDeletedMessages, \.saveDeletedMessages),
            .settingFooter(111, .messageSaving, ForkExtrasLocalizedString.saveDeletedMessagesFooter),
            .settingToggle(112, .messageSaving, ForkExtrasLocalizedString.saveMessagesHistory, settings.saveMessagesHistory, \.saveMessagesHistory),
            .settingFooter(113, .messageSaving, ForkExtrasLocalizedString.saveMessagesHistoryFooter),
            .settingToggle(114, .messageSaving, ForkExtrasLocalizedString.saveMedia, settings.saveMedia, \.saveMedia),
            .settingFooter(115, .messageSaving, ForkExtrasLocalizedString.saveMediaFooter),
            .settingToggle(116, .messageSaving, ForkExtrasLocalizedString.saveForBots, settings.saveForBots, \.saveForBots),
            .settingToggle(117, .messageSaving, ForkExtrasLocalizedString.ayuForward, settings.ayuForward, \.ayuForward),
            .settingFooter(118, .messageSaving, ForkExtrasLocalizedString.ayuForwardFooter),
            .settingToggle(119, .messageSaving, ForkExtrasLocalizedString.bypassDownloadRestrictions, settings.bypassDownloadRestrictions, \.bypassDownloadRestrictions),
            .settingFooter(120, .messageSaving, ForkExtrasLocalizedString.bypassDownloadRestrictionsFooter),
            .settingToggle(121, .messageSaving, ForkExtrasLocalizedString.proactiveSaveMedia, settings.proactiveSaveMedia, \.proactiveSaveMedia),
            .settingFooter(122, .messageSaving, ForkExtrasLocalizedString.proactiveSaveMediaFooter),
            .deletedMessageMark(settings.deletedMessageMark),
            .settingFooter(124, .messageSaving, ForkExtrasLocalizedString.deletedMessageMarkFooter),
            .editedMessageMark(settings.editedMessageMark),
            .settingFooter(126, .messageSaving, ForkExtrasLocalizedString.editedMessageMarkFooter),
            .exportMessageSavingDatabase,
            .importMessageSavingDatabase,
            .settingFooter(129, .messageSaving, ForkExtrasLocalizedString.messageSavingDbFooter),
            .settingToggle(130, .messageFilters, ForkExtrasLocalizedString.hideAds, settings.hideAds, \.hideAds),
            .settingFooter(131, .messageFilters, ForkExtrasLocalizedString.hideAdsFooter),
            .settingToggle(132, .messageFilters, ForkExtrasLocalizedString.hideBlockedMessages, settings.hideBlockedMessages, \.hideBlockedMessages),
            .settingFooter(133, .messageFilters, ForkExtrasLocalizedString.hideBlockedMessagesFooter),
            .settingToggle(147, .messageFilters, ForkExtrasLocalizedString.showSensitiveContent, settings.showSensitiveContent, \.showSensitiveContent),
            .settingFooter(148, .messageFilters, ForkExtrasLocalizedString.showSensitiveContentFooter),
            .settingToggle(134, .messageFilters, ForkExtrasLocalizedString.regexFilters, settings.regexMessageFiltersEnabled, \.regexMessageFiltersEnabled),
        ]
        if settings.regexMessageFiltersEnabled {
            entries.append(contentsOf: [
                .settingToggle(135, .messageFilters, ForkExtrasLocalizedString.regexFiltersCaseInsensitive, settings.regexMessageFiltersCaseInsensitive, \.regexMessageFiltersCaseInsensitive),
                .regexFiltersPatterns(settings.regexMessageFilterPatterns.joined(separator: "\n")),
            ])
        }
        entries.append(.regexFiltersFooter(settings.regexMessageFiltersEnabled ? ForkRegexMessageFilters.unusablePatternCount(settings.regexMessageFilterPatterns) : 0))
    case .network:
        entries = []
        entries += [
            .settingToggle(2105, .proxy, russian ? "Скрыть спонсора прокси" : "Hide proxy sponsor", settings.hideProxySponsor, \.hideProxySponsor),
            .destination(138, ForkPresentationLanguage.prefersRussianStrings ? "Прокси" : "Proxy", .proxy),
            .destination(139, russian ? "Проверка подключения" : "Connection check", .connectionCheck),

            .settingToggle(144, .downloads, ForkExtrasLocalizedString.downloadSpeedBoost, settings.downloadSpeedBoost, \.downloadSpeedBoost),
            .settingToggle(2103, .downloads, russian ? "Параллельные загрузки" : "Parallel downloads", settings.parallelDownloads, \.parallelDownloads),
            .settingFooter(2104, .downloads, russian ? "Выбранные файлы скачиваются одновременно и делят соединение." : "Files you select download at the same time and share your connection."),
            .settingFooter(145, .downloads, ForkExtrasLocalizedString.downloadSpeedBoostFooter),
            .settingToggle(146, .backgroundConnection, ForkExtrasLocalizedString.keepAliveInBackground, settings.keepAliveInBackground, \.keepAliveInBackground),
            .settingFooter(149, .backgroundConnection, ForkExtrasLocalizedString.keepAliveInBackgroundFooter),
        ]
    case .top:
        break
    }
    return entries.sorted()
}

public enum ForkExtrasControllerFocus {
    case top
    case appearance
    case ninja
    case ghost
    case privacy
    case chatList
    case tabBar
    case messages
    case messageSending
    case messageActions
    case messagesMore
    case voiceAndRound
    case media
    case profile
    case profileMore
    case network
    case messageSaving
    case messageFilters

    var resolvedCategory: ForkExtrasControllerFocus {
        switch self {
        case .messageSaving, .messageFilters:
            return .ninja
        default:
            return self
        }
    }

    var title: String {
        switch self.resolvedCategory {
        case .appearance:
            return ForkPresentationLanguage.prefersRussianStrings ? "Оформление" : "Appearance"
        case .ninja:
            return ForkExtrasLocalizedString.hubNinja
        case .ghost:
            return ForkExtrasLocalizedString.hubGhost
        case .privacy:
            return ForkExtrasLocalizedString.hubPrivacy
        case .chatList:
            return ForkExtrasLocalizedString.hubChatList
        case .tabBar:
            return ForkExtrasLocalizedString.hubTabBar
        case .messages:
            return ForkExtrasLocalizedString.hubMessages
        case .messageSending:
            return ForkPresentationLanguage.prefersRussianStrings ? "Ввод и отправка" : "Input and Sending"
        case .messageActions:
            return ForkPresentationLanguage.prefersRussianStrings ? "Действия с сообщениями" : "Message Actions"
        case .voiceAndRound:
            return ForkPresentationLanguage.prefersRussianStrings ? "Голосовые и кружки" : "Voice and Round Videos"
        case .messagesMore:
            return ForkPresentationLanguage.prefersRussianStrings ? "Ещё о сообщениях" : "More Message Settings"
        case .profileMore:
            return ForkPresentationLanguage.prefersRussianStrings ? "Ещё о профиле" : "More Profile Settings"
        case .media:
            return ForkExtrasLocalizedString.hubMedia
        case .profile:
            return ForkExtrasLocalizedString.hubProfile
        case .network:
            return ForkExtrasLocalizedString.hubNetwork
        default:
            return ForkExtrasLocalizedString.title
        }
    }
}

/// Every Extras row that has a title, with the screen that shows it, so Settings search can offer each one.
func forkExtrasSearchableRows(strings: PresentationStrings) -> [(id: Int32, title: String, focus: ForkExtrasControllerFocus)] {
    var result: [(id: Int32, title: String, focus: ForkExtrasControllerFocus)] = []
    var seen = Set<Int32>()
    let categories: [ForkExtrasControllerFocus] = [.ninja, .ghost, .privacy, .appearance, .chatList, .tabBar, .messages, .messageSending, .messageActions, .messagesMore, .voiceAndRound, .media, .profile, .profileMore, .network]
    for focus in categories {
        let entries = forkExtrasControllerEntries(settings: .defaultSettings, autoFetchPublicMtProxy: false, showCallsTab: true, mediaInputSettings: .defaultSettings, focus: focus)
        for entry in entries {
            guard let title = entry.searchTitle(strings: strings), !title.isEmpty, seen.insert(entry.stableId).inserted else {
                continue
            }
            result.append((entry.stableId, title, focus))
        }
    }
    return result
}

public func forkExtrasController(context: AccountContext, focus: ForkExtrasControllerFocus = .top, focusItemId: Int32? = nil) -> ViewController {
    if focus != .network && focusItemId == 146 {
        return forkExtrasController(context: context, focus: .network, focusItemId: 146)
    }
    // Rows moved between screens when Extras was regrouped by window; links and search results keep their old page.
    if let id = focusItemId, let owner = ForkExtrasEntry.regroupedOwner(of: id), owner != focus.resolvedCategory {
        return forkExtrasController(context: context, focus: owner, focusItemId: id)
    }
    if let id = focusItemId, id == 1610 || id == 1611 {
        return bananaGramThemePreviewController(context: context, dark: id == 1611) ?? themeSettingsController(context: context)
    }
    // Preserve already shared links to the former automatic-proxy switch.
    if focus == .network && focusItemId == 142 {
        return context.sharedContext.makeProxySettingsController(context: context)
    }
    let updateDisposable = MetaDisposable()
    /// Debounce regex pattern edits — each keystroke must not rewrite AccountManager + rebuild history filters.
    let regexPatternsDisposable = MetaDisposable()
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    func presentPicker(title: String, options: [(String, () -> Void)], destructiveTitles: Set<String> = []) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
        for (optionTitle, action) in options {
            let color: ActionSheetButtonColor = destructiveTitles.contains(optionTitle) ? .destructive : .accent
            items.append(ActionSheetButtonItem(title: optionTitle, color: color, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                action()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(actionSheet)
    }

    let arguments = ForkExtrasControllerArguments(
        updateGhostModeMaster: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.setFullGhostMode(value)
                return updated
            }.start())
        },
        updateGhostReadOnInteract: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostReadOnInteract = value
                if value {
                    updated.ghostScheduleMessages = false
                }
                return updated
            }.start())
        },
        openAccentSaturation: {
            let percents: [Int32] = [0, 25, 50, 75, 100]
            presentPicker(title: ForkExtrasLocalizedString.accentSaturation, options: percents.map { percent in
                ("\(percent)%", {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.accentColorSaturation = percent
                        return updated
                    }.start())
                })
            })
        },
        openTranslationBackend: {
            var options: [(String, () -> Void)] = [
                (ForkExtrasLocalizedString.backendDefault, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.translationBackend = .default
                        return updated
                    }.start())
                })
            ]
            // Apple's on-device translation needs iOS 18; offering it earlier selected an engine that never ran.
            if #available(iOS 18.0, *) {
                options.append((ForkExtrasLocalizedString.backendSystem, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.translationBackend = .system
                        return updated
                    }.start())
                }))
            }
            presentPicker(title: ForkExtrasLocalizedString.translationBackend, options: options)
        },
        openTranscriptionBackend: {
            presentPicker(title: ForkExtrasLocalizedString.transcriptionBackend, options: [
                (ForkExtrasLocalizedString.backendDefault, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.transcriptionBackend = .default
                        return updated
                    }.start())
                }),
                (ForkExtrasLocalizedString.backendApple, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.transcriptionBackend = .apple
                        return updated
                    }.start())
                })
            ])
        },
        updateScrollToNextChatDisabled: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.scrollToNextChatDisabled = value
                return updated
            }.start())
        },
        updateDeletedMessageMark: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.deletedMessageMark = value
                return updated
            }.start())
        },
        updateEditedMessageMark: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.editedMessageMark = value
                return updated
            }.start())
        },
        updateGhostScheduleMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostScheduleMessages = value
                if value {
                    updated.ghostReadOnInteract = false
                }
                return updated
            }.start())
        },
        updateRegexFilterPatternsText: { value in
            regexPatternsDisposable.set((
                Signal<String, NoError>.single(value)
                |> delay(0.4, queue: Queue.mainQueue())
                |> mapToSignal { value in
                    return updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        let patterns = value
                            .split(whereSeparator: { $0.isNewline })
                            .map { String($0).trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        // Skip no-op writes (avoids filter recompile + sharedData fan-out while typing).
                        if updated.regexMessageFilterPatterns == patterns {
                            return updated
                        }
                        updated.regexMessageFilterPatterns = patterns
                        return updated
                    }
                }
            ).start())
        },
        exportMessageSavingDatabase: {
            // Encoding the store and copying every saved attachment runs off the main thread: with
            // a few GB of media it blocked the UI long enough for the watchdog to kill the app.
            DispatchQueue.global(qos: .userInitiated).async {
            MessageSavingStore.flush()
            let exportedUrl = MessageSavingStore.exportBundle()
            let exportedRecordCount = MessageSavingStore.recordCount
            DispatchQueue.main.async {
            guard let url = exportedUrl else {
                // Was a silent no-op — with a failed bundle the row looked simply dead.
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let alert = textAlertController(context: context, title: nil, text: ForkExtrasLocalizedString.exportMessageSavingFailed, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                presentControllerImpl?(alert)
                return
            }
            // Folder URL: AirDrop / "Save to Files" accept it. Import the folder itself (not a
            // zip — the picker does not open archives).
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: url)
                // The bundle existed with `exportedRecordCount` records whether or not the user
                // shared it — tell them, so an empty/short backup is caught before a restore.
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let text = ForkExtrasLocalizedString.exportMessageSavingDone.replacingOccurrences(of: "{count}", with: "\(exportedRecordCount)")
                let alert = textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                presentControllerImpl?(alert)
            }
            forkExtrasPresentNativeController(activity, context: context)
            }
            }
        },
        importMessageSavingDatabase: {
            presentPicker(
                title: ForkExtrasLocalizedString.importMessageSaving,
                options: [
                    (ForkExtrasLocalizedString.importMessageSavingMerge, {
                        ForkExtrasMessageSavingImportPresenter.shared.present(replace: false, context: context, present: { presentControllerImpl?($0) })
                    }),
                    (ForkExtrasLocalizedString.importMessageSavingReplace, {
                        ForkExtrasMessageSavingImportPresenter.shared.present(replace: true, context: context, present: { presentControllerImpl?($0) })
                    }),
                ],
                destructiveTitles: [ForkExtrasLocalizedString.importMessageSavingReplace]
            )
        },
        openDestination: { destination in
            switch destination {
            case .proxy: pushControllerImpl?(context.sharedContext.makeProxySettingsController(context: context))
            case .security: pushControllerImpl?(bananaSecurityController(context: context))
            case .accountOrder: pushControllerImpl?(accountOrderController(context: context))
            case .messageSending: pushControllerImpl?(forkExtrasController(context: context, focus: .messageSending))
            case .messageActions: pushControllerImpl?(forkExtrasController(context: context, focus: .messageActions))
            case .voiceAndRound: pushControllerImpl?(forkExtrasController(context: context, focus: .voiceAndRound))
            case .messagesMore: pushControllerImpl?(forkExtrasController(context: context, focus: .messagesMore))
            case .profileMore: pushControllerImpl?(forkExtrasController(context: context, focus: .profileMore))
            case .connectionCheck:
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let proxySettings: Signal<ProxySettings, NoError> = context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
                |> map { sharedData -> ProxySettings in
                    return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
                }
                // The screen's own checker, kept alive by its signal: pings the saved servers as the proxy list does.
                let statusesContext = ProxyServersStatuses(network: context.account.network, servers: proxySettings
                |> map { proxySettings -> [ProxyServerSettings] in
                    return proxySettings.servers.filter { !proxySettings.automaticServers.contains($0) }
                })
                let statuses = statusesContext.statuses()
                |> map { value -> [ProxyServerSettings: ProxyServerStatus] in
                    let _ = statusesContext
                    return value
                }
                pushControllerImpl?(proxyConnectionStatusController(presentationData: presentationData, updatedPresentationData: context.sharedContext.presentationData, proxySettings: proxySettings, statuses: statuses, connectionStatus: context.account.network.connectionStatus))
            }
        },
        updateMusicPolicy: { id, value in
            updateDisposable.set(updateMediaInputSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                switch id {
                case 2001: return current.withUpdatedPauseMusicOnRecording(value)
                case 2002: return current.withUpdatedVoiceMusicPolicy(recording: value)
                case 2003: return current.withUpdatedVoiceMusicPolicy(playback: value)
                default: return current
                }
            }).start())
        },
        openCategory: { category in
            pushControllerImpl?(forkExtrasController(context: context, focus: category))
        },
        context: context,
        openBrandTheme: { dark in
            if let controller = bananaGramThemePreviewController(context: context, dark: dark) {
                pushControllerImpl?(controller)
            }
        },
        updateCallsTab: { value in
            updateDisposable.set(updateCallListSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withUpdatedShowTab(value) }.start())
        },
        updateAppearance: { keyPath, value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated[keyPath: keyPath] = value
                if value && keyPath == \ForkExtrasSettings.roundVideoAlwaysResetZoom {
                    updated.staticRoundVideoZoom = false
                } else if value && keyPath == \ForkExtrasSettings.staticRoundVideoZoom {
                    updated.roundVideoAlwaysResetZoom = false
                }
                return updated
            }.start())
        },
        openStickerSize: {
            let percents: [Int32] = [50, 75, 100, 125, 150]
            presentPicker(title: ForkExtrasLocalizedString.stickerSize, options: percents.map { percent in
                ("\(percent)%", {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.stickerSizePercent = percent
                        return updated
                    }.start())
                })
            })
        },
        openOutgoingPhotoQuality: {
            presentPicker(title: ForkExtrasLocalizedString.outgoingPhotoQuality, options: [
                (ForkExtrasLocalizedString.outgoingPhotoQualityDefault, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.outgoingPhotoQuality = 0
                        return updated
                    }.start())
                }),
                (ForkExtrasLocalizedString.outgoingPhotoQualityBetter, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.outgoingPhotoQuality = 1
                        return updated
                    }.start())
                }),
                (ForkExtrasLocalizedString.outgoingPhotoQualityMax, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.outgoingPhotoQuality = 2
                        return updated
                    }.start())
                }),
            ])
        },
        openIntChoice: { id in
            let russian = ForkPresentationLanguage.prefersRussianStrings
            if id == 2106 {
                presentPicker(title: russian ? "Локальный значок (виден только вам)" : "Local badge (only visible to you)", options: forkLocalVerificationOptions(russian: russian).map { option in
                    (option.0, {
                        updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                            var updated = current
                            let accountId = context.account.id.int64
                            if option.1 == 0 { updated.localVerificationBadges.removeValue(forKey: accountId) }
                            else { updated.localVerificationBadges[accountId] = option.1 }
                            return updated
                        }.start())
                    })
                })
                return
            }
            if id == 1981 {
                presentPicker(title: russian ? "Визуальная метка" : "Visual label", options: forkVisualLabelOptions(russian: russian).map { option in
                    (option.0, {
                        updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                            var updated = current
                            let accountId = context.account.peerId.toInt64()
                            if option.1 == 0 { updated.visualLabels.removeValue(forKey: accountId) }
                            else { updated.visualLabels[accountId] = option.1 }
                            return updated
                        }.start())
                    })
                })
                return
            }
            let title: String
            let options: [(String, Int32)]
            let keyPath: WritableKeyPath<ForkExtrasSettings, Int32>
            switch id {
            case 1753:
                title = russian ? "Форма стикеров" : "Sticker shape"
                options = forkStickerShapeOptions(russian: russian)
                keyPath = \.stickerShape
            case 1755:
                title = russian ? "Перемотка двойным касанием" : "Double-tap seek"
                options = forkDoubleTapSeekOptions(russian: russian)
                keyPath = \.doubleTapSeekSeconds
            case 1802:
                title = russian ? "Двойное касание" : "Double-tap action"
                options = forkDoubleTapActionOptions(russian: russian)
                keyPath = \.doubleTapAction
            case 1902:
                title = russian ? "Оттенок стекла" : "Glass tint"
                options = forkGlassTintOptions(russian: russian)
                keyPath = \.glassBubbleTint
            case 1903:
                title = russian ? "Блик сверху" : "Rim: top"
                options = forkGlassRimOptions(russian: russian)
                keyPath = \.glassBubbleRimTop
            case 1904:
                title = russian ? "Блик по бокам" : "Rim: sides"
                options = forkGlassRimOptions(russian: russian)
                keyPath = \.glassBubbleRimSides
            case 1905:
                title = russian ? "Блик снизу" : "Rim: bottom"
                options = forkGlassRimOptions(russian: russian)
                keyPath = \.glassBubbleRimBottom
            case 1851:
                title = russian ? "Формат по умолчанию" : "Default formatting"
                options = forkSendFormattingOptions(russian: russian)
                keyPath = \.defaultSendFormatting
            case 1864:
                title = russian ? "Качество видео по умолчанию" : "Default video quality"
                options = forkVideoQualityOptions(russian: russian)
                keyPath = \.defaultVideoQuality
            default:
                return
            }
            presentPicker(title: title, options: options.map { option in
                (option.0, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated[keyPath: keyPath] = option.1
                        return updated
                    }.start())
                })
            })
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: context.sharedContext.accountManager),
        context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings, ApplicationSpecificSharedDataKeys.callListSettings, ApplicationSpecificSharedDataKeys.mediaInputSettings])
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let proxySettings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
        // The Network page shows how the app connects: the active proxy's kind and host (no secret, no password).
        let connectionSummary: (viaProxy: Bool, detail: String)
        if let server = proxySettings.effectiveActiveServer {
            let kind: String
            switch server.connection {
            case .socks5:
                kind = "SOCKS5"
            case .mtp:
                kind = "MTProto"
            case .web:
                kind = "WEB"
            case .vless:
                kind = "VLESS"
            }
            connectionSummary = (true, "\(kind) · \(server.host)")
        } else {
            connectionSummary = (false, ForkPresentationLanguage.prefersRussianStrings ? "Без прокси" : "No proxy")
        }
        let entries = forkExtrasControllerEntries(settings: settings, autoFetchPublicMtProxy: proxySettings.autoFetchPublicMtProxy, showCallsTab: (sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? .defaultSettings).showTab, mediaInputSettings: sharedData.entries[ApplicationSpecificSharedDataKeys.mediaInputSettings]?.get(MediaInputSettings.self) ?? .defaultSettings, focus: focus, accountPeerId: context.account.peerId.toInt64(), accountRecordId: context.account.id.int64, connectionSummary: connectionSummary)
        let focusedSection: ItemListSectionId?
        switch focus {
        case .messageSaving:
            focusedSection = ForkExtrasSection.messageSaving.rawValue
        case .messageFilters:
            focusedSection = ForkExtrasSection.messageFilters.rawValue
        default:
            focusedSection = nil
        }
        let initialScrollToItem: ListViewScrollToItem?
        if let focusItemId, let index = entries.firstIndex(where: { $0.stableId == focusItemId }) {
            initialScrollToItem = ListViewScrollToItem(index: index, position: .top(0.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Down)
        } else if let focusedSection, let index = entries.firstIndex(where: { $0.section == focusedSection }) {
            initialScrollToItem = ListViewScrollToItem(index: index, position: .top(0.0), animated: false, curve: .Default(duration: 0.0), directionHint: .Down)
        } else {
            initialScrollToItem = nil
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(focus.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            initialScrollToItem: initialScrollToItem
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    let linkGesture = BananaSettingsLinkGesture(controller: controller, context: context, focus: focus)
    controller.afterTransactionCompleted = {
        // The callback owns its gesture target; the target only weakly references the controller.
        linkGesture.highlight(id: focusItemId)
    }
    presentControllerImpl = { [weak controller] presented in
        controller?.present(presented, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}
