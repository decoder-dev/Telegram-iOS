import Foundation
import SwiftSignalKit

/// Lifecycle manager for the embedded VLESS runtime, mirroring the desktop
/// client's `Core::VlessManager`: parse a `vless://` profile, allocate local
/// authenticated SOCKS5/HTTP inbounds, start the runtime, and expose the local
/// SOCKS5 sink that the application's proxy state should point at while the
/// runtime is up.
public enum VlessError: Error, Equatable {
    case invalidProfile(VlessProfileError)
    case runtimeUnavailable
    case portAllocationFailed
    case configurationFailed
    case startFailed(String)
    case notRunning
    case busy
}

/// The local proxy sink to install as the application's active proxy while
/// the VLESS runtime is running. Calls whose active proxy matches this shape
/// (loopback SOCKS5 with credentials) are routed as `managed` by tgcalls.
public struct VlessProxySink: Equatable {
    public var host: String
    public var port: Int
    public var user: String
    public var password: String

    public init(host: String, port: Int, user: String, password: String) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
    }
}

public final class VlessManager {
    public enum State: Equatable {
        case idle
        case preparing
        case running(sink: VlessProxySink)
        case failed(VlessError)
    }

    /// Process-wide manager, mirroring `WebProxyManager.shared`.
    public static let shared = VlessManager()

    private let lock = NSLock()
    private let runtime: XrayRuntime
    private var stateValue: State = .idle
    private var activeProfileURLValue: String?
    private let stateUpdated: (() -> Void)?
    
    private let stateEventsPipe = ValuePipe<State>()
    public var stateEvents: Signal<State, NoError> {
        return self.stateEventsPipe.signal()
    }
    
    private let runtimeQueue = DispatchQueue(label: "TelegramVLESS.runtime")
    private var generation: UInt64 = 0
    private var retryAttempt = 0
    private var heartbeatTimer: DispatchSourceTimer?

    public var state: State {
        lock.lock()
        defer { lock.unlock() }
        return stateValue
    }

    public init(runtime: XrayRuntime = LibXrayRuntime(), onStateChange: (() -> Void)? = nil) {
        self.runtime = runtime
        self.stateUpdated = onStateChange
    }

    /// Parses and validates `url` without starting anything.
    public static func validate(url: String) -> Result<VlessProfile, VlessError> {
        switch VlessProfileParser.parse(url) {
        case let .success(profile):
            return .success(profile)
        case let .failure(error):
            return .failure(.invalidProfile(error))
        }
    }

    /// Starts the runtime for `url`. On success the app should install the
    /// returned sink as its active proxy (SOCKS5, `useForCalls` included).
    public func start(url: String) {
        configure(activeProfileURL: url)
    }

    public func stop() {
        configure(activeProfileURL: nil)
    }

