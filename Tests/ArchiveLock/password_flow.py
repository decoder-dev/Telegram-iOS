import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/ChatListUI/Sources/ArchiveLockHelpers.swift').read_text(encoding='utf-8')
start = source.index('private var activePasswordPrompts:')
end = source.index('\nprivate var archiveAlertThemeSubscriptionKey:', start)
fixtures = (root / 'Tests/ArchiveLock/PasswordFlowFixtures.swift').read_text(encoding='utf-8')
tests = '''
let context = AccountContext()
var successes = 0
var cancelled = 0
var writes = 0
var storeSucceeds = false
presentArchivePasswordAlert(context: context, title: "Set", message: nil, confirmTitle: "Next", verifyPassword: false, onSuccess: { successes += 1 }, onCancel: { cancelled += 1 }, capturePassword: { _ in
    writes += 1
    return storeSucceeds
})
var duplicateCancelled = 0
presentArchivePasswordAlert(context: context, title: "Duplicate", message: nil, confirmTitle: "Next", verifyPassword: false, onSuccess: { preconditionFailure("Duplicate prompt unexpectedly succeeded") }, onCancel: { duplicateCancelled += 1 })
precondition(duplicateCancelled == 1 && presented.count == 1)
weak var firstPrompt = presented.last
submit("password")
precondition(firstPrompt == nil, "Password prompt retained by its action")
Queue.drain()
weak var firstConfirmation = presented.last
submit("password")
precondition(firstConfirmation == nil, "Confirmation retained by its action")
Queue.drain()
precondition(writes == 1 && successes == 0 && cancelled == 0)
precondition(presented.last?.message == ArchiveLockLocalizedString.storageError)
storeSucceeds = true
submit("password"); Queue.drain(); submit("password"); Queue.drain()
precondition(writes == 2 && successes == 1 && cancelled == 0 && presented.isEmpty)

for _ in 0..<20 {
    presentArchivePasswordAlert(context: context, title: "Set", message: nil, confirmTitle: "Next", verifyPassword: false, onSuccess: { successes += 1 }, onCancel: { cancelled += 1 }, capturePassword: { _ in writes += 1; return true })
    submit("password"); Queue.drain()
    weak var confirmation = presented.last
    submit("different"); Queue.drain()
    precondition(confirmation == nil)
    precondition(presented.last?.message == ArchiveLockLocalizedString.passwordsDoNotMatch)
    submit("", cancel: true); Queue.drain()
}
precondition(writes == 2 && successes == 1 && cancelled == 20)
precondition(presented.isEmpty && Queue.callbacks.isEmpty)
print("Archive password persistence failure/retry, mismatches and 20 prompt release cycles: passed")
'''
with tempfile.TemporaryDirectory(prefix='archive-password-flow-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixtures + '\n' + source[start:end] + '\n' + tests, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
