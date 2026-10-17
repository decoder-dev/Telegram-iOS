"""Liquid Glass message bubbles (ported from Glassgram): settings, runtime projection, rows, rendering hook."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
ARENA = 'submodules/TelegramCore/Sources/Arena/ArenaSettings.swift'
HISTORY = 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
BACKGROUND = 'submodules/ChatMessageBackground/Sources/ChatMessageBackground.swift'
GLASS = 'submodules/ChatMessageBackground/Sources/ChatMessageGlassBubble.swift'
BUBBLE = 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift'

FIELDS = [
    ('glassBubbles', 'Bool', 'false'),
    ('glassBubbleTint', 'Int32', '25'),
    ('glassBubbleRimTop', 'Int32', '95'),
    ('glassBubbleRimSides', 'Int32', '20'),
    ('glassBubbleRimBottom', 'Int32', '55'),
]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def method(source, signature):
    start = source.index(signature)
    start = source.rfind('\n', 0, start) + 1
    return source[start:source.index('\n    }\n', start) + len('\n    }\n')]


class GlassBubbleSettings(unittest.TestCase):
    def test_fields_are_declared_defaulted_decoded_and_encoded(self):
        source = read(SETTINGS)
        for name, kind, default in FIELDS:
            self.assertIn('    public var %s: %s\n' % (name, kind), source)
            self.assertIn('        self.%s = %s\n' % (name, default), source)
            self.assertIn('self.%s = try container.decodeIfPresent(%s.self, forKey: "%s") ?? %s' % (name, kind, name, default), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_switch_is_off_by_default(self):
        self.assertIn('        self.glassBubbles = false\n', read(SETTINGS))

    def test_runtime_projection_reaches_the_chat(self):
        settings = read(SETTINGS)
        apply = settings[settings.index('public func applyForkChatAppearanceSettings('):]
        apply = apply[:apply.index('\n}\n')]
        self.assertIn('ArenaSettings.shared.setGlassBubbles(', apply)
        for name, _, _ in FIELDS:
            self.assertIn('settings.%s' % name, apply)
        arena = read(ARENA)
        self.assertIn('public func setGlassBubbles(enabled: Bool, tint: Int32, rimTop: Int32, rimSides: Int32, rimBottom: Int32)', arena)
        self.assertIn('private var glassBubblesValue = false', arena)
        self.assertIn('public var glassBubblesEnabled: Bool { return self.locked { self.glassBubblesValue } }', arena)
        # SharedAccountContext projects every settings change through the same helper.
        self.assertIn('applyForkChatAppearanceSettings(settings)', read('submodules/TelegramUI/Sources/SharedAccountContext.swift'))

    def test_open_chats_relayout_when_the_glass_settings_change(self):
        history = read(HISTORY)
        fingerprint = history[history.index('struct MessageFilterSettingsFingerprint: Equatable {'):]
        fingerprint = fingerprint[:fingerprint.index('\n        }\n')]
        self.assertIn('var glassBubbles: [Int32]', fingerprint)
        self.assertIn('glassBubbles: [settings.glassBubbles ? 1 : 0, settings.glassBubbleTint, settings.glassBubbleRimTop, settings.glassBubbleRimSides, settings.glassBubbleRimBottom]', history)


class GlassBubbleRows(unittest.TestCase):
    def test_rows_use_only_their_id_block_and_live_on_the_appearance_screen(self):
        source = read(EXTRAS)
        self.assertIn('[1900, 1901, 1902, 1903, 1904, 1905, 1906]', source)
        appearance = re.search(r'\(\.appearance, \[(.*?)\]\),\n', source).group(1)
        self.assertIn('[1900, 1901, 1902, 1903, 1904, 1905, 1906]', appearance)
        factory = source[source.index('    case .appearance:\n        entries = ['):]
        factory = factory[:factory.index('\n        ]\n')]
        ids = [int(value) for value in re.findall(r'\.(?:designHeader|designFooter|appearanceToggle|intChoice)\((19\d\d),', factory)]
        self.assertEqual(ids, [1900, 1901, 1902, 1903, 1904, 1905, 1906])
        self.assertTrue(all(1900 <= value <= 1909 for value in ids))
        self.assertIn('.appearanceToggle(1901, russian ? "Стеклянные пузыри" : "Glass bubbles", settings.glassBubbles, \\.glassBubbles)', factory)

    def test_level_rows_are_int_choices_with_both_languages(self):
        source = read(EXTRAS)
        picker = source[source.index('        openIntChoice: { id in'):]
        picker = picker[:picker.index('            default:\n                return')]
        for row, key, helper in [(1902, 'glassBubbleTint', 'forkGlassTintOptions'), (1903, 'glassBubbleRimTop', 'forkGlassRimOptions'), (1904, 'glassBubbleRimSides', 'forkGlassRimOptions'), (1905, 'glassBubbleRimBottom', 'forkGlassRimOptions')]:
            self.assertRegex(source, r'\.intChoice\(%d, russian \? "[^"]+" : "[^"]+", forkIntChoiceLabel\(%s\(russian: russian\), settings\.%s\)\)' % (row, helper, key))
            case = picker[picker.index('            case %d:' % row):]
            case = case[:case.index('keyPath = ')+len('keyPath = ')+len(key)+2]
            self.assertIn('options = %s(russian: russian)' % helper, case)
            self.assertIn('keyPath = \\.%s' % key, case)

    def test_option_sets_contain_every_default(self):
        source = read(EXTRAS)
        tint = source[source.index('private func forkGlassTintOptions('):]
        tint = tint[:tint.index('\n}\n')]
        self.assertIn('"Default (25%)", 25)', tint)
        rim = source[source.index('private func forkGlassRimOptions('):]
        rim = rim[:rim.index('\n}\n')]
        values = [int(value) for value in re.search(r'\[Int32\(0\), ([0-9, ]+)\]', rim).group(1).split(',')]
        for default in [95, 20, 55]:
            self.assertIn(default, values)

    def test_menu_fixture_knows_the_helpers(self):
        fixture = read('Tests/ClientAdditions/menu_layout.py')
        self.assertIn("'forkGlassTintOptions','forkGlassRimOptions'", fixture)


class GlassBubbleRendering(unittest.TestCase):
    def test_glass_api_is_only_touched_on_ios_26(self):
        source = read(BACKGROUND)
        update = method(source, 'private func updateGlass() {')
        guard = update.index('if #available(iOS 26.0, *), let style = self.glassStyle, let tint = self.glassTint, let shapeImage {')
        self.assertGreater(update.index('UIGlassEffect(style: .clear)'), guard)
        self.assertEqual(source.count('UIGlassEffect('), 1)
        glass = read(GLASS)
        self.assertNotIn('UIGlassEffect', glass)
        self.assertIn('if #available(iOS 26.0, *) {\n            return true', glass)

    def test_switch_off_costs_nothing(self):
        source = read(BACKGROUND)
        set_glass = method(source, 'public func setGlass(tint: UIColor?, isDark: Bool, style: ChatMessageGlassBubbleStyle?) -> Bool {')
        early = set_glass.index('if effectiveStyle == nil && self.glassStyle == nil {')
        self.assertLess(early, set_glass.index('self.updateGlass()'))
        # No per-bubble observers, and the shape/rim work is skipped unless glass is on.
        self.assertNotIn('NotificationCenter', source)
        self.assertIn('if self.glassStyle != nil || self.glassView != nil {\n            self.updateGlass()', source)
        self.assertIn('if self.glassView != nil {\n            self.layoutGlass()', source)
        bubble = read(BUBBLE)
        self.assertIn('if ArenaSettings.shared.glassBubblesEnabled && ChatMessageGlassBubbleStyle.isAvailable {', bubble)

    def test_selection_highlight_and_shape_are_preserved(self):
        source = read(BACKGROUND)
        update = method(source, 'private func updateGlass() {')
        self.assertIn('self.imageView?.isHidden = isGlass && self.currentHighlighted != true', update)
        # The glass is cut by the same mask the wallpaper backdrop uses, so grouped corners match.
        self.assertIn('shapeImage = bubbleMaskForType(type, graphics: graphics)', update)
        self.assertIn('glassView.mask = glassMaskView', update)
        layout = method(source, 'private func layoutGlass() {')
        self.assertIn('max(imageFrame.height, ChatMessageGlassBubbleStyle.minGlassHeight)', layout)
        # The component positions its own subviews; it never writes its own frame.
        for body in [update, layout]:
            self.assertNotIn('self.frame =', body)

    def test_backdrop_fill_is_hidden_under_glass(self):
        source = read(BACKGROUND)
        self.assertIn('public var hidesContentForGlass: Bool = false', source)
        self.assertEqual(source.count('backgroundContent.isHidden = self.hidesContentForGlass'), 2)
        self.assertIn('self.backgroundContent?.isHidden = self.hidesContentForGlass', source)
        bubble = read(BUBBLE)
        self.assertIn('let isGlassBubble = strongSelf.backgroundNode.setGlass(tint: glassBubbleTint, isDark: item.presentationData.theme.theme.overallDarkAppearance, style: glassBubbleStyle)', bubble)
        self.assertIn('strongSelf.backgroundWallpaperNode.hidesContentForGlass = isGlassBubble', bubble)
        self.assertIn('bubble.withWallpaper.fill : bubble.withoutWallpaper.fill).first', bubble)

    def test_rim_cache_matches_by_identity(self):
        glass = read(GLASS)
        self.assertIn('weak var shape: UIImage?', glass)
        self.assertIn('if entry.shape === shape {', glass)
        self.assertIn('init(tintPercent: Int32, rimTopPercent: Int32, rimSidesPercent: Int32, rimBottomPercent: Int32)', glass)
        self.assertIn('CGFloat(min(100, max(0, value))) / 100.0', glass)


    def test_rim_is_a_plain_tinted_image_not_a_masked_gradient(self):
        # Device logs showed a GPU-heavy day; the rim used a CAGradientLayer behind a mask view, an extra
        # offscreen pass per bubble per frame. It is now the ring image drawn as a template.
        src = read('submodules/ChatMessageBackground/Sources/ChatMessageGlassBubble.swift')
        self.assertNotIn('CAGradientLayer', src)
        self.assertNotIn('self.mask = ', src)
        self.assertIn('final class GlassRimView: UIImageView', src)
        self.assertIn('.withRenderingMode(.alwaysTemplate)', src)

if __name__ == '__main__':
    unittest.main()
