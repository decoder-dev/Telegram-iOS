import Foundation

// UIKit presentation is simulated; the password prompt/confirmation state machine
// is extracted unchanged from ArchiveLockHelpers.swift by the runner.
final class UITextField {
    enum Option { case no, none, done }
    var text: String?
    var placeholder: String?
    var isSecureTextEntry = false
    var autocorrectionType: Option = .no
    var autocapitalizationType: Option = .none
    var returnKeyType: Option = .done
}
final class UIAlertAction {
    enum Style { case cancel, `default`, destructive }
    let handler: ((UIAlertAction) -> Void)?
    init(title: String, style: Style, handler: ((UIAlertAction) -> Void)?) { self.handler = handler }
    func invoke() { handler?(self) }
}
final class UIAlertController {
    enum Style { case alert }
    let message: String?
    var textFields: [UITextField]? = []
    var actions: [UIAlertAction] = []
    init(title: String, message: String?, preferredStyle: Style) { self.message = message }
    func addTextField(configurationHandler: (UITextField) -> Void) {
        let field = UITextField(); configurationHandler(field); textFields?.append(field)
    }
    func addAction(_ action: UIAlertAction) { actions.append(action) }
    func dismiss(animated: Bool, completion: (() -> Void)? = nil) { completion?() }
}
final class Logger {
    static let shared = Logger()
    func log(_ tag: String, _ message: String) {}
}
final class ArchiveLockSession {
    static let shared = ArchiveLockSession()
    var authorizationGeneration = 0
    func unlock() {}
    func beginSuppressBackgroundRelock() {}
    func endSuppressBackgroundRelock() {}
}
public enum ArchiveUnlockResult {
    case unlocked, cancelled, notProtected
}
struct Signal<Value, Error> {
    var value: Value? = nil
    func startStandalone(next: ((Value) -> Void)? = nil) { if let value { next?(value) } }
}
func deliverOnMainQueue<Value, Error>(_ signal: Signal<Value, Error>) -> Signal<Value, Error> { signal }
infix operator |>
func |><Value, Error, Result>(_ signal: Signal<Value, Error>, _ transform: (Signal<Value, Error>) -> Result) -> Result { transform(signal) }
enum LocalAuth {
    static var result: Bool? = true
    static var duringAuthentication: () -> Void = {}
    static func authenticateDeviceOwner(reason: String) -> Signal<Bool?, NoError> {
        duringAuthentication()
        return Signal(value: .some(result))
    }
    static func currentBiometricsDomainState() -> Data? { nil }
}
typealias NoError = Never
final class Queue {
    static var callbacks: [() -> Void] = []
    static func mainQueue() -> Queue { Queue() }
    func after(_ delay: Double, _ action: @escaping () -> Void) { Self.callbacks.append(action) }
    static func drain() {
        while !callbacks.isEmpty { callbacks.removeFirst()() }
    }
}
struct Strings {
    let Common_OK = "OK"
    let Common_Cancel = "Cancel"
    let Common_Done = "Done"
}
struct Presentation { let strings = Strings() }
struct PresentationValue {
    func with<T>(_ body: (Presentation) -> T) -> T { body(Presentation()) }
}
struct SharedContext { let currentPresentationData = PresentationValue() }
enum EnginePeer { typealias Id = Int64 }
struct Account { let peerId: EnginePeer.Id = 1 }
public typealias ViewController = Any
public final class AccountContext {
    let account = Account()
    let sharedContext = SharedContext()
    let engine = 0
}
enum ArchivePasswordKeychain {
    static var stored: String? = "password"
    static var backup: String? = "password"
    static var storeSucceeds = true
    static func store(password: String, peerId: Int64) -> Bool {
        guard storeSucceeds else { return false }
        stored = password
        return true
    }
    static func loadHash(peerId: Int64) -> String? { stored }
    static func noteBackupVerifier(_ value: String?, peerId: Int64) { backup = value }
    static var cooldown: Double = 0
    static var failures = 0
    static func remainingCooldown(peerId: Int64) -> Double { cooldown }
    static func matchesPassword(_ value: String, peerId: Int64) -> Bool { value == stored || value == backup }
    static func clearFailureState(peerId: Int64) { failures = 0 }
    static func recordFailure(peerId: Int64) { failures += 1 }
    static func failureCount(peerId: Int64) -> Int { failures }
}
enum ArchiveLockLocalizedString {
    static let setTitle = "Set"
    static let setText = "Set password"
    static let continueAction = "Continue"
    static let passwordPlaceholder = "Password"
    static let confirmTitle = "Confirm"
    static let confirmText = "Confirm password"
    static let storageError = "Storage failed"
    static let passwordsDoNotMatch = "Mismatch"
    static let lostReset = "Reset"
    static let lostReason = "Reason"
    static func tooManyAttempts(seconds: Int) -> String { "Cooldown" }
    static func incorrectPassword(attemptsLeft: Int) -> String { "Incorrect" }
}
struct ChatArchiveSettings {
    var isPasswordConfigured = true
    var passwordVerifier: String? = "password"
    var useBiometrics = false
    func clearingLegacyPasswordHash() -> Self { self }
    func withUpdatedIsPasswordConfigured(_ value: Bool) -> Self {
        var result = self; result.isPasswordConfigured = value; return result
    }
    func withUpdatedPasswordVerifier(_ value: String?) -> Self {
        var result = self; result.passwordVerifier = value; return result
    }
    func withUpdatedBiometricsDomainState(_ value: Data?) -> Self { self }
}
var archiveSettings = ChatArchiveSettings()
func updateChatArchiveSettings(engine: Int, _ update: (ChatArchiveSettings) -> ChatArchiveSettings) -> Signal<Bool, NoError> {
    archiveSettings = update(archiveSettings)
    return Signal(value: true)
}
func alignKeepArchivedUnmutedIfNeeded(context: AccountContext) {}
func clearStaleArchiveNotifications(context: AccountContext) {}
var presented: [UIAlertController] = []
// The full-screen lock (ArchiveUnlockScreen.swift) is simulated the same way: the screen only collects text and shows
// what the prompt logic tells it; every decision is in the extracted code.
final class ArchiveUnlockScreen {
    enum Subject { case archive, savedMessages, hiddenAccount }
    var submit: ((String) -> Void)?
    var cancel: (() -> Void)?
    var resetOwner: (() -> Void)?
    let subject: Subject
    let hasReset: Bool
    var messages: [String] = []
    var closed = false
    init(context: AccountContext, subject: Subject, message: String?, confirmTitle: String, resetTitle: String?) {
        self.subject = subject
        self.hasReset = resetTitle != nil
    }
    func showMessage(_ text: String, isError: Bool) { messages.append(text) }
    func close() { closed = true; presentedScreens.removeAll(where: { $0 === self }) }
    // The Close button, or anything else that dismisses the screen.
    func userClosed() { presentedScreens.removeAll(where: { $0 === self }); cancel?() }
}
var presentedScreens: [ArchiveUnlockScreen] = []
var screenHostAvailable = true
func presentArchiveUnlockScreen(context: AccountContext, screen: ArchiveUnlockScreen, onUnavailableHost: @escaping () -> Void) {
    if screenHostAvailable { presentedScreens.append(screen) } else { onUnavailableHost() }
}
func presentUIAlert(context: AccountContext, alert: UIAlertController, onUnavailableHost: @escaping () -> Void) { presented.append(alert) }

// UIKit keeps the alert alive while its action handler runs, then dismisses it.
func submit(_ text: String, cancel: Bool = false) {
    let alert = presented.removeLast()
    alert.textFields?.first?.text = text
    alert.actions[cancel ? 0 : 1].invoke()
}
