import Foundation
import SwiftSignalKit

/// Fork: counts how many instances of a screen or node are alive at once, written to the app log (`Perf` lines).
///
/// A chat list that is drawn two, three or four times over while the app connects through a proxy is either
/// several live copies of the screen, or one copy that draws itself repeatedly. The log could not tell the two
/// apart. Hold one token per instance (`private let liveToken = ForkLiveToken(kind: "...")`): it logs the number
/// alive when the instance is created and when it goes. It carries no peer, message or account data.
public final class ForkLiveToken {
    private static let counts = Atomic<[String: Int]>(value: [:])

    private let kind: String

    public init(kind: String) {
        self.kind = kind
        let alive = ForkLiveToken.adjust(kind: kind, by: 1)
        Logger.shared.log("Perf", "live \(kind): \(alive)")
    }

    deinit {
        let alive = ForkLiveToken.adjust(kind: self.kind, by: -1)
        Logger.shared.log("Perf", "live \(self.kind): \(alive)")
    }

    private static func adjust(kind: String, by delta: Int) -> Int {
        var result = 0
        let _ = counts.modify { current in
            var next = current
            result = (current[kind] ?? 0) + delta
            next[kind] = result
            return next
        }
        return result
    }
}
