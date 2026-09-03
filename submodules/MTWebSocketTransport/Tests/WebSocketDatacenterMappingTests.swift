import XCTest
@testable import MTWebSocketTransport

final class WebSocketDatacenterMappingTests: XCTestCase {
    func testNonMediaOrderingPutsBaseHostFirst() {
        XCTAssertEqual(WebSocketDatacenter.hostnames(datacenterId: 2, isMedia: false), ["kws2.web.telegram.org", "kws2-1.web.telegram.org"])
    }

    func testMediaOrderingPutsAlternateHostFirst() {
        XCTAssertEqual(WebSocketDatacenter.hostnames(datacenterId: 2, isMedia: true), ["kws2-1.web.telegram.org", "kws2.web.telegram.org"])
    }

    func testAllProductionDatacentersOneThroughFive() {
        for dc in 1...5 {
            XCTAssertEqual(WebSocketDatacenter.hostnames(datacenterId: dc, isMedia: false).first, "kws\(dc).web.telegram.org")
        }
    }

    func testDc203FoldsToDc2() {
        XCTAssertEqual(WebSocketDatacenter.hostnames(datacenterId: 203, isMedia: false), WebSocketDatacenter.hostnames(datacenterId: 2, isMedia: false))
        XCTAssertEqual(WebSocketDatacenter.hostnames(datacenterId: 203, isMedia: true), WebSocketDatacenter.hostnames(datacenterId: 2, isMedia: true))
    }

    func testNegativeDatacenterIdIsTreatedAsMagnitude() {
        // MTTcpConnection encodes preferForMedia as a sign bit on the DC id in some call paths;
        // the mapping only cares about magnitude, media-ness is passed separately.
        XCTAssertEqual(WebSocketDatacenter.hostnames(datacenterId: -2, isMedia: false), WebSocketDatacenter.hostnames(datacenterId: 2, isMedia: false))
    }

    func testProductionPath() {
        XCTAssertEqual(WebSocketDatacenter.path(isTestingEnvironment: false), "/apiws")
    }

    func testTestEnvironmentPath() {
        XCTAssertEqual(WebSocketDatacenter.path(isTestingEnvironment: true), "/apiws_test")
    }

    func testEndpointPlannerCombinesHostsAndPath() {
        let candidates = WebSocketEndpointPlanner.candidates(datacenterId: 4, isMedia: true, isTestingEnvironment: true)
        XCTAssertEqual(candidates, [
            WebSocketEndpointCandidate(host: "kws4-1.web.telegram.org", path: "/apiws_test", kind: .telegramGateway),
            WebSocketEndpointCandidate(host: "kws4.web.telegram.org", path: "/apiws_test", kind: .telegramGateway),
        ])
    }

    func testEndpointPlannerDefaultPortIs443() {
        let candidates = WebSocketEndpointPlanner.candidates(datacenterId: 1, isMedia: false, isTestingEnvironment: false)
        XCTAssertEqual(candidates.map { $0.port }, [443, 443])
    }

    func testEndpointPlannerTelegramCandidatesHaveIdenticalHttpHostAndTlsName() {
        let candidates = WebSocketEndpointPlanner.candidates(datacenterId: 2, isMedia: false, isTestingEnvironment: false)
        for c in candidates {
            XCTAssertEqual(c.httpHost, c.host)
            XCTAssertEqual(c.tlsServerName, c.host)
            XCTAssertEqual(c.kind, .telegramGateway)
        }
    }

    func testEndpointPlannerFrontCandidateOverridesHttpHostAndSNI() {
        let template = WebSocketFrontTemplate(
            host: "worker.example.com",
            port: 443,
            pathTemplate: "/dc/{dc}/apiws",
            httpHostTemplate: "worker.example.com",
            tlsServerNameTemplate: "worker.example.com"
        )
        let config = WebSocketEndpointPlanConfig(fronts: [template], order: .frontsFirst)
        let candidates = WebSocketEndpointPlanner.candidates(datacenterId: 1, isMedia: false, isTestingEnvironment: false, config: config)
        guard let front = candidates.first else {
            return XCTFail("expected front candidate first")
        }
        XCTAssertEqual(front.kind, .front)
        XCTAssertEqual(front.httpHost, "worker.example.com")
        XCTAssertEqual(front.tlsServerName, "worker.example.com")
        // Remaining candidates are Telegram gateways
        XCTAssertTrue(candidates.dropFirst().allSatisfy { $0.kind == .telegramGateway })
    }
}
