// Read All from the chat list, adapted from kittenello/Donutgram (DonutgramReadAllMessages).
import Foundation
import Postbox
import SwiftSignalKit

public extension TelegramEngine.Messages {
    /// The chats Read All goes through, from the main list and, if asked, the archive. On the
    /// server that includes the chats read only on this device: they look read here but are
    /// still unread there.
    func bananaReadAllChatPeerIds(includeArchived: Bool, onServer: Bool) -> Signal<[EnginePeer.Id], NoError> {
        let accountPeerId = self.account.peerId
        return self.account.postbox.transaction { transaction -> [EnginePeer.Id] in
            var groupIds: [PeerGroupId] = [.root]
            if includeArchived {
                groupIds.append(Namespaces.PeerGroup.archive)
            }
            var peerIds: [PeerId] = []
            for groupId in groupIds {
                peerIds.append(contentsOf: transaction.getUnreadChatListPeerIds(groupId: groupId, filterPredicate: nil, additionalFilter: nil, stopOnFirstMatch: false))
            }
            if onServer {
                var seen = Set(peerIds)
                for key in TelegramSimpleSettings.shared.ghostLocalReads(accountPeerId: accountPeerId.toInt64()).keys {
                    let peerId = PeerId(key)
                    if let groupId = transaction.getPeerChatListIndex(peerId)?.0, groupIds.contains(groupId), !seen.contains(peerId) {
                        seen.insert(peerId)
                        peerIds.append(peerId)
                    }
                }
            }
            return peerIds
        }
    }

    /// Read All, only on this device: the chats are read here and nothing is sent. Returns how
    /// many were read; secret chats, forums and channel direct messages can't be read this way
    /// and stay unread.
    func bananaReadChatsOnThisDevice(peerIds: [EnginePeer.Id]) -> Signal<Int, NoError> {
        let account = self.account
        return account.postbox.transaction { transaction -> Int in
            var readCount = 0
            var readMessageIds: [MessageId] = []
            for peerId in peerIds {
                guard let index = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud) else {
                    continue
                }
                if bananaApplyDeviceOnlyRead(transaction: transaction, accountPeerId: account.peerId, index: index) {
                    readCount += 1
                    readMessageIds.append(index.id)
                }
            }
            // Removes their notifications, as reading in ghost mode does.
            if !readMessageIds.isEmpty {
                account.stateManager.notifyAppliedIncomingReadMessages(readMessageIds)
            }
            return readCount
        }
    }
}
