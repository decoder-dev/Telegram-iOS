"""Execute production recovery policies and EOF handling with deterministic inputs."""
import pathlib
import json
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]


def extract(path, start, end):
    text = (root / path).read_text(encoding="utf-8")
    offset = text.index(start)
    return text[offset:text.index(end, offset) + len(end)]


health = extract('submodules/TelegramCore/Sources/Network/NetworkFrameworkTcpConnectionInterface.swift',
                 'struct NetworkEndpointHealth {', '\n}')
fetch_source = 'submodules/TelegramCore/Sources/Network/FetchV2.swift'
commit = extract(fetch_source, '        private func commitPendingReadyPart(', '\n        }').replace('private func', 'func', 1)
priority = extract('submodules/Postbox/Sources/MediaBox.swift', 'public enum MediaBoxFetchPriority:', '\n}')
reference_cache = extract(fetch_source, 'final class FetchV2FileReferenceCache {', '\n}')
part_alignment = extract(fetch_source, 'private let possiblePartLengths:', '\n}')
range_filter_end = '\n                var maxPendingParts = state.maxPendingParts'
range_filter = extract(fetch_source, '                var filteredRequiredRanges:', range_filter_end).removesuffix(range_filter_end)
part_schedule = extract(fetch_source, '                    while state.pendingParts.count < maxPendingParts', '\n                    }')
revalidation_source = 'submodules/TelegramCore/Sources/Network/FetchedMediaResource.swift'
revalidation_error = extract(revalidation_source, 'enum RevalidateMediaReferenceError', '\n}')
revalidation_end = '\n\nfinal class MediaReferenceRevalidationContext {'
revalidation = extract(revalidation_source, 'private typealias MediaReferenceRevalidationResult', revalidation_end).removesuffix(revalidation_end)
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
struct MediaResourceId { let stringRepresentation: String }
protocol TelegramMediaResource { var id: MediaResourceId { get } }
struct CloudFile: TelegramMediaResource {
    let id: MediaResourceId
    let accessHash: Int64
}
''' + reference_cache + '\n'
fixture += part_alignment + '\n' + priority + '''
struct PendingPart {
    let partRange: Range<Int64>
    let fetchRange: Range<Int64>
}
struct CdnReupload {
    let ranges: RangeSet<Int64>
}
struct RequestedRange {
    let value: Range<Int64>
    let priority: MediaBoxFetchPriority
}
struct SchedulingState {
    let partSize: Int64
    let minPartSize: Int64
    let maxPartSize: Int64
    let partAlignment: Int64
    let partDivision: Int64 = 1024 * 1024
    let maxPendingParts = 6
    var nextRangePriorityIndex = 0
    var completedRanges = RangeSet<Int64>()
    var pendingParts: [PendingPart] = []
    var pendingReadyParts: [PendingPart] = []
    var pendingCdnReuploads: [CdnReupload] = []
}
struct Scheduler {
    let requiredRanges: [RequestedRange]
    let knownSize: Int64?
    let loggingIdentifier = "test"

