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
    enum Style { case cancel, `default` }
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
}
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
final class AccountContext {
    let account = Account()
    let sharedContext = SharedContext()
}
enum ArchivePasswordKeychain {
    static func remainingCooldown(peerId: Int64) -> Double { 0 }
    static func matchesPassword(_ value: String, peerId: Int64) -> Bool { value == "password" }
    static func clearFailureState(peerId: Int64) {}
    static func recordFailure(peerId: Int64) {}
    static func failureCount(peerId: Int64) -> Int { 1 }
}
enum ArchiveLockLocalizedString {
    static let passwordPlaceholder = "Password"
    static let confirmTitle = "Confirm"
    static let confirmText = "Confirm password"
    static let storageError = "Storage failed"
    static let passwordsDoNotMatch = "Mismatch"
    static func tooManyAttempts(seconds: Int) -> String { "Cooldown" }
    static func incorrectPassword(attemptsLeft: Int) -> String { "Incorrect" }
}
var presented: [UIAlertController] = []
func presentUIAlert(context: AccountContext, alert: UIAlertController, onUnavailableHost: @escaping () -> Void) { presented.append(alert) }

// UIKit keeps the alert alive while its action handler runs, then dismisses it.
func submit(_ text: String, cancel: Bool = false) {
    let alert = presented.removeLast()
    alert.textFields?.first?.text = text
    alert.actions[cancel ? 0 : 1].invoke()
}
