"""Donutgram profile / identity switches: settings plumbing, Extras rows and the display hooks."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
PEER_INFO = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/'
FIELDS = ['showChatCreationDate', 'profileIdBotApiFormat', 'showMutualContact', 'hidePremiumStatuses',
          'hideVerification', 'hideGiftButton', 'visualPhoneEnabled']


class DonutProfileFeatures(unittest.TestCase):
    def test_settings_are_declared_defaulted_decoded_and_encoded(self):
        s = read(SETTINGS)
        for field in FIELDS:
            self.assertIn('public var %s: Bool' % field, s)
            self.assertIn('self.%s = false' % field, s)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (field, field), s)
        for field in FIELDS:
            if field != 'showMutualContact':
                self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (field, field), s)
        # The mutual-contact row used to ride on Show Profile ID; old blobs keep it.
        self.assertIn('forKey: "showMutualContact") ?? self.showProfileId', s)
        self.assertIn('public var visualPhoneNumber: String', s)
        self.assertIn('try container.decodeIfPresent(String.self, forKey: "visualPhoneNumber") ?? ""', s)

    def test_extras_rows_use_the_assigned_ids_and_are_grouped(self):
        c = read(CONTROLLER)
        for row_id, field in [(1730, 'showChatCreationDate'), (1731, 'profileIdBotApiFormat'), (1732, 'showMutualContact'),
                              (1733, 'hidePremiumStatuses'), (1734, 'hideVerification'), (1735, 'hideGiftButton'),
                              (1736, 'visualPhoneEnabled')]:
            self.assertRegex(c, r'\.appearanceToggle\(%d, .*settings\.%s, \\\.%s\)' % (row_id, field, field))
        self.assertIn('[1739, 1731, 1732, 1730, 1733, 1734, 1980, 1981]', c)
        self.assertIn('[1740, 1736, 1737, 1738]', c)
        self.assertIn('[1508, 1509, 1735, 54,', c)
        self.assertIn('case .visualPhoneNumber: return 1737', c)
        self.assertIn('.visualPhoneNumber(settings.visualPhoneNumber)', c)
        self.assertIn('updated.visualPhoneNumber = value', c)
        ids = [int(x) for x in re.findall(r'\b(17[3-4]\d)\b', c)]
        self.assertTrue(all(1730 <= i <= 1749 for i in ids))

    def test_profile_rows(self):
        items = read(PEER_INFO + 'PeerInfoProfileItems.swift')
        self.assertIn('forkProfileIdText(peerId: $0.id, botApiFormat: forkExtras.profileIdBotApiFormat)', items)
        self.assertIn('if forkExtras.showMutualContact && !hideDiagnostics, case let .user(user)? = data.peer', items)
        self.assertIn('if forkExtras.showChatCreationDate {', items)
        self.assertIn('creationTimestamp = channel.creationDate', items)
        self.assertIn('creationTimestamp = group.creationDate', items)
        self.assertIn('AnyHashable("fork_creation_date")', items)
        s = read(SETTINGS)
        self.assertIn('return "\\(-1_000_000_000_000 - rawId)"', s)
        self.assertIn('if peerId.namespace == Namespaces.Peer.CloudGroup {', s)

    def test_visual_phone_is_display_only_and_own_only(self):
        s = read(SETTINGS)
        self.assertIn('if accountPeerId == peerId && settings.visualPhoneEnabled {', s)
        for name in ['PeerInfoProfileItems.swift', 'PeerInfoHeaderNode.swift', 'PeerInfoSettingsItems.swift']:
            self.assertIn('forkDisplayedPhone(accountPeerId:', read(PEER_INFO + name), name)
        # The phone action still opens the real number.
        self.assertIn('interaction.openPhone(phone, node, nil, progress)', read(PEER_INFO + 'PeerInfoProfileItems.swift'))

    def test_badge_hiding_is_projected_and_hooked(self):
        holder = read('submodules/TelegramCore/Sources/Arena/BananaIdentityBadges.swift')
        self.assertIn('return peerId != accountPeerId && state.with { $0.hidesPremiumStatuses }', holder)
        self.assertIn('BananaIdentityBadges.update(hidesPremiumStatuses: settings.hidePremiumStatuses, hidesVerification: settings.hideVerification)',
                      read('submodules/TelegramUI/Sources/SharedAccountContext.swift'))
        sites = {
            PEER_INFO + 'PeerInfoHeaderNode.swift': 1,
            'submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift': 1,
            'submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift': 1,
            'submodules/ChatListUI/Sources/Node/ChatListItem.swift': 2,
            'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift': 1,
        }
        for path, count in sites.items():
            source = read(path)
            self.assertEqual(source.count('BananaIdentityBadges.hidesPremiumStatus(peerId:'), count, path)
            self.assertGreaterEqual(source.count('BananaIdentityBadges.hidesVerification'), count, path)
            self.assertNotRegex(source, r'if peer\.isVerified \{', path)

    def test_gift_button(self):
        source = read('submodules/TelegramUI/Sources/ChatInterfaceInputContexts.swift')
        hook = source.index('if context.sharedContext.immediateForkExtrasSettings.hideGiftButton {')
        self.assertLess(hook, source.index('accessoryItems.append(.gift)'))
        self.assertIn('import TelegramUIPreferences', source)


if __name__ == '__main__':
    unittest.main()
