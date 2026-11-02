import UIKit
import XCTest
import AsyncDisplayKit
import Display
import ItemListUI
import PresentationStrings
import TelegramPresentationData

final class ChoiceRowLayoutTests: XCTestCase {
    private let strings = PresentationStrings(
        primaryComponent: PresentationStrings.Component(languageCode: "en", localizedName: "English", pluralizationRulesCode: nil, dict: [:]),
        secondaryComponent: nil,
        groupingSeparator: ","
    )

    private func presentationData() -> ItemListPresentationData {
        return ItemListPresentationData(theme: makeDefaultPresentationTheme(reference: .day, serviceBackgroundColor: nil), fontSize: .extraLargeX2, strings: self.strings, nameDisplayOrder: .firstLast, dateTimeFormat: PresentationDateTimeFormat())
    }

    private func descendants(_ node: ASDisplayNode) -> [ASDisplayNode] {
        return (node.subnodes ?? []).flatMap { [$0] + self.descendants($0) }
    }

    func testLongActionWrapsWithinBothSafeInsets() throws {
        let title = "Удалить только загруженные копии файлов на этом устройстве"
        for width: CGFloat in [320.0, 393.0, 768.0] {
            for alignment: ItemListActionAlignment in [.natural, .center] {
                let item = ItemListActionItem(presentationData: self.presentationData(), title: title, kind: .generic, alignment: alignment, sectionId: 0, style: .blocks, action: {})
                let node = ItemListActionItemNode()
                let params = ListViewItemLayoutParams(width: width, leftInset: 20.0, rightInset: 28.0, availableHeight: 1000.0)
                let (layout, apply) = node.asyncLayout()(item, params, ItemListNeighbors(top: .none, bottom: .none))
                apply(false)
                let text = try XCTUnwrap(self.descendants(node).compactMap { $0 as? TextNode }.first)
                XCTAssertFalse(try XCTUnwrap(text.cachedLayout).truncated)
                XCTAssertGreaterThanOrEqual(text.frame.minX, 36.0)
                XCTAssertLessThanOrEqual(text.frame.maxX, width - 44.0)
                XCTAssertLessThanOrEqual(text.frame.maxY, layout.contentSize.height)
            }
        }
    }

    func testDisabledActionBlocksVoiceOverAndLongPressAfterReuse() throws {
        let node = ItemListActionItemNode()
        var actions = 0
        var longPresses = 0
        for kind: ItemListActionKind in [.generic, .disabled, .destructive] {
            let item = ItemListActionItem(presentationData: self.presentationData(), title: "Action", kind: kind, alignment: .natural, sectionId: 0, style: .blocks, action: { actions += 1 }, longTapAction: { longPresses += 1 })
            let (_, apply) = node.asyncLayout()(item, ListViewItemLayoutParams(width: 320.0, leftInset: 0.0, rightInset: 0.0, availableHeight: 1000.0), ItemListNeighbors(top: .none, bottom: .none))
            apply(false)
            let area = try XCTUnwrap(self.descendants(node).compactMap { $0 as? AccessibilityAreaNode }.first)
            XCTAssertEqual(area.accessibilityActivate(), kind != .disabled)
            XCTAssertEqual(item.selectable, kind != .disabled)
            XCTAssertEqual(node.canBeLongTapped, kind != .disabled)
            node.longTapped()
            XCTAssertEqual(area.accessibilityTraits.contains(.notEnabled), kind == .disabled)
        }
        XCTAssertEqual(actions, 2)
        XCTAssertEqual(longPresses, 2)
    }

    func testChoiceWrapsAndAnnouncesSubtitleAndSelection() throws {
        let title = "Разрешить уведомления о сообщениях и входящих звонках"
        let subtitle = "Используется для личных чатов, групп и каналов"
        for width: CGFloat in [320.0, 393.0, 768.0] {
            for style: ItemListCheckboxItemStyle in [.left, .right] {
                let node = ItemListCheckboxItemNode()
                let item = ItemListCheckboxItem(presentationData: self.presentationData(), title: title, subtitle: subtitle, style: style, checked: true, zeroSeparatorInsets: false, sectionId: 0, action: {})
                let (_, apply) = node.asyncLayout()(item, ListViewItemLayoutParams(width: width, leftInset: 20.0, rightInset: 28.0, availableHeight: 1000.0), ItemListNeighbors(top: .none, bottom: .none))
                apply()
                let nodes = self.descendants(node)
                let texts = nodes.compactMap { $0 as? TextNode }
                XCTAssertEqual(texts.count, 2)
                for text in texts {
                    XCTAssertFalse(try XCTUnwrap(text.cachedLayout).truncated)
                    XCTAssertLessThanOrEqual(text.frame.maxX, width - 28.0 - (style == .right ? 48.0 : 16.0))
                }
                let area = try XCTUnwrap(nodes.compactMap { $0 as? AccessibilityAreaNode }.first)
                XCTAssertEqual(area.accessibilityLabel, title)
                XCTAssertEqual(area.accessibilityValue, subtitle)
                XCTAssertTrue(area.accessibilityTraits.contains(.button))
                XCTAssertTrue(area.accessibilityTraits.contains(.selected))
            }
        }
    }

    func testDisabledChoiceCannotActivateThroughVoiceOver() throws {
        let node = ItemListCheckboxItemNode()
        var actions = 0
        for enabled in [true, false, true] {
            let item = ItemListCheckboxItem(presentationData: self.presentationData(), title: "Choice", style: .right, checked: enabled, enabled: enabled, zeroSeparatorInsets: false, sectionId: 0, action: { actions += 1 })
            let (_, apply) = node.asyncLayout()(item, ListViewItemLayoutParams(width: 320.0, leftInset: 0.0, rightInset: 0.0, availableHeight: 1000.0), ItemListNeighbors(top: .none, bottom: .none))
            apply()
            let area = try XCTUnwrap(self.descendants(node).compactMap { $0 as? AccessibilityAreaNode }.first)
            XCTAssertEqual(area.accessibilityActivate(), enabled)
            XCTAssertEqual(item.selectable, enabled)
            XCTAssertEqual(area.accessibilityTraits.contains(.notEnabled), !enabled)
        }
        XCTAssertEqual(actions, 2)
    }
}
