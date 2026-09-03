import Foundation
import Network

import MtProtoKit
import SwiftSignalKit
import MTWebSocketTransport

/// Tracks "every WS endpoint failed" outcomes across reconnect attempts and tells `Network.swift`'s
/// `makeTcpConnectionInterface` closure when to stop returning a WebSocket interface for the rest of
/// the session (only consulted when the user has enabled "fall back to direct transport"). One instance
/// is owned by `Network` and shared by every `MTWebSocketConnectionInterface` it spawns.
final class MTWebSocketFallbackCoordinator {
    /// Failures are reported per connection, and MTProto keeps several open at once — master, media,
    /// and download workers. A single network event therefore reports three or four failures within
    /// the same instant, which would reach the threshold on its own. Failures landing inside this
    /// window after a counted one are collapsed into it, so "3 consecutive failures" means three
    /// separate attempts rather than one attempt across three sockets.
    private static let failureCoalescingInterval: Double = 5.0

    /// Falling back is not the end of it. What makes WebSocket fail is a property of the network the
    /// device is on — a blocked host, a middlebox, a captive portal — and that is exactly the kind of
    /// thing that changes underneath a running app: the user leaves the network, moves between
    /// cellular and Wi-Fi, lands in another country. A door that only ever shuts left them on the
    /// transport they turned this feature on to avoid, for the rest of the process, with nothing in
    /// the app to say so and nothing they could do but relaunch it.
    ///
    /// So the fallback re-opens on its own. After the wait below one connection is let through while
    /// the rest stay on the working transport; if it carries traffic the fallback is lifted, and if
    /// it does not the wait doubles up to a ceiling. The first wait is long enough that a genuinely
    /// blocked network costs one probe every couple of minutes rather than a reconnect storm, and
    /// the ceiling keeps a device that never recovers down to one probe every half hour.
    private static let initialFallbackRetryInterval: Double = 120.0
    private static let maximumFallbackRetryInterval: Double = 1800.0

    private struct State {
        var policy = WebSocketFallbackPolicy()
        var lastCountedFailureTimestamp: Double?
        /// When the fallback was last engaged. Nil while WebSocket is in use.
        var fallbackSince: Double?
        var fallbackRetryInterval: Double = MTWebSocketFallbackCoordinator.initialFallbackRetryInterval
        /// A probe has been let through and has not yet reported an outcome, so no second one is.
        var isProbing = false
    }

    private let state = Atomic<State>(value: State())

    /// Whether a connection being opened now may use WebSocket.
    ///
    /// This consumes a probe permission, so it is a method rather than a property: while the
    /// fallback is engaged it answers true exactly once per wait, and false to everything else until
    /// that attempt has reported success or failure.
    func shouldAttemptWebSocket() -> Bool {
        let timestamp = CFAbsoluteTimeGetCurrent()
        var grantedProbe = false
        let state = self.state.modify { state in
            var state = state
            guard let fallbackSince = state.fallbackSince else {
                return state
            }
            if !state.isProbing, timestamp - fallbackSince >= state.fallbackRetryInterval {
                state.isProbing = true
                grantedProbe = true
            }
            return state
        }
        if state.fallbackSince == nil {
            return true
        }
        if grantedProbe {
            Logger.shared.log("MTWebSocket", "[WS] probing whether WebSocket works again after \(Int(state.fallbackRetryInterval))s on direct transport")
        }
        return grantedProbe
    }

    func abortProbe() {
        _ = self.state.modify { state in
            var state = state
            if state.isProbing {
                // Clear the probe slot without backing off further — MTProto asked us to close
                // (path rebuild / pause / short-lived media worker), not a network failure.
                state.isProbing = false
            }
            return state
        }
    }

