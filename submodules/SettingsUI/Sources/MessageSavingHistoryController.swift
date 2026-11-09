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
import ItemListPeerItem
import LocalizedPeerData
import TelegramStringFormatting

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
    case loading
    case error(String)
    case empty(String)
    case record(Int, MessageSavingRecord)

    var section: ItemListSectionId { 0 }

    var stableId: Int32 {
        switch self {
        case .loading:
            return -3
        case .error:
            return -2
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
        case .loading:
            return ItemListTextItem(presentationData: presentationData, text: .plain(ForkMessageSavingStrings.loading), sectionId: self.section)
        case let .error(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .record(_, record):
            // AyuGram Android: customizable deleted mark (default 🧹) next to the timestamp in View Deleted too.
            let mark = record.kind == .deleted ? "\(MessageSavingBridge.deletedMark) " : ""
            let header = "\(record.authorName) · \(mark)\(messageSavingDateString(record.date, languageCode: presentationData.strings.baseLanguageCode))"
            var body = record.text
            let hasAttachment = messageSavingRecordHasFile(record)
            if let mediaPath = record.mediaPath, hasAttachment {
                let name = (mediaPath as NSString).lastPathComponent
                body += "\n📎 \(name)"
            }
            return ItemListMultilineTextItem(
                presentationData: presentationData,
                text: "\(header)\n\(body)",
                enabledEntityTypes: [],
                sectionId: self.section,
                style: .blocks,
                action: hasAttachment ? {
                    if let mediaPath = record.mediaPath, messageSavingRecordHasFile(record) {
                        args?.openAttachment(mediaPath)
                    }
                } : nil
            )
        }
    }
}

