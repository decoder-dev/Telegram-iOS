import Foundation
import UIKit
import XCTest
import AsyncDisplayKit
import Display
import ItemListUI
import PresentationStrings
import TelegramPresentationData
import TelegramUIPreferences

final class SettingsRowLayoutTests: XCTestCase {
    private let strings = PresentationStrings(
        primaryComponent: PresentationStrings.Component(languageCode: "en", localizedName: "English", pluralizationRulesCode: nil, dict: [:]),
        secondaryComponent: nil,
        groupingSeparator: ","
    )

    private func row(width: CGFloat, fontSize: PresentationFontSize, dark: Bool = false, style: ItemListSystemStyle = .glass, title: String, value: String, labelStyle: ItemListDisclosureLabelStyle = .text) -> (ItemListDisclosureItemNode, ListViewItemNodeLayout) {
        let data = ItemListPresentationData(
            theme: makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil),
            fontSize: fontSize,
            strings: self.strings,
            nameDisplayOrder: .firstLast,
            dateTimeFormat: PresentationDateTimeFormat()
        )
        let item = ItemListDisclosureItem(presentationData: data, systemStyle: style, title: title, label: value, labelStyle: labelStyle, sectionId: 0, style: .blocks, action: {})
        let node = ItemListDisclosureItemNode()
        let params = ListViewItemLayoutParams(width: width, leftInset: 0.0, rightInset: 0.0, availableHeight: 1000.0)
        let (layout, apply) = node.asyncLayout()(item, params, ItemListNeighbors(top: .none, bottom: .none))
        apply()
        node.frame = CGRect(origin: .zero, size: layout.contentSize)
        return (node, layout)
    }

    private func titleNode(_ node: ItemListDisclosureItemNode, text: String) throws -> TextNode {
        return try XCTUnwrap(node.subnodes?.compactMap { $0 as? TextNode }.first { $0.cachedLayout?.attributedString?.string == text })
    }

    func testRegularRowsKeepTheirTrailingValue() throws {
        let title = "Notifications"
        for width: CGFloat in [320.0, 393.0, 768.0] {
            let (node, layout) = self.row(width: width, fontSize: .regular, title: title, value: "On")
            let titleNode = try self.titleNode(node, text: title)
            XCTAssertLessThanOrEqual(titleNode.frame.maxX, node.labelNode.frame.minX)
            XCTAssertLessThan(abs(titleNode.frame.midY - node.labelNode.frame.midY), 4.0)
            XCTAssertGreaterThanOrEqual(layout.contentSize.height, PresentationLayoutMetrics.minimumInteractiveSize)
        }
    }

    func testLargeTextKeepsTitlesAndValuesOnSeparateLines() throws {
        let title = "Уведомления и звуки для сообщений и звонков"
        let value = "Личные чаты, группы и каналы"
        for width: CGFloat in [320.0, 393.0, 768.0] {
            for dark in [false, true] {
                for style: ItemListSystemStyle in [.legacy, .glass] {
                    let (node, layout) = self.row(width: width, fontSize: .extraLargeX2, dark: dark, style: style, title: title, value: value)
                    let titleNode = try self.titleNode(node, text: title)
                    XCTAssertFalse(try XCTUnwrap(titleNode.cachedLayout).truncated)
                    XCTAssertFalse(try XCTUnwrap(node.labelNode.cachedLayout).truncated)
                    XCTAssertGreaterThanOrEqual(node.labelNode.frame.minY, titleNode.frame.maxY)
                    XCTAssertEqual(node.labelNode.frame.minX, titleNode.frame.minX)
                    XCTAssertLessThanOrEqual(node.labelNode.frame.maxY, layout.contentSize.height)
                    XCTAssertLessThanOrEqual(titleNode.frame.maxX, width)
                }
            }
        }
    }

    func testLargeTextDoesNotMoveBadgesUnderTheTitle() throws {
        let title = "Storage"
        for width: CGFloat in [320.0, 393.0] {
            let (node, _) = self.row(width: width, fontSize: .extraLargeX2, title: title, value: "12", labelStyle: .badge(.red))
            let titleNode = try self.titleNode(node, text: title)
            XCTAssertGreaterThan(node.labelNode.frame.minX, titleNode.frame.maxX)
            XCTAssertLessThan(abs(node.labelNode.frame.midY - titleNode.frame.midY), 4.0)
        }
    }
}
