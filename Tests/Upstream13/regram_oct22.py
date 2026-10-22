"""Regram chat and folder options ported (Oct 22): bulk invite-link revocation, hidden folder unread counts, confirm before
unpinning, hidden typing status in private chats, staying at the newest message after a reload. Every one is a default-off
Extras switch. Source-text assertions; the Swift is verified by the full Bazel build."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
FIELDS = ['inviteLinksBulkRevoke', 'hideFolderUnreadCount', 'confirmUnpin', 'hidePrivateChatActivities', 'stayAtLatestMessageAfterRefresh']
IDS = [1960, 1961, 1962, 1963, 1964]
INVITES = 'submodules/InviteLinksUI/Sources/InviteLinkListController.swift'


class Settings(unittest.TestCase):
    def test_fields_declared_defaulted_decoded_encoded(self):
        source = read(SETTINGS)
        for name in FIELDS:
            self.assertEqual(source.count('public var %s: Bool' % name), 1, name)
            self.assertIn('self.%s = false' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_rows_are_listed_in_groups_with_unique_ids(self):
        source = read(CONTROLLER)
        groups = source[source.index('private static let regroupedCategories'):source.index('private static let interfaceGroups')]
        self.assertIn('[1961, 1963]', groups)
        self.assertIn('[1960, 1962, 1964]', groups)
        for item_id, name in zip(IDS, FIELDS):
            self.assertRegex(source, r'\.appearanceToggle\(%d, [^\n]*settings\.%s, \\\.%s\)' % (item_id, name, name))
            self.assertEqual(len(re.findall(r'\b%d\b' % item_id, source)), 2, item_id)


class InviteRevocation(unittest.TestCase):
    def test_flow_is_gated_and_protects_the_main_link(self):
        source = read(INVITES)
        self.assertIn('immediateForkExtrasSettings.inviteLinksBulkRevoke', source)
        self.assertIn('bulkRevokeEnabled && hasLinks', source)
        candidates = source[source.index('private func inviteLinksBulkRevokeCandidates('):source.index('private func revokeInviteLinksSerially(')]
        self.assertIn('adminId == accountPeerId, link != protectedMainLink, !isPermanent, !isRevoked', candidates)
        self.assertIn('protectedMainLink.swap(exportedInvitation?.link)', source)

    def test_revocation_is_serial_and_reloads_both_lists(self):
        source = read(INVITES)
        self.assertIn('mapToQueue', source)
        self.assertIn('delay(inviteLinksBulkRevokeDelay', source)
        self.assertIn('invitesContext.reload()', source)
        self.assertIn('revokedInvitesContext.reload()', source)

    def test_entry_is_wired_through_every_switch(self):
        source = read(INVITES)
        self.assertEqual(source.count('linksBulkRevoke'), 7)
        self.assertEqual(source.count('bulkRevokeAdditionalLinks'), 9)


class FolderBadges(unittest.TestCase):
    def test_both_tab_implementations_honour_the_switch(self):
        node = read('submodules/ChatListUI/Sources/ChatListControllerNode.swift')
        self.assertIn('unread.value != 0 && !self.context.sharedContext.immediateForkExtrasSettings.hideFolderUnreadCount', node)
        tabs = read('submodules/TelegramUI/Components/ChatList/ChatListFilterTabContainerNode/Sources/ChatListFilterTabContainerNode.swift')
        self.assertIn('var unreadCount: Int', tabs)
        self.assertIn('immediateForkExtrasSettings.hideFolderUnreadCount {\n                unreadCount = 0', tabs)


class ChatBehaviours(unittest.TestCase):
    def test_confirm_unpin_covers_single_and_all(self):
        source = read('submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift')
        self.assertIn('askForConfirmation || strongSelf.context.sharedContext.immediateForkExtrasSettings.confirmUnpin', source)
        self.assertEqual(source.count('immediateForkExtrasSettings.confirmUnpin'), 2)
        self.assertIn('Chat_PanelUnpinAllMessages, action: {', source)

    def test_private_typing_status_is_hidden_in_list_and_title(self):
        chat_list = read('submodules/ChatListUI/Sources/Node/ChatListNode.swift')
        self.assertIn('forkActivitySharedContext.immediateForkExtrasSettings.hidePrivateChatActivities', chat_list)
        self.assertIn('key.peerId.namespace == Namespaces.Peer.CloudUser || key.peerId.namespace == Namespaces.Peer.SecretChat', chat_list)
        chat = read('submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift')
        self.assertIn('immediateForkExtrasSettings.hidePrivateChatActivities && (peerId.namespace == Namespaces.Peer.CloudUser', chat)

    def test_reload_stays_at_newest_only_from_the_edge(self):
        source = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        marker = source.index('immediateForkExtrasSettings.stayAtLatestMessageAfterRefresh')
        block = source[marker:marker + 900]
        self.assertIn('updatedScrollPosition == nil', block)
        self.assertIn('offset <= 0.9', block)
        self.assertIn('case .Reload, .HoleReload:', block)
        self.assertLess(marker, source.index('let rawTransition = preparedChatHistoryViewTransition(from: previous, to: processedView, reason: reason, reverse: reverse'))


if __name__ == '__main__':
    unittest.main()
