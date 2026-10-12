"""Execute the production proxy probe scheduler, including replaced-profile callbacks."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'submodules/TelegramCore/Sources/Network/ProxyServersStatuses.swift').read_text(encoding='utf-8')

class ProbeQueue(unittest.TestCase):
    def test_scheduler_owns_initial_dials_and_checks_callback_generation(self):
        worker = SOURCE.split('final class ProxyServersStatusesImpl', 1)[1]
        self.assertIn('ProxyStatusProbeQueue<ProxyServerSettings>(limit: 4)', worker)
        self.assertIn('self.probes.takeNext()', worker)
        self.assertIn('self.probes.tokens[key] == token', worker)
        self.assertIn('value != .checking, self.probes.complete(key, token: token)', worker)
        self.assertIn('strongSelf.probes.update(servers)', worker)
        self.assertIn('self.contexts[key]?.value ?? .notChecked', worker)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; production scheduler executes in macOS CI')
    def test_actual_scheduler_bounds_and_event_order(self):
        scheduler = SOURCE.split('struct ProxyStatusProbeQueue<Key: Hashable>', 1)[1].split('final class ProxyServersStatusesImpl', 1)[0]
        fixture = 'import Foundation\nstruct ProxyStatusProbeQueue<Key: Hashable>' + scheduler + '''
var queue = ProxyStatusProbeQueue<Int>(limit: 4)
queue.update([0, 0] + Array(1..<40))
var batch = queue.takeNext()
precondition(batch.map { $0.0 } == [0, 1, 2, 3])
precondition(queue.tokens.count == 40 && queue.running.count == 4)
precondition(queue.takeNext().isEmpty)
var completed = Set<Int>()
while !batch.isEmpty {
    for (key, token) in batch {
        precondition(queue.complete(key, token: token))
        precondition(!queue.complete(key, token: token))
        precondition(completed.insert(key).inserted)
    }
    batch = queue.takeNext()
    precondition(batch.count <= 4 && queue.running.count <= 4)
}
precondition(completed.count == 40)
// Repeating a list must not redial already checked profiles.
queue.update(Array(0..<40))
precondition(queue.takeNext().isEmpty)
queue.update([])
precondition(queue.tokens.isEmpty && queue.running.isEmpty)
queue.update([0, 1, 2, 3, 4])
let old = queue.takeNext()
queue.update([0, 2, 3, 4]) // cancel 1, free its slot
precondition(queue.takeNext().map { $0.0 } == [4])
queue.update([0, 1, 2, 3, 4]) // same key, new generation
let stale = old.first { $0.0 == 1 }!
precondition(!queue.complete(1, token: stale.1))
precondition(queue.running.count == 4)
precondition(queue.complete(0, token: old[0].1))
let fresh = queue.takeNext()
precondition(fresh.count == 1 && fresh[0].0 == 1 && fresh[0].1 != stale.1)
precondition(!queue.complete(1, token: stale.1))
precondition(queue.complete(1, token: fresh[0].1))
queue.update([])
precondition(queue.running.isEmpty && queue.takeNext().isEmpty)
print("Production probe queue: concurrency, priority, deduplication, cancellation and stale completions passed")
'''
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / 'main.swift'
            executable = pathlib.Path(directory) / 'fixture'
            source.write_text(fixture, encoding='utf-8')
            subprocess.run(['swiftc', str(source), '-o', str(executable)], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=30)

if __name__ == '__main__':
    unittest.main()
