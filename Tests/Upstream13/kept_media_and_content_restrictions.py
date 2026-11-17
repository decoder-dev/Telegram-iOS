"""Keep Self-Destructing Media and Bypass Content Restrictions (Ghostgram): settings, Extras rows, the runtime flags,
the places that consume media or match a platform restriction, and Mark as Opened. Source-text checks; Swift builds in CI."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
SHARED = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
FLAGS = 'submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift'
CONSUME = 'submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift'
ENGINE = 'submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift'
TIMEOUT = 'submodules/TelegramCore/Sources/SyncCore/SyncCore_AutoremoveTimeoutMessageAttribute.swift'
VIEWER = 'submodules/GalleryUI/Sources/SecretMediaPreviewController.swift'
PEER_UTILS = 'submodules/TelegramCore/Sources/Utils/PeerUtils.swift'
MATCHING = 'submodules/PlatformRestrictionMatching/Sources/PlatformRestrictionMatching.swift'
MENU = 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift'
MENU_ITEMS = 'submodules/TelegramUIPreferences/Sources/ForkMessageMenu.swift'

FIELDS = ['keepSelfDestructingMedia', 'bypassContentRestrictions']


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


class Settings(unittest.TestCase):
    def test_fields_are_stored_and_off_by_default(self):
        source = read(SETTINGS)
        for name in FIELDS:
            self.assertIn('public var %s: Bool' % name, source)
            self.assertIn('self.%s = false' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_settings_reach_telegram_core(self):
        source = read(SHARED)
        self.assertIn('ForkKeepSelfDestructingMediaSettings.enabled = settings.keepSelfDestructingMedia', source)
        self.assertIn('ForkContentRestrictionsBypassSettings.enabled = settings.bypassContentRestrictions', source)

    def test_extras_rows_sit_in_their_blocks(self):
        source = read(EXTRAS)
        self.assertIn('.appearanceToggle(2430, russian ? "Не сжигать исчезающие медиа" : "Keep Self-Destructing Media", settings.keepSelfDestructingMedia, \\.keepSelfDestructingMedia)', source)
        self.assertIn('            [2046, 38, 1775, 40, 39, 41],\n            [2430, 2431],\n', source)
        self.assertIn('.settingToggle(2432, .messageFilters, russian ? "Обходить ограничения контента" : "Bypass Content Restrictions", settings.bypassContentRestrictions, \\.bypassContentRestrictions)', source)
        self.assertIn('        2432: 133.7,', source)
        self.assertIn('        2433: 133.8,', source)
        for row_id in (2430, 2431, 2432, 2433):
            self.assertEqual(source.count('(%d,' % row_id), 1, row_id)


class KeptMedia(unittest.TestCase):
    def test_only_incoming_cloud_secret_media_is_kept(self):
        source = read(FLAGS)
        body = source[source.index('public enum ForkKeepSelfDestructingMediaSettings {'):]
        body = body[:body.index('\n}\n')]
        self.assertIn('Atomic<Bool>(value: false)', body)
        self.assertIn('message.flags.contains(.Incoming), message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat', body)
        self.assertIn('return message.containsSecretMedia', body)

    def test_opening_kept_media_changes_nothing(self):
        source = read(CONSUME)
        guard = source.index('if ForkKeepSelfDestructingMediaSettings.keeps(message) {\n                return\n            }')
        # Before the consumed flag, the read packet, the countdown and the Message Saving copy.
        self.assertLess(guard, source.index('let suppressContentReadPacket'))
        self.assertLess(guard, source.index('MessageSavingBridge.preserveMediaIfNeeded'))

    def test_kept_media_has_no_blur_and_no_screenshot_notice(self):
        blur = read(TIMEOUT)
        blur = blur[blur.index('var shouldDrawSecretMediaBlur: Bool {'):]
        self.assertLess(blur.index('if ForkKeepSelfDestructingMediaSettings.keeps(self) {\n            return false'), blur.index('return self.containsSecretMedia'))
        viewer = read(VIEWER)
        self.assertIn('if strongSelf.messageId.peerId.namespace == Namespaces.Peer.CloudUser && !ForkKeepSelfDestructingMediaSettings.enabled {', viewer)

    def test_mark_as_opened_reports_without_consuming(self):
        engine = read(ENGINE)
        body = engine[engine.index('public func reportSelfDestructingMediaOpened(messageId: MessageId) -> Signal<Void, NoError> {'):]
        body = body[:body.index('\n        }\n')]
        self.assertIn('addSynchronizeConsumeMessageContentsOperation(transaction: transaction, messageIds: [messageId])', body)
        self.assertNotIn('updateMessage', body)
        menu = read(MENU)
        self.assertIn('ForkKeepSelfDestructingMediaSettings.keeps(message), message.id.peerId.namespace == Namespaces.Peer.CloudUser || message.id.peerId.namespace == Namespaces.Peer.CloudGroup, !ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: context.account.peerId, peerId: message.id.peerId)', menu)
        self.assertIn('ContextMenuActionItem(id: ForkMessageMenuItem.markMediaOpened, text: extrasMenuIsRussian ? "Отметить открытым" : "Mark as Opened"', menu)
        self.assertIn('context.engine.messages.reportSelfDestructingMediaOpened(messageId: messageId)', menu)
        items = read(MENU_ITEMS)
        self.assertIn('    case mediaInfo\n    case markMediaOpened\n    case saveToSavedMessages\n', items)


class ContentRestrictions(unittest.TestCase):
    def test_flag_is_off_by_default(self):
        source = read(FLAGS)
        body = source[source.index('public enum ForkContentRestrictionsBypassSettings {'):]
        self.assertIn('Atomic<Bool>(value: false)', body[:body.index('\n}\n')])

    def test_both_matchers_return_no_restriction_first(self):
        for name, signature in [(PEER_UTILS, 'func restrictionText(platform: String, contentSettings: ContentSettings) -> String? {'),
                                (MATCHING, 'func platformText(platform: String, contentSettings: ContentSettings) -> String? {')]:
            source = read(name)
            body = source[source.index(signature):]
            self.assertLess(body.index('if ForkContentRestrictionsBypassSettings.enabled {\n            return nil\n        }'), body.index('for rule in'), name)


if __name__ == '__main__':
    unittest.main()
