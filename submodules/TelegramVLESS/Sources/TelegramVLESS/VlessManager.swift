import Foundation

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
    @discardableResult
    public func start(url: String) -> Result<VlessProxySink, VlessError> {
        lock.lock()
        if case .preparing = stateValue {
            lock.unlock()
            return .failure(.busy)
        }
        if case .running = stateValue {
            lock.unlock()
            return .failure(.busy)
        }
        stateValue = .preparing
        lock.unlock()
        notifyStateChange()

        let fail: (VlessError) -> Result<VlessProxySink, VlessError> = { [weak self] error in
            guard let self = self else {
                return .failure(error)
            }
            self.lock.lock()
            self.stateValue = .failed(error)
            self.lock.unlock()
            self.notifyStateChange()
            return .failure(error)
        }

        guard runtime.isAvailable else {
            return fail(.runtimeUnavailable)
        }

        let profile: VlessProfile
        switch VlessProfileParser.parse(url) {
        case let .success(value):
            profile = value
        case let .failure(error):
            return fail(.invalidProfile(error))
        }

        let ports: [Int]
        do {
            ports = try runtime.getFreePorts(count: 2)
        } catch {
            return fail(.portAllocationFailed)
        }

        let socksCredential = Self.generateCredential()
        let httpCredential = Self.generateCredential()
        let socks = VlessLocalInbound(port: ports[0], user: socksCredential.0, password: socksCredential.1)
        let http = VlessLocalInbound(port: ports[1], user: httpCredential.0, password: httpCredential.1)

        guard let configJSON = VlessXrayConfig.configJSON(profile: profile, socks: socks, http: http) else {
            return fail(.configurationFailed)
        }

        do {
            try runtime.start(configJSON: configJSON)
        } catch {
            return fail(.startFailed(String(describing: error)))
        }

        guard runtime.isRunning() else {
            try? runtime.stop()
            return fail(.startFailed("runtime did not stay running"))
        }

        let sink = VlessProxySink(host: "127.0.0.1", port: socks.port, user: socks.user, password: socks.password)
        lock.lock()
        stateValue = .running(sink: sink)
        activeProfileURLValue = url
        lock.unlock()
        notifyStateChange()
        return .success(sink)
    }

    /// Stops the runtime. The app must drop the sink from its active proxy
    /// before or immediately after calling this.
    public func stop() {
        lock.lock()
        stateValue = .idle
        activeProfileURLValue = nil
        lock.unlock()
        try? runtime.stop()
        notifyStateChange()
    }

    /// Reconciles the embedded runtime with the currently active profile.
    ///
    /// - Same URL and running: no-op.
    /// - Different URL: restart with the new profile.
    /// - `nil` or a profile that fails to start: stop.
    ///
    /// Mirrors `WebProxyManager.configure(activeWebProxy:)`.
    public func configure(activeProfileURL: String?) {
        lock.lock()
        let previousURL = activeProfileURLValue
        if activeProfileURL == nil {
            activeProfileURLValue = nil
        }
        let isRunningForPrevious: Bool
        if case .running = stateValue {
            isRunningForPrevious = true
        } else {
            isRunningForPrevious = false
        }
        lock.unlock()

        if let activeProfileURL = activeProfileURL {
            if isRunningForPrevious && previousURL == activeProfileURL {
                return
            }
            _ = start(url: activeProfileURL)
        } else {
            if isRunningForPrevious || previousURL != nil {
                stop()
            }
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
        stateUpdated?()
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
