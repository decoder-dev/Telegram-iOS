import Foundation
import UIKit
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
        // iOS 13-compatible picker API. Includes JSON and folders so we can import
        // either a bare records.json or a full exportBundle() directory.
        let picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.folder"], in: .open)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        forkExtrasPresentNativeController(picker, context: context)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let result = MessageSavingStore.importBundle(from: url, replace: self.replace)
        let presentationData = context?.sharedContext.currentPresentationData.with { $0 }
        guard let context = self.context, let presentationData else {
            return
        }
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


private enum ForkExtrasLocalizedString {
    private static let translations: [String: [String: String]] = [
        "en": [
            "ForkExtras.Title": "Extras",
            "ForkExtras.GhostModeMaster": "Ghost Mode",
            "ForkExtras.GhostDontReadMessages": "Don't Read Messages",
            "ForkExtras.GhostDontReadStories": "Don't Read Stories",
            "ForkExtras.GhostDontSendOnline": "Don't Send Online",
            "ForkExtras.GhostDontSendTyping": "Don't Send Typing",
            "ForkExtras.GhostGoOfflineAutomatically": "Go Offline Automatically",
            "ForkExtras.GhostGoOfflineAutomaticallyFooter": "After briefly appearing online, immediately go offline again.",
            "ForkExtras.GhostReadOnInteract": "Read on Interact",
            "ForkExtras.GhostReadOnInteractFooter": "When Don't Read Messages is on, mark chats read and blink online after you send or react.",
            "ForkExtras.GhostAlertBeforeOpeningStory": "Alert Before Opening Story",
            "ForkExtras.GhostAlertBeforeOpeningStoryFooter": "Ask before opening any story. Tap outside to dismiss without opening.",
            "ForkExtras.GhostModeFooter": "The master switch enables Don't Read Messages, Don't Read Stories, Don't Send Online, Don't Send Typing, and Go Offline Automatically. Each option can still be toggled independently.",
            "ForkExtras.InstantPasscode": "Instant Passcode Lock",
            "ForkExtras.InstantPasscodeFooter": "Lock the app as soon as it leaves the foreground.",
            "ForkExtras.StreamerMode": "Streamer Mode",
            "ForkExtras.StreamerModeFooter": "Hide your phone number and username in profiles and the Settings header (AyuGram-style).",
            "ForkExtras.HideMentions": "Hide Mention Notifications",
            "ForkExtras.HideMentionsFooter": "Suppress push notifications for mentions.",
            "ForkExtras.HidePinned": "Hide Pinned Notifications",
            "ForkExtras.HidePinnedFooter": "Suppress push notifications for pinned messages.",
            "ForkExtras.SessionBackup": "Keychain Session Backup",
            "ForkExtras.SessionBackupFooter": "Mirror account session data to the device Keychain for same-bundle reinstalls.",
            "ForkExtras.CompactChatList": "Compact Chat List",
            "ForkExtras.CompactMessagePreview": "Compact Message Preview",
            "ForkExtras.CompactFolderNames": "Compact Folder Names",
            "ForkExtras.UIDensityFooter": "Tighter list spacing. Rows stay at least 44 pt so they remain easy to tap.",
            "ForkExtras.HideReactionsBar": "Hide Reactions",
            "ForkExtras.HideReactionsBarFooter": "Hide the reaction bar under messages.",
            "ForkExtras.ShowDC": "Show Data Center & Registration Date",
            "ForkExtras.ShowProfileId": "Show Profile ID",
            "ForkExtras.PrivacyFooter": "Add extra diagnostic rows to profile screens.",
            "ForkExtras.AccentSaturation": "Accent Color Saturation",
            "ForkExtras.ConfirmBeforeCall": "Confirm Before Calling",
            "ForkExtras.SendWithReturnKey": "Send With Return Key",
            "ForkExtras.SendWithReturnKeyFooter": "Tapping Return on the keyboard sends the message instead of adding a new line.",
            "ForkExtras.ForceBuiltInMic": "Force Built-in Microphone",
            "ForkExtras.ForceBuiltInMicFooter": "Use the device's built-in microphone instead of a connected Bluetooth device for calls and voice messages.",
            "ForkExtras.CallsFooter": "Ask for confirmation before dialing a call.",
            "ForkExtras.TranslationBackend": "Translation",
            "ForkExtras.TranscriptionBackend": "Voice Transcription",
            "ForkExtras.TranslationFooter": "Choose an alternative translation or voice-transcription engine, independent of Telegram Premium.",
            "ForkExtras.ScrollToNextChat": "Swipe to Next Chat",
            "ForkExtras.ScrollToNextChatFooter": "Swiping up on the last message jumps to the next unread chat or topic.",
            "ForkExtras.BackendDefault": "Default",
            "ForkExtras.BackendSystem": "System (Apple)",
            "ForkExtras.BackendApple": "On-Device (Apple)",
            "ForkExtras.SaveDeletedMessages": "Save Deleted Messages",
            "ForkExtras.SaveDeletedMessagesFooter": "Keep deleted messages (yours and others), including one-time media, visible in chat (🧹). Also under View Deleted.",
            "ForkExtras.SaveMessagesHistory": "Save Edit History",
            "ForkExtras.SaveMessagesHistoryFooter": "Keep previous text when a message is edited. Open Edit History from the message menu.",
            "ForkExtras.SaveMedia": "Save Media",
            "ForkExtras.SaveMediaFooter": "Copy attachments into local Saved Attachments on delete/TTL (own and others; AyuGram Android parity).",
            "ForkExtras.SaveForBots": "Also Save Bot Messages",
            "ForkExtras.AyuForward": "AyuForward",
            "ForkExtras.AyuForwardFooter": "Forward from noforwards channels and deleted messages by re-uploading media without an author (AyuGram Android).",
            "ForkExtras.BypassDownloadRestrictions": "Save Stories & Protected Media",
            "ForkExtras.BypassDownloadRestrictionsFooter": "Save stories and download protected media without Telegram Premium, even when forwarding is disabled (AyuGram Desktop).",
            "ForkExtras.ProactiveSaveMedia": "Proactively Download Media",
            "ForkExtras.ProactiveSaveMediaFooter": "Actively download attachments that aren't fully cached yet, so TTL/delete can't outrun the save.",
            "ForkExtras.DeletedMessageMark": "Deleted Message Mark",
            "ForkExtras.DeletedMessageMarkFooter": "Shown before the time on deleted messages kept in chat.",
            "ForkExtras.EditedMessageMark": "Edited Message Mark",
            "ForkExtras.EditedMessageMarkFooter": "Replaces Telegram's \"edited\" label. Leave empty for the default.",
            "ForkExtras.LocalPremium": "Local Telegram Premium",
            "ForkExtras.LocalPremiumFooter": "Unlock client-side Premium UX on this device: Story Stealth Mode, HD stories, sticker/emoji cosmetics. Does not buy real Premium or change your badge for others.",
            "ForkExtras.AutoFetchMtProxy": "Auto MTProxy",
            "ForkExtras.AutoFetchMtProxyFooter": "Keeps Telegram on the fastest live public MTProxy automatically. Auto servers stay hidden from the saved list. Third-party nodes cannot read chats, but they see your IP.",
            "ForkExtras.HideAds": "Hide Ads",
            "ForkExtras.HideAdsFooter": "Hide sponsored and recommended messages in chats.",
            "ForkExtras.HideBlockedMessages": "Hide Blocked Users",
            "ForkExtras.HideBlockedMessagesFooter": "Hide messages and typing from users you've blocked.",
            "ForkExtras.GhostScheduleMessages": "Schedule Messages (Ghost)",
            "ForkExtras.GhostScheduleMessagesFooter": "When full Ghost Mode is on, delay sending (text 12s; media max(6, ceil(MB×4.5))) so you stay offline (AyuGram).",
            "ForkExtras.AllowSecretScreenshots": "Screenshots in Secret Chats",
            "ForkExtras.AllowSecretScreenshotsFooter": "Allow screenshots in secret chats and of secret media, without notifying the peer.",
            "ForkExtras.ExpireTtlButton": "Expire TTL Button",
            "ForkExtras.ExpireTtlButtonFooter": "Tap the flame on expiring photos/videos to expire them immediately.",
            "ForkExtras.KeepBannedChats": "Keep Banned Chats",
            "ForkExtras.KeepBannedChatsFooter": "Keep chats where you were banned or kicked in the chat list.",
            "ForkExtras.RegexFilters": "Regex Message Filters",
            "ForkExtras.RegexFiltersCaseInsensitive": "Case Insensitive",
            "ForkExtras.RegexFiltersPatterns": "Patterns (one per line)",
            "ForkExtras.RegexFiltersFooter": "Hide messages matching any NSRegularExpression pattern, checked against the text, any button labels/links, and a trailing <type>N</type> tag (AyuGram Message Filters). Import a list from an allowlisted paste site via tg://ayu/filters/import/<host/path>.",
            "ForkExtras.ExportMessageSaving": "Export Saved Messages DB",
            "ForkExtras.ImportMessageSaving": "Import Saved Messages DB",
            "ForkExtras.ImportMessageSavingMerge": "Merge with existing",
            "ForkExtras.ImportMessageSavingReplace": "Replace existing",
            "ForkExtras.MessageSavingDbFooter": "Export / import the local deleted & edit-history JSON store (AyuGram DB backup), including a copy of Saved Attachments. Import also accepts a bare records.json.",
            "ForkExtras.ExportMessageSavingDone": "Exported {count} records.",
            "ForkExtras.ImportMessageSavingDone": "Imported {count} new records.",
            "ForkExtras.ImportMessageSavingFailed": "Could not import this file.",
            "ForkExtras.ViewDeleted": "View Deleted",
            "ForkExtras.EditHistory": "Edit History",
            "ForkExtras.ClearDeleted": "Clear Deleted",
            "ForkExtras.NoDeleted": "No deleted messages saved yet.",
            "ForkExtras.NoEdits": "No previous versions saved.",
            "ForkExtras.HubFooter": "Each row opens a grouped Settings list. Navigation, sheets and switches follow iOS conventions.",
            "ForkExtras.HubNinja": "Ninja",
            "ForkExtras.HubNinjaLabel": "Save, filters, bypass",
            "ForkExtras.HubGhost": "Ghost",
            "ForkExtras.HubGhostLabel": "Master switch, read receipts",
            "ForkExtras.HubPrivacy": "Privacy",
            "ForkExtras.HubPrivacyLabel": "Lock, notifications, backup",
            "ForkExtras.HubInterface": "Interface",
            "ForkExtras.HubInterfaceLabel": "List, folders, appearance",
            "ForkExtras.HubChat": "Chat",
            "ForkExtras.HubChatLabel": "Composer, translate, menus",
            "ForkExtras.HubNetwork": "Network",
            "ForkExtras.HubNetworkLabel": "Proxy, downloads, Premium",
            "ForkExtras.HideAllChats": "Hide All Chats Tab",
            "ForkExtras.HideAllChatsFooter": "When you have folders, hide the All Chats tab and stay in folders only.",
            "ForkExtras.RememberLastFolder": "Remember Last Folder",
            "ForkExtras.RememberLastFolderFooter": "Open the last used folder after launch or switching accounts.",
            "ForkExtras.HideTabBar": "Hide Tab Bar",
            "ForkExtras.HideTabBarFooter": "Hides Chats / Contacts / Settings at the bottom of iPhone. Settings stays in the chat list header. iPad always keeps the tab bar.",
            "ForkExtras.ShowMessageSeconds": "Seconds in Timestamps",
            "ForkExtras.ShowMessageSecondsFooter": "Show hours:minutes:seconds on message times.",
            "ForkExtras.WideChannelPosts": "Wide Channel Posts",
            "ForkExtras.WideChannelPostsFooter": "Let bubbles use more of the screen width.",
            "ForkExtras.StickerSize": "Sticker Size",
            "ForkExtras.DoubleTapToEdit": "Double-Tap to Edit",
            "ForkExtras.DoubleTapToEditFooter": "Double-tap your own message to edit it. Edit is also in the message menu.",
            "ForkExtras.QuickTranslate": "Quick Translate",
            "ForkExtras.QuickTranslateFooter": "Always show Translate in the message menu.",
            "ForkExtras.SaveToCloud": "Save to Saved Messages",
            "ForkExtras.SaveToCloudFooter": "Add a context-menu action that copies the message into Saved Messages.",
            "ForkExtras.SelectFromAuthor": "Select from Author",
            "ForkExtras.SelectFromAuthorFooter": "Select loaded messages from the same sender.",
            "ForkExtras.DownloadSpeedBoost": "Download Speed Boost",
            "ForkExtras.DownloadSpeedBoostFooter": "Larger download chunks and more parallel parts. Uses more data and battery.",
            "ForkExtras.OutgoingPhotoQuality": "Outgoing Photo Quality",
            "ForkExtras.OutgoingPhotoQualityDefault": "Default (1280)",
            "ForkExtras.OutgoingPhotoQualityBetter": "Better (1920)",
            "ForkExtras.OutgoingPhotoQualityMax": "Maximum (2560)",
            "ForkExtras.OutgoingPhotoQualityFooter": "Size cap when sending photos from the camera roll. Maximum is like Telegram HD.",
        ],
        "ru": [
            "ForkExtras.Title": "Дополнительно",
            "ForkExtras.GhostModeMaster": "Режим призрака",
            "ForkExtras.GhostDontReadMessages": "Не читать сообщения",
            "ForkExtras.GhostDontReadStories": "Не читать истории",
            "ForkExtras.GhostDontSendOnline": "Не отправлять онлайн",
            "ForkExtras.GhostDontSendTyping": "Не отправлять набор",
            "ForkExtras.GhostGoOfflineAutomatically": "Сразу уходить в офлайн",
            "ForkExtras.GhostGoOfflineAutomaticallyFooter": "После короткого появления онлайн сразу снова уходить в офлайн.",
            "ForkExtras.GhostReadOnInteract": "Читать при взаимодействии",
            "ForkExtras.GhostReadOnInteractFooter": "Если включено «Не читать сообщения», отмечать прочтение и кратко показывать онлайн после отправки или реакции.",
            "ForkExtras.GhostAlertBeforeOpeningStory": "Спрашивать перед открытием истории",
            "ForkExtras.GhostAlertBeforeOpeningStoryFooter": "Показывать предупреждение перед открытием истории. Нажатие снаружи закрывает без открытия.",
            "ForkExtras.GhostModeFooter": "Мастер-переключатель включает «Не читать сообщения», «Не читать истории», «Не отправлять онлайн», «Не отправлять набор» и «Сразу уходить в офлайн». Каждую опцию можно включать отдельно.",
            "ForkExtras.InstantPasscode": "Мгновенная блокировка",
            "ForkExtras.InstantPasscodeFooter": "Блокировать приложение сразу при уходе в фон.",
            "ForkExtras.StreamerMode": "Режим стримера",
            "ForkExtras.StreamerModeFooter": "Скрывать номер телефона и имя пользователя в профилях и в шапке Настроек.",
            "ForkExtras.HideMentions": "Скрыть уведомления об упоминаниях",
            "ForkExtras.HideMentionsFooter": "Не показывать push-уведомления об упоминаниях.",
            "ForkExtras.HidePinned": "Скрыть уведомления о закреплении",
            "ForkExtras.HidePinnedFooter": "Не показывать push-уведомления о закреплённых сообщениях.",
            "ForkExtras.SessionBackup": "Резерв сессии в Keychain",
            "ForkExtras.SessionBackupFooter": "Дублировать данные сессии в Keychain для переустановки с тем же Bundle ID.",
            "ForkExtras.CompactChatList": "Компактный список чатов",
            "ForkExtras.CompactMessagePreview": "Компактное превью сообщений",
            "ForkExtras.CompactFolderNames": "Компактные названия папок",
            "ForkExtras.UIDensityFooter": "Плотнее список. Строки не ниже 44 pt, чтобы их было удобно нажимать.",
            "ForkExtras.HideReactionsBar": "Скрыть реакции",
            "ForkExtras.HideReactionsBarFooter": "Скрыть панель реакций под сообщениями.",
            "ForkExtras.ShowDC": "Показать DC и дату регистрации",
            "ForkExtras.ShowProfileId": "Показать ID профиля",
            "ForkExtras.PrivacyFooter": "Добавить дополнительные диагностические строки на экраны профиля.",
            "ForkExtras.AccentSaturation": "Насыщенность акцентного цвета",
            "ForkExtras.ConfirmBeforeCall": "Подтверждать перед звонком",
            "ForkExtras.SendWithReturnKey": "Отправка по Enter",
            "ForkExtras.SendWithReturnKeyFooter": "Нажатие Enter на клавиатуре отправляет сообщение вместо новой строки.",
            "ForkExtras.ForceBuiltInMic": "Только встроенный микрофон",
            "ForkExtras.ForceBuiltInMicFooter": "Использовать встроенный микрофон устройства вместо подключённого Bluetooth-устройства для звонков и голосовых сообщений.",
            "ForkExtras.CallsFooter": "Запрашивать подтверждение перед началом звонка.",
            "ForkExtras.TranslationBackend": "Перевод",
            "ForkExtras.TranscriptionBackend": "Расшифровка голоса",
            "ForkExtras.TranslationFooter": "Выбрать альтернативный движок перевода или расшифровки голоса, независимо от Telegram Premium.",
            "ForkExtras.ScrollToNextChat": "Свайп к следующему чату",
            "ForkExtras.ScrollToNextChatFooter": "Смахивание вверх на последнем сообщении переходит к следующему непрочитанному чату или теме.",
            "ForkExtras.BackendDefault": "По умолчанию",
            "ForkExtras.BackendSystem": "Системный (Apple)",
            "ForkExtras.BackendApple": "На устройстве (Apple)",
            "ForkExtras.SaveDeletedMessages": "Сохранять удалённые",
            "ForkExtras.SaveDeletedMessagesFooter": "Свои и чужие удалённые, включая одноразовые медиа, остаются в чате (🧹). Также в «Удалённые».",
            "ForkExtras.SaveMessagesHistory": "История правок",
            "ForkExtras.SaveMessagesHistoryFooter": "Хранить предыдущий текст при редактировании. Открывается из меню сообщения.",
            "ForkExtras.SaveMedia": "Сохранять медиа",
            "ForkExtras.SaveMediaFooter": "Копировать вложения в Saved Attachments при удалении/TTL (свои и чужие; как в AyuGram Android).",
            "ForkExtras.SaveForBots": "Также сохранять ботов",
            "ForkExtras.AyuForward": "AyuForward",
            "ForkExtras.AyuForwardFooter": "Пересылать из каналов с запретом пересылки и удалённые сообщения: медиа загружается заново без автора (AyuGram Android).",
            "ForkExtras.BypassDownloadRestrictions": "Сохранять истории и защищённые медиа",
            "ForkExtras.BypassDownloadRestrictionsFooter": "Сохранять истории и скачивать защищённые медиа без Premium, даже при запрете пересылки (AyuGram Desktop).",
            "ForkExtras.ProactiveSaveMedia": "Активно скачивать медиа",
            "ForkExtras.ProactiveSaveMediaFooter": "Активно скачивать ещё не кэшированные вложения, чтобы TTL/удаление не обгоняло сохранение.",
            "ForkExtras.DeletedMessageMark": "Метка удалённого",
            "ForkExtras.DeletedMessageMarkFooter": "Показывается перед временем на сохранённых удалённых сообщениях.",
            "ForkExtras.EditedMessageMark": "Метка изменённого",
            "ForkExtras.EditedMessageMarkFooter": "Вместо метки «изменено». Пусто — стандарт Telegram.",
            "ForkExtras.LocalPremium": "Локальный Telegram Premium",
            "ForkExtras.LocalPremiumFooter": "Клиентские функции Premium на этом устройстве: stealth историй, HD, косметика стикеров/эмодзи. Не покупает Premium и не меняет ваш значок для других.",
            "ForkExtras.AutoFetchMtProxy": "Авто MTProxy",
            "ForkExtras.AutoFetchMtProxyFooter": "Сам держит соединение на самом быстром живом публичном MTProxy. Авто-серверы в списке сохранённых не показываются. Чужие ноды не читают чаты, но видят IP.",
            "ForkExtras.HideAds": "Скрыть рекламу",
            "ForkExtras.HideAdsFooter": "Скрывать спонсорские и рекомендованные сообщения в чатах.",
            "ForkExtras.HideBlockedMessages": "Скрыть заблокированных",
            "ForkExtras.HideBlockedMessagesFooter": "Скрывать сообщения и набор текста от заблокированных пользователей.",
            "ForkExtras.GhostScheduleMessages": "Отложенная отправка (призрак)",
            "ForkExtras.GhostScheduleMessagesFooter": "При полном режиме призрака откладывать отправку (текст 12 с; медиа max(6, ceil(МБ×4.5))), чтобы оставаться офлайн (AyuGram).",
            "ForkExtras.AllowSecretScreenshots": "Скриншоты в секретных чатах",
            "ForkExtras.AllowSecretScreenshotsFooter": "Разрешить скриншоты в секретных чатах и секретного медиа без уведомления собеседника.",
            "ForkExtras.ExpireTtlButton": "Кнопка Expire TTL",
            "ForkExtras.ExpireTtlButtonFooter": "Нажатие на пламя у самоуничтожающихся фото/видео сразу истекает их.",
            "ForkExtras.KeepBannedChats": "Сохранять забаненные чаты",
            "ForkExtras.KeepBannedChatsFooter": "Оставлять в списке чаты, из которых вас забанили или кикнули.",
            "ForkExtras.RegexFilters": "Regex-фильтры сообщений",
            "ForkExtras.RegexFiltersCaseInsensitive": "Без учёта регистра",
            "ForkExtras.RegexFiltersPatterns": "Шаблоны (по одному в строке)",
            "ForkExtras.RegexFiltersFooter": "Скрывать сообщения, совпадающие с любым NSRegularExpression: проверяются текст, подписи/ссылки кнопок и завершающий тег <type>N</type> (фильтры AyuGram). Список шаблонов можно импортировать с разрешённого paste-сайта через tg://ayu/filters/import/<host/path>.",
            "ForkExtras.ExportMessageSaving": "Экспорт БД сохранённых",
            "ForkExtras.ImportMessageSaving": "Импорт БД сохранённых",
            "ForkExtras.ImportMessageSavingMerge": "Объединить с текущей",
            "ForkExtras.ImportMessageSavingReplace": "Заменить текущую",
            "ForkExtras.MessageSavingDbFooter": "Экспорт / импорт локального JSON с удалёнными и историей правок (бэкап БД AyuGram), включая копию Saved Attachments. При импорте также подходит обычный records.json.",
            "ForkExtras.ExportMessageSavingDone": "Экспортировано записей: {count}.",
            "ForkExtras.ImportMessageSavingDone": "Добавлено новых записей: {count}.",
            "ForkExtras.ImportMessageSavingFailed": "Не удалось импортировать файл.",
            "ForkExtras.ViewDeleted": "Удалённые",
            "ForkExtras.EditHistory": "История правок",
            "ForkExtras.ClearDeleted": "Очистить удалённые",
            "ForkExtras.NoDeleted": "Пока нет сохранённых удалённых сообщений.",
            "ForkExtras.NoEdits": "Предыдущих версий нет.",
            "ForkExtras.HubFooter": "Каждая строка открывает grouped-список как в Настройках iOS: навигация, шиты и переключатели системные.",
            "ForkExtras.HubNinja": "Ниндзя",
            "ForkExtras.HubNinjaLabel": "Сохранение, фильтры, обход",
            "ForkExtras.HubGhost": "Невидимка",
            "ForkExtras.HubGhostLabel": "Мастер-переключатель, прочтения",
            "ForkExtras.HubPrivacy": "Приватность",
            "ForkExtras.HubPrivacyLabel": "Блокировка, уведомления, бэкап",
            "ForkExtras.HubInterface": "Интерфейс",
            "ForkExtras.HubInterfaceLabel": "Список, папки, внешний вид",
            "ForkExtras.HubChat": "Чат",
            "ForkExtras.HubChatLabel": "Ввод, перевод, меню",
            "ForkExtras.HubNetwork": "Сеть",
            "ForkExtras.HubNetworkLabel": "Прокси, загрузки, Premium",
            "ForkExtras.HideAllChats": "Скрыть «Все чаты»",
            "ForkExtras.HideAllChatsFooter": "Если есть папки, вкладка «Все чаты» скрывается — остаются только папки.",
            "ForkExtras.RememberLastFolder": "Запоминать последнюю папку",
            "ForkExtras.RememberLastFolderFooter": "Открывать последнюю папку после запуска или смены аккаунта.",
            "ForkExtras.HideTabBar": "Скрыть панель вкладок",
            "ForkExtras.HideTabBarFooter": "На iPhone прячет Чаты / Контакты / Настройки снизу. Настройки остаются в шапке списка чатов. На iPad панель вкладок всегда на месте.",
            "ForkExtras.ShowMessageSeconds": "Секунды во времени",
            "ForkExtras.ShowMessageSecondsFooter": "Показывать часы:минуты:секунды у сообщений.",
            "ForkExtras.WideChannelPosts": "Широкие посты",
            "ForkExtras.WideChannelPostsFooter": "Пузыри занимают больше ширины экрана.",
            "ForkExtras.StickerSize": "Размер стикеров",
            "ForkExtras.DoubleTapToEdit": "Двойной тап — править",
            "ForkExtras.DoubleTapToEditFooter": "Двойной тап по своему сообщению открывает правку. Правка также есть в меню сообщения.",
            "ForkExtras.QuickTranslate": "Быстрый перевод",
            "ForkExtras.QuickTranslateFooter": "Всегда показывать «Перевести» в меню сообщения.",
            "ForkExtras.SaveToCloud": "В Избранное",
            "ForkExtras.SaveToCloudFooter": "Пункт меню, который копирует сообщение в Избранное.",
            "ForkExtras.SelectFromAuthor": "Выбрать от автора",
            "ForkExtras.SelectFromAuthorFooter": "Выделить загруженные сообщения этого отправителя.",
            "ForkExtras.DownloadSpeedBoost": "Ускорить загрузки",
            "ForkExtras.DownloadSpeedBoostFooter": "Больше куски и параллельные части. Больше трафика и батареи.",
            "ForkExtras.OutgoingPhotoQuality": "Качество исходящих фото",
            "ForkExtras.OutgoingPhotoQualityDefault": "Обычное (1280)",
            "ForkExtras.OutgoingPhotoQualityBetter": "Лучше (1920)",
            "ForkExtras.OutgoingPhotoQualityMax": "Максимум (2560)",
            "ForkExtras.OutgoingPhotoQualityFooter": "Ограничение размера при отправке фото из галереи. Максимум как HD в Telegram.",
        ],
    ]
    
