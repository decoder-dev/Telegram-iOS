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

private enum MessageSavingHistoryMode {
    case deleted(peerId: EnginePeer.Id, topicId: Int64?)
    case edits(peerId: EnginePeer.Id, messageId: EngineMessage.Id)
}

private enum MessageSavingHistoryEntry: ItemListNodeEntry {
    case empty(String)
    case record(Int, MessageSavingRecord)

    var section: ItemListSectionId { 0 }

    var stableId: Int32 {
        switch self {
        case .empty:
            return -1
        case let .record(index, _):
            return Int32(index)
        }
    }

    static func <(lhs: MessageSavingHistoryEntry, rhs: MessageSavingHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .record(_, record):
            let date = Date(timeIntervalSince1970: TimeInterval(record.date))
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let header = "\(record.authorName) · \(formatter.string(from: date))"
            return ItemListMultilineTextItem(
                presentationData: presentationData,
                text: "\(header)\n\(record.text)",
                enabledEntityTypes: [],
                sectionId: self.section,
                style: .blocks
            )
        }
    }
}

private func messageSavingHistoryEntries(mode: MessageSavingHistoryMode, accountPeerId: EnginePeer.Id, emptyText: String) -> [MessageSavingHistoryEntry] {
    let accountId = accountPeerId.toInt64()
    let records: [MessageSavingRecord]
    switch mode {
    case let .deleted(peerId, topicId):
        records = MessageSavingStore.deleted(accountPeerId: accountId, peerId: peerId.toInt64(), topicId: topicId)
    case let .edits(peerId, messageId):
        records = MessageSavingStore.edits(
            accountPeerId: accountId,
            peerId: peerId.toInt64(),
            messageId: messageId.id,
            namespace: messageId.namespace
        )
    }
    if records.isEmpty {
        return [.empty(emptyText)]
    }
    return records.enumerated().map { .record($0.offset, $0.element) }
}

/// AyuGram-style "View Deleted" list for a peer.
public func messageSavingDeletedController(context: AccountContext, peerId: EnginePeer.Id, topicId: Int64? = nil) -> ViewController {
    return messageSavingHistoryController(
        context: context,
        title: messageSavingLocalizedString(key: "ForkExtras.ViewDeleted", en: "View Deleted", ru: "Удалённые"),
        emptyText: messageSavingLocalizedString(key: "ForkExtras.NoDeleted", en: "No deleted messages saved yet.", ru: "Пока нет сохранённых удалённых сообщений."),
        mode: .deleted(peerId: peerId, topicId: topicId),
        clearAction: {
            MessageSavingStore.clearDeleted(
                accountPeerId: context.account.peerId.toInt64(),
                peerId: peerId.toInt64(),
                topicId: topicId
            )
        }
    )
}

/// AyuGram-style edit history for one message.
public func messageSavingEditsController(context: AccountContext, messageId: EngineMessage.Id) -> ViewController {
    return messageSavingHistoryController(
        context: context,
        title: messageSavingLocalizedString(key: "ForkExtras.EditHistory", en: "Edit History", ru: "История правок"),
        emptyText: messageSavingLocalizedString(key: "ForkExtras.NoEdits", en: "No previous versions saved.", ru: "Предыдущих версий нет."),
        mode: .edits(peerId: messageId.peerId, messageId: messageId),
        clearAction: nil
    )
}

private func messageSavingHistoryController(
    context: AccountContext,
    title: String,
    emptyText: String,
    mode: MessageSavingHistoryMode,
    clearAction: (() -> Void)?
) -> ViewController {
    let refresh = Promise<Void>()
    refresh.set(.single(Void()))

    let signal = combineLatest(
        context.sharedContext.presentationData,
        refresh.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var rightButton: ItemListNavigationButton?
        if clearAction != nil {
            rightButton = ItemListNavigationButton(
                content: .text(messageSavingLocalizedString(key: "ForkExtras.ClearDeleted", en: "Clear Deleted", ru: "Очистить удалённые")),
                style: .regular,
                enabled: true,
                action: {
                    clearAction?()
                    refresh.set(.single(Void()))
                }
            )
        }
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: rightButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: messageSavingHistoryEntries(mode: mode, accountPeerId: context.account.peerId, emptyText: emptyText),
            style: .blocks
        )
        return (controllerState, (listState, ()))
    }

    return ItemListController(context: context, state: signal)
}

private func messageSavingLocalizedString(key: String, en: String, ru: String) -> String {
    let candidates = Locale.preferredLanguages + Bundle.main.preferredLocalizations
    for candidate in candidates {
        let code = String(candidate.prefix(2)).lowercased()
        if code == "ru" {
            return ru
        }
    }
    return en
}
