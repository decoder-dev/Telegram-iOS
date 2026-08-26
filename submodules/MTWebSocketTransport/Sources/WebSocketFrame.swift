import Foundation

/// RFC 6455 opcodes used by the Telegram WebSocket transport (`kwsN.web.telegram.org`).
public enum WebSocketOpcode: UInt8, Equatable {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

public struct WebSocketFrameHeader: Equatable {
    public let fin: Bool
    public let opcode: WebSocketOpcode
    public let masked: Bool
    public let payloadLength: Int
}

public enum WebSocketFrameParseResult {
    case needsMoreData
    case invalid(String)
    case frame(header: WebSocketFrameHeader, payload: Data, consumed: Int)
}

/// Pure RFC 6455 frame encoder/decoder. No networking, no state beyond a single call — the caller
/// (`WebSocketMessageReassembler`) owns buffering and fragmentation reassembly.
public enum WebSocketFrameEncoder {
    /// Encodes a single frame. Outbound frames from a real client MUST be masked per RFC 6455 §5.1;
    /// `mask: false` exists only so tests can synthesize server-style frames to feed the decoder.
    /// Unlike the decoder, encoding has no payload-size cap: the caller (MtProtoKit's existing framing)
    /// is trusted, whereas the decoder's cap guards against a hostile/corrupted length field on
    /// untrusted inbound data.
    public static func encode(opcode: WebSocketOpcode, payload: Data, fin: Bool = true, mask: Bool, maskKey: [UInt8]? = nil) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(14)

        bytes.append((fin ? 0x80 : 0x00) | opcode.rawValue)

        let length = payload.count
        let maskBit: UInt8 = mask ? 0x80 : 0x00
        if length < 126 {
            bytes.append(maskBit | UInt8(length))
        } else if length <= 0xFFFF {
            bytes.append(maskBit | 126)
            bytes.append(UInt8((length >> 8) & 0xFF))
            bytes.append(UInt8(length & 0xFF))
        } else {
            bytes.append(maskBit | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8((UInt64(length) >> UInt64(shift)) & 0xFF))
            }
        }

        // `bytes` holds only the header (at most 14 bytes). The payload is appended to the result
        // directly and masked in place, so an outgoing frame copies the payload once rather than three
        // times — through a `[UInt8]` mask buffer, into the header array, and again into a `Data`.
        // This is the file-upload path, so those copies are the size of every byte the app sends.
        var frame = Data()
        frame.reserveCapacity(bytes.count + payload.count)

        if mask {
            let key = maskKey ?? WebSocketFrameEncoder.randomMaskKey()
            precondition(key.count == 4, "WebSocket mask key must be 4 bytes")
            bytes.append(contentsOf: key)

            frame.append(contentsOf: bytes)
            let payloadStart = frame.count
            frame.append(payload)
            if !payload.isEmpty {
                frame.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                    let out = raw.bindMemory(to: UInt8.self)
                    for i in 0 ..< payload.count {
                        out[payloadStart + i] ^= key[i & 3]
                    }
                }
            }
        } else {
            frame.append(contentsOf: bytes)
            frame.append(payload)
        }

        return frame
    }

    public static func randomMaskKey() -> [UInt8] {
        return [UInt8.random(in: 0...255), UInt8.random(in: 0...255), UInt8.random(in: 0...255), UInt8.random(in: 0...255)]
    }
}

public enum WebSocketFrameDecoder {
    private static let maxPayloadLength = 16 * 1024 * 1024

