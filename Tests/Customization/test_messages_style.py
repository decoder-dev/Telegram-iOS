"""Persistent Messages geometry and production integration contracts; no application build."""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def declaration(source, marker):
    start = source.index(marker)
    return source[start:source.index('\n}', start) + 2]


class MessagesStyleTests(unittest.TestCase):
    def test_all_fork_palette_calls_follow_production_argument_order(self):
        # Parsing succeeds with reordered named arguments; Swift type checking rejects them.
        # Check every nested update against the actual API, before an expensive IPA build.
        def labels(source, start):
            depth, index, begin = 1, start, start
            quoted = escaped = False
            arguments = []
            while depth:
                char = source[index]
                if quoted:
                    if escaped:
                        escaped = False
                    elif char == chr(92):
                        escaped = True
                    elif char == '"':
                        quoted = False
                elif char == '"':
                    quoted = True
                elif char in '([{':
                    depth += 1
                elif char in ')]}':
                    depth -= 1
                elif char == ',' and depth == 1:
                    arguments.append(source[begin:index])
                    begin = index + 1
                index += 1
            arguments.append(source[begin:index - 1])
            return [re.match(r'\s*(\w+)\s*:', argument).group(1) for argument in arguments]

        api = read('submodules/TelegramPresentationData/Sources/PresentationTheme.swift')
        signatures = [labels(api, match.end()) for match in re.finditer(r'func withUpdated\(', api)]
        palette = read('submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift')
        palette = palette.split('public func customizePresentationTheme', 1)[0]
        calls = list(re.finditer(r'([\w.]+)\.withUpdated\(', palette))
        self.assertGreaterEqual(len(calls), 38)
        for call in calls:
            actual = labels(palette, call.end())
            candidates = [signature for signature in signatures if set(actual) <= set(signature)]
            self.assertTrue(candidates, 'Unknown update arguments: ' + call.group(1))
            self.assertTrue(any([signature.index(label) for label in actual] == sorted(signature.index(label) for label in actual)
                                for signature in candidates), 'Reordered update arguments: ' + call.group(1))

    def test_modern_and_legacy_sections_share_geometry(self):
        modern = read('submodules/TelegramUI/Components/ListSectionComponent/Sources/ListSectionComponent.swift')
        self.assertEqual(modern.count('configuration.theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius :'), 2)
        self.assertIn('case .plain:\n            cornerRadius = 0.0', modern)
        legacy = read('submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesItemList.swift')
        self.assertIn('theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius :', legacy)
        buttons = read('submodules/SolidRoundedButtonNode/Sources/SolidRoundedButtonNode.swift')
        self.assertEqual(buttons.count('return self.theme.resolvedCornerRadius(self.requestedCornerRadius, height: self.buttonHeight)'), 2)
        self.assertIn('maximumCornerRadius: self.maximumCornerRadius)', buttons)

    def test_independent_screen_cards_update_their_style_when_reused(self):
        for path in ('StorageUsageScreen/Sources/DataCategoriesComponent.swift', 'TextProcessingScreen/Sources/TextProcessingTranslateContentComponent.swift', 'SendInviteLinkScreen/Sources/SendInviteLinkScreen.swift', 'ChatFolderLinkPreviewScreen/Sources/ChatFolderLinkPreviewScreen.swift', 'ListSwitchItemComponent/Sources/ListSwitchItemComponent.swift', 'PeerAllowedReactionsScreen/Sources/EmojiListInputComponent.swift', 'Gifts/GiftViewScreen/Sources/GiftAuctionActiveBidsScreen.swift'):
            source = read('submodules/TelegramUI/Components/' + path)
            self.assertIn('component.theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius : 26.0', source, path)
        share = read('submodules/TelegramUI/Components/ShareWithPeersScreen/Sources/ShareWithPeersScreen.swift')
        self.assertIn('environment.theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius : 26.0', share)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; runs in macOS CI')
    def test_production_button_theme_geometry_and_copy(self):
        source = read('submodules/SolidRoundedButtonNode/Sources/SolidRoundedButtonNode.swift')
        fixture = 'import Foundation\npublic typealias UIColor = Int\n' + declaration(source, 'public final class SolidRoundedButtonTheme:')
        fixture += '''
let original = SolidRoundedButtonTheme(backgroundColor: 1, foregroundColor: 2)
let messages = SolidRoundedButtonTheme(backgroundColor: 1, foregroundColor: 2, maximumCornerRadius: 14)
precondition(original != messages)
let copy = messages.withUpdated(disabledBackgroundColor: 3, disabledForegroundColor: 4)
precondition(copy.maximumCornerRadius == 14 && copy.foregroundColor == 2 && copy.backgroundColor == 1)
for requested: CGFloat in [-20, 0, 8, 14, 26, 50] {
    for height: CGFloat in [-10, 0, 16, 44, 100] {
        precondition(original.resolvedCornerRadius(requested, height: height) == requested)
        let radius = messages.resolvedCornerRadius(requested, height: height)
        precondition(radius >= 0 && radius <= 14 && radius <= max(0, height / 2))
        precondition(copy.resolvedCornerRadius(requested, height: height) == radius)
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'main.swift'
            path.write_text(fixture, encoding='utf-8')
            subprocess.run(['swift', '-swift-version', '5', str(path)], check=True, capture_output=True, text=True, timeout=60)

    def test_shared_section_switch_preserves_callbacks_and_theme_changes(self):
        source = read('submodules/ItemListUI/Sources/ItemListControllerSegmentedTitleView.swift')
        for contract in ('self.messagesControl.isHidden = !usesMessages', 'self.backgroundContainer.isHidden = usesMessages', 'self.messagesControl.removeAllSegments()', 'UISegmentedControl.noSegment', 'self.indexUpdated?(index)', 'self.segments.indices.contains(index)', '(44.0 - self.bounds.height) * 0.5', 'UIContentSizeCategory.didChangeNotification'):
            self.assertIn(contract, source)
        self.assertIn('HorizontalTabsComponent(', source)

    def test_attachment_checkout_and_alerts_use_matching_foreground_pairs(self):
        for path in ('submodules/MediaPickerUI/Sources/MediaPickerScreen.swift', 'submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift', 'submodules/BotPaymentsUI/Sources/BotCheckoutControllerNode.swift'):
            source = read(path)
            self.assertIn('theme.isMessagesTheme ? ', source)
            self.assertIn('theme.list.itemCheckColors.fillColor : ', source)
        alerts = read('submodules/TelegramPresentationData/Sources/ComponentsThemes.swift')
        self.assertEqual(alerts.count('contrastColor: presentationTheme.isMessagesTheme ? actionSheet.checkContentColor :'), 2)

    def test_search_shape_survives_activation_and_resets_when_theme_changes(self):
        source = read('submodules/SearchBarNode/Sources/SearchBarNode.swift')
        self.assertIn('self.inlineSearchPlaceholder.maximumCornerRadius = presentationTheme.isMessagesTheme ? MessagesAppearanceMetrics.searchCornerRadius : nil', source)
        self.assertIn('if inline, !theme.isMessagesTheme,', source)
        placeholder = read('submodules/SearchBarNode/Sources/SearchBarPlaceholderNode.swift')
        self.assertIn('self.contentView.maximumCornerRadius = newValue', placeholder)
        self.assertIn('self.maximumCornerRadius ?? backgroundFrame.height * 0.5', placeholder)
        self.assertIn('self.maximumCornerRadius ?? height * 0.5', placeholder)
        navigation = read('submodules/SearchUI/Sources/NavigationBarSearchContentNode.swift')
        self.assertEqual(navigation.count('maximumCornerRadius = theme.isMessagesTheme ? MessagesAppearanceMetrics.searchCornerRadius : nil'), 2)

    def test_profile_content_and_primary_action_remain_accessible(self):
        root = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/'
        header = read(root + 'ListItems/PeerInfoScreenHeaderItem.swift')
        self.assertIn('presentationData.listsFontSize.itemListBaseHeaderFontSize', header)
        self.assertIn('max(textSize.height, labelSize.height)', header)
        self.assertIn('[item.text, item.label ?? ""]', header)
        action = read(root + 'PeerInfoHeaderActionButtonNode.swift')
        self.assertIn('theme.isMessagesTheme ? presentationData.theme.list.itemCheckColors.fillColor', action)
        self.assertIn('textColor: presentationData.theme.list.itemCheckColors.foregroundColor', action)
        self.assertIn('max(1.0, size.width - 24.0)', action)
        self.assertIn('self.action(self, nil)', action)
        profile = read(root + 'ListItems/PeerInfoScreenDisclosureItem.swift')
        self.assertIn('contentWidth * 0.45', profile)
        self.assertIn('max(0.0, labelConstrainWidth)', profile)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; runs in macOS CI')
    def test_production_geometry_preserves_content_at_narrow_and_large_sizes(self):
        source = read('submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift')
        fixture = 'import Foundation\n' + declaration(source, 'public enum MessagesAppearanceMetrics {')
        fixture += '''
