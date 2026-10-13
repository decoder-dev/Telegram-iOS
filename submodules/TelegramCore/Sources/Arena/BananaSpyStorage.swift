import Foundation
import Postbox
import SwiftSignalKit

/// Local, per-account record keeping that never leaves the device: what a profile showed before it changed, the text a
/// deleted message was replied with, when somebody was last seen. It sits on Postbox's item cache, so it is stored with
/// the account (removed with it on logout) and needs no schema change. Adapted from Donutgram's `DonutgramSpyStorage`.
///
/// Every collection is a separate `Namespaces.CachedItemCollection` id; the keys are fixed-width so ranges never
/// overlap, and every list kept here is bounded by its caller.
public enum BananaSpyStorage {
    private static let flags = Atomic<Flags>(value: Flags())

    private struct Flags {
        var trackDisappearedGifts = false
    }

    /// Whether a profile's gift list is read to the end and remembered, so gifts that vanish can still be shown.
    /// Off by default: it costs one extra request per page of every profile that is opened.
    public static var trackDisappearedGifts: Bool {
        get { return flags.with { $0.trackDisappearedGifts } }
        set {
            let previous = flags.with { $0.trackDisappearedGifts }
            let _ = flags.modify { var value = $0; value.trackDisappearedGifts = newValue; return value }
            if previous != newValue {
                NotificationCenter.default.post(name: trackDisappearedGiftsDidChangeNotification, object: nil)
            }
        }
    }
    
    public static let trackDisappearedGiftsDidChangeNotification = Notification.Name("BananaSpyStorage.trackDisappearedGifts.didChange")

    public enum Collection {
        case disappearedGifts
        case presence

        var id: Int8 {
            switch self {
            case .disappearedGifts:
                return Namespaces.CachedItemCollection.bananaDisappearedGifts
            case .presence:
                return Namespaces.CachedItemCollection.bananaPresence
            }
        }
    }

    public static func entryId(_ collection: Collection, peerId: PeerId) -> ItemCacheEntryId {
        let key = ValueBoxKey(length: 8)
        key.setInt64(0, value: peerId.toInt64())
        return ItemCacheEntryId(collectionId: collection.id, key: key)
    }

    public static func read<T: Codable>(_ type: T.Type, transaction: Transaction, collection: Collection, peerId: PeerId) -> T? {
        return transaction.retrieveItemCacheEntry(id: entryId(collection, peerId: peerId))?.get(type)
    }

    public static func write<T: Codable>(_ value: T, transaction: Transaction, collection: Collection, peerId: PeerId) {
        if let entry = CodableEntry(value) {
            transaction.putItemCacheEntry(id: entryId(collection, peerId: peerId), entry: entry)
        }
    }

    public static func remove(transaction: Transaction, collection: Collection, peerId: PeerId) {
        transaction.removeItemCacheEntry(id: entryId(collection, peerId: peerId))
    }
}
