import UIKit
import XCTest
import AsyncDisplayKit
import Display
import ItemListUI
import AccountContext
import ContactListUI
import PresentationStrings
import TelegramPresentationData

final class ContactRowLayoutTests: XCTestCase {
    private let strings = PresentationStrings(
        primaryComponent: PresentationStrings.Component(languageCode: "en", localizedName: "English", pluralizationRulesCode: nil, dict: [:]),
        secondaryComponent: nil,
        groupingSeparator: ","
    )

    private func data(_ size: PresentationFontSize) -> ItemListPresentationData {
        return ItemListPresentationData(theme: makeDefaultPresentationTheme(reference: .day, serviceBackgroundColor: nil), fontSize: size, strings: self.strings, nameDisplayOrder: .firstLast, dateTimeFormat: PresentationDateTimeFormat())
    }

    private func node(_ item: ListViewItem, width: CGFloat) throws -> ListViewItemNode {
        let configured = self.expectation(description: "Configured contact row")
        var result: ListViewItemNode?
        item.nodeConfiguredForParams(async: { $0() }, params: ListViewItemLayoutParams(width: width, leftInset: 20.0, rightInset: 28.0, availableHeight: 1000.0), synchronousLoads: true, neighbors: .none, completion: { node, prepare in
            prepare().1(ListViewItemApply())
            node.frame = CGRect(origin: .zero, size: node.contentSize)
            result = node
            configured.fulfill()
        })
        self.wait(for: [configured], timeout: 5.0)
        return try XCTUnwrap(result)
    }

    func testLimitedPermissionKeepsDescriptionAndManageActionSeparate() throws {
        let description = "Приложению доступны только выбранные контакты. Вы можете изменить список в любое время."
        for size: PresentationFontSize in [.regular, .extraLargeX2] {
            for width: CGFloat in [320.0, 393.0, 768.0] {
                var actions = 0
                let node = try self.node(LimitedPermissionItem(presentationData: self.data(size), text: description, action: { actions += 1 }), width: width)
                let text = try XCTUnwrap(node.subnodes?.compactMap { $0 as? TextNode }.first { $0.cachedLayout?.attributedString?.string == description })
                let button = try XCTUnwrap(node.subnodes?.compactMap { $0 as? HighlightableButtonNode }.first)
                XCTAssertFalse(try XCTUnwrap(text.cachedLayout).truncated)
                XCTAssertFalse(text.frame.intersects(button.frame))
                XCTAssertGreaterThanOrEqual(button.frame.width, 44.0)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44.0)
                XCTAssertLessThanOrEqual(button.frame.maxY, node.contentSize.height)
                XCTAssertLessThanOrEqual(button.frame.maxX, width - 44.0)
                XCTAssertEqual(button.accessibilityLabel, self.strings.Contacts_LimitedAccess_Manage)
                button.sendActions(forControlEvents: .touchUpInside, with: nil)
                XCTAssertEqual(actions, 1)
            }
        }
    }

    func testTallContactActionGrowsAndKeepsLeadingIconOutsideText() throws {
        let title = "Пригласить друзей и близких в приложение"
        let subtitle = "Ссылка для приглашения доступна через системное меню"
        let icon = try XCTUnwrap(generateFilledCircleImage(diameter: 14.0, color: .red))
        let item = ContactListActionItem(presentationData: self.data(.extraLargeX2), title: title, subtitle: subtitle, icon: .inline(icon, .left), actionStyle: .generic, height: .tall, header: nil, action: {})
        let node = try self.node(item, width: 320.0)
        let titleNode = try XCTUnwrap(node.subnodes?.compactMap { $0 as? TextNode }.first { $0.cachedLayout?.attributedString?.string == title })
        let subtitleNode = try XCTUnwrap(node.subnodes?.compactMap { $0 as? TextNode }.first { $0.cachedLayout?.attributedString?.string == subtitle })
        let iconNode = try XCTUnwrap(node.subnodes?.compactMap { $0 as? ASImageNode }.first { $0.image === icon })
        XCTAssertFalse(try XCTUnwrap(titleNode.cachedLayout).truncated)
        XCTAssertFalse(try XCTUnwrap(subtitleNode.cachedLayout).truncated)
        XCTAssertGreaterThanOrEqual(titleNode.frame.minX, iconNode.frame.maxX + 4.0)
        XCTAssertLessThanOrEqual(subtitleNode.frame.maxY, node.contentSize.height)
        XCTAssertGreaterThan(node.contentSize.height, 50.0)
        let area = try XCTUnwrap(node.subnodes?.compactMap { $0 as? AccessibilityAreaNode }.first)
        XCTAssertEqual(area.accessibilityValue, subtitle)
        XCTAssertTrue(area.accessibilityTraits.contains(.button))
    }
}
