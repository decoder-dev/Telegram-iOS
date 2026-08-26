import Foundation

/// Log sink for this module. Same inversion as `WebProxyLog`: `Logger` is in TelegramCore, which
/// depends on this module, so the host installs a closure once at startup and an unset handler
/// costs a nil check. See `initializeAccountManagement`.
public enum WebSocketTransportLog {
    public static var handler: ((String) -> Void)?

    public static func log(_ what: @autoclosure () -> String) {
        guard let handler = self.handler else {
            return
        }
        handler(what())
    }
}
