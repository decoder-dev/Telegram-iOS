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
        precondition(frame.streamId <= 0xffffff)
        precondition(frame.payload.count <= maxPayloadSize)
        var data = Data(capacity: 8 + frame.payload.count)
        data.append(frame.type.rawValue)
        data.append(UInt8((frame.streamId >> 16) & 0xff))
        data.append(UInt8((frame.streamId >> 8) & 0xff))
        data.append(UInt8(frame.streamId & 0xff))
        var length = UInt32(frame.payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(frame.payload)
        return data
    }
    
    public static func encodeBatch(_ frames: [WebProxyFrame]) -> Data {
        var data = Data()
        for frame in frames {
            data.append(encode(frame))
        }
        return data
    }
    
    public static func decodeBatch(_ data: Data) throws -> [WebProxyFrame] {
        var frames: [WebProxyFrame] = []
        var offset = 0
        while offset < data.count {
            let remaining = data.count - offset
            if remaining < 8 {
                throw WebProxyFrameCodecError.bufferTooShort
            }
            guard let type = WebProxyFrameType(rawValue: data[offset]) else {
                throw WebProxyFrameCodecError.invalidFrameType
            }
            let streamId = (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
            let payloadSize = Int(readUInt32BigEndian(data, offset + 4))
            if payloadSize > maxPayloadSize || (type == .data && payloadSize == 0) {
                throw WebProxyFrameCodecError.invalidPayloadSize
            }
            let end = offset + 8 + payloadSize
            if end > data.count {
                throw WebProxyFrameCodecError.bufferTooShort
            }
            let payload = data.subdata(in: (offset + 8) ..< end)
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
    
    private static func readUInt32BigEndian(_ data: Data, _ offset: Int) -> UInt32 {
        return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}
