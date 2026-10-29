"""Pin the Donutgram media / sticker / playback features ported into BananaGram (source-text assertions)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


TWEAKS = 'submodules/TelegramCore/Sources/Arena/BananaMediaTweaks.swift'
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
FIELDS = {
    'accelerateUpload': ('Bool', 'false'),
    'infiniteRecentStickers': ('Bool', 'false'),
    'onlyAddedStickers': ('Bool', 'false'),
    'autoPauseMediaInBackground': ('Bool', 'false'),
    'doubleTapSeekSeconds': ('Int32', '15'),
    'staticRoundVideoZoom': ('Bool', 'false'),
    'stickerShape': ('Int32', '0'),
}


class DonutMediaFeatures(unittest.TestCase):
    def test_settings_fields_default_to_stock_and_round_trip(self):
        source = read(SETTINGS)
        for name, (kind, default) in FIELDS.items():
            self.assertIn(f'    public var {name}: {kind}\n', source)
            self.assertIn(f'        self.{name} = {default}\n', source)
            self.assertIn(f'forKey: "{name}")', source)
            self.assertIn(f'try container.encode(self.{name}, forKey: "{name}")', source)
        self.assertIn('[0, 5, 10, 15, 30].contains(decodedSeekSeconds) ? decodedSeekSeconds : 15', source)
        self.assertIn('self.stickerShape = min(2, max(0,', source)

    def test_runtime_holder_is_projected_and_stock_by_default(self):
        tweaks = read(TWEAKS)
        self.assertNotIn('import UIKit', tweaks)
        self.assertIn('public var doubleTapSeekSeconds: Int32 = 15', tweaks)
        self.assertIn('return state.with { $0.infiniteRecentStickers } ? nil : 20', tweaks)
        self.assertIn('case 1: return 12.0', tweaks)
        self.assertIn('case 2: return 22.0', tweaks)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        projection = re.search(r'BananaMediaTweaks\.update\(BananaMediaTweaks\.State\((.*)\)\)\n', shared)
        self.assertIsNotNone(projection)
        for name in FIELDS:
            self.assertIn(f'{name}: settings.{name}', projection.group(1))

    def test_accelerated_upload_keeps_secret_chats_stock(self):
        source = read('submodules/TelegramCore/Sources/Network/MultipartUpload.swift')
        self.assertIn('} else if BananaMediaTweaks.accelerateUpload && encryptionKey == nil {\n'
                      '            // Fork (Donutgram accelerateUpload): more parts in flight; secret-chat uploads keep the stock 3.\n'
                      '            self.parallelParts = 8\n', source)

    def test_recent_sticker_limit_is_shared_by_every_writer(self):
        for path, count in [
            ('submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift', 1),
            ('submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift', 2),
            ('submodules/TelegramCore/Sources/State/SynchronizeRecentlyUsedMediaOperations.swift', 1),
        ]:
            source = read(path)
            self.assertEqual(source.count('removeTailIfCountExceeds: BananaMediaTweaks.recentStickersLimit)'), count, path)
            self.assertNotRegex(source, r'CloudRecentStickers.*removeTailIfCountExceeds: 20\)')

    def test_only_added_stickers_hides_trending_and_group_pack(self):
        source = read('submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentSignals.swift')
        self.assertIn('if !BananaMediaTweaks.onlyAddedStickers && dismissedTrendingStickerPacksSet != featuredStickerPacksSet {', source)
        self.assertEqual(source.count('if !BananaMediaTweaks.onlyAddedStickers, let peerSpecificPack = peerSpecificPack {'), 1)

    def test_media_pauses_on_interruption(self):
        manager = read('submodules/TelegramUI/Sources/MediaManager.swift')
        for name in ['willResignActiveNotification', 'didEnterBackgroundNotification', 'protectedDataWillBecomeUnavailableNotification']:
            self.assertIn('UIApplication.' + name, manager)
        self.assertIn('guard BananaMediaTweaks.autoPauseMediaInBackground else {', manager)
        self.assertIn('pauseForBackground(video: true, instantVideo: true)', manager)
        self.assertIn('NotificationCenter.default.removeObserver(observer)', manager)
        videos = read('submodules/TelegramUniversalVideoContent/Sources/UniversalVideoContentManager.swift')
        self.assertIn('public func pauseForBackground(video: Bool, instantVideo: Bool) {', videos)
        self.assertIn('holder.contentNode.pause()', videos)

    def test_double_tap_seek_step_is_configurable(self):
        source = read('submodules/GalleryUI/Sources/Items/UniversalVideoGalleryItem.swift')
        self.assertIn('let seekSeconds = BananaMediaTweaks.doubleTapSeekSeconds', source)
        self.assertIn('seekable, seekSeconds > 0 {', source)
        self.assertIn('self.footerContentNode.seekForward?(Double(seekSeconds))', source)
        self.assertIn('self.footerContentNode.seekBackward?(Double(seekSeconds))', source)

    def test_round_video_pinch_zoom_can_stay(self):
        source = read('submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift')
        self.assertRegex(source, r'if !BananaMediaTweaks\.staticRoundVideoZoom \{\n(?:\s*//.*\n)*\s*self\.setDisplayedZoom\(self\.zoomBeforePinch')

    def test_sticker_shape_rounds_stickers_but_not_emoji(self):
        plain = read('submodules/TelegramUI/Components/Chat/ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift')
        self.assertIn("telegramFile?.isSticker == true ? CGFloat(BananaMediaTweaks.stickerCornerRadius) : 0.0", plain)
        animated = read('submodules/TelegramUI/Components/Chat/ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift')
        self.assertIn("telegramFile?.isSticker == true && !isEmoji ? CGFloat(BananaMediaTweaks.stickerCornerRadius) : 0.0", animated)
        self.assertIn('animationNode.layer.cornerRadius = stickerCornerRadius', animated)
        history = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('            var stickerShape: Int32\n', history)
        self.assertIn('stickerShape: settings.stickerShape,\n', history)

    def test_extras_rows_are_listed_in_the_media_screen(self):
        source = read(CONTROLLER)
        self.assertIn('            [1750, 1751, 1752, 1753, 1754, 1755, 1756, 2021, 1757, 1758],\n', source)
        media = source[source.index('    case .media:\n        entries = ['):source.index('    case .profile:\n        entries = [')]
        for row in ['.designHeader(1750', '.appearanceToggle(1751', '.appearanceToggle(1752', '.intChoice(1753',
                    '.appearanceToggle(1754', '.intChoice(1755', '.appearanceToggle(1756', '.appearanceToggle(1757',
                    '.designFooter(1758']:
            self.assertIn(row, media)
        for name in ['onlyAddedStickers', 'infiniteRecentStickers', 'autoPauseMediaInBackground', 'staticRoundVideoZoom', 'accelerateUpload']:
            self.assertIn(f'\\.{name})', media)
        self.assertIn('keyPath = \\.stickerShape', source)
        self.assertIn('keyPath = \\.doubleTapSeekSeconds', source)
        self.assertIn('arguments.openIntChoice(id)', source)


if __name__ == '__main__':
    unittest.main()
