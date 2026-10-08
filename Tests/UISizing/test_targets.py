"""Check effective hit sizes, not decorative icon sizes, from production constants."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding='utf-8')


def slop(text, name):
    match = re.search(re.escape(name) + r'\.hitTestSlop = UIEdgeInsets\(top: ([-\d.]+), left: ([-\d.]+), bottom: ([-\d.]+), right: ([-\d.]+)\)', text)
    return tuple(map(float, match.groups()))


class TouchTargets(unittest.TestCase):
    def test_paste(self):
        text = source('submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift')
        top, _, bottom, _ = slop(text, 'self.pasteButton')
        heights = re.findall(r'let pasteButtonSize = CGSize\(.*?height: ([\d.]+)\)', text)
        self.assertTrue(heights)
        for height in heights:
            self.assertGreaterEqual(float(height) - top - bottom, 44)

    def test_contacts_action(self):
        text = source('submodules/ContactListUI/Sources/LimitedPermissionItem.swift')
        top, _, bottom, _ = slop(text, 'self.actionButton')
        height = float(re.search(r'let actionButtonSize = CGSize\(.*?height: ([\d.]+)\)', text)[1])
        self.assertGreaterEqual(height - top - bottom, 44)

    def test_join_call(self):
        text = source('submodules/CallListUI/Sources/CallListGroupCallItem.swift')
        top, _, bottom, _ = slop(text, 'self.joinButtonNode')
        height = float(re.search(r'let joinButtonSize = CGSize\(.*?height: ([\d.]+)\)', text)[1])
        self.assertGreaterEqual(height - top - bottom, 44)

    def test_playback_speed(self):
        text = source('submodules/TelegramUI/Sources/OverlayAudioPlayerControlsNode.swift')
        top, left, bottom, right = slop(text, 'self.rateButton')
        width, height = map(float, re.search(r'updateFrame\(node: self.rateButton,.*?CGSize\(width: ([\d.]+), height: ([\d.]+)\)', text).groups())
        self.assertGreaterEqual(width - left - right, 44)
        self.assertGreaterEqual(height - top - bottom, 44)

    def test_header_has_room_for_action(self):
        text = source('submodules/ItemListUI/Sources/Items/ItemListSectionHeaderItem.swift')
        self.assertIn('max(44.0, actionLayout.size.width)', text)
        self.assertIn('max(44.0, actionLayoutAndApply!.0.size.height)', text)
        self.assertIn('height: contentSize.height)', text)

    def test_cancel_recording_expands_both_axes(self):
        text = source('submodules/TelegramUI/Components/Chat/ChatTextInputAudioRecordingCancelIndicator/Sources/ChatTextInputAudioRecordingCancelIndicator.swift')
        for axis in ['width', 'height']:
            self.assertIn('(44.0 - self.cancelButton.frame.' + axis + ') / 2.0', text)
