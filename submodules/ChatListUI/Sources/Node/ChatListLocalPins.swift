import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext

// Postbox keeps the pinned peers of a filtered list in a space of their own. The group spaces it adds beside it are
// pointed at a group no chat is ever in, so they hold neither chats nor holes: a hole there would start loading the
// whole chat list just to show a few pinned chats.
private let localPinsEmptyGroupId = PeerGroupId(rawValue: Int32.max)

/// Pin Beyond the Limit: the chats pinned on this device only, in their stored order (pinning index 0 on top). A chat
/// that is no longer in the main list (deleted, left or archived) is dropped from the stored list.
func localPinnedChatListItems(context: AccountContext) -> Signal<[EngineChatList.Item], NoError> {
    let account = context.account
    let engine = context.engine
    return combineLatest(
        forkExtrasSettings(accountManager: context.sharedContext.accountManager)
        |> map { $0.pinBeyondLimit }
        |> distinctUntilChanged,
        localPinnedChatIds(engine: engine)
    )
    |> mapToSignal { isEnabled, peerIds -> Signal<[EngineChatList.Item], NoError> in
        if !isEnabled || peerIds.isEmpty {
            return .single([])
        }
        let predicate = ChatListFilterPredicate(includePeerIds: Set(), excludePeerIds: Set(), pinnedPeerIds: peerIds, messageTagSummary: nil, includeAdditionalPeerGroupIds: [], include: { _, _, _, _, _ in
            return false
        })
        return combineLatest(
            engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Messages.ChatListGroup.init(id:)))),
            account.viewTracker.tailChatListView(groupId: localPinsEmptyGroupId, filterPredicate: predicate, count: peerIds.count + 1)
        )
        |> map { groups, viewAndUpdate -> [EngineChatList.Item] in
            let removedPeerIds = Set(peerIds.filter { peerId in
                if case .root? = groups[peerId] ?? nil {
                    return false
                }
                return true
            })
            if !removedPeerIds.isEmpty {
                let _ = updateLocalPinnedChatIds(engine: engine, { current in
                    return current.filter { !removedPeerIds.contains($0) }
                }).startStandalone()
            }
            return EngineChatList(viewAndUpdate.0, accountPeerId: account.peerId).items.filter { item in
                if case let .chatList(peerId) = item.id {
                    return !removedPeerIds.contains(peerId)
                }
                return false
            }
        }
    }
}

/// Lists the chats pinned on this device right under the server pins. Pins only exist at the top of the list, and a
/// chat the server pinned as well is listed once, as the server's.
func chatListNodeViewUpdateWithLocalPins(update: ChatListNodeViewUpdate, localPinnedItems: Signal<[EngineChatList.Item], NoError>) -> Signal<ChatListNodeViewUpdate, NoError> {
    var isFirst = true
    return localPinnedItems
    |> map { localPinnedItems -> ChatListNodeViewUpdate in
        let type: ViewUpdateType
        let scrollPosition: ChatListNodeViewScrollPosition?
        if isFirst {
            isFirst = false
            type = update.type
            scrollPosition = update.scrollPosition
        } else {
            type = .Generic
            scrollPosition = nil
        }
        if localPinnedItems.isEmpty || update.list.hasLater {
            return ChatListNodeViewUpdate(list: update.list, type: type, scrollPosition: scrollPosition)
        }

        var serverPinnedPeerIds = Set<EnginePeer.Id>()
        var nextPinningIndex: UInt16 = 0
        for item in update.list.items {
            if case let .chatList(index) = item.index, let pinningIndex = index.pinningIndex {
                serverPinnedPeerIds.insert(index.messageIndex.id.peerId)
                nextPinningIndex = max(nextPinningIndex, pinningIndex + 1)
            }
        }

        var items: [EngineChatList.Item] = []
        var localPinnedPeerIds = Set<EnginePeer.Id>()
        for item in localPinnedItems.sorted(by: { $0.index > $1.index }) {
            guard case let .chatList(index) = item.index, !serverPinnedPeerIds.contains(index.messageIndex.id.peerId) else {
                continue
            }
            localPinnedPeerIds.insert(index.messageIndex.id.peerId)
            items.append(item.withUpdatedIndex(.chatList(EngineChatList.Item.Index.ChatList(pinningIndex: nextPinningIndex, messageIndex: index.messageIndex))))
            nextPinningIndex += 1
        }
        for item in update.list.items {
            if case let .chatList(index) = item.index, localPinnedPeerIds.contains(index.messageIndex.id.peerId) {
                continue
            }
            items.append(item)
        }
        items.sort(by: { $0.index < $1.index })

        let list = EngineChatList(
            items: items,
            groupItems: update.list.groupItems,
            additionalItems: update.list.additionalItems,
            hasEarlier: update.list.hasEarlier,
            hasLater: update.list.hasLater,
            isLoading: update.list.isLoading
        )
        return ChatListNodeViewUpdate(list: list, type: type, scrollPosition: scrollPosition)
    }
}

