"""Message Saving additions from Donutgram: Save My Deleted Messages, Save Messages from Notifications, Deleted Messages page."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
STORE = 'submodules/TelegramUIPreferences/Sources/MessageSavingStore.swift'
STAGING = 'submodules/TelegramUIPreferences/Sources/MessageSavingNotificationStaging.swift'
BRIDGE = 'submodules/TelegramCore/Sources/MessageSaving/MessageSavingBridge.swift'
DELETE = 'submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift'
SERVICE = 'Telegram/NotificationService/Sources/NotificationService.swift'
CONTEXT = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
HISTORY = 'submodules/SettingsUI/Sources/MessageSavingHistoryController.swift'

FIELDS = ['saveMyDeletedMessages', 'saveMessagesFromNotifications']


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def function(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n    }\n', start)]


class Settings(unittest.TestCase):
    def test_fields_round_trip_and_default_off(self):
        source = read(SETTINGS)
        for name in FIELDS:
            self.assertIn('    public var %s: Bool\n' % name, source)
            self.assertIn('        self.%s = false\n' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_extension_reads_the_switches_from_the_shared_defaults(self):
        source = read(SETTINGS)
        sync = function(source, 'public static func sync(_ settings: ForkExtrasSettings)')
        self.assertIn('syncMessageSaving(settings)', sync.split('guard shouldWrite')[0])
        saving = function(source, 'private static func syncMessageSaving(')
        for value in ['settings.saveDeletedMessages', 'settings.saveForBots', 'settings.saveMessagesFromNotifications']:
            self.assertIn(value, saving)
        self.assertIn('return bool(forKey: saveDeletedKey) && bool(forKey: saveFromNotificationsKey)', source)


class SaveMyDeletedMessages(unittest.TestCase):
    def test_store_projects_the_switch(self):
        self.assertIn('saveMyDeleted: settings.saveMyDeletedMessages', read(STORE))
        self.assertIn('public var saveMyDeleted: Bool', read(BRIDGE))

    def test_only_own_sent_messages_deleted_here_are_kept(self):
        bridge = read(BRIDGE)
        local = function(bridge, 'public static func snapshotLocallyDeletedMessages(')
        self.assertIn('guard settings.with({ $0.saveDeleted && $0.saveMyDeleted })', local)
        self.assertIn('if id.peerId == accountPeerId', local)
        self.assertIn('id.namespace != Namespaces.Message.Cloud && id.peerId.namespace != Namespaces.Peer.SecretChat', local)
        self.assertIn("!message.flags.contains(.Incoming) && !message.flags.contains(.Unsent) && !message.flags.contains(.Failed)", local)

    def test_interactive_delete_still_removes_the_bubble(self):
        delete = read(DELETE)
        body = delete[delete.index('public func _internal_deleteMessages('):]
        body = body[:body.index('guard !hardDeleteIds.isEmpty')]
        self.assertIn('''    } else {
        MessageSavingBridge.snapshotLocallyDeletedMessages(transaction: transaction, messageIds: ids, mediaBox: mediaBox)
    }''', body)
        # Markers stay limited to remote deletions.
        self.assertIn('    if allowDeletedMarkers {\n        let converted = convertEligibleMessagesToDeletedMarkers', body)


class SaveMessagesFromNotifications(unittest.TestCase):
    def test_extension_configures_saving_before_it_can_delete(self):
        service = read(SERVICE)
        configure = service.index('MessageSavingNotificationStaging.configureExtension(rootPath: rootPath)')
        self.assertLess(service.index('strongSelf.stateManager = stateManager'), configure)
        self.assertLess(configure, service.index('case let .deleteMessage(ids):'))
        self.assertLess(configure, service.index('unboundedPollSignal = stateManager.standalonePollDifference()'))

    def test_delete_push_saves_pushed_copies_first(self):
        service = read(SERVICE)
        handler = service[service.index('case let .deleteMessage(ids):'):]
        handler = handler[:handler.index('_internal_deleteMessages(')]
        self.assertIn('let missingIds = Set(ids.filter { transaction.getMessage($0) == nil })', handler)
        self.assertIn('MessageSavingNotificationStaging.saveDeletedPushedMessages(', handler)

    def test_only_message_pushes_are_remembered(self):
        service = read(SERVICE)
        self.assertIn('''if let messageIdValue, !isReaction {
                                    pushedMessage = (messageIdValue,''', service)
        self.assertIn('if let pushedMessage, transaction.getMessage(pushedMessage.id) == nil {', service)

    def test_extension_stays_stock_when_off_and_never_copies_media(self):
        staging = read(STAGING)
        configure = function(staging, 'public static func configureExtension(')
        self.assertIn('let _ = MessageSavingBridge.settings.swap(.disabled)', configure)
        self.assertIn('let _ = MessageSavingBridge.append.swap(nil)', configure)
        self.assertIn('saveEdits: false', configure)
        self.assertNotIn('saveMedia: true', configure)
        self.assertIn('options: .atomic', configure)

    def test_app_merges_without_duplicates(self):
        store = read(STORE)
        merge = function(store, 'private static func mergeNotificationStaging(')
        self.assertIn('if historyReadFailed {', merge)
        self.assertIn('if !hasDeletedSnapshot(of: record) {', merge)
        self.assertIn('try? FileManager.default.removeItem(at: url)', merge)
        context = read(CONTEXT)
        self.assertIn('''        if applicationBindings.isMainApp {
            MessageSavingStore.scheduleAttachmentCleanup()
            MessageSavingStore.installNotificationStaging(rootPath: rootPath)''', context)

    def test_store_test_harness_still_strips_the_app_only_code(self):
        store = read(STORE)
        install = store.index('    public static func installBridge()')
        append = store.index('    public static func append(')
        self.assertLess(install, store.index('public static func installNotificationStaging('))
        self.assertLess(store.index('private static func hasDeletedSnapshot('), append)


class DeletedMessagesPage(unittest.TestCase):
    def test_rows_live_in_message_saving(self):
        extras = read(EXTRAS)
        saving = extras[extras.index('    case .ninja, .messageSaving, .messageFilters:'):]
        saving = saving[:saving.index('    case .network:')]
        self.assertIn('.destination(2340, russian ? "Удалённые сообщения" : "Deleted Messages", .deletedMessages)', saving)
        self.assertIn('.settingToggle(2341, .messageSaving, russian ? "Сохранять мои удалённые" : "Save My Deleted Messages", settings.saveMyDeletedMessages, \\.saveMyDeletedMessages)', saving)
        self.assertIn('.settingToggle(2343, .messageSaving, russian ? "Сохранять из уведомлений" : "Save Messages from Notifications", settings.saveMessagesFromNotifications, \\.saveMessagesFromNotifications)', saving)
        for row in ['2342', '2344']:
            footer = re.search(r'\.settingFooter\(%s, \.messageSaving, russian \? "([^"]*)" : "([^"]*)"\)' % row, saving)
            self.assertIsNotNone(footer)
            self.assertLessEqual(len(footer.group(1)), 170)
            self.assertLessEqual(len(footer.group(2)), 170)
        for row in range(2340, 2345):
            self.assertEqual(len(re.findall(r'\(%d, ' % row, extras)), 1, row)
            self.assertIn('        %d: 1' % row, extras)

    def test_destination_opens_the_page(self):
        extras = read(EXTRAS)
        self.assertIn('case .deletedMessages: pushControllerImpl?(messageSavingDeletedChatsController(context: context))', extras)
        self.assertIn('case .deletedMessages: return ForkExtrasSection.deletedMessages.rawValue', extras)

    def test_page_groups_searches_and_deletes(self):
        history = read(HISTORY)
        page = history[history.index('public func messageSavingDeletedChatsController('):]
        self.assertIn('MessageSavingStore.allDeleted(accountPeerId: accountPeerId.toInt64())', page)
        self.assertIn('bananaDeletedMessageMatchesQuery(text: record.text + " " + record.authorName, query: trimmedQuery)', page)
        self.assertIn('pushControllerImpl?(messageSavingDeletedController(context: context, peerId: peerId))', page)
        self.assertIn('MessageSavingStore.clearDeleted(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())', page)
        self.assertIn('MessageSavingStore.clearAllDeleted(accountPeerId: accountPeerId.toInt64())', page)
        self.assertIn('TextAlertAction(type: .destructiveAction', page)
        self.assertIn('DataSizeStringFormatting(presentationData: presentationData)', page)
        self.assertIn('let historyQueue = Queue(name: "MessageSavingDeletedChats")', page)

    def test_clear_all_keeps_edit_history(self):
        store = read(STORE)
        remove = function(store, 'private static func removeDeleted(where predicate:')
        self.assertIn('let matches = record.kind == .deleted && predicate(record)', remove)


if __name__ == '__main__':
    unittest.main()
