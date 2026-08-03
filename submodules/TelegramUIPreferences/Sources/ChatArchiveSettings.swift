import Foundation
import SwiftSignalKit
import TelegramCore

public struct ChatArchiveSettings: Equatable, Codable {
    public var isHiddenByDefault: Bool
    public var hiddenPsaPeerId: EnginePeer.Id?
    /// When non-nil, opening the Archive folder requires this password.
    public var lockPassword: String?
    
    public static var `default`: ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: false, hiddenPsaPeerId: nil, lockPassword: nil)
    }
    
    public var isPasswordProtected: Bool {
        if let lockPassword = self.lockPassword, !lockPassword.isEmpty {
            return true
        }
        return false
    }
    
    public init(isHiddenByDefault: Bool, hiddenPsaPeerId: EnginePeer.Id?, lockPassword: String? = nil) {
        self.isHiddenByDefault = isHiddenByDefault
        self.hiddenPsaPeerId = hiddenPsaPeerId
        self.lockPassword = lockPassword
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.isHiddenByDefault = (try container.decode(Int32.self, forKey: "isHiddenByDefault")) != 0
        self.hiddenPsaPeerId = (try container.decodeIfPresent(Int64.self, forKey: "hiddenPsaPeerId")).flatMap(EnginePeer.Id.init)
        self.lockPassword = try container.decodeIfPresent(String.self, forKey: "lockPassword")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.isHiddenByDefault ? 1 : 0) as Int32, forKey: "isHiddenByDefault")
        if let hiddenPsaPeerId = self.hiddenPsaPeerId {
            try container.encode(hiddenPsaPeerId.toInt64(), forKey: "hiddenPsaPeerId")
        } else {
            try container.encodeNil(forKey: "hiddenPsaPeerId")
        }
        if let lockPassword = self.lockPassword {
            try container.encode(lockPassword, forKey: "lockPassword")
        } else {
            try container.encodeNil(forKey: "lockPassword")
        }
    }
    
    public func withUpdatedLockPassword(_ password: String?) -> ChatArchiveSettings {
        return ChatArchiveSettings(isHiddenByDefault: self.isHiddenByDefault, hiddenPsaPeerId: self.hiddenPsaPeerId, lockPassword: password)
    }
}

/// In-memory session unlock for the Archive folder password.
/// Cleared when the process exits; re-lock is available via `relock()`.
public final class ArchiveLockSession {
    public static let shared = ArchiveLockSession()
    
    private let lock = NSLock()
    private var unlocked = false
    
    private init() {}
    
    public var isUnlocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.unlocked
    }
    
    public func unlock() {
        self.lock.lock()
        self.unlocked = true
        self.lock.unlock()
    }
    
    public func relock() {
        self.lock.lock()
        self.unlocked = false
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
