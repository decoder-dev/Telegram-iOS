import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TelegramStringFormatting
import ItemListUI
import TextFormat
import AccountContext

// "Messages in Common Groups" on a person's profile (after Regram and 64Gram): their latest messages
// from every group you share, newest first. Groups are searched one at a time with a pause in between,
// and a flood wait stops the search with what was found so far.

private struct CommonGroupMessage: Equatable {
    let id: EngineMessage.Id
    let threadId: Int64?
    let timestamp: Int32
    let group: EnginePeer
    let text: String
}

private struct CommonGroupMessagesState: Equatable {
    var messages: [CommonGroupMessage] = []
    var groupCount: Int?
    var searchedGroupCount = 0
    var isFinished = false
    var stoppedOnFloodWait = false
}

private final class CommonGroupMessagesArguments {
    let openMessage: (CommonGroupMessage) -> Void

    init(openMessage: @escaping (CommonGroupMessage) -> Void) {
        self.openMessage = openMessage
    }
}

private enum CommonGroupMessagesEntry: ItemListNodeEntry {
    case status(String, Bool, Bool)
    case message(Int, String, CommonGroupMessage)

    var section: ItemListSectionId {
        switch self {
        case .status:
            return 0
        case .message:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .status:
            return 0
        case let .message(index, _, _):
            return 1 + index
        }
    }

    static func <(lhs: CommonGroupMessagesEntry, rhs: CommonGroupMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CommonGroupMessagesArguments
        switch self {
        case let .status(text, isSearching, isWarning):
            return ItemListActivityTextItem(displayActivity: isSearching, presentationData: presentationData, text: text, color: isWarning ? .warning : .generic, sectionId: self.section)
        case let .message(_, label, message):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: message.text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: {
                arguments.openMessage(message)
            })
        }
    }
}

private final class CommonGroupMessagesSearch {
    private let context: AccountContext
    private let userId: EnginePeer.Id
    private let updateState: ((inout CommonGroupMessagesState) -> Void) -> Void
    private let groupsInCommon: GroupsInCommonContext
    private var groupsDisposable: Disposable?
    private let searchDisposable = MetaDisposable()
    private var groups: [EnginePeer]?

    init(context: AccountContext, userId: EnginePeer.Id, updateState: @escaping ((inout CommonGroupMessagesState) -> Void) -> Void) {
        self.context = context
        self.userId = userId
        self.updateState = updateState
        self.groupsInCommon = GroupsInCommonContext(account: context.account, peerId: userId)

        self.groupsDisposable = (self.groupsInCommon.state
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let self, self.groups == nil, case let .ready(canLoadMore) = state.dataState else {
                return
            }
            if canLoadMore {
                self.groupsInCommon.loadMore()
            } else {
                let groups = state.peers.compactMap { $0.peer.flatMap(EnginePeer.init) }
                self.groups = groups
                self.updateState { $0.groupCount = groups.count }
                self.search(index: 0)
            }
        })
    }

    deinit {
        self.groupsDisposable?.dispose()
        self.searchDisposable.dispose()
    }

    private func search(index: Int) {
        guard let groups = self.groups, index < groups.count else {
            self.updateState { $0.isFinished = true }
            return
        }
        let group = groups[index]
        let contentSettings = self.context.currentContentSettings.with { $0 }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        let accountPeerId = self.context.account.peerId

        self.searchDisposable.set((self.context.engine.messages.bananaMessages(from: self.userId, in: group.id, limit: 30)
        |> deliverOnMainQueue).startStrict(next: { [weak self] messages in
            guard let self else {
                return
            }
            let found = messages.map { message -> CommonGroupMessage in
                var text = message.text
                if text.isEmpty {
                    text = descriptionStringForMessage(contentSettings: contentSettings, message: message, strings: presentationData.strings, nameDisplayOrder: presentationData.nameDisplayOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: accountPeerId).0.string
                }
                if text.count > 300 {
                    text = String(text.prefix(300)) + "…"
                }
                return CommonGroupMessage(id: message.id, threadId: message.threadId, timestamp: message.timestamp, group: group, text: text)
            }
            self.updateState { state in
                state.searchedGroupCount = index + 1
                state.messages.append(contentsOf: found)
                state.messages.sort { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp {
                        return lhs.timestamp > rhs.timestamp
                    }
                    return lhs.id > rhs.id
                }
            }
            self.searchAfterPause(index: index + 1)
        }, error: { [weak self] error in
            guard let self else {
                return
            }
            switch error {
            case .floodWait:
                self.updateState { state in
                    state.isFinished = true
                    state.stoppedOnFloodWait = true
                }
            case .generic:
                // A group that can't be searched any more (left, banned, deleted) is skipped.
                self.updateState { $0.searchedGroupCount = index + 1 }
                self.searchAfterPause(index: index + 1)
            }
        }))
    }

    private func searchAfterPause(index: Int) {
        self.searchDisposable.set((Signal<Never, NoError>.complete()
        |> delay(Double.random(in: 0.4 ... 0.8), queue: Queue.mainQueue())).startStrict(completed: { [weak self] in
            self?.search(index: index)
        }))
    }
}

