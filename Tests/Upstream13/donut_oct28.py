"""Donutgram commits of 2026-10-27..28, ported: approximate last seen (#120) and anonymous sticker sending (#121).
#108 (copy a photo or a frame, mp4 from Files as video) was already here. Source-text assertions; the Swift is
verified by the full Bazel build."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
SHARED = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
UPLOAD = 'submodules/TelegramCore/Sources/PendingMessages/PendingMessageUploadedContent.swift'


class ApproximateLastSeen(unittest.TestCase):
    def test_setting_is_off_by_default_and_round_trips(self):
        source = read(SETTINGS)
        self.assertIn('public var approximateLastSeen: Bool', source)
        self.assertIn('self.approximateLastSeen = false', source)
        self.assertIn('decodeIfPresent(Bool.self, forKey: "approximateLastSeen") ?? false', source)
        self.assertIn('try container.encode(self.approximateLastSeen, forKey: "approximateLastSeen")', source)

    def test_row_is_in_the_profile_screen_and_wired(self):
        controller = read(CONTROLLER)
        self.assertIn('.appearanceToggle(2020,', controller)
        self.assertIn('\\.approximateLastSeen)', controller)
        self.assertIn('[55, 56, 1551, 1714, 2020, 1552, 1543, 58]', controller)
        self.assertEqual(controller.count('(2020,'), 1)
        self.assertIn('BananaApproximateLastSeen.update(enabled: settings.approximateLastSeen)', read(SHARED))

    def test_only_a_hidden_status_with_recent_activity_is_shown(self):
        source = read('submodules/TelegramCore/Sources/Arena/BananaApproximateLastSeen.swift')
        # Only "recently" is replaced; an exact or banded status from the server is never overridden.
        self.assertIn('case .recently = status', source)
        self.assertIn('guard since != 0', source)
        self.assertIn('lastActivity > since', source)
        self.assertIn('age >= 0, age < Int64(self.maximumAge)', source)
        # Switching off forgets the moment, so a later switch-on does not trust what was seen in between.
        self.assertIn('defaults.removeObject(forKey: self.sinceDefaultsKey)', source)

    def test_strings_and_refresh_follow_it(self):
        strings = read('submodules/TelegramStringFormatting/Sources/PresenceStrings.swift')
        self.assertIn('BananaApproximateLastSeen.timestamp(status: presence.status, lastActivity: presence.lastActivity, relativeTo: timestamp)', strings)
        self.assertIn('BananaApproximateLastSeen.refreshTimeout(', strings)
        manager = read('submodules/PeerPresenceStatusManager/Sources/PeerPresenceStatusManager.swift')
        self.assertIn('BananaApproximateLastSeen.refreshTimeout(', manager)


class AnonymousStickers(unittest.TestCase):
    def test_setting_is_off_by_default_and_round_trips(self):
        source = read(SETTINGS)
        self.assertIn('public var anonymousStickers: Bool', source)
        self.assertIn('self.anonymousStickers = false', source)
        self.assertIn('decodeIfPresent(Bool.self, forKey: "anonymousStickers") ?? false', source)
        self.assertIn('try container.encode(self.anonymousStickers, forKey: "anonymousStickers")', source)

    def test_row_is_in_the_media_screen_and_wired(self):
        controller = read(CONTROLLER)
        self.assertIn('.appearanceToggle(2021,', controller)
        self.assertEqual(controller.count('(2021,'), 1)
        self.assertIn('2021, 1757, 1758]', controller)
        self.assertIn('BananaAnonymousStickers.enabled = settings.anonymousStickers', read(SHARED))

    def test_upload_drops_the_set_and_skips_caches(self):
        upload = read(UPLOAD)
        self.assertEqual(upload.count('BananaAnonymousStickers.appliesTo(file: file, peerId: peerId)'), 2)
        self.assertIn('packReference: nil', upload)
        self.assertEqual(upload.count('inputDocumentAttributesFromFileAttributes(uploadFileAttributes)'), 3)
        self.assertIn('if uploadAsBannedGifVideo || anonymousSticker {', upload)
        source = read('submodules/TelegramCore/Sources/Arena/BananaAnonymousStickers.swift')
        # A secret chat keeps the set: its media is not re-uploaded through this path.
        self.assertIn('peerId.namespace != Namespaces.Peer.SecretChat', source)
        self.assertIn('case .id, .name:', source)

    def test_set_is_kept_for_the_sent_file_and_opened(self):
        apply = read('submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift')
        self.assertIn('BananaAnonymousStickers.save(originalReference, accountPeerId: accountPeerId, file: sentFile)', apply)
        self.assertIn('!sentHasReference', apply)
        self.assertIn('BananaAnonymousStickers.stickerPack(accountPeerId: params.context.account.peerId, file: file)', read('submodules/TelegramUI/Sources/OpenChatMessage.swift'))
        self.assertIn('BananaAnonymousStickers.stickerPack(accountPeerId: accountPeerId, file: file)', read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift'))


if __name__ == '__main__':
    unittest.main()
