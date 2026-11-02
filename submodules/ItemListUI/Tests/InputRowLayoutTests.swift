import UIKit
import XCTest
import AsyncDisplayKit
import Display
import ItemListUI
import PresentationStrings
import TelegramPresentationData
import TelegramUIPreferences

final class InputRowLayoutTests: XCTestCase {
    private let strings = PresentationStrings(
        primaryComponent: PresentationStrings.Component(languageCode: "en", localizedName: "English", pluralizationRulesCode: nil, dict: [:]),
        secondaryComponent: nil,
        groupingSeparator: ","
    )

    private func item(fontSize: PresentationFontSize = .regular, title: String = "Server", text: String = "value", suffix: String? = nil, type: ItemListSingleLineInputItemType = .regular(capitalization: false, autocorrection: false), enabled: Bool = true, textUpdated: @escaping (String) -> Void = { _ in }, processPaste: ((String) -> String)? = nil, action: @escaping () -> Void = {}) -> ItemListSingleLineInputItem {
        let data = ItemListPresentationData(theme: makeDefaultPresentationTheme(reference: .day, serviceBackgroundColor: nil), fontSize: fontSize, strings: self.strings, nameDisplayOrder: .firstLast, dateTimeFormat: PresentationDateTimeFormat())
        return ItemListSingleLineInputItem(presentationData: data, systemStyle: .glass, title: NSAttributedString(string: title, font: Font.regular(17.0), textColor: data.theme.list.itemPrimaryTextColor), text: text, placeholder: "Value", label: suffix, type: type, clearType: .always, enabled: enabled, sectionId: 0, textUpdated: textUpdated, processPaste: processPaste, action: action)
    }

    @discardableResult
    private func apply(_ item: ItemListSingleLineInputItem, to node: ItemListSingleLineInputItemNode, width: CGFloat) -> ListViewItemNodeLayout {
        let (layout, apply) = node.asyncLayout()(item, ListViewItemLayoutParams(width: width, leftInset: 0.0, rightInset: 0.0, availableHeight: 1000.0), ItemListNeighbors(top: .none, bottom: .none))
        apply()
        node.frame = CGRect(origin: .zero, size: layout.contentSize)
        let _ = node.view
        return layout
    }

    private func field(_ node: ItemListSingleLineInputItemNode) throws -> TextFieldNode {
        return try XCTUnwrap(node.subnodes?.compactMap { $0 as? TextFieldNode }.first)
    }

    private func textNode(_ node: ItemListSingleLineInputItemNode, text: String) throws -> TextNode {
        return try XCTUnwrap(node.subnodes?.compactMap { $0 as? TextNode }.first { $0.cachedLayout?.attributedString?.string == text })
    }

    func testLargeLabelsStackAndSuffixesDoNotCoverTheField() throws {
        let title = "Адрес сервера подключения"
        let suffix = "в месяц"
        for width: CGFloat in [320.0, 393.0, 768.0] {
            let node = ItemListSingleLineInputItemNode()
            let layout = self.apply(self.item(fontSize: .extraLargeX2, title: title, suffix: suffix), to: node, width: width)
            let field = try self.field(node)
            let titleNode = try self.textNode(node, text: title)
            let suffixNode = try self.textNode(node, text: suffix)
            XCTAssertFalse(try XCTUnwrap(titleNode.cachedLayout).truncated)
            XCTAssertGreaterThan(field.frame.minY, titleNode.frame.maxY)
            XCTAssertLessThan(field.frame.maxX, suffixNode.frame.minX)
            XCTAssertGreaterThanOrEqual(field.frame.width, 80.0)
            XCTAssertLessThanOrEqual(field.frame.maxY, layout.contentSize.height)
            XCTAssertEqual(field.textField.font?.pointSize, 26.0)
        }
    }

    func testUsernamePrefixStaysBesideTheFieldAndFontsUpdateOnReuse() throws {
        let node = ItemListSingleLineInputItemNode()
        self.apply(self.item(title: "t.me/", type: .username), to: node, width: 320.0)
        self.apply(self.item(fontSize: .extraLargeX2, title: "t.me/", type: .username), to: node, width: 320.0)
        let field = try self.field(node)
        let title = try self.textNode(node, text: "t.me/")
        XCTAssertLessThanOrEqual(title.frame.maxX, field.frame.minX)
        XCTAssertEqual(title.frame.midY, field.frame.midY, accuracy: 2.0)
        XCTAssertEqual(field.textField.font?.pointSize, 26.0)
    }

    func testClearReflectsActualTextAndCannotEditADisabledRow() throws {
        let node = ItemListSingleLineInputItemNode()
        var changes: [String] = []
        var actions = 0
        self.apply(self.item(textUpdated: { changes.append($0) }, action: { actions += 1 }), to: node, width: 320.0)
        let field = try self.field(node)
        let clear = try XCTUnwrap(node.subnodes?.compactMap { $0 as? HighlightableButtonNode }.first)
        XCTAssertTrue(clear.isAccessibilityElement)
        XCTAssertGreaterThanOrEqual(clear.frame.width, 44.0)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44.0)
        field.textField.text = ""
        field.textField.sendActions(for: .editingChanged)
        XCTAssertTrue(clear.isHidden)
        XCTAssertFalse(clear.isAccessibilityElement)
        XCTAssertEqual(changes, [""])

        self.apply(self.item(enabled: false, textUpdated: { changes.append($0) }, action: { actions += 1 }), to: node, width: 320.0)
        clear.sendActions(forControlEvents: .touchUpInside, with: nil)
        XCTAssertFalse(node.textField(field.textField, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "x"))
        XCTAssertFalse(node.textFieldShouldReturn(field.textField))
        XCTAssertEqual(field.textField.text, "value")
        XCTAssertEqual(changes, [""])
        XCTAssertEqual(actions, 0)
    }

    func testProcessedPasteUsesUTF16ForReplacementAndCaret() throws {
        let node = ItemListSingleLineInputItemNode()
        self.apply(self.item(text: "😀 value", processPaste: { _ in "🧑🏽‍💻" }), to: node, width: 320.0)
        let field = try self.field(node).textField
        let text = try XCTUnwrap(field.text)
        let range = NSRange(try XCTUnwrap(text.range(of: "v")), in: text)
        XCTAssertFalse(node.textField(field, shouldChangeCharactersIn: range, replacementString: "paste"))
        XCTAssertEqual(field.text, "😀 🧑🏽‍💻alue")
        let settled = self.expectation(description: "Caret after processed paste")
        DispatchQueue.main.async {
            if let selection = field.selectedTextRange {
                XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 10)
            } else {
                XCTFail("Missing selection")
            }
            settled.fulfill()
        }
        self.wait(for: [settled], timeout: 3.0)
    }
}
