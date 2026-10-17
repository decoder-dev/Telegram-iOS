"""WhiteGram features ported into Extras: disable story creation, channel post reactions."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text(encoding='utf-8')

SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
CORE = 'submodules/TelegramCore/Sources/Arena/ForkWhiteGramSettings.swift'
CHAT = 'submodules/TelegramUI/Components/Chat/'
ROWS = {1930: 'disableStoryCreation', 1931: 'hideChannelPostReactions'}


class WhiteGramFeatures(unittest.TestCase):
    def test_settings_default_off_and_persist(self):
        source = read(SETTINGS)
        for name in ROWS.values():
            self.assertIn('public var %s: Bool' % name, source)
            self.assertIn('self.%s = false' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_rows_and_grouping(self):
        source = read(CONTROLLER)
        groups = source.split('regroupedCategories')[1].split('interfaceGroups')[0]
        for row, name in ROWS.items():
            self.assertIn('.appearanceToggle(%d,' % row, source)
            self.assertIn('\\.%s)' % name, source)
            self.assertIn('[%d]' % row, groups)

    def test_runtime_projection(self):
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('ForkStoryCreationSettings.disabled = settings.disableStoryCreation', shared)
        self.assertIn('ForkChannelPostReactionsSettings.hidden = settings.hideChannelPostReactions', shared)
        history = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('hideChannelPostReactions: settings.hideChannelPostReactions', history)

    def test_story_entry_points_gated(self):
        chat_list = read('submodules/ChatListUI/Sources/ChatListController.swift')
        self.assertGreaterEqual(chat_list.count('ForkStoryCreationSettings.disabled'), 4)
        root = read('submodules/TelegramUI/Sources/TelegramRootController.swift')
        body = root.split('public func openStoryCamera(')[1][:700]
        self.assertIn('ForkStoryCreationSettings.disabled', body)

    def test_reactions_hook(self):
        core = read(CORE)
        self.assertIn('broadcast', core)
        self.assertIn('func forkHidesMessageReactions(', core)
        for path in ['ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift',
                     'ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift',
                     'ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift',
                     'ChatMessageInstantVideoItemNode/Sources/ChatMessageInstantVideoItemNode.swift']:
            source = read(CHAT + path)
            self.assertIn('forkHidesMessageReactions(', source)
            self.assertNotIn('ForkExtrasHotFlags.hideReactionsBar', source)


if __name__ == '__main__':
    unittest.main()
