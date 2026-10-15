"""Keep themed action surfaces consistent across every screen using ButtonComponent."""
import pathlib
import re
import shutil
import subprocess
import unittest

from test_messages_style import ROOT, read, declaration
from test_messages_screen_states import member, run_swift


class MessagesActionSurfaces(unittest.TestCase):
    def test_every_theme_aware_action_passes_its_theme(self):
        paths = subprocess.check_output(
            ['git', 'grep', '-l', '-F', 'ButtonComponent.Background(', '--', 'submodules/**/*.swift'],
            cwd=ROOT, text=True).splitlines()
        count = 0
        exceptions = []
        for path in paths:
            source = read(path)
            for match in re.finditer(r'ButtonComponent\.Background\(', source):
                index, depth = match.end(), 1
                while depth:
                    depth += (source[index] == '(') - (source[index] == ')')
                    index += 1
                arguments = source[match.end():index - 1]
                if re.match(r'\s*theme:', arguments):
                    count += 1
                else:
                    exceptions.append(path)
        # Camera permission content is deliberately independent of the app palette:
        # it is an overlay on a black capture preview and has no PresentationTheme.
        self.assertEqual(exceptions, ['submodules/TelegramUI/Components/CameraScreen/Sources/PlaceholderComponent.swift'])
        self.assertGreaterEqual(count, 164)

    def test_media_permissions_keep_visible_actions_and_content_reuse_correct(self):
        source = read('submodules/MediaPickerUI/Sources/MediaPickerPlaceholderNode.swift')
        for contract in ('private let scrollNode = ASScrollNode()',
                         'self.scrollNode.view.contentSize =',
                         'showsButton ? 20.0 + buttonHeight : 0.0',
                         'showsCamera ? 13.0 + cameraHeight : 0.0',
                         'let showsCamera = isIntro && hasCamera',
                         'effectiveReduceMotion ? .still(.start)',
                         'self.animationNode.visibility = imageHeight > 0.0',
                         'self.cameraButtonNode.accessibilityElementsHidden = !showsCamera',
                         'UIContentSizeCategory.didChangeNotification',
                         'UIAccessibility.reduceMotionStatusDidChangeNotification'):
            self.assertIn(contract, source)
        self.assertNotIn('insets.top += -', source)
        picker = read('submodules/MediaPickerUI/Sources/MediaPickerScreen.swift')
        self.assertIn('current.content == .bannedSendMedia(text: banDescription, canBoost:', picker)
        self.assertIn('current.content == .intro(story: story)', picker)
        self.assertEqual(picker.count('reduceMotion: self.presentationData.reduceMotion, transition: placeholderTransition'), 2)

    def test_media_headers_and_albums_reserve_their_metadata_width(self):
        title = read('submodules/MediaPickerUI/Sources/MediaPickerTitleView.swift')
        self.assertIn('size.width - arrowWidth', title)
        self.assertIn('y: self.titleNode.frame.maxY + 1.0', title)
        self.assertIn('self.buttonNode.accessibilityLabel = self.title', title)
        self.assertIn('self.segmentedControlNode.accessibilityElementsHidden = self.segmentsHidden', title)
        albums = read('submodules/MediaPickerUI/Sources/MediaGroupsAlbumItem.swift')
        self.assertIn('rowWidth - countLayout.size.width - 24.0', albums)
        self.assertIn('strongSelf.activateArea.accessibilityValue = item.count', albums)
        self.assertIn('strongSelf.backgroundNode.backgroundColor = item.presentationData.theme.list.plainBackgroundColor', albums)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_background_preserves_stock_themes_colors_gradients_and_copies(self):
        source = read('submodules/TelegramUI/Components/ButtonComponent/Sources/ButtonComponent.swift')
        metrics = read('submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift')
        fixture = '''import Foundation
import CoreGraphics
public typealias UIColor = Int
public class PresentationTheme {
    let isMessagesTheme: Bool
    init(_ messages: Bool) { self.isMessagesTheme = messages }
}
'''
        fixture += declaration(metrics, 'public enum MessagesAppearanceMetrics {')
        fixture += '\nenum ButtonComponent {\n' + member(source, 'public struct Background: Equatable {') + '\n}\n'
        fixture += '''
let messages = PresentationTheme(true)
let stock = PresentationTheme(false)
for style in [ButtonComponent.Background.Style.glass, .actualGlass, .legacy] {
    for radius: CGFloat in [-4, 0, 4, 10, 14, 26, 50] {
        let gradient = ButtonComponent.Background.Gradient(colors: [1, 2, 3])
        let legacy = ButtonComponent.Background(theme: stock, style: style, color: 4, foreground: 5, pressedColor: 6, cornerRadius: radius, gradient: gradient)
        let absent = ButtonComponent.Background(style: style, color: 4, foreground: 5, pressedColor: 6, cornerRadius: radius, gradient: gradient)
        precondition(legacy == absent && legacy.style == style && legacy.cornerRadius == radius)
        let themed = ButtonComponent.Background(theme: messages, style: style, color: 4, foreground: 5, pressedColor: 6, cornerRadius: radius, gradient: gradient)
        precondition(themed.style == .legacy)
        precondition(themed.cornerRadius >= 0 && themed.cornerRadius <= MessagesAppearanceMetrics.actionCornerRadius)
        precondition(themed.color == 4 && themed.foreground == 5 && themed.pressedColor == 6)
        precondition(themed.gradient == gradient)
        let copy = themed.withIsShimmering(true)
        precondition(copy.style == themed.style && copy.cornerRadius == themed.cornerRadius)
        precondition(copy.color == themed.color && copy.foreground == themed.foreground && copy.gradient == themed.gradient)
        precondition(copy.isShimmering && !themed.isShimmering)
    }
}
'''
        run_swift(fixture)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_media_geometry_keeps_controls_scrollable_on_small_screens(self):
        source = read('submodules/MediaPickerUI/Sources/MediaPickerPlaceholderNode.swift')
        fixture = 'import Foundation\nimport CoreGraphics\n' + member(source, 'private func mediaPlaceholderGeometry(')
        fixture += '''
for available: CGFloat in [1, 100, 180, 320, 640, 1000] {
    for body: CGFloat in [0, 52, 160, 400, 1200] {
        for portrait in [false, true] {
            let geometry = mediaPlaceholderGeometry(availableHeight: available, bodyHeight: body, imageHeight: 144, portrait: portrait)
            precondition(geometry.topOffset >= 0)
            precondition(geometry.contentHeight >= body)
            precondition(geometry.imageHeight == ((portrait && body + 156 <= available) ? 156 : 0))
            precondition(geometry.contentHeight + geometry.topOffset * 2 <= max(available, body))
            if body > available { precondition(geometry.topOffset == 0 && geometry.imageHeight == 0) }
        }
    }
}
'''
        run_swift(fixture)


if __name__ == '__main__':
    unittest.main()
