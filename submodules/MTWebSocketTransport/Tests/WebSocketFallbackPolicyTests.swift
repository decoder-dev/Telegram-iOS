import XCTest
@testable import MTWebSocketTransport

final class WebSocketFallbackPolicyTests: XCTestCase {
    private func makeSelector() -> WebSocketEndpointSelector {
        return WebSocketEndpointSelector(candidates: [
            WebSocketEndpointCandidate(host: "a", path: "/apiws"),
            WebSocketEndpointCandidate(host: "b", path: "/apiws"),
        ])
    }

    func testSelectorStartsAtPrimaryEndpoint() {
        XCTAssertEqual(self.makeSelector().current?.host, "a")
    }

    func testPrimaryFailsAdvancesToSecondary() {
        let selector = self.makeSelector()
        XCTAssertEqual(selector.advance()?.host, "b")
        XCTAssertFalse(selector.isExhausted)
    }

    func testBothFailExhaustsSelector() {
        let selector = self.makeSelector()
        _ = selector.advance()
        XCTAssertNil(selector.advance())
        XCTAssertTrue(selector.isExhausted)
    }

    func testResetReturnsToPrimary() {
        let selector = self.makeSelector()
        _ = selector.advance()
        selector.reset()
        XCTAssertEqual(selector.current?.host, "a")
        XCTAssertFalse(selector.isExhausted)
    }

    func testFallbackPolicyTriggersOnlyAtThreshold() {
        var policy = WebSocketFallbackPolicy(consecutiveFailureThreshold: 3)
        XCTAssertFalse(policy.recordAllEndpointsFailed())
        XCTAssertFalse(policy.recordAllEndpointsFailed())
        XCTAssertTrue(policy.recordAllEndpointsFailed())
    }

    func testFallbackPolicyResetsOnSuccess() {
        var policy = WebSocketFallbackPolicy(consecutiveFailureThreshold: 2)
        XCTAssertFalse(policy.recordAllEndpointsFailed())
        policy.recordSuccess()
        XCTAssertFalse(policy.recordAllEndpointsFailed())
        XCTAssertTrue(policy.recordAllEndpointsFailed())
    }
}
