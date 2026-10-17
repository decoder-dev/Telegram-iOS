"""Source-text pins for the Regram chat features (message id, auto-reveal spoilers, double-tap action, repeat menu)."""
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text(encoding='utf-8')

SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
HOT = 'submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'

class RegramChatA(unittest.TestCase):
    def test_settings_default_off_and_round_trip(self):
        s = read(SETTINGS)
        for key in ('showMessageId', 'autoRevealSpoilers', 'repeatMessageMenu'):
            self.assertIn('self.%s = false' % key, s)
            self.assertIn('decodeIfPresent(Bool.self, forKey: "%s") ?? false' % key, s)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (key, key), s)
        self.assertIn('self.doubleTapAction = doubleTapToEdit ? 6 : 0', s)
        self.assertIn('forKey: "doubleTapAction") ?? (self.doubleTapToEdit ? 6 : 0)', s)
        self.assertIn('self.doubleTapAction == 6, forKey: "doubleTapToEdit"', s)
        # the old key is still decoded before the migration reads it
        self.assertLess(s.index('forKey: "doubleTapToEdit") ?? false'), s.index('forKey: "doubleTapAction")'))

    def test_hot_flags_projected(self):
        h = read(HOT)
        a = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        for name in ('doubleTapAction', 'showMessageId', 'autoRevealSpoilers', 'repeatMessageMenu'):
            self.assertIn('public static var %s' % name, h)
            self.assertIn('%s: settings.%s' % (name, name), a)
        self.assertIn('doubleTapToEdit: settings.doubleTapAction == 6', a)

    def test_message_id_in_status_text(self):
        s = read('submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift')
        self.assertIn('ForkExtrasHotFlags.showMessageId', s)
        self.assertIn('"#\\(message.id.id) "', s)
        self.assertIn('TelegramChannel || message.peers[message.id.peerId] is TelegramGroup', s)

    def test_spoiler_hooks_and_relayout(self):
        self.assertIn('displayContentsUnderSpoilers.value || ForkExtrasHotFlags.autoRevealSpoilers', read('submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift'))
        m = read('submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift')
        self.assertIn('displaySpoiler = !ForkExtrasHotFlags.autoRevealSpoilers', m)
        self.assertIn('!ForkExtrasHotFlags.autoRevealSpoilers, strongSelf.extendedMediaOverlayNode == nil', m)
        self.assertIn('self.textNode.displaySpoilers = ForkExtrasHotFlags.autoRevealSpoilers', read('submodules/GalleryUI/Sources/ChatItemGalleryFooterContentNode.swift'))
        l = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('regramChat: [settings.showMessageId, settings.autoRevealSpoilers]', l)

    def test_double_tap_action_dispatch(self):
        b = read('submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift')
        self.assertIn('self.performDoubleTapActionIfNeeded(message: editMessage, item: item)', b)
        body = b[b.index('private func performDoubleTapActionIfNeeded'):b.index('private func beginDoubleTapEditIfNeeded')]
        for n in ('case 1:', 'case 2:', 'case 3:', 'case 4:', 'case 6:'):
            self.assertIn(n, body)
        self.assertIn('.translate)', body)
        self.assertIn('canSetupReply', body)
        # edit no longer depends on the old bool alone
        edit = b[b.index('private func beginDoubleTapEditIfNeeded'):]
        self.assertNotIn('ForkExtrasHotFlags.doubleTapToEdit', edit[:400])

    def test_repeat_menu_guards(self):
        c = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        block = c[c.index('// Regram port: Repeat'):c.index('if !isCopyProtected, message.text.count >= ForkOnDeviceAI')]
        for guard in ('extras.repeatMessageMenu', 'canSendMessagesToChat(chatPresentationInterfaceState)', '!isCopyProtected', 'SecretChat'):
            self.assertIn(guard, block)
        self.assertIn('ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)', block)
        self.assertIn('ForwardOptionsMessageAttribute(hideNames: false, hideCaptions: false)', block)

    def test_settings_rows_and_ids(self):
        c = read(CONTROLLER)
        ids = [int(x) for x in re.findall(r'\.(?:appearanceToggle|intChoice)\((18\d\d),', c)]
        self.assertTrue({1800, 1801, 1802, 1803} <= set(ids))
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn('[1802],\n            [1800, 1801, 1803]', c)
        self.assertIn('case 1802:', c)
        self.assertIn('keyPath = \\.doubleTapAction', c)
        self.assertIn("'forkDoubleTapActionOptions'", read('Tests/ClientAdditions/menu_layout.py'))

if __name__ == '__main__':
    unittest.main()