    func recordAllEndpointsFailed() {
        let timestamp = CFAbsoluteTimeGetCurrent()
        var engagedFallback = false
        var probeFailed = false
        let state = self.state.modify { state in
            var state = state
            if state.isProbing {
                // The one connection let through to test the water went down with everything else.
                // Stay in the fallback and wait longer before spending another.
                state.isProbing = false
                state.fallbackSince = timestamp
                state.fallbackRetryInterval = min(
                    MTWebSocketFallbackCoordinator.maximumFallbackRetryInterval,
                    state.fallbackRetryInterval * 2.0
                )
                probeFailed = true
                return state
            }
            if state.fallbackSince != nil {
                // Already fallen back and not probing: these are the other connections failing
                // alongside, and they have nothing to add.
                return state
            }
            if let last = state.lastCountedFailureTimestamp, timestamp - last < MTWebSocketFallbackCoordinator.failureCoalescingInterval {
                return state
            }
            state.lastCountedFailureTimestamp = timestamp
            if state.policy.recordAllEndpointsFailed() {
                state.fallbackSince = timestamp
                state.fallbackRetryInterval = MTWebSocketFallbackCoordinator.initialFallbackRetryInterval
                engagedFallback = true
            }
            return state
        }
        if engagedFallback {
            Logger.shared.log("MTWebSocket", "[WS] no endpoint carried traffic on \(state.policy.consecutiveTotalFailures) attempts in a row, falling back to direct transport; will probe again in \(Int(state.fallbackRetryInterval))s")
        } else if probeFailed {
            Logger.shared.log("MTWebSocket", "[WS] probe failed, staying on direct transport; next probe in \(Int(state.fallbackRetryInterval))s")
        }
    }

    func recordSuccess() {
        var liftedFallback = false
        _ = self.state.modify { state in
            var state = state
            state.policy.recordSuccess()
            state.lastCountedFailureTimestamp = nil
            if state.fallbackSince != nil {
                // Whatever was in the way is gone: the probe carried MTProto traffic.
                state.fallbackSince = nil
                state.isProbing = false
                state.fallbackRetryInterval = MTWebSocketFallbackCoordinator.initialFallbackRetryInterval
                liftedFallback = true
            }
            return state
        }
        if liftedFallback {
            Logger.shared.log("MTWebSocket", "[WS] probe carried traffic, WebSocket transport is back in use")
        }
    }
}

/// `MTTcpConnectionInterface` implementation that carries MtProtoKit's already-framed/obfuscated byte
/// stream over a WebSocket connection to `kwsN.web.telegram.org` (or `kwsN-1...`) instead of a raw TCP
/// socket. All MTProto packet framing, obfuscation and crypto stay in `MTTcpConnection` above this
/// class, untouched — see `docs/websocket-transport.md` for the full architecture rationale.
///
/// `inHost`/`port` passed to `connect(toHost:onPort:...)` are the literal Telegram DC IP MTTcpConnection
/// resolved for the normal TCP path; they are meaningless for a WS front-end whose hostname/IP have no
/// relation to the DC's direct IP, so this interface ignores them and dials its own DC -> hostname
/// mapping (`WebSocketEndpointPlanner`) instead, using the `datacenterId`/`isMediaConnection`/
/// `isTestingEnvironment` it was constructed with.
@available(iOS 12.0, macOS 14.0, *)
final class MTWebSocketConnectionInterface: NSObject, MTTcpConnectionInterface {
    private struct ReadRequest {
        let length: Int
        let tag: Int
    }

    private final class ExecutingReadRequest {
        let request: ReadRequest
        var data: Data
        var readyLength: Int = 0

        init(request: ReadRequest) {
            self.request = request
            self.data = Data(count: request.length)
        }
    }

    private final class Impl {
        private static let maximumRetainedReadPrefix = 256 * 1024
        /// MTTcpConnection sets `_readyToSendData` as soon as `connectToHost` returns, before
        /// `connectionInterfaceDidConnect` — which for WebSocket only fires after the HTTP upgrade
        /// completes. Buffer outbound bytes until then instead of dropping them.
        private static let maximumPendingWriteBytes = 256 * 1024

        private enum HandshakeState {
            case tcpConnecting
            case sentUpgradeRequest
            case established
        }

        private let queue: Queue

        private weak var delegate: MTTcpConnectionInterfaceDelegate?
        private let delegateQueue: DispatchQueue

        private let datacenterId: Int
        private let isMediaConnection: Bool
        private let isTestingEnvironment: Bool
        private let fallbackCoordinator: MTWebSocketFallbackCoordinator?

        private var connection: NWConnection?
        private var reportedDisconnection = false
        private var currentInterfaceIsWifi = true

        private var connectTimeout: Double = 12.0
        private var connectTimeoutTimer: SwiftSignalKit.Timer?
        private var viabilityLossTimer: SwiftSignalKit.Timer?
        private var isReady = false