    /// All calls into the process-wide runtime are serialized. A generation invalidates
    /// starts, heartbeats and retries as soon as the user switches or disables a profile.
    public func configure(activeProfileURL: String?) {
        let url = activeProfileURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        if activeProfileURLValue == url {
            lock.unlock()
            return
        }
        generation &+= 1
        let token = generation
        activeProfileURLValue = url
        retryAttempt = 0
        stateValue = url == nil ? .idle : .preparing
        lock.unlock()
        notifyStateChange()
        runtimeQueue.async { [weak self] in
            guard let self = self, self.isCurrent(token) else { return }
            self.heartbeatTimer?.cancel()
            self.heartbeatTimer = nil
            // Always stop the previous process before starting a replacement.
            try? self.runtime.stop()
            guard let url = url, self.isCurrent(token) else { return }
            self.startRuntime(url: url, token: token)
        }
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    private func startRuntime(url: String, token: UInt64) {
        guard isCurrent(token) else { return }
        guard runtime.isAvailable else {
            fail(.runtimeUnavailable, url: url, token: token, retry: false)
            return
        }
        let profile: VlessProfile
        switch VlessProfileParser.parse(url) {
        case let .success(value): profile = value
        case let .failure(error):
            fail(.invalidProfile(error), url: url, token: token, retry: false)
            return
        }
        let ports: [Int]
        do {
            ports = try runtime.getFreePorts(count: 2)
        } catch {
            fail(.portAllocationFailed, url: url, token: token)
            return
        }
        guard ports.count == 2, ports[0] != ports[1], ports.allSatisfy({ (1...65535).contains($0) }) else {
            fail(.portAllocationFailed, url: url, token: token)
            return
        }
        let socksCredential = Self.generateCredential()
        let httpCredential = Self.generateCredential()
        let socks = VlessLocalInbound(port: ports[0], user: socksCredential.0, password: socksCredential.1)
        let http = VlessLocalInbound(port: ports[1], user: httpCredential.0, password: httpCredential.1)
        guard let config = VlessXrayConfig.configJSON(profile: profile, socks: socks, http: http) else {
            fail(.configurationFailed, url: url, token: token, retry: false)
            return
        }
        guard isCurrent(token) else { return }
        do {
            try runtime.start(configJSON: config)
        } catch {
            try? runtime.stop()
            fail(.startFailed(String(describing: error)), url: url, token: token)
            return
        }
        guard isCurrent(token) else {
            try? runtime.stop()
            return
        }
        guard runtime.isRunning() else {
            try? runtime.stop()
            fail(.notRunning, url: url, token: token)
            return
        }
        lock.lock()
        guard generation == token else {
            lock.unlock()
            try? runtime.stop()
            return
        }
        stateValue = .running(sink: VlessProxySink(host: "127.0.0.1", port: socks.port, user: socks.user, password: socks.password))
        lock.unlock()
        notifyStateChange()
        startHeartbeat(url: url, token: token)
    }

    private func fail(_ error: VlessError, url: String, token: UInt64, retry: Bool = true) {
        lock.lock()
        guard generation == token else { lock.unlock(); return }
        stateValue = .failed(error)
        let delay = min(30.0, pow(2.0, Double(min(retryAttempt, 5))))
        retryAttempt = min(retryAttempt + 1, 5)
        lock.unlock()
        notifyStateChange()
        guard retry else { return }
        runtimeQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            guard self.generation == token else { self.lock.unlock(); return }
            self.stateValue = .preparing
            self.lock.unlock()
            self.notifyStateChange()
            try? self.runtime.stop()
            self.startRuntime(url: url, token: token)
        }
    }

    /// Whether the runtime is currently serving the given profile URL.
    public func isReady(for profileURL: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .running = stateValue, activeProfileURLValue == profileURL {
            return true
        }
        return false
    }

    /// The running loopback endpoint, if any.
    public var activeLoopbackEndpoint: VlessProxySink? {
        lock.lock()
        defer { lock.unlock() }
        if case let .running(sink) = stateValue {
            return sink
        }
        return nil
    }

    public var isRunning: Bool {
        if case .running = state {
            return true
        }
        return false
    }

    private func notifyStateChange() {
        // Network settings callbacks are main-queue-owned and must never re-enter
        // configure synchronously while a transition is still being delivered.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stateUpdated?()
            self.stateEventsPipe.putNext(self.state)
        }
    }

    private func startHeartbeat(url: String, token: UInt64) {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: runtimeQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isCurrent(token) else { return }
            if !self.runtime.isRunning() {
                self.heartbeatTimer?.cancel()
                self.heartbeatTimer = nil
                self.fail(.notRunning, url: url, token: token)
            }
        }
        heartbeatTimer = timer
        timer.resume()
    }

    deinit {
        heartbeatTimer?.cancel()
    }

    /// Random printable-ASCII credentials for the local inbounds, in the
    /// shape tgcalls' managed-route validation accepts (non-empty, <=255,
    /// printable ASCII without control characters).
    static func generateCredential() -> (String, String) {
        let alphabet: [UInt8] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
        func randomString(_ length: Int) -> String {
            var bytes = [UInt8]()
            bytes.reserveCapacity(length)
            for _ in 0..<length {
                bytes.append(alphabet[Int(arc4random_uniform(UInt32(alphabet.count)))])
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        return (randomString(16), randomString(24))
    }
}
