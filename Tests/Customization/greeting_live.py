"""Live greeting layout replay: production method with retained-layout/weak-node fixtures."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_PATH = ROOT / "submodules/TelegramUI/Components/Chat/ChatEmptyNode/Sources/ChatEmptyNode.swift"
SOURCE = SOURCE_PATH.read_text(encoding="utf-8")
OUTER = SOURCE[SOURCE.index("public final class ChatEmptyNode: ASDisplayNode") :]


class GreetingLiveTests(unittest.TestCase):
    def test_subscription_lifetime_and_layout_wiring(self):
        subscription = OUTER[OUTER.index("self.greetingSettingsDisposable.set(") : OUTER.index("    deinit {")]
        for expected in ("forkExtrasSettings(accountManager:", "map { $0.hideGreetingSticker }", "distinctUntilChanged", "deliverOnMainQueue", "[weak self]", "updateGreetingStickerVisibility"):
            self.assertIn(expected, subscription)
        self.assertIn("self.greetingSettingsDisposable.dispose()", OUTER)
        self.assertIn("greetingNode.hideGreetingSticker = self.hideGreetingSticker", OUTER)
        self.assertIn("if updateGreetingSticker && !self.hideGreetingSticker", OUTER)
        self.assertIn('"//submodules/TelegramUIPreferences"', (SOURCE_PATH.parents[1] / "BUILD").read_text(encoding="utf-8"))

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable locally; fixture must execute in macOS CI")
    def test_actual_layout_replay_and_weak_references(self):
        parameters = OUTER[OUTER.index("    private final class LayoutParameters {") : OUTER.index("    private let greetingSettingsDisposable")]
        method = OUTER[OUTER.index("    private func updateGreetingStickerVisibility(") : OUTER.index("    override public func hitTest(")]
        fixture = r'''
import Foundation
struct ChatPresentationInterfaceState: Equatable { let id: Int }
struct CGSize: Equatable { let width: Double; let height: Double }
struct UIEdgeInsets: Equatable { let top: Double; let left: Double; let bottom: Double; let right: Double }
typealias CGFloat = Double
class ChatLoadingNode {}
class WallpaperBackgroundNode {}
enum ContainedViewLayoutTransition { case immediate; case animated }
final class Fixture {
    enum Subject: Equatable { case generic; case customGreeting }
''' + parameters + r'''
    var replays = 0
    var lastState: ChatPresentationInterfaceState?
    var lastSubject: Subject?
    var lastSize: CGSize?
    var lastInsets: UIEdgeInsets?
    var lastLeft: CGFloat?
    var lastRight: CGFloat?
    var receivedLoading = false
    var receivedWallpaper = false
    init() { self.hideGreetingSticker = false }
''' + method + r'''
    func updateLayout(interfaceState: ChatPresentationInterfaceState, subject: Subject, loadingNode: ChatLoadingNode?, backgroundNode: WallpaperBackgroundNode?, size: CGSize, insets: UIEdgeInsets, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) {
        precondition(transition == .immediate)
        replays += 1
        lastState = interfaceState; lastSubject = subject; lastSize = size; lastInsets = insets
        lastLeft = leftInset; lastRight = rightInset
        receivedLoading = loadingNode != nil; receivedWallpaper = backgroundNode != nil
    }
    func verify() {
        updateGreetingStickerVisibility(true)
        precondition(replays == 0 && hideGreetingSticker)
        let state = ChatPresentationInterfaceState(id: 42)
        let size = CGSize(width: 390, height: 844)
        let insets = UIEdgeInsets(top: 59, left: 7, bottom: 34, right: 11)
        var loading: ChatLoadingNode? = ChatLoadingNode()
        var wallpaper: WallpaperBackgroundNode? = WallpaperBackgroundNode()
        weak var weakLoading = loading
        weak var weakWallpaper = wallpaper
        layoutParameters = LayoutParameters(interfaceState: state, subject: .customGreeting, loadingNode: loading, backgroundNode: wallpaper, size: size, insets: insets, leftInset: 17, rightInset: 23)
        updateGreetingStickerVisibility(true)
        precondition(replays == 0)
        updateGreetingStickerVisibility(false)
        precondition(replays == 1 && lastState == state && lastSubject == .customGreeting)
        precondition(lastSize == size && lastInsets == insets && lastLeft == 17 && lastRight == 23)
        precondition(receivedLoading && receivedWallpaper)
        loading = nil; wallpaper = nil
        precondition(weakLoading == nil && weakWallpaper == nil)
        updateGreetingStickerVisibility(true)
        precondition(replays == 2 && !receivedLoading && !receivedWallpaper)
    }
}
Fixture().verify()
print("Production greeting live replay: toggle, duplicate, custom subject, safe area, weak nodes passed")
'''
        with tempfile.TemporaryDirectory() as directory:
            source_path = pathlib.Path(directory) / "main.swift"
            executable = pathlib.Path(directory) / "fixture"
            source_path.write_text(fixture, encoding="utf-8")
            subprocess.run(["swiftc", str(source_path), "-o", str(executable)], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
