import Foundation
import Network
import SwiftSignalKit

private let pathReconnectDebounceSeconds: Double = 1.5

/// Rebuild MtProto transport when the OS path changes (Wi‑Fi↔cellular, VPN up/down). SCNetworkReachability
/// often stays "reachable" through a VPN handoff while the old TCP routes are dead — without this the
/// app can sit "connecting" until manual retry.
func managedNetworkPathReconnect(network: Network) -> Signal<Never, NoError> {
    return Signal { _ in
        let monitor = NWPathMonitor()
        var lastSignature: String?
        var debounceTimer: SwiftSignalKit.Timer?
        let debounceQueue = Queue()
        
        monitor.pathUpdateHandler = { path in
            // Only the interface the system prefers decides: `availableInterfaces` lists every interface that is up,
            // and extra ones (AWDL for AirDrop and Handoff, a tunnel for Private Relay) come and go on their own
            // while the route in use stays the same. Counting them rebuilt the transport (and the proxy connection)
            // 153 times in two days of one device's log, 70% of them with the cellular or Wi-Fi route unchanged.
            // A VPN taking over the default route still changes the preferred interface, so it still rebuilds.
            let preferredInterface = path.availableInterfaces.first.map { String(describing: $0.type) } ?? "none"
            let signature = "\(String(describing: path.status))-\(preferredInterface)"
            guard path.status == .satisfied else {
                lastSignature = signature
                return
            }
            guard let previous = lastSignature, previous != signature else {
                lastSignature = signature
                return
            }
            lastSignature = signature
            
            debounceQueue.async {
                debounceTimer?.invalidate()
                debounceTimer = SwiftSignalKit.Timer(timeout: pathReconnectDebounceSeconds, repeat: false, completion: {
                    Logger.shared.log("Network", "path changed (\(previous) → \(signature)), rebuilding transport")
                    network.rebuildTransport()
                }, queue: debounceQueue)
                debounceTimer?.start()
            }
        }
        monitor.start(queue: DispatchQueue(label: "ManagedNetworkPathReconnect"))
        
        return ActionDisposable {
            debounceQueue.async {
                debounceTimer?.invalidate()
            }
            monitor.cancel()
        }
    }
}