for content: CGFloat in [0, 14, 20, 44, 88, 160, 512] {
    for inset: CGFloat in [0, 6, 11, 15, 24] {
        let height = MessagesAppearanceMetrics.rowHeight(contentHeight: content, verticalInset: inset)
        precondition(height >= 50 && height >= content + inset * 2)
        precondition(MessagesAppearanceMetrics.searchRadius(height: height) <= height / 2)
        precondition(MessagesAppearanceMetrics.actionRadius(height: height) <= height / 2)
    }
}
for height: CGFloat in [-20, 0, 1, 12, 24, 44, 88] {
    precondition((0...12).contains(MessagesAppearanceMetrics.searchRadius(height: height)))
    precondition((0...14).contains(MessagesAppearanceMetrics.actionRadius(height: height)))
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'main.swift'
            path.write_text(fixture, encoding='utf-8')
            subprocess.run(['swift', '-swift-version', '5', str(path)], check=True, capture_output=True, text=True, timeout=60)

    def test_preview_and_saved_chat_share_the_same_geometry(self):
        source = read('submodules/SettingsUI/Sources/BubbleSettings/BubbleSettingsController.swift')
        self.assertGreaterEqual(source.count('higChatBubbleCorners(from:'), 3)
        self.assertIn('current.chatBubbleSettings = chatBubbleSettings', source)
        self.assertNotIn('UISegmentedControl', source)
        self.assertNotIn('self.toolbarNode.updateStyle =', source)

    def test_composer_decoration_does_not_replace_the_editor(self):
        source = read('submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift')
        block = source.split('let messagesStyle = interfaceState.bubbleCorners.style == .messages', 1)[1].split('transition.updateFrame(layer: self.textInputBackgroundNode.layer', 1)[0]
        self.assertIn('layer.borderWidth = messagesStyle ? UIScreenPixel : 0.0', block)
        self.assertIn('inputStrokeColor.cgColor', block)
        self.assertNotIn('addSubview', block)
        self.assertNotIn('isUserInteractionEnabled', block)

    def test_effect_removal_cancels_pending_work_and_updates_send_parameters(self):
        source = read('submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift')
        action = source.split('@objc private func clearEffectPreview()', 1)[1].split('private func requestUpdateOverlay', 1)[0]
        for required in ('self.messageEffectDisposable.set(nil)', 'self.selectedMessageEffect = nil', 'selectedItems = Set([])', 'self.stopEffectPreviewAnimation()', 'sendMessage.messageEffect?.1(nil)'):
            self.assertIn(required, action)
        self.assertIn('guard self.selectedMessageEffect?.id == effectId else', source)
        self.assertIn('guard !self.shouldReduceEffectMotion, self.presentationAnimationState.key == .animatedIn else', source)
        self.assertIn('UIAccessibility.reduceMotionStatusDidChangeNotification', source)
        self.assertIn('$0.reduceMotion', source)
        self.assertIn('playbackMode: .once', source)
        self.assertIn('accessibilityElementsHidden = !showEffectPreview', source)

    def test_new_incoming_motion_keeps_outgoing_morph_and_reduced_motion(self):
        source = read('submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift')
        action = source.split('override public func animateAdded(', 1)[1].split('public func animateFromLoadingPlaceholder', 1)[0]
        for required in ('style == .messages', 'effectivelyIncoming', '!item.presentationData.disableAnimations', '!item.presentationData.isPreview', '!UIAccessibility.isReduceMotionEnabled'):
            self.assertIn(required, action)
        self.assertNotIn('repeatForever', action)

    def test_effect_fetch_is_bounded_without_dropping_the_selected_effect(self):
        source = read('submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift')
        self.assertIn('timeout(15.0, queue: .mainQueue(), alternate: .single(false))', source)
        failure = source.split('guard resourceAvailable else {', 1)[1].split('guard let targetView', 1)[0]
        self.assertIn('self.effectPreviewUnavailable = true', failure)
        self.assertNotIn('selectedMessageEffect = nil', failure)
        self.assertIn('self.selectedMessageEffect?.id == effectId, self.presentationAnimationState.key == .animatedIn', source)
        self.assertIn('titleLabel?.numberOfLines = 0', source)
        self.assertIn('minimumPreviewWidth - 24.0', source)
        self.assertIn('ceil(previewTextHeight) + 12.0', source)
        self.assertIn('let canChooseEffects = false', source)
        self.assertIn('self.effectPreviewButton.isHidden = true', source)
        stale = source.split('guard self.selectedMessageEffect?.id == effectId else {', 1)[1].split('guard !self.shouldReduceEffectMotion', 1)[0]
        self.assertNotIn('stopEffectPreviewAnimation', stale)

    def test_avatar_setup_and_layout_share_messages_mode_and_size(self):
        source = read('submodules/ChatListUI/Sources/Node/ChatListItem.swift')
        setup = source.split('func setupItem(', 1)[1].split('func updateIsHighlighted', 1)[0]
        self.assertIn('usesMessagesChatListLayout(item) ? 50.0 : 52.0', setup)
        self.assertNotIn('usesMessagesList', setup)
        self.assertIn('let usesMessagesList = usesMessagesChatListLayout(item)', source)
        self.assertEqual(source.count('min(baseAvatarDiameter, floor(item.presentationData.fontSize.baseDisplaySize * baseAvatarDiameter / 17.0))'), 2)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; runs in macOS CI')
    def test_production_list_mode_for_search_folders_and_inline(self):
        source = read('submodules/ChatListUI/Sources/Node/ChatListItem.swift')
        fixture = '''
struct Theme { var isMessagesTheme: Bool }
struct Presentation { var theme: Theme }
struct Interaction { var isInlineMode: Bool }
struct PeerData { var displayAsMessage: Bool }
enum Location: Equatable { case chatList, savedMessagesChats, search }
enum Content { case loading, peer(PeerData), groupReference }
struct ChatListItem {
    var presentationData: Presentation
    var useCommunityViewLayout: Bool
    var interaction: Interaction
    var chatListLocation: Location
    var content: Content
}
'''
        fixture += declaration(source, 'private func usesMessagesChatListLayout(')
        fixture += '''
for messages in [false, true] {
    for community in [false, true] {
        for inline in [false, true] {
            for location in [Location.chatList, .savedMessagesChats, .search] {
                for (content, searchLayout) in [(Content.loading, true), (.peer(PeerData(displayAsMessage: true)), true), (.peer(PeerData(displayAsMessage: false)), false), (.groupReference, false)] {
                    let item = ChatListItem(presentationData: Presentation(theme: Theme(isMessagesTheme: messages)), useCommunityViewLayout: community, interaction: Interaction(isInlineMode: inline), chatListLocation: location, content: content)
                    let expected = messages && !community && !inline && (location != .search || searchLayout)
                    precondition(usesMessagesChatListLayout(item) == expected)
                }
            }
        }
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'main.swift'
            path.write_text(fixture, encoding='utf-8')
            subprocess.run(['swift', str(path)], check=True, capture_output=True, text=True)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; runs in macOS CI')
    def test_production_codable_migration_and_geometry(self):
        preferences = read('submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift')
        presentation = read('submodules/TelegramPresentationData/Sources/PresentationData.swift')
        fixture = '''import Foundation
public struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
    public var stringValue: String
    public var intValue: Int? { return Int(self.stringValue) }
    public init(stringValue: String) { self.stringValue = stringValue }
    public init(intValue: Int) { self.stringValue = String(intValue) }
    public init(stringLiteral value: String) { self.stringValue = value }
}
'''
        fixture += '\n'.join([
            declaration(preferences, 'public enum PresentationChatBubbleStyle:'),
            declaration(preferences, 'public struct PresentationChatBubbleSettings:'),
            declaration(presentation, 'public struct PresentationChatBubbleCorners:'),
            declaration(presentation, 'public func higChatBubbleCorners('),
        ])
        fixture += '\npublic enum TelegramBaseTheme { case classic, day, night, tinted }\n' + declaration(preferences, 'public enum PresentationBuiltinThemeReference:') + '\n'
        fixture += '''
