"""Regram input / links / media block: source-text pins for the hooks (no Swift compiler locally)."""
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text(encoding='utf-8')

SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
FIELDS = {
    'defaultSendFormatting': 'Int32', 'avatarLongPressMention': 'Bool', 'fixLinkPreviews': 'Bool',
    'saveStickerToPhotos': 'Bool', 'showMediaInfo': 'Bool', 'defaultVideoQuality': 'Int32',
}

class RegramInputMedia(unittest.TestCase):
    def test_settings_fields_declared_defaulted_decoded_encoded(self):
        s = read(SETTINGS)
        for name, kind in FIELDS.items():
            self.assertIn('public var %s: %s' % (name, kind), s)
            self.assertRegex(s, r'self\.%s = (0|false)\n' % name)
            self.assertIn('decodeIfPresent(%s.self, forKey: "%s")' % (kind, name), s)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), s)

    def test_choices_are_range_checked_on_decode(self):
        s = read(SETTINGS)
        self.assertIn('(0 ... 5).contains(decodedSendFormatting)', s)
        self.assertIn('(0 ... 2).contains(decodedVideoQuality)', s)

    def test_rows_use_reserved_ids_and_are_grouped(self):
        c = read(CONTROLLER)
        ids = [int(i) for i in re.findall(r'\.(?:appearanceToggle|intChoice|designHeader|designFooter)\((18[5-9]\d)', c)]
        self.assertEqual(sorted(ids), list(range(1850, 1854)) + list(range(1860, 1866)))
        self.assertIn('[1850, 1851, 1852, 1853]', c)
        self.assertIn('[1860, 1861, 1862, 1863, 1864, 1865]', c)
        for key in ('1851', '1864'):
            self.assertIn('case %s:' % key, c)
        self.assertIn('\\.defaultSendFormatting', c)
        self.assertIn('\\.defaultVideoQuality', c)

    def test_menu_factory_fixture_knows_the_new_helpers(self):
        t = read('Tests/ClientAdditions/menu_layout.py')
        c = read(CONTROLLER)
        for name in ('forkSendFormattingOptions', 'forkVideoQualityOptions'):
            self.assertIn(name, t)
            self.assertIn('private func %s(' % name, c)

    def test_send_formatting_is_applied_to_text_entities_only(self):
        n = read('submodules/TelegramUI/Sources/ChatControllerNode.swift')
        self.assertIn('forkApplyDefaultSendFormatting(text: text.string, entities: entities, style: defaultSendFormatting)', n)
        self.assertIn('defaultSendFormatting != 0 && !sendWithoutFormatting', n)
        f = read('submodules/TelegramUI/Sources/ForkDefaultSendFormatting.swift')
        for kept in ('.Bold', '.Italic', '.Underline', '.Strikethrough', '.Spoiler', '.Code', '.Pre', '.BlockQuote', '.CustomEmoji'):
            self.assertIn(kept, f)

    def test_avatar_long_press_mentions_full_name(self):
        c = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertIn('immediateForkExtrasSettings.avatarLongPressMention', c)
        self.assertIn('chatTextInputAddFullNameMentionAttribute(current, peer: peer)', c)
        t = read('submodules/ChatPresentationInterfaceState/Sources/ChatTextFormat.swift')
        self.assertIn('public func chatTextInputAddFullNameMentionAttribute(', t)
        self.assertIn('ChatTextInputTextMentionAttribute(peerId: peer.id)', t)

    def test_link_preview_rewrites_request_not_the_message(self):
        m = read('submodules/TelegramUI/Sources/ForkLinkPreviewMirrors.swift')
        for pair in ('"x.com": "fixupx.com"', '"twitter.com": "fxtwitter.com"', '"www.instagram.com": "ddinstagram.com"',
                     '"vm.tiktok.com": "vm.vxtiktok.com"', '"www.reddit.com": "www.vxreddit.com"', '"bsky.app": "fxbsky.app"',
                     '"www.pixiv.net": "www.phixiv.net"'):
            self.assertIn(pair, m)
        q = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextQueries.swift')
        self.assertIn('webpagePreview(account: context.account, urls: requestUrls, forPeerId: forPeerId)', q)
        self.assertIn('UrlPreviewState(detectedUrls: detectedUrls)', q)
        self.assertIn('immediateForkExtrasSettings.fixLinkPreviews && forPeerId?.namespace != Namespaces.Peer.SecretChat', q)

    def test_sticker_save_and_media_info_menu_entries(self):
        m = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('extras.saveStickerToPhotos', m)
        self.assertIn('forkSaveStickerToPhotos(context: context', m)
        self.assertIn('extras.showMediaInfo', m)
        self.assertIn('ForkMediaInfo.report(mediaBox: mediaBox', m)
        declared = m.index('let extras = context.sharedContext.immediateForkExtrasSettings')
        self.assertLess(declared, m.index('extras.saveStickerToPhotos'))
        sv = read('submodules/TelegramUI/Sources/ForkStickerSave.swift')
        self.assertIn('UTType.gif.identifier', sv)
        self.assertIn('PHAssetCreationRequest.forAsset()', sv)

    def test_default_video_quality_picks_only_offered_versions(self):
        g = read('submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift')
        self.assertIn('state.available.max() : state.available.min()', g)
        self.assertIn('(state?.available.count ?? 0) > 1', g)
        self.assertIn('case .auto = self.videoQuality', g)


if __name__ == '__main__':
    unittest.main()
