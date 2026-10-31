import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox

public struct ChatArchiveSettings: Equatable, Codable {
    public var isHiddenByDefault: Bool
    public var hiddenPsaPeerId: EnginePeer.Id?
    /// Retained until migration into Keychain succeeds.
    public var legacyLockPasswordHash: String?
    /// Per-account: allow Face ID/Touch ID as a convenience unlock alongside the password.
    /// Only meaningful while a password is set; forced back to `false` when the password is removed.
    public var useBiometrics: Bool
    /// Plain mirror of "does this account currently have an Archive password set" — kept in
    /// sync with the Keychain by ArchiveLockHelpers. Exists so processes that only have this
    /// account's Postbox (no Keychain access group shared with the main app, e.g. the
    /// Notification Service Extension) can still decide whether to redact a locked-archived
    /// peer's notifications, without needing the password hash itself.
    public var isPasswordConfigured: Bool
    /// Copy of the salted PBKDF2 verifier (never the password) kept next to the account's data. The Keychain item is
    /// bound to the app's signing identity, so a re-signed or re-installed sideload build can no longer read it; this copy
    /// lets the Keychain be restored instead of silently leaving the Archive unprotected or unopenable.
    public var passwordVerifier: String?
    /// Biometric enrollment (`LAContext.evaluatedPolicyDomainState`) at the time Face ID / Touch ID unlock was trusted.
    /// A different enrollment (a newly added face or finger) must not open the Archive.
    public var biometricsDomainState: Data?
    /// What the password locks: the Archive folder and its chats, and Saved Messages. At least one of the two; both by
    /// default, which is how the lock always behaved.
    public var locksArchive: Bool
    public var locksSavedMessages: Bool

    /// Whether the Archive folder and its chats are locked: a password is set and it covers them.
    public var isArchiveLocked: Bool {
        return self.isPasswordConfigured && self.locksArchive
    }

    /// Whether Saved Messages is locked: a password is set and it covers it.
    public var isSavedMessagesLocked: Bool {
        return self.isPasswordConfigured && self.locksSavedMessages
    }