    private static func languageCode() -> String {
        // The app's language first — Telegram's own setting is independent of the device's.
        // The device list stays as the fallback for the window before the first push.
        if let appLanguage = ForkPresentationLanguage.languageCode, translations[appLanguage] != nil {
            return appLanguage
        }
        let candidates = Locale.preferredLanguages + Bundle.main.preferredLocalizations
        for candidate in candidates {
            let code = String(candidate.prefix(2)).lowercased()
            if translations[code] != nil {
                return code
            }
        }
        return "en"
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
    static var importMessageSavingDone: String { string(forKey: "ForkExtras.ImportMessageSavingDone") }
    static var importMessageSavingFailed: String { string(forKey: "ForkExtras.ImportMessageSavingFailed") }
    static var viewDeleted: String { string(forKey: "ForkExtras.ViewDeleted") }
    static var editHistory: String { string(forKey: "ForkExtras.EditHistory") }
    static var clearDeleted: String { string(forKey: "ForkExtras.ClearDeleted") }
    static var noDeleted: String { string(forKey: "ForkExtras.NoDeleted") }
    static var noEdits: String { string(forKey: "ForkExtras.NoEdits") }
    static var hubFooter: String { string(forKey: "ForkExtras.HubFooter") }
    static var hubNinja: String { string(forKey: "ForkExtras.HubNinja") }
    static var hubNinjaLabel: String { string(forKey: "ForkExtras.HubNinjaLabel") }
    static var hubGhost: String { string(forKey: "ForkExtras.HubGhost") }
    static var hubGhostLabel: String { string(forKey: "ForkExtras.HubGhostLabel") }
    static var hubPrivacy: String { string(forKey: "ForkExtras.HubPrivacy") }
    static var hubPrivacyLabel: String { string(forKey: "ForkExtras.HubPrivacyLabel") }
    static var hubInterface: String { string(forKey: "ForkExtras.HubInterface") }
    static var hubInterfaceLabel: String { string(forKey: "ForkExtras.HubInterfaceLabel") }
    static var hubChat: String { string(forKey: "ForkExtras.HubChat") }
    static var hubChatLabel: String { string(forKey: "ForkExtras.HubChatLabel") }
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

private final class ForkExtrasControllerArguments {
    let updateGhostModeMaster: (Bool) -> Void
    let updateGhostDontReadMessages: (Bool) -> Void
    let updateGhostDontReadStories: (Bool) -> Void
    let updateGhostDontSendOnline: (Bool) -> Void
    let updateGhostDontSendTyping: (Bool) -> Void
    let updateGhostGoOfflineAutomatically: (Bool) -> Void
    let updateGhostReadOnInteract: (Bool) -> Void
    let updateGhostAlertBeforeOpeningStory: (Bool) -> Void
    let updateInstantPasscode: (Bool) -> Void
    let updateStreamerMode: (Bool) -> Void
    let updateHideMentions: (Bool) -> Void
    let updateHidePinned: (Bool) -> Void
    let updateSessionBackup: (Bool) -> Void
    let updateCompactChatList: (Bool) -> Void
    let updateCompactMessagePreview: (Bool) -> Void
    let updateCompactFolderNames: (Bool) -> Void
    let updateHideReactionsBar: (Bool) -> Void
    let updateShowDC: (Bool) -> Void
    let updateShowProfileId: (Bool) -> Void
    let openAccentSaturation: () -> Void
    let updateConfirmBeforeCall: (Bool) -> Void
    let updateSendWithReturnKey: (Bool) -> Void
    let updateForceBuiltInMic: (Bool) -> Void
    let openTranslationBackend: () -> Void
    let openTranscriptionBackend: () -> Void
    let updateScrollToNextChatDisabled: (Bool) -> Void
    let updateSaveDeletedMessages: (Bool) -> Void
    let updateSaveMessagesHistory: (Bool) -> Void
    let updateSaveMedia: (Bool) -> Void
    let updateSaveForBots: (Bool) -> Void
    let updateAyuForward: (Bool) -> Void
    let updateBypassDownloadRestrictions: (Bool) -> Void
    let updateProactiveSaveMedia: (Bool) -> Void
    let updateDeletedMessageMark: (String) -> Void
    let updateEditedMessageMark: (String) -> Void
    let updateLocalPremium: (Bool) -> Void
    let updateAutoFetchMtProxy: (Bool) -> Void
    let updateHideAds: (Bool) -> Void
    let updateHideBlockedMessages: (Bool) -> Void
    let updateGhostScheduleMessages: (Bool) -> Void
    let updateAllowSecretScreenshots: (Bool) -> Void
    let updateExpireTtlButton: (Bool) -> Void
    let updateKeepBannedChats: (Bool) -> Void
    let updateRegexFiltersEnabled: (Bool) -> Void
    let updateRegexFiltersCaseInsensitive: (Bool) -> Void
    let updateRegexFilterPatternsText: (String) -> Void
    let exportMessageSavingDatabase: () -> Void
    let importMessageSavingDatabase: () -> Void
    let openCategory: (ForkExtrasControllerFocus) -> Void
    let updateHideAllChats: (Bool) -> Void
    let updateRememberLastFolder: (Bool) -> Void
    let updateHideTabBar: (Bool) -> Void
    let updateShowMessageSeconds: (Bool) -> Void
    let updateWideChannelPosts: (Bool) -> Void
    let openStickerSize: () -> Void
    let updateDoubleTapToEdit: (Bool) -> Void
    let updateQuickTranslateButton: (Bool) -> Void
    let updateSaveToCloudMenu: (Bool) -> Void
    let updateSelectFromAuthor: (Bool) -> Void
    let updateDownloadSpeedBoost: (Bool) -> Void
    let openOutgoingPhotoQuality: () -> Void

    init(
        updateGhostModeMaster: @escaping (Bool) -> Void,
        updateGhostDontReadMessages: @escaping (Bool) -> Void,
        updateGhostDontReadStories: @escaping (Bool) -> Void,
        updateGhostDontSendOnline: @escaping (Bool) -> Void,
        updateGhostDontSendTyping: @escaping (Bool) -> Void,
        updateGhostGoOfflineAutomatically: @escaping (Bool) -> Void,
        updateGhostReadOnInteract: @escaping (Bool) -> Void,
        updateGhostAlertBeforeOpeningStory: @escaping (Bool) -> Void,
        updateInstantPasscode: @escaping (Bool) -> Void,
        updateStreamerMode: @escaping (Bool) -> Void,
        updateHideMentions: @escaping (Bool) -> Void,
        updateHidePinned: @escaping (Bool) -> Void,
        updateSessionBackup: @escaping (Bool) -> Void,
        updateCompactChatList: @escaping (Bool) -> Void,
        updateCompactMessagePreview: @escaping (Bool) -> Void,
        updateCompactFolderNames: @escaping (Bool) -> Void,
        updateHideReactionsBar: @escaping (Bool) -> Void,
        updateShowDC: @escaping (Bool) -> Void,
        updateShowProfileId: @escaping (Bool) -> Void,
        openAccentSaturation: @escaping () -> Void,
        updateConfirmBeforeCall: @escaping (Bool) -> Void,
        updateSendWithReturnKey: @escaping (Bool) -> Void,
        updateForceBuiltInMic: @escaping (Bool) -> Void,
        openTranslationBackend: @escaping () -> Void,
        openTranscriptionBackend: @escaping () -> Void,
        updateScrollToNextChatDisabled: @escaping (Bool) -> Void,
        updateSaveDeletedMessages: @escaping (Bool) -> Void,
        updateSaveMessagesHistory: @escaping (Bool) -> Void,
        updateSaveMedia: @escaping (Bool) -> Void,
        updateSaveForBots: @escaping (Bool) -> Void,
        updateAyuForward: @escaping (Bool) -> Void,
        updateBypassDownloadRestrictions: @escaping (Bool) -> Void,
        updateProactiveSaveMedia: @escaping (Bool) -> Void,
        updateDeletedMessageMark: @escaping (String) -> Void,
        updateEditedMessageMark: @escaping (String) -> Void,
        updateLocalPremium: @escaping (Bool) -> Void,
        updateAutoFetchMtProxy: @escaping (Bool) -> Void,
        updateHideAds: @escaping (Bool) -> Void,
        updateHideBlockedMessages: @escaping (Bool) -> Void,
        updateGhostScheduleMessages: @escaping (Bool) -> Void,
        updateAllowSecretScreenshots: @escaping (Bool) -> Void,
        updateExpireTtlButton: @escaping (Bool) -> Void,
        updateKeepBannedChats: @escaping (Bool) -> Void,
        updateRegexFiltersEnabled: @escaping (Bool) -> Void,
        updateRegexFiltersCaseInsensitive: @escaping (Bool) -> Void,
        updateRegexFilterPatternsText: @escaping (String) -> Void,
        exportMessageSavingDatabase: @escaping () -> Void,
        importMessageSavingDatabase: @escaping () -> Void,
        openCategory: @escaping (ForkExtrasControllerFocus) -> Void,
        updateHideAllChats: @escaping (Bool) -> Void,
        updateRememberLastFolder: @escaping (Bool) -> Void,
        updateHideTabBar: @escaping (Bool) -> Void,
        updateShowMessageSeconds: @escaping (Bool) -> Void,
        updateWideChannelPosts: @escaping (Bool) -> Void,
        openStickerSize: @escaping () -> Void,
        updateDoubleTapToEdit: @escaping (Bool) -> Void,
        updateQuickTranslateButton: @escaping (Bool) -> Void,
        updateSaveToCloudMenu: @escaping (Bool) -> Void,
        updateSelectFromAuthor: @escaping (Bool) -> Void,
        updateDownloadSpeedBoost: @escaping (Bool) -> Void,
        openOutgoingPhotoQuality: @escaping () -> Void
    ) {
        self.updateGhostModeMaster = updateGhostModeMaster
        self.updateGhostDontReadMessages = updateGhostDontReadMessages
        self.updateGhostDontReadStories = updateGhostDontReadStories
        self.updateGhostDontSendOnline = updateGhostDontSendOnline
        self.updateGhostDontSendTyping = updateGhostDontSendTyping
        self.updateGhostGoOfflineAutomatically = updateGhostGoOfflineAutomatically
        self.updateGhostReadOnInteract = updateGhostReadOnInteract
        self.updateGhostAlertBeforeOpeningStory = updateGhostAlertBeforeOpeningStory
        self.updateInstantPasscode = updateInstantPasscode
        self.updateStreamerMode = updateStreamerMode
        self.updateHideMentions = updateHideMentions
        self.updateHidePinned = updateHidePinned
        self.updateSessionBackup = updateSessionBackup
        self.updateCompactChatList = updateCompactChatList
        self.updateCompactMessagePreview = updateCompactMessagePreview
        self.updateCompactFolderNames = updateCompactFolderNames
        self.updateHideReactionsBar = updateHideReactionsBar
        self.updateShowDC = updateShowDC
        self.updateShowProfileId = updateShowProfileId
        self.openAccentSaturation = openAccentSaturation
        self.updateConfirmBeforeCall = updateConfirmBeforeCall
        self.updateSendWithReturnKey = updateSendWithReturnKey
        self.updateForceBuiltInMic = updateForceBuiltInMic
        self.openTranslationBackend = openTranslationBackend
        self.openTranscriptionBackend = openTranscriptionBackend
        self.updateScrollToNextChatDisabled = updateScrollToNextChatDisabled
        self.updateSaveDeletedMessages = updateSaveDeletedMessages
        self.updateSaveMessagesHistory = updateSaveMessagesHistory
        self.updateSaveMedia = updateSaveMedia
        self.updateSaveForBots = updateSaveForBots
        self.updateAyuForward = updateAyuForward
        self.updateBypassDownloadRestrictions = updateBypassDownloadRestrictions
        self.updateProactiveSaveMedia = updateProactiveSaveMedia
        self.updateDeletedMessageMark = updateDeletedMessageMark
        self.updateEditedMessageMark = updateEditedMessageMark
        self.updateLocalPremium = updateLocalPremium
        self.updateAutoFetchMtProxy = updateAutoFetchMtProxy
        self.updateHideAds = updateHideAds
        self.updateHideBlockedMessages = updateHideBlockedMessages
        self.updateGhostScheduleMessages = updateGhostScheduleMessages
        self.updateAllowSecretScreenshots = updateAllowSecretScreenshots
        self.updateExpireTtlButton = updateExpireTtlButton
        self.updateKeepBannedChats = updateKeepBannedChats
        self.updateRegexFiltersEnabled = updateRegexFiltersEnabled
        self.updateRegexFiltersCaseInsensitive = updateRegexFiltersCaseInsensitive
        self.updateRegexFilterPatternsText = updateRegexFilterPatternsText
        self.exportMessageSavingDatabase = exportMessageSavingDatabase
        self.importMessageSavingDatabase = importMessageSavingDatabase
        self.openCategory = openCategory
        self.updateHideAllChats = updateHideAllChats
        self.updateRememberLastFolder = updateRememberLastFolder
        self.updateHideTabBar = updateHideTabBar
        self.updateShowMessageSeconds = updateShowMessageSeconds
        self.updateWideChannelPosts = updateWideChannelPosts
        self.openStickerSize = openStickerSize
        self.updateDoubleTapToEdit = updateDoubleTapToEdit
        self.updateQuickTranslateButton = updateQuickTranslateButton
        self.updateSaveToCloudMenu = updateSaveToCloudMenu
        self.updateSelectFromAuthor = updateSelectFromAuthor
        self.updateDownloadSpeedBoost = updateDownloadSpeedBoost
        self.openOutgoingPhotoQuality = openOutgoingPhotoQuality
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
}

private enum ForkExtrasEntry: ItemListNodeEntry {
    case hubNinja
    case hubGhost
    case hubPrivacy
    case hubInterface
    case hubChat
    case hubNetwork
    case hubFooter
    case ghostModeMaster(Bool)
    case ghostDontReadMessages(Bool)
    case ghostDontReadStories(Bool)
    case ghostDontSendOnline(Bool)
    case ghostDontSendTyping(Bool)
    case ghostGoOfflineAutomatically(Bool)
    case ghostGoOfflineAutomaticallyFooter
    case ghostReadOnInteract(Bool)
    case ghostReadOnInteractFooter
    case ghostAlertBeforeOpeningStory(Bool)
    case ghostAlertBeforeOpeningStoryFooter
    case ghostScheduleMessages(Bool)
    case ghostScheduleMessagesFooter
    case ghostModeFooter
    case streamerMode(Bool)
    case streamerModeFooter
    case instantPasscode(Bool)
    case instantPasscodeFooter
    case hideMentions(Bool)
    case hideMentionsFooter
    case hidePinned(Bool)
    case hidePinnedFooter
    case sessionBackup(Bool)
    case sessionBackupFooter
    case compactChatList(Bool)
    case compactMessagePreview(Bool)
    case compactFolderNames(Bool)
    case uiDensityFooter
    case hideReactionsBar(Bool)
    case showDC(Bool)
    case showProfileId(Bool)
    case accentSaturation(Int32)
    case privacyFooter
    case confirmBeforeCall(Bool)
    case sendWithReturnKey(Bool)
    case sendWithReturnKeyFooter
    case forceBuiltInMic(Bool)
    case callsFooter
    case translationBackend(ForkTranslationBackend)
    case transcriptionBackend(ForkTranscriptionBackend)
    case translationFooter
    case scrollToNextChat(Bool)
    case scrollToNextChatFooter
    case saveDeletedMessages(Bool)
    case saveDeletedMessagesFooter
    case saveMessagesHistory(Bool)
    case saveMessagesHistoryFooter
    case saveMedia(Bool)
    case saveMediaFooter
    case saveForBots(Bool)
    case ayuForward(Bool)
    case ayuForwardFooter
    case bypassDownloadRestrictions(Bool)
    case bypassDownloadRestrictionsFooter
    case proactiveSaveMedia(Bool)
    case proactiveSaveMediaFooter
    case deletedMessageMark(String)
    case deletedMessageMarkFooter
    case editedMessageMark(String)
    case editedMessageMarkFooter
    case exportMessageSavingDatabase
    case importMessageSavingDatabase
    case messageSavingDbFooter
    case localPremium(Bool)
    case localPremiumFooter
    case autoFetchMtProxy(Bool)
    case autoFetchMtProxyFooter
    case hideAds(Bool)
    case hideAdsFooter
    case hideBlockedMessages(Bool)
    case hideBlockedMessagesFooter
    case allowSecretScreenshots(Bool)
    case allowSecretScreenshotsFooter
    case expireTtlButton(Bool)
    case expireTtlButtonFooter
    case keepBannedChats(Bool)
    case keepBannedChatsFooter
    case regexFilters(Bool)
    case regexFiltersCaseInsensitive(Bool)
    case regexFiltersPatterns(String)
    case regexFiltersFooter
    case hideAllChats(Bool)
    case hideAllChatsFooter
    case rememberLastFolder(Bool)
    case rememberLastFolderFooter
    case hideTabBar(Bool)
    case hideTabBarFooter
    case showMessageSeconds(Bool)
    case showMessageSecondsFooter
    case wideChannelPosts(Bool)
    case wideChannelPostsFooter
    case stickerSize(Int32)
    case doubleTapToEdit(Bool)
    case doubleTapToEditFooter
    case quickTranslate(Bool)
    case quickTranslateFooter
    case saveToCloud(Bool)
    case saveToCloudFooter
    case selectFromAuthor(Bool)
    case selectFromAuthorFooter
    case downloadSpeedBoost(Bool)
    case downloadSpeedBoostFooter
    case outgoingPhotoQuality(Int32)
    case outgoingPhotoQualityFooter

    var section: ItemListSectionId {
        switch self {
        case .hubNinja, .hubGhost, .hubPrivacy, .hubInterface, .hubChat, .hubNetwork, .hubFooter:
            return ForkExtrasSection.hub.rawValue
        case .ghostModeMaster, .ghostDontReadMessages, .ghostDontReadStories, .ghostDontSendOnline, .ghostDontSendTyping, .ghostGoOfflineAutomatically, .ghostGoOfflineAutomaticallyFooter, .ghostReadOnInteract, .ghostReadOnInteractFooter, .ghostAlertBeforeOpeningStory, .ghostAlertBeforeOpeningStoryFooter, .ghostScheduleMessages, .ghostScheduleMessagesFooter, .ghostModeFooter:
            return ForkExtrasSection.ghost.rawValue
        case .streamerMode, .streamerModeFooter, .instantPasscode, .instantPasscodeFooter:
            return ForkExtrasSection.lock.rawValue
        case .hideMentions, .hideMentionsFooter, .hidePinned, .hidePinnedFooter:
            return ForkExtrasSection.notifications.rawValue
        case .sessionBackup, .sessionBackupFooter:
            return ForkExtrasSection.backup.rawValue
        case .compactChatList, .compactMessagePreview, .compactFolderNames, .uiDensityFooter:
            return ForkExtrasSection.uiDensity.rawValue
        case .hideReactionsBar, .showDC, .showProfileId, .accentSaturation, .privacyFooter:
            return ForkExtrasSection.privacy.rawValue
        case .confirmBeforeCall, .sendWithReturnKey, .sendWithReturnKeyFooter, .forceBuiltInMic, .callsFooter:
            return ForkExtrasSection.calls.rawValue
        case .translationBackend, .transcriptionBackend, .translationFooter:
            return ForkExtrasSection.translation.rawValue
        case .scrollToNextChat, .scrollToNextChatFooter:
            return ForkExtrasSection.navigation.rawValue
        case .saveDeletedMessages, .saveDeletedMessagesFooter, .saveMessagesHistory, .saveMessagesHistoryFooter, .saveMedia, .saveMediaFooter, .proactiveSaveMedia, .proactiveSaveMediaFooter, .deletedMessageMark, .deletedMessageMarkFooter, .editedMessageMark, .editedMessageMarkFooter, .exportMessageSavingDatabase, .importMessageSavingDatabase, .messageSavingDbFooter, .saveForBots, .ayuForward, .ayuForwardFooter, .bypassDownloadRestrictions, .bypassDownloadRestrictionsFooter:
            return ForkExtrasSection.messageSaving.rawValue
        case .hideAds, .hideAdsFooter, .hideBlockedMessages, .hideBlockedMessagesFooter, .regexFilters, .regexFiltersCaseInsensitive, .regexFiltersPatterns, .regexFiltersFooter:
            return ForkExtrasSection.messageFilters.rawValue
        case .allowSecretScreenshots, .allowSecretScreenshotsFooter, .expireTtlButton, .expireTtlButtonFooter, .keepBannedChats, .keepBannedChatsFooter:
            return ForkExtrasSection.smallThings.rawValue
        case .localPremium, .localPremiumFooter:
            return ForkExtrasSection.premium.rawValue
        case .autoFetchMtProxy, .autoFetchMtProxyFooter:
            return ForkExtrasSection.proxy.rawValue
        case .hideAllChats, .hideAllChatsFooter, .rememberLastFolder, .rememberLastFolderFooter, .hideTabBar, .hideTabBarFooter:
            return ForkExtrasSection.folders.rawValue
        case .showMessageSeconds, .showMessageSecondsFooter, .wideChannelPosts, .wideChannelPostsFooter, .stickerSize:
            return ForkExtrasSection.appearance.rawValue
        case .doubleTapToEdit, .doubleTapToEditFooter, .quickTranslate, .quickTranslateFooter, .saveToCloud, .saveToCloudFooter, .selectFromAuthor, .selectFromAuthorFooter, .outgoingPhotoQuality, .outgoingPhotoQualityFooter:
            return ForkExtrasSection.chatExtras.rawValue
        case .downloadSpeedBoost, .downloadSpeedBoostFooter:
            return ForkExtrasSection.downloads.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .hubNinja: return 0
        case .hubGhost: return 1
        case .hubPrivacy: return 2
        case .hubInterface: return 3
        case .hubChat: return 4
        case .hubNetwork: return 5
        case .hubFooter: return 6
        case .ghostModeMaster: return 9
        case .ghostDontReadMessages: return 10
        case .ghostDontReadStories: return 11
        case .ghostDontSendOnline: return 12
        case .ghostDontSendTyping: return 13
        case .ghostGoOfflineAutomatically: return 14
        case .ghostGoOfflineAutomaticallyFooter: return 15
        case .ghostReadOnInteract: return 16
        case .ghostReadOnInteractFooter: return 17
        case .ghostAlertBeforeOpeningStory: return 18
        case .ghostAlertBeforeOpeningStoryFooter: return 19
        case .ghostScheduleMessages: return 20
        case .ghostScheduleMessagesFooter: return 21
        case .ghostModeFooter: return 22
        case .streamerMode: return 28
        case .streamerModeFooter: return 29
        case .instantPasscode: return 30
        case .instantPasscodeFooter: return 31
        case .hideMentions: return 32
        case .hideMentionsFooter: return 33
        case .hidePinned: return 34
        case .hidePinnedFooter: return 35
        case .sessionBackup: return 36
        case .sessionBackupFooter: return 37
        case .allowSecretScreenshots: return 38
        case .allowSecretScreenshotsFooter: return 39
        case .expireTtlButton: return 40
        case .expireTtlButtonFooter: return 41
        case .keepBannedChats: return 42
        case .keepBannedChatsFooter: return 43
        case .compactChatList: return 50
        case .compactMessagePreview: return 51
        case .compactFolderNames: return 52
        case .uiDensityFooter: return 53
        case .hideReactionsBar: return 54
        case .showDC: return 55
        case .showProfileId: return 56
        case .accentSaturation: return 57
        case .privacyFooter: return 58
        case .hideAllChats: return 59
        case .hideAllChatsFooter: return 60
        case .rememberLastFolder: return 61
        case .rememberLastFolderFooter: return 62
        case .hideTabBar: return 63
        case .hideTabBarFooter: return 64
        case .showMessageSeconds: return 65
        case .showMessageSecondsFooter: return 66
        case .wideChannelPosts: return 67
        case .wideChannelPostsFooter: return 68
        case .stickerSize: return 69
        case .confirmBeforeCall: return 80
        case .sendWithReturnKey: return 81
        case .sendWithReturnKeyFooter: return 82
        case .forceBuiltInMic: return 83
        case .callsFooter: return 84
        case .translationBackend: return 85
        case .transcriptionBackend: return 86
        case .translationFooter: return 87
        case .scrollToNextChat: return 88
        case .scrollToNextChatFooter: return 89
        case .doubleTapToEdit: return 90
        case .doubleTapToEditFooter: return 91
        case .quickTranslate: return 92
        case .quickTranslateFooter: return 93
        case .saveToCloud: return 94
        case .saveToCloudFooter: return 95
        case .selectFromAuthor: return 96
        case .selectFromAuthorFooter: return 97
        case .outgoingPhotoQuality: return 98
        case .outgoingPhotoQualityFooter: return 99
        case .saveDeletedMessages: return 110
        case .saveDeletedMessagesFooter: return 111
        case .saveMessagesHistory: return 112
        case .saveMessagesHistoryFooter: return 113
        case .saveMedia: return 114
        case .saveMediaFooter: return 115
        case .saveForBots: return 116
        case .ayuForward: return 117
        case .ayuForwardFooter: return 118
        case .bypassDownloadRestrictions: return 119
        case .bypassDownloadRestrictionsFooter: return 120
        case .proactiveSaveMedia: return 121
        case .proactiveSaveMediaFooter: return 122
        case .deletedMessageMark: return 123
        case .deletedMessageMarkFooter: return 124
        case .editedMessageMark: return 125
        case .editedMessageMarkFooter: return 126
        case .exportMessageSavingDatabase: return 127
        case .importMessageSavingDatabase: return 128
        case .messageSavingDbFooter: return 129
        case .hideAds: return 130
        case .hideAdsFooter: return 131
        case .hideBlockedMessages: return 132
        case .hideBlockedMessagesFooter: return 133
        case .regexFilters: return 134
        case .regexFiltersCaseInsensitive: return 135
        case .regexFiltersPatterns: return 136
        case .regexFiltersFooter: return 137
        case .localPremium: return 140
        case .localPremiumFooter: return 141
        case .autoFetchMtProxy: return 142
        case .autoFetchMtProxyFooter: return 143
        case .downloadSpeedBoost: return 144
        case .downloadSpeedBoostFooter: return 145
        }
    }

    static func <(lhs: ForkExtrasEntry, rhs: ForkExtrasEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkExtrasControllerArguments
        switch self {
        case .hubNinja:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.savedMessages, title: ForkExtrasLocalizedString.hubNinja, label: ForkExtrasLocalizedString.hubNinjaLabel, sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.ninja)
            })
        case .hubGhost:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.stories, title: ForkExtrasLocalizedString.hubGhost, label: ForkExtrasLocalizedString.hubGhostLabel, sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.ghost)
            })
        case .hubPrivacy:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.security, title: ForkExtrasLocalizedString.hubPrivacy, label: ForkExtrasLocalizedString.hubPrivacyLabel, sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.privacy)
            })
        case .hubInterface:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: ForkExtrasLocalizedString.hubInterface, label: ForkExtrasLocalizedString.hubInterfaceLabel, sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.interface)
            })
        case .hubChat:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.privateChats, title: ForkExtrasLocalizedString.hubChat, label: ForkExtrasLocalizedString.hubChatLabel, sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.chat)
            })
        case .hubNetwork:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.proxy, title: ForkExtrasLocalizedString.hubNetwork, label: ForkExtrasLocalizedString.hubNetworkLabel, sectionId: self.section, style: .blocks, action: {
                arguments.openCategory(.network)
            })
        case .hubFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hubFooter), sectionId: self.section)
        case let .ghostModeMaster(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostModeMaster, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostModeMaster(value)
            })
        case let .ghostDontReadMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontReadMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontReadMessages(value)
            })
        case let .ghostDontReadStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontReadStories, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontReadStories(value)
            })
        case let .ghostDontSendOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontSendOnline, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontSendOnline(value)
            })
        case let .ghostDontSendTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostDontSendTyping, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostDontSendTyping(value)
            })
        case let .ghostGoOfflineAutomatically(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostGoOfflineAutomatically, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostGoOfflineAutomatically(value)
            })
        case .ghostGoOfflineAutomaticallyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostGoOfflineAutomaticallyFooter), sectionId: self.section)
        case let .ghostReadOnInteract(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostReadOnInteract, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostReadOnInteract(value)
            })
        case .ghostReadOnInteractFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostReadOnInteractFooter), sectionId: self.section)
        case let .ghostAlertBeforeOpeningStory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostAlertBeforeOpeningStory, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostAlertBeforeOpeningStory(value)
            })
        case .ghostAlertBeforeOpeningStoryFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostAlertBeforeOpeningStoryFooter), sectionId: self.section)
        case let .ghostScheduleMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ghostScheduleMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostScheduleMessages(value)
            })
        case .ghostScheduleMessagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostScheduleMessagesFooter), sectionId: self.section)
        case .ghostModeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ghostModeFooter), sectionId: self.section)
        case let .streamerMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.streamerMode, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateStreamerMode(value)
            })
        case .streamerModeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.streamerModeFooter), sectionId: self.section)
        case let .instantPasscode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.instantPasscode, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateInstantPasscode(value)
            })
        case .instantPasscodeFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.instantPasscodeFooter), sectionId: self.section)
        case let .hideMentions(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideMentions, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideMentions(value)
            })
        case .hideMentionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideMentionsFooter), sectionId: self.section)
        case let .hidePinned(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hidePinned, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHidePinned(value)
            })
        case .hidePinnedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hidePinnedFooter), sectionId: self.section)
        case let .sessionBackup(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.sessionBackup, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSessionBackup(value)
            })
        case .sessionBackupFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.sessionBackupFooter), sectionId: self.section)
        case let .compactChatList(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.compactChatList, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactChatList(value)
            })
        case let .compactMessagePreview(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.compactMessagePreview, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactMessagePreview(value)
            })
        case let .compactFolderNames(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.compactFolderNames, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactFolderNames(value)
            })
        case .uiDensityFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.uiDensityFooter), sectionId: self.section)
        case let .hideReactionsBar(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideReactionsBar, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideReactionsBar(value)
            })
        case let .showDC(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.showDC, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowDC(value)
            })
        case let .showProfileId(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.showProfileId, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowProfileId(value)
            })
        case let .accentSaturation(percent):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.accentSaturation, label: "\(percent)%", sectionId: self.section, style: .blocks, action: {
                arguments.openAccentSaturation()
            })
        case .privacyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.privacyFooter), sectionId: self.section)
        case let .confirmBeforeCall(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.confirmBeforeCall, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateConfirmBeforeCall(value)
            })
        case let .sendWithReturnKey(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.sendWithReturnKey, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSendWithReturnKey(value)
            })
        case .sendWithReturnKeyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.sendWithReturnKeyFooter), sectionId: self.section)
        case let .forceBuiltInMic(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.forceBuiltInMic, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateForceBuiltInMic(value)
            })
        case .callsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.forceBuiltInMicFooter + "\n\n" + ForkExtrasLocalizedString.callsFooter), sectionId: self.section)
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
            })
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
            })
        case .translationFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.translationFooter), sectionId: self.section)
        case let .scrollToNextChat(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.scrollToNextChat, value: !value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateScrollToNextChatDisabled(!value)
            })
        case .scrollToNextChatFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.scrollToNextChatFooter), sectionId: self.section)
        case let .saveDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveDeletedMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveDeletedMessages(value)
            })
        case .saveDeletedMessagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveDeletedMessagesFooter), sectionId: self.section)
        case let .saveMessagesHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveMessagesHistory, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveMessagesHistory(value)
            })
        case .saveMessagesHistoryFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveMessagesHistoryFooter), sectionId: self.section)
        case let .saveMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveMedia, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveMedia(value)
            })
        case .saveMediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveMediaFooter), sectionId: self.section)
        case let .saveForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveForBots, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveForBots(value)
            })
        case let .ayuForward(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.ayuForward, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAyuForward(value)
            })
        case .ayuForwardFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.ayuForwardFooter), sectionId: self.section)
        case let .bypassDownloadRestrictions(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.bypassDownloadRestrictions, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateBypassDownloadRestrictions(value)
            })
        case .bypassDownloadRestrictionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.bypassDownloadRestrictionsFooter), sectionId: self.section)
        case let .proactiveSaveMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.proactiveSaveMedia, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateProactiveSaveMedia(value)
            })
        case .proactiveSaveMediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.proactiveSaveMediaFooter), sectionId: self.section)
        case let .deletedMessageMark(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ForkExtrasLocalizedString.deletedMessageMark), text: value, placeholder: "🧹", type: .regular(capitalization: false, autocorrection: false), clearType: .always, maxLength: 8, sectionId: self.section, textUpdated: { value in
                arguments.updateDeletedMessageMark(value)
            }, action: {})
        case .deletedMessageMarkFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.deletedMessageMarkFooter), sectionId: self.section)
        case let .editedMessageMark(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ForkExtrasLocalizedString.editedMessageMark), text: value, placeholder: "", type: .regular(capitalization: false, autocorrection: false), clearType: .always, maxLength: 8, sectionId: self.section, textUpdated: { value in
                arguments.updateEditedMessageMark(value)
            }, action: {})
        case .editedMessageMarkFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.editedMessageMarkFooter), sectionId: self.section)
        case .exportMessageSavingDatabase:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.exportMessageSaving, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportMessageSavingDatabase()
            })
        case .importMessageSavingDatabase:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.importMessageSaving, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importMessageSavingDatabase()
            })
        case .messageSavingDbFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.messageSavingDbFooter), sectionId: self.section)
        case let .localPremium(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.localPremium, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateLocalPremium(value)
            })
        case .localPremiumFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.localPremiumFooter), sectionId: self.section)
        case let .autoFetchMtProxy(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.autoFetchMtProxy, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAutoFetchMtProxy(value)
            })
        case .autoFetchMtProxyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.autoFetchMtProxyFooter), sectionId: self.section)
        case let .hideAds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideAds, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideAds(value)
            })
        case .hideAdsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideAdsFooter), sectionId: self.section)
        case let .hideBlockedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideBlockedMessages, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideBlockedMessages(value)
            })
        case .hideBlockedMessagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideBlockedMessagesFooter), sectionId: self.section)
        case let .allowSecretScreenshots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.allowSecretScreenshots, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAllowSecretScreenshots(value)
            })
        case .allowSecretScreenshotsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.allowSecretScreenshotsFooter), sectionId: self.section)
        case let .expireTtlButton(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.expireTtlButton, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateExpireTtlButton(value)
            })
        case .expireTtlButtonFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.expireTtlButtonFooter), sectionId: self.section)
        case let .keepBannedChats(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.keepBannedChats, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepBannedChats(value)
            })
        case .keepBannedChatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.keepBannedChatsFooter), sectionId: self.section)
        case let .regexFilters(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.regexFilters, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRegexFiltersEnabled(value)
            })
        case let .regexFiltersCaseInsensitive(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.regexFiltersCaseInsensitive, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRegexFiltersCaseInsensitive(value)
            })
        case let .regexFiltersPatterns(value):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: value, placeholder: ForkExtrasLocalizedString.regexFiltersPatterns, maxLength: ItemListMultilineInputItemTextLimit(value: 4000, display: false), sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, textUpdated: { value in
                arguments.updateRegexFilterPatternsText(value)
            })
        case .regexFiltersFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.regexFiltersFooter), sectionId: self.section)
        case let .hideAllChats(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideAllChats, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideAllChats(value)
            })
        case .hideAllChatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideAllChatsFooter), sectionId: self.section)
        case let .rememberLastFolder(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.rememberLastFolder, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRememberLastFolder(value)
            })
        case .rememberLastFolderFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.rememberLastFolderFooter), sectionId: self.section)
        case let .hideTabBar(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.hideTabBar, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideTabBar(value)
            })
        case .hideTabBarFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.hideTabBarFooter), sectionId: self.section)
        case let .showMessageSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.showMessageSeconds, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowMessageSeconds(value)
            })
        case .showMessageSecondsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.showMessageSecondsFooter), sectionId: self.section)
        case let .wideChannelPosts(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.wideChannelPosts, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateWideChannelPosts(value)
            })
        case .wideChannelPostsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.wideChannelPostsFooter), sectionId: self.section)
        case let .stickerSize(percent):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.stickerSize, label: "\(percent)%", sectionId: self.section, style: .blocks, action: {
                arguments.openStickerSize()
            })
        case let .doubleTapToEdit(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.doubleTapToEdit, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateDoubleTapToEdit(value)
            })
        case .doubleTapToEditFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.doubleTapToEditFooter), sectionId: self.section)
        case let .quickTranslate(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.quickTranslate, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateQuickTranslateButton(value)
            })
        case .quickTranslateFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.quickTranslateFooter), sectionId: self.section)
        case let .saveToCloud(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.saveToCloud, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveToCloudMenu(value)
            })
        case .saveToCloudFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.saveToCloudFooter), sectionId: self.section)
        case let .selectFromAuthor(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.selectFromAuthor, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSelectFromAuthor(value)
            })
        case .selectFromAuthorFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.selectFromAuthorFooter), sectionId: self.section)
        case let .downloadSpeedBoost(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.downloadSpeedBoost, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateDownloadSpeedBoost(value)
            })
        case .downloadSpeedBoostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.downloadSpeedBoostFooter), sectionId: self.section)
        case let .outgoingPhotoQuality(value):
            let label: String
            switch value {
            case 2:
                label = ForkExtrasLocalizedString.outgoingPhotoQualityMax
            case 1:
                label = ForkExtrasLocalizedString.outgoingPhotoQualityBetter
            default:
                label = ForkExtrasLocalizedString.outgoingPhotoQualityDefault
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ForkExtrasLocalizedString.outgoingPhotoQuality, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openOutgoingPhotoQuality()
            })
        case .outgoingPhotoQualityFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkExtrasLocalizedString.outgoingPhotoQualityFooter), sectionId: self.section)
        }
    }
}

