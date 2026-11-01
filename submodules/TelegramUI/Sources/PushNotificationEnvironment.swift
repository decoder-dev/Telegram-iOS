import Foundation

enum PushNotificationEnvironment {
    private static let infoPlistKey = "TelegramAPNSEnvironment"

    static var isSandbox: Bool {
        let environment = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        #if DEBUG
        let debugFallback = true
        #else
        let debugFallback = false
        #endif
        return isSandbox(environment: environment, debugFallback: debugFallback)
    }

    static var tokenEnvironment: String {
        return isSandbox ? "sandbox" : "production"
    }

    static func isSandbox(environment: String?, debugFallback: Bool) -> Bool {
        switch environment {
        case "development":
            return true
        case "production":
            return false
        default:
            return debugFallback
        }
    }
}
