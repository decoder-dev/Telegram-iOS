import Foundation
import SwiftSignalKit
import TelegramCore

public struct ChatArchiveSettings: Equatable, Codable {
    public var isHiddenByDefault: Bool
    public var hiddenPsaPeerId: EnginePeer.Id?
    /// Legacy field kept only for migration into Keychain; never written going forward.
    public var legacyLockPasswordHash: String?
    
    public static var `default`: ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, legacyLockPasswordHash: nil)
    }
    
    public init(isHiddenByDefault: Bool, hiddenPsaPeerId: EnginePeer.Id?, legacyLockPasswordHash: String? = nil) {
        self.isHiddenByDefault = isHiddenByDefault
        self.hiddenPsaPeerId = hiddenPsaPeerId
        self.legacyLockPasswordHash = legacyLockPasswordHash
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
    }
    
    public func clearingLegacyPasswordHash() -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, legacyLockPasswordHash: nil)
    }
}

/// In-memory session unlock for the Archive folder password.
public final class ArchiveLockSession {
    public static let shared = ArchiveLockSession()
    
    private let lock = NSLock()
    private var unlocked = false
    private var didMuteSweep = false
    private var didAlignKeepArchived = false
    private var backgroundDisposable: Disposable?
    private let relockedPipe = ValuePipe<Void>()
    
    private init() {}
    
    public var isUnlocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.unlocked
    }
    
    /// Fires whenever the session is re-locked (Lock Now / background).
    public var relockedSignal: Signal<Void, NoError> {
        return self.relockedPipe.signal()
    }
    
    public func unlock() {
        self.lock.lock()
        self.unlocked = true
        self.lock.unlock()
    }
    
    public func relock() {
        var shouldNotify = false
        self.lock.lock()
        if self.unlocked {
            self.unlocked = false
            shouldNotify = true
        }
        self.lock.unlock()
        if shouldNotify {
            self.relockedPipe.putNext(Void())
        }
    }
    
    /// Returns true the first time per process; used to mute existing archived chats once.
    public func claimMuteSweep() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.didMuteSweep {
            return false
        }
        self.didMuteSweep = true
        return true
    }
    
    /// Returns true the first time per process; used to align keepArchivedUnmuted with force-mute.
    public func claimKeepArchivedAlign() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.didAlignKeepArchived {
            return false
        }
        self.didAlignKeepArchived = true
        return true
    }
    
    /// Re-lock Archive when the app leaves the active state.
    public func bindBackgroundRelock(applicationIsActive: Signal<Bool, NoError>) {
        self.lock.lock()
        let alreadyBound = self.backgroundDisposable != nil
        self.lock.unlock()
        if alreadyBound {
            return
        }
        let disposable = (applicationIsActive
        |> distinctUntilChanged
        |> filter { !$0 }
        |> deliverOnMainQueue).startStrict(next: { [weak self] _ in
            self?.relock()
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
