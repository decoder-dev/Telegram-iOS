import UIKit

/// Scene entry point. The app builds its window itself, in `AppDelegate`, so this does nothing but hand the connected
/// scene (and what it was opened with) to the app delegate. It is only registered in an `Info.plist` scene manifest by the
/// iOS 27 SDK build, which refuses to launch an app without one; other builds never instantiate it.
@objc(TelegramSceneDelegate) final class TelegramSceneDelegate: UIResponder, UIWindowSceneDelegate {
    private var appDelegate: AppDelegate? {
        return UIApplication.shared.delegate as? AppDelegate
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        self.appDelegate?.attach(toScene: windowScene, connectionOptions: connectionOptions)
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let appDelegate = self.appDelegate else {
            return
        }
        for context in URLContexts {
            let _ = appDelegate.application(UIApplication.shared, open: context.url, options: [:])
        }
    }
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        let _ = self.appDelegate?.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
    }
    
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let appDelegate = self.appDelegate else {
            completionHandler(false)
            return
        }
        appDelegate.application(UIApplication.shared, performActionFor: shortcutItem, completionHandler: completionHandler)
    }
}
