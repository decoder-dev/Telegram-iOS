"""Production state transitions and contrast checks, without an application build."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

from test_messages_style import read, declaration

STORAGE = 'submodules/TelegramUI/Components/StorageUsageScreen/Sources/'
WALLPAPER = 'submodules/TelegramUI/Components/Settings/WallpaperGalleryScreen/Sources/WallpaperGalleryToolbarNode.swift'


def member(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def run_swift(source):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / 'main.swift'
        path.write_text(source, encoding='utf-8')
        result = subprocess.run(['swift', '-swift-version', '5', str(path)], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)


class ScreenStateTests(unittest.TestCase):
    def test_file_empty_state_reuse_updates_animation_motion_and_visible_layout(self):
        source = read('submodules/TelegramUI/Components/AttachmentFileController/Sources/AttachmentFileEmptyItem.swift')
        for contract in ('self.reduceMotion == item.reduceMotion', 'self.animationName != name || self.animationReduceMotion != reduceMotion', 'reduceMotion ? .still(.start) : .loop', 'reduceMotion ? .still(.start) : .once', 'self.animationNode.visibility = imageHeight > 0.0', 'UIContentSizeCategory.didChangeNotification', 'UIAccessibility.reduceMotionStatusDidChangeNotification', 'NotificationCenter.default.removeObserver(self)', 'layout.insets(options: [.input])', 'self.showsButton ? buttonSpacing + buttonHeight : 0.0', 'min(248.0, contentWidth)', 'self.buttonNode.removeFromSupernode()'):
            self.assertIn(contract, source)
        self.assertNotIn('insets.top += -60.0', source)
        self.assertNotIn('insets.top += 120.0', source)

    def test_wallpaper_solid_content_and_touch_target_are_outside_the_hidden_glass(self):
        source = read(WALLPAPER)
        for node in ('doneButtonSolidBackgroundNode', 'doneButtonSolidTitleNode'):
            self.assertIn('self.addSubnode(self.' + node + ')', source)
            self.assertNotIn('contentView.addSubnode(self.' + node + ')', source)
        self.assertIn('self.view.addSubview(self.doneButton.view)', source)
        self.assertNotIn('contentView.addSubview(self.doneButton.view)', source)
        self.assertIn('self.doneButton.isEnabled = enabled', source)
        self.assertIn('self.doneButtonSubtitle = nil', source)
        self.assertIn('self.applyButton.isHidden = applyTitle.isEmpty', source)
        self.assertIn('self.strings = strings', member(source, 'public func updateThemeAndStrings('))
        self.assertIn('self.updateColors()', member(source, 'var dark: Bool = false'))
        self.assertEqual(source.count('layout.safeInsets.right'), 2)
        self.assertEqual(source.count('layout.safeInsets.left'), 2)

    def test_storage_accessibility_keeps_selection_expansion_and_children_separate(self):
        source = read(STORAGE + 'StorageCategoryItemCompoment.swift')
        for action in ('component.action(component.category.key, .generic)', 'component.action(component.category.key, .toggle)', 'self?.pressed()', 'self?.checkPressed()'):
            self.assertIn(action, source)
        self.assertIn('var elements: [Any] = [self.selectionAccessibilityElement, self.headerAccessibilityElement]', source)
        self.assertIn('if component.isExpanded {\n                    for category in component.category.subcategories', source)
        self.assertIn('component.category.isSelected ? [.button, .selected] : [.button]', source)
        self.assertNotIn('self.checkButtonArea.accessibilityFrameInContainerSpace', source)
        self.assertIn('maximumNumberOfLines: usesMessages ? 0 : 1', source)
        self.assertIn('rowContentWidth * 0.35', source)
        self.assertIn('rowContentWidth * 0.25', source)
        for name in ('DataButtonComponent.swift', 'StorageKeepSizeComponent.swift', 'StorageCategoriesComponent.swift'):
            self.assertIn('component.theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius : 26.0', read(STORAGE + name))

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_wallpaper_enabled_and_solid_transitions(self):
        source = read(WALLPAPER)
        fixture = '''import Foundation
struct Traits: OptionSet {
    let rawValue: Int
    static let button = Traits(rawValue: 1)
    static let notEnabled = Traits(rawValue: 2)
}
class Node {
    var alpha: CGFloat = 1
    var isEnabled = true
    var isUserInteractionEnabled = true
    var accessibilityTraits: Traits = .button
}
struct Subtitle { var view: Node? = Node() }
struct ContainedViewLayoutTransition {
    static let immediate = Self()
    func updateAlpha(node: Node, alpha: CGFloat) { node.alpha = alpha }
}
class Harness {
    var enabled = true
    var isSolid = false
    let doneButton = Node()
    let doneButtonBackgroundNode = Node()
    let doneButtonSolidBackgroundNode = Node()
    let doneButtonTitleNode = Node()
    let doneButtonSolidTitleNode = Node()
    let animationNode = Node()
    var doneButtonSubtitle: Subtitle? = Subtitle()
    func updateColors() {}
'''
        fixture += '\n'.join(member(source, marker) for marker in ('func setEnabled(', 'func setIsSolid(', 'private func updateContentAlpha('))
        fixture += '''
}
let view = Harness()
for enabled in [false, true, false, true] {
    view.setEnabled(enabled)
    for solid in [true, false, true, false] {
        view.setIsSolid(solid, transition: .immediate)
        let alpha: CGFloat = enabled ? 1 : 0.4
        precondition(view.doneButton.isEnabled == enabled)
        precondition(view.doneButton.isUserInteractionEnabled == enabled)
        precondition(view.doneButton.accessibilityTraits.contains(.notEnabled) == !enabled)
        precondition(view.doneButtonSolidBackgroundNode.alpha == (solid ? alpha : 0))
        precondition(view.doneButtonSolidTitleNode.alpha == (solid ? alpha : 0))
        precondition(view.doneButtonBackgroundNode.alpha * view.doneButtonTitleNode.alpha == (solid ? 0 : alpha))
        precondition(view.doneButtonSubtitle!.view!.alpha == alpha)
    }
}
'''
        run_swift(fixture)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_category_check_contrast_on_bright_and_dark_colors(self):
        source = read(STORAGE + 'StorageCategoryItemCompoment.swift')
        fixture = 'import Foundation\n' + declaration(source, 'private func storageCategoryUsesDarkForeground(')
        fixture += '''
precondition(storageCategoryUsesDarkForeground(red: 1, green: 1, blue: 0))
precondition(!storageCategoryUsesDarkForeground(red: 0, green: 0, blue: 1))
precondition(storageCategoryUsesDarkForeground(red: 1, green: 1, blue: 1))
precondition(!storageCategoryUsesDarkForeground(red: 0, green: 0, blue: 0))
func luminance(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
for r in stride(from: 0, through: 255, by: 17) {
    for g in stride(from: 0, through: 255, by: 17) {
        for b in stride(from: 0, through: 255, by: 17) {
            let rgb = [r, g, b].map { Double($0) / 255 }
            let background = 0.2126 * luminance(rgb[0]) + 0.7152 * luminance(rgb[1]) + 0.0722 * luminance(rgb[2])
            let dark = storageCategoryUsesDarkForeground(red: CGFloat(rgb[0]), green: CGFloat(rgb[1]), blue: CGFloat(rgb[2]))
            let ratio = dark ? (background + 0.05) / 0.05 : 1.05 / (background + 0.05)
            precondition(ratio >= 4.5)
        }
    }
}
'''
        run_swift(fixture)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_focus_highlight_does_not_clear_a_newer_or_pressed_highlight(self):
        source = read(STORAGE + 'DataButtonComponent.swift')
        fixture = '''import Foundation
import CoreGraphics
class Queue {
    static let main = Queue()
    static func mainQueue() -> Queue { main }
    var callbacks: [() -> Void] = []
    func after(_ delay: Double, _ action: @escaping () -> Void) { callbacks.append(action) }
    func next() { callbacks.removeFirst()() }
}
class SimpleLayer {
    var backgroundColor = 0
    var frame = CGRect.zero
    var opacity: Float = 1
    var removed = false
    func insertSublayer(_ layer: SimpleLayer, at index: Int) {}
    func removeFromSuperlayer() { removed = true }
    func animateAlpha(from: CGFloat, to: CGFloat, duration: Double, removeOnCompletion: Bool, completion: (Bool) -> Void) { completion(true) }
}
struct Color { let cgColor = 1 }
struct List { let itemHighlightedBackgroundColor = Color() }
struct Theme { let list = List() }
struct Component { let theme = Theme() }
class Parent { func bringSubviewToFront(_ view: Harness) {} }
class Harness {
    var component: Component? = Component()
    var highlightBackgroundFrame: CGRect? = CGRect(x: 0, y: 0, width: 240, height: 64)
    var highlightBackgroundLayer: SimpleLayer?
    let layer = SimpleLayer()
    var superview: Parent?
    var isHighlighted = false
    var highligthedChanged: (Bool) -> Void = { _ in }
    init() {
'''
        fixture += member(source, 'self.highligthedChanged =') + '\n}\n' + member(source, 'func displayHighlight()')
        fixture += '''
}
let view = Harness()
view.displayHighlight()
let first = view.highlightBackgroundLayer!
view.displayHighlight()
let second = view.highlightBackgroundLayer!
precondition(first.removed && first !== second)
Queue.mainQueue().next()
precondition(view.highlightBackgroundLayer === second && !second.removed)
Queue.mainQueue().next()
precondition(view.highlightBackgroundLayer == nil && second.removed)
view.displayHighlight()
let pressed = view.highlightBackgroundLayer!
view.isHighlighted = true
Queue.mainQueue().next()
precondition(view.highlightBackgroundLayer === pressed && !pressed.removed)
view.highligthedChanged(false)
precondition(view.highlightBackgroundLayer == nil && pressed.removed)
view.highlightBackgroundFrame = nil
view.displayHighlight()
precondition(view.highlightBackgroundLayer == nil)
'''
        run_swift(fixture)


if __name__ == '__main__':
    unittest.main()
