"""Donutgram commits of 2026-10-16, ported: gift sale Stars refresh, profile-music removal, editing during
slow mode, avatar date in the gallery footer, the story-camera swipe switch and "Jump to start" in the
avatar menu. Source-text assertions; the Swift is verified by the full Bazel build."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'


def regrouped(source):
    return source[source.index('private static let regroupedCategories'):source.index('private static let interfaceGroups')]


def category(source, focus):
    groups = regrouped(source)
    start = groups.index('(.%s, [' % focus)
    return groups[start:groups.index(']),', start)]


class GiftSaleStarsRefresh(unittest.TestCase):
    def test_stars_open_after_the_sheet_dismissed_and_balance_reloads_on_completion(self):
        source = read('submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift')
        start = source.index('title: presentationData.strings.Gift_Convert_Convert, action:')
        convert = source[start:source.index('parseMarkdown: true', start)]
        self.assertNotIn('Queue.mainQueue().after(2.5)', convert)
        self.assertIn('controller.dismissAnimated(completion: { [weak navigationController] in', convert)
        self.assertIn('startStandalone(completed: {\n                                    starsContext.load(force: true)', convert)
        self.assertIn('public func dismissAnimated(completion: (() -> Void)? = nil)', source)
        self.assertIn('fileprivate func completeDismissal()', source)
        self.assertEqual(source.count('controller.completeDismissal()'), 2)
        self.assertNotIn('controller.dismiss(completion: nil)', source[source.index('dismiss: { animated in'):])

    def test_profile_gifts_reload_stars_once_the_conversion_completed(self):
        core = read('submodules/TelegramCore/Sources/TelegramEngine/Payments/StarGifts.swift')
        self.assertIn('public func convertStarGift(reference: StarGiftReference, completion: (() -> Void)? = nil)', core)
        self.assertIn('func convertStarGift(reference: StarGiftReference, completion: (() -> Void)?)', core)
        self.assertIn('|> deliverOnMainQueue).startStrict(completed: {\n                completion?()', core)
        for path in ['submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift',
                     'submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/GiftsListView.swift']:
            source = read(path)
            self.assertIn('convertStarGift(reference: reference, completion: {', source, path)
            self.assertIn('starsContext?.load(force: true)', source, path)


class ProfileMusicRemoval(unittest.TestCase):
    def setUp(self):
        self.source = read('submodules/TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift')

    def test_last_track_is_decided_from_the_saved_music_context(self):
        self.assertIn('private func removeFromSavedMusic(file: FileMediaReference, dismissPlayer: Bool)', self.source)
        self.assertIn('state.dataState == .ready(canLoadMore: false)', self.source)
        self.assertIn('if dismissPlayer {', self.source)
        self.assertNotIn('self.historyNode.originalHistoryView?.entries.count == 1', self.source)

    def test_reorderable_list_does_not_dismiss_on_overscroll(self):
        start = self.source.index('self.historyNode.didEndScrollingWithOverscroll')
        block = self.source[start:self.source.index('self.requestDismiss()', start)]
        self.assertIn('case let .savedMusic(_, _, canReorder) = playlistLocation, canReorder', block)

    def test_menu_dismisses_before_removing(self):
        self.assertIn('c.dismiss(completion: { [weak self] in\n                                    self?.removeFromSavedMusic(file: fileReference)', self.source)


class EditingDuringSlowMode(unittest.TestCase):
    def test_slow_mode_does_not_block_saving_an_edit(self):
        panel = read('submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift')
        self.assertIn('if interfaceState.slowmodeState != nil && !isScheduledMessages && interfaceState.interfaceState.editMessage == nil {', panel)
        self.assertIn('presentationInterfaceState.slowmodeState != nil, presentationInterfaceState.interfaceState.editMessage == nil {', panel)
        self.assertIn('rightSlowModeInset.isZero && interfaceState.interfaceState.editMessage == nil {', panel)
        self.assertNotIn('interfaceState.editMessageState == nil) || interfaceState.inputTextPanelState.contextPlaceholder', panel)
        buttons = read('submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift')
        self.assertIn('if let slowmodeState = interfaceState.slowmodeState, interfaceState.interfaceState.editMessage == nil {', buttons)


class AvatarGalleryDate(unittest.TestCase):
    def test_date_sits_on_the_buttons_row_and_yields_to_main_photo_controls(self):
        source = read('submodules/PeerAvatarGalleryUI/Sources/AvatarGalleryItemFooterContentNode.swift')
        self.assertIn('import TelegramStringFormatting', source)
        self.assertIn('dateText = stringForFullDate(timestamp: date, strings: self.strings, dateTimeFormat: self.presentationData.dateTimeFormat)', source)
        self.assertIn('if !self.mainNode.isHidden || !self.setMainButton.isHidden {\n            dateText = nil', source)
        self.assertIn('y: controlsY + floor((44.0 - dateSize.height) / 2.0)', source)
        self.assertIn('"//submodules/TelegramStringFormatting:TelegramStringFormatting"', read('submodules/PeerAvatarGalleryUI/BUILD'))

    def test_profile_id_row_already_offers_copy_on_long_press(self):
        source = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift')
        start = source.index('AnyHashable("fork_profile_id")')
        row = source[start:source.index('}))', start)]
        self.assertIn('longTapAction: { sourceNode in\n            interaction.openPeerInfoContextMenu(.genericCopy(idText), sourceNode, nil)', row)


class StoryCameraSwipe(unittest.TestCase):
    def test_setting_defaults_off_and_round_trips(self):
        source = read(SETTINGS)
        self.assertIn('public var disableStoryCameraSwipe: Bool', source)
        self.assertIn('self.disableStoryCameraSwipe = false', source)
        self.assertIn('forKey: "disableStoryCameraSwipe") ?? false', source)
        self.assertIn('try container.encode(self.disableStoryCameraSwipe, forKey: "disableStoryCameraSwipe")', source)

    def test_chat_list_swipe_and_stories_row_pull_respect_it(self):
        node = read('submodules/ChatListUI/Sources/ChatListControllerNode.swift')
        self.assertEqual(node.count('!self.context.sharedContext.immediateForkExtrasSettings.disableStoryCameraSwipe'), 2)
        row = read('submodules/TelegramUI/Components/Stories/StoryPeerListComponent/Sources/StoryPeerListComponent.swift')
        self.assertIn('import TelegramUIPreferences', row)
        self.assertIn('return !component.context.sharedContext.immediateForkExtrasSettings.disableStoryCameraSwipe', row)
        self.assertIn('let willComposeOnRelease = composesOnPull && scrollView.contentOffset.x <= -70.0', row)
        self.assertIn('if composesOnPull && scrollView.isScrollEnabled && scrollView.isTracking', row)
        self.assertIn('if self.composesOnPull && scrollView.isScrollEnabled && scrollView.contentOffset.x <= -70.0', row)
        self.assertIn('self.scrollView.contentOffset.x < 0.0 && self.composesOnPull', row)
        self.assertIn('"//submodules/TelegramUIPreferences"', read('submodules/TelegramUI/Components/Stories/StoryPeerListComponent/BUILD'))

    def test_row_lives_in_the_chat_list_category(self):
        source = read(CONTROLLER)
        self.assertIn('.appearanceToggle(1790, russian ? "Отключить камеру по свайпу" : "No story camera on swipe", settings.disableStoryCameraSwipe, \\.disableStoryCameraSwipe)', source)
        self.assertIn('[1773, 1774, 1790]', category(source, 'chatList'))


class JumpToStart(unittest.TestCase):
    def test_setting_defaults_on_and_round_trips(self):
        source = read(SETTINGS)
        self.assertIn('public var jumpToStartInChatMenu: Bool', source)
        self.assertIn('self.jumpToStartInChatMenu = true', source)
        self.assertIn('forKey: "jumpToStartInChatMenu") ?? true', source)
        self.assertIn('try container.encode(self.jumpToStartInChatMenu, forKey: "jumpToStartInChatMenu")', source)

    def test_avatar_menus_of_chat_and_topic_offer_it(self):
        item = read('submodules/TelegramUI/Sources/ChatController+BananaJumpToStart.swift')
        self.assertIn('guard self.context.sharedContext.immediateForkExtrasSettings.jumpToStartInChatMenu else', item)
        self.assertIn('self?.scrollToStartOfHistory()', item)
        self.assertIn('func scrollToStartOfHistory()', read('submodules/TelegramUI/Sources/ChatControllerScrollToPointInHistory.swift'))
        controller = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertEqual(controller.count('if let jumpToStartItem = strongSelf.bananaJumpToStartContextMenuItem() {'), 2)
        replyThread = controller.index('case let .replyThread(message):', controller.index('avatarNode.contextAction'))
        self.assertGreater(controller.index('bananaJumpToStartContextMenuItem', replyThread), replyThread)

    def test_row_lives_in_the_messages_category(self):
        source = read(CONTROLLER)
        self.assertIn('.appearanceToggle(1791, russian ? "«В начало чата» в меню аватарки" : "Jump to start in the avatar menu", settings.jumpToStartInChatMenu, \\.jumpToStartInChatMenu)', source)
        self.assertIn('[1720, 1711, 1703, 1713, 1716, 1719, 1717, 1718, 1791]', category(source, 'messages'))

    def test_new_ids_are_unique(self):
        source = read(CONTROLLER)
        for value in ('1790', '1791'):
            self.assertEqual(len(re.findall(r'\.appearanceToggle\(%s,' % value, source)), 1, value)


if __name__ == '__main__':
    unittest.main()
