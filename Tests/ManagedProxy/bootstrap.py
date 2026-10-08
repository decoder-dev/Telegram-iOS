"""Run the production route application against a synchronous MTContext fixture."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramCore/Sources/Settings/ProxySettings.swift').read_text(encoding='utf-8')
start = source.index('func applySharedProxySettingsToNetwork(')
apply = source[start:source.index('\n}\n', start) + 2]
fixtures = r'''
import Foundation
final class MTSocksProxySettings: NSObject {
    let id: String
    init(_ id: String) { self.id = id }
    override func isEqual(_ object: Any?) -> Bool {
        return (object as? MTSocksProxySettings)?.id == self.id
    }
}
struct Connection {
    var isWebProxy = false
    var isVlessProxy = false
}
struct ProxyServerSettings {
    static let managedBootstrapProxySettings = MTSocksProxySettings("blocked")
    var connection: Connection
    var webProxyConfiguration: String? = nil
    var vlessProxyURL: String? = nil
    var mtProxySettings: MTSocksProxySettings? = nil
}
struct ProxySettings {
    var useLocalDNSForProxyHosts = false
    var effectiveActiveServer: ProxyServerSettings?
}
final class WebProxyManager {
    static let shared = WebProxyManager()
    func configure(activeWebProxy: String?) {}
    func isReady(for configuration: String) -> Bool { true }
}
final class VlessManager {
    static let shared = VlessManager()
    func configure(activeProfileURL: String?) {}
}
final class Environment {
    let socksProxySettings: MTSocksProxySettings?
    init(_ route: MTSocksProxySettings?) { self.socksProxySettings = route }
    func withUpdatedSocksProxySettings(_ route: MTSocksProxySettings?) -> Environment {
        return Environment(route)
    }
}
final class Context {
    var forceLocalDNS = false
    var environment = Environment(nil)
    var updates = 0
    func updateApiEnvironment(_ f: (Environment?) -> Environment?) {
        if let updated = f(environment) { environment = updated; updates += 1 }
    }
}
final class Network {
    let context = Context()
    var paused = false
    var resumedRoutes: [String] = []
    var drops = 0
    func pauseForWebProxyBootstrap() { paused = true }
    func resumeIfWebProxyBootstrapPaused() {
        if paused { resumedRoutes.append(context.environment.socksProxySettings?.id ?? "direct") }
        paused = false
    }
    func dropConnectionStatus() { drops += 1 }
    func rebuildTransport() {}
}
'''
tests = r'''
for web in [false, true] {
    for previous in [nil, "old-remote-proxy", "old-loopback-profile", "blocked"] as [String?] {
        let network = Network()
        network.context.environment = Environment(previous.map { MTSocksProxySettings($0) })
        var server = ProxyServerSettings(connection: Connection(isWebProxy: web, isVlessProxy: !web))
        var settings = ProxySettings(effectiveActiveServer: server)
        applySharedProxySettingsToNetwork(settings: settings, network: network)
        precondition(network.paused)
        precondition(network.context.environment.socksProxySettings?.id == "blocked")
        precondition(network.resumedRoutes.isEmpty)
        let updates = network.context.updates
        for _ in 0..<100 { applySharedProxySettingsToNetwork(settings: settings, network: network) }
        precondition(network.context.updates == updates, "Repeated bootstrap rebuilt the route")

        server.mtProxySettings = MTSocksProxySettings("new-loopback-profile")
        settings.effectiveActiveServer = server
        applySharedProxySettingsToNetwork(settings: settings, network: network)
        precondition(!network.paused)
        precondition(network.resumedRoutes == ["new-loopback-profile"], "Resumed before route update")
        settings.effectiveActiveServer = nil
        applySharedProxySettingsToNetwork(settings: settings, network: network)
        precondition(network.context.environment.socksProxySettings == nil)
    }
}
print("Managed bootstrap: previous routes blocked, repeated events coalesced, ready route installed before resume")
'''
with tempfile.TemporaryDirectory(prefix='managed-bootstrap-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixtures + apply + tests, encoding='utf-8')
    subprocess.run(['swift', str(file)], check=True)