precondition(PresentationBuiltinThemeReference(rawValue: 7)?.restoredAppearance == .day)
precondition(PresentationBuiltinThemeReference(rawValue: 8)?.restoredAppearance == .night)
for id: Int32 in [0, 1, 2, 3, 4, 5, 6, 9, 10] { precondition(PresentationBuiltinThemeReference(rawValue: id)?.restoredAppearance.rawValue == id) }
let decoder = JSONDecoder()
let retired = try decoder.decode(PresentationChatBubbleSettings.self, from: Data(#"{"style":1,"mainRadius":20,"auxiliaryRadius":4,"mergeBubbleCorners":0}"#.utf8))
precondition(retired == .default)

let legacy = try decoder.decode(PresentationChatBubbleSettings.self, from: Data("{\\"mainRadius\\":24}".utf8))
precondition(legacy.style == .standard && legacy.mainRadius == 24 && legacy.mergeBubbleCorners)
let unknown = try decoder.decode(PresentationChatBubbleSettings.self, from: Data("{\\"style\\":999}".utf8))
precondition(unknown.style == .standard)
for style in [PresentationChatBubbleStyle.standard, .messages] {
    for radius: Int32 in [Int32.min, 4, 14, 20, 30, Int32.max] {
        for merge in [true, false] {
            let original = PresentationChatBubbleSettings(mainRadius: radius, auxiliaryRadius: 7, mergeBubbleCorners: merge, style: style)
            let restored = try decoder.decode(PresentationChatBubbleSettings.self, from: JSONEncoder().encode(original))
            precondition(restored == original)
            let corners = higChatBubbleCorners(from: restored)
            precondition((4...30).contains(corners.mainRadius))
            precondition(corners.style == .standard && corners.mergeBubbleCorners == original.mergeBubbleCorners)
            precondition(!corners.hasTails)
            precondition(corners.auxiliaryRadius == floor(4.0 + (corners.mainRadius - 4.0) * 0.4))
        }
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'main.swift'
            path.write_text(fixture, encoding='utf-8')
            subprocess.run(['swift', '-swift-version', '5', str(path)], check=True, timeout=60)


if __name__ == '__main__':
    unittest.main()