    /// Attempts to parse a single frame from the front of `buffer`. Never mutates `buffer` — the caller
    /// removes exactly `consumed` bytes once it accepts the result. Index arithmetic is relative to
    /// `buffer.startIndex` throughout, since `Data` does not guarantee zero-based indices after slicing.
    public static func parseFrame(from buffer: Data) -> WebSocketFrameParseResult {
        let start = buffer.startIndex
        let count = buffer.count
        if count < 2 {
            return .needsMoreData
        }

        let byte0 = buffer[start]
        let byte1 = buffer[start + 1]

        let fin = (byte0 & 0x80) != 0
        let rsv = byte0 & 0x70
        if rsv != 0 {
            return .invalid("non-zero RSV bits without a negotiated extension")
        }
        guard let opcode = WebSocketOpcode(rawValue: byte0 & 0x0F) else {
            return .invalid("unsupported opcode 0x\(String(byte0 & 0x0F, radix: 16))")
        }

        let masked = (byte1 & 0x80) != 0
        let lengthField = Int(byte1 & 0x7F)

        var offset = 2
        var payloadLength: Int
        if lengthField == 126 {
            if count < offset + 2 {
                return .needsMoreData
            }
            payloadLength = Int(buffer[start + offset]) << 8 | Int(buffer[start + offset + 1])
            offset += 2
        } else if lengthField == 127 {
            if count < offset + 8 {
                return .needsMoreData
            }
            var length: UInt64 = 0
            for i in 0 ..< 8 {
                length = (length << 8) | UInt64(buffer[start + offset + i])
            }
            if length > UInt64(Int.max) {
                return .invalid("frame payload length overflow")
            }
            payloadLength = Int(length)
            offset += 8
        } else {
            payloadLength = lengthField
        }

        if payloadLength > WebSocketFrameDecoder.maxPayloadLength {
            return .invalid("frame payload of \(payloadLength) bytes exceeds the \(WebSocketFrameDecoder.maxPayloadLength)-byte limit")
        }
        if (opcode == .close || opcode == .ping || opcode == .pong) && (!fin || payloadLength > 125) {
            return .invalid("control frame must be final and <=125 bytes")
        }

        var maskKey: [UInt8]? = nil
        if masked {
            if count < offset + 4 {
                return .needsMoreData
            }
            maskKey = [buffer[start + offset], buffer[start + offset + 1], buffer[start + offset + 2], buffer[start + offset + 3]]
            offset += 4
        }

        if count < offset + payloadLength {
            return .needsMoreData
        }

        var payload = buffer.subdata(in: (start + offset) ..< (start + offset + payloadLength))
        if let maskKey = maskKey {
            payload.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                let ptr = raw.bindMemory(to: UInt8.self)
                for i in 0 ..< ptr.count {
                    ptr[i] = ptr[i] ^ maskKey[i % 4]
                }
            }
        }

        let header = WebSocketFrameHeader(fin: fin, opcode: opcode, masked: masked, payloadLength: payloadLength)
        return .frame(header: header, payload: payload, consumed: offset + payloadLength)
    }
}

/// Buffers incoming bytes, splits them into frames via `WebSocketFrameDecoder`, and reassembles
/// fragmented (continuation-frame) messages into single logical events. This is the only stateful
/// piece of the framing layer; everything else is pure functions over `Data`.
public final class WebSocketMessageReassembler {
    public enum Event: Equatable {
        case message(opcode: WebSocketOpcode, data: Data)
        case ping(Data)
        case pong(Data)
        case close(code: UInt16?, reason: Data?)
        case protocolError(String)
    }

    private var buffer = Data()
    private var fragmentedOpcode: WebSocketOpcode?
    private var fragmentedPayload = Data()

    public init() {}

    /// Feeds newly-received bytes (which may contain zero, one, or many complete frames, and may split
    /// a frame across calls) and returns every event that became decodable as a result.
    public func feed(_ data: Data) -> [Event] {
        self.buffer.append(data)

        var events: [Event] = []
        parseLoop: while true {
            switch WebSocketFrameDecoder.parseFrame(from: self.buffer) {
            case .needsMoreData:
                break parseLoop
            case let .invalid(reason):
                // A framing error means the peer is not speaking what we think it is. The buffer is
                // dropped either way, so this is the only moment the reason exists.
                WebSocketTransportLog.log("framing rejected after \(self.buffer.count) buffered bytes: \(reason)")
                events.append(.protocolError(reason))
                self.buffer.removeAll()
                break parseLoop
            case let .frame(header, payload, consumed):
                self.buffer.removeFirst(consumed)

                switch header.opcode {
                case .continuation:
                    guard let opcode = self.fragmentedOpcode else {
                        events.append(.protocolError("continuation frame without an initiating fragment"))
                        continue parseLoop
                    }
                    self.fragmentedPayload.append(payload)
                    if header.fin {
                        events.append(.message(opcode: opcode, data: self.fragmentedPayload))
                        self.fragmentedOpcode = nil
                        self.fragmentedPayload = Data()
                    }
                case .text, .binary:
                    if self.fragmentedOpcode != nil {
                        events.append(.protocolError("new data frame started before the previous fragmented message finished"))
                        self.fragmentedOpcode = nil
                        self.fragmentedPayload = Data()
                        continue parseLoop
                    }
                    if header.fin {
                        events.append(.message(opcode: header.opcode, data: payload))
                    } else {
                        self.fragmentedOpcode = header.opcode
                        self.fragmentedPayload = payload
                    }
                case .ping:
                    events.append(.ping(payload))
                case .pong:
                    events.append(.pong(payload))
                case .close:
                    var code: UInt16? = nil
                    var reason: Data? = nil
                    if payload.count >= 2 {
                        let payloadStart = payload.startIndex
                        code = UInt16(payload[payloadStart]) << 8 | UInt16(payload[payloadStart + 1])
                        if payload.count > 2 {
                            reason = payload.subdata(in: (payloadStart + 2) ..< payload.endIndex)
                        }
                    }
                    events.append(.close(code: code, reason: reason))
                }
            }
        }
        return events
    }
}
