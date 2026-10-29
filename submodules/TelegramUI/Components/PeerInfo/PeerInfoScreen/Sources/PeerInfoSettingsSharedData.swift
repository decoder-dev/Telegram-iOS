import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import SettingsUI

/// What the Settings screen loads from the server (notification exceptions, privacy, archived sticker packs, the
/// two-step configuration, the session list), held once per account and shared by every Settings screen its root
/// controller creates.
///
/// The tab's Settings screen loads this once. With the tab bar hidden each visit pushes a new Settings screen, and each
/// loaded it all again: a device log shows about 455 notification exception loads in a day. Sharing the promises
/// also keeps the screens consistent, since the privacy and exception editors update the promise the root controller
/// hands them (`getPrivacySettings()`, `getNotificationExceptions()`), which is now the same one for every screen.
///
/// Main thread only, like the screens that use it.
public final class PeerInfoSettingsSharedData {
    let notificationExceptions = Promise<NotificationExceptionsList?>()
    let privacySettings = Promise<AccountPrivacySettings?>()
    let archivedPacks = Promise<[ArchivedStickerPackItem]?>()
    let twoStepAccessConfiguration = Promise<TwoStepVerificationAccessConfiguration?>(nil)
    let activeSessionsContextAndCount = Promise<(ActiveSessionsContext, Int, WebSessionsContext)?>(nil)

    private var didBeginLoading = false
    private var didBeginSessions = false

    public init() {
    }

    /// True for the first screen to ask: that screen starts the loads, the others share them.
    func beginLoading() -> Bool {
        if self.didBeginLoading {
            return false
        }
        self.didBeginLoading = true
        return true
    }

    /// True for the first screen to ask: that screen starts the session list, the others share it.
    func beginSessions() -> Bool {
        if self.didBeginSessions {
            return false
        }
        self.didBeginSessions = true
        return true
    }
}
