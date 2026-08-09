import Foundation
import XCTest
import TelegramCore
import TelegramUIPreferences

/// Covers the invariants of the saved-message store that are pure logic: deduplication, the
/// reference-counted indexes behind hasDeleted / hasEdits, the per-message edit cap, and the
/// containment guard that decides whether a stored path may be deleted from disk.
///
/// The store keeps static state and persists to Application Support, so every test starts by
/// pointing it at its own temporary directory via resetForTesting.
final class MessageSavingStoreTests: XCTestCase {
    private var directory: URL!

    private let account: Int64 = 1000
    private let peer: Int64 = 2000
    private let namespace: Int32 = 0

    override func setUp() {
        super.setUp()
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageSavingStoreTests-\(UUID().uuidString)", isDirectory: true)
        MessageSavingStore.resetForTesting(directory: self.directory)
    }

    override func tearDown() {
        if let directory = self.directory {
            try? FileManager.default.removeItem(at: directory)
        }
        super.tearDown()
    }

    private func record(
        messageId: Int32,
        text: String,
        kind: MessageSavingKind,
        mediaPath: String? = nil,
        savedAt: Int32 = 0,
        peerId: Int64? = nil
    ) -> MessageSavingRecord {
        return MessageSavingRecord(
            id: UUID().uuidString,
            accountPeerId: self.account,
            peerId: peerId ?? self.peer,
            messageId: messageId,
            namespace: self.namespace,
            date: 100,
            authorId: 3000,
            authorName: "Author",
            text: text,
            kind: kind,
            savedAt: savedAt,
            topicId: 0,
            mediaPath: mediaPath
        )
    }

    // MARK: - Deleted snapshots

    /// The bug this store shipped with: the first snapshot of a deleted message is often taken
    /// while its media is still downloading, so it carries no path, and the later snapshot that
    /// does carry one used to be discarded as a duplicate. The path has to be merged in.
    func testRepeatDeletedSnapshotMergesMediaPathIntoExistingRecord() {
        MessageSavingStore.append(self.record(messageId: 1, text: "hi", kind: .deleted, mediaPath: nil))
        MessageSavingStore.append(self.record(messageId: 1, text: "hi", kind: .deleted, mediaPath: "/tmp/a.jpg"))

        let stored = MessageSavingStore.deleted(accountPeerId: self.account, peerId: self.peer)
        XCTAssertEqual(stored.count, 1, "the repeat snapshot must not create a second record")
        XCTAssertEqual(stored.first?.mediaPath, "/tmp/a.jpg", "the late path must be merged in, not dropped")
    }

