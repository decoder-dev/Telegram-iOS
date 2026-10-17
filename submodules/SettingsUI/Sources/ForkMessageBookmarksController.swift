import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class ForkMessageBookmarksArguments {
    let chooseFilter: () -> Void
    let openBookmark: (ForkMessageBookmark) -> Void

    init(chooseFilter: @escaping () -> Void, openBookmark: @escaping (ForkMessageBookmark) -> Void) {
        self.chooseFilter = chooseFilter
        self.openBookmark = openBookmark
    }
}

private enum ForkMessageBookmarksEntry: ItemListNodeEntry {
    case filter(String, String)
    case empty(String)
    case bookmark(Int, ForkMessageBookmark)

    var section: ItemListSectionId { 0 }

    var stableId: Int32 {
        switch self {
        case .filter:
            return -2
        case .empty:
            return -1
        case let .bookmark(index, _):
            return Int32(index)
        }
    }

    static func <(lhs: ForkMessageBookmarksEntry, rhs: ForkMessageBookmarksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkMessageBookmarksArguments
        switch self {
        case let .filter(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.chooseFilter()
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .bookmark(_, bookmark):
            let tags = bookmark.tags.map { "#\($0)" }.joined(separator: " ")
            return ItemListDisclosureItem(presentationData: presentationData, title: bookmark.chatTitle, label: tags, additionalDetailLabel: bookmark.snippet, sectionId: self.section, style: .blocks, action: {
                arguments.openBookmark(bookmark)
            })
        }
    }
}

/// Fork (Regram): list of this account's bookmarked messages. Filter by tag; tap to jump back to the message or remove it.
public func forkMessageBookmarksController(context: AccountContext) -> ViewController {
    let russian = ForkPresentationLanguage.prefersRussianStrings
    let accountPeerId = context.account.peerId
    let selectedTag = ValuePromise<String?>(nil, ignoreRepeated: true)
    let refresh = ValuePromise<Int>(0)
    let refreshCounter = Atomic<Int>(value: 0)

    var presentImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = ForkMessageBookmarksArguments(
        chooseFilter: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            var tags: [String] = []
            for bookmark in ForkMessageBookmarks.all(accountPeerId: accountPeerId) {
                for tag in bookmark.tags where !tags.contains(tag) {
                    tags.append(tag)
                }
            }
            let sheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            items.append(ActionSheetButtonItem(title: russian ? "Все" : "All", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                selectedTag.set(nil)
            }))
            for tag in tags {
                items.append(ActionSheetButtonItem(title: "#\(tag)", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    selectedTag.set(tag)
                }))
            }
            sheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])])
            presentImpl?(sheet)
        },
        openBookmark: { bookmark in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            sheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: bookmark.snippet, parseMarkdown: false),
                ActionSheetButtonItem(title: russian ? "Перейти к сообщению" : "Go to message", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    let peerId = EnginePeer.Id(bookmark.peerId)
                    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                    |> deliverOnMainQueue).startStandalone(next: { peer in
                        guard let peer, let navigationController = navigationControllerImpl?() else {
                            return
                        }
                        let messageId = EngineMessage.Id(peerId: peerId, namespace: bookmark.messageNamespace, id: bookmark.messageId)
                        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), useExisting: true))
                    })
                }),
                ActionSheetButtonItem(title: russian ? "Удалить закладку" : "Remove bookmark", color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    ForkMessageBookmarks.remove(accountPeerId: accountPeerId, identity: bookmark.identity)
                    let next = refreshCounter.modify { $0 + 1 }
                    refresh.set(next)
                })
            ]), ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])])
            presentImpl?(sheet)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        selectedTag.get(),
        refresh.get()
    )
    |> map { presentationData, tag, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var bookmarks = ForkMessageBookmarks.all(accountPeerId: accountPeerId)
        if let tag {
            bookmarks = bookmarks.filter { $0.tags.contains(tag) }
        }
        var entries: [ForkMessageBookmarksEntry] = []
        entries.append(.filter(russian ? "Тег" : "Tag", tag.flatMap { "#\($0)" } ?? (russian ? "Все" : "All")))
        if bookmarks.isEmpty {
            entries.append(.empty(russian ? "Закладок пока нет. Добавьте их из меню сообщения." : "No bookmarks yet. Add them from a message's menu."))
        } else {
            for (index, bookmark) in bookmarks.enumerated() {
                entries.append(.bookmark(index, bookmark))
            }
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(russian ? "Закладки" : "Bookmarks"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}