    public static var `default`: ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, legacyLockPasswordHash: nil, useBiometrics: false, isPasswordConfigured: false)
    }

    public init(isHiddenByDefault: Bool, hiddenPsaPeerId: EnginePeer.Id?, legacyLockPasswordHash: String? = nil, useBiometrics: Bool = false, isPasswordConfigured: Bool = false, passwordVerifier: String? = nil, biometricsDomainState: Data? = nil, locksArchive: Bool = true, locksSavedMessages: Bool = true) {
        self.isHiddenByDefault = isHiddenByDefault
        self.hiddenPsaPeerId = hiddenPsaPeerId
        self.legacyLockPasswordHash = legacyLockPasswordHash
        self.useBiometrics = useBiometrics
        self.isPasswordConfigured = isPasswordConfigured
        self.passwordVerifier = passwordVerifier
        self.biometricsDomainState = biometricsDomainState
        self.locksArchive = locksArchive || !locksSavedMessages
        self.locksSavedMessages = locksSavedMessages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.isHiddenByDefault = (try container.decode(Int32.self, forKey: "isHiddenByDefault")) != 0
        self.hiddenPsaPeerId = (try container.decodeIfPresent(Int64.self, forKey: "hiddenPsaPeerId")).flatMap(EnginePeer.Id.init)
        if let hash = try container.decodeIfPresent(String.self, forKey: "lockPasswordHash"), !hash.isEmpty {
            self.legacyLockPasswordHash = hash
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: "lockPassword"), !legacy.isEmpty {
            self.legacyLockPasswordHash = archivePasswordHash(legacy)
        } else {
            self.legacyLockPasswordHash = nil
        }
        self.useBiometrics = ((try container.decodeIfPresent(Int32.self, forKey: "useBiometrics")) ?? 0) != 0
        self.isPasswordConfigured = ((try container.decodeIfPresent(Int32.self, forKey: "isPasswordConfigured")) ?? 0) != 0
        if let verifier = try container.decodeIfPresent(String.self, forKey: "passwordVerifier"), !verifier.isEmpty {
            self.passwordVerifier = verifier
        } else {
            self.passwordVerifier = nil
        }
        self.biometricsDomainState = try container.decodeIfPresent(Data.self, forKey: "biometricsDomainState")
        // Absent in settings written before the choice existed: both, as the lock behaved then.
        let locksSavedMessages = ((try container.decodeIfPresent(Int32.self, forKey: "locksSavedMessages")) ?? 1) != 0
        let locksArchive = ((try container.decodeIfPresent(Int32.self, forKey: "locksArchive")) ?? 1) != 0
        self.locksSavedMessages = locksSavedMessages
        self.locksArchive = locksArchive || !locksSavedMessages
        // Extensions must redact before the main app has migrated the legacy credential.
        self.isPasswordConfigured = self.isPasswordConfigured || self.legacyLockPasswordHash != nil || self.passwordVerifier != nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.isHiddenByDefault ? 1 : 0) as Int32, forKey: "isHiddenByDefault")
        if let hiddenPsaPeerId = self.hiddenPsaPeerId {
            try container.encode(hiddenPsaPeerId.toInt64(), forKey: "hiddenPsaPeerId")
        } else {
            try container.encodeNil(forKey: "hiddenPsaPeerId")
        }
        // Only clearingLegacyPasswordHash after successful migration may remove this copy.
        try container.encodeIfPresent(self.legacyLockPasswordHash, forKey: "lockPasswordHash")
        try container.encodeNil(forKey: "lockPassword")
        try container.encode((self.useBiometrics ? 1 : 0) as Int32, forKey: "useBiometrics")
        try container.encode((self.isPasswordConfigured ? 1 : 0) as Int32, forKey: "isPasswordConfigured")
        try container.encodeIfPresent(self.passwordVerifier, forKey: "passwordVerifier")
        try container.encodeIfPresent(self.biometricsDomainState, forKey: "biometricsDomainState")
        try container.encode((self.locksArchive ? 1 : 0) as Int32, forKey: "locksArchive")
        try container.encode((self.locksSavedMessages ? 1 : 0) as Int32, forKey: "locksSavedMessages")
    }

    public func clearingLegacyPasswordHash() -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: nil, useBiometrics: self.useBiometrics, isPasswordConfigured: self.isPasswordConfigured, passwordVerifier: self.passwordVerifier, biometricsDomainState: self.biometricsDomainState, locksArchive: self.locksArchive, locksSavedMessages: self.locksSavedMessages)
    }

    public func withUpdatedUseBiometrics(_ useBiometrics: Bool) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: self.legacyLockPasswordHash, useBiometrics: useBiometrics, isPasswordConfigured: self.isPasswordConfigured, passwordVerifier: self.passwordVerifier, biometricsDomainState: self.biometricsDomainState, locksArchive: self.locksArchive, locksSavedMessages: self.locksSavedMessages)
    }

    public func withUpdatedIsPasswordConfigured(_ isPasswordConfigured: Bool) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: self.legacyLockPasswordHash, useBiometrics: isPasswordConfigured ? self.useBiometrics : false, isPasswordConfigured: isPasswordConfigured, passwordVerifier: isPasswordConfigured ? self.passwordVerifier : nil, biometricsDomainState: isPasswordConfigured ? self.biometricsDomainState : nil, locksArchive: self.locksArchive, locksSavedMessages: self.locksSavedMessages)
    }

    /// Change what the password locks. At least one stays locked: asking for neither keeps the Archive.
    public func withUpdatedLockTargets(archive: Bool, savedMessages: Bool) -> ChatArchiveSettings {
        var result = self
        result.locksSavedMessages = savedMessages
        result.locksArchive = archive || !savedMessages
        return result
    }

    public func withUpdatedBiometricsDomainState(_ biometricsDomainState: Data?) -> ChatArchiveSettings {
        var result = self
        result.biometricsDomainState = biometricsDomainState
        return result
    }

    public func withUpdatedPasswordVerifier(_ passwordVerifier: String?) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: self.legacyLockPasswordHash, useBiometrics: self.useBiometrics, isPasswordConfigured: self.isPasswordConfigured || passwordVerifier != nil, passwordVerifier: passwordVerifier, biometricsDomainState: self.biometricsDomainState, locksArchive: self.locksArchive, locksSavedMessages: self.locksSavedMessages)
    }
}

/// How the secret Archive folder is presented in the main chat list.
/// `collapsing` keeps the row for one official spring hide (0.4s), then `omitted`.
public enum ArchiveFolderPresentation: Equatable {
    case omitted
    case expanded
    case collapsing
}

