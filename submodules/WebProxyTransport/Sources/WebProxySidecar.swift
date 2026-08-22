import Foundation
import Network

private final class WebProxyStream {
    let id: UInt32
    let connection: NWConnection
    var receiveBuffer = Data()
    var pendingWrite = Data()
    var isWriting = false
    var isClosed = false
    
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
        var offset = 0
        while offset < data.count {
            let chunkSize = min(WebProxyFrameCodec.maxDataChunkSize, data.count - offset)
            let chunk = data.subdata(in: offset ..< (offset + chunkSize))
            self.sendFrames([WebProxyFrame(type: .data, streamId: streamId, payload: chunk)])
            offset += chunkSize
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
                break
            case .ping:
                if frame.payload.count == 4 {
                    self.sendFrames([WebProxyFrame(type: .pong, streamId: 0, payload: frame.payload)])
                }
            default:
                break
            }
        }
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
                self.flushWrite(stream: stream)
            }
        })
    }
    
    private func closeStream(_ streamId: UInt32, notifyRemote: Bool) {
        guard let stream = self.streams.removeValue(forKey: streamId) else {
            return
        }
        if stream.isClosed {
            return
        }
        stream.isClosed = true
        stream.connection.cancel()
        if notifyRemote {
            self.sendFrames([WebProxyFrame(type: .close, streamId: streamId, payload: Data())])
        }
    }
}
