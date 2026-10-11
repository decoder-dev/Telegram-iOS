"""Execute the production capture policy and verify both live permission gates."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift').read_text(encoding='utf-8')
policy = source[source.index('private enum ForkCameraMediaRestriction'):source.index('private func legacyCameraCapturedMediaSignals')].replace('private ', '')
camera = (root / 'submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift').read_text(encoding='utf-8')
for method, gate in [('func takePhoto()', 'capturePermission?(false)'), ('func startVideoRecording(pressing:', 'capturePermission?(true)')]:
    body = camera[camera.index(method):]
    assert gate in body[:600], 'Capture must check current permission before starting'
send_start = source.index('let send: (Bool, Int32?, Int32?)')
send = source[send_start:source.index('var items: [ActionSheetItem]', send_start)]
assert send.index('self.cameraCaptureRestriction(') < send.index('legacyCameraCapturedMediaSignals(')
assert 'ignoreDefault: bypass' in source.split('private func cameraCaptureRestriction', 1)[1].split('func openCamera', 1)[0]
fixture = '''import Foundation
''' + policy + '''
func check(_ photo: Bool, _ video: Bool, _ photoBan: Bool, _ videoBan: Bool, _ call: Bool, _ expected: ForkCameraMediaRestriction?) {
    precondition(forkCameraMediaRestriction(hasPhoto: photo, hasVideo: video, photosBanned: photoBan, videosBanned: videoBan, hasActiveCall: call) == expected)
}
check(true, false, false, false, false, nil)
check(false, true, false, false, false, nil)
check(true, true, false, false, false, nil)
check(true, false, false, false, true, nil) // photos never take over call audio
check(false, true, false, false, true, .activeCall)
check(true, false, true, false, false, .photos)
check(false, true, false, true, false, .videos)
check(false, true, true, false, false, nil)
check(true, false, false, true, true, nil)
check(true, true, true, false, false, .photos)
check(true, true, false, true, false, .videos)
check(true, true, false, false, true, .activeCall)
check(false, false, true, true, true, nil)
// Re-evaluation: permissions/call state can change between capture and Send.
check(false, true, false, false, false, nil)
check(false, true, false, true, false, .videos)
check(false, true, false, false, true, .activeCall)
check(false, true, false, false, false, nil)
print("Production camera permissions, mixed assets, capture and send gates passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
