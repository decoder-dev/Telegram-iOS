import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

private final class ForkChoiceArguments {
    let select: (Int) -> Void

    init(select: @escaping (Int) -> Void) {
        self.select = select
    }
}

private enum ForkChoiceEntry: ItemListNodeEntry {
    case option(index: Int, title: String, checked: Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .option(index, _, _):
            return Int32(index)
        }
    }

    static func <(lhs: ForkChoiceEntry, rhs: ForkChoiceEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkChoiceArguments
        switch self {
        case let .option(index, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(index)
            })
        }
    }
}

/// A setting's value picked from a list with a checkmark on the current one (Apple HIG: action sheets are for actions,
/// not for choosing a value). Tapping an option applies it and goes back.
func forkChoiceController(context: AccountContext, title: String, options: [String], selectedIndex: Int?, select: @escaping (Int) -> Void) -> ViewController {
    var popImpl: (() -> Void)?
    let arguments = ForkChoiceArguments(select: { index in
        select(index)
        popImpl?()
    })
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let entries = options.enumerated().map { ForkChoiceEntry.option(index: $0.offset, title: $0.element, checked: $0.offset == selectedIndex) }
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    popImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}
