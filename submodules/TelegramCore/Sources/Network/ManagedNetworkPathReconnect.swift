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
        let queue = Queue(name: "ManagedNetworkPathReconnect")
        let disposed = Atomic(value: false)
        var lastSignature: String?
        var debounceTimer: SwiftSignalKit.Timer?
        
        monitor.pathUpdateHandler = { path in
            guard !disposed.with({ $0 }) else { return }
            // Only the interface the system prefers decides: `availableInterfaces` lists every interface that is up,
            // and extra ones (AWDL for AirDrop and Handoff, a tunnel for Private Relay) come and go on their own
            // while the route in use stays the same. Counting them rebuilt the transport (and the proxy connection)
            // 153 times in two days of one device's log, 70% of them with the cellular or Wi-Fi route unchanged.
            // A VPN taking over the default route still changes the preferred interface, so it still rebuilds.
            let preferredInterface = path.availableInterfaces.first.map { "\($0.type):\($0.name)" } ?? "none"
            let signature = "\(String(describing: path.status))-\(preferredInterface)"
            let previous = lastSignature
            lastSignature = signature
            guard path.status == .satisfied else {
                // A previously scheduled rebuild is obsolete as soon as the route is lost.
                debounceTimer?.invalidate()
                debounceTimer = nil
                return
            }
            guard let previous, previous != signature else {
                return
            }
            
            debounceTimer?.invalidate()
            debounceTimer = SwiftSignalKit.Timer(timeout: pathReconnectDebounceSeconds, repeat: false, completion: { timer in
                guard debounceTimer === timer, !disposed.with({ $0 }) else { return }
                debounceTimer = nil
                Logger.shared.log("Network", "path changed (\(previous) → \(signature)), rebuilding transport")
                network.rebuildTransport()
            }, queue: queue)
            debounceTimer?.start()
        }
        monitor.start(queue: queue.queue)
        
        return ActionDisposable {
            let _ = disposed.swap(true)
            monitor.cancel()
            queue.async {
                debounceTimer?.invalidate()
                debounceTimer = nil
            }
        }
    }
}
