"""Compatibility contracts after withdrawing the Messages appearance."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def source(path):
    return (ROOT / path).read_text(encoding='utf-8')

class MessagesRollback(unittest.TestCase):
    def test_legacy_theme_ids_resolve_to_stock_appearances(self):
        settings = source('submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift')
        for contract in ('case messagesDay = 7', 'case messagesNight = 8',
                         'case .messagesDay: return .day', 'case .messagesNight: return .night',
                         '?? .dayClassic).restoredAppearance'):
            self.assertIn(contract, settings)
        factory = source('submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift')
        gate = factory.split('var isMessagesTheme: Bool {', 1)[1].split('}', 1)[0]
        self.assertIn('return false', gate)
        self.assertNotIn('messages: true', factory)

    def test_messages_choices_are_removed_but_halloween_remains(self):
        selection = source('submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift')
        self.assertNotIn('(.messagesDay, "Messages Light")', selection)
        self.assertNotIn('(.messagesNight, "Messages Dark")', selection)
        self.assertNotIn('result.chatBubbleSettings.style = .messages', selection)
        self.assertIn('(.bananaGramHalloween, "BananaGram Halloween")', selection)
        bubbles = source('submodules/SettingsUI/Sources/BubbleSettings/BubbleSettingsController.swift')
        self.assertNotIn('styleControl', bubbles)

    def test_defaults_and_saved_bubble_styles_restore_standard(self):
        settings = source('submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift')
        defaults = settings.split('public static var defaultSettings:', 1)[1].split('public init(', 1)[0]
        self.assertIn('theme: .builtin(.dayClassic)', defaults)
        self.assertIn('chatBubbleSettings: .default', defaults)
        self.assertNotIn('.messagesNight', defaults)
        self.assertIn('if self.style == .messages {\n            self = .default', settings)
        presentation = source('submodules/TelegramPresentationData/Sources/PresentationData.swift')
        self.assertIn('updated.chatBubbleSettings = .default', presentation)
        self.assertIn('updated.theme = .builtin(reference.restoredAppearance)', presentation)

    def test_existing_messages_icon_restores_the_primary_icon(self):
        app = source('submodules/TelegramUI/Sources/AppDelegate.swift')
        self.assertNotIn('PresentationAppIcon(name: "MessagesIcon"', app)
        self.assertIn('UIApplication.shared.alternateIconName == "MessagesIcon"', app)
        self.assertIn('UIApplication.shared.setAlternateIconName(nil, completionHandler: nil)', app)

if __name__ == '__main__':
    unittest.main()