        private var endpointSelector: WebSocketEndpointSelector
        private var currentCandidateHost: String?
        private var currentCandidatePath: String?
        private var currentCandidateHttpHost: String?
        private var currentCandidateTlsServerName: String?

        private var handshakeState: HandshakeState = .tcpConnecting
        private var handshakeResponseBuffer = Data()
        private var reassembler = WebSocketMessageReassembler()
        private var readBuffer = Data()
        private var readBufferOffset = 0

        /// Bumped every time a connection is dialed or abandoned. NWConnection callbacks capture the
        /// value current when their connection was created and drop out if it has moved on, so a
        /// callback already dispatched onto `queue` when we abandoned that connection cannot act on
        /// the one that replaced it. An Int is captured instead of the connection itself so the
        /// handlers stored on the connection do not retain it.
        private var connectionGeneration = 0

        /// Set once `connectionInterfaceDidConnect` has been delivered. From that moment the endpoint
        /// list is frozen — see `candidateFailed`.
        private var didReportConnection = false
        /// Whether the peer ever delivered MTProto payload on this connection. This, not a completed
        /// WebSocket handshake, is the transport's health signal: the gateway accepts the upgrade
        /// before it has seen a single byte of the MTProto stream it may then reject, so treating the
        /// handshake as success would keep resetting the fallback counter on a connection that never
        /// carries anything.
        private var didReceivePayload = false
        private var recordedAttemptOutcome = false
        /// Distinguishes "MTTcpConnection asked us to close" from "the connection died", so a clean
        /// teardown before any payload is not counted against the endpoints.
        private var didRequestDisconnect = false

        private var readRequests: [ReadRequest] = []
        private var currentReadRequest: ExecutingReadRequest?
        private var pendingWrites: [Data] = []
        private var pendingWriteBytes = 0

        private var usageCalculationInfo: MTNetworkUsageCalculationInfo?
        private var networkUsageManager: MTNetworkUsageManager?

        init(
            queue: Queue,
            delegate: MTTcpConnectionInterfaceDelegate,
            delegateQueue: DispatchQueue,
            datacenterId: Int,
            isMediaConnection: Bool,
            isTestingEnvironment: Bool,
            fallbackCoordinator: MTWebSocketFallbackCoordinator?
        ) {
            self.queue = queue
            self.delegate = delegate
            self.delegateQueue = delegateQueue
            self.datacenterId = datacenterId
            self.isMediaConnection = isMediaConnection
            self.isTestingEnvironment = isTestingEnvironment
            self.fallbackCoordinator = fallbackCoordinator
            self.endpointSelector = WebSocketEndpointSelector(candidates: WebSocketEndpointPlanner.candidates(
                datacenterId: datacenterId,
                isMedia: isMediaConnection,
                isTestingEnvironment: isTestingEnvironment
            ))
        }

        deinit {
            // QueueLocalObject deallocates this on `queue`, so the connection may still be open if
            // MTTcpConnection released the interface without disconnecting first. An NWConnection that
            // is never cancelled keeps its TLS session and its receive loop alive.
            self.connectTimeoutTimer?.invalidate()
            self.viabilityLossTimer?.invalidate()
            if !self.recordedAttemptOutcome && !self.didReceivePayload {
                self.fallbackCoordinator?.abortProbe()
            }
            self.discardCurrentConnection()
        }

        /// Detaches the handlers of the current connection, cancels it, and invalidates the generation
        /// so any callback still in flight for it becomes a no-op.
        private func discardCurrentConnection() {
            self.connectionGeneration += 1
            if let viabilityLossTimer = self.viabilityLossTimer {
                self.viabilityLossTimer = nil
                viabilityLossTimer.invalidate()
            }
            self.isReady = false
            guard let connection = self.connection else {
                return
            }
            self.connection = nil
            connection.stateUpdateHandler = nil
            connection.pathUpdateHandler = nil
            connection.viabilityUpdateHandler = nil
            connection.cancel()
        }

        func setUsageCalculationInfo(_ usageCalculationInfo: MTNetworkUsageCalculationInfo?) {
            if self.usageCalculationInfo !== usageCalculationInfo {
                self.usageCalculationInfo = usageCalculationInfo
                if let usageCalculationInfo = usageCalculationInfo {
                    self.networkUsageManager = MTNetworkUsageManager(info: usageCalculationInfo)
                } else {
                    self.networkUsageManager = nil
                }
            }
        }

