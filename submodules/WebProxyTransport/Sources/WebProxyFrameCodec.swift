import Foundation

public enum WebProxyFrameType: UInt8 {
    case open = 0x01
    case data = 0x02
    case close = 0x03
    case window = 0x04
    case ping = 0x05
    case pong = 0x06
    case hello = 0x10
    case welcome = 0x11
    case bye = 0x1f
}

public struct WebProxyFrame: Equatable {
    public let type: WebProxyFrameType
    public let streamId: UInt32
    public let payload: Data
    
    public init(type: WebProxyFrameType, streamId: UInt32, payload: Data) {
        self.type = type
        self.streamId = streamId
        self.payload = payload
    }
    
    public static func hello() -> WebProxyFrame {
        return WebProxyFrame(type: .hello, streamId: 0, payload: Data([0x01]))
    }
}

public enum WebProxyFrameCodecError: Error {
    case bufferTooShort
    case invalidFrameType
    case invalidPayloadSize
    case invalidBatch
}

public enum WebProxyFrameCodec {
    public static let maxPayloadSize = 1_048_576
    public static let maxDataChunkSize = 65_536
    public static let maxBatchFrames = 4096
    
    public static func encode(_ frame: WebProxyFrame) -> Data {
        var data = Data(capacity: 8 + frame.payload.count)
        appendEncoded(frame, to: &data)
        return data
    }
    
    /// Appends into an existing buffer so a batch is one allocation rather than one per frame.
    private static func appendEncoded(_ frame: WebProxyFrame, to data: inout Data) {
        // Soft-skip instead of precondition: a long-lived soft-reconnect path used to mint
        // stream ids past the 24-bit wire limit and SIGABRT the process. Callers that still
        // overflow after the sidecar's allocateStreamId clamp must not take the app down.
        guard frame.streamId <= 0xffffff, frame.payload.count <= maxPayloadSize else {
            return
        }
        data.append(frame.type.rawValue)
        data.append(UInt8((frame.streamId >> 16) & 0xff))
        data.append(UInt8((frame.streamId >> 8) & 0xff))
        data.append(UInt8(frame.streamId & 0xff))
        var length = UInt32(frame.payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(frame.payload)
    }
    
    public static func encodeBatch(_ frames: [WebProxyFrame]) -> Data {
        var data = Data(capacity: frames.reduce(0) { $0 + 8 + $1.payload.count })
        for frame in frames {
            appendEncoded(frame, to: &data)
        }
        return data
    }
    
    public static func decodeBatch(_ data: Data) throws -> [WebProxyFrame] {
        var frames: [WebProxyFrame] = []
        var offset = 0
        // `Data` subscripts by index, not by offset from the front, so every read is rebased on
        // `startIndex`. Without it this only worked while every caller happened to pass a
        // zero-based buffer - a slice would have been read from the wrong bytes or trapped.
        let base = data.startIndex
        while offset < data.count {
            let remaining = data.count - offset
            if remaining < 8 {
                throw WebProxyFrameCodecError.bufferTooShort
            }
            guard let type = WebProxyFrameType(rawValue: data[base + offset]) else {
                throw WebProxyFrameCodecError.invalidFrameType
            }
            let streamId = (UInt32(data[base + offset + 1]) << 16) | (UInt32(data[base + offset + 2]) << 8) | UInt32(data[base + offset + 3])
            let payloadSize = Int(readUInt32BigEndian(data, base + offset + 4))
            if payloadSize > maxPayloadSize || (type == .data && payloadSize == 0) {
                throw WebProxyFrameCodecError.invalidPayloadSize
            }
            let end = offset + 8 + payloadSize
            if end > data.count {
                throw WebProxyFrameCodecError.bufferTooShort
            }
            let payload = data.subdata(in: (base + offset + 8) ..< (base + end))
            frames.append(WebProxyFrame(type: type, streamId: streamId, payload: payload))
            offset = end
            if frames.count > maxBatchFrames {
                throw WebProxyFrameCodecError.invalidBatch
            }
        }
        if frames.isEmpty {
            throw WebProxyFrameCodecError.invalidBatch
        }
        return frames
    }
    
    /// `index` is an absolute `Data` index, already rebased on `startIndex` by the caller.
    private static func readUInt32BigEndian(_ data: Data, _ index: Int) -> UInt32 {
        return (UInt32(data[index]) << 24) | (UInt32(data[index + 1]) << 16) | (UInt32(data[index + 2]) << 8) | UInt32(data[index + 3])
    }
}
