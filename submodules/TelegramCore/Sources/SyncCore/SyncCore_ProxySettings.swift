import Foundation
import Postbox

public enum ProxyServerConnection: Equatable, Hashable, Codable {
    case socks5(username: String?, password: String?)
    case mtp(secret: Data)
    /// WEB proxy (tproxy-server): hostname is the masking HTTPS site; traffic is tunneled via WebView/HTTPS carrier.
    case web(secret: Data)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        switch try container.decode(Int32.self, forKey: "_t") {
            case 0:
                self = .socks5(username: try container.decodeIfPresent(String.self, forKey: "username"), password: try container.decodeIfPresent(String.self, forKey: "password"))
            case 1:
                self = .mtp(secret: try container.decode(Data.self, forKey: "secret"))
            case 2:
                self = .web(secret: try container.decode(Data.self, forKey: "secret"))
            default:
                self = .socks5(username: nil, password: nil)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        switch self {
            case let .socks5(username, password):
                try container.encode(0 as Int32, forKey: "_t")
                try container.encodeIfPresent(username, forKey: "username")
                try container.encodeIfPresent(password, forKey: "password")
            case let .mtp(secret):
                try container.encode(1 as Int32, forKey: "_t")
                try container.encode(secret, forKey: "secret")
            case let .web(secret):
                try container.encode(2 as Int32, forKey: "_t")
                try container.encode(secret, forKey: "secret")
        }
    }
    
    public var isWebProxy: Bool {
        if case .web = self {
            return true
        }
        return false
    }
}

public struct ProxyServerSettings: Codable, Equatable, Hashable {
    public let host: String
    public let port: Int32
    public let connection: ProxyServerConnection
    
    public init(host: String, port: Int32, connection: ProxyServerConnection) {
        self.host = host
        self.port = port
        self.connection = connection
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.host = (try? container.decode(String.self, forKey: "host")) ?? ""
        self.port = (try? container.decode(Int32.self, forKey: "port")) ?? 0
        if let username = try container.decodeIfPresent(String.self, forKey: "username") {
            self.connection = .socks5(username: username, password: try container.decodeIfPresent(String.self, forKey: "password"))
        } else {
            self.connection = (try? container.decodeIfPresent(ProxyServerConnection.self, forKey: "connection")) ?? ProxyServerConnection.socks5(username: nil, password: nil)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.host, forKey: "host")
        try container.encode(self.port, forKey: "port")
        try container.encode(self.connection, forKey: "connection")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.host)
        hasher.combine(self.port)
        hasher.combine(self.connection)
    }
}

/// Android-style wait-before-probe values for manual proxy rotation (`ProxyRotationController`).
public enum ProxyRotationTimeouts {
    public static let seconds: [Int32] = [5, 10, 15, 30, 60]
    public static let defaultIndex: Int32 = 1
    
    public static func timeoutSeconds(at index: Int32) -> Double {
        let clamped = max(0, min(Int(index), seconds.count - 1))
        return Double(seconds[clamped])
    }
}

public struct ProxySettings: Codable, Equatable {
    public var enabled: Bool
    public var servers: [ProxyServerSettings]
    public var activeServer: ProxyServerSettings?
    public var useForCalls: Bool
    /// Resolve SOCKS/MTProxy hostnames via system DNS (skip Google DoH-first).
    public var useLocalDNSForProxyHosts: Bool
    /// When stuck connecting via the active proxy, probe saved servers and switch to the lowest-latency live one.
    public var autoRotateProxies: Bool
    /// Index into `ProxyRotationTimeouts.seconds` (5/10/15/30/60 s wait while connecting via proxy).
    public var proxyRotationTimeoutIndex: Int32
    /// Fetch public MTProxy servers, probe RTT, and fail over to the fastest live one.
    public var autoFetchPublicMtProxy: Bool
    /// Servers last pulled by auto-fetch (kept separate from manually added entries).
    public var automaticServers: [ProxyServerSettings]
    /// Native WebSocket MTProto transport (routes traffic through `kwsN.web.telegram.org/apiws` instead
    /// of a raw TCP socket). Independent of `enabled`/`servers`/`activeServer` — it changes how MtProtoKit
    /// opens its socket, not which SOCKS5/MTProxy server is used. See docs/websocket-transport.md.
    public var webSocketTransportEnabled: Bool
    /// When true, falls back to MtProtoKit's normal TCP transport after repeated WebSocket endpoint
    /// failures for the rest of the session. When false, the app keeps retrying WebSocket endpoints only
    /// (appropriate when the user's whole point is bypassing TCP-level blocking).
    public var webSocketFallbackToDirect: Bool
    
    public static var defaultSettings: ProxySettings {
        return ProxySettings(enabled: false, servers: [], activeServer: nil, useForCalls: false, useLocalDNSForProxyHosts: false, autoRotateProxies: false, proxyRotationTimeoutIndex: ProxyRotationTimeouts.defaultIndex, autoFetchPublicMtProxy: false, automaticServers: [])
    }
    
