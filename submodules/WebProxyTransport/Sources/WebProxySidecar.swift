import Foundation
import Network

private final class WebProxyStream {
    let id: UInt32
    let connection: NWConnection
    var receiveBuffer = Data()
    var pendingWrite = Data()
    var isWriting = false
    var isClosed = false
    /// Uplink credit granted by the relay, in bytes. Both directions open with an implicit 4 MiB
    /// window; `DATA` spends it and `WINDOW` grants it back.
    var sendCredit: Int = WebProxySidecar.initialStreamWindow
    /// Bytes read off the local socket that have no credit to travel on yet.
    var pendingUplink = Data()
    
    init(id: UInt32, connection: NWConnection) {
        self.id = id
        self.connection = connection
    }
}

public final class WebProxySidecar {
    public struct Endpoint: Equatable {
        public let host: String
        public let port: UInt16
        
        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }
    
    private let queue = DispatchQueue(label: "WebProxySidecar", qos: .userInitiated)
    private var listener: NWListener?
    private var carrier: WebProxyHttpCarrier?
    private var urlSession: URLSession?
    private var streams: [UInt32: WebProxyStream] = [:]
    private var nextStreamId: UInt32 = 1
    private var endpoint: Endpoint?
    private var onFailure: (() -> Void)?
    
    /// Implicit per-stream window both directions start with, per the shared relay contract.
    static let initialStreamWindow = 4 * 1024 * 1024
    /// A stream whose uplink backs up past this is failed rather than buffered without bound.
    private static let maximumPendingUplink = 8 * 1024 * 1024
    
    public init() {
    }
    