/// In-memory session state for the secret Archive:
/// - `isRevealed`: folder row visible (10 taps on Settings).
/// - `isUnlocked`: password accepted for this process.
/// Both clear on background / Lock Now / after unarchiving a chat / when leaving the Archive
/// folder back to the main chat list. The session does **not** stay open after that leave: an
/// attacker who finds the phone still in the foreground must pass the password again.
///
/// Revealing the folder (Settings × 10) must not leak contents. While a password is set and the
/// session is still locked, the Archive row is title-only — no peer names, last-message preview,
/// unread counts, or stories.
///
/// Both gates only exist to protect a password that is actually set. An account with no Archive
/// password has a stock Telegram Archive — always in the chat list, opened without a prompt — so
/// every gate here reads through `passwordConfigured` rather than the raw flag.
public final class ArchiveLockSession {
    public static let shared = ArchiveLockSession()
    
    /// Match ChatListItem's official archive hide spring (`duration: 0.4`).
    private static let collapseAnimationDuration: Double = 0.4
    
    private let lock = NSLock()
    private var unlocked = false
    private var revealed = false
    /// Whether the currently bound account has an Archive password. Pushed in by
    /// `bindPasswordProtection`; false until the first push, which is the fail-closed direction
    /// (the folder stays omitted) rather than the leaky one.
    private var passwordConfigured = false
    /// False until the bound account's stored password state has actually been read once. The
    /// first value is the account's existing state, not a change the user just made, so it must
    /// not play the hide animation — a protected account has to start out omitted, not collapse
    /// into omitted while the chat list is still appearing.
    private var passwordStateResolved = false
    private var passwordBindingAccountId: Int64?
    /// The bound account's peer id, for checks that only know the account from its Postbox (`archiveSearchShouldHide`).
    private var passwordBindingAccountPeerId: EnginePeer.Id?
    private var passwordDisposable: Disposable?
    private var muteSweepAccountIds = Set<Int64>()
    private var keepArchivedAlignAccountIds = Set<Int64>()
    private var backgroundDisposable: Disposable?
    private var lockedPeerIdsBindingAccountId: Int64?
    private var lockedPeerIdsDisposable: Disposable?
    private var lockedPeerIds = Set<EnginePeer.Id>()
    /// Whether the bound account's password covers Saved Messages. True until the first value (fail closed: its row in
    /// Settings stays hidden rather than flashing in).
    private var savedMessagesLocked = true
    private var savedMessagesBindingAccountId: Int64?
    private var savedMessagesDisposable: Disposable?
    private let savedMessagesListedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    private var lockedPeerIdsResolved = false
    /// App-switcher cover / foreground cleanup. Looked up at fire time so they can be
    /// registered after `bindBackgroundRelock` (first-wins) has already claimed the slot.
    private var willRelockHandlerValue: (() -> Void)?
    private var didBecomeActiveHandlerValue: (() -> Void)?
    /// >0 while Archive biometric unlock is in progress. Face ID/Touch ID resigns active and
    /// would otherwise `relock()` mid-prompt (clear reveal + schedule dismiss of the folder
    /// we are about to open).
    private var suppressBackgroundRelockCount: Int = 0
    private var collapseGeneration: Int = 0
    private var authorizationGenerationValue: UInt64 = 0
    private let relockedPipe = ValuePipe<Void>()
    private let revealedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    private let unlockedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    private let folderPresentationPromise = ValuePromise<ArchiveFolderPresentation>(.omitted, ignoreRepeated: true)
    
    private init() {}

    /// Invalidates outstanding password/biometric prompts on relock or account change.
    public var authorizationGeneration: UInt64 {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.authorizationGenerationValue
    }
    
