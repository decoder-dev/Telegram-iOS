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
import PremiumUI

private final class AccountOrderArguments {
    let context: AccountContext
    let addAccount: () -> Void
    let toggleEditing: () -> Void

    init(context: AccountContext, addAccount: @escaping () -> Void, toggleEditing: @escaping () -> Void) {
        self.context = context
        self.addAccount = addAccount
        self.toggleEditing = toggleEditing
    }
}

/// Scene 28: the signed-in accounts, then a Manage group (add an account, reorder). Hidden accounts that are still
/// locked are never listed, so the list says nothing about them.
private enum AccountOrderStrings {
    private static var ru: Bool {
        return ForkPresentationLanguage.prefersRussianStrings
    }

    static var title: String { ru ? "Аккаунты" : "Accounts" }
    static var accountsHeader: String { ru ? "ДОБАВЛЕННЫЕ" : "SIGNED IN" }
    static var active: String { ru ? "Активен" : "Active" }
    static var manageHeader: String { ru ? "УПРАВЛЕНИЕ" : "MANAGE" }
    static var addAccount: String { ru ? "Добавить аккаунт" : "Add Account" }
    static var reorder: String { ru ? "Изменить порядок" : "Change Order" }
    static var reorderDone: String { ru ? "Готово" : "Done" }
    static var notice: String { ru ? "Скрытые аккаунты здесь не показываются, пока их не откроет владелец." : "Hidden accounts are not shown here until their owner opens them." }
    static var editingNotice: String { ru ? "Перетащите аккаунты в нужном порядке. Текущий аккаунт останется выбранным." : "Drag accounts into the order you want. Your current account stays selected." }
}

private enum AccountOrderEntryStableId: Hashable {
    case accountsHeader
    case account(AccountRecordId)
    case manageHeader
    case addAccount
    case reorder
    case notice
}

private enum AccountOrderEntry: ItemListNodeEntry {
    case accountsHeader(text: String)
    case account(index: Int, context: AccountContext, peer: EnginePeer, isCurrent: Bool, editing: Bool)
    case manageHeader(text: String)
    case addAccount(text: String)
    case reorder(text: String)
    case notice(text: String)

    var section: ItemListSectionId {
        switch self {
        case .accountsHeader, .account:
            return 0
        case .manageHeader, .addAccount, .reorder, .notice:
            return 1
        }
    }

    var stableId: AccountOrderEntryStableId {
        switch self {
        case .accountsHeader:
            return .accountsHeader
        case let .account(_, context, _, _, _):
            return .account(context.account.id)
        case .manageHeader:
            return .manageHeader
        case .addAccount:
            return .addAccount
        case .reorder:
            return .reorder
        case .notice:
            return .notice
        }
    }

    private var sortIndex: Int {
        switch self {
        case .accountsHeader:
            return -1
        case let .account(index, _, _, _, _):
            return index
        case .manageHeader:
            return Int.max - 3
        case .addAccount:
            return Int.max - 2
        case .reorder:
            return Int.max - 1
        case .notice:
            return Int.max
        }
    }