        func connect(timeout: Double) {
            if self.connection != nil {
                assertionFailure("A connection already exists")
                return
            }
            self.connectTimeout = timeout
            self.endpointSelector.reset()
            self.dialCurrentCandidate()
        }

        private func dialCurrentCandidate() {
            guard let candidate = self.endpointSelector.current else {
                self.cancelWithError(error: nil)
                return
            }

            let mediaSuffix = self.isMediaConnection ? " media" : ""
            Logger.shared.log("MTWebSocket", "[WS] DC\(self.datacenterId)\(mediaSuffix) -> \(candidate.host)\(candidate.path)")

            self.handshakeState = .tcpConnecting
            self.handshakeResponseBuffer = Data()
            self.reassembler = WebSocketMessageReassembler()
            self.isReady = false
            if let viabilityLossTimer = self.viabilityLossTimer {
                self.viabilityLossTimer = nil
                viabilityLossTimer.invalidate()
            }
            // Only reachable before the connection has been reported (see `candidateFailed`), so
            // nothing is in flight — but leaving a previous candidate's bytes in place would splice
            // two unrelated streams together if that ever changed.
            self.readBuffer = Data()
            self.readBufferOffset = 0
            self.currentCandidateHost = candidate.host
            self.currentCandidatePath = candidate.path
            self.currentCandidateHttpHost = candidate.httpHost
            self.currentCandidateTlsServerName = candidate.tlsServerName

            let host = NWEndpoint.Host(candidate.host)
            guard let port = NWEndpoint.Port(rawValue: candidate.port) else {
                self.candidateFailed(error: nil)
                return
            }

            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 5
            tcpOptions.keepaliveCount = 2
            tcpOptions.keepaliveInterval = 5
            tcpOptions.enableFastOpen = false

            // TLS SNI. For Telegram-gateway candidates, SNI is derived from `host` automatically.
            // For CF-Worker / custom-front candidates, `tlsServerName` may differ from `host`
            // (the Worker's own hostname) — use sec_protocol_options to override it while keeping
            // full certificate-chain validation against that Worker cert (NOT weakened).
            let tlsOptions = NWProtocolTLS.Options()
            let effectiveSNI = self.currentCandidateTlsServerName ?? candidate.host
            if effectiveSNI != candidate.host {
                sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, effectiveSNI)
            }

            let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            let connection = NWConnection(host: host, port: port, using: parameters)
            self.connectionGeneration += 1
            let generation = self.connectionGeneration
            self.connection = connection