    public init(enabled: Bool, servers: [ProxyServerSettings], activeServer: ProxyServerSettings?, useForCalls: Bool, useLocalDNSForProxyHosts: Bool = false, autoRotateProxies: Bool = false, proxyRotationTimeoutIndex: Int32 = ProxyRotationTimeouts.defaultIndex, autoFetchPublicMtProxy: Bool = false, automaticServers: [ProxyServerSettings] = [], webSocketTransportEnabled: Bool = false, webSocketFallbackToDirect: Bool = true) {
        self.enabled = enabled
        self.servers = servers
        self.activeServer = activeServer
        self.useForCalls = useForCalls
        self.useLocalDNSForProxyHosts = useLocalDNSForProxyHosts
        self.autoRotateProxies = autoRotateProxies
        self.proxyRotationTimeoutIndex = proxyRotationTimeoutIndex
        self.autoFetchPublicMtProxy = autoFetchPublicMtProxy
        self.automaticServers = automaticServers
        self.webSocketTransportEnabled = webSocketTransportEnabled
        self.webSocketFallbackToDirect = webSocketFallbackToDirect
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.enabled = ((try? container.decode(Int32.self, forKey: "enabled")) ?? 0) != 0
        self.servers = try container.decode([ProxyServerSettings].self, forKey: "servers")
        self.activeServer = try container.decodeIfPresent(ProxyServerSettings.self, forKey: "activeServer")
        self.useForCalls = ((try? container.decode(Int32.self, forKey: "useForCalls")) ?? 0) != 0
        self.useLocalDNSForProxyHosts = ((try? container.decode(Int32.self, forKey: "useLocalDNSForProxyHosts")) ?? 0) != 0
        self.autoRotateProxies = ((try? container.decode(Int32.self, forKey: "autoRotateProxies")) ?? 0) != 0
        self.proxyRotationTimeoutIndex = (try? container.decode(Int32.self, forKey: "proxyRotationTimeoutIndex")) ?? ProxyRotationTimeouts.defaultIndex
        if let stored = try? container.decode(Int32.self, forKey: "autoFetchMtProxy") {
            self.autoFetchPublicMtProxy = stored != 0
        } else {
            // No stored value means the user never opted in — including every account upgrading
            // from a build without this feature. Defaulting to true here would route their
            // traffic through a public proxy they never chose, on the first launch after update.
            self.autoFetchPublicMtProxy = false
        }
        self.automaticServers = (try? container.decode([ProxyServerSettings].self, forKey: "automaticServers")) ?? []
        self.webSocketTransportEnabled = ((try? container.decode(Int32.self, forKey: "webSocketTransportEnabled")) ?? 0) != 0
        self.webSocketFallbackToDirect = ((try? container.decode(Int32.self, forKey: "webSocketFallbackToDirect")) ?? 1) != 0
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.enabled ? 1 : 0) as Int32, forKey: "enabled")
        try container.encode(self.servers, forKey: "servers")
        try container.encodeIfPresent(self.activeServer, forKey: "activeServer")
        try container.encode((self.useForCalls ? 1 : 0) as Int32, forKey: "useForCalls")
        try container.encode((self.useLocalDNSForProxyHosts ? 1 : 0) as Int32, forKey: "useLocalDNSForProxyHosts")
        try container.encode((self.autoRotateProxies ? 1 : 0) as Int32, forKey: "autoRotateProxies")
        try container.encode(self.proxyRotationTimeoutIndex, forKey: "proxyRotationTimeoutIndex")
        // Key name is "autoFetchMtProxy" because that is what init(from:) reads; a second copy
        // under "autoFetchPublicMtProxy" was written here and never read by anything.
        try container.encode((self.autoFetchPublicMtProxy ? 1 : 0) as Int32, forKey: "autoFetchMtProxy")
        try container.encode(self.automaticServers, forKey: "automaticServers")
        try container.encode((self.webSocketTransportEnabled ? 1 : 0) as Int32, forKey: "webSocketTransportEnabled")
        try container.encode((self.webSocketFallbackToDirect ? 1 : 0) as Int32, forKey: "webSocketFallbackToDirect")
    }
    
    public var effectiveActiveServer: ProxyServerSettings? {
        if self.enabled, let activeServer = self.activeServer {
            return activeServer
        } else {
            return nil
        }
    }
    
    /// Enable or disable public MTProxy auto-fetch. Turning off removes only auto-pulled servers.
    public mutating func setAutoFetchPublicMtProxy(_ enabled: Bool) {
        self.autoFetchPublicMtProxy = enabled
        if enabled {
            self.enabled = true
            return
        }
        let automatic = Set(self.automaticServers)
        if !automatic.isEmpty {
            self.servers = self.servers.filter { !automatic.contains($0) }
        }
        self.automaticServers = []
        if let active = self.activeServer, automatic.contains(active) {
            self.activeServer = self.servers.first
            self.enabled = self.activeServer != nil
        }
    }
}
