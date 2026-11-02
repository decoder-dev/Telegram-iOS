import UIKit
import XCTest
import AsyncDisplayKit
import Display
import SearchBarNode
import PresentationStrings
import TelegramPresentationData

final class SearchBarLayoutTests: XCTestCase {
    private let strings = PresentationStrings(
        primaryComponent: PresentationStrings.Component(languageCode: "en", localizedName: "English", pluralizationRulesCode: nil, dict: [:]),
        secondaryComponent: nil,
        groupingSeparator: ","
    )

    private func button(_ node: SearchBarNode, label: String) throws -> HighlightableButtonNode {
        return try XCTUnwrap(node.subnodes?.compactMap { $0 as? HighlightableButtonNode }.first { $0.accessibilityLabel == label })
    }

    func testClearTargetReceivesTouchesBesideTheGlyphAndClearsText() throws {
        for width: CGFloat in [320.0, 393.0, 768.0] {
            for (style, height): (SearchBarStyle, CGFloat) in [(.legacy, 82.0), (.modern, 54.0), (.glass, 44.0), (.inlineNavigation, 48.0)] {
                let theme = makeDefaultPresentationTheme(reference: .day, serviceBackgroundColor: nil)
                let node = SearchBarNode(theme: SearchBarNodeTheme(theme: theme), presentationTheme: theme, strings: self.strings, fieldStyle: style)
                node.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
                node.text = "Query"
                node.updateLayout(boundingSize: node.bounds.size, leftInset: 0.0, rightInset: 0.0, transition: .immediate)
                let clear = try self.button(node, label: self.strings.WebSearch_RecentSectionClear)
                XCTAssertTrue(clear.isAccessibilityElement)
                XCTAssertTrue(clear.isEnabled)
                XCTAssertGreaterThanOrEqual(clear.bounds.width - clear.hitTestSlop.left - clear.hitTestSlop.right, 44.0)
                XCTAssertGreaterThanOrEqual(clear.bounds.height - clear.hitTestSlop.top - clear.hitTestSlop.bottom, 44.0)
                let point = clear.view.convert(CGPoint(x: clear.bounds.midX - 20.0, y: clear.bounds.midY), to: node.view)
                let hit = try XCTUnwrap(node.view.hitTest(point, with: nil))
                XCTAssertTrue(hit === clear.view || hit.isDescendant(of: clear.view))
                clear.sendActions(forControlEvents: .touchUpInside, with: nil)
                XCTAssertEqual(node.text, "")
                XCTAssertFalse(clear.isAccessibilityElement)
                XCTAssertFalse(clear.isEnabled)
            }
        }
    }

    func testCancelHasAFullTargetAndKeepsItsCallback() throws {
        let theme = makeDefaultPresentationTheme(reference: .night, serviceBackgroundColor: nil)
        let node = SearchBarNode(theme: SearchBarNodeTheme(theme: theme), presentationTheme: theme, strings: self.strings, fieldStyle: .modern)
        node.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 54.0)
        node.updateLayout(boundingSize: node.bounds.size, leftInset: 0.0, rightInset: 0.0, transition: .immediate)
        var cancellations = 0
        node.cancel = { cancellations += 1 }
        let cancel = try self.button(node, label: self.strings.Common_Cancel)
        XCTAssertGreaterThanOrEqual(cancel.frame.width, 44.0)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44.0)
        cancel.sendActions(forControlEvents: .touchUpInside, with: nil)
        XCTAssertEqual(cancellations, 1)
    }
}