private func messageSavingDateString(_ timestamp: Int32, languageCode: String) -> String {
    let formatter: DateFormatter
    if let current = Thread.current.threadDictionary["messageSavingHistoryFormatter"] as? DateFormatter, current.locale.identifier == languageCode {
        formatter = current
    } else {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageCode)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        Thread.current.threadDictionary["messageSavingHistoryFormatter"] = formatter
    }
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
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
    if MessageSavingStore.historyReadFailed {
        return [.error(ForkMessageSavingStrings.readError)]
    }
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
    var presentControllerImpl: ((ViewController) -> Void)?

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
    DispatchQueue.global(qos: .utility).async {
        let reconcileRecords = messageSavingRecords(mode: mode, accountPeerId: reconcileAccountPeerId)
        if !reconcileRecords.isEmpty {
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
    // Store reads may load JSON and sort thousands of records. Serialize those
    // snapshots off the UI thread; only deliver the resulting list state on main.
    let historyQueue = Queue(name: "MessageSavingHistory")
    let signal = combineLatest(
        context.sharedContext.presentationData,
        refresh.get(),
        MessageSavingStore.changes.get()
    )
    |> mapToSignal { presentationData, _, _ -> Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> in
        func makeState(_ entries: [MessageSavingHistoryEntry]) -> (ItemListControllerState, (ItemListNodeState, Any)) {
            var rightButton: ItemListNavigationButton?
            if entries.contains(where: { if case .error = $0 { return true }; return false }) {
                rightButton = ItemListNavigationButton(content: .text(ForkMessageSavingStrings.retry), style: .regular, enabled: true, action: {
                    historyQueue.async {
                        MessageSavingStore.retryHistoryRead()
                        refresh.set(.single(Void()))
                    }
                })
            } else if clearAction != nil && !entries.contains(where: { if case .loading = $0 { return true }; return false }) {
                // Apple HIG: an irreversible delete asks first, and a button with nothing to act on is disabled. The saved
                // copies are the only ones left once the originals are gone.
                let hasRecords = entries.contains(where: { if case .record = $0 { return true }; return false })
                rightButton = ItemListNavigationButton(
                    content: .text(ForkMessageSavingStrings.clearDeleted),
                    style: .regular,
                    enabled: hasRecords,
                    action: {
                        let russian = ForkPresentationLanguage.prefersRussianStrings
                        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                        presentControllerImpl?(textAlertController(
                            context: context,
                            title: ForkMessageSavingStrings.clearDeleted,
                            text: russian ? "Сохранённые копии удалённых сообщений этого чата будут стёрты с устройства. Это нельзя отменить." : "The saved copies of this chat's deleted messages will be erased from this device. This can't be undone.",
                            actions: [
                                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                                TextAlertAction(type: .destructiveAction, title: russian ? "Очистить" : "Clear", action: {
                                    clearAction?()
                                    refresh.set(.single(Void()))
                                })
                            ]
                        ))
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
                entries: entries,
                style: .blocks
            )
            return (controllerState, (listState, arguments))
        }
        return .single(makeState([.loading]))
        |> then(Signal { subscriber in
            historyQueue.async {
                subscriber.putNext(makeState(messageSavingHistoryEntries(mode: mode, accountPeerId: context.account.peerId, emptyText: emptyText)))
                subscriber.putCompletion()
            }
            return EmptyDisposable
        })
    }
    |> deliverOnMainQueue

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    return controller
}

private final class MessageSavingDeletedChatsArguments {
    let context: AccountContext
    let updateQuery: (String) -> Void
    let openChat: (EnginePeer.Id) -> Void
    let deleteChat: (EnginePeer.Id) -> Void
    let deleteAll: () -> Void

    init(context: AccountContext, updateQuery: @escaping (String) -> Void, openChat: @escaping (EnginePeer.Id) -> Void, deleteChat: @escaping (EnginePeer.Id) -> Void, deleteAll: @escaping () -> Void) {
        self.context = context
        self.updateQuery = updateQuery
        self.openChat = openChat
        self.deleteChat = deleteChat
        self.deleteAll = deleteAll
    }
}

private enum MessageSavingDeletedChatsEntry: ItemListNodeEntry {
    case search(String)
    case empty(String)
    /// A chat: its index, id, peer when this account still knows it, title, and "N messages · size".
    case chat(Int, EnginePeer.Id, EnginePeer?, String, String)
    /// A search match: its index, the chat it belongs to, and its text with a header line.
    case result(Int, EnginePeer.Id, String)
    case deleteAll(Bool)

    var section: ItemListSectionId {
        switch self {
        case .search:
            return 0
        case .empty, .chat, .result:
            return 1
        case .deleteAll:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .search:
            return 0
        case .empty:
            return 1
        case let .chat(index, _, _, _, _):
            return 100 + Int32(index)
        case let .result(index, _, _):
            return 100_000 + Int32(index)
        case .deleteAll:
            return Int32.max
        }
    }

    static func <(lhs: MessageSavingDeletedChatsEntry, rhs: MessageSavingDeletedChatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MessageSavingDeletedChatsArguments
        let russian = ForkPresentationLanguage.prefersRussianStrings
        switch self {
        case let .search(query):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: query, placeholder: russian ? "Поиск по тексту" : "Search Text", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateQuery(value)
            }, action: {})
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .chat(_, peerId, peer, title, detail):
            guard let peer else {
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, sectionId: self.section, style: .blocks, action: {
                    arguments.openChat(peerId)
                })
            }
            return ItemListPeerItem(
                presentationData: presentationData,
                systemStyle: .glass,
                dateTimeFormat: PresentationDateTimeFormat(),
                nameDisplayOrder: .firstLast,
                context: arguments.context,
                peer: peer,
                height: .generic,
                aliasHandling: .threatSelfAsSaved,
                presence: nil,
                text: .text(detail, .secondary),
                label: .none,
                editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: false),
                revealOptions: ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: presentationData.strings.Common_Delete, action: {
                    arguments.deleteChat(peerId)
                })]),
                switchValue: nil,
                enabled: true,
                selectable: true,
                sectionId: self.section,
                action: {
                    arguments.openChat(peerId)
                },
                setPeerIdWithRevealedOptions: { _, _ in },
                removePeer: { id in
                    arguments.deleteChat(id)
                }
            )
        case let .result(_, peerId, text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: text, enabledEntityTypes: [], sectionId: self.section, style: .blocks, action: {
                arguments.openChat(peerId)
            })
        case let .deleteAll(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: russian ? "Удалить все" : "Delete All", kind: enabled ? .destructive : .disabled, alignment: .center, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.deleteAll()
                }
            })
        }
    }
}