private func forkExtrasControllerEntries(settings: ForkExtrasSettings, autoFetchPublicMtProxy: Bool, focus: ForkExtrasControllerFocus) -> [ForkExtrasEntry] {
    let category = focus.resolvedCategory
    if category == .top {
        return [
            .hubNinja,
            .hubGhost,
            .hubPrivacy,
            .hubInterface,
            .hubChat,
            .hubNetwork,
            .hubFooter,
        ]
    }

    var entries: [ForkExtrasEntry] = []
    switch category {
    case .ghost:
        entries = [
            .ghostModeMaster(settings.isFullGhostMode),
            .ghostDontReadMessages(settings.ghostDontReadMessages),
            .ghostDontReadStories(settings.ghostDontReadStories),
            .ghostDontSendOnline(settings.ghostDontSendOnline),
            .ghostDontSendTyping(settings.ghostDontSendTyping),
            .ghostGoOfflineAutomatically(settings.ghostGoOfflineAutomatically),
            .ghostGoOfflineAutomaticallyFooter,
            .ghostReadOnInteract(settings.ghostReadOnInteract),
            .ghostReadOnInteractFooter,
            .ghostAlertBeforeOpeningStory(settings.ghostAlertBeforeOpeningStory),
            .ghostAlertBeforeOpeningStoryFooter,
            .ghostScheduleMessages(settings.ghostScheduleMessages),
            .ghostScheduleMessagesFooter,
            .ghostModeFooter,
        ]
    case .privacy:
        entries = [
            .streamerMode(settings.streamerMode),
            .streamerModeFooter,
            .instantPasscode(settings.instantPasscodeLock),
            .instantPasscodeFooter,
            .hideMentions(settings.hideMentionNotifications),
            .hideMentionsFooter,
            .hidePinned(settings.hidePinnedNotifications),
            .hidePinnedFooter,
            .sessionBackup(settings.sessionKeychainBackup),
            .sessionBackupFooter,
            .allowSecretScreenshots(settings.allowSecretScreenshots),
            .allowSecretScreenshotsFooter,
            .expireTtlButton(settings.expireTtlButton),
            .expireTtlButtonFooter,
            .keepBannedChats(settings.keepBannedChats),
            .keepBannedChatsFooter,
        ]
    case .interface:
        entries = [
            .compactChatList(settings.compactChatList),
            .compactMessagePreview(settings.compactMessagePreview),
            .compactFolderNames(settings.compactFolderNames),
            .uiDensityFooter,
            .hideReactionsBar(settings.hideReactionsBar),
            .showDC(settings.showDC),
            .showProfileId(settings.showProfileId),
            .accentSaturation(settings.accentColorSaturation),
            .privacyFooter,
            .hideAllChats(settings.hideAllChats),
            .hideAllChatsFooter,
            .rememberLastFolder(settings.rememberLastFolder),
            .rememberLastFolderFooter,
        ]
        if UIDevice.current.userInterfaceIdiom != .pad {
            entries.append(.hideTabBar(settings.hideTabBar))
            entries.append(.hideTabBarFooter)
        }
        entries.append(contentsOf: [
            .showMessageSeconds(settings.showMessageSeconds),
            .showMessageSecondsFooter,
            .wideChannelPosts(settings.wideChannelPosts),
            .wideChannelPostsFooter,
            .stickerSize(settings.stickerSizePercent),
        ])
    case .chat:
        entries = [
            .confirmBeforeCall(settings.confirmBeforeCall),
            .sendWithReturnKey(settings.sendWithReturnKey),
            .sendWithReturnKeyFooter,
            .forceBuiltInMic(settings.forceBuiltInMic),
            .callsFooter,
            .translationBackend(settings.translationBackend),
            .transcriptionBackend(settings.transcriptionBackend),
            .translationFooter,
            .scrollToNextChat(settings.scrollToNextChatDisabled),
            .scrollToNextChatFooter,
            .doubleTapToEdit(settings.doubleTapToEdit),
            .doubleTapToEditFooter,
            .quickTranslate(settings.quickTranslateButton),
            .quickTranslateFooter,
            .saveToCloud(settings.saveToCloudMenu),
            .saveToCloudFooter,
            .selectFromAuthor(settings.selectFromAuthor),
            .selectFromAuthorFooter,
            .outgoingPhotoQuality(settings.outgoingPhotoQuality),
            .outgoingPhotoQualityFooter,
        ]
    case .ninja, .messageSaving, .messageFilters:
        entries = [
            .saveDeletedMessages(settings.saveDeletedMessages),
            .saveDeletedMessagesFooter,
            .saveMessagesHistory(settings.saveMessagesHistory),
            .saveMessagesHistoryFooter,
            .saveMedia(settings.saveMedia),
            .saveMediaFooter,
            .saveForBots(settings.saveForBots),
            .ayuForward(settings.ayuForward),
            .ayuForwardFooter,
            .bypassDownloadRestrictions(settings.bypassDownloadRestrictions),
            .bypassDownloadRestrictionsFooter,
            .proactiveSaveMedia(settings.proactiveSaveMedia),
            .proactiveSaveMediaFooter,
            .deletedMessageMark(settings.deletedMessageMark),
            .deletedMessageMarkFooter,
            .editedMessageMark(settings.editedMessageMark),
            .editedMessageMarkFooter,
            .exportMessageSavingDatabase,
            .importMessageSavingDatabase,
            .messageSavingDbFooter,
            .hideAds(settings.hideAds),
            .hideAdsFooter,
            .hideBlockedMessages(settings.hideBlockedMessages),
            .hideBlockedMessagesFooter,
            .regexFilters(settings.regexMessageFiltersEnabled),
        ]
        if settings.regexMessageFiltersEnabled {
            entries.append(contentsOf: [
                .regexFiltersCaseInsensitive(settings.regexMessageFiltersCaseInsensitive),
                .regexFiltersPatterns(settings.regexMessageFilterPatterns.joined(separator: "\n")),
            ])
        }
        entries.append(.regexFiltersFooter)
    case .network:
        entries = [
            .localPremium(settings.localPremium),
            .localPremiumFooter,
            .autoFetchMtProxy(autoFetchPublicMtProxy),
            .autoFetchMtProxyFooter,
            .downloadSpeedBoost(settings.downloadSpeedBoost),
            .downloadSpeedBoostFooter,
        ]
    case .top:
        break
    }
    return entries
}

