"""Donutgram commits of 2026-10-19..21, ported: service message filter and confirmations (#109), round-video
sound for headset microphones (#114) and the profile header with an empty name (#116). #105, #106, #108 and #110
are on origin/codex/donutgram-oct18; #111 and #112 have no counterpart here. Source-text assertions; the Swift is
verified by the full Bazel build."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
ROWS = {
    1940: 'hideServiceMessages',
    1941: 'confirmReactionsInUnjoinedChats',
    1942: 'confirmTelegramLinks',
    1943: 'confirmChatPreviewEntry',
}


def regrouped(source):
    return source[source.index('private static let regroupedCategories'):source.index('private static let interfaceGroups')]


def category(source, focus):
    groups = regrouped(source)
    start = groups.index('(.%s, [' % focus)
    return groups[start:groups.index(']),', start)]


class ServiceMessageSettings(unittest.TestCase):
    def test_switches_default_off_and_round_trip(self):
        source = read(SETTINGS)
        for name in ROWS.values():
            self.assertIn('public var %s: Bool' % name, source)
            self.assertIn('self.%s = false' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_rows_are_unique_and_grouped_under_messages(self):
        source = read(CONTROLLER)
        for row, name in ROWS.items():
            self.assertEqual(source.count('.appearanceToggle(%d,' % row), 1)
            self.assertIn('settings.%s, \\.%s)' % (name, name), source)
        self.assertIn('[1940, 1941, 1942, 1943]', category(source, 'messages'))

    def test_filter_only_hides_membership_and_chat_edits(self):
        source = read('submodules/TelegramCore/Sources/Arena/ForkServiceMessageFilter.swift')
        self.assertIn('public func forkIsHideableServiceMessage(_ message: Message) -> Bool', source)
        for case in ['.addedMembers', '.removedMembers', '.peerJoined', '.titleUpdated', '.pinnedMessageUpdated',
                     '.pollOptionAppended', '.todoCompletions']:
            self.assertIn(case, source)
        for case in ['.phoneCall', '.starGift', '.giftPremium', '.giveawayLaunched', '.paymentSent', '.suggestedPostSuccess']:
            self.assertNotIn(case, source)
        self.assertIn('default:\n            return false', source)

    def test_history_counts_hidden_messages_with_the_shadow_banned(self):
        entries = read('submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift')
        self.assertIn('    hideServiceMessages: Bool,\n', entries)
        hidden = entries.index('if hideServiceMessages && forkIsHideableServiceMessage(message) {')
        self.assertIn('ArenaHiddenCount += 1', entries[hidden:hidden + 200])
        self.assertLess(hidden, entries.index('if let shadowBan, TelegramShadowBan.isHidden'))
        self.assertIn('if let joinMessage, !(hideServiceMessages && forkIsHideableServiceMessage(joinMessage)) {', entries)

    def test_open_chat_rebuilds_when_the_switch_changes(self):
        node = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('var hideServiceMessages: Bool', node)
        self.assertIn('ForkServiceMessageSettings.hidden = settings.hideServiceMessages', node)
        self.assertIn('hideServiceMessages: settings.hideServiceMessages,', node)
        self.assertIn('hideServiceMessages: mode == .bubbles && ForkServiceMessageSettings.hidden,', node)


class Confirmations(unittest.TestCase):
    def test_telegram_link_check_keeps_login_part_logic(self):
        source = read('submodules/UrlWhitelist/Sources/UrlWhitelist.swift')
        self.assertIn('public func isTelegramLinkUrl(_ url: String) -> Bool', source)
        self.assertIn('["t.me", "telegram.me", "telegram.dog"]', source)
        self.assertIn('canonicalExternalUrl(from: url)', source[source.index('func isTelegramLinkUrl'):])
        self.assertIn('public func externalUrlWithLoginPart(_ url: String) -> URL?', source)
        self.assertIn('public func canonicalExternalUrl(from url: String) -> URL?', source)

    def test_links_in_messages_bios_and_other_apps_ask(self):
        user = read('submodules/TelegramUI/Components/OpenUserGeneratedUrl/Sources/OpenUserGeneratedUrl.swift')
        self.assertIn('immediateForkExtrasSettings.confirmTelegramLinks && isTelegramLinkUrl(url)', user)
        self.assertIn('import TelegramUIPreferences', user)
        self.assertIn('TelegramUIPreferences', read('submodules/TelegramUI/Components/OpenUserGeneratedUrl/BUILD'))
        text = read('submodules/TelegramUI/Sources/TextLinkHandling.swift')
        self.assertIn('peerId != nil && context.sharedContext.immediateForkExtrasSettings.confirmTelegramLinks && isTelegramLinkUrl(url)', text)
        opener = read('submodules/TelegramUI/Sources/OpenUrl.swift')
        ask = opener.index('immediateForkExtrasSettings.confirmTelegramLinks, case .external = urlContext')
        self.assertLess(ask, opener.index('if let loginPartUrl = externalUrlWithLoginPart(url), !consumeLoginPartConfirmation(loginPartUrl)'))

    def test_reaction_question_is_asked_only_when_adding_after_the_checks(self):
        helper = read('submodules/TelegramUI/Sources/ChatController+ForkConfirmations.swift')
        self.assertIn('guard self.context.sharedContext.immediateForkExtrasSettings.confirmReactionsInUnjoinedChats', helper)
        self.assertIn('channel.participationStatus != .member', helper)
        menu = read('submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift')
        ask = menu.index('removedReaction == nil && self.forkReactionNeedsConfirmation(chosenReaction)')
        self.assertLess(menu.index('self?.displaySendReactionRestrictedToast()'), ask)
        self.assertLess(menu.index('controller?.premiumReactionsSelected?()'), ask)
        self.assertIn('reactions: confirmedReactions, isLarge: isLarge', menu[ask:ask + 2500])
        controller = read('submodules/TelegramUI/Sources/ChatController.swift')
        ask = controller.index('removedReaction == nil && strongSelf.forkReactionNeedsConfirmation(chosenReaction)')
        self.assertLess(controller.index('itemNode.openMessageContextMenu()'), ask)

    def test_preview_asks_on_the_tap_and_stays_open_on_no(self):
        helper = read('submodules/TelegramUI/Sources/ChatController+ForkConfirmations.swift')
        self.assertIn('func openFromPreviewing()', helper)
        self.assertIn('case .messageOptions = subject', helper)
        self.assertIn('self.presentInGlobalOverlay(alert)', helper)
        self.assertIn('TextAlertAction(type: .genericAction, title: presentationData.strings.Common_No, action: {})', helper)
        self.assertIn('weak var forkPreviewEntryAlert: ViewController?', read('submodules/TelegramUI/Sources/ChatController.swift'))
        self.assertIn('self.controller?.openFromPreviewing()', read('submodules/TelegramUI/Sources/ChatControllerNode.swift'))


class RoundVideoAudio(unittest.TestCase):
    def test_bit_rate_comes_from_the_encoder_not_a_fixed_64k(self):
        helper = read('submodules/Camera/CameraNeo/Sources/RoundVideoAudioSettings.swift')
        self.assertIn('kAudioConverterApplicableEncodeBitRates', helper)
        self.assertIn('func roundVideoAudioBitRate(applicable: [ClosedRange<Int>]) -> Int?', helper)
        self.assertIn('func roundVideoAudioSettings(', helper)
        recorder = read('submodules/Camera/CameraNeo/Sources/VideoRecorder.swift')
        self.assertIn('roundVideoAudioSettings(formatDescription: formatDescription', recorder)
        self.assertNotIn('AVEncoderBitRateKey', recorder)


class ProfileHeaderEmptyName(unittest.TestCase):
    def test_status_and_rating_are_laid_out_even_without_a_name(self):
        source = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift')
        self.assertNotIn('if !titleSize.width.isZero && !titleSize.height.isZero {', source)
        self.assertIn('let titleScale = titleFrame.height.isZero ? neutralTitleScale :', source)
        self.assertIn('let subtitleScale = subtitleFrame.height.isZero ? neutralSubtitleScale :', source)


if __name__ == '__main__':
    unittest.main()
