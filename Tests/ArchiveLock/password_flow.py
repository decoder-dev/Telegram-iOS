import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/ChatListUI/Sources/ArchiveLockHelpers.swift').read_text(encoding='utf-8')
start = source.index('private var activePasswordPrompts:')
end = source.index('\nprivate var archiveAlertThemeSubscriptionKey:', start)
fixtures = (root / 'Tests/ArchiveLock/PasswordFlowFixtures.swift').read_text(encoding='utf-8')
# Compile the real replacement and persistence code rather than an always-successful stub.
replacement_start = source.index('public func setArchivePassword(')
replacement_end = source.index('/// Recovery for a password', replacement_start)
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
func beginOwnerReset() {
    presentArchivePasswordAlert(context: context, title: "Unlock", message: nil, confirmTitle: "Unlock", verifyPassword: true, onSuccess: { successes += 1 }, onCancel: { cancelled += 1 }, allowOwnerReset: true)
    let alert = presented.removeLast()
    precondition(alert.actions.count == 3)
    alert.actions[2].invoke()
}
func expectOldProtection() {
    precondition(ArchivePasswordKeychain.stored == "password")
    precondition(ArchivePasswordKeychain.backup == "password")
    precondition(archiveSettings.isPasswordConfigured && archiveSettings.passwordVerifier == "password")
}
let successesBeforeReset = successes
var expectedCancellations = cancelled
for authResult in [false, nil] as [Bool?] {
    LocalAuth.result = authResult
    beginOwnerReset()
    expectedCancellations += 1
    precondition(cancelled == expectedCancellations && successes == successesBeforeReset)
    precondition(presented.isEmpty && activePasswordPrompts.isEmpty)
    expectOldProtection()
}
LocalAuth.result = true
LocalAuth.duringAuthentication = { ArchiveLockSession.shared.authorizationGeneration += 1 }
beginOwnerReset()
expectedCancellations += 1
precondition(cancelled == expectedCancellations && presented.isEmpty)
expectOldProtection()
LocalAuth.duringAuthentication = {}

beginOwnerReset()
precondition(presented.count == 1, "Owner reset must actually present the new-password prompt")
expectOldProtection()
submit("", cancel: true)
expectedCancellations += 1
precondition(cancelled == expectedCancellations && activePasswordPrompts.isEmpty)
expectOldProtection()

beginOwnerReset()
submit("new-password"); Queue.drain()
submit("", cancel: true)
expectedCancellations += 1
precondition(cancelled == expectedCancellations && activePasswordPrompts.isEmpty)
expectOldProtection()

ArchivePasswordKeychain.storeSucceeds = false
beginOwnerReset()
submit("new-password"); Queue.drain(); submit("new-password"); Queue.drain()
precondition(presented.last?.message == ArchiveLockLocalizedString.storageError)
expectOldProtection()
precondition(successes == successesBeforeReset && cancelled == expectedCancellations)
ArchivePasswordKeychain.storeSucceeds = true
submit("new-password"); Queue.drain(); submit("new-password"); Queue.drain()
precondition(successes == successesBeforeReset + 1 && cancelled == expectedCancellations)
precondition(ArchivePasswordKeychain.stored == "new-password")
precondition(ArchivePasswordKeychain.backup == "new-password")
precondition(archiveSettings.isPasswordConfigured && archiveSettings.passwordVerifier == "new-password")
precondition(!ArchivePasswordKeychain.matchesPassword("password", peerId: 1))
precondition(presented.isEmpty && activePasswordPrompts.isEmpty)
print("Owner reset: rejected/stale authentication, cancellation, persistence failure/retry and replacement: passed")

