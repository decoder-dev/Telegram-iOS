import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class SceneManifestTests(unittest.TestCase):
    def test_scene_delegate_name_matches_the_application_manifest(self):
        swift = (ROOT / 'submodules/TelegramUI/Sources/SceneDelegate.swift').read_text()
        match = re.search(r'@objc\((\w+)\)\s+final class (\w+)', swift)
        self.assertIsNotNone(match, 'SceneDelegate.swift must declare an @objc-named scene delegate')
        self.assertEqual(match.group(1), match.group(2))
        manifest = (ROOT / 'Telegram/BUILD').read_text()
        self.assertIn('<string>%s</string>' % match.group(1), manifest)
        self.assertEqual(manifest.count('<key>UIApplicationSceneManifest</key>'), 1)
        self.assertEqual(manifest.count('<key>UISceneDelegateClassName</key>'), 1)

    def test_ci_does_not_inject_a_second_scene_manifest(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        step = workflow.split('- name: Adapt sources to the Xcode 27 SDK', 1)[1].split('- name:', 1)[0]
        self.assertIn("inputs.toolchain == 'xcode27'", step)
        self.assertNotIn('UIApplicationSceneManifest', step)
        self.assertNotIn('TelegramSceneDelegate', workflow)


if __name__ == '__main__':
    unittest.main()
