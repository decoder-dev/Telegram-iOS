"""Compile extracted production policies; structural checks also run on Windows."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def declaration(path, marker):
    text = read(path)
    start = text.index(marker)
    return text[start:text.index("\n}", start) + 2]


class WiringTests(unittest.TestCase):
    def test_round_permission_and_single_selection(self):
        source = read("submodules/MediaPickerUI/Sources/LegacyMediaPickerGallery.swift")
        self.assertIn("canSendRoundVideo, voiceMessagesAvailable", source)
        self.assertIn("CachedUserData)?.voiceMessagesAvailable", source)
        self.assertIn("onlyCurrentItemSelected", source)
        self.assertIn(".banSendInstantVideos", source)
        self.assertIn("editingContext.price(for: item.asset) == nil", source)
        self.assertIn("ActionSheetButtonItem(title: presentationData.strings.Common_Cancel", source)

    def test_round_metadata_matches_conversion(self):
        source = read("submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift")
        self.assertIn("isRoundVideo ? [.instantRoundVideo] : [.supportsStreaming]", source)
        self.assertIn("localGroupingKey: isRoundVideo ? nil : item.groupedId", source)
        self.assertIn("videoCover: isRoundVideo ? nil : videoCover", source)
        self.assertIn("videoMessageDimensions(for: adjustments.cropRect.size)", source)

    def test_stable_appearance_ids_are_unique(self):
        source = read("submodules/SettingsUI/Sources/ForkExtrasController.swift")
        ids = re.findall(r"\.appearanceToggle\((\d+),", source)
        ids += re.findall(r"case \.(?:tabPreview|callsTab): return (\d+)", source)
        self.assertEqual(len(ids), len(set(ids)), "Duplicate item IDs break list diffs")

    def test_link_is_navigation_only(self):
        source = read("submodules/SettingsUI/Sources/BananaSettingsLinks.swift")
        self.assertNotIn("updateForkExtrasSettings", source)
        self.assertIn("current is UIControl", source)
        self.assertIn("current is UITextField", source)
        routing = read("submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift")
        self.assertIn("focus: focus, focusItemId: itemId", routing)

    def test_live_counter_refresh_and_missing_attribute(self):
        source = read("submodules/TelegramUI/Sources/ChatHistoryListNode.swift")
        self.assertIn("showChannelForwardCount: settings.showChannelForwardCount", source)
        core = read("submodules/TelegramCore/Sources/State/AccountViewTracker.swift")
        self.assertIn("if !foundForwards, let forwards", core)

    def test_audio_paths_have_independent_policy(self):
        self.assertIn("!BananaAudioPolicy.current.pauseMusicOnVoiceRecording", read("submodules/TelegramUI/Sources/ManagedAudioRecorder.swift"))
        self.assertIn("!BananaAudioPolicy.current.pauseMusicOnVoicePlayback", read("submodules/TelegramUI/Sources/SharedMediaPlayer.swift"))
        self.assertIn("self.videoRecorderValue != nil ? settings.pauseMusicOnRecording : settings.pauseMusicOnVoiceRecording", read("submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift"))


def swift_tests():
    prefs = declaration("submodules/TelegramUIPreferences/Sources/MediaInputSettings.swift", "public struct MediaInputSettings:")
    key = read("submodules/TelegramCore/Sources/TelegramEngine/Utils/StringCodingKey.swift")
    geometry = declaration("submodules/MediaPickerUI/Sources/LegacyMediaPickerGallery.swift", "func bananaRoundVideoGeometry(")
    parser = declaration("submodules/SettingsUI/Sources/BananaSettingsLinks.swift", "func bananaSettingsLinkTarget(")
    page = declaration("submodules/SettingsUI/Sources/BananaSettingsLinks.swift", "func bananaSettingsPage(")
    fixture = r'''
import Foundation
import CoreGraphics
enum ForkExtrasControllerFocus: Equatable {
    case top, ninja, ghost, privacy, interface, chat, network, messageSaving, messageFilters
    var resolvedCategory: Self { switch self { case .messageSaving, .messageFilters: return .ninja; default: return self } }
}
'''
    tests = r'''
for mask in 0..<8 {
    let saved = MediaInputSettings(enableRaiseToSpeak: false, pauseMusicOnRecording: mask & 1 != 0, pauseMusicOnVoiceRecording: mask & 2 != 0, pauseMusicOnVoicePlayback: mask & 4 != 0)
    let encoded = try JSONEncoder().encode(saved)
    let decoded = try JSONDecoder().decode(MediaInputSettings.self, from: encoded)
    precondition(decoded == saved)
    let updated = saved.withUpdatedEnableRaiseToSpeak(true)
    precondition(updated.pauseMusicOnRecording == saved.pauseMusicOnRecording)
    precondition(updated.pauseMusicOnVoiceRecording == saved.pauseMusicOnVoiceRecording)
    precondition(updated.pauseMusicOnVoicePlayback == saved.pauseMusicOnVoicePlayback)
    precondition(saved.withUpdatedPauseMusicOnRecording(true).pauseMusicOnVoicePlayback == saved.pauseMusicOnVoicePlayback)
    precondition(saved.withUpdatedVoiceMusicPolicy(recording: true).pauseMusicOnRecording == saved.pauseMusicOnRecording)
    precondition(saved.withUpdatedVoiceMusicPolicy(playback: false).pauseMusicOnVoiceRecording == saved.pauseMusicOnVoiceRecording)
}
let old = try JSONDecoder().decode(MediaInputSettings.self, from: Data(#"{"enableRaiseToSpeak":1,"pauseMusicOnRecording_v2":0}"#.utf8))
precondition(!old.pauseMusicOnRecording && old.pauseMusicOnVoiceRecording && old.pauseMusicOnVoicePlayback)
for focus in [ForkExtrasControllerFocus.top, .ninja, .ghost, .privacy, .interface, .chat, .network] {
    let page = bananaSettingsPage(focus)
    let parsed = bananaSettingsLinkTarget("bananagram/" + page + "/1508")!
    precondition(parsed.0 == focus && parsed.1 == 1508)
    precondition(bananaSettingsLinkTarget("bananagram/" + page)!.1 == nil)
}
for path in ["", "bananagram", "bananagram/unknown", "bananagram/appearance/", "bananagram/appearance/-1", "bananagram/appearance/999999999999999", "bananagram/appearance/1/2", "bananagram/appearance/1?value=true", "bananagram/appearance/١", "other/appearance/1"] {
    precondition(bananaSettingsLinkTarget(path) == nil, path)
}
let wide = bananaRoundVideoGeometry(size: CGSize(width: 1920, height: 1080), crop: nil, duration: 120, trimStart: 10, trimEnd: 100)!
precondition(wide.0 == CGRect(x: 420, y: 0, width: 1080, height: 1080))
precondition(wide.1 == 10 && wide.2 == 70)
let tall = bananaRoundVideoGeometry(size: CGSize(width: 1080, height: 1920), crop: nil, duration: 30, trimStart: 0, trimEnd: 0)!
precondition(tall.0 == CGRect(x: 0, y: 420, width: 1080, height: 1080) && tall.2 == 30)
let selected = bananaRoundVideoGeometry(size: CGSize(width: 1920, height: 1080), crop: CGRect(x: 100, y: 200, width: 800, height: 400), duration: 80, trimStart: 20, trimEnd: 35)!
precondition(selected.0 == CGRect(x: 300, y: 200, width: 400, height: 400) && selected.2 == 35)
for invalid in [Double.nan, .infinity, -.infinity] {
    precondition(bananaRoundVideoGeometry(size: CGSize(width: 100, height: 100), crop: nil, duration: invalid, trimStart: 0, trimEnd: 0) == nil)
    precondition(bananaRoundVideoGeometry(size: CGSize(width: 100, height: 100), crop: nil, duration: 30, trimStart: invalid, trimEnd: 0) == nil)
}
precondition(bananaRoundVideoGeometry(size: CGSize(width: 10, height: 10), crop: nil, duration: 30, trimStart: 0, trimEnd: 0) == nil)
precondition(bananaRoundVideoGeometry(size: CGSize(width: 100, height: 100), crop: CGRect(x: 500, y: 500, width: 100, height: 100), duration: 30, trimStart: 0, trimEnd: 0) == nil)
precondition(bananaRoundVideoGeometry(size: CGSize(width: 100, height: 100), crop: nil, duration: 30, trimStart: 35, trimEnd: 0) == nil)
print("Audio settings migration/round trips, navigation-only links, round video crops/trims passed")
'''
    with tempfile.TemporaryDirectory(prefix="banana-additions-") as tmp:
        path = pathlib.Path(tmp) / "main.swift"
        path.write_text("\n\n".join([fixture, key, prefs, geometry, parser, page, tests]), encoding="utf-8")
        subprocess.run(["swift", str(path)], check=True)
        for source in [
            "submodules/SettingsUI/Sources/BananaSettingsLinks.swift",
            "submodules/SettingsUI/Sources/ForkExtrasController.swift",
            "submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift",
            "submodules/MediaPickerUI/Sources/LegacyMediaPickerGallery.swift",
            "submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift",
            "submodules/LegacyMediaPickerUI/Sources/LegacyPaintStickersContext.swift",
            "submodules/TelegramAudio/Sources/ManagedAudioSession.swift",
            "submodules/MediaPlayer/Sources/MediaPlayerAudioRenderer.swift",
        ]:
            subprocess.run(["swiftc", "-frontend", "-parse", str(ROOT / source)], check=True)


if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(WiringTests))
    if not result.wasSuccessful():
        sys.exit(1)
    if "--structural-only" not in sys.argv:
        swift_tests()