    public var isUnlocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.unlocked
    }

    /// Whether this account's Archive is open right now. False for every account but the bound one: an unlock belongs
    /// to the account it was entered on.
    public func isUnlocked(accountPeerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.unlocked && self.passwordBindingAccountPeerId == accountPeerId
    }
    
    /// Whether the Archive folder may appear in the main chat list. With no password there is
    /// nothing to hide, so the folder is always available and the 10-tap gesture is a no-op.
    public var isRevealed: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return !self.passwordConfigured || self.revealed
    }
    
    /// Whether the bound account's password covers Saved Messages.
    public var isSavedMessagesLocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.savedMessagesLocked
    }

    /// Whether Saved Messages is listed in Settings: it is not locked, or Settings × 10 revealed it (opening it still asks
    /// for the password).
    public var isSavedMessagesListed: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return !self.savedMessagesLocked || self.revealed
    }

    public var savedMessagesListedSignal: Signal<Bool, NoError> {
        return self.savedMessagesListedPromise.get()
    }

    private func updateSavedMessagesListed() {
        self.savedMessagesListedPromise.set(self.isSavedMessagesListed)
    }

    /// Whether the currently bound account's Archive folder is locked (`isPasswordConfigured` is true only when the
    /// password covers the Archive: `bindPasswordProtection` is fed `archiveFolderLockSignal`).
    public var isPasswordConfigured: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.passwordConfigured
    }
    
    /// Folder row may be visible (Settings × 10) while still locked; the row must then be
    /// title-only so last-message / peers / unread / stories cannot leak before the password.
    public var hidesFolderRowContents: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.passwordConfigured && !self.unlocked
    }
    
    /// Whether the lock is in force at all. `unlocked` is the belt to `passwordConfigured`'s braces:
    /// it can only be set by a password flow, and it is cleared when the password is removed, so it
    /// still reads true in the brief window after launch before the stored password state arrives.
    public var isLockActive: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.passwordConfigured || self.unlocked
    }
    
    /// Fires whenever the session is re-locked (Lock Now / background / unarchive / leaving Archive).
    public var relockedSignal: Signal<Void, NoError> {
        return self.relockedPipe.signal()
    }
    
    /// Current reveal flag (updates when Settings 10-tap reveals or when relocked).
    public var revealedSignal: Signal<Bool, NoError> {
        return self.revealedPromise.get()
    }
    
    /// Current unlock flag. Drives the main chat-list Archive row so it stays title-only
    /// until the password is accepted, then can show previews again.
    public var unlockedSignal: Signal<Bool, NoError> {
        return self.unlockedPromise.get()
    }
    
    /// List presentation including the transient `collapsing` auto-close phase.
    public var folderPresentationSignal: Signal<ArchiveFolderPresentation, NoError> {
        return self.folderPresentationPromise.get()
    }
    
    public func unlock() {
        self.lock.lock()
        self.unlocked = true
        self.lock.unlock()
        self.unlockedPromise.set(true)
    }
    
    /// Show the Archive folder (Settings tab × 10). Does not skip the password.
    public func reveal() {
        var changed = false
        self.lock.lock()
        self.collapseGeneration &+= 1
        if !self.revealed {
            self.revealed = true
            changed = true
        }
        self.lock.unlock()
        if changed {
            self.revealedPromise.set(true)
            self.folderPresentationPromise.set(.expanded)
        } else {
            // Cancel a mid-collapse omit if Settings is tapped again.
            self.folderPresentationPromise.set(.expanded)
        }
        self.updateSavedMessagesListed()
    }
    
    public func relock() {
        // With no password there is no lock to re-apply, and re-locking has side effects the
        // stock Archive must not get: it pops an open Archive screen and hides the folder row. A Settings × 10 reveal of
        // a locked Saved Messages alone (the Archive itself not locked) is still taken back.
        self.lock.lock()
        let revealedOnly = self.revealed
        self.lock.unlock()
        guard self.isLockActive || revealedOnly else {
            return
        }
        var shouldNotifyRelock = false
        var shouldNotifyReveal = false
        var collapseGeneration = 0
        self.lock.lock()
        self.authorizationGenerationValue &+= 1
        if self.unlocked {
            self.unlocked = false
            shouldNotifyRelock = true
        }
        if self.revealed {
            self.revealed = false
            shouldNotifyReveal = true
            self.collapseGeneration &+= 1
            collapseGeneration = self.collapseGeneration
        }
        self.lock.unlock()
        if shouldNotifyReveal {
            self.revealedPromise.set(false)
            self.beginFolderCollapse(generation: collapseGeneration)
        }
        if shouldNotifyRelock {
            self.unlockedPromise.set(false)
        }
        if shouldNotifyRelock || shouldNotifyReveal {
            self.relockedPipe.putNext(Void())
        }
        self.updateSavedMessagesListed()
    }
    
    /// Keep the folder row briefly so ChatList can play the official spring collapse, then omit it
    /// so pull-to-reveal stays unavailable while locked. Must be called without holding `lock`;
    /// `generation` is the value `collapseGeneration` was bumped to by the caller, so a reveal that
    /// lands mid-collapse cancels the trailing omit instead of racing it.
    private func beginFolderCollapse(generation: Int) {
        self.folderPresentationPromise.set(.collapsing)
        Queue.mainQueue().after(ArchiveLockSession.collapseAnimationDuration, { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            let stillCurrent = self.collapseGeneration == generation && !self.revealed
            self.lock.unlock()
            if stillCurrent {
                self.folderPresentationPromise.set(.omitted)
            }
        })
    }
    
    /// Tracks whether the bound account has an Archive password.
    ///
    /// `accountId` is the account *record* id rather than the peer id: logging out and back into
    /// the same account produces a new record against a new postbox, and keying on the peer id
    /// would keep the subscription to the discarded one and freeze the flag at its last value.
    ///
    /// The flag gates every lock behaviour, so it must never be left describing a previous
    /// account: binding for a different account replaces the existing subscription rather than
    /// adding to it, and a late value from the superseded one is dropped by the id check in
    /// `updatePasswordConfigured`.
    public func bindPasswordProtection(accountId: Int64, accountPeerId: EnginePeer.Id? = nil, isPasswordConfigured: Signal<Bool, NoError>) {
        self.lock.lock()
        if self.passwordBindingAccountId == accountId {
            self.lock.unlock()
            return
        }
        self.passwordBindingAccountPeerId = accountPeerId
        let previousDisposable = self.passwordDisposable
        // Claim the slot with a placeholder before subscribing, so a second caller for this same
        // account takes the early return above instead of starting a duplicate subscription.
        self.passwordBindingAccountId = accountId
        self.passwordDisposable = EmptyDisposable
        self.passwordStateResolved = false
        self.authorizationGenerationValue &+= 1
        // A session authenticated for another account must never authorize this one.
        self.passwordConfigured = true
        self.unlocked = false
        self.revealed = false
        self.collapseGeneration &+= 1
        self.lock.unlock()
        self.unlockedPromise.set(false)
        self.revealedPromise.set(false)
        self.folderPresentationPromise.set(.omitted)
        self.updateSavedMessagesListed()
        previousDisposable?.dispose()
        
        let disposable = (isPasswordConfigured
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            self?.updatePasswordConfigured(value, accountId: accountId)
        })
        
        var isObsolete = false
        self.lock.lock()
        if self.passwordBindingAccountId == accountId {
            self.passwordDisposable = disposable
        } else {
            isObsolete = true
        }
        self.lock.unlock()
        if isObsolete {
            disposable.dispose()
        }
    }
    
    private func updatePasswordConfigured(_ value: Bool, accountId: Int64) {
        var collapseGeneration = 0
        var shouldCollapseFolder = false
        var shouldClearUnlocked = false
        self.lock.lock()
        guard self.passwordBindingAccountId == accountId else {
            self.lock.unlock()
            return
        }
        let wasResolved = self.passwordStateResolved
        self.passwordStateResolved = true
        let didChange = self.passwordConfigured != value
        self.passwordConfigured = value
        if didChange, !value {
            // The password is gone, so nothing is unlocked any more. Leaving the flag set would
            // keep `isLockActive` true and re-lock a now-stock Archive on the next background.
            self.unlocked = false
            shouldClearUnlocked = true
        }
        if didChange, value {
            // The folder was on screen unconditionally while the account was unprotected, and any
            // reveal earned back then belongs to that unprotected state — drop it so the freshly
            // protected Archive starts hidden behind the 10-tap gesture again.
            self.revealed = false
            self.collapseGeneration &+= 1
            collapseGeneration = self.collapseGeneration
            // Only a password the user just set hides a folder that was visible a moment ago. The
            // first read of an already-protected account has nothing to hide, and animating there
            // would flash the row on screen at launch.
            shouldCollapseFolder = wasResolved
        }
        let effectiveRevealed = !value || self.revealed
        self.lock.unlock()
        // `unlocked` is deliberately left alone when a password is *set*: `setArchivePassword`
        // unlocks the session as part of the same flow, and this push lands after it.
        self.revealedPromise.set(effectiveRevealed)
        self.updateSavedMessagesListed()
        if shouldClearUnlocked {
            self.unlockedPromise.set(false)
        }
        if shouldCollapseFolder {
            self.beginFolderCollapse(generation: collapseGeneration)
        }
    }
    
    /// Returns true the first time per account in this process; used to mute existing archived chats once.
    public func claimMuteSweep(accountPeerId: EnginePeer.Id) -> Bool {
        let id = accountPeerId.toInt64()
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.muteSweepAccountIds.contains(id) {
            return false
        }
        self.muteSweepAccountIds.insert(id)
        return true
    }
    
    /// Returns true the first time per account in this process; used to align keepArchivedUnmuted with force-mute.
    public func claimKeepArchivedAlign(accountPeerId: EnginePeer.Id) -> Bool {
        let id = accountPeerId.toInt64()
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.keepArchivedAlignAccountIds.contains(id) {
            return false
        }
        self.keepArchivedAlignAccountIds.insert(id)
        return true
    }
    
    public func beginSuppressBackgroundRelock() {
        self.lock.lock()
        self.suppressBackgroundRelockCount += 1
        self.lock.unlock()
    }
    
    public func endSuppressBackgroundRelock() {
        self.lock.lock()
        self.suppressBackgroundRelockCount = max(0, self.suppressBackgroundRelockCount - 1)
        self.lock.unlock()
    }
    
    /// App-switcher cover, installed from TelegramUI where `Window1` is available. Invoked on
    /// the main queue immediately before `relock()` so the snapshot still sees `isUnlocked`.
    public var willRelockHandler: (() -> Void)? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.willRelockHandlerValue
        }
        set {
            self.lock.lock()
            self.willRelockHandlerValue = newValue
            self.lock.unlock()
        }
    }
    
    /// Remove the Archive app-switcher cover on foreground if App Lock did not replace it.
    public var didBecomeActiveHandler: (() -> Void)? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.didBecomeActiveHandlerValue
        }
        set {
            self.lock.lock()
            self.didBecomeActiveHandlerValue = newValue
            self.lock.unlock()
        }
    }
    
    /// Cached peer IDs currently sitting in a password-protected Archive. Empty when no
    /// password is set. Used by the sync Peer Info gate (`archivePeerInfoAllowed`).
    public func currentLockedPeerIds() -> Set<EnginePeer.Id> {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lockedPeerIds
    }
    
    public var areLockedPeerIdsResolved: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.lockedPeerIdsResolved
    }
    
    /// True when this peer must not open Peer Info without an unlock: password is set, the
    /// session is locked, and the peer is (or might still be) in Archive.
    ///
    /// Until the locked-peer-id cache has been read once, this fails closed for every peer so
    /// a launch race cannot push archived profile UI.
    public func isLockedArchivedPeer(_ peerId: EnginePeer.Id) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if !self.passwordConfigured || self.unlocked {
            return false
        }
        if !self.lockedPeerIdsResolved {
            return true
        }
        return self.lockedPeerIds.contains(peerId)
    }
    
    /// Tracks whether the bound account's password covers Saved Messages. Same replacement rules as
    /// `bindPasswordProtection`: a new account record replaces the subscription and starts locked.
    public func bindSavedMessagesLock(accountId: Int64, isLocked: Signal<Bool, NoError>) {
        self.lock.lock()
        if self.savedMessagesBindingAccountId == accountId {
            self.lock.unlock()
            return
        }
        let previousDisposable = self.savedMessagesDisposable
        self.savedMessagesBindingAccountId = accountId
        self.savedMessagesDisposable = EmptyDisposable
        self.savedMessagesLocked = true
        self.lock.unlock()
        previousDisposable?.dispose()
        self.updateSavedMessagesListed()

        let disposable = (isLocked
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let self else {
                return
            }
            self.lock.lock()
            guard self.savedMessagesBindingAccountId == accountId else {
                self.lock.unlock()
                return
            }
            self.savedMessagesLocked = value
            self.lock.unlock()
            self.updateSavedMessagesListed()
        })

        var isObsolete = false
        self.lock.lock()
        if self.savedMessagesBindingAccountId == accountId {
            self.savedMessagesDisposable = disposable
        } else {
            isObsolete = true
        }
        self.lock.unlock()
        if isObsolete {
            disposable.dispose()
        }
    }

    /// Keep `currentLockedPeerIds` in sync with Postbox. Replaces any previous subscription
    /// when the bound account record changes (same pattern as `bindPasswordProtection`).
    public func bindLockedPeerIds(accountId: Int64, lockedPeerIds: Signal<Set<EnginePeer.Id>, NoError>) {
        self.lock.lock()
        if self.lockedPeerIdsBindingAccountId == accountId {
            self.lock.unlock()
            return
        }
        let previousDisposable = self.lockedPeerIdsDisposable
        self.lockedPeerIdsBindingAccountId = accountId
        self.lockedPeerIdsDisposable = EmptyDisposable
        self.lockedPeerIdsResolved = false
        self.lockedPeerIds = []
        self.lock.unlock()
        previousDisposable?.dispose()
        
        let disposable = (lockedPeerIds
        |> distinctUntilChanged
        |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            guard let self else {
                return
            }
            self.lock.lock()
            guard self.lockedPeerIdsBindingAccountId == accountId else {
                self.lock.unlock()
                return
            }
            self.lockedPeerIds = value
            self.lockedPeerIdsResolved = true
            self.lock.unlock()
        })
        
        var isObsolete = false
        self.lock.lock()
        if self.lockedPeerIdsBindingAccountId == accountId {
            self.lockedPeerIdsDisposable = disposable
        } else {
            isObsolete = true
        }
        self.lock.unlock()
        if isObsolete {
            disposable.dispose()
        }
    }
    
    /// Re-lock Archive when the app leaves the active state.
    ///
    /// Handlers are looked up at fire time (`willRelockHandler` / `didBecomeActiveHandler`) so
    /// account switches can refresh them without rebinding the subscription. `applicationInForeground`
    /// distinguishes Face ID resign-active (still foreground — suppressible) from a true Home
    /// background (always relock, even mid-biometric).
    public func bindBackgroundRelock(applicationIsActive: Signal<Bool, NoError>, applicationInForeground: Signal<Bool, NoError>) {
        // Claim the "binding" slot atomically with a placeholder before subscribing, so two
        // concurrent callers can't both observe "not yet bound" and both subscribe — only the
        // caller that wins the claim installs a real disposable; the loser's subscription is
        // disposed immediately instead of being silently orphaned by an overwritten assignment.
        self.lock.lock()
        let alreadyBound = self.backgroundDisposable != nil
        if !alreadyBound {
            self.backgroundDisposable = EmptyDisposable
        }
        self.lock.unlock()
        if alreadyBound {
            return
        }
        let disposable = (combineLatest(applicationIsActive, applicationInForeground)
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs.0 == rhs.0 && lhs.1 == rhs.1
        })
        |> deliverOnMainQueue).startStrict(next: { [weak self] isActive, inForeground in
            guard let self else {
                return
            }
            if isActive {
                self.didBecomeActiveHandler?()
            } else {
                self.lock.lock()
                let suppressed = self.suppressBackgroundRelockCount > 0
                self.lock.unlock()
                // Face ID/Touch ID resigns active while still foreground — skip. A real
                // background (Home / app switcher settle) must always relock.
                if suppressed && inForeground {
                    return
                }
                self.willRelockHandler?()
                self.relock()
                // Hidden accounts close only on a real background: leaving one switches the whole app to another
                // account, which Control Center or a call banner over the app must not do.
                if !inForeground {
                    HiddenAccountsSession.shared.relock()
                }
            }
        })
        self.lock.lock()
        self.backgroundDisposable = disposable
        self.lock.unlock()
    }
}

