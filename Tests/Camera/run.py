"""Run production picker completion/cancellation gates without UIKit."""
import pathlib
import subprocess
import tempfile
import sys

root = pathlib.Path(__file__).resolve().parents[2]
for component, value_type in [('ChatScheduleTimeController', 'Result'), ('ChatTimerScreen', 'Int32?')]:
    filename = 'ChatScheduleTimeScreen.swift' if component == 'ChatScheduleTimeController' else 'ChatTimerScreen.swift'
    source = (root / 'submodules/TelegramUI/Components' / component / 'Sources' / filename).read_text(encoding='utf-8')
    start = source.index('    fileprivate let completion:')
    end = source.index('        super.dismiss(completion: completion)', start)
    end = source.index('    }', end) + 5
    gate = source[start:end]
    assert 'controller.completion(' not in source, 'All picker selections must use the once-only gate'
    fixture = """
import Foundation
class Base {
    var dismissals = 0
    func dismiss(completion: (() -> Void)? = nil) { dismissals += 1; completion?() }
}
final class Picker: Base {
    typealias Result = Int32
""" + gate + """
    init(_ completion: @escaping (""" + value_type + """) -> Void) { self.completion = completion }
}
var sent = 0
var cancelled = 0
let confirmed = Picker { _ in sent += 1 }
confirmed.cancelled = { cancelled += 1 }
confirmed.complete(10)
confirmed.complete(20)
confirmed.dismiss()
precondition(sent == 1 && cancelled == 0)
let abandoned = Picker { _ in sent += 1 }
abandoned.cancelled = { cancelled += 1 }
abandoned.dismiss()
abandoned.dismiss()
abandoned.complete(30)
precondition(sent == 1 && cancelled == 1)
print("Picker confirmation/cancellation gates passed")
"""
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / 'main.swift'
        path.write_text(fixture, encoding='utf-8')
        subprocess.run(['swift', str(path)], check=True)

