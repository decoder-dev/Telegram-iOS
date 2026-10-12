"""Wiring checks complementing the executed sticker geometry fixture."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class StickerSettings(unittest.TestCase):
    def test_size_fit_does_not_resize_already_laid_out_text_emoji(self):
        for node in ["ChatMessageStickerItemNode", "ChatMessageAnimatedStickerItemNode"]:
            source = read(f"submodules/TelegramUI/Components/Chat/{node}/Sources/{node}.swift")
            layout = source.split("override public func asyncLayout()", 1)[1]
            fit_start = layout.index("let stickerLeftMargin = ")
            guard_start = layout.rfind("if !isEmoji {", 0, fit_start)
            self.assertGreaterEqual(guard_start, 0, node)
            # The guard must directly surround fitting, rather than being an
            # unrelated earlier check whose body has already ended.
            self.assertNotIn("}", layout[guard_start:fit_start], node)
            fit_end = layout.index("imageSize = imageSize.aspectFitted", fit_start)
            frame_start = layout.index("var imageFrame = ", fit_end)
            self.assertIn("}", layout[fit_end:frame_start], node)
            self.assertLess(layout.index("textLayoutAndApply!.0.size"), fit_start)

    def test_fit_precedes_frame_and_transform_construction(self):
        for node in ["ChatMessageStickerItemNode", "ChatMessageAnimatedStickerItemNode"]:
            source = read(f"submodules/TelegramUI/Components/Chat/{node}/Sources/{node}.swift")
            fit_start = source.index("let stickerLeftMargin = ")
            tail = source[fit_start:]
            self.assertLess(tail.index("imageSize = imageSize.aspectFitted"), tail.index("var imageFrame = "))
            self.assertLess(tail.index("var imageFrame = "), tail.index("let arguments = TransformImageArguments"))


if __name__ == "__main__":
    unittest.main()
