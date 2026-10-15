import gzip
import json
import pathlib
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET
from test_themes import luminance

ROOT = pathlib.Path(__file__).resolve().parents[2]


def ratio(first, second):
    low, high = sorted((luminance(first), luminance(second)))
    return (high + .05) / (low + .05)


class HalloweenTests(unittest.TestCase):
    def test_palette_contrast_including_pressed_rows_and_bubbles(self):
        source = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        colors = {key: int(value, 16) for key, value in re.findall(r'let (\w+) = UIColor\(rgb: (?:messages && dark \? 0x[0-9A-F]+ : messages \? 0x[0-9A-F]+ : )?halloween \? (0x[0-9A-F]+)', source)}
        for text in ('foreground', 'secondary', 'accent'):
            for fill in ('background', 'surface', 'raisedSurface', 'searchBar', 'highlighted', 'pinnedRow'):
                self.assertGreaterEqual(ratio(colors[text], colors[fill]), 4.5, (text, fill))
        bubbles = re.search(r'outgoingBubbleColors: \[UInt32\] = (?:messages \? \[[^]]+\] : )?halloween \? \[([^]]+)\]', source).group(1)
        for fill in re.findall(r'0x[0-9A-F]+', bubbles):
            self.assertGreaterEqual(ratio(colors['foreground'], int(fill, 16)), 4.5)
        self.assertGreaterEqual(ratio(colors['onAccent'], colors['accent']), 4.5)
        self.assertGreaterEqual(ratio(colors['foreground'], colors['inactiveBadgeBackground']), 4.5)

    def test_offline_wallpaper_is_the_checked_in_vector_master(self):
        svg = (ROOT/'assets/branding/HalloweenWallpaper.svg').read_bytes()
        packed = (ROOT/'submodules/TelegramUI/Resources/bananagram-halloween-v1.tgv').read_bytes()
        self.assertEqual(gzip.decompress(packed), svg)
        tree = ET.fromstring(svg)
        self.assertEqual(tree.attrib['viewBox'], '0 0 1440 2960')
        self.assertGreater(len(list(tree.iter('{http://www.w3.org/2000/svg}path'))), 80)
        self.assertNotIn(b'href=', svg)
        self.assertNotIn(b'<image', svg)
        factory = (ROOT/'submodules/TelegramPresentationData/Sources/DefaultDayPresentationTheme.swift').read_text(encoding='utf-8')
        self.assertIn('WallpaperDataResource(slug: data.slug)', factory)
        self.assertIn(f'fileSize: {len(packed)}', factory)
        fetcher = (ROOT/'submodules/TelegramUI/Components/TelegramAccountAuxiliaryMethods/Sources/TelegramAccountAuxiliaryMethods.swift').read_text(encoding='utf-8')
        self.assertIn('"bananagram-halloween-v1"', fetcher.split('if builtinWallpapers.contains', 1)[0])
        cache = (ROOT/'submodules/WallpaperResources/Sources/WallpaperCache.swift').read_text(encoding='utf-8')
        self.assertLess(cache.index('if slug == "bananagram-halloween-v1"'), cache.index('return engine.data.get'))

    def test_builtin_identity_and_theme_serialization(self):
        settings = (ROOT/'submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift').read_text(encoding='utf-8')
        self.assertIn('case bananaGramHalloween = 6', settings)
        self.assertIn('case .night, .bananaGramGraphite, .bananaGramHalloween:', settings)
        codec = (ROOT/'submodules/TelegramPresentationData/Sources/PresentationThemeCodable.swift').read_text(encoding='utf-8')
        self.assertIn('case "bananagramhalloween":\n                    self = .bananaGramHalloween', codec)
        self.assertIn('case .bananaGramHalloween:\n                try container.encode("bananagramhalloween")', codec)
        accent = (ROOT/'submodules/PresentationDataUtils/Sources/DefaultAccentPresentationData.swift').read_text(encoding='utf-8')
        self.assertLess(accent.index('if theme.bananaGramReference != nil'), accent.index('switch theme.referenceTheme'))
        selection = (ROOT/'submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift').read_text(encoding='utf-8')
        self.assertIn('if theme.baseTheme == .day || theme.baseTheme == .classic', selection)
        self.assertNotIn('if [.day, .dayClassic].contains(theme)', selection)

    def test_icon_registered_for_launcher_preview_and_ipad(self):
        self.assertIn('"HalloweenIcon"', (ROOT/'Telegram/BUILD').read_text(encoding='utf-8').split('alternate_icon_folders = [', 1)[1].split(']', 1)[0])
        for path in ('submodules/TelegramUI/Sources/AppDelegate.swift', 'submodules/SettingsUI/Sources/Themes/ThemeSettingsAppIconItem.swift'):
            self.assertIn('"HalloweenIcon"', (ROOT/path).read_text(encoding='utf-8'))
        info = plistlib.loads((ROOT/'Telegram/Telegram-iOS/Info.plist').read_bytes())
        for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
            self.assertIn('HalloweenIcon', info[key]['CFBundleAlternateIcons'])
        manifest = json.loads((ROOT/'assets/branding/manifest.json').read_text())
        sizes = {tuple(asset['size']) for asset in manifest if asset['palette'] == 'HalloweenIcon'}
        for size in (29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024):
            self.assertIn((size, size), sizes)


if __name__ == '__main__':
    unittest.main()
