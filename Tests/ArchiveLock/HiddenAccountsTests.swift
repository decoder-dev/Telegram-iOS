import Foundation
import XCTest
import SwiftSignalKit

final class HiddenAccountsTests: XCTestCase {
    private let owner: Int64 = 10
    private let second: Int64 = 20
    private let third: Int64 = 30
    private let other: Int64 = 40

    override func setUp() {
        super.setUp()
        HiddenAccountsSession.shared.relock()
        HiddenAccountsSession.shared.updateOwners([:])
    }

    // MARK: settings

    func testOwnerHidesSeveralOtherAccounts() throws {
        let settings = HiddenAccountsSettings.default
            .withHidden(self.second, ownerAccountId: self.owner)
            .withHidden(self.third, ownerAccountId: self.owner)
        XCTAssertTrue(settings.isHidden(self.second))
        XCTAssertTrue(settings.isHidden(self.third))
        XCTAssertFalse(settings.isHidden(self.owner), "The account that hides is never hidden by that")
        XCTAssertEqual(settings.owner(of: self.second), self.owner)
        XCTAssertEqual(settings.hiddenAccountIds(ownerAccountId: self.owner), [self.second, self.third])

        let restored = try JSONDecoder().decode(HiddenAccountsSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
    }

    func testAnAccountCannotHideItselfAndAHiddenAccountHidesNobody() {
        let selfHidden = HiddenAccountsSettings.default.withHidden(self.owner, ownerAccountId: self.owner)
        XCTAssertFalse(selfHidden.isHidden(self.owner))

        let hidden = HiddenAccountsSettings.default.withHidden(self.second, ownerAccountId: self.owner)
        let chained = hidden.withHidden(self.third, ownerAccountId: self.second)
        XCTAssertFalse(chained.isHidden(self.third), "A hidden account's own Archive could only be opened from inside it")

        // Hiding an account that was itself hiding others shows those others: nothing could open them any more.
        let earlier = HiddenAccountsSettings.default.withHidden(self.third, ownerAccountId: self.second)
        let now = earlier.withHidden(self.second, ownerAccountId: self.owner)
        XCTAssertTrue(now.isHidden(self.second))
        XCTAssertFalse(now.isHidden(self.third))
    }

    func testShowingAgainAndRemovingThePasswordAndSigningOut() {
        let settings = HiddenAccountsSettings.default
            .withHidden(self.second, ownerAccountId: self.owner)
            .withHidden(self.third, ownerAccountId: self.owner)
        XCTAssertFalse(settings.withHidden(self.second, ownerAccountId: nil).isHidden(self.second))

        let noPassword = settings.removingOwner(self.owner)
        XCTAssertFalse(noPassword.isHidden(self.second))
        XCTAssertFalse(noPassword.isHidden(self.third))

        let ownerSignedOut = settings.keepingAccounts([self.second, self.third, self.other])
        XCTAssertFalse(ownerSignedOut.isHidden(self.second), "Nothing can open an account whose owner signed out")
        XCTAssertFalse(ownerSignedOut.isHidden(self.third))
    }

    func testOlderOrEmptyDataDecodesAsNothingHidden() throws {
        let settings = try JSONDecoder().decode(HiddenAccountsSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.owners.isEmpty)
    }

    // MARK: session

    func testOnlyTheOwnersSettingsTapsListItsHiddenAccountsAndOnlyItsPasswordOpensThem() {
        let session = HiddenAccountsSession.shared
        session.updateOwners([self.second: self.owner, self.third: self.other])
        var state = session.state
        XCTAssertTrue(state.isResolved)
        XCTAssertNil(state.listing(accountId: self.second), "Not listed before Settings × 10")
        XCTAssertEqual(state.listing(accountId: self.owner), .normal)
        XCTAssertTrue(state.isLocked(accountId: self.second))

        XCTAssertFalse(session.reveal(ownerAccountId: self.third), "An account that hides nothing reveals nothing")
        XCTAssertTrue(session.reveal(ownerAccountId: self.owner))
        state = session.state
        XCTAssertEqual(state.listing(accountId: self.second), .locked, "The owner's taps list it without opening it")
        XCTAssertNil(state.listing(accountId: self.third), "Another owner's hidden account stays out")
        XCTAssertTrue(state.isLocked(accountId: self.second), "Ten taps must not authenticate")

        session.unlock(accountId: self.second)
        state = session.state
        XCTAssertEqual(state.listing(accountId: self.second), .normal)
        XCTAssertFalse(state.isLocked(accountId: self.second))
        XCTAssertTrue(state.isLocked(accountId: self.third))
    }

    func testOpeningTheOwnersArchiveOpensWhatItHides() {
        let session = HiddenAccountsSession.shared
        let anotherOwner: Int64 = 99
        session.updateOwners([self.second: self.owner, self.third: self.owner, self.other: anotherOwner])
        session.unlockAccounts(ownerAccountId: self.owner)
        let state = session.state
        XCTAssertFalse(state.isLocked(accountId: self.second))
        XCTAssertFalse(state.isLocked(accountId: self.third))
        XCTAssertTrue(state.isLocked(accountId: self.other), "Another owner's account needs its own owner")
    }

    func testRelockDropsTheRevealAndEveryOpenedAccount() {
        let session = HiddenAccountsSession.shared
        session.updateOwners([self.second: self.owner])
        session.reveal(ownerAccountId: self.owner)
        session.unlock(accountId: self.second)
        session.relock()
        let state = session.state
        XCTAssertFalse(state.isRevealed)
        XCTAssertTrue(state.unlockedAccountIds.isEmpty)
        XCTAssertTrue(state.isLocked(accountId: self.second))
        XCTAssertNil(state.listing(accountId: self.second))
    }

    func testAnOwnerThatLostItsPasswordRevealsNothing() {
        let session = HiddenAccountsSession.shared
        session.updateOwners([self.second: self.owner])
        session.reveal(ownerAccountId: self.owner)
        // SharedAccountContextImpl leaves out the entries of owners without a password.
        session.updateOwners([:])
        let state = session.state
        XCTAssertFalse(state.isRevealed)
        XCTAssertFalse(state.isLocked(accountId: self.second))
        XCTAssertEqual(state.listing(accountId: self.second), .normal)
    }

    func testStateSignalDeliversChanges() {
        let session = HiddenAccountsSession.shared
        var received: [HiddenAccountsSession.State] = []
        let disposable = session.stateSignal.start(next: { received.append($0) })
        session.updateOwners([self.second: self.owner])
        session.reveal(ownerAccountId: self.owner)
        disposable.dispose()
        XCTAssertEqual(received.last?.revealedOwnerId, self.owner)
        XCTAssertEqual(received.last?.hiddenAccountIds, [self.second])
    }
}
