"""Keep themed action surfaces consistent across every screen using ButtonComponent."""
import pathlib
import re
import shutil
import subprocess
import unittest

from test_messages_style import ROOT, read, declaration
from test_messages_screen_states import member, run_swift


class MessagesActionSurfaces(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_button_labels_follow_content_and_preserve_explicit_names(self):
        fixture = """import Foundation
class UIView { var accessibilityLabel: String? }
class Content { var view: UIView?; var componentView: UIView? }
"""
        paths = [
            ('Plain', 'submodules/TelegramUI/Components/PlainButtonComponent/Sources/PlainButtonComponent.swift', 'let content = Content()'),
            ('Flow', 'submodules/ComponentFlow/Source/Components/Button.swift', 'let contentView = Content()'),
            ('Glass', 'submodules/TelegramUI/Components/GlassBarButtonComponent/Sources/GlassBarButtonComponent.swift', 'var componentView: Content?'),
        ]
        for name, path, field in paths:
            prop = member(read(path), 'public override var accessibilityLabel: String?').replace('public override ', 'override ')
            fixture += 'class ' + name + ': UIView { ' + field + '\n' + prop + '\n}\n'
        fixture += """
let content = UIView(); content.accessibilityLabel = "Отправить"
let plain = Plain(); plain.content.view = content
let flow = Flow(); flow.contentView.componentView = content
let glass = Glass(); glass.componentView = Content(); glass.componentView?.view = content
for button in [plain as UIView, flow, glass] {
    precondition(button.accessibilityLabel == "Отправить")
    button.accessibilityLabel = "Специальная подпись"
    precondition(button.accessibilityLabel == "Специальная подпись")
}
content.accessibilityLabel = "Send"
for button in [plain as UIView, flow, glass] {
    precondition(button.accessibilityLabel == "Специальная подпись")
    button.accessibilityLabel = nil
    precondition(button.accessibilityLabel == "Send")
}
"""
        run_swift(fixture)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_check_initialization_publishes_once_and_isolates_replaced_owners(self):
        source = read('submodules/TelegramUI/Components/AlertComponent/AlertCheckComponent/Sources/AlertCheckComponent.swift')
        fixture = """import Foundation
class ValuePromise<T> {
    var value: T
    init(_ value: T) { self.value = value }
    func set(_ value: T) { self.value = value }
    func get() -> ValuePromise<T> { self }
}
class Promise<T> {
    var source: ValuePromise<T>?
    func set(_ source: ValuePromise<T>) { self.source = source }
}
class External { var value = false; let valuePromise = Promise<Bool>() }
class Model {
    let externalState: External; let initialValue: Bool
    init(_ external: External, _ initial: Bool) { externalState = external; initialValue = initial }
}
class View {
    var component: Model?
    var valuePromise = ValuePromise<Bool>(false)
    func update(component: Model) {
"""
        fixture += member(source, 'if self.component?.externalState !== component.externalState {')
        fixture += """
        self.component = component
    }
}
let view = View(); let first = External()
view.update(component: Model(first, true))
precondition(first.value && first.valuePromise.source?.value == true)
first.value = false; view.valuePromise.set(false)
view.update(component: Model(first, true))
precondition(!first.value && first.valuePromise.source?.value == false)
let second = External()
view.update(component: Model(second, false))
view.valuePromise.set(true)
precondition(second.valuePromise.source?.value == true)
precondition(first.valuePromise.source?.value == false)
"""
        run_swift(fixture)

    def test_shared_drawn_text_exposes_current_full_text_to_button_wrappers(self):
        text = read('submodules/ComponentFlow/Source/Components/Text.swift')
        body = member(text, 'public func update(component: Text,')
        self.assertLess(body.index('self.accessibilityLabel = component.text'), body.index('if let measureState = self.measureState'))
        multiline = read('submodules/Components/MultilineTextComponent/Sources/MultilineTextComponent.swift')
        self.assertIn('self.accessibilityLabel = attributedString.string', multiline)
        # Labels alone do not group rich-text links or hide their existing interactions.
        self.assertNotIn('self.accessibilityElementsHidden = true', multiline)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_alert_input_validates_utf16_ranges_and_character_limits(self):
        source = read('submodules/TelegramUI/Components/AlertComponent/AlertInputFieldComponent/Sources/AlertInputFieldComponent.swift')
        fixture = 'import Foundation\n' + member(source, 'private func alertInputFieldReplacement(')
        fixture += """
precondition(alertInputFieldReplacement(text: "Привет", range: NSRange(location: 6, length: 0), replacement: "!", characterLimit: 6) == nil)
precondition(alertInputFieldReplacement(text: "Привет", range: NSRange(location: 0, length: 6), replacement: "Hello", characterLimit: 6) == "Hello")
precondition(alertInputFieldReplacement(text: "🎃", range: NSRange(location: 0, length: 2), replacement: "👨‍👩‍👧‍👦", characterLimit: 1) == "👨‍👩‍👧‍👦")
precondition(alertInputFieldReplacement(text: "🎃", range: NSRange(location: 1, length: 0), replacement: "x", characterLimit: nil) == nil)
precondition(alertInputFieldReplacement(text: "x", range: NSRange(location: 5, length: 20), replacement: "y", characterLimit: nil) == nil)
precondition(alertInputFieldReplacement(text: "", range: NSRange(location: 0, length: 0), replacement: "x", characterLimit: -1) == nil)
precondition(alertInputFieldReplacement(text: "long", range: NSRange(location: 3, length: 1), replacement: "", characterLimit: 1) == "lon")
precondition(alertInputFieldReplacement(text: "", range: NSRange(location: 0, length: 0), replacement: "unlimited", characterLimit: nil) == "unlimited")
"""
        run_swift(fixture)

    def test_alert_form_inputs_keep_keyboard_validation_and_initial_check_state(self):
        base = 'submodules/TelegramUI/Components/AlertComponent/'
        single = read(base + 'AlertInputFieldComponent/Sources/AlertInputFieldComponent.swift')
        for contract in ('self.textField.keyboardType = component.keyboardType',
                         'self.textField.reloadInputViews()',
                         'self.textField.accessibilityLabel = component.placeholder',
                         'clearButtonView.accessibilityLabel = environment.strings.VoiceOver_Editing_ClearText',
                         'textField.markedTextRange == nil ? component.characterLimit : nil',
                         'self.currentText.prefix(max(0, characterLimit))',
                         'return shouldChangeText(updatedText)',
                         'self.setText(text: "")'):
            self.assertIn(contract, single)
        for name in ('AlertInputFieldComponent', 'AlertMultilineInputFieldComponent', 'AlertCheckComponent'):
            body = read(base + name + '/Sources/' + name + '.swift')
            self.assertIn('UIContentSizeCategory.didChangeNotification', body)
            self.assertIn('UIFont.preferredFont(forTextStyle:', body)
            self.assertIn('NotificationCenter.default.removeObserver(self)', body)
        check = read(base + 'AlertCheckComponent/Sources/AlertCheckComponent.swift')
        self.assertIn('lhs.title != rhs.title', check)
        self.assertIn('lhs.externalState !== rhs.externalState', check)
        initial = member(check, 'if self.component?.externalState !== component.externalState {')
        self.assertLess(initial.index('self.valuePromise = ValuePromise<Bool>(component.initialValue)'), initial.index('component.externalState.valuePromise.set(self.valuePromise.get())'))
        self.assertIn('buttonView.accessibilityTraits = component.externalState.value ? [.button, .selected] : [.button]', check)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_alerts_and_sheets_cannot_execute_disabled_actions(self):
        action = read('submodules/TelegramUI/Components/AlertComponent/Sources/AlertActionComponent.swift')
        alert = read('submodules/TelegramUI/Components/AlertComponent/Sources/AlertComponent.swift')
        sheet = read('submodules/Display/Source/ActionSheetButtonItem.swift')
        fixture = 'import Foundation\nenum AlertActionComponent { class View {\nvar isEnabled = false; var hasProgress = false; var action: (() -> Void)?\n'
        fixture += member(action, 'var canPerformAction: Bool') + '\n'
        fixture += member(action, 'override func accessibilityActivate() -> Bool').replace('override ', '') + '\n}}\n'
        fixture += """
struct Action { let id: AnyHashable; let autoDismiss: Bool; let action: () -> Void }
struct Item { let view: Any? }
class Alert {
    var actions: [Action]?
    var highlightedAction: AnyHashable?
    var actionItems: [AnyHashable: Item] = [:]
    var dismissals = 0
    func requestDismiss() { dismissals += 1 }
"""
        fixture += member(alert, 'func performHighlightedAction()') + '\n}\n'
        fixture += 'struct SheetItem { let enabled: Bool; let action: () -> Void }\nclass Sheet { var item: SheetItem?\n'
        fixture += member(sheet, '@objc func buttonPressed()').replace('@objc ', '') + '\n}\n'
        fixture += """
var count = 0
let view = AlertActionComponent.View()
let alert = Alert()
alert.actions = [Action(id: "confirm", autoDismiss: true, action: { count += 1 })]
alert.highlightedAction = "confirm"
alert.performHighlightedAction()
precondition(count == 0 && alert.dismissals == 0)
alert.actionItems["confirm"] = Item(view: view)
view.action = { alert.performHighlightedAction() }
for enabled in [false, true] {
    for progress in [false, true] {
        view.isEnabled = enabled; view.hasProgress = progress
        let before = count; let dismissals = alert.dismissals
        alert.performHighlightedAction()
        let expected = enabled && !progress
        precondition(count == before + (expected ? 1 : 0))
        precondition(alert.dismissals == dismissals + (expected ? 1 : 0))
        let prior = count
        precondition(view.accessibilityActivate() == expected)
        precondition(count == prior + (expected ? 1 : 0))
    }
}
let sheet = Sheet()
sheet.buttonPressed()
for enabled in [false, true] {
    sheet.item = SheetItem(enabled: enabled, action: { count += 1 })
    let before = count
    sheet.buttonPressed()
    precondition(count == before + (enabled ? 1 : 0))
}
"""
        run_swift(fixture)

    def test_alert_reuse_refreshes_signals_and_preserves_accessible_dynamic_layout(self):
        action = read('submodules/TelegramUI/Components/AlertComponent/Sources/AlertActionComponent.swift')
        for contract in ('previousComponent?.isEnabled !== component.isEnabled',
                         'previousComponent?.progress !== component.progress',
                         'self.isEnabledDisposable?.dispose()', 'self.progressDisposable?.dispose()',
                         'self.accessibilityLabel = component.title', 'self.updateAccessibilityState()',
                         'maximumNumberOfLines: usesMessages ? 2 : 1',
                         'MessagesAppearanceMetrics.actionRadius(height:',
                         'UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)'):
            self.assertIn(contract, action)
        alert = read('submodules/TelegramUI/Components/AlertComponent/Sources/AlertComponent.swift')
        self.assertIn('actionView.canPerformAction', member(alert, 'func performHighlightedAction()'))
        self.assertIn('self.accessibilityViewIsModal = true', alert)
        self.assertIn('override func accessibilityPerformEscape() -> Bool', alert)
        self.assertIn('fullWidthActionSize.height = max(fullWidthActionSize.height, itemSize.height)', alert)
        sheet = read('submodules/Display/Source/ActionSheetButtonItem.swift')
        self.assertIn('guard let self, self.item?.enabled == true', sheet)
        checkbox = read('submodules/Display/Source/ActionSheetCheckboxItem.swift')
        self.assertIn('x: size.width - rightInset - labelSize.width', checkbox)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_button_title_and_badge_stay_inside_measured_bounds(self):
        source = read('submodules/TelegramUI/Components/ButtonComponent/Sources/ButtonComponent.swift')
        fixture = 'import Foundation\nimport CoreGraphics\n' + member(source, 'private func buttonTextContentGeometry(')
        fixture += """
for available: CGFloat in [100, 160, 280, 375, 700] {
    for badge: CGFloat in [0, 20, 48, 90] {
        for combined in [false, true] {
            let spacing: CGFloat = 6
            let maxTitle = max(0, available - badge - spacing)
            for title in [CGFloat(0), min(50, maxTitle), maxTitle] {
                let result = buttonTextContentGeometry(titleWidth: title, badgeWidth: badge, spacing: spacing, availableWidth: available, combinedAlignment: combined)
                precondition(result.titleX >= 0 && result.width <= available)
                precondition(result.titleX + title + spacing + badge <= result.width)
                if !combined && title + 2 * (spacing + badge) <= available {
                    precondition(result.titleX + title / 2 == result.width / 2)
                }
            }
        }
    }
    let plain = buttonTextContentGeometry(titleWidth: available, badgeWidth: nil, spacing: 6, availableWidth: available, combinedAlignment: false)
    precondition(plain.width == available && plain.titleX == 0)
}
"""
        run_swift(fixture)

    def test_button_badges_reserve_width_keep_spoken_counts_and_respect_reduced_motion(self):
        source = read('submodules/TelegramUI/Components/ButtonComponent/Sources/ButtonComponent.swift')
        body = member(source, 'func update(component: ButtonTextContentComponent,')
        self.assertLess(body.index('badgeSize = badge.update('), body.index('let contentSize = self.content.update('))
        self.assertIn('availableSize.width - (badgeSize.map { $0.width + badgeSpacing } ?? 0.0)', body)
        self.assertIn('UIAccessibility.isReduceMotionEnabled ? transition.withAnimation(.none) : transition', body)
        self.assertIn('self.accessibilityValue = component.badge > 0 ? String(component.badge) : nil', body)
        self.assertIn('self.button.accessibilityLabel = contentView.accessibilityLabel', source)
        self.assertIn('self.button.accessibilityValue = contentView.accessibilityValue', source)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_empty_attributed_text_and_accessible_activation(self):
        text = read('submodules/ComponentFlow/Source/Components/Text.swift')
        fixture = """import Foundation
class UIFont: NSObject {
    static let systemFontSize: Double = 17
    static func systemFont(ofSize: Double) -> UIFont { UIFont() }
}
class UIColor: NSObject { static let black = UIColor() }
extension NSAttributedString.Key {
    static let font = NSAttributedString.Key("font")
    static let foregroundColor = NSAttributedString.Key("foregroundColor")
}
final class Text {
    let text: String
    let font: UIFont
    let color: UIColor
    init(text: String, font: UIFont, color: UIColor, tintColor: UIColor?) {
        self.text = text; self.font = font; self.color = color
    }
"""
        fixture += member(text, 'public convenience init(attributedString:').replace('public ', '') + '\n}\n'
        fixture += """
precondition(Text(attributedString: NSAttributedString(string: "")).text.isEmpty)
let font = UIFont(); let color = UIColor()
let content = Text(attributedString: NSAttributedString(string: "Привет 🎃", attributes: [.font: font, .foregroundColor: color]))
precondition(content.text == "Привет 🎃" && content.font === font && content.color === color)
"""
        for path, glass in [
            ('submodules/TelegramUI/Components/ButtonComponent/Sources/ButtonComponent.swift', False),
            ('submodules/TelegramUI/Components/GlassBarButtonComponent/Sources/GlassBarButtonComponent.swift', True),
        ]:
            source = read(path)
            activation = member(source, 'public override func accessibilityActivate() -> Bool').replace('public override ', '')
            name = 'Glass' if glass else 'Action'
            fields = 'var isEnabled = true; var isVisible = true; var action: ((AnyObject) -> Void)?' if glass else 'var isEnabled = true; var allowActionWhenDisabled = false; var displaysProgress = false; var action: () -> Void = {}'
            fixture += '\nclass ' + name + 'Model { ' + fields + ' }\n'
            fixture += 'class ' + name + 'View { var component: ' + name + 'Model?; ' + activation + '\n}\n'
        fixture += """
let button = ActionView(); var count = 0
precondition(!button.accessibilityActivate())
let model = ActionModel(); model.action = { count += 1 }; button.component = model
for enabled in [false, true] {
    for allowed in [false, true] {
        for loading in [false, true] {
            model.isEnabled = enabled; model.allowActionWhenDisabled = allowed; model.displaysProgress = loading
            let before = count; let expected = (enabled || allowed) && !loading
            precondition(button.accessibilityActivate() == expected)
            precondition(count == before + (expected ? 1 : 0))
        }
    }
}
let glass = GlassView(); let glassModel = GlassModel(); glass.component = glassModel
precondition(!glass.accessibilityActivate())
glassModel.action = { _ in count += 1 }
for enabled in [false, true] {
    for visible in [false, true] {
        glassModel.isEnabled = enabled; glassModel.isVisible = visible
        let before = count; let expected = enabled && visible
        precondition(glass.accessibilityActivate() == expected)
        precondition(count == before + (expected ? 1 : 0))
    }
}
"""
        run_swift(fixture)

    def test_shared_actions_use_one_guarded_activation_path(self):
        button = read('submodules/TelegramUI/Components/ButtonComponent/Sources/ButtonComponent.swift')
        self.assertIn('_ = self.accessibilityActivate()', member(button, '@objc private func pressed()'))
        self.assertIn('!component.displaysProgress', member(button, '@objc private func longPressed('))
        glass = read('submodules/TelegramUI/Components/GlassBarButtonComponent/Sources/GlassBarButtonComponent.swift')
        self.assertIn('_ = self.accessibilityActivate()', member(glass, '@objc private func pressed()'))
        self.assertIn('_ = self.accessibilityActivate()', member(glass, '@objc private func onTapGesture('))
        self.assertIn('component.isEnabled && component.isVisible && component.action != nil', glass)
        self.assertIn('(lhs.action == nil) != (rhs.action == nil)', glass)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_search_reset_identity_and_safe_area_geometry(self):
        source = read('submodules/TelegramUI/Components/SearchInputPanelComponent/Sources/SearchInputPanelComponent.swift')
        fixture = 'import Foundation\nimport CoreGraphics\nenum SearchInputPanelComponent {\n'
        fixture += member(source, 'public final class ResetText: Equatable {') + '\n}\n'
        fixture += member(source, 'private func searchInputPanelResetText(') + '\n'
        fixture += member(source, 'private func searchInputPanelFrames(') + '\n'
        fixture += '''
let first = SearchInputPanelComponent.ResetText(value: "query")
precondition(searchInputPanelResetText(previous: nil, next: first) == "query")
precondition(searchInputPanelResetText(previous: first, next: first) == nil)
let again = SearchInputPanelComponent.ResetText(value: "query")
precondition(searchInputPanelResetText(previous: first, next: again) == "query")
let clear = SearchInputPanelComponent.ResetText(value: "")
precondition(searchInputPanelResetText(previous: first, next: clear) == "")
precondition(searchInputPanelResetText(previous: first, next: nil) == nil)
for width: CGFloat in [320, 393, 568, 768] {
    for left: CGFloat in [11, 55] {
        for right: CGFloat in [11, 55] {
            for height: CGFloat in [48, 50, 90] {
                for cancel: CGFloat in [44, 80, 150] {
                    let frames = searchInputPanelFrames(width: width, leftInset: left, rightInset: right, topInset: 10, fieldHeight: height, cancelWidth: cancel)
                    precondition(frames.field.minX == left && frames.field.width > 0)
                    precondition(frames.cancel.minX >= frames.field.maxX + 10)
                    precondition(frames.cancel.maxX <= width - right + 0.001)
                    precondition(frames.field.height == height && frames.cancel.height == height)
                }
            }
        }
    }
}
'''
        run_swift(fixture)

    def test_search_panels_keep_localized_controls_and_current_theme(self):
        source = read('submodules/TelegramUI/Components/SearchInputPanelComponent/Sources/SearchInputPanelComponent.swift')
        self.assertIn('searchInputPanelResetText(previous: previousComponent?.resetText, next: component.resetText)', source)
        self.assertIn('self.textField.text = resetText', source)
        self.assertIn('MessagesAppearanceMetrics.searchRadius(height: fieldHeight)', source)
        self.assertIn('usesMessages ? AnyComponent(PlainButtonComponent(', source)
        self.assertIn('clearButtonView.accessibilityLabel = component.strings.VoiceOver_Editing_ClearText', source)
        self.assertIn('fieldFrame.width - fieldSideInset - self.textField.trailingInset', source)
        files = read('submodules/TelegramUI/Components/AttachmentFileController/Sources/AttachmentFileSearchItem.swift')
        self.assertIn('current.updateThemeAndStrings(theme: self.presentationData.theme, strings: self.presentationData.strings)', files)
        self.assertIn('self.closeButton.addTarget(self, action: #selector(self.closePressed)', files)
        self.assertIn('self.closeButton.accessibilityLabel = self.strings.Common_Cancel', files)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_gradient_stops_for_invalid_data_hidden_views_and_reduced_motion(self):
        source = read('submodules/TelegramUI/Components/ButtonComponent/Sources/ButtonComponent.swift')
        fixture = 'import Foundation\nimport CoreGraphics\n'
        fixture += member(source, 'private func buttonGradientLocations(') + '\n'
        fixture += member(source, 'private func buttonGradientCanAnimate(') + '\n'
        fixture += '''
for count in [-1, 0, 1, 2, 3, 8, 30] {
    let locations = buttonGradientLocations(colorCount: count)
    precondition(locations.count == max(0, count))
    precondition(locations.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
    if count > 1 {
        precondition(locations.first == 0 && abs(locations.last! - 1) < 0.001)
        precondition(locations == locations.sorted())
    }
    for duration in [-Double.infinity, Double.nan, -2, 0, 0.1, 4.5, Double.infinity] {
        for hasWindow in [false, true] {
            for reduced in [false, true] {
                let animate = buttonGradientCanAnimate(colorCount: count, duration: duration, hasWindow: hasWindow, reduceMotion: reduced)
                precondition(animate == (count > 1 && duration.isFinite && duration > 0 && hasWindow && !reduced))
            }
        }
    }
}
'''
        run_swift(fixture)
        self.assertIn('guard self.currentGradient == gradient, self.currentSize == size else { return }', source)
        self.assertIn('if gradient.colors.count < 2', source)
        self.assertIn('override func didMoveToWindow()', source)
        self.assertIn('if foregroundChanged { activityIndicator.type = .custom(component.background.foreground', source)
        self.assertIn('UIAccessibility.reduceMotionStatusDidChangeNotification', source)

    def test_recipient_field_refreshes_presentation_without_replacing_the_editor(self):
        source = read('submodules/TelegramUI/Components/TokenListTextField/Sources/EditableTokenListNode.swift')
        refresh = member(source, 'func updatePresentation(')
        self.assertNotIn('.textField.text =', refresh)
        self.assertNotIn('resignFirstResponder', refresh)
        self.assertNotIn('selectedTokenId =', refresh)
        self.assertIn('self.presentationTheme !== presentationTheme', refresh)
        self.assertIn('self.textFieldNode.textField.reloadInputViews()', refresh)
        self.assertIn('node.token.title == token.title', source)
        self.assertIn('currentOffset.y += currentRowHeight', source)
        self.assertIn('width - currentOffset.x - rightSideInset - 8.0', source)
        self.assertIn('tokenNode.activate = { [weak self, weak tokenNode]', source)
        self.assertIn('self.deleteToken?(tokenNode.token.id)', source)
        wrapper = read('submodules/TelegramUI/Components/TokenListTextField/Sources/TokenListTextField.swift')
        self.assertIn('tokenListNode.updatePresentation(presentationTheme: component.theme, theme: tokenTheme, placeholder: component.placeholder)', wrapper)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_recipient_chip_bounds_with_long_names_and_large_text(self):
        source = read('submodules/TelegramUI/Components/TokenListTextField/Sources/EditableTokenListNode.swift')
        fixture = '''import Foundation
import CoreGraphics
class Label {
    var width: CGFloat = 0
    var height: CGFloat = 18
    func measure(_ size: CGSize) -> CGSize { CGSize(width: min(width, size.width), height: height) }
}
class Emoji {
    var supernode: Int?
    func updateLayout(_ size: CGSize) -> CGSize { .zero }
}
class Harness {
    let titleNode = Label()
    let emojiTextNode = Emoji()
'''
        fixture += member(source, 'override func calculateSizeThatFits(').replace('override func', 'func') + '\n}\n'
        fixture += '''
let view = Harness()
for width: CGFloat in [64, 120, 200, 300] {
    for textWidth: CGFloat in [0, 40, 10000] {
        for textHeight: CGFloat in [18, 40, 90] {
            for emoji in [false, true] {
                view.titleNode.width = textWidth
                view.titleNode.height = textHeight
                view.emojiTextNode.supernode = emoji ? 1 : nil
                let size = view.calculateSizeThatFits(CGSize(width: width, height: 1000))
                precondition(size.width <= width && size.width >= 0)
                precondition(size.height >= textHeight + 10 && size.height >= 28)
            }
        }
    }
}
'''
        run_swift(fixture)

    def test_shared_form_controls_scale_and_keep_localized_accessible_actions(self):
        field = read('submodules/TelegramUI/Components/ListTextFieldItemComponent/Sources/ListTextFieldItemComponent.swift')
        for contract in ('UIFont.preferredFont(forTextStyle: .body)',
                         'component.hasClearButton ? 44.0 : 0.0',
                         'counterIsVisible ? counterWidth + 8.0 : 0.0',
                         'self.textField.accessibilityLabel = component.placeholder',
                         'let keyboardAppearance: UIKeyboardAppearance = component.theme.overallDarkAppearance ? .dark : .light',
                         '(component.strings ?? defaultPresentationStrings).VoiceOver_Editing_ClearText'):
            self.assertIn(contract, field)
        toggle = read('submodules/TelegramUI/Components/SwitchComponent/Sources/SwitchComponent.swift')
        self.assertIn('self.switchView.onTintColor = component.tintColor', toggle)
        self.assertIn('self.switchView.accessibilityLabel = component.accessibilityLabel', toggle)
        row = read('submodules/TelegramUI/Components/ListSwitchItemComponent/Sources/ListSwitchItemComponent.swift')
        self.assertIn('accessibilityLabel: component.title', row)
        self.assertIn('maximumNumberOfLines: component.theme.isMessagesTheme ? 0 : 1', row)
        self.assertIn('titleView.accessibilityElementsHidden = true', row)

    @unittest.skipUnless(shutil.which('swift'), 'Swift unavailable locally; executes in macOS CI')
    def test_production_multiline_text_replacement_and_change_notifications(self):
        source = read('submodules/TelegramUI/Components/ListMultilineTextFieldItemComponent/Sources/ListMultilineTextFieldItemComponent.swift')
        fixture = '''import Foundation
class NativeTextField {
    var text = NSAttributedString(string: "")
    var changed: ((NSAttributedString) -> Void)?
    func setAttributedText(_ value: NSAttributedString, updateState: Bool) {
        text = value
        changed?(value)
    }
}
enum TextFieldComponent { typealias View = NativeTextField }
class Box { var view: AnyObject? = NativeTextField() }
class ExternalState {
    var text = NSAttributedString(string: "")
    var updated: (() -> Void)?
}
class Component {
    var externalState: ExternalState? = ExternalState()
    var updated: ((String) -> Void)?
}
enum Transition { case immediate }
class State {
    var updates = 0
    func updated(transition: Transition, isLocal: Bool) { updates += 1 }
}
class Harness {
    let textField = Box()
    let textFieldExternalState = ExternalState()
    var component: Component? = Component()
    var state: State? = State()
    var isUpdating = false
    var currentText: String { (textField.view as? NativeTextField)?.text.string ?? "" }
    init() {
'''
        fixture += member(source, 'self.textFieldExternalState.updated =')
        fixture += '''
        (self.textField.view as! NativeTextField).changed = { [weak self] value in
            self?.textFieldExternalState.text = value
            self?.textFieldExternalState.updated?()
        }
    }
'''
        fixture += member(source, 'public func setText(text: String, updateState: Bool)') + '\n}\n'
        fixture += '''
let view = Harness()
var delivered: [String] = []
view.component!.updated = { delivered.append($0) }
view.setText(text: "Draft 👩‍💻", updateState: false)
precondition(view.currentText == "Draft 👩‍💻" && delivered.isEmpty)
precondition(view.component!.externalState!.text.string == "Draft 👩‍💻")
view.setText(text: "Исправлено", updateState: true)
precondition(view.currentText == "Исправлено" && delivered == ["Исправлено"])
let native = view.textField.view as! NativeTextField
native.setAttributedText(NSAttributedString(string: "Typed"), updateState: true)
precondition(delivered == ["Исправлено", "Typed"])
view.isUpdating = true
view.setText(text: "Reset", updateState: false)
precondition(view.isUpdating && delivered.count == 2)
view.textField.view = nil
view.setText(text: "Unavailable", updateState: true)
precondition(delivered.count == 2)
'''
        run_swift(fixture)

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
