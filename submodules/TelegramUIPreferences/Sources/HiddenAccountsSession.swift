import Foundation
import SwiftSignalKit
import TelegramCore

/// Which accounts are hidden, and by whom: an account with an Archive password (the owner) picks other signed-in
/// accounts to hide behind that password, in its Archive settings. Shared data of the account manager, so every account
/// and the Notification Service Extension read the same answer.
///
/// Account ids are `AccountRecordId` raw values.
public struct HiddenAccountsSettings: Codable, Equatable {
    /// Hidden account → the account whose Archive password opens it.
    public private(set) var owners: [Int64: Int64]

    public static var `default`: HiddenAccountsSettings {
        return HiddenAccountsSettings(owners: [:])
    }

    public init(owners: [Int64: Int64]) {
        self.owners = owners
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let hidden = (try container.decodeIfPresent([Int64].self, forKey: "hidden")) ?? []
        let owners = (try container.decodeIfPresent([Int64].self, forKey: "owners")) ?? []
        var result: [Int64: Int64] = [:]
        for (hiddenId, ownerId) in zip(hidden, owners) where hiddenId != ownerId {
            result[hiddenId] = ownerId
        }
        self.owners = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        let sorted = self.owners.sorted(by: { $0.key < $1.key })
        try container.encode(sorted.map { $0.key }, forKey: "hidden")
        try container.encode(sorted.map { $0.value }, forKey: "owners")
    }

    public func isHidden(_ accountId: Int64) -> Bool {
        return self.owners[accountId] != nil
    }

    public func owner(of accountId: Int64) -> Int64? {
        return self.owners[accountId]
    }

    public func hiddenAccountIds(ownerAccountId: Int64) -> Set<Int64> {
        return Set(self.owners.filter { $0.value == ownerAccountId }.map { $0.key })
    }

    /// Hide `accountId` behind `ownerAccountId`'s password, or show it again (`ownerAccountId == nil`). An account cannot
    /// hide itself, and a hidden account hides nobody: its own Archive could only be opened from inside it.
    public func withHidden(_ accountId: Int64, ownerAccountId: Int64?) -> HiddenAccountsSettings {
        var result = self
        if let ownerAccountId {
            if ownerAccountId == accountId || result.owners[ownerAccountId] != nil {
                return self
            }
            result.owners[accountId] = ownerAccountId
            // Accounts the newly hidden one was hiding become visible: nothing could open them any more.
            for (hiddenId, owner) in result.owners where owner == accountId {
                result.owners[hiddenId] = nil
            }
        } else {
            result.owners[accountId] = nil
        }
        return result
    }

    /// Show everything an owner was hiding: it removed its Archive password.
    public func removingOwner(_ ownerAccountId: Int64) -> HiddenAccountsSettings {
        var result = self
        for (hiddenId, owner) in result.owners where owner == ownerAccountId {
            result.owners[hiddenId] = nil
        }
        return result
    }

    /// Drop entries naming an account that is no longer signed in, as the hidden one or as its owner.
    public func keepingAccounts(_ accountIds: Set<Int64>) -> HiddenAccountsSettings {
        return HiddenAccountsSettings(owners: self.owners.filter { accountIds.contains($0.key) && accountIds.contains($0.value) })
    }
}

/// In-memory state of hidden accounts for this process.
///
/// A hidden account is left out of the account list, the account switcher and every other account's badges until its
/// owner's Settings × 10 reveals it and the owner's Archive password opens it. Like `ArchiveLockSession`, nothing here
/// survives the app going to the background: the reveal and every opened account are dropped, and the app leaves a
/// hidden account it is showing (`SharedAccountContextImpl`).
///
/// Main thread only for the mutators; the readers are locked.
public final class HiddenAccountsSession {
    public static let shared = HiddenAccountsSession()

    public struct State: Equatable {
        /// Hidden account → owner, for owners that are signed in and have an Archive password.
        public var owners: [Int64: Int64] = [:]
        /// False until the settings and every owner's password state have been read once. Until then the checks that
        /// cannot wait read the stored settings themselves.
        public var isResolved: Bool = false
        /// The owner whose Settings × 10 listed its hidden accounts (without their unread counts).
        public var revealedOwnerId: Int64?
        /// Hidden accounts opened with their owner's password since the app last came to the foreground.
        public var unlockedAccountIds: Set<Int64> = []

        public init() {
        }

        public var hiddenAccountIds: Set<Int64> {
            return Set(self.owners.keys)
        }

        public var isRevealed: Bool {
            return self.revealedOwnerId != nil
        }

        /// Whether opening this account needs its owner's password first.
        public func isLocked(accountId: Int64) -> Bool {
            if self.unlockedAccountIds.contains(accountId) {
                return false
            }
            return self.owners[accountId] != nil
        }

        /// How an account appears in the account list. `nil` when it must not appear at all.
        public func listing(accountId: Int64) -> HiddenAccountListing? {
            guard let owner = self.owners[accountId], !self.unlockedAccountIds.contains(accountId) else {
                return .normal
            }
            return self.revealedOwnerId == owner ? .locked : nil
        }
    }

    public enum HiddenAccountListing: Equatable {
        /// Listed as any other account.
        case normal
        /// Listed after its owner's Settings × 10, without its unread count; opening it asks for the owner's password.
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

    /// The hidden accounts in force: the stored settings, limited to owners that are signed in with a password.
    public func updateOwners(_ owners: [Int64: Int64]) {
        self.update { state in
            state.owners = owners
            state.isResolved = true
            if let revealedOwnerId = state.revealedOwnerId, !owners.values.contains(revealedOwnerId) {
                state.revealedOwnerId = nil
            }
        }
    }

    /// Settings × 10 on `ownerAccountId`. Returns false when it hides nothing, so there was nothing to show.
    @discardableResult
    public func reveal(ownerAccountId: Int64) -> Bool {
        var revealed = false
        self.update { state in
            if state.owners.values.contains(ownerAccountId) {
                state.revealedOwnerId = ownerAccountId
                revealed = true
            }
        }
        return revealed
    }

    /// The owner's Archive password was entered for this account.
    public func unlock(accountId: Int64) {
        self.update { state in
            state.unlockedAccountIds.insert(accountId)
        }
    }

    /// The owner's Archive password was entered (its Archive was opened): everything it hides is open too.
    public func unlockAccounts(ownerAccountId: Int64) {
        self.update { state in
            for (hiddenId, owner) in state.owners where owner == ownerAccountId {
                state.unlockedAccountIds.insert(hiddenId)
            }
        }
    }

    /// Hide every hidden account again: on background and on Lock Now.
    public func relock() {
        self.update { state in
            state.revealedOwnerId = nil
            state.unlockedAccountIds = []
        }
    }
}
