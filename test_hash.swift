import Foundation
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
}
let vless = ProxyServerSettings(host: "vless.example", port: 443, connection: .vless(secret: Data("vless-a".utf8)))
let other = ProxyServerSettings(host: "other.example", port: 443, connection: .vless(secret: Data("vless-b".utf8)))
let web = ProxyServerSettings(host: "web.example", port: 443, connection: .web(secret: Data([1])))
print(Set([vless, other, web]).count)