// Full-screen unlock (scenes 27, 53): one screen across wrong attempts, the Keychain limit before every attempt,
// exactly one terminal result, and the single-flight entry released on every way out.
ArchivePasswordKeychain.failures = 0
var screenSuccesses = 0
var screenCancels = 0
func openScreen(_ subject: ArchiveUnlockScreen.Subject = .archive, reset: Bool = true) -> ArchiveUnlockScreen {
    presentArchivePasswordAlert(context: context, title: "Unlock", message: nil, confirmTitle: "Unlock", verifyPassword: true, onSuccess: { screenSuccesses += 1 }, onCancel: { screenCancels += 1 }, allowOwnerReset: reset, fullScreenSubject: subject)
    precondition(presented.isEmpty, "The unlock must not fall back to an alert")
    return presentedScreens.last!
}
var screen = openScreen()
precondition(screen.subject == .archive && screen.hasReset && presentedScreens.count == 1)
var duplicate = 0
presentArchivePasswordAlert(context: context, title: "Unlock", message: nil, confirmTitle: "Unlock", verifyPassword: true, onSuccess: { preconditionFailure() }, onCancel: { duplicate += 1 }, fullScreenSubject: .archive)
precondition(duplicate == 1 && presentedScreens.count == 1, "A second unlock while the screen is up is cancelled at once")
screen.submit?("wrong")
precondition(ArchivePasswordKeychain.failures == 1 && screen.messages.last == "Incorrect" && !screen.closed && presentedScreens.count == 1)
ArchivePasswordKeychain.cooldown = 30
screen.submit?("new-password")
precondition(screen.messages.last == "Cooldown" && screenSuccesses == 0, "No password is checked during the cooldown")
precondition(ArchivePasswordKeychain.failures == 1)
ArchivePasswordKeychain.cooldown = 0
screen.submit?("  new-password ")
precondition(screen.closed && screenSuccesses == 1 && screenCancels == 0 && ArchivePasswordKeychain.failures == 0)
precondition(activePasswordPrompts.isEmpty && presentedScreens.isEmpty)
screen.submit?("new-password"); screen.cancel?()
precondition(screenSuccesses == 1 && screenCancels == 0, "A finished screen reports nothing more")

for _ in 0..<20 {
    let s = openScreen(.savedMessages, reset: false)
    precondition(s.subject == .savedMessages && !s.hasReset)
    s.submit?("wrong")
    s.userClosed()
    s.cancel?()
    precondition(activePasswordPrompts.isEmpty && presentedScreens.isEmpty)
}
precondition(screenCancels == 20 && screenSuccesses == 1)
ArchivePasswordKeychain.failures = 0

ArchivePasswordKeychain.cooldown = 10
screen = openScreen(.hiddenAccount)
precondition(screen.messages == ["Cooldown"], "A standing cooldown is shown as soon as the screen opens")
screen.userClosed()
ArchivePasswordKeychain.cooldown = 0
precondition(screenCancels == 21 && activePasswordPrompts.isEmpty)

screenHostAvailable = false
presentArchivePasswordAlert(context: context, title: "Unlock", message: nil, confirmTitle: "Unlock", verifyPassword: true, onSuccess: { preconditionFailure() }, onCancel: { screenCancels += 1 }, fullScreenSubject: .archive)
precondition(screenCancels == 22 && activePasswordPrompts.isEmpty, "No host to present on is a cancellation")
screenHostAvailable = true

LocalAuth.result = false
screen = openScreen()
screen.resetOwner?()
precondition(screen.closed && screenCancels == 23 && activePasswordPrompts.isEmpty && presentedScreens.isEmpty, "A refused owner reset cancels")
LocalAuth.result = true
screen = openScreen()
screen.resetOwner?()
precondition(screen.closed && presented.count == 1, "An accepted owner reset continues with the new-password prompt")
submit("reset-password"); Queue.drain(); submit("reset-password"); Queue.drain()
precondition(screenSuccesses == 2 && screenCancels == 23 && activePasswordPrompts.isEmpty && presented.isEmpty)
precondition(ArchivePasswordKeychain.stored == "reset-password")
print("Full-screen unlock: wrong password, cooldown, success, close, 20 release cycles, no host and owner reset: passed")
print("Archive password persistence failure/retry, mismatches and 20 prompt release cycles: passed")
'''
with tempfile.TemporaryDirectory(prefix='archive-password-flow-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixtures + '\n' + source[start:end] + '\n' + source[replacement_start:replacement_end] + '\n' + tests, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
