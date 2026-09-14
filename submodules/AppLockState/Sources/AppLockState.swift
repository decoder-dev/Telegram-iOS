import Foundation
import MonotonicTime

public struct MonotonicTimestamp: Codable, Equatable {
    public var bootTimestamp: Int32
    public var uptime: Int32

    public init(bootTimestamp: Int32, uptime: Int32) {
        self.bootTimestamp = bootTimestamp
        self.uptime = uptime
    }
}

public struct UnlockAttempts: Codable, Equatable {
    public var count: Int32
    public var timestamp: MonotonicTimestamp

    public init(count: Int32, timestamp: MonotonicTimestamp) {
        self.count = count
        self.timestamp = timestamp
    }
}

public struct LockState: Codable, Equatable {
    public var isManuallyLocked: Bool
    public var autolockTimeout: Int32?
    public var unlockAttempts: UnlockAttempts?
    public var applicationActivityTimestamp: MonotonicTimestamp?

    public init(isManuallyLocked: Bool = false, autolockTimeout: Int32? = nil, unlockAttemts: UnlockAttempts? = nil, applicationActivityTimestamp: MonotonicTimestamp? = nil) {
        self.isManuallyLocked = isManuallyLocked
        self.autolockTimeout = autolockTimeout
        self.unlockAttempts = unlockAttemts
        self.applicationActivityTimestamp = applicationActivityTimestamp
    }
}

public func appLockStatePath(rootPath: String) -> String {
    return rootPath + "/lockState.json"
}

public func isAppLocked(state: LockState) -> Bool {
    if state.isManuallyLocked {
        return true
    } else if let autolockTimeout = state.autolockTimeout {
        var bootTimestamp: Int32 = 0
        let uptime = getDeviceUptimeSeconds(&bootTimestamp)
        let timestamp = MonotonicTimestamp(bootTimestamp: bootTimestamp, uptime: uptime)
        
        if let applicationActivityTimestamp = state.applicationActivityTimestamp {
            if timestamp.bootTimestamp != applicationActivityTimestamp.bootTimestamp {
                return true
            }
            if timestamp.uptime >= applicationActivityTimestamp.uptime + autolockTimeout {
                return true
            }
        } else {
            return true
        }
    }
    return false
}

/// Fail-closed app-lock check for extension processes (NSE, Siri, widgets).
///
/// - No lock-state file at all → no passcode was ever set up → unlocked.
/// - File exists but cannot be read or parsed → assume LOCKED. A corrupt or partially
///   written state must never surface private content through a notification, Siri
///   response, or widget; the main app rewrites the file atomically on its next state
///   change. The cost of a false "locked" (generic text instead of message content) is
///   trivial next to the cost of a false "unlocked".
public func isAppLockedFailClosed(rootPath: String) -> Bool {
    let path = appLockStatePath(rootPath: rootPath)
    guard FileManager.default.fileExists(atPath: path) else {
        return false
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let state = try? JSONDecoder().decode(LockState.self, from: data) else {
        return true
    }
    return isAppLocked(state: state)
}
