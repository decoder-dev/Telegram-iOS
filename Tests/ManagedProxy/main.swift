import Foundation
import SwiftSignalKit

let vless = ProxyServerSettings(host: "vless.example", port: 443, connection: .vless(secret: Data("vless-a".utf8)))
let other = ProxyServerSettings(host: "other.example", port: 443, connection: .vless(secret: Data("vless-b".utf8)))
let web = ProxyServerSettings(host: "web.example", port: 443, connection: .web(secret: Data([1])))
let manager = VlessManager.shared
manager.configuration = "vless-a"
let statuses = ProxyServersStatuses(network: Network(), servers: .single([vless, other, web]))
var latest: [ProxyServerSettings: ProxyServerStatus] = [:]
let subscription = (statuses.statuses() |> deliverOnMainQueue).start(next: {
    latest = $0
    print("Statuses:", $0.map { "\($0.key.host)=\($0.value)" }.sorted()); fflush(stdout)
})
func awaitState(_ name: String, _ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(predicate(), "Proxy status transition timed out: \(name)")
}
awaitState("initial") { latest.count == 3 && latest.values.allSatisfy { $0 == .notChecked } }
precondition(manager.mutations == 0 && WebProxyManager.shared.mutations == 0, "Observing a saved proxy switched the active tunnel")
precondition(latest.values.allSatisfy { $0 == .notChecked }, "Inactive tunnels were reported as failed or left checking")
manager.endpoint = VlessProxySink(port: 21001)
manager.events.putNext(1)
awaitState("first ready") { if case .available? = latest[vless] { return true }; return false }
precondition(latest[other] == .notChecked, "Another VLESS profile reused the active endpoint")
manager.configuration = "vless-b"
manager.endpoint = VlessProxySink(port: 21002)
manager.events.putNext(2)
awaitState("switch") { if case .available? = latest[other], latest[vless] == .notChecked { return true }; return false }
precondition(manager.mutations == 0, "Status refresh mutated tunnel configuration")
manager.endpoint = nil
manager.events.putNext(3)
awaitState("stopped") { latest[other] == .notChecked }
subscription.dispose()
print("Saved proxy observation, readiness events and profile isolation: passed")
