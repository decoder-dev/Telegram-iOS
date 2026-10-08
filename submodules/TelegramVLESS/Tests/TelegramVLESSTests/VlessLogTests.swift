import XCTest
@testable import TelegramVLESS

final class VlessLogTests: XCTestCase {
    func testOptionalSinkAndReentrantReplacement() {
        let previous = VlessLog.handler
        defer { VlessLog.handler = previous }
        VlessLog.handler = nil
        var evaluations = 0
        func message() -> String {
            evaluations += 1
            return "runtime ready"
        }
        VlessLog.log(message())
        XCTAssertEqual(evaluations, 0)

        var received: [String] = []
        VlessLog.handler = { text in
            received.append(text)
            VlessLog.handler = nil
        }
        VlessLog.log(message())
        VlessLog.log(message())
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(received, ["runtime ready"])
    }
}
