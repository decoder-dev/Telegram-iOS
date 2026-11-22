import Foundation
import XCTest
@testable import Postbox

final class StoryExpirationTimeItemsViewTests: XCTestCase {
    private func peer(_ id: Int64) -> PeerId {
        return PeerId(namespace: ._internalFromInt32Value(0), id: ._internalFromInt64Value(id))
    }

    private func item(_ id: Int32, _ expirationTimestamp: Int32?) -> StoryItemsTableEntry {
        return StoryItemsTableEntry(value: CodableEntry(data: Data([1])), id: id, expirationTimestamp: expirationTimestamp, isCloseFriends: false, isLiveStream: false)
    }

    func testReplacingStoriesUsesOnlyTheFinalEntriesAndFindsTheNextPeer() {
        let fixture = PostboxFixture(name: "StoryExpirationTimeItemsViewTests")
        defer { fixture.close() }
        let firstPeer = self.peer(1)
        let secondPeer = self.peer(2)
        let view = fixture.observe(.storyExpirationTimeItems, as: StoryExpirationTimeItemsView.self)
        XCTAssertNil(view.waitForValues(count: 1).last?.topEntry)

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: firstPeer, items: [self.item(1, 100)])
            transaction.setStoryItems(peerId: secondPeer, items: [self.item(2, 200)])
        }
        XCTAssertEqual(view.waitForValues(count: 2).last?.topEntry?.id, StoryId(peerId: firstPeer, id: 1))

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: secondPeer, items: [self.item(3, 25)])
            transaction.setStoryItems(peerId: secondPeer, items: [self.item(4, 150)])
        }
        XCTAssertEqual(view.values.count, 2)

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: firstPeer, items: [self.item(5, 300)])
        }
        XCTAssertEqual(view.waitForValues(count: 3).last?.topEntry?.id, StoryId(peerId: secondPeer, id: 4))

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: firstPeer, items: [self.item(6, 50)])
        }
        XCTAssertEqual(view.waitForValues(count: 4).last?.topEntry?.id, StoryId(peerId: firstPeer, id: 6))

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: firstPeer, items: [self.item(7, nil)])
            transaction.setStoryItems(peerId: secondPeer, items: [])
        }
        XCTAssertNil(view.waitForValues(count: 5).last?.topEntry)
    }

    func testEqualExpirationsUseTheSameKeyOrderForRangeAndFullScans() {
        let fixture = PostboxFixture(name: "StoryExpirationTimeItemsTieTests")
        defer { fixture.close() }
        let firstPeer = self.peer(1)
        let secondPeer = self.peer(2)
        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: secondPeer, items: [self.item(1, 100)])
        }
        let view = fixture.observe(.storyExpirationTimeItems, as: StoryExpirationTimeItemsView.self)
        XCTAssertEqual(view.waitForValues(count: 1).last?.topEntry?.id, StoryId(peerId: secondPeer, id: 1))

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: firstPeer, items: [self.item(2, 100), self.item(1, 100)])
        }
        XCTAssertEqual(view.waitForValues(count: 2).last?.topEntry?.id, StoryId(peerId: firstPeer, id: 1))

        fixture.transaction { transaction in
            transaction.setStoryItems(peerId: firstPeer, items: [self.item(2, 100)])
        }
        XCTAssertEqual(view.waitForValues(count: 3).last?.topEntry?.id, StoryId(peerId: firstPeer, id: 2))
    }
}
