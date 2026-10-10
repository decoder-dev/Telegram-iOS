import ast
import pathlib
import re
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]

def luminance(rgb):
    channels = [(rgb >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(a * b for a, b in zip(linear, (0.2126, 0.7152, 0.0722)))

class ThemeTests(unittest.TestCase):
    def test_unread_badges_in_the_bars_follow_the_accent(self):
        # The stock tab bar / navigation bar badge is red; the BananaGram themes carry their own.
        source = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        body = source.split('private func makeBananaGramTheme', 1)[1].split('return PresentationTheme(', 1)[0]
        self.assertRegex(body, r'tabBar: theme\.rootController\.tabBar\.withUpdated\([^\n]*badgeBackgroundColor: accent[^\n]*badgeTextColor: onAccent')
        self.assertRegex(body, r'navigationBar: theme\.rootController\.navigationBar\.withUpdated\([^\n]*badgeBackgroundColor: accent[^\n]*badgeTextColor: onAccent')
    
    def test_text_contrast(self):
        source = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        palette = {name: (int(dark,16), int(light,16)) for name,dark,light in re.findall(r'let (\w+) = UIColor\(rgb: dark \? (0x[0-9A-F]+) : (0x[0-9A-F]+)\)',source)}
        for mode in (0,1):
            for text in ('foreground','secondary','accent'):
                for background in ('background','surface','raisedSurface'):
                    a,b=sorted((luminance(palette[text][mode]),luminance(palette[background][mode])))
                    self.assertGreaterEqual((b+.05)/(a+.05),4.5,(mode,text,background))
            # Glyphs on accent fills (send button, checkmarks, unread badges).
            a,b=sorted((luminance(palette['onAccent'][mode]),luminance(palette['accent'][mode])))
            self.assertGreaterEqual((b+.05)/(a+.05),4.5,(mode,'onAccent','accent'))
    def test_secondary_text_on_pressed_and_search_surfaces(self):
        source = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        palette = {name: (int(dark,16), int(light,16)) for name,dark,light in re.findall(r'let (\w+) = UIColor\(rgb: dark \? (0x[0-9A-F]+) : (0x[0-9A-F]+)\)',source)}
        for mode in (0,1):
            for text in ('foreground','secondary'):
                for background in ('highlighted','searchBar'):
                    a,b=sorted((luminance(palette[text][mode]),luminance(palette[background][mode])))
                    self.assertGreaterEqual((b+.05)/(a+.05),4.5,(mode,text,background))
        # White badge text on the inactive (muted) unread badge.
        for mode,value in enumerate(re.search(r'unreadBadgeInactiveBackgroundColor: UIColor\(rgb: dark \? (0x[0-9A-F]+) : (0x[0-9A-F]+)\)',source).groups()):
            self.assertGreaterEqual(1.05/(luminance(int(value,16))+.05),3.0,('inactive badge',mode))
    def test_call_screen_palettes_keep_white_text_legible(self):
        source = (ROOT/'submodules/TelegramUI/Components/Calls/CallScreen/Sources/CallScreenPalette.swift').read_text(encoding='utf-8')
        sets = re.findall(r'(?:connecting|active|weakSignal): \[((?:0x[0-9A-Fa-f]{6},? ?){4})\]',source)
        self.assertEqual(len(sets),12,'four themes x three call states')
        floor = float(re.search(r'minimumContrast: Double = ([0-9.]+)',source).group(1))
        for colors in sets:
            for value in re.findall(r'0x[0-9A-Fa-f]{6}',colors):
                self.assertGreaterEqual(1.05/(luminance(int(value,16))+.05),floor,value)
    def test_call_palette_recognises_bananagram_by_index(self):
        # referenceTheme stays .day/.night for the BananaGram themes; switching on it alone sent their yellow accent to the derived palette.
        source = (ROOT/'submodules/TelegramUI/Components/Calls/CallScreen/Sources/CallScreenPalette.swift').read_text(encoding='utf-8')
        self.assertIn('theme.bananaGramReference ?? theme.referenceTheme',source)
        themes = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        self.assertIn('var bananaGramReference: PresentationBuiltinThemeReference?',themes)
    def test_graphite_neutrals_are_warm(self):
        source = (ROOT/'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
        for name in ('background','surface','raisedSurface','separator'):
            dark = int(re.search(r'let '+name+r' = UIColor\(rgb: dark \? (0x[0-9A-F]+)',source).group(1),16)
            red, blue = dark >> 16 & 255, dark & 255
            self.assertGreaterEqual(red, blue, name+' must not lean blue: Graphite is a warm charcoal')
    def test_interface_groups_have_unique_ids(self):
        source = (ROOT/'submodules/SettingsUI/Sources/ForkExtrasController.swift').read_text(encoding='utf-8')
        block=source.split('private static let interfaceGroups: [[Int32]] = ',1)[1].split('\n    ]',1)[0]+'\n    ]'
        groups=ast.literal_eval(block)
        ids=[value for group in groups for value in group]
        self.assertEqual(len(ids),len(set(ids)))
        footers={53,58,60,62,64,66,68}
        for group in groups:
            for index,value in enumerate(group):
                if value in footers:
                    self.assertEqual(index,len(group)-1,'footer %d must close its section, not sit between switches'%value)
        self.assertIn([1507],groups,'Tab preview is a section of its own')
        self.assertTrue(any({1500,1501}.issubset(group) for group in groups))
if __name__=='__main__': unittest.main()
