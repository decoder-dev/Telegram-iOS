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

private final class MessageSavingHistoryArguments {
    let openAttachment: (String) -> Void

    init(openAttachment: @escaping (String) -> Void) {
        self.openAttachment = openAttachment
    }
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
        let args = arguments as? MessageSavingHistoryArguments
        switch self {
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .record(_, record):
            let date = Date(timeIntervalSince1970: TimeInterval(record.date))
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            // AyuGram Android: customizable deleted mark (default 🧹) next to the timestamp in View Deleted too.
            let mark = record.kind == .deleted ? "\(MessageSavingBridge.deletedMark) " : ""
            let header = "\(record.authorName) · \(mark)\(formatter.string(from: date))"
            var body = record.text
            if let mediaPath = record.mediaPath, messageSavingRecordHasFile(record) {
                let name = (mediaPath as NSString).lastPathComponent
                body += "\n📎 \(name)"
            }
            return ItemListMultilineTextItem(
                presentationData: presentationData,
                text: "\(header)\n\(body)",
                enabledEntityTypes: [],
                sectionId: self.section,
                style: .blocks,
                action: {
                    if let mediaPath = record.mediaPath, messageSavingRecordHasFile(record) {
                        args?.openAttachment(mediaPath)
                    }
                }
            )
        }
    }
}

/// A record only counts as having an attachment when the file is actually on disk: the durable
/// copy is dispatched, so the path is stored before the bytes exist.
private func messageSavingRecordHasFile(_ record: MessageSavingRecord) -> Bool {
    guard let mediaPath = record.mediaPath else {
        return false
    }
    return FileManager.default.fileExists(atPath: mediaPath)
}

private func messageSavingRecords(mode: MessageSavingHistoryMode, accountPeerId: EnginePeer.Id) -> [MessageSavingRecord] {
    let accountId = accountPeerId.toInt64()
    switch mode {
    case let .deleted(peerId, topicId):
        return MessageSavingStore.deleted(accountPeerId: accountId, peerId: peerId.toInt64(), topicId: topicId)
    case let .edits(peerId, messageId):
        return MessageSavingStore.edits(
            accountPeerId: accountId,
            peerId: peerId.toInt64(),
            messageId: messageId.id,
            namespace: messageId.namespace
        )
    }
}

private func messageSavingHistoryEntries(mode: MessageSavingHistoryMode, accountPeerId: EnginePeer.Id, emptyText: String) -> [MessageSavingHistoryEntry] {
    let records = messageSavingRecords(mode: mode, accountPeerId: accountPeerId)
    if records.isEmpty {
        return [.empty(emptyText)]
    }
    return records.enumerated().map { .record($0.offset, $0.element) }
}

/// AyuGram-style "View Deleted" list for a peer (rows with 🧹 + attachment affordance).
public func messageSavingDeletedController(context: AccountContext, peerId: EnginePeer.Id, topicId: Int64? = nil) -> ViewController {
    return messageSavingHistoryController(
        context: context,
        title: ForkMessageSavingStrings.viewDeleted,
        emptyText: ForkMessageSavingStrings.noDeleted,
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
        title: ForkMessageSavingStrings.editHistory,
        emptyText: ForkMessageSavingStrings.noEdits,
        mode: .edits(peerId: messageId.peerId, messageId: messageId),
        clearAction: nil
    )
}

private func messageSavingPresentAttachmentShare(path: String) {
    let url = URL(fileURLWithPath: path)
    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
    if let window, let popover = activity.popoverPresentationController {
        popover.sourceView = window
        popover.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
        popover.permittedArrowDirections = []
    }
    var presenter = window?.rootViewController
    while let presented = presenter?.presentedViewController {
        presenter = presented
    }
    presenter?.present(activity, animated: true)
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

    // In-memory retry state does not survive an app kill, so a copy that finished right before
    // the process died leaves a record with no path. Re-link those lazily for just the records
    // this screen shows — off the main thread, and never a global Postbox scan. The store's
    // change signal repaints the list once links are made.
    //
    // A stored path with no file behind it needs the same treatment: the copy is dispatched
    // rather than synchronous, so a record is written with its final path before the bytes have
    // landed, and a copy interrupted by a kill leaves that path pointing at nothing. Checking the
    // filesystem here also picks up a file the user removed from Files.app and a legacy-named
    // copy from before account scoping.
    let reconcileAccountPeerId = context.account.peerId
    let reconcileMediaBox = context.account.postbox.mediaBox
    let reconcileRecords = messageSavingRecords(mode: mode, accountPeerId: reconcileAccountPeerId)
    if !reconcileRecords.isEmpty {
        DispatchQueue.global(qos: .utility).async {
            var didFindFile = false
            for record in reconcileRecords where !messageSavingRecordHasFile(record) {
                let path = MessageSavingBridge.reconcileStoredAttachment(
                    accountPeerId: reconcileAccountPeerId,
                    peerId: EnginePeer.Id(record.peerId),
                    namespace: record.namespace,
                    messageId: record.messageId,
                    mediaBox: reconcileMediaBox
                )
                if path != nil {
                    didFindFile = true
                }
            }
            // A record already pointing at the right path gets no store mutation when the copy
            // finally lands, so nothing would tell an open screen to rebuild. Ask for one rebuild
            // covering the whole pass rather than one per record.
            if didFindFile {
                MessageSavingStore.refresh()
            }
        }
    }

    let arguments = MessageSavingHistoryArguments(openAttachment: { path in
        messageSavingPresentAttachmentShare(path: path)
    })

    // Also rebuild when the store itself changes: a durable attachment can be copied seconds
    // after this screen is opened (slow download), and without this the row would keep showing
    // no attachment until the controller is closed and reopened.
    let signal = combineLatest(
        context.sharedContext.presentationData,
        refresh.get(),
        MessageSavingStore.changes.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var rightButton: ItemListNavigationButton?
        if clearAction != nil {
            rightButton = ItemListNavigationButton(
                content: .text(ForkMessageSavingStrings.clearDeleted),
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
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