public enum ForkExtrasControllerFocus {
    case top
    case ninja
    case ghost
    case privacy
    case interface
    case chat
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
        case .ninja:
            return ForkExtrasLocalizedString.hubNinja
        case .ghost:
            return ForkExtrasLocalizedString.hubGhost
        case .privacy:
            return ForkExtrasLocalizedString.hubPrivacy
        case .interface:
            return ForkExtrasLocalizedString.hubInterface
        case .chat:
            return ForkExtrasLocalizedString.hubChat
        case .network:
            return ForkExtrasLocalizedString.hubNetwork
        default:
            return ForkExtrasLocalizedString.title
        }
    }
}

public func forkExtrasController(context: AccountContext, focus: ForkExtrasControllerFocus = .top) -> ViewController {
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
        updateGhostDontReadMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontReadMessages = value
                return updated
            }.start())
        },
        updateGhostDontReadStories: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontReadStories = value
                return updated
            }.start())
        },
        updateGhostDontSendOnline: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontSendOnline = value
                return updated
            }.start())
        },
        updateGhostDontSendTyping: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostDontSendTyping = value
                return updated
            }.start())
        },
        updateGhostGoOfflineAutomatically: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostGoOfflineAutomatically = value
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
        updateGhostAlertBeforeOpeningStory: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ghostAlertBeforeOpeningStory = value
                return updated
            }.start())
        },
        updateInstantPasscode: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.instantPasscodeLock = value
                return updated
            }.start())
        },
        updateStreamerMode: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.streamerMode = value
                return updated
            }.start())
        },
        updateHideMentions: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideMentionNotifications = value
                return updated
            }.start())
        },
        updateHidePinned: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hidePinnedNotifications = value
                return updated
            }.start())
        },
        updateSessionBackup: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.sessionKeychainBackup = value
                return updated
            }.start())
            if !value {
                SessionKeychainBackup.deleteAll()
            }
        },
        updateCompactChatList: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.compactChatList = value
                return updated
            }.start())
        },
        updateCompactMessagePreview: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.compactMessagePreview = value
                return updated
            }.start())
        },
        updateCompactFolderNames: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.compactFolderNames = value
                return updated
            }.start())
        },
        updateHideReactionsBar: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideReactionsBar = value
                return updated
            }.start())
        },
        updateShowDC: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.showDC = value
                return updated
            }.start())
        },
        updateShowProfileId: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.showProfileId = value
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
        updateConfirmBeforeCall: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.confirmBeforeCall = value
                return updated
            }.start())
        },
        updateSendWithReturnKey: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.sendWithReturnKey = value
                return updated
            }.start())
        },
        updateForceBuiltInMic: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.forceBuiltInMic = value
                return updated
            }.start())
        },
        openTranslationBackend: {
            presentPicker(title: ForkExtrasLocalizedString.translationBackend, options: [
                (ForkExtrasLocalizedString.backendDefault, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.translationBackend = .default
                        return updated
                    }.start())
                }),
                (ForkExtrasLocalizedString.backendSystem, {
                    updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                        var updated = current
                        updated.translationBackend = .system
                        return updated
                    }.start())
                })
            ])
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
        updateSaveDeletedMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveDeletedMessages = value
                return updated
            }.start())
        },
        updateSaveMessagesHistory: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveMessagesHistory = value
                return updated
            }.start())
        },
        updateSaveMedia: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveMedia = value
                return updated
            }.start())
        },
        updateSaveForBots: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveForBots = value
                return updated
            }.start())
        },
        updateAyuForward: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.ayuForward = value
                return updated
            }.start())
        },
        updateBypassDownloadRestrictions: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.bypassDownloadRestrictions = value
                return updated
            }.start())
        },
        updateProactiveSaveMedia: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.proactiveSaveMedia = value
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
        updateLocalPremium: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.localPremium = value
                return updated
            }.start())
        },
        updateAutoFetchMtProxy: { value in
            let _ = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var current = current
                current.setAutoFetchPublicMtProxy(value)
                if value {
                    current.autoRotateProxies = false
                }
                return current
            }).start()
        },
        updateHideAds: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideAds = value
                return updated
            }.start())
        },
        updateHideBlockedMessages: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideBlockedMessages = value
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
        updateAllowSecretScreenshots: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.allowSecretScreenshots = value
                return updated
            }.start())
        },
        updateExpireTtlButton: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.expireTtlButton = value
                return updated
            }.start())
        },
        updateKeepBannedChats: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.keepBannedChats = value
                return updated
            }.start())
        },
        updateRegexFiltersEnabled: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.regexMessageFiltersEnabled = value
                return updated
            }.start())
        },
        updateRegexFiltersCaseInsensitive: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.regexMessageFiltersCaseInsensitive = value
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
            MessageSavingStore.flush()
            guard let url = MessageSavingStore.exportBundle() else {
                return
            }
            // Folder URL: AirDrop / "Save to Files" accept it. Import the folder itself (not a
            // zip — the picker does not open archives).
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: url)
            }
            forkExtrasPresentNativeController(activity, context: context)
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
        openCategory: { category in
            pushControllerImpl?(forkExtrasController(context: context, focus: category))
        },
        updateHideAllChats: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideAllChats = value
                return updated
            }.start())
        },
        updateRememberLastFolder: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.rememberLastFolder = value
                return updated
            }.start())
        },
        updateHideTabBar: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.hideTabBar = value
                return updated
            }.start())
        },
        updateShowMessageSeconds: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.showMessageSeconds = value
                return updated
            }.start())
        },
        updateWideChannelPosts: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.wideChannelPosts = value
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
        updateDoubleTapToEdit: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.doubleTapToEdit = value
                return updated
            }.start())
        },
        updateQuickTranslateButton: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.quickTranslateButton = value
                return updated
            }.start())
        },
        updateSaveToCloudMenu: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.saveToCloudMenu = value
                return updated
            }.start())
        },
        updateSelectFromAuthor: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.selectFromAuthor = value
                return updated
            }.start())
        },
        updateDownloadSpeedBoost: { value in
            updateDisposable.set(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated.downloadSpeedBoost = value
                return updated
            }.start())
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
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: context.sharedContext.accountManager),
        context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let proxySettings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
        let entries = forkExtrasControllerEntries(settings: settings, autoFetchPublicMtProxy: proxySettings.autoFetchPublicMtProxy, focus: focus)
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
        if let focusedSection, let index = entries.firstIndex(where: { $0.section == focusedSection }) {
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
    presentControllerImpl = { [weak controller] presented in
        controller?.present(presented, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}
