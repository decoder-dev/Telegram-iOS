import Foundation
import Network

import MtProtoKit
import SwiftSignalKit

@available(iOS 12.0, macOS 14.0, *)
final class NetworkFrameworkTcpConnectionInterface: NSObject, MTTcpConnectionInterface {
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
        private let queue: Queue
        
        private weak var delegate: MTTcpConnectionInterfaceDelegate?
        private let delegateQueue: DispatchQueue
        
        private let requestChunkLength: Int
        
        private var connection: NWConnection?
        private var reportedDisconnection: Bool = false
        private var isReady: Bool = false
        
        private var currentInterfaceIsWifi: Bool = true
        
        private var connectTimeoutTimer: SwiftSignalKit.Timer?
        private var viabilityLossTimer: SwiftSignalKit.Timer?
        
        private var usageCalculationInfo: MTNetworkUsageCalculationInfo?
        private var networkUsageManager: MTNetworkUsageManager?
        
        private var readRequests: [ReadRequest] = []
        private var currentReadRequest: ExecutingReadRequest?

        /// Connections that have been started and have not yet reached `.ready`, failed, or been
        /// cancelled.
        ///
        /// This is the number the whole Network.framework experiment exists to hold down. The
        /// socket transport it replaces blocks a dispatch worker inside `connect(2)` for as long
        /// as the kernel takes to give up — a tester's watchdog report caught eleven of them at
        /// once — and nothing in a log said so; it took thread archaeology on a crash payload.
        /// `NWConnection` cannot block a thread, so if this number still climbs the cause is
        /// somewhere else entirely, and either way the log now answers it directly.
        ///
        /// Mutated only from `sharedQueue`, which every `Impl` in the process shares, so it needs
        /// no lock.
        private static var inFlightConnectCount: Int = 0
        private var isCountedInFlight: Bool = false

        /// Kept only so the log lines can name the endpoint.
        ///
        /// The first log with this counter in it caught 4,176 connection attempts in twenty-five
        /// seconds, ending in a watchdog kill — and could not say where a single one of them was
        /// going, which is the one thing needed to tell a hammered relay from a hammered
        /// loopback port from a hammered datacenter.
        private var endpointDescription: String = "?"
        
        init(
            queue: Queue,
            delegate: MTTcpConnectionInterfaceDelegate,
            delegateQueue: DispatchQueue
        ) {
            self.queue = queue
            
            self.delegate = delegate
            self.delegateQueue = delegateQueue
            
            self.requestChunkLength = 256 * 1024
        }
        