public func updateChatArchiveSettings(engine: TelegramEngine, _ f: @escaping (ChatArchiveSettings) -> ChatArchiveSettings) -> Signal<Never, NoError> {
    return engine.preferences.update(id: ApplicationSpecificPreferencesKeys.chatArchiveSettings, { entry in
        let currentSettings: ChatArchiveSettings
        if let entry = entry?.get(ChatArchiveSettings.self) {
            currentSettings = entry
        } else {
            currentSettings = .default
        }
        return SharedPreferencesEntry(f(currentSettings))
    })
}

/// Whether Archive is password-protected for this account (Keychain, with prefs migration).
public func archiveIsPasswordProtected(peerId: EnginePeer.Id, settings: ChatArchiveSettings) -> Bool {
    ArchivePasswordKeychain.noteBackupVerifier(settings.passwordVerifier, peerId: peerId)
    if ArchivePasswordKeychain.migrateFromPreferencesIfNeeded(peerId: peerId, legacyHash: settings.legacyLockPasswordHash) {
        return true
    }
    // A re-signed build cannot read the old Keychain item. Put the backup verifier back so the password keeps working.
    if let verifier = settings.passwordVerifier, !verifier.isEmpty {
        if !ArchivePasswordKeychain.hasPassword(peerId: peerId) {
            _ = ArchivePasswordKeychain.storeHash(verifier, peerId: peerId)
        }
        return true
    }
    return settings.isPasswordConfigured || ArchivePasswordKeychain.hasPassword(peerId: peerId)
}

