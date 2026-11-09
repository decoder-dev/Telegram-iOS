"""Message menu editor (Swiftgram, Regram, exteraGram, Nekogram) and Message JSON (Swiftgram): settings, the Extras
row, the editor screen and the menu hook. Source-text checks; the Swift is verified by the full Bazel build."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
ITEMS = 'submodules/TelegramUIPreferences/Sources/ForkMessageMenu.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
EDITOR = 'submodules/SettingsUI/Sources/ForkMessageMenuController.swift'
MENU = 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift'
CUSTOMIZE = 'submodules/TelegramUI/Sources/ForkMessageMenuCustomization.swift'
JSON = 'submodules/TelegramUI/Sources/ForkMessageJson.swift'

FIELDS = [
    ('messageMenuHiddenItems', '[String]', '[]'),
    ('messageMenuOrder', '[String]', '[]'),
    ('messageJsonMenu', 'Bool', 'false'),
]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def item_cases():
    source = read(ITEMS)
    body = source[source.index('public enum ForkMessageMenuItem'):source.index('public var isMovable')]
    return re.findall(r'^    case (\w+)$', body, re.M)


def main_menu():
    source = read(MENU)
    start = source.index('func contextMenuForChatPresentationInterfaceState(')
    return source[start:source.index('\nprivate func canPerformDeleteActions(', start)]


class MessageMenuSettings(unittest.TestCase):
    def test_fields_are_declared_defaulted_decoded_and_encoded(self):
        source = read(SETTINGS)
        for name, kind, default in FIELDS:
            self.assertIn('    public var %s: %s\n' % (name, kind), source)
            self.assertIn('        self.%s = %s\n' % (name, default), source)
            self.assertIn('self.%s = try container.decodeIfPresent(%s.self, forKey: "%s") ?? %s' % (name, kind, name, default), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_items_follow_the_stock_order_of_the_menu(self):
        # Default order must equal the order the menu appends tagged actions in, or the stock menu would be resorted.
        cases = item_cases()
        menu = main_menu()
        first_seen = []
        for match in re.finditer(r'ForkMessageMenuItem\.(\w+)', menu):
            if match.group(1) not in first_seen:
                first_seen.append(match.group(1))
        self.assertEqual(first_seen, cases)
        self.assertIn('return self != .select', read(ITEMS))


class MessageMenuRows(unittest.TestCase):
    def test_editor_is_reached_from_message_actions(self):
        source = read(EXTRAS)
        page = source[source.index('    case .messageActions:\n        entries = ['):]
        page = page[:page.index('\n        ]\n')]
        self.assertIn('.destination(2320, russian ? "Меню сообщения" : "Message Menu", .messageMenu)', page)
        groups = re.search(r'\(\.messageActions, \[(.*?)\]\),\n', source, re.S).group(1)
        self.assertIn('[2320]', groups)
        self.assertIn('case .messageMenu: pushControllerImpl?(forkMessageMenuController(context: context))', source)
        self.assertEqual(len(re.findall(r'\((23[23]\d)[,)]', source)), 1)

    def test_editor_shows_every_item_and_maps_fork_items_to_their_switches(self):
        editor = read(EDITOR)
        for case in item_cases():
            self.assertIn('    case .%s:' % case, editor[editor.index('private func forkMessageMenuItemTitle('):])
        for case, key_path in [('screenshot', 'messageShot'), ('saveToSavedMessages', 'saveToCloudMenu'), ('messageJson', 'messageJsonMenu'), ('repeatMessage', 'repeatMessageMenu')]:
            self.assertIn('    case .%s:\n        return \\.%s' % (case, key_path), editor)
        self.assertIn('settings.messageMenuOrder = order == ForkMessageMenuItem.allCases.filter({ $0.isMovable }) ? [] : order.map { $0.rawValue }', editor)
        for footer in re.findall(r'\.(?:itemsFooter|selectFooter)\(russian \? "([^"]*)" : "([^"]*)"\)', editor):
            for text in footer:
                self.assertLessEqual(len(text), 170)


class MessageMenuHook(unittest.TestCase):
    def test_menu_is_customized_before_the_leading_separator_is_dropped(self):
        menu = main_menu()
        hook = menu.index('actions = forkCustomizedMessageMenu(actions, settings: extras)')
        self.assertLess(hook, menu.index('if !actions.isEmpty, case .separator = actions[0] {'))
        self.assertLess(menu.index('let extras = context.sharedContext.immediateForkExtrasSettings'), hook)

    def test_stock_settings_leave_the_menu_untouched(self):
        source = read(CUSTOMIZE)
        self.assertIn('if settings.messageMenuHiddenItems.isEmpty && settings.messageMenuOrder.isEmpty {\n        return items\n    }', source)
        self.assertIn("return customItem is ChatDeleteMessageContextItem ? .delete : nil", source)
        self.assertIn('if let last = cleaned.last, case .separator = last {', source)

    def test_cancel_sending_is_never_hidden(self):
        menu = main_menu()
        self.assertIn('let deleteMenuId: AnyHashable? = isSending ? nil : AnyHashable(ForkMessageMenuItem.delete)', menu)
        self.assertIn('ContextMenuActionItem(id: deleteMenuId, text: title, textColor: .destructive', menu)

    def test_message_json_is_off_by_default_and_built_by_hand(self):
        menu = main_menu()
        self.assertIn('if extras.messageJsonMenu {', menu)
        self.assertIn('ForkMessageJsonController(presentationData: presentationData, title: jsonTitle, text: forkMessageJson(message), canCopy: !isCopyProtected)', menu)
        source = read(JSON)
        for key in ['"edit_date"', '"views"', '"reply_to"', '"forward"', '"entities"', '"media"', '"flags"']:
            self.assertIn(key, source)
        self.assertIn('JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])', source)
        self.assertIn('self.textView.isSelectable = self.canCopy', source)


if __name__ == '__main__':
    unittest.main()
