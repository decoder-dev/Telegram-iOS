import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext

private final class ForkMessageMenuArguments {
    let toggle: (ForkMessageMenuItem, Bool) -> Void
    let openMove: (ForkMessageMenuItem) -> Void
    let reset: () -> Void

    init(toggle: @escaping (ForkMessageMenuItem, Bool) -> Void, openMove: @escaping (ForkMessageMenuItem) -> Void, reset: @escaping () -> Void) {
        self.toggle = toggle
        self.openMove = openMove
        self.reset = reset
    }
}

/// Fork menu items that already have their own Extras switch. The editor flips that switch instead of keeping a second
/// "hidden" flag, so the two screens never disagree.
private func forkMessageMenuFeatureKeyPath(_ item: ForkMessageMenuItem) -> WritableKeyPath<ForkExtrasSettings, Bool>? {
    switch item {
    case .saveStickerToPhotos:
        return \.saveStickerToPhotos
    case .mediaInfo:
        return \.showMediaInfo
    case .saveToSavedMessages:
        return \.saveToCloudMenu
    case .screenshot:
        return \.messageShot
    case .selectFromAuthor:
        return \.selectFromAuthor
    case .repeatMessage:
        return \.repeatMessageMenu
    case .messageJson:
        return \.messageJsonMenu
    default:
        return nil
    }
}

private func forkMessageMenuItemIsShown(_ item: ForkMessageMenuItem, settings: ForkExtrasSettings) -> Bool {
    if let keyPath = forkMessageMenuFeatureKeyPath(item) {
        return settings[keyPath: keyPath]
    }
    return !settings.messageMenuHiddenItems.contains(item.rawValue)
}

private func forkMessageMenuItemTitle(_ item: ForkMessageMenuItem, strings: PresentationStrings, russian: Bool) -> String {
    switch item {
    case .reply:
        return strings.Conversation_ContextMenuReply
    case .editHistory:
        return forkEditHistoryMenuTitle(strings)
    case .copy:
        return strings.Conversation_ContextMenuCopy
    case .translate:
        return strings.Conversation_ContextMenuTranslate
    case .saveMedia:
        return russian ? "Сохранить фото или видео" : "Save Photo or Video"
    case .saveToFiles:
        return strings.Conversation_SaveToFiles
    case .convertAudio:
        return russian ? "Отправить как аудио или голосовое" : "Send as Audio or Voice"
    case .viewReplies:
        return strings.Conversation_ContextViewThread
    case .edit:
        return strings.Conversation_MessageDialogEdit
    case .pin:
        return "\(strings.Conversation_Pin) / \(strings.Conversation_Unpin)"
    case .copyLink:
        return strings.Conversation_ContextMenuCopyLink
    case .saveGif:
        return strings.Conversation_SaveGif
    case .forward:
        return strings.Conversation_ContextMenuForward
    case .saveStickerToPhotos:
        return russian ? "Сохранить стикер в Фото" : "Save Sticker to Photos"
    case .mediaInfo:
        return russian ? "Сведения о медиа" : "Media Info"
    case .saveToSavedMessages:
        return forkSavedMessagesMenuTitle(strings)
    case .screenshot:
        return russian ? "Скриншот" : "Screenshot"
    case .bookmarks:
        return russian ? "Закладки" : "Bookmarks"
    case .selectFromAuthor:
        return russian ? "Выбрать от автора" : "Select from Author"
    case .repeatMessage:
        return russian ? "Повторить, переслать без автора" : "Repeat, Forward Without Author"
    case .summarize:
        return russian ? "Кратко (на устройстве)" : "Summarize (On Device)"
    case .messageJson:
        return russian ? "JSON сообщения" : "Message JSON"
    case .report:
        return strings.Conversation_ContextMenuReport
    case .shadowBan:
        return russian ? "Теневой бан" : "Shadow Ban"
    case .statistics:
        return strings.Conversation_ContextViewStats
    case .delete:
        return strings.Conversation_ContextMenuDelete
    case .select:
        return strings.Conversation_ContextMenuSelect
    }
}

private enum ForkMessageMenuEntry: ItemListNodeEntry {
    case itemsHeader(String)
    case menuItem(index: Int, item: ForkMessageMenuItem, title: String, isShown: Bool)
    case itemsFooter(String)
    case select(String, Bool)
    case selectFooter(String)
    case reset(String)

    var section: ItemListSectionId {
        switch self {
        case .itemsHeader, .menuItem, .itemsFooter:
            return 0
        case .select, .selectFooter:
            return 1
        case .reset:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .itemsHeader:
            return 0
        case let .menuItem(_, item, _, _):
            // Keyed by the item, not its position, so a move animates the row instead of retitling two rows.
            return 100 + Int32(ForkMessageMenuItem.allCases.firstIndex(of: item) ?? 0)
        case .itemsFooter:
            return 1
        case .select:
            return 2
        case .selectFooter:
            return 3
        case .reset:
            return 4
        }
    }

