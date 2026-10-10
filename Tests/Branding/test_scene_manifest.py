import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class SceneManifestTests(unittest.TestCase):
    def test_scene_delegate_name_matches_the_ci_manifest(self):
        swift = (ROOT / 'submodules/TelegramUI/Sources/SceneDelegate.swift').read_text()
        match = re.search(r'@objc\((\w+)\)\s+final class (\w+)', swift)
        self.assertIsNotNone(match, 'SceneDelegate.swift must declare an @objc-named scene delegate')
        self.assertEqual(match.group(1), match.group(2))
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertIn('<string>%s</string>' % match.group(1), workflow)

    def test_manifest_is_only_injected_for_the_ios_27_toolchain(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        step = workflow.split('- name: Adapt sources to the Xcode 27 SDK', 1)[1].split('- name:', 1)[0]
        self.assertIn("inputs.toolchain == 'xcode27'", step)
        self.assertIn('UIApplicationSceneManifest', step)
        for plist in ('Telegram/Telegram-iOS/Info.plist', 'Telegram/Telegram-iOS/InfoBazel.plist', 'Telegram/BUILD'):
            self.assertNotIn('UIApplicationSceneManifest', (ROOT / plist).read_text(), plist)


if __name__ == '__main__':
    unittest.main()
