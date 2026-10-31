import Foundation
import XCTest
import SwiftSignalKit

final class HiddenAccountsTests: XCTestCase {
    private let visible: Int64 = 10
    private let hidden: Int64 = 20

    override func setUp() {
        super.setUp()
        HiddenAccountsSession.shared.relock()
        HiddenAccountsSession.shared.updateHiddenAccountIds([])
    }

    func testHiddenAccountIsLeftOutUntilRevealedAndListedLockedUntilItsPassword() {
        let session = HiddenAccountsSession.shared
        session.updateHiddenAccountIds([self.hidden])
        var state = session.state
        XCTAssertTrue(state.isResolved)
        XCTAssertNil(state.listing(accountId: self.hidden, isHidden: true), "A hidden account is not listed before Settings × 10")
        XCTAssertEqual(state.listing(accountId: self.visible, isHidden: false), .normal)
        XCTAssertTrue(state.isLocked(accountId: self.hidden))
        XCTAssertFalse(state.isLocked(accountId: self.visible))

        XCTAssertTrue(session.reveal(primaryAccountId: self.visible))
        state = session.state
        XCTAssertEqual(state.listing(accountId: self.hidden, isHidden: true), .locked, "Settings × 10 lists it without opening it")
        XCTAssertTrue(state.isLocked(accountId: self.hidden), "Ten taps must not authenticate")

        session.unlock(accountId: self.hidden)
        state = session.state
        XCTAssertEqual(state.listing(accountId: self.hidden, isHidden: true), .normal)
        XCTAssertFalse(state.isLocked(accountId: self.hidden))
    }

    func testRelockDropsTheRevealAndEveryOpenedAccount() {
        let session = HiddenAccountsSession.shared
        session.updateHiddenAccountIds([self.hidden])
        session.reveal(primaryAccountId: self.visible)
        session.unlock(accountId: self.hidden)
        session.relock()
        let state = session.state
        XCTAssertFalse(state.isRevealed)
        XCTAssertTrue(state.unlockedAccountIds.isEmpty)
        XCTAssertTrue(state.isLocked(accountId: self.hidden))
        XCTAssertNil(state.listing(accountId: self.hidden, isHidden: true))
    }

    func testTenTapsRevealNothingWhenOnlyTheAccountOnScreenIsHidden() {
        let session = HiddenAccountsSession.shared
        session.updateHiddenAccountIds([self.visible])
        XCTAssertFalse(session.reveal(primaryAccountId: self.visible), "Nothing else is hidden, so there is nothing to show")
        XCTAssertFalse(session.state.isRevealed)
    }

    func testHidingTheAccountOnScreenKeepsItOpenUntilTheNextRelock() {
        let session = HiddenAccountsSession.shared
        // The toggle opens the account first; its own setting reaches the hidden set afterwards.
        session.unlock(accountId: self.visible)
        session.updateHiddenAccountIds([self.visible])
        XCTAssertFalse(session.state.isLocked(accountId: self.visible), "Hiding the account on screen must not throw the user out of it")
        session.relock()
        XCTAssertTrue(session.state.isLocked(accountId: self.visible))
    }

    func testStateSignalDeliversChanges() {
        let session = HiddenAccountsSession.shared
        var received: [HiddenAccountsSession.State] = []
        let disposable = session.stateSignal.start(next: { received.append($0) })
        session.updateHiddenAccountIds([self.hidden])
        session.reveal(primaryAccountId: self.visible)
        disposable.dispose()
        XCTAssertEqual(received.last?.isRevealed, true)
        XCTAssertEqual(received.last?.hiddenAccountIds, [self.hidden])
    }

    func testHideFlagRoundTripsAndNeedsAPassword() throws {
        let protected = ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, isPasswordConfigured: true)
        let hiddenSettings = protected.withUpdatedHidesAccount(true)
        XCTAssertTrue(hiddenSettings.isAccountHidden)
        let restored = try JSONDecoder().decode(ChatArchiveSettings.self, from: JSONEncoder().encode(hiddenSettings))
        XCTAssertTrue(restored.hidesAccount)
        XCTAssertTrue(restored.isAccountHidden)
        // Every other settings write keeps the flag.
        XCTAssertTrue(restored.withUpdatedUseBiometrics(true).isAccountHidden)
        XCTAssertTrue(restored.withUpdatedPasswordVerifier("verifier").isAccountHidden)
        XCTAssertTrue(restored.clearingLegacyPasswordHash().isAccountHidden)

        let unprotected = ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil)
        XCTAssertFalse(unprotected.withUpdatedHidesAccount(true).isAccountHidden, "Without a password there is nothing to open it with")
    }

    func testRemovingThePasswordShowsTheAccountAgain() throws {
        let hiddenSettings = ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, isPasswordConfigured: true).withUpdatedHidesAccount(true)
        let removed = hiddenSettings.withUpdatedIsPasswordConfigured(false)
        XCTAssertFalse(removed.hidesAccount)
        XCTAssertFalse(removed.isAccountHidden)
        let reprotected = removed.withUpdatedIsPasswordConfigured(true)
        XCTAssertFalse(reprotected.isAccountHidden, "Setting a new password must not hide the account again by itself")
    }

    func testOlderSettingsDecodeAsNotHidden() throws {
        let data = Data(#"{"isHiddenByDefault":0,"isPasswordConfigured":1}"#.utf8)
        let settings = try JSONDecoder().decode(ChatArchiveSettings.self, from: data)
        XCTAssertFalse(settings.hidesAccount)
        XCTAssertFalse(settings.isAccountHidden)
    }
}
