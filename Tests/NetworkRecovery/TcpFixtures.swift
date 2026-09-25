import Foundation
import Network
import SwiftSignalKit
import Darwin

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
@available(macOS 14.0, *)
func checkEcho(port: NWEndpoint.Port) throws {
    let listener = try NWListener(using: .tcp, on: port)
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

if #available(macOS 14.0, *) {
    try checkEcho(port: .any)
    // Reserve a port without listening, so the first dial fails deterministically.
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    precondition(descriptor >= 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    precondition(bound == 0)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    precondition(named == 0)
    let port = UInt16(bigEndian: address.sin_port)
    let failure = Delegate()
    let unavailable = NetworkFrameworkTcpConnectionInterface(delegate: failure, delegateQueue: .main)
    _ = unavailable.connect(toHost: "127.0.0.1", onPort: port, viaInterface: nil, withTimeout: 3, error: nil)
    waitFor { failure.disconnects == 1 }
    precondition(failure.connects == 0)
    Darwin.close(descriptor)
    // The server recovers while the shared cooldown is active. Writes and reads queued
    // before NWConnection.start must survive admission and reach the echo server.
    try checkEcho(port: NWEndpoint.Port(rawValue: port)!)
    print("Production NW interface: refused endpoint recovered with pre-admission writes and reads")
}
