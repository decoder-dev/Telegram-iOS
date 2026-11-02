"""Contrast checks against the palette used by the native theme builder."""

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'submodules/TelegramPresentationData/Sources/LiquidPresentationTheme.swift'


def luminance(rgb):
    channels = [(rgb >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return sum(value * weight for value, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


class LiquidContrastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.palette = {
            name: (int(dark, 16), int(light, 16))
            for name, dark, light in re.findall(
                r'self\.(\w+) = UIColor\(rgb: dark \? (0x[0-9A-F]+) : (0x[0-9A-F]+)\)', SOURCE.read_text()
            )
        }

    def assert_contrast(self, foreground, background, minimum=4.5):
        low, high = sorted((luminance(foreground), luminance(background)))
        self.assertGreaterEqual((high + 0.05) / (low + 0.05), minimum)

    def test_text_and_placeholders_on_content_surfaces(self):
        for mode in (0, 1):
            for text in ('primaryText', 'secondaryText'):
                for surface in ('background', 'surface', 'groupedBackground', 'incoming'):
                    with self.subTest(mode=mode, text=text, surface=surface):
                        self.assert_contrast(self.palette[text][mode], self.palette[surface][mode])

    def test_links_and_inactive_reactions(self):
        for mode in (0, 1):
            for surface in ('incoming', 'groupedBackground'):
                with self.subTest(mode=mode, surface=surface):
                    self.assert_contrast(self.palette['link'][mode], self.palette[surface][mode])

    def test_send_controls_badges_and_selected_reactions(self):
        for mode in (0, 1):
            with self.subTest(mode=mode):
                self.assert_contrast(self.palette['onAccent'][mode], self.palette['accent'][mode])
                self.assert_contrast(self.palette['background'][mode], self.palette['secondaryText'][mode])

    def test_outgoing_text_and_status(self):
        for mode in (0, 1):
            with self.subTest(mode=mode):
                self.assert_contrast(0xFFFFFF, self.palette['outgoing'][mode])

    def test_destructive_labels_and_incoming_scam_warning(self):
        for mode in (0, 1):
            for surface in ('background', 'surface', 'incoming'):
                with self.subTest(mode=mode, surface=surface):
                    self.assert_contrast(self.palette['destructive'][mode], self.palette[surface][mode])


if __name__ == '__main__':
    unittest.main()
