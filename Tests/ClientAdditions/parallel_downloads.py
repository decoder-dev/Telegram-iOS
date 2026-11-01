"""Exercise the production admission policy with queued, active and mixed-size downloads."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
policy = (ROOT / 'submodules/FetchManagerImpl/Sources/DownloadConcurrencyPolicy.swift').read_text()
manager = (ROOT / 'submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift').read_text()
start = manager.index('    var hasActiveUserInitiatedEntries: Bool {')
active_status = manager[start:manager.index('    init(postbox:', start)]
checks = '''
final class Entry { var userInitiated = false }
final class ActiveContext { let userInitiated = false }
final class Category {
    var entries: [Int: Entry] = [:]
    var activeContexts: [Int: ActiveContext] = [:]
''' + active_status + '''
}
let category = Category()
let entry = Entry()
category.entries[1] = entry
category.activeContexts[1] = ActiveContext()
precondition(!category.hasActiveUserInitiatedEntries)
// An explicit download may reuse an already running prefetch.
entry.userInitiated = true
precondition(category.hasActiveUserInitiatedEntries)
category.entries.removeValue(forKey: 1)
precondition(!category.hasActiveUserInitiatedEntries)
category.entries[1] = entry
category.activeContexts.removeAll()
precondition(!category.hasActiveUserInitiatedEntries)
func download(_ id: Int, dc: Int = 1, size: Int64? = 1024, user: Bool = true) -> DownloadCandidate<Int> {
    DownloadCandidate(id: id, datacenterId: dc, size: size, userInitiated: user)
}
let small = (0..<10).map { download($0) }
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: small, active: []) == Array(0..<5))
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: small, active: Array(small.prefix(3))) == [3, 4])
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: small, active: Array(small.prefix(6))).isEmpty)
let large = (10..<15).map { download($0, size: 21 * 1024 * 1024) }
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: large, active: []) == [10, 11])
let unknown = (20..<25).map { download($0, size: nil) }
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: unknown, active: []) == [20, 21])
let boundary = download(30, size: 20 * 1024 * 1024)
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: [boundary], active: Array(small.prefix(5))).isEmpty)
let anotherDc = download(31, dc: 2)
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: [anotherDc], active: small) == [31])
let prefetch = (40..<45).map { download($0, user: false) }
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: prefetch, active: small + large) == [40])
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: prefetch, active: [prefetch[0]]).isEmpty)
// The occupied slots include other media categories, not just the category being scheduled.
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: [small[8]], active: Array(small.prefix(5))).isEmpty)
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: [small[8]], active: Array(small.prefix(4))) == [8])
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: [small[8], small[8]], active: []) == [8])
precondition(DownloadConcurrencyPolicy.additionalIds(candidates: [], active: small).isEmpty)
print("Parallel download admission: priority, shared budgets, sizes, DCs, prefetch and released slots passed")
'''
with tempfile.TemporaryDirectory(prefix='download-policy-') as directory:
    source = pathlib.Path(directory) / 'main.swift'
    source.write_text(policy + '\n' + checks)
    subprocess.run(['swift', str(source)], check=True, timeout=120)