    public func start(hostname: String, secret: Data, bridgeCapability: String, completion: @escaping (Result<Endpoint, Error>) -> Void) {
        self.queue.async {
            self.stopLocked()
            do {
                let config = URLSessionConfiguration.ephemeral
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                config.urlCache = nil
                config.httpCookieAcceptPolicy = .never
                config.httpShouldSetCookies = false
                config.timeoutIntervalForRequest = 90.0
                config.timeoutIntervalForResource = 300.0
                let urlSession = URLSession(configuration: config)
                let carrier = try WebProxyHttpCarrier(hostname: hostname, session: urlSession, queue: self.queue)
                carrier.onDownlinkBatch = { [weak self] batch in
                    self?.handleDownlinkBatch(batch)
                }
                carrier.onFailure = { [weak self] _ in
                    self?.queue.async {
                        self?.onFailure?()
                        self?.stopLocked()
                    }
                }
                
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection: connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else {
                        return
                    }
                    switch state {
                    case .failed:
                        self.queue.async {
                            self.onFailure?()
                            self.stopLocked()
                        }
                    default:
                        break
                    }
                }
                
                self.urlSession = urlSession
                self.carrier = carrier
                self.listener = listener
                
                listener.start(queue: self.queue)
                
                carrier.start(secret: secret, bridgeCapability: bridgeCapability) { [weak self] result in
                    guard let self else {
                        return
                    }
                    self.queue.async {
                        switch result {
                        case .success:
                            guard let port = listener.port?.rawValue else {
                                completion(.failure(WebProxyHttpCarrierError.sessionCreationFailed))
                                self.stopLocked()
                                return
                            }
                            let endpoint = Endpoint(host: "127.0.0.1", port: port)
                            self.endpoint = endpoint
                            completion(.success(endpoint))
                        case let .failure(error):
                            self.stopLocked()
                            completion(.failure(error))
                        }
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    public func stop() {
        self.queue.async {
            self.stopLocked()
        }
    }
    
    public func setFailureHandler(_ handler: @escaping () -> Void) {
        self.queue.async {
            self.onFailure = handler
        }
    }
    
    private func stopLocked() {
        self.carrier?.stop()
        self.carrier = nil
        self.listener?.cancel()
        self.listener = nil
        self.urlSession?.invalidateAndCancel()
        self.urlSession = nil
        for stream in self.streams.values {
            stream.connection.cancel()
        }
        self.streams.removeAll()
        self.nextStreamId = 1
        self.endpoint = nil
    }
    
    private func accept(connection: NWConnection) {
        let streamId = self.nextStreamId
        self.nextStreamId &+= 1
        if self.nextStreamId == 0 {
            self.nextStreamId = 1
        }
        let stream = WebProxyStream(id: streamId, connection: connection)
        self.streams[streamId] = stream
        self.sendFrames([WebProxyFrame(type: .open, streamId: streamId, payload: Data())])
        
        connection.stateUpdateHandler = { [weak self, weak stream] state in
            guard let self, let stream else {
                return
            }
            switch state {
            case .ready:
                self.receive(from: stream)
            case .failed, .cancelled:
                self.queue.async {
                    self.closeStream(streamId, notifyRemote: true)
                }
            default:
                break
            }
        }
        connection.start(queue: self.queue)
    }
    
    private func receive(from stream: WebProxyStream) {
        stream.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak stream] data, _, isComplete, error in
            guard let self, let stream else {
                return
            }
            self.queue.async {
                if stream.isClosed {
                    return
                }
                if let data = data, !data.isEmpty {
                    self.sendStreamData(streamId: stream.id, data: data)
                }
                if isComplete || error != nil {
                    self.closeStream(stream.id, notifyRemote: true)
                    return
                }
                self.receive(from: stream)
            }
        }
    }
    
    private func sendStreamData(streamId: UInt32, data: Data) {
        guard let stream = self.streams[streamId], !stream.isClosed else {
            return
        }
        if stream.pendingUplink.count + data.count > WebProxySidecar.maximumPendingUplink {
            // The relay has stopped granting credit and this stream has buffered more than the
            // contract allows. Failing it here keeps one stalled socket from growing without
            // bound; MTProto reconnects the session like any other dropped connection.
            self.closeStream(streamId, notifyRemote: true)
            return
        }
        stream.pendingUplink.append(data)
        self.flushUplink(stream: stream)
    }
    
    /// Emits queued uplink as `DATA` frames while the relay's credit lasts, in chunks of at most
    /// 64 KiB. Whatever credit does not cover stays queued until a `WINDOW` frame grants more.
    private func flushUplink(stream: WebProxyStream) {
        var frames: [WebProxyFrame] = []
        while !stream.pendingUplink.isEmpty, stream.sendCredit > 0 {
            let chunkSize = min(min(WebProxyFrameCodec.maxDataChunkSize, stream.sendCredit), stream.pendingUplink.count)
            let chunk = Data(stream.pendingUplink.prefix(chunkSize))
            stream.pendingUplink = Data(stream.pendingUplink.dropFirst(chunkSize))
            stream.sendCredit -= chunkSize
            frames.append(WebProxyFrame(type: .data, streamId: stream.id, payload: chunk))
        }
        if !frames.isEmpty {
            self.sendFrames(frames)
        }
    }
    
    private func sendFrames(_ frames: [WebProxyFrame]) {
        guard let carrier = self.carrier else {
            return
        }
        carrier.sendFrames(WebProxyFrameCodec.encodeBatch(frames))
    }
    
    private func handleDownlinkBatch(_ batch: Data) {
        guard let frames = try? WebProxyFrameCodec.decodeBatch(batch) else {
            self.onFailure?()
            self.stopLocked()
            return
        }
        for frame in frames {
            switch frame.type {
            case .data:
                self.write(streamId: frame.streamId, data: frame.payload)
            case .close:
                self.closeStream(frame.streamId, notifyRemote: false)
            case .window:
                self.grantUplinkCredit(streamId: frame.streamId, payload: frame.payload)
            case .ping:
                // `PONG` is the exact response to a `PING`, payload included, whatever its size —
                // the previous four-byte requirement dropped keepalives the relay would then time
                // out on.
                self.sendFrames([WebProxyFrame(type: .pong, streamId: frame.streamId, payload: frame.payload)])
            case .bye:
                // The relay is closing the carrier: fail every logical stream and tear down, so the
                // manager reports the failure instead of leaving sockets hanging on a dead session.
                self.onFailure?()
                self.stopLocked()
                return
            default:
                break
            }
        }
    }
    
    private func grantUplinkCredit(streamId: UInt32, payload: Data) {
        guard payload.count == 4, let stream = self.streams[streamId], !stream.isClosed else {
            return
        }
        let base = payload.startIndex
        let delta = (Int(payload[base]) << 24) | (Int(payload[base + 1]) << 16) | (Int(payload[base + 2]) << 8) | Int(payload[base + 3])
        guard delta > 0 else {
            return
        }
        stream.sendCredit += delta
        self.flushUplink(stream: stream)
    }
    
    private func write(streamId: UInt32, data: Data) {
        guard let stream = self.streams[streamId], !stream.isClosed else {
            return
        }
        stream.pendingWrite.append(data)
        self.flushWrite(stream: stream)
    }
    
    private func flushWrite(stream: WebProxyStream) {
        if stream.isWriting || stream.pendingWrite.isEmpty || stream.isClosed {
            return
        }
        stream.isWriting = true
        let chunk = stream.pendingWrite
        stream.pendingWrite = Data()
        stream.connection.send(content: chunk, completion: .contentProcessed { [weak self, weak stream] error in
            guard let self, let stream else {
                return
            }
            self.queue.async {
                stream.isWriting = false
                if error != nil {
                    self.closeStream(stream.id, notifyRemote: true)
                    return
                }
                // Downlink credit is returned only once the bytes have actually reached the local
                // socket, which is what bounds unread data per stream. Without this the relay
                // spends its implicit 4 MiB window and then stops sending — a large download
                // stalled part-way with the connection still nominally up.
                if !stream.isClosed, !chunk.isEmpty {
                    self.sendWindowCredit(streamId: stream.id, bytes: chunk.count)
                }
                self.flushWrite(stream: stream)
            }
        })
    }
    
    private func sendWindowCredit(streamId: UInt32, bytes: Int) {
        let delta = UInt32(clamping: bytes)
        var payload = Data(capacity: 4)
        payload.append(UInt8((delta >> 24) & 0xff))
        payload.append(UInt8((delta >> 16) & 0xff))
        payload.append(UInt8((delta >> 8) & 0xff))
        payload.append(UInt8(delta & 0xff))
        self.sendFrames([WebProxyFrame(type: .window, streamId: streamId, payload: payload)])
    }
    
    private func closeStream(_ streamId: UInt32, notifyRemote: Bool) {
        guard let stream = self.streams.removeValue(forKey: streamId) else {
            return
        }
        if stream.isClosed {
            return
        }
        stream.isClosed = true
        stream.pendingUplink = Data()
        stream.pendingWrite = Data()
        stream.connection.cancel()
        if notifyRemote {
            self.sendFrames([WebProxyFrame(type: .close, streamId: streamId, payload: Data())])
        }
    }
}
