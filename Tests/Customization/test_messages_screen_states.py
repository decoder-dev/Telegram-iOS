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
    def test_contact_creation_uses_native_messages_actions_without_losing_validation(self):
        source = read('submodules/TelegramUI/Components/Contacts/NewContactScreen/Sources/NewContactScreen.swift')
        self.assertEqual(source.count('theme.isMessagesTheme ? AnyComponent(PlainButtonComponent('), 2)
        self.assertNotIn('string: "mobile"', source)
        self.assertEqual(source.count('string: strings.ContactInfo_PhoneLabelMobile'), 2)
        self.assertIn('let input = self.validatedInput() else { return }', source)
        self.assertIn('controller.complete(result: input)', source)
        self.assertIn('doneButtonView.accessibilityTraits = isValid ? [.button] : [.button, .notEnabled]', source)
        self.assertNotIn('containerSize: CGSize(width: 200.0, height: 40.0)', source)
        self.assertIn('max(environment.safeInsets.left, environment.safeInsets.right)', source)
        avatar = source.index('avatarNode.setPeer(context: component.context, theme: theme, peer: peer)')
        self.assertGreater(avatar, source.index('self.avatarNode = avatarNode'))

    def test_invite_panel_refreshes_colors_and_cannot_invite_zero_contacts(self):
        source = read('submodules/ContactListUI/Sources/InviteContactsCountPanelNode.swift')
        self.assertIn('self.accessibilityElementsHidden = self.count == 0', source)
        self.assertIn('isEnabled: self.count > 0', source)
        self.assertIn('style: self.theme.isMessagesTheme ? .legacy : .glass', source)
        self.assertIn('buttonView.accessibilityLabel = self.strings.Contacts_InviteContacts', source)
        self.assertIn('self.strings = presentationData.strings', source)
        parent = read('submodules/ContactListUI/Sources/InviteContactsControllerNode.swift')
        self.assertIn('self.countPanelNode.updatePresentationData(self.presentationData)', parent)

    def test_contact_rows_keep_full_labels_selection_and_reused_header_theme(self):
        source = read('submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift')
        self.assertIn('maximumNumberOfLines: usesMessages ? 2 : 1', source)
        self.assertIn('if isSelected { accessibilityTraits.insert(.selected) }', source)
        self.assertIn('if !item.enabled { accessibilityTraits.insert(.notEnabled) }', source)
        actions = read('submodules/ContactListUI/Sources/ContactListActionItem.swift')
        self.assertIn('titleOffset = iconFrame.maxX + iconSpacing', actions)
        self.assertIn('MessagesAppearanceMetrics.rowHeight(contentHeight:', actions)
        self.assertIn('strongSelf.activateArea.accessibilityValue = item.subtitle', actions)
        header = read('submodules/ContactListUI/Sources/ContactListNameIndexHeader.swift')
        self.assertIn('(node as? ContactListNameIndexHeaderNode)?.updateTheme(theme: self.theme)', header)
        self.assertIn('lhs.theme === rhs.theme', header)

    def test_recipient_footer_refreshes_theme_language_and_checkbox_accessibility(self):
        source = read('submodules/TelegramUI/Sources/ContactMultiselectionControllerNode.swift')
        self.assertIn('self.footerPanelNode?.updatePresentationData(presentationData)', source)
        self.assertIn('self.button.updateTheme(SolidRoundedButtonTheme(theme: self.theme))', source)
        self.assertIn('self.checkOptionTitle = self.strings.NewCall_VideoOption', source)
        self.assertNotIn('Content(title: "Call"', source)
        self.assertIn('max(49.0, checkOptionTextSize.height + 20.0)', source)
        self.assertIn('checkOptionButton.accessibilityTraits = self.isCheckOptionSelected ? [.button, .selected] : [.button]', source)
        self.assertIn('self.button.accessibilityValue = self.content.badge.isEmpty ? nil : self.content.badge', source)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_call_detail_columns_fit_narrow_and_wide_screens(self):
        source = read('submodules/PeerInfoUI/Sources/ItemListCallListItem.swift')
        fixture = 'import Foundation\nimport CoreGraphics\n' + member(source, 'private func callDetailColumnWidths(')
        fixture += '''
for width: CGFloat in [-20, 0, 1, 2, 13, 14, 100, 160, 284, 357, 720, 1024] {
    let columns = callDetailColumnWidths(availableWidth: width)
    precondition(columns.time >= 1 && columns.type >= 1)
    precondition(columns.spacing >= 0 && columns.spacing <= 12)
    precondition(abs(columns.time + columns.type + columns.spacing - max(2, width)) < 0.001)
    precondition(columns.time <= 75)
}
'''
        run_swift(fixture)
        self.assertNotIn('.first!', source)
        self.assertIn('max(timeLayout.size.height, typeLayout.size.height) + 12.0', source)
        self.assertIn('max(layout.0.size.height, layout.1.size.height) + 12.0', source)
        self.assertIn('leftInset + columns.time + columns.spacing', source)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_call_accessibility_never_calls_while_editing(self):
        source = read('submodules/CallListUI/Sources/CallListCallItem.swift')
        fixture = '''import Foundation
class UIAccessibilityCustomAction {}
struct Message { let id: Int }
class Interaction {
    var calls = 0
    var deleted: [Int] = []
    func call(_ message: Message) { calls += 1 }
    func delete(_ ids: [Int]) { deleted = ids }
}
struct Item {
    var editing = false
    let interaction = Interaction()
    let messages = [Message(id: 42), Message(id: 43)]
    var topMessage: Message { messages[0] }
}
class Area { var activate: (() -> Bool)? }
class Harness {
    var layoutParams: (Item, Int)? = (Item(), 0)
    let accessibilityArea = Area()
    var infoCount = 0
    func infoPressed() { infoCount += 1 }
    init() {
'''
        fixture += member(source, 'self.accessibilityArea.activate =') + '\n}\n'
        fixture += '\n'.join(member(source, marker).replace('@objc ', '') for marker in (
            '@objc private func performLocalAccessibilityCustomAction(',
            '@objc private func performAccessibilityInfoAction('))
        fixture += '''
    func delete() -> Bool { self.performLocalAccessibilityCustomAction(UIAccessibilityCustomAction()) }
    func info() -> Bool { self.performAccessibilityInfoAction(UIAccessibilityCustomAction()) }
}
let view = Harness()
let interaction = view.layoutParams!.0.interaction
precondition(view.accessibilityArea.activate!())
precondition(interaction.calls == 1)
precondition(view.info() && view.infoCount == 1)
view.layoutParams!.0.editing = true
precondition(!view.accessibilityArea.activate!())
precondition(interaction.calls == 1)
precondition(!view.info() && view.infoCount == 1)
precondition(view.delete() && interaction.deleted == [42, 43])
view.layoutParams = nil
precondition(!view.accessibilityArea.activate!() && !view.info() && !view.delete())
'''
        run_swift(fixture)

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
