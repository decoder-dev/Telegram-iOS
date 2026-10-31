import Foundation
import XCTest

final class ArchiveSettingsTests: XCTestCase {
    func testLegacyCredentialSurvivesUnrelatedSettingsWrite() throws {
        let data = Data(#"{"isHiddenByDefault":1,"lockPasswordHash":"legacy-test-hash"}"#.utf8)
        let original = try JSONDecoder().decode(ChatArchiveSettings.self, from: data)
        XCTAssertTrue(original.isPasswordConfigured, "Redact before Keychain migration")
        let edited = original.withUpdatedUseBiometrics(true)
        let restored = try JSONDecoder().decode(ChatArchiveSettings.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(restored.legacyLockPasswordHash, "legacy-test-hash")
        XCTAssertTrue(restored.isPasswordConfigured)
    }

    func testSuccessfulMigrationAndRemovalDoNotRestoreLegacyCredential() throws {
        let original = ChatArchiveSettings(isHiddenByDefault: true, hiddenPsaPeerId: nil, legacyLockPasswordHash: "legacy-test-hash")
        let migrated = original.clearingLegacyPasswordHash().withUpdatedIsPasswordConfigured(true)
        let restored = try JSONDecoder().decode(ChatArchiveSettings.self, from: JSONEncoder().encode(migrated))
        XCTAssertNil(restored.legacyLockPasswordHash)
        XCTAssertTrue(restored.isPasswordConfigured)
        let removed = restored.withUpdatedIsPasswordConfigured(false)
        let unlocked = try JSONDecoder().decode(ChatArchiveSettings.self, from: JSONEncoder().encode(removed))
        XCTAssertFalse(unlocked.isPasswordConfigured)
        XCTAssertNil(unlocked.legacyLockPasswordHash)
    }

    func testLockTargetsDefaultToBothAndSurviveEveryOtherWrite() throws {
        let older = try JSONDecoder().decode(ChatArchiveSettings.self, from: Data(#"{"isHiddenByDefault":0,"isPasswordConfigured":1}"#.utf8))
        XCTAssertTrue(older.locksArchive && older.locksSavedMessages, "Settings written before the choice lock both, as they did")
        XCTAssertTrue(older.isArchiveLocked && older.isSavedMessagesLocked)

        let savedOnly = older.withUpdatedLockTargets(archive: false, savedMessages: true)
        XCTAssertFalse(savedOnly.isArchiveLocked)
        XCTAssertTrue(savedOnly.isSavedMessagesLocked)
        for edited in [savedOnly.withUpdatedUseBiometrics(true), savedOnly.withUpdatedPasswordVerifier("v"), savedOnly.clearingLegacyPasswordHash(), savedOnly.withUpdatedIsPasswordConfigured(true), savedOnly.withUpdatedBiometricsDomainState(Data([1]))] {
            XCTAssertFalse(edited.locksArchive, "Another settings write must keep the choice")
            XCTAssertTrue(edited.locksSavedMessages)
        }
        let restored = try JSONDecoder().decode(ChatArchiveSettings.self, from: JSONEncoder().encode(savedOnly))
        XCTAssertFalse(restored.locksArchive)
        XCTAssertTrue(restored.locksSavedMessages)
    }

    func testAtLeastOneTargetStaysLockedAndNothingIsLockedWithoutAPassword() {
        let settings = ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, isPasswordConfigured: true)
        let none = settings.withUpdatedLockTargets(archive: false, savedMessages: false)
        XCTAssertTrue(none.locksArchive, "Asking for neither keeps the Archive locked")
        XCTAssertFalse(none.locksSavedMessages)
        let unprotected = ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil)
        XCTAssertFalse(unprotected.isArchiveLocked)
        XCTAssertFalse(unprotected.isSavedMessagesLocked)
    }
}
