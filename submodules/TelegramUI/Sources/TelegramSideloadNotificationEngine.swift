import Foundation
import UIKit

public final class TelegramSideloadNotificationEngine {
    public static let shared = TelegramSideloadNotificationEngine()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskGeneration: UInt64 = 0

    public init() {}

    /// Requests the short grace period iOS grants after entering the background.
    /// This only lets already-started work finish; APNs remains responsible for later messages.
    public func beginBackgroundKeepAlive(application: UIApplication) {
        self.performOnMainThread { [weak self, weak application] in
            guard let self, let application else { return }
            self.backgroundTaskGeneration &+= 1
            let generation = self.backgroundTaskGeneration
            if self.backgroundTask != .invalid {
                application.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
            self.backgroundTask = application.beginBackgroundTask(withName: "TelegramSideloadKeepAlive") { [weak self] in
                self?.performOnMainThread { [weak self, weak application] in
                    guard let self, let application, self.backgroundTaskGeneration == generation else { return }
                    if self.backgroundTask != .invalid {
                        application.endBackgroundTask(self.backgroundTask)
                        self.backgroundTask = .invalid
                    }
                }
            }
        }
    }

    public func endBackgroundKeepAlive(application: UIApplication) {
        self.performOnMainThread { [weak self, weak application] in
            guard let self, let application else { return }
            self.backgroundTaskGeneration &+= 1
            if self.backgroundTask != .invalid {
                application.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }

    private func performOnMainThread(_ f: @escaping () -> Void) {
        if Thread.isMainThread {
            f()
        } else {
            DispatchQueue.main.async(execute: f)
        }
    }
}
