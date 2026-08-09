import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

/// Account-scoped blocked peer ids for AyuGram-style Hide Blocked Messages filtering.
/// Updated from AccountContextImpl via BlockedPeersContext; read from history/typing paths.
enum ForkBlockedPeersFilter {
    private static let map = Atomic<[PeerId: Set<PeerId>]>(value: [:])

    static func update(accountPeerId: PeerId, peerIds: Set<PeerId>) {
        let _ = map.modify { current in
            var next = current
            next[accountPeerId] = peerIds
            return next
        }
    }

    /// Take once per history rebuild — avoid an Atomic lock per message.
    static func peerIds(accountPeerId: PeerId) -> Set<PeerId> {
        return map.with { $0[accountPeerId] ?? [] }
    }

    static func contains(accountPeerId: PeerId, peerId: PeerId) -> Bool {
        return map.with { $0[accountPeerId]?.contains(peerId) ?? false }
    }
}
