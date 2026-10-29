import Foundation
import Postbox

/// Fork: a small list kept per account as JSON in `UserDefaults` under `"<keyPrefix>.<account id>"`. Lists are read
/// once and served from memory afterwards, and every read and change holds one lock, so callers on any queue (a
/// context menu is built off the main thread) neither decode the list on each call nor lose a concurrent change.
public final class BananaAccountListStore<Item: Codable> {
    private let keyPrefix: String
    private let lock = NSLock()
    private var cache: [Int64: [Item]] = [:]

    public init(keyPrefix: String) {
        self.keyPrefix = keyPrefix
    }

    private func key(_ accountPeerId: PeerId) -> String {
        return "\(self.keyPrefix).\(accountPeerId.toInt64())"
    }

    private func loadedItems(_ accountPeerId: PeerId) -> [Item] {
        let id = accountPeerId.toInt64()
        if let cached = self.cache[id] {
            return cached
        }
        var items: [Item] = []
        if let data = UserDefaults.standard.data(forKey: self.key(accountPeerId)), let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
        }
        self.cache[id] = items
        return items
    }

    public func items(accountPeerId: PeerId) -> [Item] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadedItems(accountPeerId)
    }

    /// Changes the list in place and writes it back.
    public func update(accountPeerId: PeerId, _ f: (inout [Item]) -> Void) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var items = self.loadedItems(accountPeerId)
        f(&items)
        self.cache[accountPeerId.toInt64()] = items
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: self.key(accountPeerId))
        }
    }
}
