"""Share links (tg://msg_url, tg://msg, t.me/share) ask before they open a prefilled message."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


class ShareLinkGuard(unittest.TestCase):
    def test_setting_is_on_by_default_and_persisted(self):
        s = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        self.assertIn('public var confirmShareLinks: Bool', s)
        self.assertIn('self.confirmShareLinks = true', s)
        self.assertIn('decodeIfPresent(Bool.self, forKey: "confirmShareLinks") ?? true', s)
        self.assertIn('try container.encode(self.confirmShareLinks, forKey: "confirmShareLinks")', s)

    def test_row_is_listed_in_the_messages_group(self):
        c = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('.appearanceToggle(1944,', c)
        self.assertIn('\\.confirmShareLinks)', c)
        self.assertIn('[1944],', c)

    def test_share_case_asks_once_per_confirmed_link(self):
        o = read('submodules/TelegramUI/Sources/OpenResolvedUrl.swift')
        share = o.split('case let .share(url, text, to):', 1)[1]
        ask = share.index('immediateForkExtrasSettings.confirmShareLinks, !ForkShareLinkGuard.consumeApproval(shareKey)')
        self.assertLess(ask, share.index('let continueWithPeer'))
        self.assertIn('ForkShareLinkGuard.approve(shareKey)', share)
        self.assertIn('openResolvedUrlImpl(resolvedUrl,', share)

    def test_guard_shows_text_url_and_recipient(self):
        g = read('submodules/TelegramUI/Sources/ForkShareLinkGuard.swift')
        for needle in ('Кому:', 'Ссылка:', 'Текст:', 'To:', 'Link:', 'Text:', 'let limit = 400'):
            self.assertIn(needle, g)


if __name__ == '__main__':
    unittest.main()