/// Whether a peer's notifications/calls should be fully redacted because it currently lives
/// in a password-protected Archive. Single source of truth for this check so the Notification
/// Service Extension (Postbox only, no Keychain access group shared with the main app) and the
/// main app's CallKit/VoIP handling can't drift out of sync with each other.
///
/// Uses `ChatArchiveSettings.isPasswordConfigured` (a plain Postbox-resident mirror of the
/// Keychain state) rather than `archiveIsPasswordProtected`/`ArchivePasswordKeychain` directly,
/// since the latter requires Keychain access this check must also work without.
public func archiveNotificationShouldRedact(transaction: Transaction, peerId: EnginePeer.Id) -> Bool {
    let savedMessagesPeerId = (transaction.getState() as? AuthorizedAccountState)?.peerId
    let settings = transaction.getPreferencesEntry(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)?.get(ChatArchiveSettings.self) ?? .default
    if peerId == savedMessagesPeerId {
        return settings.isSavedMessagesLocked
    }
    guard transaction.getPeerChatListIndex(peerId)?.0 == Namespaces.PeerGroup.archive else {
        return false
    }
    return settings.isArchiveLocked
}

public func hiddenAccountsSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<HiddenAccountsSettings, NoError> {
    return accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.hiddenAccountsSettings])
    |> map { sharedData -> HiddenAccountsSettings in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.hiddenAccountsSettings]?.get(HiddenAccountsSettings.self) ?? .default
    }
    |> distinctUntilChanged
}