    func schedule(state: inout SchedulingState) -> [RangeSet<Int64>] {
''' + range_filter + '''
        let unscheduledRanges = filteredRequiredRanges
        let maxPendingParts = state.maxPendingParts
''' + part_schedule + '''
        return unscheduledRanges
    }
}
'''
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

let block: Int64 = 128 * 1024
let mediaId = MediaResourceId(stringRepresentation: "video")
let staleReference = Data([1])
let freshReference = Data([2])
let fileReferenceCache = FetchV2FileReferenceCache()
let updatedFile = CloudFile(id: mediaId, accessHash: 42)
fileReferenceCache.store(resource: updatedFile, reference: freshReference, originalReference: staleReference)
let replacement = fileReferenceCache.replacement(for: mediaId, originalReference: staleReference)
precondition(replacement?.reference == freshReference && (replacement?.resource as? CloudFile)?.accessHash == 42)
precondition(fileReferenceCache.replacement(for: mediaId, originalReference: Data([3])) == nil)
precondition(fileReferenceCache.replacement(for: MediaResourceId(stringRepresentation: "other"), originalReference: staleReference) == nil)
precondition(FetchV2FileReferenceCache().replacement(for: mediaId, originalReference: staleReference) == nil)
fileReferenceCache.store(resource: updatedFile, reference: Data(), originalReference: staleReference)
precondition(fileReferenceCache.replacement(for: mediaId, originalReference: staleReference)?.reference == freshReference)

// A full download, playback and an explicit fetch may ask for the same bytes. A high-priority
// subrange owns those bytes, and alignment must reserve the actual request in every bucket.
let overlappingRanges = Scheduler(requiredRanges: [
    RequestedRange(value: 0..<block, priority: .default),
    RequestedRange(value: 0..<(block / 2), priority: .elevated),
    RequestedRange(value: (block / 4)..<(block / 2), priority: .maximum),
], knownSize: block)
let geometries: [(partSize: Int64, minPartSize: Int64, maxPartSize: Int64, alignment: Int64, expectedRequests: Int)] = [
    (block, 4096, 8 * block, 4096, 3),
    (4 * block, 4096, 8 * block, 4096, 3),
    (block, block, 2 * block, block, 1),
]
for (partSize, minPartSize, maxPartSize, alignment, expectedRequests) in geometries {
    var state = SchedulingState(partSize: partSize, minPartSize: minPartSize, maxPartSize: maxPartSize, partAlignment: alignment)
    let ranges = overlappingRanges.schedule(state: &state)
    precondition(ranges == [RangeSet((block / 2)..<block), RangeSet(0..<(block / 4)), RangeSet((block / 4)..<(block / 2))])
    precondition(state.pendingParts.count == expectedRequests)
    precondition(Set(state.pendingParts.map(\\.fetchRange)).count == expectedRequests)
    let pendingCount = state.pendingParts.count
    _ = overlappingRanges.schedule(state: &state)
    precondition(state.pendingParts.count == pendingCount, "An update must respect reservations from earlier passes")
}

let withinMasterAlignment = Scheduler(requiredRanges: [
    RequestedRange(value: 0..<1024, priority: .default),
    RequestedRange(value: 2048..<4096, priority: .maximum),
], knownSize: block)
var master = SchedulingState(partSize: block, minPartSize: 4096, maxPartSize: 8 * block, partAlignment: 4096)
_ = withinMasterAlignment.schedule(state: &master)
precondition(master.pendingParts.map(\\.fetchRange) == [0..<4096])

// Disjoint priorities near a division boundary still align to one physical CDN part.
let boundary = 8 * block
let clippedRanges = Scheduler(requiredRanges: [
    RequestedRange(value: (boundary - 32)..<(boundary - 24), priority: .default),
    RequestedRange(value: (boundary - 8)..<(boundary + 200), priority: .elevated),
], knownSize: boundary + 4)
var cdn = SchedulingState(partSize: block, minPartSize: block, maxPartSize: 2 * block, partAlignment: block)
let clipped = clippedRanges.schedule(state: &cdn)
precondition(clipped[1] == RangeSet((boundary - 8)..<(boundary + 4)))
precondition(cdn.pendingParts.map(\\.fetchRange) == [(boundary - block)..<boundary, boundary..<(boundary + block)])
print("Multipart priority ranges, aligned reservations and division boundaries: passed")

// All permutations of a full block, final partial block and an empty read beyond EOF.
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
// A short reply behind bytes already received must not truncate MediaBox through
// resourceSizeUpdated, even when there is no previously known file size.
for knownSize: Int64? in [nil, 4 * block] {
    let fetch = Fetch()
    fetch.knownSize = knownSize
    let state = FetchingState()
    fetch.commitPendingReadyPart(state: state, partRange: block..<(2*block), fetchRange: block..<(2*block), data: Data(count: Int(block)))
    fetch.events.removeAll()
    fetch.commitPendingReadyPart(state: state, partRange: 0..<block, fetchRange: 0..<block, data: Data())
    precondition(fetch.knownSize == knownSize)
    precondition(fetch.events.isEmpty, "Rejected EOF leaked a resource size to the cache")
}
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
    handshake = extract('submodules/TelegramCore/Sources/Network/MTWebSocketConnectionInterface.swift',
                        '        private func beginWebSocketHandshake()', '\n        }').replace('private func', 'func', 1)
    handshake_fixture = (root / 'Tests/NetworkRecovery/HandshakeFixtures.swift').read_text(encoding='utf-8')
    file.write_text(handshake_fixture.replace('// PRODUCTION_HANDSHAKE', handshake), encoding='utf-8')
    subprocess.run(['swift', str(file)], check=True)
    file.write_text(fixture + health + tests)
    subprocess.run(['swift', str(file)], check=True)
    revalidation_fixture = (root / 'Tests/NetworkRecovery/RevalidationFixtures.swift').read_text(encoding='utf-8')
    bag = (root / 'submodules/SSignalKit/SwiftSignalKit2/Source/Bag.swift').read_text(encoding='utf-8')
    file.write_text(revalidation_fixture.replace('// PRODUCTION_REVALIDATION', bag + '\n' + revalidation_error + '\n' + revalidation))
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
