import Foundation

public struct StoryExpirationTimeEntry: Equatable {
    public var id: StoryId
    public var expirationTimestamp: Int32

    init(id: StoryId, expirationTimestamp: Int32) {
        self.id = id
        self.expirationTimestamp = expirationTimestamp
    }

    fileprivate func precedes(_ other: StoryExpirationTimeEntry) -> Bool {
        if self.expirationTimestamp != other.expirationTimestamp {
            return self.expirationTimestamp < other.expirationTimestamp
        }
        // The full scan breaks ties by the order of the big-endian database keys.
        if self.id.peerId != other.id.peerId {
            return UInt64(bitPattern: self.id.peerId.toInt64()) < UInt64(bitPattern: other.id.peerId.toInt64())
        }
        return UInt32(bitPattern: self.id.id) < UInt32(bitPattern: other.id.id)
    }
}

final class MutableStoryExpirationTimeItemsView: MutablePostboxView {
    var topEntry: StoryExpirationTimeEntry?

    init(postbox: PostboxImpl) {
        let _ = self.refreshDueToExternalTransaction(postbox: postbox)
    }
    
    func replay(postbox: PostboxImpl, transaction: PostboxTransaction) -> Bool {
        guard !transaction.storyItemsEvents.isEmpty else {
            return false
        }
        var changedPeerIds = Set<PeerId>()
        for event in transaction.storyItemsEvents {
            if case let .replace(peerId) = event {
                changedPeerIds.insert(peerId)
            }
        }

        var earliestChanged: StoryExpirationTimeEntry?
        for peerId in changedPeerIds {
            if let item = postbox.storyItemsTable.getMinExpirationTimestamp(peerId: peerId) {
                let entry = StoryExpirationTimeEntry(id: item.0, expirationTimestamp: item.1)
                if earliestChanged.map({ entry.precedes($0) }) ?? true {
                    earliestChanged = entry
                }
            }
        }

        if let topEntry = self.topEntry {
            if changedPeerIds.contains(topEntry.id.peerId) {
                // Only a removed or later minimum makes the unchanged peers candidates again.
                if earliestChanged.map({ topEntry.precedes($0) }) ?? true {
                    return self.refreshDueToExternalTransaction(postbox: postbox)
                }
            } else if !(earliestChanged.map { $0.precedes(topEntry) } ?? false) {
                return false
            }
        }

        return self.updateTopEntry(earliestChanged)
    }

    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool {
        var topEntry: StoryExpirationTimeEntry?
        if let item = postbox.storyItemsTable.getMinExpirationTimestamp() {
            topEntry = StoryExpirationTimeEntry(id: item.0, expirationTimestamp: item.1)
        }
        return self.updateTopEntry(topEntry)
    }

    private func updateTopEntry(_ topEntry: StoryExpirationTimeEntry?) -> Bool {
        if self.topEntry != topEntry {
            self.topEntry = topEntry
            return true
        } else {
            return false
        }
    }
    
    func immutableView() -> PostboxView {
        return StoryExpirationTimeItemsView(self)
    }
}

public final class StoryExpirationTimeItemsView: PostboxView {
    public let topEntry: StoryExpirationTimeEntry?
    
    init(_ view: MutableStoryExpirationTimeItemsView) {
        self.topEntry = view.topEntry
    }
}
