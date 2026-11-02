import UIKit
import XCTest
import AsyncDisplayKit
@testable import Display

final class AlertActionStateTests: XCTestCase {
    private func sheetTheme() -> ActionSheetControllerTheme {
        return ActionSheetControllerTheme(dimColor: .black, backgroundType: .light, itemBackgroundColor: .white, itemHighlightedBackgroundColor: .lightGray, standardActionTextColor: .blue, destructiveActionTextColor: .red, disabledActionTextColor: .gray, primaryTextColor: .black, secondaryTextColor: .darkGray, controlAccentColor: .blue, controlColor: .gray, switchFrameColor: .gray, switchContentColor: .green, switchHandleColor: .white, baseFontSize: 26.0)
    }

    func testSheetDisabledActionBlocksTouchKeyboardAndVoiceOverAfterReuse() throws {
        var actions = 0
        let node = ActionSheetButtonItem(title: "Action", action: { actions += 1 }).node(theme: self.sheetTheme())
        let button = try XCTUnwrap(node.view.subviews.compactMap { $0 as? UIButton }.first)
        let area = try XCTUnwrap(node.subnodes?.compactMap { $0 as? AccessibilityAreaNode }.first)
        for enabled in [true, false, true] {
            ActionSheetButtonItem(title: "Action", enabled: enabled, action: { actions += 1 }).updateNode(node)
            let previous = actions
            XCTAssertEqual(area.accessibilityActivate(), enabled)
            node.performAction()
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(actions, previous + (enabled ? 3 : 0))
            XCTAssertEqual(button.isEnabled, enabled)
            XCTAssertEqual(area.accessibilityTraits.contains(.notEnabled), !enabled)
        }
    }

    func testAlertDisabledActionBlocksProgrammaticPressAndKeyboard() {
        let theme = AlertControllerTheme(backgroundType: .light, backgroundColor: .white, separatorColor: .lightGray, highlightedItemColor: .lightGray, primaryColor: .black, secondaryColor: .darkGray, accentColor: .blue, contrastColor: .white, destructiveColor: .red, disabledColor: .gray, controlBorderColor: .gray, baseFontSize: 17.0)
        var actions = 0
        let node = TextAlertContentActionNode(theme: theme, action: TextAlertAction(type: .destructiveAction, title: "Delete", action: { actions += 1 }))
        for enabled in [true, false, true] {
            node.actionEnabled = enabled
            let previous = actions
            node.performAction()
            node.pressed()
            XCTAssertEqual(actions, previous + (enabled ? 2 : 0))
            XCTAssertEqual(node.accessibilityTraits.contains(.notEnabled), !enabled)
        }
    }

    func testSheetLabelsKeepTheirFullHeightWhenTheGroupMustScroll() throws {
        let title = Array(repeating: "Длинное описание действия с данными пользователя", count: 8).joined(separator: " ")
        for width: CGFloat in [272.0, 320.0, 393.0] {
            for item: ActionSheetItem in [ActionSheetTextItem(title: title), ActionSheetButtonItem(title: title, action: {})] {
                let node = item.node(theme: self.sheetTheme())
                let size = node.updateLayout(constrainedSize: CGSize(width: width, height: 20.0), transition: .immediate)
                let text = try XCTUnwrap(node.subnodes?.compactMap { $0 as? ImmediateTextNode }.first)
                XCTAssertFalse(try XCTUnwrap(text.cachedLayout).truncated)
                XCTAssertGreaterThan(size.height, 57.0)
                XCTAssertLessThanOrEqual(text.frame.maxY, size.height)
            }
        }
    }

    func testSheetReadsRenderedMarkdownInsteadOfFormattingMarkers() throws {
        let node = ActionSheetTextItem(title: "Удалить **все копии**?", parseMarkdown: true).node(theme: self.sheetTheme())
        let area = try XCTUnwrap(node.subnodes?.compactMap { $0 as? AccessibilityAreaNode }.first)
        XCTAssertEqual(area.accessibilityLabel, "Удалить все копии?")
    }
}
