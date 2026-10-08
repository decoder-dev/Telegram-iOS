"""Exercise production Auto MTProxy transactions and connection timers with deterministic fixtures."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramCore/Sources/State/ManagedAutomaticMtProxy.swift').read_text(encoding='utf-8')

def extract(begin, end):
    offset = source.index(begin)
    return source[offset:source.index(end, offset) + len(end)]

reducers = extract('private func automaticMtProxyApplyCandidate(', '\n}') + '\n' + extract('private func automaticMtProxyMergeFetched(', '\n}')
methods = extract('    private func connectionStatusUpdated(', '\n    }') + '\n' + extract('    private func scheduleConnectionFallback(', '\n    }')
methods = methods.replace('private func', 'func')
fixture = r"""
import Foundation
struct ProxyServerSettings: Hashable { let id: Int }
struct ProxySettings: Equatable {
    var autoFetchPublicMtProxy = true
    var enabled = true
    var activeServer: ProxyServerSettings?
    var automaticServers: [ProxyServerSettings] = []
    var servers: [ProxyServerSettings] = []
}
let automaticMtProxyStoredLimit = 40
let automaticMtProxyProbeLimit = 20
let automaticMtProxyConnectionFallbackDelay: Double = 6
let a = ProxyServerSettings(id: 1), b = ProxyServerSettings(id: 2), manual = ProxyServerSettings(id: 3)
"""
tests = r"""
var settings = ProxySettings(activeServer: a, automaticServers: [a,b], servers: [manual])
precondition(automaticMtProxyApplyCandidate(settings, expectedActive: a, candidate: b).activeServer == b)
var disabled = settings; disabled.enabled = false
precondition(automaticMtProxyApplyCandidate(disabled, expectedActive: a, candidate: b) == disabled)
var off = settings; off.autoFetchPublicMtProxy = false
precondition(automaticMtProxyApplyCandidate(off, expectedActive: a, candidate: b) == off)
var userSelection = settings; userSelection.activeServer = manual
precondition(automaticMtProxyApplyCandidate(userSelection, expectedActive: a, candidate: b) == userSelection)
precondition(automaticMtProxyApplyCandidate(userSelection, expectedActive: manual, candidate: b) == userSelection)
var removed = settings; removed.automaticServers = [a]
precondition(automaticMtProxyApplyCandidate(removed, expectedActive: a, candidate: b) == removed)
// Refresh cannot enable a disabled route, including when the previous route disappeared.
let mergedDisabled = automaticMtProxyMergeFetched(disabled, fetched: [b])
precondition(!mergedDisabled.enabled && mergedDisabled.activeServer == a)
let refreshed = automaticMtProxyMergeFetched(settings, fetched: [b,manual])
precondition(refreshed.activeServer == a && refreshed.automaticServers.contains(a))
precondition(refreshed.servers == [manual] && !refreshed.automaticServers.contains(manual))
precondition(automaticMtProxyMergeFetched(userSelection, fetched: [b,manual]).activeServer == manual)
precondition(automaticMtProxyMergeFetched(off, fetched: [b]) == off)
precondition(automaticMtProxyMergeFetched(settings, fetched: []) == settings)
var initial = ProxySettings()
precondition(automaticMtProxyMergeFetched(initial, fetched: [b]).activeServer == b)
initial.enabled = false
precondition(automaticMtProxyMergeFetched(initial, fetched: [b]).activeServer == nil)
let pool = (10..<60).map { ProxyServerSettings(id: $0) }
let bounded = automaticMtProxyMergeFetched(settings, fetched: pool)
precondition(bounded.automaticServers.count == 40 && bounded.automaticServers.first == a)

// Deterministic timers exercise the actual production connection-status handlers.
enum ConnectionStatus { case online(proxyAddress: String?), connecting(proxyAddress: String?, proxyHasConnectionIssues: Bool), waitingForNetwork, updating(proxyAddress: String?) }
enum SwiftSignalKit {
    final class Timer {
        var valid = true
        let completion: () -> Void
        init(timeout: Double, repeat repeatValue: Bool, completion: @escaping () -> Void, queue: Int) { self.completion = completion }
        func start() {}
        func invalidate() { valid = false }
        func fire() { if valid { completion() } }
    }
}
enum ServersSignal { case single([ProxyServerSettings]) }
final class Candidates {
    var values: [ProxyServerSettings] = []
    func set(_ signal: ServersSignal) { if case let .single(values) = signal { self.values = values } }
}
final class Context {
    var waitingForNetwork = false
    var currentSettings = ProxySettings(activeServer: a, automaticServers: [a,b])
    var currentStatuses: [ProxyServerSettings: Int] = [a: 1]
    var excludedActiveServer: ProxyServerSettings?
    var connectionFallbackTimer: SwiftSignalKit.Timer?
    var selectionTimer: SwiftSignalKit.Timer?
    let candidateServers = Candidates()
    let queue = 0
    var selections = 0
    func scheduleBestProxySelection(immediate: Bool = false) { selections += 1 }
__METHODS__
}
for recovered in [ConnectionStatus.online(proxyAddress: nil), .updating(proxyAddress: nil), .waitingForNetwork] {
    let context = Context()
    context.connectionStatusUpdated(.connecting(proxyAddress: nil, proxyHasConnectionIssues: true))
    let timer = context.connectionFallbackTimer!
    context.connectionStatusUpdated(recovered)
    timer.fire()
    precondition(context.selections == 0 && context.connectionFallbackTimer == nil)
}
let stale = Context()
stale.connectionStatusUpdated(.connecting(proxyAddress: nil, proxyHasConnectionIssues: true))
stale.currentSettings.activeServer = b
stale.connectionFallbackTimer!.fire()
precondition(stale.selections == 0)
let failed = Context()
failed.connectionStatusUpdated(.connecting(proxyAddress: nil, proxyHasConnectionIssues: true))
let singleFlight = failed.connectionFallbackTimer!
failed.connectionStatusUpdated(.connecting(proxyAddress: nil, proxyHasConnectionIssues: true))
precondition(failed.connectionFallbackTimer === singleFlight)
singleFlight.fire()
precondition(failed.selections == 1 && failed.excludedActiveServer == a)
let offline = Context()
offline.connectionStatusUpdated(.waitingForNetwork)
precondition(offline.currentStatuses.isEmpty && offline.candidateServers.values.isEmpty)
offline.connectionStatusUpdated(.connecting(proxyAddress: nil, proxyHasConnectionIssues: false))
precondition(offline.candidateServers.values == [a,b])
let lateActive = Context()
lateActive.currentSettings.automaticServers = pool + [a]
lateActive.connectionStatusUpdated(.waitingForNetwork)
lateActive.connectionStatusUpdated(.connecting(proxyAddress: nil, proxyHasConnectionIssues: false))
precondition(lateActive.candidateServers.values.count == 20 && lateActive.candidateServers.values.contains(a))
print("Auto MTProxy: manual/OFF state, stale selection, list refresh, bounded pool, offline recovery and fallback timers passed")
"""
with tempfile.TemporaryDirectory(prefix='auto-mtproxy-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixture + reducers + tests.replace('__METHODS__', methods), encoding='utf-8')
    subprocess.run(['swift', str(file)], check=True)
