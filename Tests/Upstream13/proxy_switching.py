"""Execute production factory selection through repeated route transitions."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
source = (ROOT / 'submodules/TelegramCore/Sources/Network/Network.swift').read_text(encoding='utf-8')
begin = source.index('    func updateWebSocketTransportSettings(')
websocket = source[begin:source.index('\n    }', begin) + 6]
begin = source.index('    func updateProxySettings(')
proxy = source[begin:source.index('        let updated =', begin)] + '    }\n'
settings = (ROOT / 'submodules/TelegramCore/Sources/Settings/ProxySettings.swift').read_text(encoding='utf-8')
assert settings.index('network.updateWebSocketTransportSettings(') < settings.index('network.updateProxySettings(activeServer)')
fixture = '''import Foundation
typealias Factory = (Int, Int, Int, Bool, Bool) -> String?
final class Context { var makeTcpConnectionInterface: Factory? }
struct ProxyServerSettings {
    var isWebProxy: Bool
    // A root-path WEB relay the fork's sidecar reached: MTProto dials its loopback over TCP.
    var sidecarReady = false
    var usesWebProxyCarrier: Bool { isWebProxy && !sidecarReady }
    var webProxyConfiguration: String? { isWebProxy ? "configured" : nil }
}
final class WebProxyTransport {
    static let shared = WebProxyTransport()
    func apply(configuration: String?) {}
    func makeConnectionInterface(delegate: Int, delegateQueue: Int) -> String { "web" }
}
final class Promise { func set(_ value: Bool) {} }
func applyWebSocketTransport(context: Context, webSocketTransportEnabled: Bool, webSocketFallbackToDirect: Bool, hasActiveProxyServer: Bool, useNetworkFramework: Bool, fallbackCoordinator: inout Bool) {
    let route = webSocketTransportEnabled && !hasActiveProxyServer ? "ws" : "tcp"
    context.makeTcpConnectionInterface = { _, _, _, _, _ in route }
}
final class Network {
    let context = Context()
    var baseTcpConnectionInterfaceFactory: Factory?
    var currentWebProxyActive = false
    let isAppExtension = false
    let usesNetworkFrameworkTcpConnection = true
    var webSocketFallbackCoordinator = false
    let webProxyActive = Promise()
''' + websocket + '\n' + proxy + '''
    func route() -> String? { context.makeTcpConnectionInterface!(0, 0, 0, false, false) }
}
let network = Network()
let web = ProxyServerSettings(isWebProxy: true)
let vless = ProxyServerSettings(isWebProxy: false)
let sidecarWeb = ProxyServerSettings(isWebProxy: true, sidecarReady: true)
for enabled in [false, true] {
    for server in [nil, web, vless, web, sidecarWeb, web, sidecarWeb, nil, vless, nil] as [ProxyServerSettings?] {
        network.updateWebSocketTransportSettings(webSocketTransportEnabled: enabled, webSocketFallbackToDirect: true, hasActiveProxyServer: server != nil)
        network.updateProxySettings(server)
        let expected = server?.usesWebProxyCarrier == true ? "web" : (enabled && server == nil ? "ws" : "tcp")
        precondition(network.route() == expected, "Initial route mismatch")
        // Independent Account settings observer must not overwrite an active Web carrier.
        for _ in 0..<100 {
            network.updateWebSocketTransportSettings(webSocketTransportEnabled: enabled, webSocketFallbackToDirect: true, hasActiveProxyServer: server != nil)
            precondition(network.route() == expected, "Repeated settings application replaced the proxy")
            network.updateProxySettings(server)
            precondition(network.route() == expected, "Stale base factory restored")
        }
    }
}
network.baseTcpConnectionInterfaceFactory = { _, _, _, _, _ in nil }
network.updateProxySettings(nil)
precondition(network.route() == nil, "Unavailable factory must not become a direct connection")
print("PASS production factory transitions, unavailable factory and repeated settings updates")
'''
with tempfile.TemporaryDirectory() as temporary:
    path = pathlib.Path(temporary)
    (path / 'main.swift').write_text(fixture, encoding='utf-8')
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'test')], check=True, timeout=60)
    subprocess.run([str(path / 'test')], check=True, timeout=15)