    static func ==(lhs: AccountOrderEntry, rhs: AccountOrderEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.accountsHeader(lhsText), .accountsHeader(rhsText)):
            return lhsText == rhsText
        case let (.account(lhsIndex, lhsContext, lhsPeer, lhsIsCurrent, lhsEditing), .account(rhsIndex, rhsContext, rhsPeer, rhsIsCurrent, rhsEditing)):
            return lhsIndex == rhsIndex && lhsContext === rhsContext && lhsPeer == rhsPeer && lhsIsCurrent == rhsIsCurrent && lhsEditing == rhsEditing
        case let (.manageHeader(lhsText), .manageHeader(rhsText)):
            return lhsText == rhsText
        case let (.addAccount(lhsText), .addAccount(rhsText)):
            return lhsText == rhsText
        case let (.reorder(lhsText), .reorder(rhsText)):
            return lhsText == rhsText
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
        case let .accountsHeader(text), let .manageHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .account(_, context, peer, isCurrent, editing):
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
                text: isCurrent ? .text(AccountOrderStrings.active, .accent) : .none,
                label: .none,
                editing: ItemListPeerItemEditing(editable: false, editing: editing, canBeReordered: editing, revealed: false),
                switchValue: nil,
                enabled: true,
                selectable: false,
                sectionId: self.section,
                action: nil,
                setPeerIdWithRevealedOptions: { _, _ in },
                removePeer: { _ in }
            )
        case let .addAccount(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addAccount()
            })
        case let .reorder(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.toggleEditing()
            })
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
        var records: [(id: AccountRecordId, order: Int32)] = []
        for record in transaction.getRecords() {
            var order: Int32 = 0
            for attribute in record.attributes {
                if case let .sortOrder(value) = attribute {
                    order = value.order
                    break
                }
            }
            records.append((id: record.id, order: order))
        }
        records.sort { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.id < rhs.id
            }
            return lhs.order < rhs.order
        }
        // Without a stored current id the first account is treated as current. Do not restore an account logged out during the drag.
        if transaction.getCurrent() == nil, records.contains(where: { $0.id == currentId }) {
            transaction.setCurrentId(currentId)
        }
        // Hidden or newly added accounts keep their relative order after the visible accounts.
        let ids = accountIdsApplyingOrder(existing: records.map { $0.id }, requested: orderedIds)
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
    let editing = ValuePromise<Bool>(false, ignoreRepeated: true)
    let editingValue = Atomic<Bool>(value: false)
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = AccountOrderArguments(context: context, addAccount: {
        // The same limit the Settings "Add Account" row applies.
        let _ = (activeAccountsAndPeers(context: context)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { accountAndPeer, accountsAndPeers in
            var maximumAvailableAccounts: Int = maximumNumberOfAccounts
            if accountAndPeer?.1.isPremium == true && !context.account.testingEnvironment {
                maximumAvailableAccounts = maximumPremiumNumberOfAccounts
            }
            var count: Int = 1
            for (accountContext, peer, _) in accountsAndPeers {
                if !accountContext.account.testingEnvironment {
                    if peer.isPremium {
                        maximumAvailableAccounts = maximumPremiumNumberOfAccounts
                    }
                    count += 1
                }
            }
            if count >= maximumAvailableAccounts {
                var replaceImpl: ((ViewController) -> Void)?
                let controller = PremiumLimitScreen(context: context, subject: .accounts, count: Int32(count), action: {
                    let controller = PremiumIntroScreen(context: context, source: .accounts)
                    replaceImpl?(controller)
                    return true
                })
                replaceImpl = { [weak controller] c in
                    controller?.replace(with: c)
                }
                pushControllerImpl?(controller)
            } else {
                context.sharedContext.beginNewAuth(testingEnvironment: context.account.testingEnvironment)
            }
        })
    }, toggleEditing: {
        let value = !editingValue.with { $0 }
        let _ = editingValue.swap(value)
        editing.set(value)
    })

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
        updatedOrder.get(),
        editing.get()
    )
    |> map { presentationData, accounts, order, editing -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [AccountOrderEntry] = []
        entries.append(.accountsHeader(text: AccountOrderStrings.accountsHeader))
        for (index, account) in accountsWithAppliedOrder(accounts, order: order).enumerated() {
            entries.append(.account(index: index, context: account.0, peer: account.1, isCurrent: account.0.account.id == context.account.id, editing: editing))
        }
        entries.append(.manageHeader(text: AccountOrderStrings.manageHeader))
        entries.append(.addAccount(text: AccountOrderStrings.addAccount))
        if accounts.count > 1 {
            entries.append(.reorder(text: editing ? AccountOrderStrings.reorderDone : AccountOrderStrings.reorder))
        }
        entries.append(.notice(text: editing ? AccountOrderStrings.editingNotice : AccountOrderStrings.notice))

        let rightNavigationButton: ItemListNavigationButton? = editing ? ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
            arguments.toggleEditing()
        }) : nil
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(AccountOrderStrings.title), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [AccountOrderEntry]) -> Signal<Bool, NoError> in
        guard entries.indices.contains(fromIndex), toIndex >= 0, case let .account(_, fromContext, _, _, _) = entries[fromIndex] else {
            return .single(false)
        }
        let fromId = fromContext.account.id
        var referenceId: AccountRecordId?
        var insertsBeforeReference = fromIndex > toIndex
        if toIndex < entries.count, case let .account(_, referenceContext, _, _, _) = entries[toIndex] {
            referenceId = referenceContext.account.id
        } else if let firstAccountIndex = entries.firstIndex(where: { if case .account = $0 { return true } else { return false } }), toIndex < firstAccountIndex, case let .account(_, firstContext, _, _, _) = entries[firstAccountIndex] {
            // Dropped on the section header: the account goes first.
            referenceId = firstContext.account.id
            insertsBeforeReference = true
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
                ids.insert(fromId, at: insertsBeforeReference ? index : index + 1)
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
