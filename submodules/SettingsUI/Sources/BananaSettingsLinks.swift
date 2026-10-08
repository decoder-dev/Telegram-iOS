import Foundation
import UIKit
import Display
import ItemListUI
import AccountContext
import TelegramPresentationData

struct BananaSettingsItemTag: ItemListItemTag {
    let id: Int32
    func isEqual(to other: ItemListItemTag) -> Bool {
        return (other as? BananaSettingsItemTag)?.id == self.id
    }
}

// Stable paths are independent of translated labels and never change preferences.
func bananaSettingsLinkTarget(_ path: String) -> (ForkExtrasControllerFocus, Int32?)? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3, parts[0] == "bananagram" else { return nil }
    let focus: ForkExtrasControllerFocus
    switch parts[1] {
    case "general": focus = .top
    case "saving": focus = .ninja
    case "ghost": focus = .ghost
    case "privacy": focus = .privacy
    case "appearance": focus = .interface
    case "chats": focus = .chat
    case "network": focus = .network
    default: return nil
    }
    if parts.count == 3 {
        guard !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int32(parts[2]) else { return nil }
        return (focus, id)
    }
    return (focus, nil)
}

func bananaSettingsPage(_ focus: ForkExtrasControllerFocus) -> String {
    switch focus.resolvedCategory {
    case .top: return "general"
    case .ninja: return "saving"
    case .ghost: return "ghost"
    case .privacy: return "privacy"
    case .interface: return "appearance"
    case .chat: return "chats"
    case .network: return "network"
    case .messageSaving, .messageFilters: return "saving"
    }
}

final class BananaSettingsLinkGesture: NSObject, UIGestureRecognizerDelegate {
    private weak var controller: ItemListController?
    private let context: AccountContext
    private let page: String
    private var didHighlight = false

    init(controller: ItemListController, context: AccountContext, focus: ForkExtrasControllerFocus) {
        self.controller = controller
        self.context = context
        self.page = bananaSettingsPage(focus)
        super.init()
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        gesture.delegate = self
        controller.displayNode.view.addGestureRecognizer(gesture)
    }

    func highlight(id: Int32?) {
        guard !didHighlight, let id, let controller else { return }
        controller.forEachItemNode { node in
            if let item = node as? ItemListItemNode, let tag = item.tag as? BananaSettingsItemTag, tag.id == id {
                self.didHighlight = true
                item.displayHighlight()
            }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl || current is UITextField || current is UITextView { return false }
            if current === controller?.displayNode.view { break }
            view = current.superview
        }
        guard let controller else { return false }
        var found = false
        controller.forEachItemNode { node in
            if (node as? ItemListItemNode)?.tag is BananaSettingsItemTag,
               let touchedView = touch.view, touchedView === node.view || touchedView.isDescendant(of: node.view) {
                found = true
            }
        }
        return found
    }

    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let controller else { return }
        var target: Int32?
        controller.forEachItemNode { node in
            if let tag = (node as? ItemListItemNode)?.tag as? BananaSettingsItemTag,
               node.view.bounds.contains(gesture.location(in: node.view)) { target = tag.id }
        }
        guard let target else { return }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let url = "tg://settings/bananagram/\(page)/\(target)"
        let sheet = ActionSheetController(presentationData: data)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [ActionSheetTextItem(title: url), ActionSheetButtonItem(title: data.strings.Common_Copy, action: { [weak sheet] in
                UIPasteboard.general.string = url
                sheet?.dismissAnimated()
            })]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        controller.present(sheet, in: .window(.root))
    }
}
