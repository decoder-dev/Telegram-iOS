"""Exercise the production zoom preset calculation against camera capabilities."""
import pathlib
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "submodules/Camera/Sources/CameraDevice.swift").read_text(encoding="utf-8")
start = source.index("    var zoomFactorRange:")
end = source.index("    func setZoomFactor(", start)
fixture = """
import Foundation
struct Device {
    let neutralZoomFactor: CGFloat
    let minAvailableVideoZoomFactor: CGFloat
    let maxAvailableVideoZoomFactor: CGFloat
    let virtualDeviceSwitchOverVideoZoomFactors: [NSNumber]
}
class Camera {
    var videoDevice: Device?
""" + source[start:end] + """
}
let camera = Camera()
precondition(camera.nativeZoomFactors == [1])
camera.videoDevice = Device(neutralZoomFactor: 1, minAvailableVideoZoomFactor: 1, maxAvailableVideoZoomFactor: 8, virtualDeviceSwitchOverVideoZoomFactors: [])
precondition(camera.nativeZoomFactors == [1])
camera.videoDevice = Device(neutralZoomFactor: 2, minAvailableVideoZoomFactor: 1, maxAvailableVideoZoomFactor: 20, virtualDeviceSwitchOverVideoZoomFactors: [2, 6])
precondition(camera.nativeZoomFactors == [0.5, 1, 3])
camera.videoDevice = Device(neutralZoomFactor: 2, minAvailableVideoZoomFactor: 1, maxAvailableVideoZoomFactor: 20, virtualDeviceSwitchOverVideoZoomFactors: [2, 10])
precondition(camera.nativeZoomFactors == [0.5, 1, 5])
print("Single, ultrawide, 3x and 5x camera presets passed")
"""
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "main.swift"
    path.write_text(fixture, encoding="utf-8")
    subprocess.run(["swift", str(path)], check=True, timeout=120)
