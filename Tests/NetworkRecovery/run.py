"""Execute production recovery policies and EOF handling with deterministic inputs."""
import pathlib
import json
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]


def extract(path, start, end):
    text = (root / path).read_text()
    offset = text.index(start)
    return text[offset:text.index(end, offset) + len(end)]


health = extract('submodules/TelegramCore/Sources/Network/NetworkFrameworkTcpConnectionInterface.swift',
                 'struct NetworkEndpointHealth {', '\n}')
commit = extract('submodules/TelegramCore/Sources/Network/FetchV2.swift',
                 '        private func commitPendingReadyPart(', '\n        }').replace('private func', 'func', 1)
trim = extract('submodules/TelegramCore/Sources/State/AccountViewTracker.swift',
               '    func trimCachedData()', '\n    }')
ws_connect = extract('submodules/TelegramCore/Sources/Network/MTWebSocketConnectionInterface.swift',
                     '        func connect(timeout: Double)', '\n        }')
fixture = '''import Foundation
final class Logger {
    static let shared = Logger()
    func log(_ category: String, _ message: String) {}
}
let logFetchV2Parts = false
final class FetchingState { 
    var completedRanges = RangeSet<Int64>() 
    var downloadedUpperBound: Int64 = 0 
}
enum Event {
    case resourceSizeUpdated(Int64)
    case dataPart(resourceOffset: Int64, data: Data, range: Range<Int64>, complete: Bool)
}
final class Fetch {
    var knownSize: Int64?
    let loggingIdentifier = "test"
    var events: [Event] = []
    func onNext(_ event: Event) { events.append(event) }
'''
fixture += commit + '\n}\n'
fixture += '''
final class ImmediateQueue { func async(_ f: () -> Void) { f() } }
final class PeerContext { var viewIds: Set<Int> = [] }
final class Tracker {
    let queue = ImmediateQueue()
    var cachedDataContexts: [Int: PeerContext] = [:]
''' + trim + '\n}\n'
fixture += '''
struct Selector { var resets = 0; mutating func reset() { resets += 1 } }
final class WebSocketDial {
    var connection: Int?
    var connectTimeout: Double = 0
    var didRequestConnect = false
    var reportedDisconnection = false
    var endpointSelector = Selector()
    var dials = 0
    func dialCurrentCandidate() { dials += 1 }
''' + ws_connect + '\n}\n'

tests = '''
var health = NetworkEndpointHealth()
let endpoint = "194.221.250.50:443"
precondition(health.delay(endpoint: endpoint, attempt: 1, now: 100) == 0)
health.failed(endpoint: endpoint, attempt: 1, now: 100)
// A burst of failing contexts must not multiply one outage into 100 backoff steps.
for id in UInt64(2)...100 { health.failed(endpoint: endpoint, attempt: id, now: 100) }
precondition(health.delay(endpoint: endpoint, attempt: 101, now: 100.5) == 0.5)
precondition(health.delay(endpoint: "another-dc:443", attempt: 102, now: 100.5) == 0)
precondition(health.delay(endpoint: endpoint, attempt: 101, now: 101) == 0)
for id in UInt64(102)...201 { precondition(health.delay(endpoint: endpoint, attempt: id, now: 101) > 0) }
// A cancelled waiter cannot release another connection's half-open probe.
health.cancelled(endpoint: endpoint, attempt: 102)
precondition(health.delay(endpoint: endpoint, attempt: 103, now: 101) > 0)
health.cancelled(endpoint: endpoint, attempt: 101)
precondition(health.delay(endpoint: endpoint, attempt: 103, now: 101) == 0)
health.failed(endpoint: endpoint, attempt: 103, now: 101)
precondition(health.delay(endpoint: endpoint, attempt: 104, now: 102) == 1)
health.succeeded(endpoint: endpoint)
for id in UInt64(105)...205 { precondition(health.delay(endpoint: endpoint, attempt: id, now: 102) == 0) }
var now: Double = 200
for id in UInt64(300)...320 {
    precondition(health.delay(endpoint: endpoint, attempt: id, now: now) == 0)
    health.failed(endpoint: endpoint, attempt: id, now: now)
    let delay = health.delay(endpoint: endpoint, attempt: id + 1, now: now)
    precondition(delay > 0 && delay <= 8)
    now += delay
}

// All permutations of a full block, final partial block and an empty read beyond EOF.
let block: Int64 = 128 * 1024
for order in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]] {
    let fetch = Fetch()
    let state = FetchingState()
    for part in order {
        let offset = Int64(part) * block
        let range = offset..<(offset + block)
        let length = part == 0 ? block : (part == 1 ? block / 2 : 0)
        fetch.commitPendingReadyPart(state: state, partRange: range, fetchRange: range, data: Data(count: Int(length)))
    }
    precondition(fetch.knownSize == block + block / 2, "out-of-order EOF: \\(order)")
    let sizes = fetch.events.compactMap { event -> Int64? in
        if case let .resourceSizeUpdated(size) = event { return size }; return nil
    }
    precondition(sizes.last == block + block / 2)
}
// An exact multiple requires the empty response to establish EOF too.
let exact = Fetch()
let exactState = FetchingState()
exact.commitPendingReadyPart(state: exactState, partRange: 0..<block, fetchRange: 0..<block, data: Data(count: Int(block)))
exact.commitPendingReadyPart(state: exactState, partRange: block..<(2*block), fetchRange: block..<(2*block), data: Data())
precondition(exact.knownSize == block)
let tracker = Tracker()
let active = PeerContext(); active.viewIds.insert(7)
tracker.cachedDataContexts = [1: active, 2: PeerContext()]
tracker.trimCachedData()
precondition(tracker.cachedDataContexts.count == 1 && tracker.cachedDataContexts[1] === active)
print("Endpoint cooldown, probe ownership, EOF permutations and active cache ownership: passed")
let ws = WebSocketDial()
for _ in 0..<100 { ws.connect(timeout: 12) }
precondition(ws.dials == 1 && ws.endpointSelector.resets == 1)
let closed = WebSocketDial()
closed.reportedDisconnection = true
closed.connect(timeout: 12)
precondition(closed.dials == 0)
print("WebSocket connect coalescing across candidate gaps and terminal close: passed")
'''
with tempfile.TemporaryDirectory(prefix='telegram-recovery-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixture + health + tests)
    subprocess.run(['swift', str(file)], check=True)
    manager = (root / 'submodules/WebProxyTransport/Sources/WebProxyManager.swift').read_text()
    manager = manager.replace('import Network\n', '')
    file.write_text(manager + '\n' + (root / 'Tests/NetworkRecovery/ManagerFixtures.swift').read_text())
    subprocess.run(['swift', str(file)], check=True)
    # Compile and execute the actual NW interface against Apple's Network.framework.
    package = pathlib.Path(tmp) / 'TcpCheck'
    sources = package / 'Sources/Checks'
    sources.mkdir(parents=True)
    tcp = (root / 'submodules/TelegramCore/Sources/Network/NetworkFrameworkTcpConnectionInterface.swift').read_text()
    (sources / 'Tcp.swift').write_text(tcp.replace('import MtProtoKit\n', ''))
    (sources / 'main.swift').write_text((root / 'Tests/NetworkRecovery/TcpFixtures.swift').read_text())
    dependency = json.dumps(str(root / 'submodules/SSignalKit'))
    (package / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "TcpRecoveryChecks", platforms: [.macOS(.v14)],
dependencies: [.package(path: ''' + dependency + ''')],
targets: [.executableTarget(name: "Checks", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")])])
''')
    subprocess.run(['swift', 'run', '--package-path', str(package), 'Checks'], check=True)
