import Foundation
import UIKit
import UserNotifications
import SwiftSignalKit
import Postbox
import TelegramCore

public final class TelegramSideloadNotificationEngine {
    public static let shared = TelegramSideloadNotificationEngine()

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let queue = DispatchQueue(label: "TelegramSideloadNotificationEngine")
    private var isEnabled = true

    public init() {}

    /// Called when the application transitions to background. Extends background execution
    /// time to keep MTProto background sockets alive and process incoming messages locally.
    public func beginBackgroundKeepAlive(application: UIApplication) {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            if self.backgroundTask != .invalid {
                application.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
            self.backgroundTask = application.beginBackgroundTask(withName: "TelegramSideloadKeepAlive") { [weak self] in
                guard let self = self else { return }
                self.queue.async {
                    if self.backgroundTask != .invalid {
                        application.endBackgroundTask(self.backgroundTask)
                        self.backgroundTask = .invalid
                    }
                }
            }
        }
    }

    public func endBackgroundKeepAlive(application: UIApplication) {
        self.queue.async { [weak self] in
            guard let self = self else { return }
            if self.backgroundTask != .invalid {
                application.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }

    /// Present a local notification when an incoming message is received while APNs is unavailable or app is backgrounded.
    public func presentLocalPushNotification(title: String, body: String, messageId: MessageId, userInfo: [AnyHashable: Any] = [:]) {
        guard #available(iOS 10.0, *) else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.badge = 1
        var updatedUserInfo = userInfo
        updatedUserInfo["messageId"] = "\(messageId.namespace)_\(messageId.peerId.id)_`\(messageId.id)"
        content.userInfo = updatedUserInfo

        let request = UNNotificationRequest(
            identifier: "msg_\(messageId.peerId.id)_\(messageId.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.log("TelegramSideloadNotification", "Failed to deliver local push notification: \(error)")
            }
        }
    }
}
