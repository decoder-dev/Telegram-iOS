import Foundation

/// TelegramCore installs the sink; this lower-level module cannot import its Logger.
public enum VlessLog {
    private static let lock = NSLock()
    private static var handlerValue: ((String) -> Void)?

    public static var handler: ((String) -> Void)? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.handlerValue
        }
        set {
            self.lock.lock()
            self.handlerValue = newValue
            self.lock.unlock()
        }
    }

    public static func log(_ message: @autoclosure () -> String) {
        // Invoke outside the lock: the host may change the sink from its callback.
        guard let handler = self.handler else { return }
        handler(message())
    }
}
