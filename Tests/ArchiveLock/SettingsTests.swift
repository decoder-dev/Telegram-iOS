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
}
