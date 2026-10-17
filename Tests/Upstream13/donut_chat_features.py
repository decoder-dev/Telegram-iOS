"""Donutgram chat-appearance switches ported into Extras: settings, runtime projection and hooks."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text(encoding='utf-8')

SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
ARENA = 'submodules/TelegramCore/Sources/Arena/ArenaSettings.swift'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
CHAT = 'submodules/TelegramUI/Components/Chat/'
NAMES = ['commaAfterMention', 'disableColoredReplies', 'hideStickerChecks', 'mentionAvatars', 'relativeLastSeen',
         'disableCustomBackgrounds', 'channelBottomDiscuss', 'hideChannelBottomButton', 'hideShareButton']
ROWS = {1710: 'commaAfterMention', 1711: 'disableColoredReplies', 1712: 'hideStickerChecks', 1713: 'mentionAvatars',
        1714: 'relativeLastSeen', 1716: 'disableCustomBackgrounds', 1717: 'channelBottomDiscuss',
        1718: 'hideChannelBottomButton', 1719: 'hideShareButton'}


class DonutChatFeatures(unittest.TestCase):
    def test_settings_default_off_and_persist(self):
        source = read(SETTINGS)
        for name in NAMES:
            self.assertIn('public var %s: Bool' % name, source)
            self.assertIn('self.%s = false' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_runtime_projection(self):
        source = read(SETTINGS)
        self.assertIn('public func applyForkChatAppearanceSettings(_ settings: ForkExtrasSettings)', source)
        self.assertIn('ArenaSettings.shared.setChatAppearance(', source)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('applyForkChatAppearanceSettings(settings)', shared)
        self.assertIn('relativeLastSeen: settings.relativeLastSeen', shared)
        history = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('chatAppearance: [settings.disableColoredReplies, settings.hideStickerChecks, settings.mentionAvatars, settings.hideShareButton]', history)
        self.assertEqual(history.count('applyForkChatAppearanceSettings(settings)'), 1)

    def test_comma_after_mention(self):
        arena = read(ARENA)
        self.assertIn('return self.locked { self.commaAfterMentionValue && !isBot ? ", " : " " }', arena)
        text_format = read('submodules/ChatPresentationInterfaceState/Sources/ChatTextFormat.swift')
        self.assertIn('let mentionSuffix = ArenaSettings.shared.mentionSuffix(isBot: isBot)', text_format)
        self.assertIn('let replacementText = "@\\(addressName)\\(mentionSuffix)"', text_format)
        panel = read('submodules/TelegramUI/Sources/MentionChatInputContextPanelNode.swift')
        self.assertIn('let mentionSuffix = ArenaSettings.shared.mentionSuffix(isBot: isBot)', panel)
        self.assertIn('replacingFlatRange(range, with: addressName + mentionSuffix)', panel)
        self.assertIn('replacementText.append(NSAttributedString(string: mentionSuffix))', panel)

    def test_disable_colored_replies_clears_the_colour_bit(self):
        arena = read(ARENA)
        self.assertIn('if self.disableColoredRepliesValue { options &= ~1 }', arena)
        reply = read(CHAT + 'ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift')
        self.assertIn('switch replyOptions & 1 != 0 ? author?.nameColor : nil {', reply)

    def test_hide_sticker_checks(self):
        status = read(CHAT + 'ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift')
        self.assertIn('hideSentStatus: Bool = false', status)
        self.assertIn('if hideStatus || arguments.hideSentStatus {', status)
        for path in ('ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift',
                     'ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift'):
            self.assertIn('hideSentStatus: telegramFile?.isSticker == true && !isEmoji && ArenaSettings.shared.hidesStickerChecks', read(CHAT + path))

    def test_mention_avatars_are_wired_and_gated(self):
        node = read(CHAT + 'ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift')
        self.assertIn('if ArenaSettings.shared.showsMentionAvatars, entitiesAppliedText.length == (rawText as NSString).length {', node)
        self.assertIn('attributedText = textWithMentionAvatars(entitiesAppliedText, entities: entities, peers: item.message.peers.map { EnginePeer($0.1) })', node)

    def test_relative_last_seen(self):
        display = read('submodules/TelegramPresentationData/Sources/BananaPresenceDisplay.swift')
        self.assertIn('public init(exactLastSeen: Bool, showsOfflineDot: Bool, relativeLastSeen: Bool = false)', display)
        formatting = read('submodules/TelegramStringFormatting/Sources/PresenceStrings.swift')
        self.assertIn('let expanded = (expanded && !presenceDisplay.relativeLastSeen) || presenceDisplay.exactLastSeen', formatting)

    def test_disable_custom_backgrounds(self):
        controller = read('submodules/TelegramUI/Sources/ChatController.swift')
        hook = controller.index('if ArenaSettings.shared.disablesCustomBackgrounds {')
        block = controller[hook:hook + 200]
        self.assertIn('chatWallpaper = nil', block)
        self.assertIn('chatTheme = nil', block)
        # Applied before the theme preview, so a previewed theme still shows.
        self.assertLess(controller.index('if let chatThemePreview {', hook) - hook, 600)

    def test_channel_bottom_button(self):
        panels = read('submodules/TelegramUI/Sources/ChatInterfaceStateInputPanels.swift')
        self.assertIn('if isMember, case .peer = chatPresentationInterfaceState.chatLocation, ArenaSettings.shared.hidesChannelBottomButton {', panels)
        panel = read(CHAT + 'ChatChannelSubscriberInputPanelNode/Sources/ChatChannelSubscriberInputPanelNode.swift')
        self.assertIn('return (strings.PeerInfo_ButtonDiscuss, theme.chat.inputPanel.panelControlAccentColor)', panel)
        self.assertIn('info.flags.contains(.hasDiscussionGroup), ArenaSettings.shared.channelBottomButtonDiscusses {', panel)
        self.assertIn('TelegramEngine.EngineData.Item.Peer.LinkedDiscussionPeerId(id: peer.id)', panel)
        self.assertIn('self.interfaceInteraction?.navigateToChat(discussionPeerId)', panel)

    def test_hide_share_button(self):
        self.assertIn('if ArenaSettings.shared.hidesShareButton || isEphemeralMessage {',
                      read(CHAT + 'ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift'))
        for path in ('ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift',
                     'ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift',
                     'ChatMessageInstantVideoItemNode/Sources/ChatMessageInstantVideoItemNode.swift'):
            self.assertIn('if ArenaSettings.shared.hidesShareButton {', read(CHAT + path))

    def test_extras_rows_are_listed(self):
        controller = read(CONTROLLER)
        for row, name in ROWS.items():
            self.assertRegex(controller, r'\.appearanceToggle\(%d, [^\n]*settings\.%s, \\\.%s\)' % (row, name, name))
        self.assertIn('.designHeader(1720, ', controller)
        self.assertIn('[1720, 1711, 1703, 1713, 1716, 1719, 1717, 1718, 1791]', controller)
        self.assertIn('[55, 56, 1551, 1714, 1552, 1543, 58]', controller)


if __name__ == '__main__':
    unittest.main()
