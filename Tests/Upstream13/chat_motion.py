"""Glass chat pills (Extras › Appearance) and the always-on iOS Messages look: motion, unread dots, plain dates,
the delivery receipt. Source-text checks; the look is checked in simulator QA ("glass-" shots and the chats)."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
ARENA = 'submodules/TelegramCore/Sources/Arena/ArenaSettings.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
HISTORY = 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift'
NAV_BACKGROUND = 'submodules/Display/Source/NavigationBackgroundView.swift'
MOTION = 'submodules/Display/Source/ChatBubbleMotion.swift'
CHAT = 'submodules/TelegramUI/Components/Chat/'
FIELDS = ['glassChatElements']
MOTION_KEYS = ['springyScrolling', 'messagePopIn', 'messageHaptics']


class Settings(unittest.TestCase):
    def test_fields_are_off_by_default_and_round_trip(self):
        source = read(SETTINGS)
        for name in FIELDS:
            self.assertIn('    public var %s: Bool\n' % name, source)
            self.assertIn('        self.%s = false\n' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_projection_reaches_the_chat(self):
        settings = read(SETTINGS)
        apply = settings[settings.index('public func applyForkChatAppearanceSettings('):]
        apply = apply[:apply.index('\n}\n')]
        self.assertIn('ArenaSettings.shared.setGlassChatElements(settings.glassChatElements)', apply)
        arena = read(ARENA)
        self.assertIn('public func setGlassChatElements(_ enabled: Bool)', arena)
        self.assertIn('public var glassChatElementsEnabled: Bool', arena)
        # Motion is part of the Messages look: no setting, no flag.
        for key in MOTION_KEYS:
            self.assertNotIn(key, read(SETTINGS))
            self.assertNotIn(key, arena)
        # Open chats lay the pills out again when the glass switch changes.
        history = read(HISTORY)
        self.assertIn('var glassChatElements: Bool', history)
        self.assertIn('glassChatElements: settings.glassChatElements,', history)

    def test_rows_live_on_the_appearance_screen(self):
        source = read(EXTRAS)
        appearance = re.search(r'\(\.appearance, \[(.*?)\]\),\n', source).group(1)
        self.assertTrue(appearance.endswith('[1907, 1908, 1909]'), appearance)
        self.assertRegex(source, r'\.appearanceToggle\(1908, [^\n]*settings\.glassChatElements, \\\.glassChatElements\)')
        for row in ['1915', '1916', '1917', '1918', '1919']:
            self.assertNotIn('(%s,' % row, source)


class GlassPills(unittest.TestCase):
    def test_background_node_has_an_opt_in_glass_mode(self):
        source = read(NAV_BACKGROUND)
        self.assertIn('public func setChatGlass(_ enabled: Bool) -> Bool', source)
        self.assertIn('UIGlassEffect(style: .regular)', source)
        # Reduce Transparency keeps the solid pill.
        self.assertIn('return !UIAccessibility.isReduceTransparencyEnabled', source)
        # A blur view made while the glass is on stays hidden under it.
        self.assertIn('if let chatGlassView = self.chatGlassView {\n                    effectView.isHidden = true', source)

    def test_pills_turn_the_glass_on(self):
        for path in ['ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift',
                     'ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift',
                     'ChatMessageShareButton/Sources/ChatMessageShareButton.swift']:
            self.assertIn('setChatGlass(ArenaSettings.shared.glassChatElementsEnabled)', read(CHAT + path), path)
        header = read(CHAT + 'ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift')
        # The date and the peer pill, not the dashed separator.
        self.assertEqual(header.count('let isGlass = self.backgroundNode.setChatGlass('), 2)
        self.assertIn('self.backgroundContent?.isHidden = isGlass', header)

    def test_service_messages_and_bot_buttons_have_their_own_glass(self):
        service = read(CHAT + 'ChatMessageActionBubbleContentNode/Sources/ChatMessageActionBubbleContentNode.swift')
        self.assertIn('private func updateServiceGlass(frame: CGRect?, maskImage: UIImage?, cornerRadius: CGFloat, tint: UIColor)', service)
        self.assertIn('maskImage: labelRects.count == 1 ? nil : image,', service)
        # A suggested post keeps the stock background.
        self.assertIn('strongSelf.updateServiceGlass(frame: nil, maskImage: nil, cornerRadius: 0.0, tint: .clear)', service)
        buttons = read(CHAT + 'ChatMessageActionButtonsNode/Sources/ChatMessageActionButtonsNode.swift')
        self.assertIn('node.updateGlass(size: CGSize(width: max(0.0, width), height: 42.0), tint: bubbleVariableColor(variableColor: messageTheme.actionButtonsFillColor, wallpaper: theme.wallpaper))', buttons)
        for source in (service, buttons):
            self.assertIn('ArenaSettings.shared.glassChatElementsEnabled, NavigationBackgroundNode.isChatGlassAvailable', source)


class Motion(unittest.TestCase):
    def test_nothing_moves_with_reduce_motion(self):
        source = read(MOTION)
        self.assertIn('return !UIAccessibility.isReduceMotionEnabled', source)
        for function in ['public static func popIn(', 'public static func landingSquash(']:
            body = source[source.index(function):]
            body = body[:body.index('\n    }\n')]
            self.assertIn('guard self.allowsMotion else', body)
        springy = source[source.index('public func contentMoved('):]
        self.assertIn('guard ChatBubbleMotion.allowsMotion', springy[:springy.index('\n    }\n')])

    def test_haptics_are_throttled(self):
        source = read(MOTION)
        self.assertIn('if timestamp - self.lastHapticTimestamp < 0.25 {', source)

    def test_springy_scrolling_keeps_the_items_own_transform(self):
        source = read(MOTION)
        # Selection mode shifts items with sublayerTransform; the springs draw on top of it and give it back.
        self.assertIn('self.baseTransform = layer.sublayerTransform', source)
        self.assertIn('state.layer?.sublayerTransform = state.baseTransform', source)
        self.assertIn('CATransform3DTranslate(state.baseTransform, 0.0, offset, 0.0)', source)

    def test_history_feeds_the_springs_only_from_user_scrolling(self):
        history = read(HISTORY)
        update = history[history.index('private func updateSpringyScroll('):]
        update = update[:update.index('\n    }\n')]
        self.assertIn('guard isTracking, isImmediate, self.controllerInteraction.selectionState == nil else {', update)
        self.assertIn('springyScroll.reset()', update)
        self.assertIn('springyScroll.contentMoved(by: -offset, items: items)', update)
        # Whoever sets didScrollWithOffset still gets every offset.
        self.assertIn('self.didScrollWithOffsetValue?(offset, transition, itemNode, isTracking)', history)
        self.assertIn('set { self.didScrollWithOffsetValue = newValue }', history)
        self.assertIn('springyScroll.beganDragging(touchY: point.y)', history)

    def test_pop_in_and_haptics_hooks(self):
        bubble = read(CHAT + 'ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift')
        insertion = bubble[bubble.index('override public func animateInsertion('):]
        insertion = insertion[:insertion.index('\n    }\n')]
        self.assertIn('item.message.effectivelyIncoming(item.context.account.peerId)', insertion)
        self.assertIn('ChatBubbleMotion.popIn(layer: self.mainContextSourceNode.layer, anchor: CGPoint(x: bubbleFrame.minX, y: bubbleFrame.maxY))', insertion)
        self.assertIn('ChatBubbleMotion.receivedHaptic()', insertion)
        transition = read('submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift')
        self.assertIn('ChatBubbleMotion.landingSquash(layer: contextSourceNode.layer)', transition)
        self.assertIn('ChatBubbleMotion.sentHaptic()', transition)


class MessagesLook(unittest.TestCase):
    """The iOS Messages look is how the app looks: there is no switch and nothing turns it off."""

    def test_there_is_no_switch(self):
        for path in [SETTINGS, EXTRAS, 'submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift', 'submodules/TelegramUI/Sources/UITestScreens.swift']:
            self.assertNotIn('messagesStyle:', read(path), path)
            self.assertNotIn('settings.messagesStyle', read(path), path)
            self.assertNotIn('.messagesStyle', read(path), path)

    def test_chat_list_row_has_a_dot_and_a_chevron(self):
        row = read('submodules/ChatListUI/Sources/Node/ChatListItem.swift')
        self.assertIn('if useChatListLayout, !item.useCommunityViewLayout, !isPeerGroup, unreadCount.unread {', row)
        dot = row[row.index('var messagesStyleUnreadDotColor: UIColor?\n            if useChatListLayout'):]
        dot = dot[:dot.index('\n            }\n')]
        self.assertIn('currentBadgeBackgroundImage = nil', dot)
        self.assertIn('unreadCount.muted ? theme.unreadBadgeInactiveBackgroundColor : theme.unreadBadgeActiveBackgroundColor', dot)
        self.assertIn('avatarFrame.minX - avatarLeftEdgeInset * 0.5 - dotDiameter * 0.5', row)
        # The content is narrowed by the chevron, so the date, checks and badges move left together.
        self.assertIn('- editingOffset - messagesStyleChevronWidth\n', row)
        self.assertIn('if hasCustomListDisclosure || messagesStyleChevronWidth > 0.0 {', row)

    def test_dates_are_plain_on_a_plain_background(self):
        header = read(CHAT + 'ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift')
        self.assertIn('if !self.presentationData.theme.wallpaper.hasWallpaper {\n            self.backgroundNode.isHidden = true', header)
        self.assertIn('} else if self.backgroundContent == nil {\n            self.backgroundNode.isHidden = false', header)

    def test_receipt_under_the_newest_own_message(self):
        item = read(CHAT + 'ChatMessageItem/Sources/ChatMessageItem.swift')
        self.assertIn('var forkIsBottomMost: Bool { get }', item)
        impl = read(CHAT + 'ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift')
        self.assertIn('let below = isRotated ? neighbors.previous : neighbors.next', impl)
        # Both layout paths refresh it from the neighbours they lay out with.
        self.assertEqual(impl.count('self.updateForkIsBottomMost(neighbors: neighbors, isRotated:'), 2)
        bubble = read(CHAT + 'ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift')
        self.assertIn('if !incoming, item.forkIsBottomMost, !item.failed, case .peer = item.chatLocation, item.message.id.peerId != item.context.account.peerId', bubble)
        for word in ['"Прочитано"', '"Доставлено"', '"Read"', '"Delivered"']:
            self.assertIn(word, bubble)
        self.assertIn('layoutSize.height += ChatMessageBubbleItemNode.messagesStyleReceiptHeight', bubble)
        self.assertIn('selfReference.value?.updateMessagesStyleReceipt(', bubble)


class TypingBubble(unittest.TestCase):
    def test_bubble_node(self):
        node = read('submodules/TelegramUI/Sources/ChatTypingBubbleNode.swift')
        self.assertIn('final class ChatTypingBubbleNode: ASDisplayNode', node)
        # Three dots that rise in turn; still with Reduce Motion.
        self.assertIn('for _ in 0 ..< 3 {', node)
        self.assertIn('group.repeatCount = .infinity', node)
        self.assertIn('guard ChatBubbleMotion.allowsMotion else {', node)
        # The incoming bubble colour of the theme, so it matches the other side's messages.
        self.assertIn('theme.chat.message.incoming.bubble', node)

    def test_chat_makes_room_and_scrolls_it(self):
        controller = read('submodules/TelegramUI/Sources/ChatControllerNode.swift')
        self.assertIn('listInsets.top += ChatTypingBubbleNode.reservedHeight', controller)
        self.assertIn('self.updateTypingBubbleLayout(contentBounds: contentBounds, bottomInset: typingBubbleBottomInset, layout: layout, transition: transition)', controller)
        self.assertIn('node.frame = baseFrame.offsetBy(dx: 0.0, dy: self.typingBubbleScrollOffset)', controller)
        load = read('submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift')
        self.assertIn('strongSelf.chatDisplayNode.updateTypingBubble(isVisible: displayActivities.contains(where: { item in', load)
        self.assertIn('strongSelf.chatDisplayNode.updateTypingBubbleScrollOffset(value)', load)


class PinnedGrid(unittest.TestCase):
    def test_pinned_rows_fold_into_one_grid_entry(self):
        entries = read('submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift')
        self.assertIn('case PinnedGrid(index: EngineChatList.Item.Index, peers: [ChatListPinnedGridPeer], presentationData: ChatListPresentationData)', entries)
        fold = entries[entries.index('private func foldPinnedChatsIntoGrid('):]
        fold = fold[:fold.index('\n}\n')]
        # Main list only, and never while editing: pinned rows are reordered there.
        self.assertIn('guard case .chatList = mode, case .chatList(groupId: .root) = chatListLocation, !state.editing else {', fold)
        self.assertIn('index.pinningIndex != nil, peerEntry.promoInfo == nil', fold)
        self.assertIn('return (foldPinnedChatsIntoGrid(result, state: state, mode: mode, chatListLocation: chatListLocation, accountPeerId: accountPeerId), view.isLoading)', entries)

    def test_grid_item_keeps_the_pinned_actions(self):
        grid = read('submodules/ChatListUI/Sources/Node/ChatListPinnedGridItem.swift')
        self.assertIn('item.interaction.peerSelected(gridPeer.peer, nil, nil, nil, false)', grid)
        self.assertIn('interaction.setItemPinned(.peer(peerId), false)', grid)
        self.assertIn('interaction.setPeerMuted(peerId, !gridPeer.isMuted)', grid)
        self.assertIn('static let columns = 3', grid)
        self.assertIn('overrideImage: gridPeer.isSavedMessages ? .savedMessagesIcon : nil', grid)
        node = read('submodules/ChatListUI/Sources/Node/ChatListNode.swift')
        self.assertEqual(node.count('item: ChatListPinnedGridItem(context: context, presentationData: entryPresentationData, peers: peers, interaction: nodeInteraction)'), 2)


class RowTyping(unittest.TestCase):
    def test_one_to_one_typing_is_a_dots_bubble(self):
        node = read('submodules/ChatListUI/Sources/Node/ChatListTypingNode.swift')
        self.assertIn('if activities.count == 1, activities[0].0.id == peerId, case .typingText = activities[0].1 {', node)
        self.assertIn('if !activities.isEmpty && !showsTypingBubble {', node)
        # Groups keep the text that says who types.
        self.assertIn('strings.DialogList_SingleTypingSuffix(peerTitle)', node)
        self.assertIn('guard !UIAccessibility.isReduceMotionEnabled else {', node)

    def test_there_is_no_undo_send(self):
        self.assertNotIn('Undo Send', read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift'))


class Header(unittest.TestCase):
    def test_chevron_after_a_chat_name(self):
        title = read('submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift')
        self.assertIn('if case let .peer(_, _, _, _, isScheduledMessages, _, customMessageCount, _, isEnabled) = component.content, isEnabled, !isScheduledMessages, customMessageCount == nil {', title)
        self.assertIn('UIImage(systemName: "chevron.right"', title)
        self.assertIn('titleRightIconsWidth += disclosureSize.width + disclosureSpacing', title)


if __name__ == '__main__':
    unittest.main()