/// Changes the hidden accounts, dropping entries for accounts that are no longer signed in on the way.
public func updateHiddenAccountsSettings(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (HiddenAccountsSettings) -> HiddenAccountsSettings) -> Signal<Never, NoError> {
    return accountManager.transaction { transaction -> Void in
        var liveAccountIds = Set<Int64>()
        for record in transaction.getRecords() {
            let loggedOut = record.attributes.contains(where: { attribute in
                if case .loggedOut = attribute {
                    return true
                } else {
                    return false
                }
            })
            if !loggedOut {
                liveAccountIds.insert(record.id.int64)
            }
        }
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.hiddenAccountsSettings, { entry in
            let current = entry?.get(HiddenAccountsSettings.self) ?? .default
            return SharedPreferencesEntry(f(current).keepingAccounts(liveAccountIds))
        })
    }
    |> ignoreValues
}

/// Whether this account's notifications and calls are redacted because it is hidden and not opened. Reads the stored
/// settings, so it answers on a cold start (a VoIP push) before `HiddenAccountsSession` has resolved.
public func hiddenAccountIsLocked(accountManager: AccountManager<TelegramAccountManagerTypes>, accountId: Int64) -> Signal<Bool, NoError> {
    return hiddenAccountsSettings(accountManager: accountManager)
    |> take(1)
    |> map { settings -> Bool in
        return settings.isHidden(accountId) && !HiddenAccountsSession.shared.state.unlockedAccountIds.contains(accountId)
    }
}

