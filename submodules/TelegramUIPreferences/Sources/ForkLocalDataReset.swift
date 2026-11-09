import Foundation
import SwiftSignalKit
import TelegramCore

/// The two "on next launch" switches of the app's page in iOS Settings (Telegram/Telegram-iOS/Settings.bundle), also
/// offered in Extras › About. The keys are the ones in the bundle's Root.plist.
///
/// What goes, per account, under `<root>/account-<id>/postbox`:
/// - cache: `media`, the downloaded files and their thumbnails. Everything there is downloaded again when needed.
/// - message database: `db`, the local copy of chats and messages. The account's auth keys are kept in the account
///   record (`accounts-metadata`, never touched here) and are written back into the new database on start, so the
///   account stays signed in and everything is loaded again from the server. Secret chats live only on the device and
///   are lost. Accounts whose record has no such copy keep their database.
public enum ForkLocalDataReset {
    public static let resetCacheKey = "BananaResetCacheOnNextLaunch"
    public static let resetDatabaseKey = "BananaResetDatabaseOnNextLaunch"

    public static var isCacheResetRequested: Bool {
        get { return UserDefaults.standard.bool(forKey: resetCacheKey) }
        set { UserDefaults.standard.set(newValue, forKey: resetCacheKey) }
    }

    public static var isDatabaseResetRequested: Bool {
        get { return UserDefaults.standard.bool(forKey: resetDatabaseKey) }
        set { UserDefaults.standard.set(newValue, forKey: resetDatabaseKey) }
    }

    /// Has to complete before any account's postbox is opened. Puts one value and completes.
    public static func performIfRequested(accountManager: AccountManager<TelegramAccountManagerTypes>, rootPath: String) -> Signal<Void, NoError> {
        let resetCache = self.isCacheResetRequested
        let resetDatabase = self.isDatabaseResetRequested
        if !resetCache && !resetDatabase {
            return .single(Void())
        }
        // Cleared before anything is deleted, so a reset that crashes halfway is not repeated on every launch.
        self.isCacheResetRequested = false
        self.isDatabaseResetRequested = false

        return accountManager.transaction { transaction -> [(id: AccountRecordId, hasKeys: Bool)] in
            return transaction.getRecords().map { record -> (id: AccountRecordId, hasKeys: Bool) in
                // The attribute can be there with its data missing (it is decoded leniently); then nothing could put
                // the auth keys back, so that account's database is left alone.
                let hasKeys = record.attributes.contains(where: { attribute in
                    if case let .backupData(backup) = attribute {
                        return backup.data != nil
                    } else {
                        return false
                    }
                })
                return (id: record.id, hasKeys: hasKeys)
            }
        }
        |> map { records -> Void in
            for record in records {
                let postboxPath = rootPath + "/" + accountRecordIdPathName(record.id) + "/postbox"
                if resetCache {
                    let _ = try? FileManager.default.removeItem(atPath: postboxPath + "/media")
                }
                if resetDatabase && record.hasKeys {
                    let _ = try? FileManager.default.removeItem(atPath: postboxPath + "/db")
                }
            }
            return Void()
        }
    }
}
