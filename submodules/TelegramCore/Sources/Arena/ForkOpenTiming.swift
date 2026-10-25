import Foundation

/// Fork: how long a screen takes to open, written to the app log (`Perf` lines in Logs ▸ All Logs).
///
/// The log had no way to tell a slow network (a request waiting for a connection through a proxy) from a slow
/// screen (layout and drawing on the main thread), so "opening a chat lags" could not be answered from it. A
/// timing starts when the screen object is created and logs each event with the milliseconds since then. It
/// carries no peer, message or account data.
public struct ForkOpenTiming {
    private let kind: String
    private let startTime: Double

    public init(kind: String) {
        self.kind = kind
        self.startTime = CFAbsoluteTimeGetCurrent()
    }

    public func log(_ event: String) {
        let milliseconds = Int((CFAbsoluteTimeGetCurrent() - self.startTime) * 1000.0)
        Logger.shared.log("Perf", "open \(self.kind): \(event) after \(milliseconds) ms")
    }
}
