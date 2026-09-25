import Foundation
import Network
import SwiftSignalKit

protocol MTTcpConnectionInterface: AnyObject {}
protocol MTTcpConnectionInterfaceDelegate: AnyObject {
    func connectionInterfaceDidConnect()
    func connectionInterfaceDidDisconnectWithError(_ error: Error?)
    func connectionInterfaceDidRead(_ data: Data, withTag tag: Int, networkType: Int32)
    func connectionInterfaceDidReadPartialData(ofLength length: UInt, tag: Int)
}
final class MTNetworkUsageCalculationInfo: NSObject {}
let MTNetworkUsageManagerInterfaceOther = 0
let MTNetworkUsageManagerInterfaceWWAN = 1
final class MTNetworkUsageManager {
    init(info: MTNetworkUsageCalculationInfo) {}
    func addOutgoingBytes(_ length: UInt, interface: Int) {}
    func addIncomingBytes(_ length: UInt, interface: Int) {}
}
final class Logger {
    static let shared = Logger()
    func log(_ category: String, _ text: String) {}
}
final class Delegate: MTTcpConnectionInterfaceDelegate {
    var connects = 0
    var disconnects = 0
    var received = Data()
    func connectionInterfaceDidConnect() { connects += 1 }
    func connectionInterfaceDidDisconnectWithError(_ error: Error?) { disconnects += 1 }
    func connectionInterfaceDidRead(_ data: Data, withTag tag: Int, networkType: Int32) { received.append(data) }
    func connectionInterfaceDidReadPartialData(ofLength length: UInt, tag: Int) {}
}
func waitFor(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "loopback check timed out")
}
if #available(macOS 14.0, *) {
    let listener = try NWListener(using: .tcp, on: .any)
    var ready = false
    var accepted: [NWConnection] = []
    listener.stateUpdateHandler = { if case .ready = $0 { ready = true } }
    listener.newConnectionHandler = { connection in
        accepted.append(connection)
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
            precondition(error == nil)
            connection.send(content: data, completion: .contentProcessed { error in precondition(error == nil) })
        }
    }
    listener.start(queue: .main)
    waitFor { ready }
    let delegate = Delegate()
    let client = NetworkFrameworkTcpConnectionInterface(delegate: delegate, delegateQueue: .main)
    for _ in 0..<20 {
        _ = client.connect(toHost: "127.0.0.1", onPort: listener.port!.rawValue, viaInterface: nil, withTimeout: 3, error: nil)
    }
    let payload = Data([1, 2, 3, 4])
    client.write(payload)
    client.readData(toLength: 4, withTimeout: 3, tag: 1)
    waitFor { delegate.received == payload }
    precondition(accepted.count == 1 && delegate.connects == 1 && delegate.disconnects == 0)
    client.disconnect()
    waitFor { delegate.disconnects == 1 }
    accepted.forEach { $0.cancel() }
    listener.cancel()
    print("Production NW interface: repeated connect deduplicated, queued write/read and disconnect passed")
}
