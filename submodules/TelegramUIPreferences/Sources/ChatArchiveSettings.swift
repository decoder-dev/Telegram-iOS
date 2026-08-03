import Foundation
import SwiftSignalKit
import TelegramCore
import CryptoUtils

public struct ChatArchiveSettings: Equatable, Codable {
    public var isHiddenByDefault: Bool
    public var hiddenPsaPeerId: EnginePeer.Id?
    /// SHA-256 hex digest of the Archive password. Nil = unlocked.
    public var lockPasswordHash: String?
    
    public static var `default`: ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, lockPasswordHash: nil)
    }
    
    public var isPasswordProtected: Bool {
        if let lockPasswordHash = self.lockPasswordHash, !lockPasswordHash.isEmpty {
            return true
        }
        return false
    }
    
    public init(isHiddenByDefault: Bool, hiddenPsaPeerId: EnginePeer.Id?, lockPasswordHash: String? = nil) {
        self.isHiddenByDefault = isHiddenByDefault
        self.hiddenPsaPeerId = hiddenPsaPeerId
        self.lockPasswordHash = lockPasswordHash
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.isHiddenByDefault = (try container.decode(Int32.self, forKey: "isHiddenByDefault")) != 0
        self.hiddenPsaPeerId = (try container.decodeIfPresent(Int64.self, forKey: "hiddenPsaPeerId")).flatMap(EnginePeer.Id.init)
        if let hash = try container.decodeIfPresent(String.self, forKey: "lockPasswordHash"), !hash.isEmpty {
            self.lockPasswordHash = hash
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: "lockPassword"), !legacy.isEmpty {
            // One-shot migration from plaintext password stored by the first draft.
            self.lockPasswordHash = archivePasswordHash(legacy)
        } else {
            self.lockPasswordHash = nil
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
        if let lockPasswordHash = self.lockPasswordHash {
            try container.encode(lockPasswordHash, forKey: "lockPasswordHash")
        } else {
            try container.encodeNil(forKey: "lockPasswordHash")
        }
        // Drop any legacy plaintext key on next write.
        try container.encodeNil(forKey: "lockPassword")
    }
    
    public func withUpdatedLockPasswordHash(_ hash: String?) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, lockPasswordHash: hash)
    }
    
    public func matchesPassword(_ password: String) -> Bool {
        guard let lockPasswordHash = self.lockPasswordHash else {
            return false
        }
        return lockPasswordHash == archivePasswordHash(password)
    }
}

public func archivePasswordHash(_ password: String) -> String {
    let data = Data(password.utf8)
    let digest: Data = data.withUnsafeBytes { buffer -> Data in
        let pointer = buffer.baseAddress ?? UnsafeRawPointer(bitPattern: 0x1)!
        return CryptoSHA256(pointer, Int32(buffer.count)) as Data
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// In-memory session unlock for the Archive folder password.
public final class ArchiveLockSession {
    public static let shared = ArchiveLockSession()
    
    private let lock = NSLock()
    private var unlocked = false
    private var didMuteSweep = false
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
