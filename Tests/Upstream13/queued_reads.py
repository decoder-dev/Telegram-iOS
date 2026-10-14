"""Automatic content-read cancellation: production helper and execution guards."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PATH = ROOT / 'submodules/TelegramCore/Sources/State/ManagedSynchronizeConsumeMessageContentsOperations.swift'
SOURCE = PATH.read_text(encoding='utf-8')


class QueuedReads(unittest.TestCase):
    def test_permission_changes_suspend_without_removing_durable_entries(self):
        self.assertIn('ForkGhostModeSettings.automaticContentReadPermissionsChanged', SOURCE)
        self.assertIn('deliverOn(queue)', SOURCE)
        self.assertIn('helper.update(entries.filter { !ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: stateManager.accountPeerId, peerId: $0.peerId) })', SOURCE)
        self.assertIn('filterByPeerId: peerId, limit: 10', SOURCE)
        body = SOURCE.split('private func synchronizeConsumeMessageContents(', 1)[1]
        self.assertLess(body.index('guard !ForkGhostModeSettings.shouldSuppressMessageReads'), body.index('network.request'))
        self.assertIn('return .never()', body.split('network.request', 1)[0])
        policy = (ROOT / 'submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift').read_text(encoding='utf-8')
        observer = policy.split('public static var automaticContentReadPermissionsChanged:', 1)[1].split('public static var shouldSuppressOnline', 1)[0]
        self.assertIn('forName: didChangeNotification', observer)
        self.assertIn('subscriber.putNext(())', observer)
        self.assertIn('NotificationCenter.default.removeObserver(observer)', observer)
        # Manual Mark Read remains an explicit action, outside this automatic queue.
        manual = (ROOT / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift').read_text(encoding='utf-8')
        explicit = manual.split('func _internal_togglePeerUnreadMarkInteractively(transaction:', 1)[1].split('public func clearPeerUnseenPersonalMessagesInteractively', 1)[0]
        self.assertNotIn('shouldSuppressMessageReads', explicit)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; real helper executes in macOS CI')
    def test_actual_helper_cancels_and_resumes_once_per_peer(self):
        helper = SOURCE.split('private final class ManagedSynchronizeConsumeMessageContentsOperationHelper', 1)[1].split('private func withTakenOperation', 1)[0]
        predicate = 'entries.filter { !ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: stateManager.accountPeerId, peerId: $0.peerId) }'
        self.assertIn(predicate, SOURCE)
        fixture = '''import Foundation
protocol Disposable { func dispose() }
final class MetaDisposable: Disposable { var disposed = false; func dispose() { disposed = true } }
struct PeerMergedOperationLogEntry { let peerId: Int; let mergedIndex: Int32 }
typealias PeerId = Int
private final class ManagedSynchronizeConsumeMessageContentsOperationHelper''' + helper + '''
struct View { let entries: [PeerMergedOperationLogEntry] }
let view = View(entries: [.init(peerId: 1, mergedIndex: 10), .init(peerId: 1, mergedIndex: 11), .init(peerId: 2, mergedIndex: 12)])
private let helper = ManagedSynchronizeConsumeMessageContentsOperationHelper()
var readsAllowed = true
var exceptionPeers: Set<Int> = []
enum ForkGhostModeSettings {
    static func shouldSuppressMessageReads(accountPeerId: Int, peerId: Int) -> Bool {
        return !readsAllowed && !exceptionPeers.contains(peerId)
    }
}
struct StateManager { let accountPeerId: Int }
let stateManager = StateManager(accountPeerId: 100)
let entries = view.entries
let initial = helper.update(PREDICATE)
precondition(initial.beginOperations.count == 2 && initial.disposeOperations.isEmpty)
precondition(helper.update(PREDICATE).beginOperations.isEmpty)
readsAllowed = false
let suspended = helper.update(PREDICATE)
precondition(suspended.beginOperations.isEmpty && suspended.disposeOperations.count == 2)
for disposable in suspended.disposeOperations { disposable.dispose() }
precondition(initial.beginOperations.allSatisfy { $0.1.disposed })
precondition(helper.update(PREDICATE).beginOperations.isEmpty)
readsAllowed = true
let resumed = helper.update(PREDICATE)
precondition(resumed.beginOperations.count == 2 && resumed.disposeOperations.isEmpty)
precondition(helper.update(PREDICATE).beginOperations.isEmpty)
readsAllowed = false
exceptionPeers = [2]
let excepted = helper.update(PREDICATE)
precondition(excepted.disposeOperations.count == 1 && excepted.beginOperations.isEmpty)
exceptionPeers = [1, 2]
precondition(helper.update(PREDICATE).beginOperations.count == 1)
exceptionPeers = []
precondition(helper.update(PREDICATE).disposeOperations.count == 2)
precondition(helper.reset().isEmpty)
print("Queued content reads: actual cancellation/resumption helper passed")
'''
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / 'main.swift'
            executable = pathlib.Path(directory) / 'fixture'
            source.write_text(fixture.replace('PREDICATE', predicate), encoding='utf-8')
            subprocess.run(['swiftc', str(source), '-o', str(executable)], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == '__main__':
    unittest.main()