        deinit {
            // An `NWConnection` keeps itself alive while started, so one that is never cancelled
            // outlives everything that referenced it — with this file's five-second keepalive
            // still running. `disconnect()` normally gets here first, but "released without being
            // closed" is exactly the shape of two bugs already fixed in the socket transport, and
            // the cost of covering it is one call.
            self.leaveInFlight()
            if let connection = self.connection {
                self.connection = nil
                connection.cancel()
            }
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
        
        func connect(host: String, port: UInt16, timeout: Double) {
            if self.connection != nil {
                Logger.shared.log("Network", "NW connect to \(self.endpointDescription) restarting while a connection still exists")
                self.discardConnectionWithoutNotifying()
            }
            self.reportedDisconnection = false
            self.isReady = false

            // Taken from the parameters, before `host` is shadowed by the `NWEndpoint.Host` below:
            // that type has no `CustomStringConvertible` conformance, so interpolating it would
            // print whatever reflection makes of the case rather than the address.
            self.endpointDescription = "\(host):\(port)"
            
            let host = NWEndpoint.Host(host)
            let port = NWEndpoint.Port(rawValue: port)!
            
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 5
            tcpOptions.keepaliveCount = 2
            tcpOptions.keepaliveInterval = 5
            tcpOptions.enableFastOpen = true
            
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            let connection = NWConnection(host: host, port: port, using: parameters)
            self.connection = connection
            
            let queue = self.queue
            // Every handler checks that the connection it belongs to is still the current one.
            //
            // Without that, a superseded connection's callbacks act on its replacement. The
            // restart path below cancels the old connection and starts a new one immediately, and
            // the old one's `.cancelled` then arrives — with no guard it runs `cancelWithError`
            // against the connection that just started, so a restart could never succeed.
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                queue.async {
                    guard let self = self, let connection = connection, self.connection === connection else {
                        return
                    }
                    self.stateUpdated(state: state)
                }
            }
            
            connection.pathUpdateHandler = { [weak self, weak connection] path in
                queue.async {
                    guard let self = self, let connection = connection, self.connection === connection else {
                        return
                    }
                    if path.usesInterfaceType(.cellular) {
                        self.currentInterfaceIsWifi = false
                    } else {
                        self.currentInterfaceIsWifi = true
                    }
                }
            }
            
            connection.viabilityUpdateHandler = { [weak self, weak connection] isViable in
                queue.async {
                    guard let self = self, let connection = connection, self.connection === connection else {
                        return
                    }
                    if isViable {
                        if let viabilityLossTimer = self.viabilityLossTimer {
                            self.viabilityLossTimer = nil
                            viabilityLossTimer.invalidate()
                        }
                        return
                    }
                    // Do not tear down a connect that has not reached `.ready` yet. On flaky paths
                    // viability often flips false while the stack is still negotiating, and
                    // cancelling there leaves the UI stuck on "Connecting…" until the timeout fires.
                    // After `.ready`, debounce brief false spikes on foreground resume — they used
                    // to disconnect every established socket and restart the whole reconnect ladder.
                    guard self.isReady, self.viabilityLossTimer == nil else {
                        return
                    }
                    self.viabilityLossTimer = SwiftSignalKit.Timer(timeout: 2.0, repeat: false, completion: { [weak self] in
                        guard let self = self else {
                            return
                        }
                        self.viabilityLossTimer = nil
                        if self.isReady {
                            self.cancelWithError(error: nil)
                        }
                    }, queue: self.queue)
                    self.viabilityLossTimer?.start()
                }
            }
            
            /*connection.betterPathUpdateHandler = { [weak self] hasBetterPath in
                queue.async {
                    guard let self = self else {
                        return
                    }
                    if hasBetterPath {
                        self.cancelWithError(error: nil)
                    }
                }
            }*/
            
            self.connectTimeoutTimer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
                guard let self = self else {
                    return
                }
                self.connectTimeoutTimer = nil
                Logger.shared.log("Network", "NW connect to \(self.endpointDescription) timed out after \(timeout)s")
                self.cancelWithError(error: nil)
            }, queue: self.queue)
            self.connectTimeoutTimer?.start()

            self.isCountedInFlight = true
            Impl.inFlightConnectCount += 1
            Logger.shared.log("Network", "NW connect starting to \(self.endpointDescription), \(Impl.inFlightConnectCount) in flight")
            
            connection.start(queue: self.queue.queue)
            
            self.processReadRequests()
        }

        /// Balanced against the increment in `connect`, from every path that ends an attempt:
        /// ready, failed, timed out, cancelled, or deallocated. Idempotent, because more than one
        /// of those can happen to the same connection.
        private func leaveInFlight() {
            if self.isCountedInFlight {
                self.isCountedInFlight = false
                Impl.inFlightConnectCount -= 1
            }
        }
        
        private func stateUpdated(state: NWConnection.State) {
            switch state {
            case .ready:
                self.isReady = true
                if let path = self.connection?.currentPath {
                    if path.usesInterfaceType(.cellular) {
                        self.currentInterfaceIsWifi = false
                    } else {
                        self.currentInterfaceIsWifi = true
                    }
                }
                
                if let connectTimeoutTimer = connectTimeoutTimer {
                    self.connectTimeoutTimer = nil
                    connectTimeoutTimer.invalidate()
                }
                self.leaveInFlight()
                
                let delegate = self.delegate
                self.delegateQueue.async { [weak delegate] in
                    if let delegate = delegate {
                        delegate.connectionInterfaceDidConnect()
                    }
                }
                self.processReadRequests()
            case let .failed(error):
                self.cancelWithError(error: error)
            case .cancelled:
                self.cancelWithError(error: nil)
            default:
                break
            }
        }
        
        func write(data: Data) {
            guard let connection = self.connection else {
                Logger.shared.log("NetworkFrameworkTcpConnectionInterface", "write called while connection == nil")
                return
            }
            
            let queue = self.queue
            connection.send(content: data, completion: .contentProcessed({ [weak self] error in
                // A dropped send used to be silent, which left MtProtoKit waiting on a reply to a
                // request that never left for as long as its own timeout — the socket transport
                // reports write errors, so this one should too.
                guard let error = error else {
                    return
                }
                queue.async {
                    guard let self = self else {
                        return
                    }
                    Logger.shared.log("NetworkFrameworkTcpConnectionInterface", "send failed: \(error)")
                    self.cancelWithError(error: error)
                }
            }))
            
            self.networkUsageManager?.addOutgoingBytes(UInt(data.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
        }
        
        func read(length: Int, timeout: Double, tag: Int) {
            self.readRequests.append(NetworkFrameworkTcpConnectionInterface.ReadRequest(length: length, tag: tag))
            self.processReadRequests()
        }
        
        private func processReadRequests() {
            if self.currentReadRequest != nil {
                return
            }
            if self.readRequests.isEmpty {
                return
            }
            
            let readRequest = self.readRequests.removeFirst()
            let currentReadRequest = ExecutingReadRequest(request: readRequest)
            self.currentReadRequest = currentReadRequest
            
            self.processCurrentRead()
        }
        
        private func processCurrentRead() {
            guard let currentReadRequest = self.currentReadRequest else {
                return
            }
            guard let connection = self.connection else {
                print("Connection not ready")
                return
            }
            
            let requestChunkLength = min(self.requestChunkLength, currentReadRequest.request.length - currentReadRequest.readyLength)
            if requestChunkLength == 0 {
                self.currentReadRequest = nil
                
                let delegate = self.delegate
                let currentInterfaceIsWifi = self.currentInterfaceIsWifi
                self.delegateQueue.async { [weak delegate] in
                    if let delegate = delegate {
                        delegate.connectionInterfaceDidRead(currentReadRequest.data, withTag: currentReadRequest.request.tag, networkType: currentInterfaceIsWifi ? 0 : 1)
                    }
                }
                
                self.processReadRequests()
            } else {
                connection.receive(minimumIncompleteLength: requestChunkLength, maximumLength: requestChunkLength, completion: { [weak self] data, context, isComplete, error in
                    guard let self = self, let currentReadRequest = self.currentReadRequest else {
                        return
                    }
                    if let data = data {
                        self.networkUsageManager?.addIncomingBytes(UInt(data.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
                        
                        if data.count != 0 && data.count <= currentReadRequest.request.length - currentReadRequest.readyLength {
                            currentReadRequest.data.withUnsafeMutableBytes { currentBuffer in
                                guard let currentBytes = currentBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                                    return
                                }
                                data.copyBytes(to: currentBytes.advanced(by: currentReadRequest.readyLength), count: data.count)
                            }
                            currentReadRequest.readyLength += data.count
                            
                            let tag = currentReadRequest.request.tag
                            let readCount = data.count
                            let delegate = self.delegate
                            self.delegateQueue.async { [weak delegate] in
                                if let delegate = delegate {
                                    delegate.connectionInterfaceDidReadPartialData(ofLength: UInt(readCount), tag: tag)
                                }
                            }
                            
                            self.processCurrentRead()
                        } else {
                            self.cancelWithError(error: error)
                        }
                        
                        if isComplete && data.count == 0 {
                            self.cancelWithError(error: nil)
                        }
                    } else {
                        self.cancelWithError(error: error)
                    }
                })
            }
        }
        
        /// Drop the current connection without telling the delegate it disconnected.
        ///
        /// The restart path cannot go through `cancelWithError`: that reports a disconnect, and
        /// `MTTcpConnection` treats a disconnect as the connection being finished — it sets
        /// `_closed` and writes the connection off. The socket started immediately afterwards
        /// would then belong to something that will never read from it, which is a connection
        /// that hangs rather than one that restarts.
        private func discardConnectionWithoutNotifying() {
            self.isReady = false
            if let viabilityLossTimer = self.viabilityLossTimer {
                self.viabilityLossTimer = nil
                viabilityLossTimer.invalidate()
            }
            if let connectTimeoutTimer = self.connectTimeoutTimer {
                self.connectTimeoutTimer = nil
                connectTimeoutTimer.invalidate()
            }
            self.leaveInFlight()
            if let connection = self.connection {
                // Cleared first: the handlers' identity check reads this, and it is what makes the
                // cancelled connection's own `.cancelled` callback a no-op instead of a teardown
                // of whatever replaces it.
                self.connection = nil
                connection.cancel()
            }
        }
        
        private func cancelWithError(error: Error?) {
            self.isReady = false
            if let viabilityLossTimer = self.viabilityLossTimer {
                self.viabilityLossTimer = nil
                viabilityLossTimer.invalidate()
            }
            if let connectTimeoutTimer = self.connectTimeoutTimer {
                self.connectTimeoutTimer = nil
                connectTimeoutTimer.invalidate()
            }
            // Only when an attempt that had not yet connected fails: an ordinary disconnect passes
            // no error and is not worth a line. A connection refused the instant it is made and a
            // connection that dies after minutes of traffic look identical in the count above, and
            // they are not the same problem — the first is a retry loop with nothing throttling it.
            if let error = error, self.isCountedInFlight {
                Logger.shared.log("Network", "NW connect to \(self.endpointDescription) failed: \(error)")
            }
            self.leaveInFlight()
            
            if !self.reportedDisconnection {
                self.reportedDisconnection = true
                let delegate = self.delegate
                self.delegateQueue.async { [weak delegate] in
                    if let delegate = delegate {
                        delegate.connectionInterfaceDidDisconnectWithError(error)
                    }
                }
            }
            if let connection = self.connection {
                self.connection = nil
                connection.cancel()
            }
        }
        
        func disconnect() {
            self.cancelWithError(error: nil)
        }
        
        func resetDelegate() {
            self.delegate = nil
        }
    }
    
    private static let sharedQueue = Queue(name: "NetworkFrameworkTcpConnectionInteface")
    
    private let queue: Queue
    private let impl: QueueLocalObject<Impl>
    
    init(delegate: MTTcpConnectionInterfaceDelegate, delegateQueue: DispatchQueue) {
        let queue = NetworkFrameworkTcpConnectionInterface.sharedQueue
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(queue: queue, delegate: delegate, delegateQueue: delegateQueue)
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
        // `viaInterface` has no equivalent here and is not implemented: it would map to
        // `NWParameters.requiredInterfaceType`, and every construction site in MtProtoKit
        // (MTTcpTransport, MTProxyConnectivity, MTDiscoverConnectionSignals) passes nil, so the
        // mapping would be code no path exercises. Saying so out loud rather than dropping the
        // argument, in case a caller ever starts passing one.
        if let inInterface = inInterface {
            Logger.shared.log("NetworkFrameworkTcpConnectionInterface", "ignoring viaInterface \(inInterface): not implemented for NWConnection")
        }
        self.impl.with { impl in
            impl.connect(host: inHost, port: port, timeout: timeout)
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
