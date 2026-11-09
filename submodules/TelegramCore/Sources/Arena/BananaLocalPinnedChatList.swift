// Pin Beyond the Limit: the chat list rows of chats pinned on this device only.
import Foundation
import Postbox
import SwiftSignalKit

// Postbox keeps the pinned peers of a filtered list in a space of their own. The group spaces it adds beside it are
// pointed at a group no chat is ever in, so they hold neither chats nor holes: a hole there would start loading the
// whole chat list just to show a few pinned chats.
private let localPinsEmptyGroupId = PeerGroupId(rawValue: Int32.max)

public extension TelegramEngine.Messages {
    /// The chat list rows of `peerIds`, as Postbox would list them if they were pinned, without loading the chat list.
    func bananaChatListItems(pinnedPeerIds peerIds: [EnginePeer.Id]) -> Signal<[EngineChatList.Item], NoError> {
        if peerIds.isEmpty {
            return .single([])
        }
        let account = self.account
        let predicate = ChatListFilterPredicate(includePeerIds: Set(), excludePeerIds: Set(), pinnedPeerIds: peerIds, messageTagSummary: nil, includeAdditionalPeerGroupIds: [], include: { _, _, _, _, _ in
            return false
        })
        return account.viewTracker.tailChatListView(groupId: localPinsEmptyGroupId, filterPredicate: predicate, count: peerIds.count + 1)
        |> map { view, _ -> [EngineChatList.Item] in
            return EngineChatList(view, accountPeerId: account.peerId).items
        }
    }
}