private func messageSavingCountString(_ count: Int, russian: Bool) -> String {
    if russian {
        let lastTwo = count % 100
        let last = count % 10
        if lastTwo >= 11 && lastTwo <= 14 {
            return "\(count) сообщений"
        } else if last == 1 {
            return "\(count) сообщение"
        } else if last >= 2 && last <= 4 {
            return "\(count) сообщения"
        } else {
            return "\(count) сообщений"
        }
    }
    return count == 1 ? "1 message" : "\(count) messages"
}

/// Extras › Message Saving › Deleted Messages: the saved deleted messages of every chat of this account, one row per
/// chat with how many there are and the space they take, a search across their text, and Delete All. A chat opens its
/// own View Deleted list.
public func messageSavingDeletedChatsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let accountPeerId = context.account.peerId
    let queryPromise = ValuePromise<String>("", ignoreRepeated: true)

    // The saved copies are the only ones left once the originals are gone, so both deletions ask first.
    let confirmDeletion: (String, @escaping () -> Void) -> Void = { text, deletion in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                // Writes the store through to disk; the list rebuilds from its change signal.
                DispatchQueue.global(qos: .userInitiated).async {
                    deletion()
                }
            })
        ]))
    }

    let arguments = MessageSavingDeletedChatsArguments(
        context: context,
        updateQuery: { query in
            queryPromise.set(query)
        },
        openChat: { peerId in
            pushControllerImpl?(messageSavingDeletedController(context: context, peerId: peerId))
        },
        deleteChat: { peerId in
            let russian = ForkPresentationLanguage.prefersRussianStrings
            confirmDeletion(russian ? "Сохранённые копии удалённых сообщений этого чата будут стёрты с устройства. Это нельзя отменить." : "The saved copies of this chat's deleted messages will be erased from this device. This can't be undone.", {
                MessageSavingStore.clearDeleted(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
            })
        },
        deleteAll: {
            let russian = ForkPresentationLanguage.prefersRussianStrings
            confirmDeletion(russian ? "Сохранённые копии удалённых сообщений всех чатов этого аккаунта будут стёрты с устройства. История правок останется. Это нельзя отменить." : "The saved copies of deleted messages from all chats in this account will be erased from this device. Edit history stays. This can't be undone.", {
                MessageSavingStore.clearAllDeleted(accountPeerId: accountPeerId.toInt64())
            })
        }
    )

    // Store reads, attachment sizes and search all run here, never on the main thread.
    let historyQueue = Queue(name: "MessageSavingDeletedChats")
    // Only touched on historyQueue. A copied attachment does not change size, and the page is rebuilt on every store
    // change, so its size is read from disk once.
    var attachmentSizes: [String: Int64] = [:]

    let records: Signal<[MessageSavingRecord], NoError> = MessageSavingStore.changes.get()
    |> mapToSignal { _ -> Signal<[MessageSavingRecord], NoError> in
        return Signal { subscriber in
            historyQueue.async {
                subscriber.putNext(MessageSavingStore.allDeleted(accountPeerId: accountPeerId.toInt64()))
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }

    let recordsAndPeers: Signal<([MessageSavingRecord], [EnginePeer.Id: EnginePeer?]), NoError> = records
    |> mapToSignal { records -> Signal<([MessageSavingRecord], [EnginePeer.Id: EnginePeer?]), NoError> in
        let peerIds = Array(Set(records.map { EnginePeer.Id($0.peerId) }))
        return context.engine.data.get(EngineDataMap(
            peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))
        ))
        |> map { peers -> ([MessageSavingRecord], [EnginePeer.Id: EnginePeer?]) in
            return (records, peers)
        }
    }

    let signal = combineLatest(queue: historyQueue,
        context.sharedContext.presentationData,
        recordsAndPeers,
        queryPromise.get()
    )
    |> map { presentationData, recordsAndPeers, query -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (records, peers) = recordsAndPeers
        let russian = ForkPresentationLanguage.prefersRussianStrings

        // Chats in the order of their latest deleted message (records come newest first).
        var order: [Int64] = []
        var counts: [Int64: Int] = [:]
        var sizes: [Int64: Int64] = [:]
        var authorTitles: [Int64: String] = [:]
        var countedPaths = Set<String>()
        for record in records {
            if counts[record.peerId] == nil {
                order.append(record.peerId)
            }
            counts[record.peerId, default: 0] += 1
            var size = Int64(record.text.utf8.count)
            if let path = record.mediaPath, !path.isEmpty, countedPaths.insert(path).inserted {
                if let known = attachmentSizes[path] {
                    size += known
                } else if let fileSize = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber {
                    // Not remembered while the file is missing: the copy may still be on its way.
                    attachmentSizes[path] = fileSize.int64Value
                    size += fileSize.int64Value
                }
            }
            sizes[record.peerId, default: 0] += size
            // Stands in for the title of a chat this account no longer knows (left, or a secret chat): in a private
            // chat that is the other person.
            if authorTitles[record.peerId] == nil, record.authorId != accountPeerId.toInt64(), !record.authorName.isEmpty {
                authorTitles[record.peerId] = record.authorName
            }
        }

        var titles: [Int64: String] = [:]
        var knownPeers: [Int64: EnginePeer] = [:]
        for peerId in order {
            var title = ""
            if let peer = peers[EnginePeer.Id(peerId)] ?? nil, peer.id.namespace != Namespaces.Peer.SecretChat {
                title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                knownPeers[peerId] = peer
            }
            if title.isEmpty {
                title = authorTitles[peerId] ?? (russian ? "Неизвестный чат" : "Unknown Chat")
            }
            titles[peerId] = title
        }

        var entries: [MessageSavingDeletedChatsEntry] = [.search(query)]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if MessageSavingStore.historyReadFailed {
            entries.append(.empty(ForkMessageSavingStrings.readError))
        } else if records.isEmpty {
            entries.append(.empty(ForkMessageSavingStrings.noDeleted))
        } else if !trimmedQuery.isEmpty {
            let matches = records.filter { record in
                return bananaDeletedMessageMatchesQuery(text: record.text + " " + record.authorName, query: trimmedQuery)
            }
            if matches.isEmpty {
                entries.append(.empty(russian ? "Ничего не найдено." : "No messages found."))
            }
            for (index, record) in matches.prefix(200).enumerated() {
                let title = titles[record.peerId] ?? ""
                var header = title
                if record.authorName != title {
                    header += " · \(record.authorName)"
                }
                header += " · \(messageSavingDateString(record.date, languageCode: presentationData.strings.baseLanguageCode))"
                entries.append(.result(index, EnginePeer.Id(record.peerId), "\(header)\n\(record.text)"))
            }
        } else {
            let sizeFormatting = DataSizeStringFormatting(presentationData: presentationData)
            for (index, peerId) in order.enumerated() {
                let detail = "\(messageSavingCountString(counts[peerId] ?? 0, russian: russian)) · \(dataSizeString(sizes[peerId] ?? 0, formatting: sizeFormatting))"
                entries.append(.chat(index, EnginePeer.Id(peerId), knownPeers[peerId], titles[peerId] ?? "", detail))
            }
        }
        entries.append(.deleteAll(!records.isEmpty))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(russian ? "Удалённые сообщения" : "Deleted Messages"),
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
    |> deliverOnMainQueue

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    presentControllerImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    return controller
}
