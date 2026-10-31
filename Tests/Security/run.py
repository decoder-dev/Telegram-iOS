"""BananaGram → Security: the login-code detector runs as compiled Swift, and every protection is wired where the
account would otherwise be given away."""
import pathlib
import subprocess
import tempfile
import unittest

root = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (root / path).read_text(encoding="utf-8")


def extract(source, start, end):
    begin = source.index(start)
    return source[begin:source.index(end, begin)]


class LoginCodeDetector(unittest.TestCase):
    def test_codes_are_found_in_service_messages_and_in_outgoing_texts(self):
        source = read("submodules/SettingsUI/Sources/BananaSecurityController.swift")
        detector = extract(source, "public func bananaSecurityTextContainsLoginCode(", "/// The alert shown instead of something Security forbids")
        fixture = "import Foundation\n" + detector + r'''
let service = bananaSecurityLoginCodes(inServiceText: "Login code: 52817. Do not give this code to anyone, even if they say they are from Telegram!")
precondition(service == ["52817"], "\(service)")
let russian = bananaSecurityLoginCodes(inServiceText: "Код для входа в Telegram: 401276. Никому не давайте код")
precondition(russian == ["401276"])
precondition(bananaSecurityLoginCodes(inServiceText: "New login from Chrome 1234 on 2026") .isEmpty, "4-digit runs are not codes")
precondition(bananaSecurityTextContainsLoginCode("мой код 52817", codes: service))
precondition(bananaSecurityTextContainsLoginCode("5 2 8 1 7", codes: service), "Spaced digits are caught")
precondition(bananaSecurityTextContainsLoginCode("52-817", codes: service), "Dashed digits are caught")
precondition(!bananaSecurityTextContainsLoginCode("12345", codes: service))
precondition(!bananaSecurityTextContainsLoginCode("52817", codes: []), "No recent code, nothing is held back")
print("Login code detector: service texts, spaced and dashed codes, no false positives")
'''
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "main.swift"
            path.write_text(fixture, encoding="utf-8")
            binary = pathlib.Path(directory) / "detector"
            subprocess.run(["swiftc", str(path), "-o", str(binary)], check=True, timeout=180)
            subprocess.run([str(binary)], check=True, timeout=30)


class Wiring(unittest.TestCase):
    def test_settings_default_on_and_persist(self):
        settings = read("submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift")
        for name in ["securityBlockQrLogin", "securityGuardLoginCodes", "securityBlockPhoneSharing", "securityWarnMiniApps", "securityConfirmExternalLinks", "securityFlagFakeSupport"]:
            self.assertIn("public var %s: Bool" % name, settings)
            self.assertIn("self.%s = true" % name, settings, name + " must be on by default")
            self.assertIn('forKey: "%s") ?? true' % name, settings)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), settings)

    def test_qr_device_linking_is_gated(self):
        sessions = read("submodules/SettingsUI/Sources/Privacy and Security/Recent Sessions/RecentSessionsController.swift")
        add_device = extract(sessions, "}, addDevice: {", "DeviceAccess.authorizeAccess(")
        self.assertIn("securityBlockQrLogin", add_device)
        search = read("submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift")
        link = extract(search, 'id: "devices/link-desktop"', "QrCodeScanScreen(context: context, subject: .authTransfer")
        self.assertIn("securityBlockQrLogin", link)

    def test_login_codes_phone_links_mini_apps_and_fake_support(self):
        chat = read("submodules/TelegramUI/Sources/ChatController.swift")
        send = extract(chat, "func sendMessages(_ messages: [EnqueueMessage]", "self.beginGhostReadOnInteractForSend()")
        self.assertIn("securityGuardLoginCodes", send)
        self.assertIn("TelegramEngine.EngineData.Item.Messages.TopMessage(id: serviceId)", send)
        self.assertIn("skipLoginCodeGuard: true", send)
        self.assertIn("forwardsServiceMessage", send, "Forwarding the code message itself is held back too")
        self.assertIn("presentBananaSecurityPhoneSharingBlocked()", chat)
        self.assertGreaterEqual(chat.count("securityBlockPhoneSharing"), 2, "Both the bot button and the panel button are gated")
        self.assertIn("presentFakeSupportWarningIfNeeded()", chat)
        web = read("submodules/WebUI/Sources/WebAppController.swift")
        self.assertIn("securityBlockPhoneSharing", web)
        self.assertIn("self.presentMiniAppSecurityWarningIfNeeded()", web)
        opener = read("submodules/TelegramUI/Components/OpenUserGeneratedUrl/Sources/OpenUserGeneratedUrl.swift")
        self.assertIn("securityConfirmExternalLinks && isWebsiteLinkUrl(url)", opener)

    def test_security_screen_is_reachable(self):
        extras = read("submodules/SettingsUI/Sources/ForkExtrasController.swift")
        self.assertIn(".destination(1995, BananaSecurityStrings.title, .security)", extras)
        self.assertIn("case .security: pushControllerImpl?(bananaSecurityController(context: context))", extras)
        screen = read("submodules/SettingsUI/Sources/BananaSecurityController.swift")
        self.assertIn("twoStepVerificationConfiguration()", screen)
        self.assertIn("recentSessionsController(context: context", screen)

    def test_fake_support_predicate(self):
        screen = read("submodules/SettingsUI/Sources/BananaSecurityController.swift")
        predicate = extract(screen, "public func bananaSecurityLooksLikeFakeSupport(", "/// A message text holding a login code")
        self.assertIn("!peer.isVerified", predicate)
        self.assertIn("777000", predicate, "Telegram's own service account is never flagged")
        for marker in ['"telegram"', '"безопасност"', '"support"', '"поддержк"']:
            self.assertIn(marker, predicate)


if __name__ == "__main__":
    unittest.main()
