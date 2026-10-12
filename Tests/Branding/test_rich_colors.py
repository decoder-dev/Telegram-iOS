import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest
from test_themes import luminance

ROOT = pathlib.Path(__file__).resolve().parents[2]

class RichColors(unittest.TestCase):
    def test_inactive_badge_contrast(self):
        source = (ROOT / 'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        palette = {name: (int(dark, 16), int(light, 16)) for name, dark, light in re.findall(r'let (\w+) = UIColor\(rgb: dark \? (0x[0-9A-F]+) : (0x[0-9A-F]+)\)', source)}
        self.assertIn('unreadBadgeInactiveTextColor: dark ? foreground : onAccent', source)
        for mode, text in enumerate(('foreground', 'onAccent')):
            a, b = sorted((luminance(palette[text][mode]), luminance(palette['inactiveBadgeBackground'][mode])))
            self.assertGreaterEqual((b + .05) / (a + .05), 4.5)

    def test_hosts_supply_theme_colors(self):
        paths = [
            'submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift',
            'submodules/TelegramUI/Sources/Chat/ChatSendMessageRichTextPreview.swift',
            'submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingRichContentView.swift',
        ]
        for path in paths:
            source = (ROOT / path).read_text(encoding='utf-8')
            self.assertNotIn('0xfef3bc', source)
            for field in ('checkboxFill:', 'checkboxForeground:', 'neutralButtonBackgroundColor:', 'neutralButtonForegroundColor:', 'buttonDangerForegroundColor:', 'buttonSuccessForegroundColor:'):
                self.assertIn(field, source, path)
        for path in paths[:2]:
            self.assertIn('instantPageSolidButtonForegroundColor(', (ROOT / path).read_text(encoding='utf-8'))

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; runs in macOS CI')
    def test_production_solid_fill_foreground(self):
        source = (ROOT / 'submodules/InstantPageUI/Sources/InstantPageTheme.swift').read_text(encoding='utf-8')
        function = 'public func instantPageSolidButtonForegroundColor' + source.split('public func instantPageSolidButtonForegroundColor', 1)[1].split('public enum InstantPageFontStyle', 1)[0]
        fixture = '''import Foundation
public struct UIColor {
 public let components: (r: CGFloat, g: CGFloat, b: CGFloat)
 public static let black = UIColor(components: (0, 0, 0))
 public static let white = UIColor(components: (1, 1, 1))
}
''' + function + '''
for r in stride(from: 0.0, through: 1.0, by: 0.1) {
 for g in stride(from: 0.0, through: 1.0, by: 0.1) {
  for b in stride(from: 0.0, through: 1.0, by: 0.1) {
   func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
   let l = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
   let result = instantPageSolidButtonForegroundColor(UIColor(components: (CGFloat(r), CGFloat(g), CGFloat(b))))
   let ratio = result.components.r == 0 ? (l + 0.05) / 0.05 : 1.05 / (l + 0.05)
   precondition(ratio >= 4.5)
  }
 }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'main.swift'
            executable = pathlib.Path(directory) / 'fixture'
            path.write_text(fixture, encoding='utf-8')
            subprocess.run(['swiftc', str(path), '-o', str(executable)], check=True, timeout=120)
            subprocess.run([str(executable)], check=True, timeout=30)
