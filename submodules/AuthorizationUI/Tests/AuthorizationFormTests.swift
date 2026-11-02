import UIKit
import XCTest
import AsyncDisplayKit
import Display
import AuthorizationUtils
import SolidRoundedButtonNode

final class AuthorizationFormTests: XCTestCase {
    func testOverflowScrollsAndKeepsTheFocusedFieldVisible() {
        for width: CGFloat in [320.0, 393.0, 768.0] {
            for height: CGFloat in [100.0, 220.0, 500.0] {
                let form = AuthorizationFormNode()
                let title = ASDisplayNode()
                let field = TextFieldNode()
                let action = ASDisplayNode()
                for node in [title, field, action] {
                    form.addSubnode(node)
                }
                let zero = AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)
                let items = [
                    AuthorizationLayoutItem(node: title, size: CGSize(width: width - 48.0, height: 200.0), spacingBefore: zero, spacingAfter: zero),
                    AuthorizationLayoutItem(node: field, size: CGSize(width: width - 88.0, height: 70.0), spacingBefore: zero, spacingAfter: zero),
                    AuthorizationLayoutItem(node: action, size: CGSize(width: width - 48.0, height: 44.0), spacingBefore: zero, spacingAfter: zero)
                ]
                form.update(bounds: CGRect(x: 24.0, y: 62.0, width: width, height: height), items: items, focusedNode: field, transition: .immediate)
                XCTAssertTrue(form.view.bounds.contains(field.frame))
                XCTAssertEqual(form.view.isScrollEnabled, height < 338.0)
                XCTAssertGreaterThanOrEqual(form.view.contentSize.height, height)
                XCTAssertGreaterThanOrEqual(field.frame.minY, title.frame.maxY)
                XCTAssertGreaterThanOrEqual(action.frame.minY, field.frame.maxY)
                XCTAssertEqual(form.view.contentInsetAdjustmentBehavior, .never)
                XCTAssertFalse(form.view.scrollsToTop)

                form.update(bounds: CGRect(x: 24.0, y: 62.0, width: width, height: 700.0), items: items, transition: .immediate)
                XCTAssertFalse(form.view.isScrollEnabled)
                XCTAssertEqual(form.view.contentOffset, .zero)
            }
        }
    }

    func testPreferenceObservationEndsWithTheFormLifetime() {
        var callbacks = 0
        var form: AuthorizationFormNode? = AuthorizationFormNode()
        form?.requestLayout = { callbacks += 1 }
        NotificationCenter.default.post(name: UIContentSizeCategory.didChangeNotification, object: nil)
        XCTAssertEqual(callbacks, 1)
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        XCTAssertEqual(callbacks, 2)
        weak var released = form
        form = nil
        XCTAssertNil(released)
        NotificationCenter.default.post(name: UIContentSizeCategory.didChangeNotification, object: nil)
        XCTAssertEqual(callbacks, 2)
    }

    func testNestedFieldsUseTheirFrameInTheScrollContent() {
        let form = AuthorizationFormNode()
        let title = ASDisplayNode()
        let group = ASDisplayNode()
        let field = TextFieldNode()
        form.addSubnode(title)
        form.addSubnode(group)
        group.addSubnode(field)
        field.frame = CGRect(x: 24.0, y: 120.0, width: 220.0, height: 44.0)
        let zero = AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)
        let items = [
            AuthorizationLayoutItem(node: title, size: CGSize(width: 200.0, height: 200.0), spacingBefore: zero, spacingAfter: zero),
            AuthorizationLayoutItem(node: group, size: CGSize(width: 300.0, height: 200.0), spacingBefore: zero, spacingAfter: zero)
        ]
        form.update(bounds: CGRect(x: 0.0, y: 62.0, width: 320.0, height: 100.0), items: items, focusedNode: field, transition: .immediate)
        XCTAssertTrue(form.view.bounds.contains(field.convert(field.bounds, to: form)))
    }

    func testContinueButtonFitsLargeAndWrappedTextAndShrinksAgain() {
        let button = SolidRoundedButtonNode(title: "Войти в аккаунт", theme: SolidRoundedButtonTheme(backgroundColor: .systemBlue, foregroundColor: .white), height: 50.0, cornerRadius: 25.0)
        let regularHeight = button.updateLayout(width: 300.0, fontSize: 17.0, transition: .immediate)
        let largeHeight = button.updateLayout(width: 300.0, fontSize: 34.0, transition: .immediate)
        let wrappedHeight = button.updateLayout(width: 160.0, fontSize: 34.0, transition: .immediate)
        XCTAssertEqual(regularHeight, 50.0)
        XCTAssertGreaterThan(largeHeight, regularHeight)
        XCTAssertGreaterThan(wrappedHeight, largeHeight)
        XCTAssertEqual(button.updateLayout(width: 300.0, fontSize: 17.0, transition: .immediate), regularHeight)
        XCTAssertEqual(button.accessibilityLabel?.trimmingCharacters(in: .whitespaces), "Войти в аккаунт")
    }

    func testProgressAndDisabledStateRemainVisibleToAccessibility() {
        let button = SolidRoundedButtonNode(title: "Continue", theme: SolidRoundedButtonTheme(backgroundColor: .systemBlue, foregroundColor: .white))
        let _ = button.updateLayout(width: 300.0, transition: .immediate)
        button.transitionToProgress()
        XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled))
        button.isEnabled = false
        button.transitionFromProgress()
        XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled))
        button.isEnabled = true
        XCTAssertFalse(button.accessibilityTraits.contains(.notEnabled))
    }

    func testEmbeddedProgressRemainsCenteredAfterTextAndWidthChanges() throws {
        let button = SolidRoundedButtonNode(title: "Continue", theme: SolidRoundedButtonTheme(backgroundColor: .systemBlue, foregroundColor: .white), height: 50.0)
        button.progressType = .embedded
        let _ = button.updateLayout(width: 260.0, fontSize: 17.0, transition: .immediate)
        button.transitionToProgress()
        let progress = try XCTUnwrap(button.subnodes?.first { $0.layer.animation(forKey: "progressRotation") != nil })
        let height = button.updateLayout(width: 320.0, fontSize: 34.0, transition: .immediate)
        XCTAssertEqual(progress.frame.midX, 160.0, accuracy: 0.5)
        XCTAssertEqual(progress.frame.midY, height * 0.5, accuracy: 0.5)
        XCTAssertLessThanOrEqual(progress.frame.height, 28.0)
    }
}
