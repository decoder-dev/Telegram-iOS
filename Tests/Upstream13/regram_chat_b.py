"""Regram chat features ported (batch B): folder choice after joining, recent chats on the back button, local
group alias, message bookmarks with tags. Source-text assertions; the Swift is verified by the full Bazel build."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
FIELDS = ['chooseFolderAfterJoin', 'recentChatsMenu', 'messageBookmarks', 'localGroupAlias']
IDS = [1825, 1826, 1827, 1828]


class Settings(unittest.TestCase):
    def test_fields_declared_defaulted_decoded_encoded(self):
        source = read(SETTINGS)
        for name in FIELDS:
            self.assertEqual(source.count('public var %s: Bool' % name), 1, name)
            self.assertIn('self.%s = false' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_rows_are_listed_in_a_group_with_unique_ids(self):
        source = read(CONTROLLER)
        groups = source[source.index('private static let regroupedCategories'):source.index('private static let interfaceGroups')]
        self.assertIn('[1825, 1826, 1827, 1828]', groups)
        for item_id, name in zip(IDS, FIELDS):
            self.assertRegex(source, r'\.appearanceToggle\(%d, [^\n]*settings\.%s, \\\.%s\)' % (item_id, name, name))
            self.assertEqual(len(re.findall(r'\b%d\b' % item_id, source)), 2, item_id)


class FolderAfterJoin(unittest.TestCase):
    def test_helper_is_gated_and_uses_existing_apis(self):
        source = read('submodules/AccountContext/Sources/ForkFolderAfterJoin.swift')
        self.assertIn('immediateForkExtrasSettings.chooseFolderAfterJoin', source)
        self.assertIn('currentChatListFilters()', source)
        self.assertIn('updatedData.addIncludePeer(peerId: peerId)', source)
        self.assertIn('updateChatListFiltersInteractively', source)

    def test_every_join_site_calls_it_and_requests_do_not(self):
        sites = {
            'submodules/TelegramUI/Sources/ChatController.swift': 2,
            'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift': 1,
            'submodules/ChatListUI/Sources/ChatListController.swift': 1,
            'submodules/ChatListUI/Sources/ChatContextMenus.swift': 1,
            'submodules/TelegramUI/Components/Chat/ChatChannelSubscriberInputPanelNode/Sources/ChatChannelSubscriberInputPanelNode.swift': 1,
            'submodules/JoinLinkPreviewUI/Sources/JoinLinkPreviewController.swift': 1,
            'submodules/TelegramUI/Components/JoinSubjectScreen/Sources/JoinSubjectScreen.swift': 1,
        }
        for path, count in sites.items():
            self.assertEqual(read(path).count('forkOfferFolderAfterJoin('), count, path)
        preview = read('submodules/JoinLinkPreviewUI/Sources/JoinLinkPreviewController.swift')
        self.assertLess(preview.index('if strongSelf.isRequest'), preview.index('forkOfferFolderAfterJoin('))


class RecentChats(unittest.TestCase):
    def test_store_is_per_account_and_capped(self):
        source = read('submodules/TelegramUIPreferences/Sources/ForkLocalChatData.swift')
        self.assertIn('public static let limit = 50', source)
        self.assertIn('ForkExtras.recentChats.\\(accountPeerId.toInt64())', source)
        self.assertIn('raw.removeAll(where: { $0 == entry })', source)

    def test_back_button_long_press_uses_the_navigation_menu(self):
        chat = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertIn('ForkRecentChats.record(', chat)
        self.assertIn('if (!chatNavigationStack.isEmpty || recentChatsEnabled)', chat)
        self.assertIn('clearRecents: clearRecents,', chat)
        info = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift')
        self.assertIn('clearRecents: (() -> Void)? = nil, nextFolderId: Int32?', info)
        self.assertIn('clearRecents()', info)


class LocalGroupAlias(unittest.TestCase):
    def test_titles_use_alias_and_switch_is_mirrored(self):
        titles = read('submodules/LocalizedPeerData/Sources/PeerTitle.swift')
        self.assertEqual(titles.count('ForkLocalGroupAlias.alias(for: group.id) ?? group.title'), 2)
        self.assertEqual(titles.count('ForkLocalGroupAlias.alias(for: channel.id) ?? channel.title'), 2)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('ForkLocalGroupAlias.isEnabled = settings.localGroupAlias', shared)

    def test_profile_menu_edits_the_alias_with_the_prompt(self):
        menu = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenPerformButtonAction.swift')
        self.assertIn('immediateForkExtrasSettings.localGroupAlias', menu)
        self.assertIn('ForkLocalGroupAlias.setAlias(value, for: aliasPeerId)', menu)
        self.assertIn('import PromptUI', menu)
        self.assertIn('"//submodules/PromptUI"', read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/BUILD'))

    def test_empty_alias_restores(self):
        source = read('submodules/TelegramUIPreferences/Sources/ForkLocalChatData.swift')
        self.assertIn('table.removeValue(forKey: peerId.toInt64())', source)


class MessageBookmarksTests(unittest.TestCase):
    def test_store_and_list_screen(self):
        store = read('submodules/TelegramUIPreferences/Sources/ForkLocalChatData.swift')
        self.assertIn('ForkExtras.messageBookmarks.\\(accountPeerId.toInt64())', store)
        self.assertIn('items.removeAll(where: { $0.identity == bookmark.identity })', store)
        screen = read('submodules/SettingsUI/Sources/ForkMessageBookmarksController.swift')
        self.assertIn('public func forkMessageBookmarksController(context: AccountContext) -> ViewController', screen)
        self.assertIn('subject: .message(id: .id(messageId)', screen)
        self.assertIn('ForkMessageBookmarks.remove(', screen)

    def test_menu_item_is_gated_and_prompts_for_tags(self):
        menu = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('if extras.messageBookmarks, message.id.namespace == Namespaces.Message.Cloud', menu)
        self.assertIn('ForkMessageBookmarks.parseTags(value)', menu)
        self.assertIn('forkMessageBookmarksController(context: context)', menu)
        self.assertLess(menu.index('if extras.messageBookmarks'), menu.index('if extras.selectFromAuthor'))


if __name__ == '__main__':
    unittest.main()
