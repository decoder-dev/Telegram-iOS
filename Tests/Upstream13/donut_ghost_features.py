"""Pin the Donutgram ghost / chat list / protected-screenshot ports (source-text checks)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


NAMES = ['ghostSendWithoutSound', 'ghostSuggestForStories', 'hideStories', 'hideArchive', 'allowProtectedScreenshots']


class DonutGhostFeatures(unittest.TestCase):
    def test_settings_fields_default_off_and_round_trip(self):
        source = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        for name in NAMES:
            self.assertIn('    public var %s: Bool\n' % name, source)
            self.assertIn('        self.%s = false\n' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_pushed_to_engine_statics(self):
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('ForkGhostSilentSendSettings.enabled = settings.ghostSendWithoutSound', shared)
        self.assertIn('ForkProtectedScreenshotSettings.allow = settings.allowProtectedScreenshots', shared)
        self.assertIn('hidesStories: settings.hideStories)', shared)

    def test_ghost_send_without_sound(self):
        privacy = read('submodules/TelegramCore/Sources/Arena/BananaGhostPrivacy.swift')
        self.assertIn('public enum ForkGhostSilentSendSettings', privacy)
        self.assertIn('func bananaGhostSendsSilently() -> Bool', privacy)
        self.assertIn('return ForkGhostSilentSendSettings.enabled && ForkGhostModeSettings.suppressMessageReads', privacy)
        enqueue = read('submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift')
        self.assertIn('let ghostSendsSilently = bananaGhostSendsSilently()', enqueue)
        self.assertIn('if ghostSendsSilently && !updatedAttributes.contains(where: { $0 is NotificationInfoMessageAttribute }) {', enqueue)
        self.assertIn('updatedAttributes.append(NotificationInfoMessageAttribute(flags: .muted))', enqueue)

    def test_ghost_suggest_for_stories(self):
        source = read('submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/OpenStories.swift')
        self.assertIn('suggestGhostStoryViewsIfNeeded(context: context, controller: controller, proceed: proceed)', source)
        self.assertIn('immediateForkExtrasSettings.ghostSuggestForStories, !ForkGhostModeSettings.suppressStoryViews', source)
        self.assertIn('ForkGhostModeSettings.suppressStoryViews = true', source)
        self.assertIn('updated.ghostDontReadStories = true', source)

    def test_hide_stories(self):
        header = read('submodules/TelegramPresentationData/Sources/BananaChatListHeader.swift')
        self.assertIn('public let hidesStories: Bool', header)
        node = read('submodules/ChatListUI/Sources/ChatListControllerNode.swift')
        self.assertIn('if BananaChatListHeader.current.hidesStories {\n        return false\n    }', node)
        for path in ['submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderComponent.swift',
                     'submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift']:
            self.assertIn('self.storySubscriptions = BananaChatListHeader.current.hidesStories ? nil : storySubscriptions', read(path))

    def test_hide_archive_keeps_password_presentation(self):
        node = read('submodules/ChatListUI/Sources/Node/ChatListNode.swift')
        self.assertIn('return settings.hideArchive', node)
        self.assertIn('if isPasswordProtected {\n                return presentation\n            }\n            return fullyHideArchive ? .omitted : .expanded', node)

    def test_protected_screenshots(self):
        core = read('submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift')
        self.assertIn('public enum ForkProtectedScreenshotSettings', core)
        sites = {
            'submodules/TelegramUI/Sources/ChatControllerNode.swift': 'self.chatPresentationInterfaceState.copyProtectionEnabled && !ForkProtectedScreenshotSettings.allow',
            'submodules/TelegramUI/Sources/ChatController.swift': 'strongSelf.presentationInterfaceState.copyProtectionEnabled && !ForkProtectedScreenshotSettings.allow',
            'submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift': 'self.presentationInterfaceState.myCopyProtectionEnabled) && !ForkProtectedScreenshotSettings.allow',
            'submodules/TelegramUI/Sources/ChatPinnedMessageTitlePanelNode.swift': 'interfaceState.myCopyProtectionEnabled) && !ForkProtectedScreenshotSettings.allow',
            'submodules/GalleryUI/Sources/GalleryController.swift': 'let copyProtectionBlocksCapture = (message.isCopyProtected() || peerIsCopyProtected) && !ForkProtectedScreenshotSettings.allow',
            'submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift': 'let copyProtectionBlocksCapture = (message.isCopyProtected() || peerIsCopyProtected) && !ForkProtectedScreenshotSettings.allow',
            'submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift': 'message.isCopyProtected()) && !ForkProtectedScreenshotSettings.allow',
            'submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift': 'item.message.isCopyProtected()) && !ForkProtectedScreenshotSettings.allow',
            'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift': 'sharedMediaFromForumTopic: self.sharedMediaFromForumTopic) && !ForkProtectedScreenshotSettings.allow)',
            'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoPaneContainerNode.swift': 'sharedMediaFromForumTopic: sharedMediaFromForumTopic) && !ForkProtectedScreenshotSettings.allow',
        }
        for path, needle in sites.items():
            self.assertIn(needle, read(path), path)
        media = read('submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift')
        self.assertEqual(media.count('message.isCopyProtected()) && !ForkProtectedScreenshotSettings.allow) || isExtendedMedia'), 2)
        # Paid / secret media keep their own protection.
        gallery = read('submodules/GalleryUI/Sources/GalleryController.swift')
        self.assertIn('return copyProtectionBlocksCapture || drawsSecretBlur || message.paidContent != nil', gallery)

    def test_extras_rows(self):
        ctl = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        for row_id, key in [(1770, 'ghostSendWithoutSound'), (1771, 'ghostSuggestForStories'), (1773, 'hideStories'), (1774, 'hideArchive'), (1775, 'allowProtectedScreenshots')]:
            self.assertRegex(ctl, r'\.appearanceToggle\(%d, russian \? "[^"]+" : "[^"]+", settings\.%s, \\\.%s\)' % (row_id, key, key))
        self.assertIn('(.ghost, [[1560, 1561, 1562], [1770, 1771, 1772]])', ctl)
        self.assertIn('[1773, 1774]', ctl)
        ids = re.findall(r'\.appearanceToggle\((\d+),', ctl)
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == '__main__':
    unittest.main()
