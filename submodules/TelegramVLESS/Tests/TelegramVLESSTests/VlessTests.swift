import XCTest
@testable import TelegramVLESS

private let profileURL = "vless://01234567-89ab-cdef-0123-456789abcdef@example.com:443?security=tls&type=ws"

private final class FakeRuntime: XrayRuntime {
    let lock = NSLock()
    var running = false
    var startedHosts: [String] = []
    var ports = [21001, 21002]
    var onStart: (() -> Void)?
    var gate: DispatchSemaphore?
    var isAvailable: Bool { true }
    func getFreePorts(count: Int) throws -> [Int] { ports }
    func start(configJSON: String) throws {
        onStart?()
        if let gate = gate { _ = gate.wait(timeout: .now() + 5) }
        let config = try JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as! [String: Any]
        let out = (config["outbounds"] as! [[String: Any]])[0]
        let server = ((out["settings"] as! [String: Any])["vnext"] as! [[String: Any]])[0]
        lock.lock(); defer { lock.unlock() }
        startedHosts.append(server["address"] as! String)
        running = true
    }
    func stop() throws { lock.lock(); running = false; lock.unlock() }
    func isRunning() -> Bool { lock.lock(); defer { lock.unlock() }; return running }
    func version() -> String? { "test" }
}

final class VlessTests: XCTestCase {
    func testEndpointResolutionUsesNormalizedProfileIdentity() {
        let runtime = FakeRuntime()
        let ready = expectation(description: "normalized profile ready")
        weak var observedManager: VlessManager?
        var fulfilled = false
        let padded = " \n" + profileURL + "\r\n"
        let manager = VlessManager(runtime: runtime, onStateChange: {
            guard let manager = observedManager, manager.isRunning, !fulfilled else { return }
            fulfilled = true
            XCTAssertNotNil(manager.loopbackEndpoint(for: padded))
            XCTAssertEqual(manager.loopbackEndpoint(for: padded), manager.loopbackEndpoint(for: profileURL))
            XCTAssertNil(manager.loopbackEndpoint(for: profileURL.replacingOccurrences(of: "example.com", with: "other.example.com")))
            ready.fulfill()
        })
        observedManager = manager
        manager.start(url: padded)
        wait(for: [ready], timeout: 5)
        manager.stop()
        XCTAssertNil(manager.loopbackEndpoint(for: padded))
    }

    func testNativeInvokeResponseContract() throws {
        let ports = try LibXrayRuntime.decodeResponse(Data(#"{"success":true,"data":{"ports":[21001,21002]},"error":""}"#.utf8))
        XCTAssertEqual(ports?.ports, [21001, 21002])
        let state = try LibXrayRuntime.decodeResponse(Data(#"{"success":true,"data":{"running":true},"error":""}"#.utf8))
        XCTAssertEqual(state?.running, true)
        XCTAssertNotNil(try LibXrayRuntime.decodeResponse(Data(#"{"success":true,"data":{},"error":""}"#.utf8)))
        XCTAssertThrowsError(try LibXrayRuntime.decodeResponse(Data(#"{"success":false,"data":null,"error":"bad config"}"#.utf8)))
        XCTAssertThrowsError(try LibXrayRuntime.decodeResponse(Data(#"{"success":true,"data":"not an object","error":""}"#.utf8)))
    }

    func testParserRejectsInvalidAuthorityAndShortID() {
        for uri in [profileURL.replacingOccurrences(of: "@", with: ":password@"), profileURL.replacingOccurrences(of: "?", with: "/ignored?")] {
            guard case .failure = VlessProfileParser.parse(uri) else { return XCTFail("Accepted invalid authority") }
        }
        let reality = profileURL.replacingOccurrences(of: "security=tls&type=ws", with: "security=reality&pbk=" + String(repeating: "a", count: 43) + "&sid=a")
        XCTAssertEqual(VlessProfileParser.parse(reality), .failure(.invalidShortId))
    }

    func testIPv6AndCommonTCPLinkParameters() throws {
        let uri = profileURL.replacingOccurrences(of: "example.com", with: "[::1]").replacingOccurrences(of: "type=ws", with: "type=raw&headerType=none")
        let profile = try VlessProfileParser.parse(uri).get()
        XCTAssertEqual(profile.endpoint.host, "::1")
        XCTAssertEqual(profile.transport, .tcp)
        XCTAssertEqual(VlessProfileParser.parse(uri.replacingOccurrences(of: "headerType=none", with: "headerType=http")), .failure(.unsupportedHeaderType("http")))
        XCTAssertFalse(VlessProfileParser.isValidRealityPublicKey(String(repeating: "=", count: 43)))
    }

    func testSupportedTransportsAndConfig() throws {
        for transport in ["tcp", "ws", "grpc", "httpupgrade", "xhttp"] {
            let profile = try VlessProfileParser.parse(profileURL.replacingOccurrences(of: "type=ws", with: "type=" + transport)).get()
            let socks = VlessLocalInbound(port: 21001, user: "user", password: "password")
            let http = VlessLocalInbound(port: 21002, user: "user", password: "password")
            let text = try XCTUnwrap(VlessXrayConfig.configJSON(profile: profile, socks: socks, http: http))
            let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            for inbound in json["inbounds"] as! [[String: Any]] {
                XCTAssertEqual(inbound["listen"] as? String, "127.0.0.1")
            }
            XCTAssertNil(VlessXrayConfig.configJSON(profile: profile, socks: socks, http: socks))
        }
    }

    func testSwitchingRunningProfileStartsReplacement() {
        let runtime = FakeRuntime()
        weak var observedManager: VlessManager?
        let first = expectation(description: "first profile")
        let second = expectation(description: "replacement profile")
        let secondURL = profileURL.replacingOccurrences(of: "example.com", with: "second.example.com")
        var seenFirst = false, seenSecond = false
        let manager = VlessManager(runtime: runtime, onStateChange: {
            guard let manager = observedManager else { return }
            if manager.isReady(for: profileURL), !seenFirst { seenFirst = true; first.fulfill() }
            if manager.isReady(for: secondURL), !seenSecond { seenSecond = true; second.fulfill() }
        })
        observedManager = manager
        manager.configure(activeProfileURL: profileURL)
        wait(for: [first], timeout: 5)
        manager.configure(activeProfileURL: secondURL)
        wait(for: [second], timeout: 5)
        XCTAssertFalse(manager.isReady(for: profileURL))
        manager.stop()
    }

    func testStoppingDuringStartupCannotPublishRunningState() {
        let runtime = FakeRuntime()
        runtime.gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "runtime entered")
        runtime.onStart = { entered.fulfill() }
        let manager = VlessManager(runtime: runtime)
        manager.start(url: profileURL)
        wait(for: [entered], timeout: 5)
        manager.stop()
        runtime.gate?.signal()
        let settled = expectation(description: "serialized stop")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(runtime.isRunning())
    }

    func testMalformedPortListFailsWithoutIndexingCrash() {
        let runtime = FakeRuntime(); runtime.ports = []
        let failed = expectation(description: "port validation")
        weak var observedManager: VlessManager?
        var observedFailure = false
        let manager = VlessManager(runtime: runtime, onStateChange: {
            guard let manager = observedManager else { return }
            // Notifications read the latest state; multiple queued transitions may
            // legitimately observe the same terminal state before this queue drains.
            if case .failed(.portAllocationFailed) = manager.state, !observedFailure {
                observedFailure = true
                failed.fulfill()
            }
        })
        observedManager = manager
        manager.start(url: profileURL)
        wait(for: [failed], timeout: 3)
        manager.stop()
    }
}