/// The Pin/Unpin of a chat list row with Pin Beyond the Limit on: in All Chats a chat the server won't pin (the limit is
/// reached) is pinned on this device instead, and a chat pinned on this device is unpinned here. Everything else, and
/// every other list, goes to the server as before.
func toggleChatListItemPinned(context: AccountContext, location: TogglePeerChatPinnedLocation, itemId: EngineChatList.PinnedItem.Id) -> Signal<TogglePeerChatPinnedResult, NoError> {
    let engine = context.engine
    guard case .group(.root) = location, case let .peer(peerId) = itemId else {
        return engine.peers.toggleItemPinned(location: location, itemId: itemId)
    }
    return combineLatest(
        forkExtrasSettings(accountManager: context.sharedContext.accountManager) |> take(1),
        localPinnedChatIds(engine: engine) |> take(1),
        engine.peers.getPinnedItemIds(location: location) |> take(1)
    )
    |> mapToSignal { settings, localPinnedPeerIds, serverPinnedItemIds -> Signal<TogglePeerChatPinnedResult, NoError> in
        if !settings.pinBeyondLimit {
            return engine.peers.toggleItemPinned(location: location, itemId: itemId)
        }
        if localPinnedPeerIds.contains(peerId) && !serverPinnedItemIds.contains(itemId) {
            return updateLocalPinnedChatIds(engine: engine, { current in
                return current.filter { $0 != peerId }
            })
            |> map { _ -> TogglePeerChatPinnedResult in }
            |> then(.single(.done))
        }
        return engine.peers.toggleItemPinned(location: location, itemId: itemId)
        |> mapToSignal { result -> Signal<TogglePeerChatPinnedResult, NoError> in
            let update: ([EnginePeer.Id]) -> [EnginePeer.Id]
            switch result {
            case .done:
                // The server pinned or unpinned it; a local copy would bring it back as a local pin.
                if !localPinnedPeerIds.contains(peerId) {
                    return .single(.done)
                }
                update = { current in
                    return current.filter { $0 != peerId }
                }
            case .limitExceeded:
                update = { current in
                    return [peerId] + current.filter { $0 != peerId }
                }
            }
            return updateLocalPinnedChatIds(engine: engine, update)
            |> map { _ -> TogglePeerChatPinnedResult in }
            |> then(.single(.done))
        }
    }
}

/// Whether a chat's context menu offers Unpin for a pin made on this device.
func isChatListItemPinnedLocally(context: AccountContext, location: TogglePeerChatPinnedLocation, peerId: EnginePeer.Id) -> Signal<Bool, NoError> {
    guard case .group(.root) = location else {
        return .single(false)
    }
    return combineLatest(
        forkExtrasSettings(accountManager: context.sharedContext.accountManager) |> take(1),
        localPinnedChatIds(engine: context.engine) |> take(1)
    )
    |> map { settings, localPinnedPeerIds -> Bool in
        return settings.pinBeyondLimit && localPinnedPeerIds.contains(peerId)
    }
}
