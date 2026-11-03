"""Check effective hit sizes, not decorative icon sizes, from production constants."""
import pathlib
import re
import subprocess
import tempfile
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
        button = re.search(r'^\s*let actionButtonSize = .*$', text, re.MULTILINE)[0]
        metrics = source('submodules/TelegramPresentationData/Sources/PresentationLayoutMetrics.swift')
        fixture = '''import Foundation
struct LabelLayout { let size: CGSize }
for width: CGFloat in [0, 24, 120, 200] {
    for height: CGFloat in [0, 18, 32, 72, 120] {
        let buttonTextLayout = LabelLayout(size: CGSize(width: width, height: height))
''' + metrics + '''
''' + button
        fixture += '''
        precondition(actionButtonSize.width >= 44)
        precondition(actionButtonSize.height >= 44)
        precondition(actionButtonSize.height >= buttonTextLayout.size.height + 16)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='contacts-targets-') as directory:
            path = pathlib.Path(directory) / 'main.swift'
            path.write_text(fixture)
            subprocess.run(['swift', str(path)], check=True)

    def test_join_call(self):
        text = source('submodules/CallListUI/Sources/CallListGroupCallItem.swift')
        button = re.search(r'^\s*let joinButtonSize = .*$', text, re.MULTILINE)[0]
        expansion = re.search(r'^\s*let verticalSlop = .*$', text, re.MULTILINE)[0]
        metrics = source('submodules/TelegramPresentationData/Sources/PresentationLayoutMetrics.swift')
        fixture = metrics + '''
struct LabelLayout { let size: CGSize }
for width: CGFloat in [0, 24, 120, 200] {
    for height: CGFloat in [0, 18, 32, 72, 120] {
        let joinTitleLayout = LabelLayout(size: CGSize(width: width, height: height))
'''
        fixture += button + '\n' + expansion
        fixture += '''
        precondition(joinButtonSize.width >= 44)
        precondition(joinButtonSize.height + verticalSlop * 2 >= 44)
        precondition(joinButtonSize.height >= joinTitleLayout.size.height + 12)
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='call-targets-') as directory:
            path = pathlib.Path(directory) / 'main.swift'
            path.write_text(fixture)
            subprocess.run(['swift', str(path)], check=True)

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
