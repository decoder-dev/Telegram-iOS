import Foundation
import SwiftSignalKit

public struct VlessProxySink: Equatable {
    var host = "127.0.0.1"
    var port: Int
    var user = "user"
    var password = "password"
}
public final class VlessManager {
    static let shared = VlessManager()
    var configuration: String?
    var endpoint: VlessProxySink?
    var mutations = 0
    let events = ValuePipe<Int>()
    var stateEvents: Signal<Int, NoError> { events.signal() }
    var activeLoopbackEndpoint: VlessProxySink? { endpoint }
    func configure(activeProfileURL: String?) { mutations += 1 }
    func loopbackEndpoint(for url: String) -> VlessProxySink? { configuration == url ? endpoint : nil }
}
public struct WebProxyConfiguration: Equatable {
    var hostname: String
    var secret: Data
}
public final class WebProxyManager {
    typealias SidecarEventToken = Int
    static let shared = WebProxyManager()
    var configuration: WebProxyConfiguration?
    var endpoint: MTSocksProxySettings?
    var handlers: [Int: (Int) -> Void] = [:]
    var nextToken = 0
    var mutations = 0
    var activeLoopbackEndpoint: MTSocksProxySettings? { endpoint }
    func isReady(for value: WebProxyConfiguration) -> Bool { configuration == value && endpoint != nil }
    func loopbackEndpoint(for value: WebProxyConfiguration) -> MTSocksProxySettings? { configuration == value ? endpoint : nil }
    func configure(activeWebProxy: WebProxyConfiguration?) { mutations += 1 }
    func addSidecarEventHandler(_ handler: @escaping (Int) -> Void) -> Int {
        nextToken += 1; handlers[nextToken] = handler; return nextToken
    }
    func removeSidecarEventHandler(_ token: Int) { handlers.removeValue(forKey: token) }
}
public struct ProxyServerSettings: Hashable {
    public enum Connection: Hashable {
        case socks5(username: String?, password: String?)
        case mtp(secret: Data)
        case web(secret: Data)
        case vless(secret: Data)
    }
    public var host: String
    public var port: Int32
    public var connection: Connection
    var vlessProxyURL: String? {
        if case let .vless(secret) = connection { return String(data: secret, encoding: .utf8) }
        return nil
    }
}
public final class MTContext {}
public final class Network {
    let context = MTContext()
    let datacenterId = 1
}
public struct MTSocksProxySettings {
    var host: String
    var port: UInt16
    var username: String?
    var password: String?
    var secret: Data?
    init(ip: String, port: UInt16, username: String?, password: String?, secret: Data?) {
        host = ip; self.port = port; self.username = username; self.password = password; self.secret = secret
    }
}
struct MTProxyConnectivityStatus { var reachable = true; var roundTripTime = 0.01 }
final class Ping {
    func start(next: (Any) -> Void) -> Disposable? { next(MTProxyConnectivityStatus()); return EmptyDisposable }
}
enum MTProxyConnectivity {
    static func pingProxy(with: MTContext, datacenterId: Int, settings: MTSocksProxySettings) -> Ping { Ping() }
}
