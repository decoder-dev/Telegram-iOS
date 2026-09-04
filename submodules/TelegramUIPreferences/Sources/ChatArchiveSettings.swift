import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox

public struct ChatArchiveSettings: Equatable, Codable {
    public var isHiddenByDefault: Bool
    public var hiddenPsaPeerId: EnginePeer.Id?
    /// Legacy field kept only for migration into Keychain; never written going forward.
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

    public static var `default`: ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, legacyLockPasswordHash: nil, useBiometrics: false, isPasswordConfigured: false)
    }

    public init(isHiddenByDefault: Bool, hiddenPsaPeerId: EnginePeer.Id?, legacyLockPasswordHash: String? = nil, useBiometrics: Bool = false, isPasswordConfigured: Bool = false) {
        self.isHiddenByDefault = isHiddenByDefault
        self.hiddenPsaPeerId = hiddenPsaPeerId
        self.legacyLockPasswordHash = legacyLockPasswordHash
        self.useBiometrics = useBiometrics
        self.isPasswordConfigured = isPasswordConfigured
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.isHiddenByDefault ? 1 : 0) as Int32, forKey: "isHiddenByDefault")
        if let hiddenPsaPeerId = self.hiddenPsaPeerId {
            try container.encode(hiddenPsaPeerId.toInt64(), forKey: "hiddenPsaPeerId")
        } else {
            try container.encodeNil(forKey: "hiddenPsaPeerId")
        }
        // Password hash lives in Keychain; clear any prefs copies on write.
        try container.encodeNil(forKey: "lockPasswordHash")
        try container.encodeNil(forKey: "lockPassword")
        try container.encode((self.useBiometrics ? 1 : 0) as Int32, forKey: "useBiometrics")
        try container.encode((self.isPasswordConfigured ? 1 : 0) as Int32, forKey: "isPasswordConfigured")
    }

    public func clearingLegacyPasswordHash() -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: nil, useBiometrics: self.useBiometrics, isPasswordConfigured: self.isPasswordConfigured)
    }

    public func withUpdatedUseBiometrics(_ useBiometrics: Bool) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: self.legacyLockPasswordHash, useBiometrics: useBiometrics, isPasswordConfigured: self.isPasswordConfigured)
    }

    public func withUpdatedIsPasswordConfigured(_ isPasswordConfigured: Bool) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: self.legacyLockPasswordHash, useBiometrics: isPasswordConfigured ? self.useBiometrics : false, isPasswordConfigured: isPasswordConfigured)
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
    private var passwordDisposable: Disposable?
    private var muteSweepAccountIds = Set<Int64>()
    private var keepArchivedAlignAccountIds = Set<Int64>()
    private var backgroundDisposable: Disposable?
    private var lockedPeerIdsBindingAccountId: Int64?
    private var lockedPeerIdsDisposable: Disposable?
    private var lockedPeerIds = Set<EnginePeer.Id>()
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
    private let relockedPipe = ValuePipe<Void>()
    private let revealedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    private let unlockedPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    private let folderPresentationPromise = ValuePromise<ArchiveFolderPresentation>(.omitted, ignoreRepeated: true)
    
    private init() {}
    
    public var isUnlocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.unlocked
    }
    
    /// Whether the Archive folder may appear in the main chat list. With no password there is
    /// nothing to hide, so the folder is always available and the 10-tap gesture is a no-op.
    public var isRevealed: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return !self.passwordConfigured || self.revealed
    }
    
    /// Whether the currently bound account has an Archive password set.
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
    }
    
    public func relock() {
        // With no password there is no lock to re-apply, and re-locking has side effects the
        // stock Archive must not get: it pops an open Archive screen and hides the folder row.
        guard self.isLockActive else {
            return
        }
        var shouldNotifyRelock = false
        var shouldNotifyReveal = false
        var collapseGeneration = 0
        self.lock.lock()
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
    public func bindPasswordProtection(accountId: Int64, isPasswordConfigured: Signal<Bool, NoError>) {
        self.lock.lock()
        if self.passwordBindingAccountId == accountId {
            self.lock.unlock()
            return
        }
        let previousDisposable = self.passwordDisposable
        // Claim the slot with a placeholder before subscribing, so a second caller for this same
        // account takes the early return above instead of starting a duplicate subscription.
        self.passwordBindingAccountId = accountId
        self.passwordDisposable = EmptyDisposable
        self.passwordStateResolved = false
        self.lock.unlock()
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
    if ArchivePasswordKeychain.migrateFromPreferencesIfNeeded(peerId: peerId, legacyHash: settings.legacyLockPasswordHash) {
        return true
    }
    return ArchivePasswordKeychain.hasPassword(peerId: peerId)
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
    guard transaction.getPeerChatListIndex(peerId)?.0 == Namespaces.PeerGroup.archive else {
        return false
    }
    let settings = transaction.getPreferencesEntry(key: ApplicationSpecificPreferencesKeys.chatArchiveSettings)?.get(ChatArchiveSettings.self) ?? .default
    return settings.isPasswordConfigured
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
    return Set(transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive))
}
