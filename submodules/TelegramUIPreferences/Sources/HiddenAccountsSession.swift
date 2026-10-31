import Foundation
import SwiftSignalKit
import TelegramCore

/// In-memory state of hidden accounts (`ChatArchiveSettings.isAccountHidden`) for this process.
///
/// A hidden account is left out of the account list, the account switcher and every other account's badges until
/// Settings × 10 reveals it and its own Archive password opens it. Like `ArchiveLockSession`, nothing here survives the
/// app going to the background: the reveal and every opened account are dropped, and the app leaves a hidden account
/// it is showing (`SharedAccountContextImpl`).
///
/// Account ids are `AccountRecordId` raw values. Main thread only for the mutators; the readers are locked.
public final class HiddenAccountsSession {
    public static let shared = HiddenAccountsSession()

    public struct State: Equatable {
        /// Accounts whose settings hide them.
        public var hiddenAccountIds: Set<Int64> = []
        /// False until every active account's settings have been read once. Until then any account may be hidden, so
        /// the checks that cannot wait fail closed (`isLocked`).
        public var isResolved: Bool = false
        /// Settings × 10: hidden accounts are listed (without their unread counts) and ask for their password when opened.
        public var isRevealed: Bool = false
        /// Hidden accounts opened with their password since the app last came to the foreground.
        public var unlockedAccountIds: Set<Int64> = []

        public init() {
        }

        /// Whether opening this account needs its password first.
        public func isLocked(accountId: Int64) -> Bool {
            if self.unlockedAccountIds.contains(accountId) {
                return false
            }
            return self.hiddenAccountIds.contains(accountId)
        }

        /// How a hidden account appears in the account list. `nil` when it must not appear at all.
        public func listing(accountId: Int64, isHidden: Bool) -> HiddenAccountListing? {
            if !isHidden || self.unlockedAccountIds.contains(accountId) {
                return .normal
            }
            return self.isRevealed ? .locked : nil
        }
    }

    public enum HiddenAccountListing: Equatable {
        /// Listed as any other account.
        case normal
        /// Listed after Settings × 10, without its unread count; opening it asks for its password.
        case locked
    }

    private let lock = NSLock()
    private var stateValue = State()
    private let statePromise = ValuePromise<State>(State(), ignoreRepeated: true)

    private init() {
    }

    public var state: State {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.stateValue
    }

    public var stateSignal: Signal<State, NoError> {
        return self.statePromise.get()
    }

    private func update(_ f: (inout State) -> Void) {
        self.lock.lock()
        var state = self.stateValue
        f(&state)
        let changed = state != self.stateValue
        self.stateValue = state
        self.lock.unlock()
        if changed {
            self.statePromise.set(state)
        }
    }

    /// The accounts whose settings hide them, read from every active account.
    public func updateHiddenAccountIds(_ ids: Set<Int64>) {
        self.update { state in
            state.hiddenAccountIds = ids
            state.isResolved = true
            // `unlockedAccountIds` is left alone: hiding the account on screen opens it first, before its own setting
            // has reached this set, and dropping it here would throw the user out of the account they just hid.
        }
    }

    /// Settings × 10. Returns false when no account other than `primaryAccountId` is hidden, so there was nothing to show.
    @discardableResult
    public func reveal(primaryAccountId: Int64?) -> Bool {
        var revealed = false
        self.update { state in
            var others = state.hiddenAccountIds
            if let primaryAccountId {
                others.remove(primaryAccountId)
            }
            if !others.isEmpty {
                state.isRevealed = true
                revealed = true
            }
        }
        return revealed
    }

    /// The account's own Archive password was entered.
    public func unlock(accountId: Int64) {
        self.update { state in
            state.unlockedAccountIds.insert(accountId)
        }
    }

    /// Hide every hidden account again: on background and on Lock Now.
    public func relock() {
        self.update { state in
            state.isRevealed = false
            state.unlockedAccountIds = []
        }
    }
}
