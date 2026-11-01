import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import AccountContext
import AccountUtils
import TelegramUIPreferences

private final class AccountOrderArguments {
    let context: AccountContext

    init(context: AccountContext) {
        self.context = context
    }
}

private enum AccountOrderEntryStableId: Hashable {
    case account(AccountRecordId)
    case notice
}

private enum AccountOrderEntry: ItemListNodeEntry {
    case account(index: Int, context: AccountContext, peer: EnginePeer)
    case notice(text: String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: AccountOrderEntryStableId {
        switch self {
        case let .account(_, context, _):
            return .account(context.account.id)
        case .notice:
            return .notice
        }
    }

    private var sortIndex: Int {
        switch self {
        case let .account(index, _, _):
            return index
        case .notice:
            return Int.max
        }
    }

    static func ==(lhs: AccountOrderEntry, rhs: AccountOrderEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.account(lhsIndex, lhsContext, lhsPeer), .account(rhsIndex, rhsContext, rhsPeer)):
            return lhsIndex == rhsIndex && lhsContext === rhsContext && lhsPeer == rhsPeer
        case let (.notice(lhsText), .notice(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: AccountOrderEntry, rhs: AccountOrderEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AccountOrderArguments
        switch self {
        case let .account(_, context, peer):
            let currentPresentationData = arguments.context.sharedContext.currentPresentationData.with { $0 }
            // Each row reads its peer from its own account.
            let itemContext = ItemListPeerItem.Context.custom(ItemListPeerItem.Context.Custom(
                accountPeerId: context.account.peerId,
                engine: context.engine,
                animationCache: context.animationCache,
                animationRenderer: context.animationRenderer,
                isPremiumDisabled: false,
                resolveInlineStickers: { fileIds in
                    return context.engine.stickers.resolveInlineStickers(fileIds: fileIds)
                }
            ))
            return ItemListPeerItem(
                presentationData: presentationData,
                dateTimeFormat: currentPresentationData.dateTimeFormat,
                nameDisplayOrder: currentPresentationData.nameDisplayOrder,
                context: itemContext,
                peer: peer,
                presence: nil,
                text: .none,
                label: .none,
                editing: ItemListPeerItemEditing(editable: false, editing: true, canBeReordered: true, revealed: false),
                switchValue: nil,
                enabled: true,
                selectable: false,
                sectionId: self.section,
                action: nil,
                setPeerIdWithRevealedOptions: { _, _ in },
                removePeer: { _ in }
            )
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func accountIdsApplyingOrder<Id: Hashable>(existing: [Id], requested: [Id]) -> [Id] {
    let available = Set(existing)
    var included = Set<Id>()
    return (requested + existing).filter { available.contains($0) && included.insert($0).inserted }
}

private func accountsWithAppliedOrder(_ accounts: [(AccountContext, EnginePeer)], order: [AccountRecordId]?) -> [(AccountContext, EnginePeer)] {
    guard let order else {
        return accounts
    }
    let byId = Dictionary(uniqueKeysWithValues: accounts.map { ($0.0.account.id, $0) })
    return accountIdsApplyingOrder(existing: accounts.map { $0.0.account.id }, requested: order).compactMap { byId[$0] }
}

/// Numbers every record, not only the listed ones: accounts with equal numbers would swap between launches.
private func updateAccountOrder(accountManager: AccountManager<TelegramAccountManagerTypes>, currentId: AccountRecordId, orderedIds: [AccountRecordId]) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        let records = transaction.getRecords().map { record -> (AccountRecordId, Int32) in
            let order = record.attributes.compactMap { attribute -> Int32? in
                if case let .sortOrder(value) = attribute { return value.order }
                return nil
            }.first ?? 0
            return (record.id, order)
        }.sorted { lhs, rhs in
            return lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
        }
        // Without a stored current id the first account is treated as current. Do not restore an account logged out during the drag.
        if transaction.getCurrent() == nil, records.contains(where: { $0.0 == currentId }) {
            transaction.setCurrentId(currentId)
        }
        // Hidden or newly added accounts keep their relative order after the visible accounts.
        let ids = accountIdsApplyingOrder(existing: records.map { $0.0 }, requested: orderedIds)
        for (order, id) in ids.enumerated() {
            transaction.updateRecord(id, { record in
                guard let record else {
                    return nil
                }
                var attributes = record.attributes.filter { attribute in
                    if case .sortOrder = attribute {
                        return false
                    } else {
                        return true
                    }
                }
                attributes.append(.sortOrder(AccountSortOrderAttribute(order: Int32(order))))
                return AccountRecord(id: record.id, attributes: attributes, temporarySessionId: record.temporarySessionId)
            })
        }
    }
}

public func accountOrderController(context: AccountContext) -> ViewController {
    let arguments = AccountOrderArguments(context: context)

    let accounts = Promise<[(AccountContext, EnginePeer)]>()
    accounts.set(activeAccountsAndPeers(context: context, includePrimary: true)
    |> map { _, accounts -> [(AccountContext, EnginePeer)] in
        return accounts.filter { !HiddenAccountsSession.shared.state.isLocked(accountId: $0.0.account.id.int64) }.map { ($0.0, $0.1) }
    })
    // Written to the account manager only on drop: every write makes the app re-emit its account list.
    let updatedOrder = Promise<[AccountRecordId]?>(nil)

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        accounts.get(),
        updatedOrder.get()
    )
    |> map { presentationData, accounts, order -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [AccountOrderEntry] = []
        for (index, account) in accountsWithAppliedOrder(accounts, order: order).enumerated() {
            entries.append(.account(index: index, context: account.0, peer: account.1))
        }
        entries.append(.notice(text: ForkPresentationLanguage.prefersRussianStrings ? "Перетащите аккаунты в нужном порядке. Текущий аккаунт останется выбранным." : "Drag accounts into the order you want. Your current account stays selected."))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ForkPresentationLanguage.prefersRussianStrings ? "Порядок аккаунтов" : "Account Order"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [AccountOrderEntry]) -> Signal<Bool, NoError> in
        guard entries.indices.contains(fromIndex), toIndex >= 0, case let .account(_, fromContext, _) = entries[fromIndex] else {
            return .single(false)
        }
        let fromId = fromContext.account.id
        var referenceId: AccountRecordId?
        if toIndex < entries.count, case let .account(_, referenceContext, _) = entries[toIndex] {
            referenceId = referenceContext.account.id
        }

        return combineLatest(
            accounts.get() |> take(1),
            updatedOrder.get() |> take(1)
        )
        |> mapToSignal { accounts, order -> Signal<Bool, NoError> in
            let initialIds = accountsWithAppliedOrder(accounts, order: order).map { $0.0.account.id }
            guard initialIds.contains(fromId) else { return .single(false) }
            var ids = initialIds.filter { $0 != fromId }
            if let referenceId, let index = ids.firstIndex(of: referenceId) {
                ids.insert(fromId, at: fromIndex < toIndex ? index + 1 : index)
            } else {
                ids.append(fromId)
            }
            if ids != initialIds {
                updatedOrder.set(.single(ids))
                return .single(true)
            } else {
                return .single(false)
            }
        }
    })
    controller.setReorderCompleted({ (_: [AccountOrderEntry]) -> Void in
        let _ = (updatedOrder.get()
        |> take(1)
        |> deliverOnMainQueue).start(next: { order in
            guard let order else {
                return
            }
            let _ = updateAccountOrder(accountManager: context.sharedContext.accountManager, currentId: context.account.id, orderedIds: order).start()
        })
    })
    return controller
}
