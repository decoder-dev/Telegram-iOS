"""Execute production policies for donor features without a camera or UIKit."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text()


def declaration(source, marker):
    start = source.index(marker)
    return source[start:source.index('\n}', start) + 2]


camera = 'submodules/Camera/'
editor = 'submodules/TelegramUI/Components/MediaEditor/Sources/'
screen = 'submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/'
capture = read(camera + 'CameraNeo/Sources/NeoCameraImpl.swift')
screen_source = read(screen + 'VideoMessageCameraScreen.swift')
mode_selection = screen_source[screen_source.index('            let useModernVideoMessagePipeline ='):screen_source.index('            self.recordingProfile =')]
audio = read(camera + 'CameraNeo/Sources/RoundVideoAudioSettings.swift')
settings = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
settings = settings[:settings.index('/// Last opened chat-list folder.')]
for module in ['TelegramCore', 'SwiftSignalKit', 'Postbox']:
    settings = settings.replace('import ' + module + '\n', '')
fixture = '''
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
enum AVCaptureDevice { enum Position { case front, back } }
enum ForkPresentationLanguage { static let prefersRussianStrings = false }
enum NeoCameraImpl { enum RoundVideoMode { case vga, hdBilinear, hdLanczos } }
struct ExperimentalCameraSettings {
 enum Mode { case legacy, vga, hdBilinear, hdLanczos }
 var resolvedUseModernVideoMessagePipeline: Bool
 var videoMessageCameraMode: Mode
}
public struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
 public var stringValue: String; public var intValue: Int? { nil }
 public init(stringValue: String) { self.stringValue = stringValue }
 public init?(intValue: Int) { return nil }
 public init(stringLiteral value: String) { self.stringValue = value }
}
public enum MessageSavingBridge { public static let defaultDeletedMark = "deleted" }
let roundVideoPreferredAudioBitRate = 64_000
'''
fixture += '\n'.join([
    read(camera + 'Sources/RoundVideoRecordingProfile.swift'),
    read(editor + 'VideoMessageEncodingProfile.swift'),
    declaration(read(editor + 'MediaEditorValues.swift'), 'public enum MediaQualityPreset:'),
    read(screen + 'RoundVideoRecordingCountdown.swift'),
    declaration(capture, 'enum RoundVideoCaptureProfile:'),
    declaration(capture, 'struct RoundVideoCaptureFormatCandidate'),
    declaration(capture, 'private func selectRoundVideoCaptureFormat('),
    declaration(audio, 'func roundVideoAudioBitRate('),
    declaration(read(editor + 'MediaEditorValues.swift'), 'func targetSize('),
    declaration(read(editor + 'MediaEditorValues.swift'), 'private struct VideoMessageExportSettings'),
    declaration(read('submodules/SettingsUI/Sources/AccountOrderController.swift'), 'private func accountIdsApplyingOrder'),
    settings,
])
fixture += '''
func selectedCameraMode(experimentalSettings: ExperimentalCameraSettings, captureSettings: ForkExtrasSettings) -> NeoCameraImpl.RoundVideoMode? {
''' + mode_selection + '''
    return mode
}
'''
checks = r'''
precondition(MediaQualityPreset.videoMessage.maximumDimensions == CGFloat(VideoMessageEncodingProfile.default.maximumDimension))
// Defaults preserve existing installations and settings survive a round trip.
var preferences = try JSONDecoder().decode(ForkExtrasSettings.self, from: Data("{}".utf8))
precondition(!preferences.parallelDownloads && !preferences.hideAIButton && !preferences.hideRichTextEditor)
precondition(!preferences.hideProxySponsor && preferences.localVerificationBadges.isEmpty)
precondition(!preferences.roundVideoCountdown && !preferences.roundVideoRecordAt60FPS && !preferences.roundVideoMaximumQuality)
precondition(!preferences.roundVideoFocusOnTap && !preferences.roundVideoAlwaysResetZoom)
for requested in [ExperimentalCameraSettings.Mode.legacy, .vga, .hdBilinear, .hdLanczos] {
    let existing = ExperimentalCameraSettings(resolvedUseModernVideoMessagePipeline: false, videoMessageCameraMode: requested)
    precondition(selectedCameraMode(experimentalSettings: existing, captureSettings: preferences) == nil)
    for sixtyFPS in [false, true] {
        for quality in [false, true] {
            var selected = preferences
            selected.roundVideoRecordAt60FPS = sixtyFPS
            selected.roundVideoMaximumQuality = quality
            precondition((selectedCameraMode(experimentalSettings: existing, captureSettings: selected) != nil) == (sixtyFPS || quality))
        }
    }
}
preferences.parallelDownloads = true
preferences.hideAIButton = true
preferences.hideRichTextEditor = true
preferences.hideProxySponsor = true
preferences.localVerificationBadges[123] = 2
preferences.roundVideoCountdown = true
preferences.roundVideoRecordAt60FPS = true
preferences.roundVideoMaximumQuality = true
preferences.roundVideoFocusOnTap = true
preferences.roundVideoAlwaysResetZoom = true
let decodedPreferences = try JSONDecoder().decode(ForkExtrasSettings.self, from: JSONEncoder().encode(preferences))
precondition(decodedPreferences == preferences)

// Delayed timer delivery catches up; cancellation and a later start cannot share a deadline.
var countdown = RoundVideoRecordingCountdown()
precondition(!countdown.isRunning && countdown.remaining(at: 0) == nil)
countdown.start(at: 10)
precondition(countdown.remaining(at: 10) == 3 && countdown.remaining(at: 11) == 2)
precondition(countdown.remaining(at: 12.8) == 1 && countdown.remaining(at: 14) == 0)
countdown.cancel()
precondition(countdown.remaining(at: 11) == nil)
countdown.start(at: 20)
precondition(countdown.remaining(at: 20) == 3 && countdown.remaining(at: 23) == 0)

// A drag races safely with deleting, adding, hiding or re-emitting an account.
precondition(accountIdsApplyingOrder(existing: [1, 2, 3], requested: [3, 1]) == [3, 1, 2])
precondition(accountIdsApplyingOrder(existing: [1, 2, 3, 4], requested: [3, 99, 3, 1]) == [3, 1, 2, 4])
precondition(accountIdsApplyingOrder(existing: [Int](), requested: [1]).isEmpty)

for highQuality in [false, true] {
    for sixtyFPS in [false, true] {
        for vga in [false, true] {
            let recording = RoundVideoRecordingProfile(recordAt60FPS: sixtyFPS, maximumQuality: highQuality, limitToVga: vga)
            precondition(recording.frameRate == (sixtyFPS ? 60 : 30))
            precondition(recording.outputSide == (highQuality && !vga ? 640 : 480))
            let encoding = VideoMessageEncodingProfile(maximumDimension: recording.outputSide, videoBitrate: recording.videoBitrate, audioBitrate: recording.audioBitrate, frameRate: recording.frameRate)
            let decoded = try JSONDecoder().decode(VideoMessageEncodingProfile.self, from: JSONEncoder().encode(encoding))
            precondition(decoded == encoding)
            for duration in [1.0, 30.0, 60.0] {
                let bitrate = encoding.fittingVideoBitrate(duration: duration)
                precondition(bitrate <= recording.videoBitrate && bitrate > 0)
                let payload = Double(bitrate + encoding.audioBitrate) * duration / 8.0 + 65_536
                precondition(payload <= Double(encoding.maximumFileSize))
                let output = VideoMessageExportSettings(sourceSize: CGSize(width: 1920, height: 1080), cropSize: CGSize(width: 1080, height: 1080), rotateSideward: false, profile: encoding, duration: duration)
                precondition(output.dimensions.width == CGFloat(recording.outputSide))
                precondition(output.bitrateKbps * 1000 <= bitrate)
            }
            let small = VideoMessageExportSettings(sourceSize: CGSize(width: 240, height: 240), cropSize: CGSize(width: 240, height: 240), rotateSideward: false, profile: encoding, duration: 5)
            precondition(small.dimensions == CGSize(width: 240, height: 240))
            for duration in [0.0, -1.0, .nan, .infinity, -.infinity] {
                precondition(encoding.fittingVideoBitrate(duration: duration) == encoding.videoBitrate)
            }
            precondition(encoding.fittingVideoBitrate(duration: Double.leastNonzeroMagnitude) == encoding.videoBitrate)
        }
    }
}
let corrupt = Data(#"{"maximumDimension":9999,"videoBitrate":9223372036854775807,"audioBitrate":-1,"frameRate":120,"maximumFileSize":-1}"#.utf8)
let bounded = try JSONDecoder().decode(VideoMessageEncodingProfile.self, from: corrupt)
precondition(bounded.maximumDimension == 640 && bounded.videoBitrate == 7_500_000)
precondition(bounded.audioBitrate == 32_000 && bounded.frameRate == 30 && bounded.maximumFileSize == 1)
precondition(bounded.fittingVideoBitrate(duration: 60) == 1000)

// 60 FPS is chosen only if the selected format supports it; 30 FPS is the safe fallback.
func format(_ profile: RoundVideoCaptureProfile, rates: [ClosedRange<Double>], multi: Bool = true) -> RoundVideoCaptureFormatCandidate {
    RoundVideoCaptureFormatCandidate(profile: profile, isNV12: true, frameRateRanges: rates, supportsMultiCam: multi, supportsStandardStabilization: false)
}
let formats = [format(.high, rates: [24...30]), format(.medium, rates: [30...60], multi: false), format(.vga, rates: [30...30])]
precondition(selectRoundVideoCaptureFormat(formats, requiresMultiCam: false, preferStabilization: false, preferMediumProfile: false, frameRate: 60) == 1)
precondition(selectRoundVideoCaptureFormat(formats, requiresMultiCam: true, preferStabilization: false, preferMediumProfile: false, frameRate: 60) == nil)
precondition(selectRoundVideoCaptureFormat(formats, requiresMultiCam: true, preferStabilization: false, preferMediumProfile: false) == 0)
precondition(RoundVideoCaptureProfile(width: 1920, height: 1080, position: .front) == nil)
precondition(RoundVideoCaptureProfile(width: 1920, height: 1080, position: .front, frameRate: 60) == .high)
precondition(roundVideoAudioBitRate(applicable: [8000...24000], preferred: 128_000) == 24000)
precondition(roundVideoAudioBitRate(applicable: [64000...128000], preferred: 128_000) == 128000)
precondition(roundVideoAudioBitRate(applicable: [64000...128000]) == 64000)
precondition(roundVideoAudioBitRate(applicable: []) == nil)
print("Donor policies passed: defaults, persistence, countdown, account churn, capture formats, export limits and Bluetooth audio")
'''
with tempfile.TemporaryDirectory(prefix='donor-updates-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'checks'
    path.write_text(fixture + '\n' + checks)
    subprocess.run(['swiftc', '-warnings-as-errors', str(path), '-o', str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
