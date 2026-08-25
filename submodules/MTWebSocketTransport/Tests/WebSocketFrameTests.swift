import XCTest
@testable import MTWebSocketTransport

final class WebSocketFrameTests: XCTestCase {
    func testSmallBinaryFrameRoundTrip() {
        let payload = Data([1, 2, 3, 4, 5])
        let key: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: true, maskKey: key)

        XCTAssertEqual(frame[frame.startIndex], 0x82)
        XCTAssertEqual(frame[frame.startIndex + 1], 0x80 | 5)

        guard case let .frame(header, decodedPayload, consumed) = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected a complete frame")
        }
        XCTAssertTrue(header.fin)
        XCTAssertEqual(header.opcode, .binary)
        XCTAssertTrue(header.masked)
        XCTAssertEqual(header.payloadLength, 5)
        XCTAssertEqual(decodedPayload, payload)
        XCTAssertEqual(consumed, frame.count)
    }

    func test126BytePayloadUsesExtended16BitLength() {
        let payload = Data(repeating: 0xAB, count: 200)
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: true)
        XCTAssertEqual(frame[frame.startIndex + 1] & 0x7F, 126)

        guard case let .frame(_, decodedPayload, consumed) = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected a complete frame")
        }
        XCTAssertEqual(decodedPayload, payload)
        XCTAssertEqual(consumed, frame.count)
    }

    func test65536BytePayloadUsesExtended64BitLength() {
        let payload = Data(repeating: 0xCD, count: 65536 + 10)
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: true)
        XCTAssertEqual(frame[frame.startIndex + 1] & 0x7F, 127)

        guard case let .frame(_, decodedPayload, consumed) = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected a complete frame")
        }
        XCTAssertEqual(decodedPayload, payload)
        XCTAssertEqual(consumed, frame.count)
    }

    func testUnmaskedFrameDecodesDirectly() {
        let payload = Data("hello".utf8)
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: false)
        guard case let .frame(header, decodedPayload, _) = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected a complete frame")
        }
        XCTAssertFalse(header.masked)
        XCTAssertEqual(decodedPayload, payload)
    }

    func testMaskingIsReversible() {
        let payload = Data((0 ..< 300).map { UInt8($0 % 256) })
        let key: [UInt8] = [9, 8, 7, 6]
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: true, maskKey: key)
        guard case let .frame(_, decodedPayload, _) = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected a complete frame")
        }
        XCTAssertEqual(decodedPayload, payload)
    }

    func testPingIsSurfacedForAutoPong() {
        let payload = Data("ping-body".utf8)
        let frame = WebSocketFrameEncoder.encode(opcode: .ping, payload: payload, mask: false)
        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(frame), [.ping(payload)])
    }

    func testPongIsSurfaced() {
        let payload = Data("pong-body".utf8)
        let frame = WebSocketFrameEncoder.encode(opcode: .pong, payload: payload, mask: false)
        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(frame), [.pong(payload)])
    }

    func testCloseFrameParsesCodeAndReason() {
        var payload = Data()
        payload.append(UInt8(1000 >> 8))
        payload.append(UInt8(1000 & 0xFF))
        payload.append(Data("bye".utf8))
        let frame = WebSocketFrameEncoder.encode(opcode: .close, payload: payload, mask: false)
        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(frame), [.close(code: 1000, reason: Data("bye".utf8))])
    }

    func testCloseFrameWithNoPayloadHasNilCodeAndReason() {
        let frame = WebSocketFrameEncoder.encode(opcode: .close, payload: Data(), mask: false)
        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(frame), [.close(code: nil, reason: nil)])
    }

    func testFragmentationReassemblesAcrossContinuationFrames() {
        let part1 = Data("Hello, ".utf8)
        let part2 = Data("world!".utf8)
        var stream = Data()
        stream.append(WebSocketFrameEncoder.encode(opcode: .binary, payload: part1, fin: false, mask: false))
        stream.append(WebSocketFrameEncoder.encode(opcode: .continuation, payload: part2, fin: true, mask: false))

        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(stream), [.message(opcode: .binary, data: part1 + part2)])
    }

    func testThreeWayFragmentation() {
        let parts = [Data("a".utf8), Data("b".utf8), Data("c".utf8)]
        var stream = Data()
        stream.append(WebSocketFrameEncoder.encode(opcode: .binary, payload: parts[0], fin: false, mask: false))
        stream.append(WebSocketFrameEncoder.encode(opcode: .continuation, payload: parts[1], fin: false, mask: false))
        stream.append(WebSocketFrameEncoder.encode(opcode: .continuation, payload: parts[2], fin: true, mask: false))

        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(stream), [.message(opcode: .binary, data: Data("abc".utf8))])
    }

    func testPartialInputAcrossMultipleFeeds() {
        let payload = Data((0 ..< 500).map { UInt8($0 % 256) })
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: true)
        let reassembler = WebSocketMessageReassembler()

        let splitPoint = frame.count / 2
        let firstHalf = Data(frame.prefix(splitPoint))
        let secondHalf = Data(frame.suffix(from: frame.startIndex + splitPoint))

        XCTAssertEqual(reassembler.feed(firstHalf), [])
        XCTAssertEqual(reassembler.feed(secondHalf), [.message(opcode: .binary, data: payload)])
    }

    func testByteAtATimeFeedStillReassembles() {
        let payload = Data("streamed byte by byte".utf8)
        let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: payload, mask: true)
        let reassembler = WebSocketMessageReassembler()

        var events: [WebSocketMessageReassembler.Event] = []
        for byte in frame {
            events.append(contentsOf: reassembler.feed(Data([byte])))
        }
        XCTAssertEqual(events, [.message(opcode: .binary, data: payload)])
    }

    func testMultipleFramesDeliveredInOneBuffer() {
        let payloadA = Data("frame-a".utf8)
        let payloadB = Data("frame-b".utf8)
        var stream = Data()
        stream.append(WebSocketFrameEncoder.encode(opcode: .binary, payload: payloadA, mask: false))
        stream.append(WebSocketFrameEncoder.encode(opcode: .binary, payload: payloadB, mask: false))

        let reassembler = WebSocketMessageReassembler()
        XCTAssertEqual(reassembler.feed(stream), [
            .message(opcode: .binary, data: payloadA),
            .message(opcode: .binary, data: payloadB),
        ])
    }

    func testReservedBitsAreRejected() {
        var frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: Data("x".utf8), mask: false)
        frame[frame.startIndex] |= 0x40
        guard case .invalid = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected an invalid-frame result")
        }
    }

    func testUnknownOpcodeIsRejected() {
        var frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: Data("x".utf8), mask: false)
        frame[frame.startIndex] = (frame[frame.startIndex] & 0xF0) | 0x3
        guard case .invalid = WebSocketFrameDecoder.parseFrame(from: frame) else {
            return XCTFail("expected an invalid-frame result")
        }
    }

    func testOversizedFrameIsRejected() {
        var frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: Data([0]), mask: false)
        // Overwrite the (already-encoded) length field with a 64-bit length far past the 16MiB cap.
        frame[frame.startIndex + 1] = 127
        let hugeLength: UInt64 = 64 * 1024 * 1024
        var extended = Data()
        for shift in stride(from: 56, through: 0, by: -8) {
            extended.append(UInt8((hugeLength >> UInt64(shift)) & 0xFF))
        }
        var rebuilt = Data([frame[frame.startIndex], frame[frame.startIndex + 1]])
        rebuilt.append(extended)
        guard case .invalid = WebSocketFrameDecoder.parseFrame(from: rebuilt) else {
            return XCTFail("expected an invalid-frame result")
        }
    }

    func testEmptyBufferNeedsMoreData() {
        guard case .needsMoreData = WebSocketFrameDecoder.parseFrame(from: Data()) else {
            return XCTFail("expected needsMoreData")
        }
    }
}
