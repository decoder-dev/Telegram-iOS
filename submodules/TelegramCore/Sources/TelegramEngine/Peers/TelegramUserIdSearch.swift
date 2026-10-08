import Foundation
import Postbox
import SwiftSignalKit

/// Telegram user ids are positive decimal integers. Reject phone numbers,
/// usernames and ids outside Postbox's 56-bit peer-id representation.
public func telegramUserIdFromSearchQuery(_ query: String) -> Int64? {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let id = Int64(value), id > 0, id <= 0x00ffffffffffffff else {
        return nil
    }
    return id
}

func telegramCanOpenIdSearchUser(_ user: TelegramUser, accountPeerId: PeerId) -> Bool {
    if user.id == accountPeerId {
        return true
    }
    if user.flags.contains(.isSupport) {
        return false
    }
    return true
}

func telegramSearchUserById(accountPeerId: PeerId, postbox: Postbox, userId: Int64, scope: TelegramSearchPeersScope) -> Signal<FoundPeer?, NoError> {
    switch scope {
    case .everywhere, .privateChats, .bots:
        break
    default:
        return .single(nil)
    }
    let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(userId))
    return postbox.transaction { transaction -> FoundPeer? in
        guard let user = transaction.getPeer(peerId) as? TelegramUser,
              telegramCanOpenIdSearchUser(user, accountPeerId: accountPeerId) else {
            return nil
        }
        if case .bots = scope, user.botInfo == nil {
            return nil
        }
        return FoundPeer(peer: EnginePeer(user), subscribers: nil)
    }
}
