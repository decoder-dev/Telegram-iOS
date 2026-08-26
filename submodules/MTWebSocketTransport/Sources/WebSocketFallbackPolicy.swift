import Foundation

/// Walks an ordered list of endpoint candidates (e.g. `kwsN.web.telegram.org` then `kwsN-1...`) for a
/// single connection attempt. Owns no timers or I/O — `MTWebSocketConnectionInterface` drives it and
/// reuses MtProtoKit's existing `MTTcpConnectionBehaviour` for cross-attempt backoff/redial timing.
public final class WebSocketEndpointSelector {
    public private(set) var candidates: [WebSocketEndpointCandidate]
    private var index: Int = 0

    public init(candidates: [WebSocketEndpointCandidate]) {
        self.candidates = candidates
    }

    public var current: WebSocketEndpointCandidate? {
        guard self.index < self.candidates.count else {
            return nil
        }
        return self.candidates[self.index]
    }

    public var isExhausted: Bool {
        return self.index >= self.candidates.count
    }

    /// Moves to the next candidate and returns it, or `nil` if every candidate has now been tried.
    @discardableResult
    /// Moves to the next candidate. Logged because falling through this list is the last thing that
    /// happens before an attempt is given up on, and which endpoint was reached is the difference
    /// between a blocked host and a blocked network.
    public func advance() -> WebSocketEndpointCandidate? {
        self.index += 1
        let next = self.current
        if let next = next {
            WebSocketTransportLog.log("endpoint \(self.index + 1)/\(self.candidates.count): \(next.host)\(next.path)")
        } else {
            WebSocketTransportLog.log("all \(self.candidates.count) endpoints exhausted")
        }
        return next
    }

    public func reset() {
        self.index = 0
    }
}

/// Tracks consecutive "every WS endpoint failed" outcomes across reconnect attempts and signals when
/// the session should give up on WebSocket transport for the rest of the session and let
/// `Network.swift` fall back to MtProtoKit's normal TCP transport (only consulted if the user has
/// enabled the "fallback to direct" setting).
public struct WebSocketFallbackPolicy {
    public let consecutiveFailureThreshold: Int
    public private(set) var consecutiveTotalFailures: Int = 0

    public init(consecutiveFailureThreshold: Int = 3) {
        self.consecutiveFailureThreshold = consecutiveFailureThreshold
    }

    /// Call once all candidates in a `WebSocketEndpointSelector` have failed for a connection attempt.
    /// Returns `true` once the threshold is reached (caller should stop using WebSocket transport).
    @discardableResult
    public mutating func recordAllEndpointsFailed() -> Bool {
        self.consecutiveTotalFailures += 1
        return self.consecutiveTotalFailures >= self.consecutiveFailureThreshold
    }

    public mutating func recordSuccess() {
        self.consecutiveTotalFailures = 0
    }
}