picker = (root / 'submodules/MediaPickerUI/Sources/MediaPickerScreen.swift').read_text()
dismissal = picker[picker.index('    public override func dismiss(completion:'):]
dismissal = dismissal[:dismissal.index('        super.dismiss(completion: completion)')]
camera_start = dismissal.index('        if let camera')
camera_teardown = dismissal[camera_start:]
fixture = '''
final class Camera {
    var invalidations = 0
    func stopCapture(invalidate: Bool) { precondition(invalidate); invalidations += 1 }
}
final class Preview { var isEnabled = true }
final class Node {
    var modernCamera: Camera?
    var modernCameraView: Preview?
}
final class Picker {
    let controllerNode = Node()
    func dismissCamera() {
''' + camera_teardown + '''
    }
}
for hasCamera in [false, true] {
    for hasPreview in [false, true] {
        let picker = Picker()
        let camera = Camera(), preview = Preview()
        picker.controllerNode.modernCamera = hasCamera ? camera : nil
        picker.controllerNode.modernCameraView = hasPreview ? preview : nil
        picker.dismissCamera()
        precondition(camera.invalidations == (hasCamera ? 1 : 0))
        precondition(preview.isEnabled == !(hasCamera && hasPreview))
    }
}
print("Media picker dismissal: camera invalidation, disabled preview and missing-camera cases passed")
'''
with tempfile.TemporaryDirectory(prefix='picker-dismissal-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, timeout=120)

subprocess.run([sys.executable, str(root / 'Tests/Camera/permissions.py')], check=True)
if sys.platform == 'darwin':
    subprocess.run([sys.executable, str(root / 'Tests/Camera/round_video_voice.py')], check=True)

legacy = (root / 'submodules/Camera/CameraLegacy/Sources/LegacyCamera.swift').read_text(encoding='utf-8')
start_stop = legacy[legacy.index('    private var wantsCapture ='):legacy.index('    func focus(at point:')]
recovery = legacy[legacy.index('    @objc private func sessionRuntimeError('):legacy.index('    private static func describe(')]
fixture = '''
import Foundation

struct AVError { init(_nsError: NSError) {} }
let AVCaptureSessionErrorKey = "error"
enum Authorization { case authorized, denied }
struct AVCaptureDevice {
    enum MediaType { case video }
    static var authorization = Authorization.authorized
    static func authorizationStatus(for: MediaType) -> Authorization { authorization }
}
struct Logger {
    static let shared = Logger()
    func log(_ tag: String, _ message: String) {}
}
final class Queue {
    var delayed: [() -> Void] = []
    func async(_ f: () -> Void) { f() }
    func after(_ delay: Double, _ f: @escaping () -> Void) { delayed.append(f) }
    func flush() { while !delayed.isEmpty { delayed.removeFirst()() } }
}
final class Session {
    var isRunning = false
    var isInterrupted = false
    var startAttempts = 0
    var errorsRemaining = 0
    var onError: (() -> Void)?
    func startRunning() {
        startAttempts += 1
        if errorsRemaining > 0 {
            errorsRemaining -= 1
            onError?()
        } else {
            isRunning = true
        }
    }
    func stopRunning() { isRunning = false }
}
final class Device {
    var device: Device { self }
    func resetZoom() {}
    func invalidate() {}
}
final class Camera {
    let queue = Queue()
    let session = (session: Session(), unused: false)
    let mainDeviceContext: Device? = nil
    var invalidated = false
    func configure(_ f: () -> Void) { f() }
    init() {
        self.session.session.onError = { [weak self] in
            self?.sessionRuntimeError(notification: NSNotification(name: Notification.Name("error"), object: nil,
                userInfo: [AVCaptureSessionErrorKey: NSError(domain: "capture", code: -11819)]))
        }
    }
''' + start_stop + recovery.replace('@objc ', '') + '''
}

let initialFailure = Camera()
initialFailure.session.session.errorsRemaining = 1
initialFailure.startCapture()
precondition(initialFailure.session.session.startAttempts == 1)
initialFailure.queue.flush()
precondition(initialFailure.session.session.startAttempts == 2 && initialFailure.session.session.isRunning)

let persistentFailure = Camera()
persistentFailure.session.session.errorsRemaining = 10
persistentFailure.startCapture()
persistentFailure.queue.flush()
precondition(persistentFailure.session.session.startAttempts == 2 && !persistentFailure.session.session.isRunning)

let stopped = Camera()
stopped.session.session.errorsRemaining = 1
stopped.startCapture()
stopped.stopCapture()
stopped.queue.flush()
precondition(stopped.session.session.startAttempts == 1)

let reopened = Camera()
reopened.session.session.errorsRemaining = 2
reopened.startCapture()
let oldRecovery = reopened.queue.delayed.removeFirst()
reopened.stopCapture()
reopened.startCapture()
oldRecovery()
precondition(reopened.session.session.startAttempts == 2)
reopened.queue.flush()
precondition(reopened.session.session.startAttempts == 3 && reopened.session.session.isRunning)

let dismissed = Camera()
dismissed.session.session.errorsRemaining = 1
dismissed.startCapture()
dismissed.stopCapture(invalidate: true)
dismissed.queue.flush()
dismissed.startCapture()
precondition(dismissed.session.session.startAttempts == 1)

let interrupted = Camera()
interrupted.session.session.errorsRemaining = 1
interrupted.startCapture()
interrupted.session.session.isInterrupted = true
interrupted.queue.flush()
precondition(interrupted.session.session.startAttempts == 1)

let denied = Camera()
denied.session.session.errorsRemaining = 1
denied.startCapture()
AVCaptureDevice.authorization = .denied
denied.queue.flush()
precondition(denied.session.session.startAttempts == 1)
print("Legacy camera: initial failure recovers once and stopped, interrupted or unauthorized capture stays stopped")
'''
with tempfile.TemporaryDirectory(prefix='legacy-camera-recovery-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True, timeout=120)
