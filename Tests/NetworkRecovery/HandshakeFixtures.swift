import Foundation
final class HandshakeQueue { func async(_ body: () -> Void) { body() } }
final class HandshakeConnection {
    enum Completion { case contentProcessed((Error?) -> Void) }
    var completion: ((Error?) -> Void)?
    func send(content: Data, completion: Completion) {
        if case let .contentProcessed(body) = completion { self.completion = body }
    }
}
final class Impl {
    enum State { case initial, sentUpgradeRequest }
    var connection: HandshakeConnection?
    var currentCandidateHost: String? = "example.invalid"
    var currentCandidatePath: String? = "/apiws"
    var currentCandidateHttpHost: String?
    var handshakeState = State.initial
    let queue = HandshakeQueue()
    var failures = 0
    static func makeSecWebSocketKey() -> String { "test-key" }
    func candidateFailed(error: Error?) { failures += 1 }
    func receiveLoop() {}
    // PRODUCTION_HANDSHAKE
}
let client = Impl()
let old = HandshakeConnection()
client.connection = old
client.beginWebSocketHandshake()
let replacement = HandshakeConnection()
client.connection = replacement
client.beginWebSocketHandshake()
old.completion?(NSError(domain: "CancelledHandshake", code: 1))
precondition(client.failures == 0, "Stale handshake cancelled replacement")
replacement.completion?(NSError(domain: "ActiveHandshake", code: 2))
precondition(client.failures == 1, "Current handshake failure was lost")
client.connection = nil
replacement.completion?(NSError(domain: "ClosedHandshake", code: 3))
precondition(client.failures == 1, "Terminal close reported twice")
print("Production WebSocket handshake: stale, active and closed completion checks passed")
