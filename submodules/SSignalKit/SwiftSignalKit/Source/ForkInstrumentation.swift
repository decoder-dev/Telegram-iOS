import Foundation

/// Runtime gate for the fork's high-volume QA instrumentation logging.
///
/// Many diagnostics added by the fork (per-transaction timings, view replays,
/// read-state sync chatter, live-object counts) are invaluable while a build is
/// being qualified, but on hot paths they cost formatting time and disk writes
/// on every user device. They are compiled in, but disabled by default.
///
/// Enable them for a diagnostic run with:
/// `defaults write <bundle-id> forkInstrumentation -bool true`
public enum ForkInstrumentation {
    public static let isEnabled: Bool = UserDefaults.standard.bool(forKey: "forkInstrumentation")
}