func peerInfoCommonGroupMessagesController(context: AccountContext, user: EnginePeer) -> ViewController {
    let initialState = CommonGroupMessagesState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((inout CommonGroupMessagesState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    var openMessageImpl: ((CommonGroupMessage) -> Void)?
    let arguments = CommonGroupMessagesArguments(openMessage: { message in
        openMessageImpl?(message)
    })

    let search = CommonGroupMessagesSearch(context: context, userId: user.id, updateState: updateState)

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let russian = ForkPresentationLanguage.prefersRussianStrings
        let statusText: String
        if state.stoppedOnFloodWait {
            statusText = russian ? "Telegram попросил подождать, поэтому поиск остановлен после \(state.searchedGroupCount) из \(state.groupCount ?? 0) групп. Попробуйте позже." : "Telegram asked to slow down, so the search stopped after \(state.searchedGroupCount) of \(state.groupCount ?? 0) groups. Try again later."
        } else if let groupCount = state.groupCount {
            if !state.isFinished {
                statusText = russian ? "Поиск в группах: \(state.searchedGroupCount + 1) из \(groupCount)…" : "Searching group \(state.searchedGroupCount + 1) of \(groupCount)…"
            } else if state.messages.isEmpty {
                statusText = russian ? "Сообщений не найдено." : "No messages found."
            } else {
                statusText = russian ? "Найдено сообщений: \(state.messages.count), групп: \(groupCount)." : "Found \(state.messages.count) messages in \(groupCount) groups."
            }
        } else {
            statusText = russian ? "Загрузка общих групп…" : "Loading groups in common…"
        }

        var entries: [CommonGroupMessagesEntry] = [.status(statusText, !state.isFinished, state.stoppedOnFloodWait)]
        for (index, message) in state.messages.enumerated() {
            let date = stringForMediumDate(timestamp: message.timestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
            let title = message.group.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            entries.append(.message(index, "\(title) · \(date)", message))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(russian ? "Сообщения в общих группах" : "Messages in Common Groups"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        // Keeps the search alive for as long as the screen is.
        let _ = search
    }

    let controller = ItemListController(context: context, state: signal)
    openMessageImpl = { [weak controller] message in
        guard let navigationController = controller?.navigationController as? NavigationController else {
            return
        }
        if let threadId = message.threadId, case let .channel(channel) = message.group, channel.isForumOrMonoForum {
            let _ = context.sharedContext.navigateToForumThread(context: context, peerId: message.group.id, threadId: threadId, messageId: message.id, navigationController: navigationController, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).startStandalone()
        } else {
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(message.group), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
        }
    }
    return controller
}
