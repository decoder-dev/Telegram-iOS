"""Exercise production alert association/cleanup with SwiftSignalKit on macOS."""
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/ChatListUI/Sources/ArchiveLockHelpers.swift').read_text(encoding='utf-8')
start = source.index('private var archiveAlertThemeSubscriptionKey:')
end = source.index('\npublic func setArchivePassword(', start)
fixtures = r'''
import Foundation
import ObjectiveC
import SwiftSignalKit
struct Theme {
    var overallDarkAppearance = true
    var actionSheet = ActionSheet()
    var rootController = RootController()
    struct ActionSheet { var controlAccentColor = 7 }
    struct RootController { var keyboardColor = KeyboardColor() }
    struct KeyboardColor { var keyboardAppearance = 3 }
}
struct PresentationData { var theme = Theme() }
class UIViewController: NSObject {
    var presentedViewController: UIViewController?
    func present(_ alert: UIAlertController, animated: Bool) { presentedViewController = alert }
}
final class UIAlertController: UIViewController {
    enum Style { case light, dark }
    var overrideUserInterfaceStyle = Style.light
    final class View { var tintColor = 0 }
    final class Field { var keyboardAppearance = 0 }
    let view = View()
    var textFields: [Field]? = [Field()]
}
final class Window { var rootViewController: UIViewController? = UIViewController() }
final class Bindings {
    var window: Window? = Window()
    func getTopWindow() -> Window? { window }
}
final class SharedContext {
    let applicationBindings = Bindings()
    var listeners = 0
    var emit: ((PresentationData) -> Void)?
    var presentationData: Signal<PresentationData, NoError> {
        return Signal { subscriber in
            self.listeners += 1
            self.emit = { subscriber.putNext($0) }
            subscriber.putNext(PresentationData())
            return ActionDisposable {
                self.listeners -= 1
                self.emit = nil
            }
        }
    }
}
final class AccountContext { let sharedContext = SharedContext() }
'''
tests = r'''
let context = AccountContext()
for _ in 0..<100 {
    weak var releasedAlert: UIAlertController?
    autoreleasepool {
        let alert = UIAlertController()
        releasedAlert = alert
        presentUIAlert(context: context, alert: alert, onUnavailableHost: { preconditionFailure() })
        precondition(context.sharedContext.listeners == 1)
        precondition(alert.overrideUserInterfaceStyle == .dark)
        precondition(alert.view.tintColor == 7 && alert.textFields?.first?.keyboardAppearance == 3)
        var updated = PresentationData()
        updated.theme.overallDarkAppearance = false
        updated.theme.actionSheet.controlAccentColor = 9
        context.sharedContext.emit?(updated)
        precondition(alert.overrideUserInterfaceStyle == .light && alert.view.tintColor == 9)
        context.sharedContext.applicationBindings.window?.rootViewController?.presentedViewController = nil
    }
    precondition(releasedAlert == nil)
    precondition(context.sharedContext.listeners == 0, "Dismissed alert still listens without another theme event")
}
context.sharedContext.applicationBindings.window = nil
var unavailable = 0
autoreleasepool {
    presentUIAlert(context: context, alert: UIAlertController(), onUnavailableHost: { unavailable += 1 })
}
precondition(unavailable == 1 && context.sharedContext.listeners == 0)
print("Archive alert live theme, 100 release cycles and unavailable-host cleanup: passed")
'''
with tempfile.TemporaryDirectory(prefix='archive-theme-') as tmp:
    package = pathlib.Path(tmp)
    sources = package / 'Sources/Checks'
    sources.mkdir(parents=True)
    (sources / 'main.swift').write_text(fixtures + source[start:end] + tests, encoding='utf-8')
    dependency = json.dumps(str(root / 'submodules/SSignalKit'))
    (package / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ArchiveThemeChecks", platforms: [.macOS(.v10_15)],
dependencies: [.package(path: ''' + dependency + ''')],
targets: [.executableTarget(name: "Checks", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")])])
''', encoding='utf-8')
    subprocess.run(['swift', 'run', '--package-path', tmp, 'Checks'], check=True)
