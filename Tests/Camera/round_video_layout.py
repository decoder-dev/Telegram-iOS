"""Run the production camera geometry against compact and keyboard-transition layouts."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraLayout.swift').read_text()
fixture = source + r'''
var cases = 0
for width: CGFloat in [320, 375, 393, 402, 430, 768, 1024] {
    for height: CGFloat in [568, 667, 852, 874, 932, 1366] {
        for keyboard: CGFloat in [0, 216, 336, 380] {
            let contentHeight = height - max(34, keyboard) - 48 - 8
            let topInset: CGFloat = 79
            // Below this size even a 1 pt preview cannot fit; these are not supported
            // portrait recording layouts. All screenshot and compact phone sizes fit.
            if contentHeight < topInset + 123 { continue }
            let side = min(369, width - 24)
            let preferred = CGRect(x: (width - side) / 2, y: max(55, (height - keyboard) * 0.4 - side / 2), width: side, height: side)
            let layout = VideoMessageCameraLayout(preferredPreviewFrame: preferred, containerSize: CGSize(width: width, height: contentHeight), topInset: topInset)
            let cameraButtons = CGRect(x: 8, y: contentHeight - 48, width: 91, height: 40)
            precondition(layout.previewFrame.minY >= topInset)
            precondition(layout.previewFrame.width > 0 && layout.previewFrame.width == layout.previewFrame.height)
            precondition(layout.previewFrame.minX >= 0 && layout.previewFrame.maxX <= width)
            precondition(layout.zoomFrame.minY >= layout.previewFrame.maxY + 10 - 0.001)
            precondition(layout.zoomFrame.maxY <= cameraButtons.minY - 8 + 0.001)
            precondition(!layout.zoomFrame.intersects(cameraButtons))
            precondition(abs(layout.zoomFrame.midX - width / 2) < 0.001)
            cases += 1
        }
    }
}
// A tall screen retains its full-size circle and its preferred placement.
let preferred = CGRect(x: 16.5, y: 155.5, width: 369, height: 369)
let tall = VideoMessageCameraLayout(preferredPreviewFrame: preferred, containerSize: CGSize(width: 402, height: 784), topInset: 79)
precondition(tall.previewFrame == preferred)
// Asymmetric safe-area placement must keep the circle on its original axis.
let asymmetric = CGRect(x: 12, y: 79, width: 300, height: 300)
let compact = VideoMessageCameraLayout(preferredPreviewFrame: asymmetric, containerSize: CGSize(width: 402, height: 420), topInset: 79)
precondition(compact.previewFrame.midX == asymmetric.midX)
print("Round-video geometry passed: \(cases) layouts, keyboard transitions, compact and asymmetric screens")
'''

with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, timeout=120)

controller = (root / 'submodules/TelegramUI/Sources/ChatController.swift').read_text()
recording = controller[controller.index('self.videoRecorderDisposable = (self.videoRecorder.get()'):]
assert recording.index('strongSelf.chatDisplayNode.dismissInput()') < recording.index('strongSelf.updateChatPresentationInterfaceState(')

screen = (root / 'submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift').read_text()
hit_test = screen[screen.index('override func hitTest('):screen.index('fileprivate func maybePresentTooltips()')]
assert hit_test.index('self.zoomControlsView.hitTest(') < hit_test.index('resultPreviewView.bounds.contains(')
assert 'result === componentView' not in hit_test
assert 'controller.inputPanelFrame' not in screen
print('Keyboard dismissal ordering and zoom touch routing passed')
