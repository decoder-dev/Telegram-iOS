import Foundation
import Postbox

private struct BananaBannedChat: Codable {
    let saved: Bool
}

private func bananaBannedChatCacheId(_ peerId: PeerId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.toInt64())
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.bananaBannedChats, key: key)
}

public func bananaPeerIsBanned(_ peer: Peer?) -> Bool {
    if let group = peer as? TelegramGroup {
        return group.membership == .Removed && !group.flags.contains(.deactivated)
    } else if let channel = peer as? TelegramChannel {
        return channel.participationStatus == .kicked
    }
    return false
}

/// `bananaIsPreservedBannedChat(transaction:peerId:peer:)` as the UI sees it in a `PeerView`: a banned chat that is
/// still in the chat list. `updatePeersCustom` takes every banned chat it does not keep out of the list in the same
/// transaction, so the peer and the list position of one view answer it without the item cache, and never disagree.
public func bananaIsPreservedBannedChat(peer: Peer?, groupId: PeerGroupId?) -> Bool {
    return groupId != nil && bananaPeerIsBanned(peer)
}

/// A local archive keeps the real banned membership, so normal input restrictions still apply.
func bananaIsPreservedBannedChat(transaction: Transaction, peerId: PeerId, peer: Peer? = nil) -> Bool {
    guard bananaPeerIsBanned(peer ?? transaction.getPeer(peerId)),
          transaction.getPeerChatListInclusion(peerId) != .notIncluded else {
        return false
    }
    return transaction.retrieveItemCacheEntry(id: bananaBannedChatCacheId(peerId))?.get(BananaBannedChat.self)?.saved == true
}

/// A pinned chat kept after a ban stays pinned here only: the server no longer lists it among the pinned chats, so each
/// pinned list it sends would unpin it. Puts the kept chats of `currentItemIds` back at their places in `itemIds`.
func bananaKeepingPinnedBannedChats(transaction: Transaction, currentItemIds: [PinnedItemId], itemIds: [PinnedItemId]) -> [PinnedItemId] {
    var result = itemIds
    for (index, itemId) in currentItemIds.enumerated() {
        guard case let .peer(peerId) = itemId, !result.contains(itemId), bananaIsPreservedBannedChat(transaction: transaction, peerId: peerId) else {
            continue
        }
        result.insert(itemId, at: min(index, result.count))
    }
    return result
}

/// The peer stored for a kept chat. A ban arrives as a stripped object (`channelForbidden`, `chatForbidden`) with only an id,
/// a title and an access hash: no photo, username, creation date or flags, so a forum would open as a plain chat. The kept
/// chat stays the chat it was, and only what the ban changed comes from the new object.
func bananaPreservedBannedPeer(previous: Peer?, updated: Peer) -> Peer {
    if let previous = previous as? TelegramChannel, let updated = updated as? TelegramChannel {
        return TelegramChannel(id: previous.id, accessHash: updated.accessHash ?? previous.accessHash, title: previous.title, username: previous.username, photo: previous.photo, creationDate: previous.creationDate, version: previous.version, participationStatus: updated.participationStatus, info: previous.info, flags: previous.flags, restrictionInfo: previous.restrictionInfo, adminRights: updated.adminRights, bannedRights: updated.bannedRights, defaultBannedRights: previous.defaultBannedRights, usernames: previous.usernames, storiesHidden: previous.storiesHidden, nameColor: previous.nameColor, backgroundEmojiId: previous.backgroundEmojiId, profileColor: previous.profileColor, profileBackgroundEmojiId: previous.profileBackgroundEmojiId, emojiStatus: previous.emojiStatus, approximateBoostLevel: previous.approximateBoostLevel, subscriptionUntilDate: previous.subscriptionUntilDate, verificationIconFileId: previous.verificationIconFileId, sendPaidMessageStars: previous.sendPaidMessageStars, linkedMonoforumId: previous.linkedMonoforumId, linkedCommunityId: previous.linkedCommunityId)
    } else if let previous = previous as? TelegramGroup, let updated = updated as? TelegramGroup {
        return TelegramGroup(id: previous.id, title: previous.title, photo: previous.photo, participantCount: previous.participantCount, role: updated.role, membership: updated.membership, flags: previous.flags, defaultBannedRights: previous.defaultBannedRights, migrationReference: previous.migrationReference, creationDate: previous.creationDate, version: previous.version)
    }
    return updated
}

func bananaUpdateBannedChat(transaction: Transaction, previous: Peer?, updated: Peer) {
    guard updated is TelegramGroup || updated is TelegramChannel else { return }
    let cacheId = bananaBannedChatCacheId(updated.id)
    if !bananaPeerIsBanned(updated) {
        // Only a banned chat can have the marker, so the hundreds of updates of a chat list load skip the item cache.
        if bananaPeerIsBanned(previous), transaction.retrieveItemCacheEntry(id: cacheId) != nil {
            transaction.removeItemCacheEntry(id: cacheId)
            // Membership was restored: allow normal history synchronization again.
            transaction.addHole(peerId: updated.id, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
            for threadId in transaction.setMessageHistoryThreads(peerId: updated.id) {
                transaction.addHole(peerId: updated.id, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
            }
        }
        return
    }

    let wasMember: Bool
    if let group = previous as? TelegramGroup {
        wasMember = group.membership == .Member
    } else if let channel = previous as? TelegramChannel {
        wasMember = channel.participationStatus == .member
    } else {
        wasMember = false
    }
    if ForkKeepBannedChatsSettings.enabled, (wasMember || bananaPeerIsBanned(previous)),
       transaction.getPeerChatListInclusion(updated.id) != .notIncluded,
       let entry = CodableEntry(BananaBannedChat(saved: true)) {
        transaction.putItemCacheEntry(id: cacheId, entry: entry)
    }
    if bananaIsPreservedBannedChat(transaction: transaction, peerId: updated.id, peer: updated) {
        // Do not leave a loading hole where the server can no longer supply history.
        transaction.removeHole(peerId: updated.id, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
        for threadId in transaction.setMessageHistoryThreads(peerId: updated.id) {
            transaction.removeHole(peerId: updated.id, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
        }
    }
}
