import json
import pathlib
import plistlib
import re
import unittest
from test_themes import luminance

ROOT = pathlib.Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT/path).read_text(encoding='utf-8')


def ratio(first, second):
    low, high = sorted((luminance(first), luminance(second)))
    return (high + .05) / (low + .05)


class MessagesAppearance(unittest.TestCase):
    def test_both_palettes_and_white_metadata_on_blue_clear_aa(self):
        factory = source('submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift')
        palette = {name: (int(dark, 16), int(light, 16)) for name, dark, light in re.findall(r'let (\w+) = UIColor\(rgb: messages && dark \? (0x[0-9A-F]+) : messages \? (0x[0-9A-F]+)', factory)}
        for mode in (0, 1):
            for text in ('foreground', 'secondary', 'accent'):
                for fill in ('background', 'surface', 'raisedSurface', 'highlighted', 'searchBar', 'pinnedRow'):
                    self.assertGreaterEqual(ratio(palette[text][mode], palette[fill][mode]), 4.5, (mode, text, fill))
            self.assertGreaterEqual(ratio(palette['onAccent'][mode], palette['accent'][mode]), 4.5)
            badge_text = 'foreground' if mode == 0 else 'onAccent'
            self.assertGreaterEqual(ratio(palette[badge_text][mode], palette['inactiveBadgeBackground'][mode]), 4.5)
        outgoing = re.search(r'outgoingBubbleColors: \[UInt32\] = messages \? \[([^]]+)\]', factory).group(1)
        for fill in re.findall(r'0x[0-9A-F]+', outgoing):
            fill = int(fill, 16)
            self.assertGreaterEqual(ratio(0xFFFFFF, fill), 4.5)
            channels = [round(255*.92 + (fill >> shift & 255)*.08) for shift in (16, 8, 0)]
            metadata = channels[0] << 16 | channels[1] << 8 | channels[2]
            self.assertGreaterEqual(ratio(metadata, fill), 4.5)
        self.assertIn('let actionFill = messages ? UIColor(rgb: 0x0064CF) : accent', factory)
        self.assertIn('let actionForeground = messages ? UIColor.white : onAccent', factory)
        self.assertIn('inputFillColor: messages ? searchBar : background', factory)
        self.assertIn('inputBackgroundColor: messages ? searchBar : dark ?', factory)

    def test_neutral_wallpapers_and_identity_survive_customization(self):
        factory = source('submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift')
        self.assertIn('messages ? .color(dark ? 0x000000 : 0xFFFFFF)', factory)
        settings = source('submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift')
        self.assertIn('case messagesDay = 7', settings)
        self.assertIn('case messagesNight = 8', settings)
        codec = source('submodules/TelegramPresentationData/Sources/PresentationThemeCodable.swift')
        for key, name in (('messagesday', 'messagesDay'), ('messagesnight', 'messagesNight')):
            self.assertIn('case "'+key+'":\n                    self = .'+name, codec)
            self.assertIn('try container.encode("'+key+'")', codec)
            self.assertIn('PresentationThemeReference.builtin(.'+name+').index', factory)
        selection = source('submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift')
        self.assertIn('result.chatBubbleSettings.style = .messages', selection)
        self.assertIn('if result.chatBubbleSettings.style != .messages', selection)

    def test_new_install_default_does_not_migrate_existing_preferences(self):
        settings = source('submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift')
        defaults = settings.split('public static var defaultSettings:', 1)[1].split('public init(', 1)[0]
        self.assertIn('theme: .builtin(.messagesNight)', defaults)
        self.assertIn('chatBubbleSettings: .messages', defaults)
        # Existing serialized bubble settings missing the new key retain Standard, rather than opting in during decode.
        self.assertIn('PresentationChatBubbleStyle(rawValue: try container.decodeIfPresent(Int32.self, forKey: "style") ?? 0) ?? .standard', settings)

    def test_dot_reuse_and_date_disclosure_do_not_overlap_title(self):
        listing = source('submodules/ChatListUI/Sources/Node/ChatListItem.swift')
        self.assertIn('usesMessagesList && !isPeerGroup && unreadCount.unread && !item.editing ? 1.0 : 0.0', listing)
        self.assertIn('if usesMessagesList && !isPeerGroup {\n                badgeContent = .none', listing)
        self.assertIn('statusWidth - titleIconsWidth - (usesMessagesList ? 14.0 : 0.0)', listing)
        self.assertIn('dateStatusX += -dateLayout.size.width - 4.0 - dateIconImage.size.width - (usesMessagesList ? 14.0 : 0.0)', listing)
        self.assertIn('if usesMessagesList || hasCustomDateDisclosure', listing)
        self.assertIn('messagesChatListTitle(self.presentationData.strings, theme: self.presentationData.theme)', source('submodules/ChatListUI/Sources/ChatListController.swift'))

    def test_original_icon_is_registered_for_all_surfaces(self):
        info = plistlib.loads((ROOT/'Telegram/Telegram-iOS/Info.plist').read_bytes())
        for key in ('CFBundleIcons', 'CFBundleIcons~ipad'):
            self.assertIn('MessagesIcon', info[key]['CFBundleAlternateIcons'])
        for path in ('Telegram/BUILD', 'submodules/TelegramUI/Sources/AppDelegate.swift', 'submodules/TelegramPresentationData/Sources/BananaIslandPalette.swift'):
            self.assertIn('"MessagesIcon"', source(path))
        manifest = json.loads(source('assets/branding/manifest.json'))
        sizes = {tuple(asset['size']) for asset in manifest if asset['palette'] == 'MessagesIcon'}
        for size in (29, 40, 60, 76, 120, 152, 167, 180, 1024):
            self.assertIn((size, size), sizes)
        self.assertNotIn('href=', source('assets/branding/MessagesIcon.svg'))


if __name__ == '__main__':
    unittest.main()