    func testRepeatDeletedSnapshotDoesNotClearAnExistingMediaPath() {
        MessageSavingStore.append(self.record(messageId: 1, text: "hi", kind: .deleted, mediaPath: "/tmp/a.jpg"))
        MessageSavingStore.append(self.record(messageId: 1, text: "hi", kind: .deleted, mediaPath: nil))

        let stored = MessageSavingStore.deleted(accountPeerId: self.account, peerId: self.peer)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.mediaPath, "/tmp/a.jpg")
    }

    /// Same message id, different text is a different snapshot and must be kept.
    func testDeletedSnapshotsWithDifferentTextAreBothKept() {
        MessageSavingStore.append(self.record(messageId: 1, text: "first", kind: .deleted))
        MessageSavingStore.append(self.record(messageId: 1, text: "second", kind: .deleted))

        XCTAssertEqual(MessageSavingStore.deleted(accountPeerId: self.account, peerId: self.peer).count, 2)
    }

    // MARK: - Indexes

    func testHasDeletedTracksInsertionAndClearing() {
        XCTAssertFalse(MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: self.peer))

        MessageSavingStore.append(self.record(messageId: 1, text: "hi", kind: .deleted))
        XCTAssertTrue(MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: self.peer))

        MessageSavingStore.clearDeleted(accountPeerId: self.account, peerId: self.peer)
        XCTAssertFalse(MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: self.peer))
    }

    /// The index is reference counted, so clearing one peer must not answer for another.
    func testClearingOnePeerLeavesAnotherPeersRecords() {
        let otherPeer: Int64 = 2001
        MessageSavingStore.append(self.record(messageId: 1, text: "a", kind: .deleted))
        MessageSavingStore.append(self.record(messageId: 2, text: "b", kind: .deleted, peerId: otherPeer))

        MessageSavingStore.clearDeleted(accountPeerId: self.account, peerId: self.peer)

        XCTAssertFalse(MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: self.peer))
        XCTAssertTrue(MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: otherPeer))
    }

    /// hasDeleted must not answer true for a different account holding the same peer id.
    func testIndexIsScopedByAccount() {
        MessageSavingStore.append(self.record(messageId: 1, text: "a", kind: .deleted))
        XCTAssertFalse(MessageSavingStore.hasDeleted(accountPeerId: 9999, peerId: self.peer))
    }

    func testHasEditsTracksInsertion() {
        XCTAssertFalse(MessageSavingStore.hasEdits(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace))

        MessageSavingStore.append(self.record(messageId: 7, text: "v1", kind: .edited))
        XCTAssertTrue(MessageSavingStore.hasEdits(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace))
    }

    // MARK: - Edit history

    func testConsecutiveIdenticalEditSnapshotsAreDeduplicated() {
        MessageSavingStore.append(self.record(messageId: 7, text: "same", kind: .edited, savedAt: 1))
        MessageSavingStore.append(self.record(messageId: 7, text: "same", kind: .edited, savedAt: 2))

        XCTAssertEqual(MessageSavingStore.editCountForTesting(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace), 1)
    }

    /// A -> B -> A is three real versions; only a repeat of the *latest* is a duplicate.
    func testEditRevertingToAnEarlierTextIsKept() {
        MessageSavingStore.append(self.record(messageId: 7, text: "A", kind: .edited, savedAt: 1))
        MessageSavingStore.append(self.record(messageId: 7, text: "B", kind: .edited, savedAt: 2))
        MessageSavingStore.append(self.record(messageId: 7, text: "A", kind: .edited, savedAt: 3))

        XCTAssertEqual(MessageSavingStore.editCountForTesting(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace), 3)
    }

    /// A message edited far past the cap keeps only the newest versions, and — the point of the
    /// cap — does not push a saved deleted message out of the store.
    ///
    /// The edit count deliberately exceeds the store's global 5000-record cap: without the
    /// per-message limit these versions alone would fill the store and the deleted record, added
    /// first, would be the first evicted. That is the failure this cap exists to prevent, so the
    /// test has to get past 5000 to actually exercise it.
    func testRunawayEditorIsCappedAndDoesNotEvictOtherRecords() {
        MessageSavingStore.append(self.record(messageId: 1, text: "keep me", kind: .deleted))

        for index in 0 ..< 6000 {
            MessageSavingStore.append(self.record(messageId: 7, text: "version \(index)", kind: .edited, savedAt: Int32(index)))
        }

        let retained = MessageSavingStore.editCountForTesting(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace)
        XCTAssertLessThanOrEqual(retained, 32)

        let edits = MessageSavingStore.edits(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace)
        XCTAssertEqual(edits.first?.text, "version 5999", "the newest version must survive")
        XCTAssertFalse(edits.contains(where: { $0.text == "version 0" }), "the oldest versions must be the ones dropped")

        XCTAssertTrue(
            MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: self.peer),
            "a chatty message must not evict saved deleted messages"
        )
    }

    /// Eviction must keep the reference-counted index in step; a stale count would leave
    /// hasEdits answering true for a message with nothing left.
    func testEditIndexStaysConsistentAfterEviction() {
        for index in 0 ..< 100 {
            MessageSavingStore.append(self.record(messageId: 7, text: "v\(index)", kind: .edited, savedAt: Int32(index)))
        }

        let indexed = MessageSavingStore.editCountForTesting(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace)
        let actual = MessageSavingStore.edits(accountPeerId: self.account, peerId: self.peer, messageId: 7, namespace: self.namespace).count
        XCTAssertEqual(indexed, actual, "index count and stored records disagree")
    }

    // MARK: - Attachment path linking

    func testAttachMediaPathLinksALateCopy() {
        MessageSavingStore.append(self.record(messageId: 1, text: "hi", kind: .deleted, mediaPath: nil))

        MessageSavingStore.attachMediaPath(
            accountPeerId: self.account,
            peerId: self.peer,
            messageId: 1,
            namespace: self.namespace,
            mediaPath: "/tmp/late.mp4"
        )

        XCTAssertEqual(
            MessageSavingStore.deleted(accountPeerId: self.account, peerId: self.peer).first?.mediaPath,
            "/tmp/late.mp4"
        )
    }

    // MARK: - Deletion containment guard

    func testPathContainmentAcceptsFilesInsideTheRoot() {
        let root = URL(fileURLWithPath: "/var/app/MessageSaving/Saved Attachments", isDirectory: true)
        XCTAssertTrue(MessageSavingStore.isPath("/var/app/MessageSaving/Saved Attachments/a.jpg", strictlyInside: root))
        XCTAssertTrue(MessageSavingStore.isPath("/var/app/MessageSaving/Saved Attachments/nested/a.jpg", strictlyInside: root))
    }

    func testPathContainmentRejectsEscapesAndNeighbours() {
        let root = URL(fileURLWithPath: "/var/app/MessageSaving/Saved Attachments", isDirectory: true)

        // Traversal out of the root, which standardizing resolves before the comparison.
        XCTAssertFalse(MessageSavingStore.isPath("/var/app/MessageSaving/Saved Attachments/../../secrets.db", strictlyInside: root))
        // A sibling whose name merely starts the same way — what a raw string prefix would accept.
        XCTAssertFalse(MessageSavingStore.isPath("/var/app/MessageSaving/Saved Attachments Backup/a.jpg", strictlyInside: root))
        // Somewhere else entirely.
        XCTAssertFalse(MessageSavingStore.isPath("/var/app/Documents/a.jpg", strictlyInside: root))
        // The root itself is not inside itself, so a corrupted record cannot delete the folder.
        XCTAssertFalse(MessageSavingStore.isPath("/var/app/MessageSaving/Saved Attachments", strictlyInside: root))
    }

    // MARK: - Persistence

    /// flush writes through, and a store pointed back at the same directory reads it back.
    func testRecordsSurviveAFlushAndReload() {
        MessageSavingStore.append(self.record(messageId: 1, text: "persisted", kind: .deleted))
        MessageSavingStore.flush()

        // Same directory: reset clears memory and the loaded flag, so the next read comes off disk.
        MessageSavingStore.resetForTesting(directory: self.directory)

        let stored = MessageSavingStore.deleted(accountPeerId: self.account, peerId: self.peer)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.text, "persisted")
        XCTAssertTrue(
            MessageSavingStore.hasDeleted(accountPeerId: self.account, peerId: self.peer),
            "indexes must be rebuilt on load, not left empty"
        )
    }
}