    private var sortIndex: Int {
        switch self {
        case .itemsHeader:
            return 0
        case let .menuItem(index, _, _, _):
            return 1 + index
        case .itemsFooter:
            return 1000
        case .select:
            return 1001
        case .selectFooter:
            return 1002
        case .reset:
            return 1003
        }
    }

    static func <(lhs: ForkMessageMenuEntry, rhs: ForkMessageMenuEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkMessageMenuArguments
        switch self {
        case let .itemsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .menuItem(_, item, title, isShown):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: isShown, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(item, value)
            }, action: {
                arguments.openMove(item)
            })
        case let .itemsFooter(text), let .selectFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .select(title, isShown):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: isShown, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(.select, value)
            })
        case let .reset(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reset()
            })
        }
    }
}

/// Extras › Message Actions › Message Menu: show or hide each message long-press item and change their order.
/// Tapping a row offers Move Up / Move Down, since ItemListSwitchItem rows can't be dragged.
public func forkMessageMenuController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let update: (@escaping (inout ForkExtrasSettings) -> Void) -> Void = { f in
        let _ = updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
            var updated = current
            f(&updated)
            return updated
        }).start()
    }

    let move: (ForkMessageMenuItem, Int) -> Void = { item, offset in
        update { settings in
            var order = ForkMessageMenuItem.order(stored: settings.messageMenuOrder).filter { $0.isMovable }
            guard let index = order.firstIndex(of: item), order.indices.contains(index + offset) else {
                return
            }
            order.swapAt(index, index + offset)
            // Back at the stock order means nothing to store: the menu then skips the sorting pass.
            settings.messageMenuOrder = order == ForkMessageMenuItem.allCases.filter({ $0.isMovable }) ? [] : order.map { $0.rawValue }
        }
    }

    let arguments = ForkMessageMenuArguments(toggle: { item, value in
        update { settings in
            if let keyPath = forkMessageMenuFeatureKeyPath(item) {
                settings[keyPath: keyPath] = value
            } else {
                settings.messageMenuHiddenItems.removeAll(where: { $0 == item.rawValue })
                if !value {
                    settings.messageMenuHiddenItems.append(item.rawValue)
                }
            }
        }
    }, openMove: { item in
        let _ = (forkExtrasSettings(accountManager: context.sharedContext.accountManager)
        |> take(1)
        |> deliverOnMainQueue).start(next: { settings in
            let order = ForkMessageMenuItem.order(stored: settings.messageMenuOrder).filter { $0.isMovable }
            guard let index = order.firstIndex(of: item) else {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let russian = ForkPresentationLanguage.prefersRussianStrings
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = [ActionSheetTextItem(title: forkMessageMenuItemTitle(item, strings: presentationData.strings, russian: russian))]
            if index > 0 {
                items.append(ActionSheetButtonItem(title: russian ? "Переместить выше" : "Move Up", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    move(item, -1)
                }))
            }
            if index < order.count - 1 {
                items.append(ActionSheetButtonItem(title: russian ? "Переместить ниже" : "Move Down", color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    move(item, 1)
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })])
            ])
            presentControllerImpl?(actionSheet)
        })
    }, reset: {
        update { settings in
            settings.messageMenuHiddenItems = []
            settings.messageMenuOrder = []
        }
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: context.sharedContext.accountManager)
    )
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = ForkPresentationLanguage.prefersRussianStrings
        let strings = presentationData.strings

        var entries: [ForkMessageMenuEntry] = []
        entries.append(.itemsHeader(russian ? "ПУНКТЫ МЕНЮ" : "MENU ITEMS"))
        for (index, item) in ForkMessageMenuItem.order(stored: settings.messageMenuOrder).filter({ $0.isMovable }).enumerated() {
            entries.append(.menuItem(index: index, item: item, title: forkMessageMenuItemTitle(item, strings: strings, russian: russian), isShown: forkMessageMenuItemIsShown(item, settings: settings)))
        }
        entries.append(.itemsFooter(russian ? "Коснитесь пункта, чтобы переместить его. Пункты видны только там, где они доступны. Скрытое «Удалить» остаётся при выборе сообщений." : "Tap an item to move it. Items appear only where they apply. A hidden Delete stays available when you select messages."))
        entries.append(.select(forkMessageMenuItemTitle(.select, strings: strings, russian: russian), forkMessageMenuItemIsShown(.select, settings: settings)))
        entries.append(.selectFooter(russian ? "«Выбрать» всегда внизу меню, под разделителем." : "Select always stays at the bottom of the menu, under a separator."))
        if !settings.messageMenuHiddenItems.isEmpty || !settings.messageMenuOrder.isEmpty {
            entries.append(.reset(russian ? "Сбросить порядок и скрытые пункты" : "Reset Order and Hidden Items"))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(russian ? "Меню сообщения" : "Message Menu"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] presented in
        controller?.present(presented, in: .window(.root))
    }
    return controller
}
