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
    def test_text_contrast(self):
        source = (ROOT/'submodules/SettingsUI/Sources/BananaGramTheme.swift').read_text(encoding='utf-8')
        palette = {name: (int(dark,16), int(light,16)) for name,dark,light in re.findall(r'let (\w+) = UIColor\(rgb: dark \? (0x[0-9A-F]+) : (0x[0-9A-F]+)\)',source)}
        for mode in (0,1):
            for text in ('foreground','secondary','accent'):
                for background in ('background','surface'):
                    a,b=sorted((luminance(palette[text][mode]),luminance(palette[background][mode])))
                    self.assertGreaterEqual((b+.05)/(a+.05),4.5,(mode,text,background))
    def test_interface_groups_have_unique_ids(self):
        source = (ROOT/'submodules/SettingsUI/Sources/ForkExtrasController.swift').read_text(encoding='utf-8')
        block=source.split('private static let interfaceGroups: [[Int32]] = ',1)[1].split('\n    ]',1)[0]+'\n    ]'
        groups=ast.literal_eval(block)
        ids=[value for group in groups for value in group]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertEqual(len(groups),4)
        self.assertIn(1507,groups[1], 'Tab preview must be with navigation controls')
        self.assertTrue({1500,1501}.issubset(groups[3]))
if __name__=='__main__': unittest.main()
