import Foundation

/// Log sink for this module.
///
/// `Logger` lives in TelegramCore and TelegramCore depends on this module, so this module cannot
/// import it back without a cycle. The sink inverts that: the handler is a plain closure the host
/// installs once at startup (`initializeAccountManagement`), and until it does — in a test binary,
/// or an extension that never sets one — logging is a nil check and nothing else.
///
/// The message is an autoclosure for the same reason `Logger.log` uses one: an unset handler must
/// not pay for building a string it will discard.
public enum WebProxyLog {
    public static var handler: ((String) -> Void)?

    public static func log(_ what: @autoclosure () -> String) {
        guard let handler = self.handler else {
            return
        }
        handler(what())
    }
}