            let queue = self.queue
            connection.stateUpdateHandler = { [weak self] state in
                queue.async {
                    guard let self = self, self.connectionGeneration == generation else {
                        return
                    }
                    self.stateUpdated(state: state)
                }
            }
            connection.pathUpdateHandler = { [weak self] path in
                queue.async {
                    guard let self = self, self.connectionGeneration == generation else {
                        return
                    }
                    self.currentInterfaceIsWifi = !path.usesInterfaceType(.cellular)
                }
            }
            connection.viabilityUpdateHandler = { [weak self] isViable in
                queue.async {
                    guard let self = self, self.connectionGeneration == generation else {
                        return
                    }
                    if isViable {
                        if let viabilityLossTimer = self.viabilityLossTimer {
                            self.viabilityLossTimer = nil
                            viabilityLossTimer.invalidate()
                        }
                        return
                    }
                    // Do not tear down a connect that has not reached `.ready` yet. After `.ready`,
                    // debounce brief false spikes on foreground resume — same policy as
                    // NetworkFrameworkTcpConnectionInterface.
                    guard self.isReady, self.viabilityLossTimer == nil else {
                        return
                    }
                    self.viabilityLossTimer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
                        guard let self = self else {
                            return
                        }
                        self.viabilityLossTimer = nil
                        if self.isReady {
                            self.candidateFailed(error: nil)
                        }
                    }, queue: self.queue)
                    self.viabilityLossTimer?.start()
                }
            }

            self.connectTimeoutTimer = SwiftSignalKit.Timer(timeout: networkFrameworkConnectTimeout(host: candidate.host, requested: self.connectTimeout), repeat: false, completion: { [weak self] in
                self?.connectTimeoutTimer = nil
                self?.candidateFailed(error: nil)
            }, queue: self.queue)
            self.connectTimeoutTimer?.start()

            connection.start(queue: self.queue.queue)
        }

        private func stateUpdated(state: NWConnection.State) {
            switch state {
            case .ready:
                self.isReady = true
                if let path = self.connection?.currentPath {
                    self.currentInterfaceIsWifi = !path.usesInterfaceType(.cellular)
                }
                self.beginWebSocketHandshake()
            case let .failed(error):
                self.candidateFailed(error: error)
            case .cancelled:
                self.candidateFailed(error: nil)
            default:
                break
            }
        }

        private func beginWebSocketHandshake() {
            guard let connection = self.connection, let host = self.currentCandidateHost, let path = self.currentCandidatePath else {
                return
            }
            // HTTP Host header: for CF-Worker fronts this is the Worker domain (same as httpHost),
            // not the Telegram gateway. For plain Telegram candidates they are identical.
            let httpHost = self.currentCandidateHttpHost ?? host

            let key = Impl.makeSecWebSocketKey()
            var request = "GET \(path) HTTP/1.1\r\n"
            request += "Host: \(httpHost)\r\n"
            request += "Upgrade: websocket\r\n"
            request += "Connection: Upgrade\r\n"
            request += "Sec-WebSocket-Key: \(key)\r\n"
            request += "Sec-WebSocket-Version: 13\r\n"
            // Telegram's kwsN.web.telegram.org gateway uses this to select binary vs. text/JSON WS
            // framing; tg-ws-proxy's RawWebSocket.connect() sends the same value (proxy/raw_websocket.py,
            // commit b2a8074c). Omitting it risks the gateway defaulting to a mode MtProtoKit's raw
            // obfuscated byte stream doesn't match.
            request += "Sec-WebSocket-Protocol: binary\r\n"
            request += "\r\n"
            guard let requestData = request.data(using: .utf8) else {
                self.candidateFailed(error: nil)
                return
            }

            self.handshakeState = .sentUpgradeRequest

            connection.send(content: requestData, completion: .contentProcessed({ [weak self] error in
                guard let error = error else {
                    return
                }
                self?.queue.async {
                    self?.candidateFailed(error: error)
                }
            }))

            self.receiveLoop()
        }

        private func receiveLoop() {
            guard let connection = self.connection else {
                return
            }
            let generation = self.connectionGeneration
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024, completion: { [weak self] data, _, isComplete, error in
                guard let self = self else {
                    return
                }
                self.queue.async {
                    guard self.connectionGeneration == generation, self.connection != nil else {
                        // This receive belonged to a candidate we've already abandoned.
                        return
                    }
                    if let data = data, !data.isEmpty {
                        self.networkUsageManager?.addIncomingBytes(UInt(data.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
                        self.handleIncomingBytes(data)
                    }
                    if let error = error {
                        self.candidateFailed(error: error)
                        return
                    }
                    if isComplete {
                        self.cancelWithError(error: nil)
                        return
                    }
                    if self.connection != nil {
                        self.receiveLoop()
                    }
                }
            })
        }

        private func handleIncomingBytes(_ data: Data) {
            switch self.handshakeState {
            case .sentUpgradeRequest:
                self.handshakeResponseBuffer.append(data)
                guard let headerRange = Impl.findHeaderTerminator(in: self.handshakeResponseBuffer) else {
                    if self.handshakeResponseBuffer.count > 16 * 1024 {
                        self.candidateFailed(error: nil)
                    }
                    return
                }
                let headerData = self.handshakeResponseBuffer.subdata(in: self.handshakeResponseBuffer.startIndex ..< headerRange.lowerBound)
                let remainder = self.handshakeResponseBuffer.subdata(in: headerRange.upperBound ..< self.handshakeResponseBuffer.endIndex)
                guard let headerString = String(data: headerData, encoding: .utf8), Impl.isSuccessfulUpgradeResponse(headerString) else {
                    self.candidateFailed(error: nil)
                    return
                }
                self.handshakeState = .established
                self.handshakeResponseBuffer = Data()
                self.markCandidateConnected()
                self.flushPendingWrites()
                if !remainder.isEmpty {
                    self.processWebSocketBytes(remainder)
                }
            case .established:
                self.processWebSocketBytes(data)
            case .tcpConnecting:
                break
            }
        }

        private func markCandidateConnected() {
            Logger.shared.log("MTWebSocket", "[WS] handshake OK (\(self.currentCandidateHost ?? "?"))")
            if let connectTimeoutTimer = self.connectTimeoutTimer {
                self.connectTimeoutTimer = nil
                connectTimeoutTimer.invalidate()
            }
            self.didReportConnection = true

            let delegate = self.delegate
            self.delegateQueue.async { [weak delegate] in
                delegate?.connectionInterfaceDidConnect()
            }
            self.serviceReadRequests()
        }

        private func processWebSocketBytes(_ data: Data) {
            let events = self.reassembler.feed(data)
            for event in events {
                switch event {
                case let .message(_, payload):
                    if !payload.isEmpty {
                        self.recordPayloadReceived()
                    }
                    self.readBuffer.append(payload)
                case let .ping(payload):
                    self.sendControlFrame(opcode: .pong, payload: payload)
                case .pong:
                    break
                case let .close(code, _):
                    Logger.shared.log("MTWebSocket", "[WS] connection closed by peer (code \(code.map { String($0) } ?? "none"))")
                    self.sendControlFrame(opcode: .close, payload: Data())
                    self.cancelWithError(error: nil)
                    return
                case let .protocolError(reason):
                    Logger.shared.log("MTWebSocket", "[WS] framing protocol error: \(reason)")
                    self.candidateFailed(error: nil)
                    return
                }
            }
            self.serviceReadRequests()
        }

        private func sendControlFrame(opcode: WebSocketOpcode, payload: Data) {
            guard let connection = self.connection else {
                return
            }
            let frame = WebSocketFrameEncoder.encode(opcode: opcode, payload: payload, mask: true)
            connection.send(content: frame, completion: .contentProcessed({ _ in
            }))
        }

        func write(data: Data) {
            guard !data.isEmpty else {
                return
            }
            if self.handshakeState != .established {
                let newSize = self.pendingWriteBytes + data.count
                if newSize > Impl.maximumPendingWriteBytes {
                    Logger.shared.log("MTWebSocket", "[WS] pending write buffer exceeded \(Impl.maximumPendingWriteBytes) bytes during handshake, closing connection")
                    self.clearPendingWrites()
                    self.candidateFailed(error: nil)
                    return
                }
                self.pendingWrites.append(data)
                self.pendingWriteBytes += data.count
                return
            }
            self.sendPayload(data)
        }

        private func sendPayload(_ data: Data) {
            guard let connection = self.connection, !data.isEmpty else {
                return
            }
            let frame = WebSocketFrameEncoder.encode(opcode: .binary, payload: data, mask: true)
            let queue = self.queue
            connection.send(content: frame, completion: .contentProcessed({ [weak self, weak connection] error in
                guard let error = error else {
                    return
                }
                queue.async {
                    guard let self = self, let connection = connection, self.connection === connection else {
                        return
                    }
                    Logger.shared.log("MTWebSocket", "[WS] send failed: \(error)")
                    self.candidateFailed(error: error)
                }
            }))
            self.networkUsageManager?.addOutgoingBytes(UInt(data.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
        }

        private func flushPendingWrites() {
            guard !self.pendingWrites.isEmpty else {
                return
            }
            let chunks = self.pendingWrites
            self.clearPendingWrites()
            for chunk in chunks {
                self.sendPayload(chunk)
            }
        }

        private func clearPendingWrites() {
            self.pendingWrites = []
            self.pendingWriteBytes = 0
        }

        func read(length: Int, timeout: Double, tag: Int) {
            self.readRequests.append(ReadRequest(length: length, tag: tag))
            self.serviceReadRequests()
        }

        private func serviceReadRequests() {
            while true {
                if self.currentReadRequest == nil {
                    if self.readRequests.isEmpty {
                        return
                    }
                    self.currentReadRequest = ExecutingReadRequest(request: self.readRequests.removeFirst())
                }
                guard let currentReadRequest = self.currentReadRequest else {
                    return
                }

                let remaining = currentReadRequest.request.length - currentReadRequest.readyLength
                if remaining == 0 {
                    self.currentReadRequest = nil

                    let delegate = self.delegate
                    let tag = currentReadRequest.request.tag
                    let resultData = currentReadRequest.data
                    let networkType: Int32 = self.currentInterfaceIsWifi ? 0 : 1
                    self.delegateQueue.async { [weak delegate] in
                        delegate?.connectionInterfaceDidRead(resultData, withTag: tag, networkType: networkType)
                    }
                    continue
                }

                let available = self.readBuffer.count - self.readBufferOffset
                if available == 0 {
                    self.compactReadBufferIfNeeded()
                    return
                }

                let takeCount = min(remaining, available)
                let chunkStart = self.readBuffer.startIndex + self.readBufferOffset
                let chunk = self.readBuffer[chunkStart ..< (chunkStart + takeCount)]
                self.readBufferOffset += takeCount
                self.compactReadBufferIfNeeded()

                currentReadRequest.data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                    guard let base = raw.baseAddress else {
                        return
                    }
                    chunk.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                        guard let srcBase = src.baseAddress else {
                            return
                        }
                        memcpy(base.advanced(by: currentReadRequest.readyLength), srcBase, takeCount)
                    }
                }
                currentReadRequest.readyLength += takeCount

                let delegate = self.delegate
                let tag = currentReadRequest.request.tag
                self.delegateQueue.async { [weak delegate] in
                    delegate?.connectionInterfaceDidReadPartialData(ofLength: UInt(takeCount), tag: tag)
                }
            }
        }

        /// A failure while dialing. Before the connection has been reported to MTTcpConnection this may
        /// move on to the next endpoint; afterwards it may not, and becomes a plain disconnect.
        ///
        /// Re-dialing after `connectionInterfaceDidConnect` would be silently fatal. MTTcpConnection
        /// prepends its 64-byte obfuscation header to the *first* packet only and then keeps encrypting
        /// with a per-connection AES-CTR stream, so a replacement socket underneath it would be handed
        /// mid-stream ciphertext with no init and would never decode anything — and it would see a
        /// second `connectionInterfaceDidConnect` with no disconnect in between. MTTcpConnection is
        /// one-shot by design (MTProto discards it and builds a new one), so the correct report after
        /// establishment is a disconnect, which is what `cancelWithError` delivers.
        private func candidateFailed(error: Error?) {
            if let connectTimeoutTimer = self.connectTimeoutTimer {
                self.connectTimeoutTimer = nil
                connectTimeoutTimer.invalidate()
            }
            self.discardCurrentConnection()

            Logger.shared.log("MTWebSocket", "[WS] endpoint \(self.currentCandidateHost ?? "?") failed (\(error?.localizedDescription ?? "timeout/protocol error"))")

            if self.didReportConnection {
                self.cancelWithError(error: error)
                return
            }

            if let _ = self.endpointSelector.advance() {
                Logger.shared.log("MTWebSocket", "[WS] trying secondary endpoint")
                self.dialCurrentCandidate()
            } else {
                self.cancelWithError(error: error)
            }
        }

        /// `readBuffer` is consumed through `readBufferOffset` rather than by removing the front of the
        /// buffer, so servicing a read is not a memmove of everything still queued behind it. The
        /// consumed prefix is dropped only when it is worth the copy: once it is half the buffer, or
        /// once it passes a fixed ceiling, so a long-lived connection never retains a growing dead
        /// prefix. Index arithmetic stays relative to `startIndex`, which `Data` does not guarantee to
        /// be zero after a `removeFirst`.
        private func compactReadBufferIfNeeded() {
            if self.readBufferOffset == 0 {
                return
            }
            if self.readBufferOffset >= self.readBuffer.count {
                self.readBuffer.removeAll(keepingCapacity: true)
                self.readBufferOffset = 0
                return
            }
            if self.readBufferOffset >= self.readBuffer.count / 2 || self.readBufferOffset >= Impl.maximumRetainedReadPrefix {
                self.readBuffer.removeFirst(self.readBufferOffset)
                self.readBufferOffset = 0
            }
        }

        private func recordPayloadReceived() {
            if self.didReceivePayload {
                return
            }
            self.didReceivePayload = true
            if !self.recordedAttemptOutcome {
                self.recordedAttemptOutcome = true
                self.fallbackCoordinator?.recordSuccess()
            }
        }

        /// Reports this attempt to the fallback coordinator, at most once. A connection that carried
        /// payload has already reported success; one that ended without any — including one that never
        /// got past the handshake — counts against the endpoints. An intentional disconnect (path
        /// rebuild / pause) must abort a probe without backing off, otherwise `isProbing` sticks
        /// forever and WS never returns.
        private func recordAttemptFailureIfNeeded() {
            if self.recordedAttemptOutcome || self.didReceivePayload {
                return
            }
            self.recordedAttemptOutcome = true
            if self.didRequestDisconnect {
                self.fallbackCoordinator?.abortProbe()
                return
            }
            self.fallbackCoordinator?.recordAllEndpointsFailed()
        }

        private func cancelWithError(error: Error?) {
            if let connectTimeoutTimer = self.connectTimeoutTimer {
                self.connectTimeoutTimer = nil
                connectTimeoutTimer.invalidate()
            }

            self.clearPendingWrites()
            self.recordAttemptFailureIfNeeded()

            if !self.reportedDisconnection {
                self.reportedDisconnection = true
                let delegate = self.delegate
                self.delegateQueue.async { [weak delegate] in
                    delegate?.connectionInterfaceDidDisconnectWithError(error)
                }
            }
            self.discardCurrentConnection()
        }

        func disconnect() {
            self.didRequestDisconnect = true
            self.cancelWithError(error: nil)
        }

        func resetDelegate() {
            self.delegate = nil
        }

        private static func makeSecWebSocketKey() -> String {
            var bytes = [UInt8](repeating: 0, count: 16)
            for i in 0 ..< bytes.count {
                bytes[i] = UInt8.random(in: 0...255)
            }
            return Data(bytes).base64EncodedString()
        }

        private static func findHeaderTerminator(in data: Data) -> Range<Data.Index>? {
            guard let terminator = "\r\n\r\n".data(using: .utf8) else {
                return nil
            }
            return data.range(of: terminator)
        }

        /// Checks the HTTP status line is "101" and the Upgrade/Connection headers are present.
        /// Deliberately does not verify `Sec-WebSocket-Accept` against the key it sent: that header is
        /// an RFC 6455 protocol-conformance echo, not a security boundary — the channel's actual
        /// security comes from TLS certificate validation (already enforced) below and MTProto's own
        /// auth-key/obfuscation layer above, neither of which this value participates in. tg-ws-proxy's
        /// own WS client does the same (see docs/websocket-transport.md).
        private static func isSuccessfulUpgradeResponse(_ headerString: String) -> Bool {
            guard let statusLine = headerString.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
                return false
            }
            let components = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard components.count >= 2, components[1] == "101" else {
                return false
            }
            let lowerHeaders = headerString.lowercased()
            return lowerHeaders.contains("upgrade: websocket") && lowerHeaders.contains("connection: upgrade")
        }
    }

    private static let sharedQueue = Queue(name: "MTWebSocketConnectionInterface")

    private let queue: Queue
    private let impl: QueueLocalObject<Impl>

    init(
        delegate: MTTcpConnectionInterfaceDelegate,
        delegateQueue: DispatchQueue,
        datacenterId: Int,
        isMediaConnection: Bool,
        isTestingEnvironment: Bool,
        fallbackCoordinator: MTWebSocketFallbackCoordinator?
    ) {
        let queue = MTWebSocketConnectionInterface.sharedQueue
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(
                queue: queue,
                delegate: delegate,
                delegateQueue: delegateQueue,
                datacenterId: datacenterId,
                isMediaConnection: isMediaConnection,
                isTestingEnvironment: isTestingEnvironment,
                fallbackCoordinator: fallbackCoordinator
            )
        })
    }

    func setGetLogPrefix(_ getLogPrefix: (() -> String)?) {
    }

    func setUsageCalculationInfo(_ usageCalculationInfo: MTNetworkUsageCalculationInfo?) {
        self.impl.with { impl in
            impl.setUsageCalculationInfo(usageCalculationInfo)
        }
    }

    func connect(toHost inHost: String, onPort port: UInt16, viaInterface inInterface: String?, withTimeout timeout: TimeInterval, error errPtr: NSErrorPointer) -> Bool {
        self.impl.with { impl in
            impl.connect(timeout: timeout)
        }
        return true
    }

    func write(_ data: Data) {
        self.impl.with { impl in
            impl.write(data: data)
        }
    }

    func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        self.impl.with { impl in
            impl.read(length: Int(length), timeout: timeout, tag: tag)
        }
    }

    func disconnect() {
        self.impl.with { impl in
            impl.disconnect()
        }
    }

    func resetDelegate() {
        self.impl.with { impl in
            impl.resetDelegate()
        }
    }
}
