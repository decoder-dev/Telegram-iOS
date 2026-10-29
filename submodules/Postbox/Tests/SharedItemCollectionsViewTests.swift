import Foundation
import XCTest
import SwiftSignalKit
@testable import Postbox

private final class FixtureCollectionInfo: ItemCollectionInfo {
    static let register: Void = {
        declareEncodable(FixtureCollectionInfo.self, f: { FixtureCollectionInfo(decoder: $0) })
        declareEncodable(FixtureCollectionItem.self, f: { FixtureCollectionItem(decoder: $0) })
    }()

    let title: String

    init(title: String) {
        self.title = title
    }

    init(decoder: PostboxDecoder) {
        self.title = decoder.decodeStringForKey("t", orElse: "")
    }

    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.title, forKey: "t")
    }
}

private final class FixtureCollectionItem: ItemCollectionItem {
    let index: ItemCollectionItemIndex
    let indexKeys: [MemoryBuffer] = []

    init(index: ItemCollectionItemIndex) {
        self.index = index
    }

    init(decoder: PostboxDecoder) {
        self.index = ItemCollectionItemIndex(index: decoder.decodeInt32ForKey("i", orElse: 0), id: decoder.decodeInt64ForKey("d", orElse: 0))
    }

    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.index.index, forKey: "i")
        encoder.encodeInt64(self.index.id, forKey: "d")
    }
}

/// A whole-namespace item collections view (every installed sticker or emoji pack, which each chat's input panel asks
/// for) is built once and shared by its subscribers, stays current while shared, and is kept a while after the last
/// subscriber leaves, so the next chat does not decode every pack again.
final class SharedItemCollectionsViewTests: XCTestCase {
    private var fixture: PostboxFixture!
    private let namespace: ItemCollectionId.Namespace = 7

    override func setUp() {
        super.setUp()
        let _ = FixtureCollectionInfo.register
        self.fixture = PostboxFixture(name: "SharedItemCollectionsViewTests")
        self.install(packs: 2)
    }

    override func tearDown() {
        self.fixture.close()
        self.fixture = nil
        super.tearDown()
    }

    private func install(packs count: Int) {
        let namespace = self.namespace
        self.fixture.transaction { transaction in
            let collections = (0 ..< count).map { i -> (ItemCollectionId, ItemCollectionInfo, [ItemCollectionItem]) in
                let id = ItemCollectionId(namespace: namespace, id: Int64(i + 1))
                return (id, FixtureCollectionInfo(title: "pack \(i)"), [FixtureCollectionItem(index: ItemCollectionItemIndex(index: 0, id: Int64(i * 10 + 1)))])
            }
            transaction.replaceItemCollections(namespace: namespace, itemCollections: collections)
        }
    }

    private func view(aroundIndex: ItemCollectionViewEntryIndex? = nil) -> Signal<ItemCollectionsView, NoError> {
        return self.fixture.postbox.itemCollectionsView(orderedItemListCollectionIds: [], namespaces: [self.namespace], aroundIndex: aroundIndex, count: 10000000)
    }

    func testSubscribersShareOneViewAndItsUpdates() {
        let first = self.fixture.observe(self.view())
        let second = self.fixture.observe(self.view())
        let a = first.waitForValues(count: 1)
        let b = second.waitForValues(count: 1)
        XCTAssertTrue(a[0] === b[0], "built once, given to both")
        XCTAssertEqual(a[0].collectionInfos.count, 2)

        self.install(packs: 3)
        XCTAssertEqual(first.waitForValues(count: 2)[1].collectionInfos.count, 3)
        XCTAssertEqual(second.waitForValues(count: 2)[1].collectionInfos.count, 3)
        XCTAssertEqual(second.values[1].entries.count, 3)
    }

    func testAViewKeptAfterItsLastSubscriberStaysCurrent() {
        let semaphore = DispatchSemaphore(value: 0)
        var firstValue: ItemCollectionsView?
        let disposable = self.view().start(next: { value in
            if firstValue == nil {
                firstValue = value
                semaphore.signal()
            }
        })
        XCTAssertEqual(semaphore.wait(timeout: .now() + 10.0), .success)
        disposable.dispose()
        // The release is queued after the subscriber leaves; a transaction after it runs after it.
        self.fixture.transaction { _ in }

        self.install(packs: 4)
        let later = self.fixture.observe(self.view())
        let values = later.waitForValues(count: 1)
        XCTAssertEqual(values[0].collectionInfos.count, 4, "the kept view followed the change")
        XCTAssertEqual(values[0].entries.count, 4)
    }

    func testAViewAroundAnIndexIsNotShared() {
        let index = ItemCollectionViewEntryIndex(collectionIndex: 0, collectionId: ItemCollectionId(namespace: self.namespace, id: 1), itemIndex: ItemCollectionItemIndex(index: 0, id: 1))
        let first = self.fixture.observe(self.view(aroundIndex: index))
        let second = self.fixture.observe(self.view(aroundIndex: index))
        XCTAssertFalse(first.waitForValues(count: 1)[0] === second.waitForValues(count: 1)[0])
    }
}
