import XCTest
import SwiftSignalKit

final class ArchiveSessionTests: XCTestCase {
    func testProtectedSessionAndAccountSwitch() {
        let session = ArchiveLockSession.shared
        let firstState = ValuePipe<Bool>()
        session.bindPasswordProtection(accountId: 1001, isPasswordConfigured: firstState.signal())
        XCTAssertFalse(session.isUnlocked)
        XCTAssertFalse(session.isRevealed)
        firstState.putNext(true)
        session.reveal()
        XCTAssertTrue(session.isRevealed)
        XCTAssertFalse(session.isUnlocked, "Ten taps must not authenticate")
        session.unlock()
        XCTAssertTrue(session.isUnlocked)

        let generation = session.authorizationGeneration
        let secondState = ValuePipe<Bool>()
        session.bindPasswordProtection(accountId: 1002, isPasswordConfigured: secondState.signal())
        XCTAssertFalse(session.isUnlocked, "Account switch must invalidate authentication synchronously")
        XCTAssertFalse(session.isRevealed)
        XCTAssertNotEqual(session.authorizationGeneration, generation)
        firstState.putNext(false)
        XCTAssertTrue(session.isPasswordConfigured, "Obsolete account must not release the lock")
        secondState.putNext(true)
        XCTAssertFalse(session.isRevealed)
    }

    func testRelockInvalidatesPendingAuthenticationEvenBeforeUnlock() {
        let session = ArchiveLockSession.shared
        session.bindPasswordProtection(accountId: 2001, isPasswordConfigured: .single(true))
        let before = session.authorizationGeneration
        session.relock()
        XCTAssertNotEqual(session.authorizationGeneration, before)
        XCTAssertFalse(session.isUnlocked)
    }

    func testUnprotectedAccountRetainsStockBehavior() {
        let session = ArchiveLockSession.shared
        session.bindPasswordProtection(accountId: 3001, isPasswordConfigured: .single(false))
        XCTAssertFalse(session.isPasswordConfigured)
        XCTAssertTrue(session.isRevealed)
        session.relock()
        XCTAssertTrue(session.isRevealed)
    }

    func testLockedPeerCacheIsReplacedOnAccountChange() {
        let session = ArchiveLockSession.shared
        session.bindPasswordProtection(accountId: 4001, isPasswordConfigured: .single(true))
        session.bindLockedPeerIds(accountId: 4001, lockedPeerIds: .single([EnginePeer.Id(1)]))
        XCTAssertTrue(session.isLockedArchivedPeer(EnginePeer.Id(1)))
        XCTAssertFalse(session.isLockedArchivedPeer(EnginePeer.Id(2)))
        let pending = ValuePipe<Set<EnginePeer.Id>>()
        session.bindLockedPeerIds(accountId: 4002, lockedPeerIds: pending.signal())
        XCTAssertTrue(session.isLockedArchivedPeer(EnginePeer.Id(2)), "Unknown cache must fail closed")
        pending.putNext([EnginePeer.Id(2)])
        XCTAssertFalse(session.isLockedArchivedPeer(EnginePeer.Id(1)))
        XCTAssertTrue(session.isLockedArchivedPeer(EnginePeer.Id(2)))
    }

    func testUnlockBelongsToTheAccountItWasEnteredOn() {
        let session = ArchiveLockSession.shared
        let account = EnginePeer.Id(5001)
        let other = EnginePeer.Id(5002)
        session.bindPasswordProtection(accountId: 5001, accountPeerId: account, isPasswordConfigured: .single(true))
        XCTAssertFalse(session.isUnlocked(accountPeerId: account))
        session.unlock()
        XCTAssertTrue(session.isUnlocked(accountPeerId: account), "Search inside an open Archive must see its chats")
        XCTAssertFalse(session.isUnlocked(accountPeerId: other), "An unlock does not open another account's Archive")
        session.relock()
        XCTAssertFalse(session.isUnlocked(accountPeerId: account))
        session.bindPasswordProtection(accountId: 5003, isPasswordConfigured: .single(true))
        session.unlock()
        XCTAssertFalse(session.isUnlocked(accountPeerId: account), "A rebind forgets the previous account")
    }
}