/// Whether search, mentions and the share sheet leave this peer out: it is in a password-protected Archive and that Archive
/// is locked. Unlike notifications and calls (`archiveNotificationShouldRedact`, which also run in extensions and while
/// the app is in the background), these are on screen in front of someone who has just opened the Archive, and hiding
/// its chats from them there made searching inside an unlocked Archive find nothing.
public func archiveSearchShouldHide(transaction: Transaction, peerId: EnginePeer.Id) -> Bool {
    if let accountPeerId = (transaction.getState() as? AuthorizedAccountState)?.peerId, ArchiveLockSession.shared.isUnlocked(accountPeerId: accountPeerId) {
        return false
    }
    return archiveNotificationShouldRedact(transaction: transaction, peerId: peerId)
}

/// Engine-data equivalent of `archiveNotificationShouldRedact` for call sites that already
/// have `ChatListGroup` + settings and must not import Postbox (CallListUI, ContactListUI).
public func archiveNotificationShouldRedact(chatListGroup: EngineChatList.Group?, isPasswordConfigured: Bool) -> Bool {
    return chatListGroup == .archive && isPasswordConfigured
}

/// Peer IDs currently sitting in a password-protected Archive. Empty when no password is set.
public func archiveLockedPeerIds(transaction: Transaction) -> Set<EnginePeer.Id> {
    let settings = transaction.getPreferencesEntry(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)?.get(ChatArchiveSettings.self) ?? .default
    guard settings.isPasswordConfigured else {
        return []
    }
    var peerIds = Set<EnginePeer.Id>()
    if settings.isArchiveLocked {
        peerIds.formUnion(transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive))
    }
    if settings.isSavedMessagesLocked, let peerId = (transaction.getState() as? AuthorizedAccountState)?.peerId {
        peerIds.insert(peerId)
    }
    return peerIds
}
