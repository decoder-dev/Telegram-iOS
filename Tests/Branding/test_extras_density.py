"""Extras keeps few settings up front (Apple HIG): less used Messages and Profile switches live on More pages, the main
pages stay short, and footers stay a few lines. Source-text checks; the Swift is verified by the full Bazel build."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / 'submodules/SettingsUI/Sources/ForkExtrasController.swift'

MOVED = {
    'messagesMore': [1931, 1940, 1941, 1942, 1943, 1944, 1721, 1542, 1712, 1700, 1701, 1702, 1533, 1518, 1607, 1510,
                     1513, 1517, 1825, 1826, 1827, 1828, 1960, 1962, 1964],
    'profileMore': [1740, 1736, 1737, 1738, 1603, 1500, 1501, 1541, 2022, 57, 1604, 140, 141],
}
SPECIAL = {'visualPhoneNumber': 1737, 'accentSaturation': 57}


def source():
    return CONTROLLER.read_text(encoding='utf-8')


def page(text, focus):
    body = text.split('private func forkExtrasControllerEntries(', 1)[1]
    start = body.index('\n    case .%s:\n        entries = [\n' % focus)
    return body[start:body.index('\n        ]\n', start)]


def page_ids(text, focus):
    ids = set()
    for line in page(text, focus).split('\n'):
        match = re.match(r'\s+\.(\w+)\((\d+)[,)]', line)
        if match:
            ids.add(int(match.group(2)))
            continue
        match = re.match(r'\s+\.(\w+)\(', line)
        if match and match.group(1) in SPECIAL:
            ids.add(SPECIAL[match.group(1)])
    return ids


def groups_of(text, focus):
    block = text.split('private static let regroupedCategories', 1)[1].split('private static let interfaceGroups', 1)[0]
    match = re.search(r'\(\.%s,\s*\[(.*?)\]\s*\)' % focus, block, re.S)
    return [[int(value) for value in group.replace(' ', '').split(',') if value] for group in re.findall(r'\[([\d,\s]+)\]', match.group(1))]


class ExtrasDensity(unittest.TestCase):
    def test_less_used_rows_moved_one_level_deeper(self):
        text = source()
        for focus, ids in MOVED.items():
            parent = 'messages' if focus == 'messagesMore' else 'profile'
            with self.subTest(focus=focus):
                self.assertTrue(set(ids) <= page_ids(text, focus))
                self.assertFalse(set(ids) & page_ids(text, parent))
                grouped = {value for group in groups_of(text, focus) for value in group}
                self.assertEqual(grouped, set(ids))

    def test_more_pages_are_reachable(self):
        text = source()
        self.assertIn('.destination(2043, russian ? "Ещё о сообщениях" : "More Message Settings", .messagesMore)', page(text, 'messages'))
        self.assertIn('.destination(2044, russian ? "Ещё о профиле" : "More Profile Settings", .profileMore)', page(text, 'profile'))
        self.assertIn([2200, 2201, 2043], groups_of(text, 'messages'))
        self.assertIn([2044], groups_of(text, 'profile'))
        self.assertIn('case .messagesMore: pushControllerImpl?(forkExtrasController(context: context, focus: .messagesMore))', text)
        self.assertIn('case .profileMore: pushControllerImpl?(forkExtrasController(context: context, focus: .profileMore))', text)
        self.assertIn('.messagesMore, .voiceAndRound, .media, .profile, .profileMore, .network]', text)
        links = (ROOT / 'submodules/SettingsUI/Sources/BananaSettingsLinks.swift').read_text(encoding='utf-8')
        self.assertIn('case "messages-more": focus = .messagesMore', links)
        self.assertIn('case .profileMore: return "profile-more"', links)
        search = (ROOT / 'submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift').read_text(encoding='utf-8')
        self.assertIn('("bananagram/messages-more", ForkExtrasControllerFocus.messagesMore.title, [], .messagesMore)', search)
        qa = (ROOT / '.github/workflows/simulator-qa.yml').read_text(encoding='utf-8')
        self.assertIn('"app extras:messagesMore"', qa)
        self.assertIn('"app extras:profileMore"', qa)

    def test_main_pages_stay_short(self):
        text = source()
        for focus in ['messages', 'profile', 'chatList', 'media', 'ghost', 'privacy']:
            with self.subTest(focus=focus):
                toggles = len(re.findall(r'\.(appearanceToggle|settingToggle|musicPolicy)\(', page(text, focus)))
                self.assertLessEqual(toggles, 25, '%s has %d switches; move the less used ones to a More page' % (focus, toggles))

    def test_footers_stay_a_few_lines(self):
        text = source()
        for row, russian, english in re.findall(r'\.designFooter\((\d+), russian \? "((?:[^"\\]|\\.)*)" : "((?:[^"\\]|\\.)*)"', text):
            with self.subTest(row=row):
                self.assertLessEqual(len(russian), 170)
                self.assertLessEqual(len(english), 170)
        for key, value in re.findall(r'"(ForkExtras\.\w*Footer)": "((?:[^"\\]|\\.)*)"', text):
            with self.subTest(key=key):
                self.assertLessEqual(len(value), 170)


    def test_values_are_chosen_on_a_list_not_an_action_sheet(self):
        text = source()
        helper = text.split('    func presentPicker(', 1)[1].split('let presentationData = context.sharedContext.currentPresentationData.with { $0 }', 1)[0]
        self.assertIn('selected: String? = nil', helper)
        self.assertIn('pushControllerImpl?(forkChoiceController(context: context, title: title, options: options.map { $0.0 }, selectedIndex:', helper)
        # Every value picker passes the current value: accent saturation, both backends, sticker size, photo quality,
        # local badge, visual label and the generic numeric choices.
        self.assertEqual(text.count('selected: '), 9)
        choice = (ROOT / 'submodules/SettingsUI/Sources/ForkChoiceController.swift').read_text(encoding='utf-8')
        self.assertIn('ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: checked', choice)
        self.assertIn('select(index)\n        popImpl?()', choice)


if __name__ == '__main__':
    unittest.main()
