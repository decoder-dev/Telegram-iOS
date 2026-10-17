"""Source-text checks for the MadGram ports: Message Shot and the Power Saving preset."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


SETTINGS = "submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift"
CONTROLLER = "submodules/SettingsUI/Sources/ForkExtrasController.swift"
SHOT = "submodules/TelegramUI/Components/MessageShotScreen/Sources/MessageShotScreen.swift"


class Settings(unittest.TestCase):
    def test_fields_declared_defaulted_decoded_encoded(self):
        source = read(SETTINGS)
        for key, default in [("messageShot", "true"), ("powerSaving", "false")]:
            self.assertIn(f"    public var {key}: Bool\n", source)
            self.assertIn(f"        self.{key} = {default}\n", source)
            self.assertIn(f'self.{key} = try container.decodeIfPresent(Bool.self, forKey: "{key}") ?? {default}', source)
            self.assertIn(f'try container.encode(self.{key}, forKey: "{key}")', source)

    def test_rows_use_reserved_ids_and_are_grouped(self):
        source = read(CONTROLLER)
        ids = [int(i) for i in re.findall(r"\.(?:appearanceToggle|designHeader|designFooter)\((19\d\d),", source)]
        ids = [i for i in ids if 1910 <= i <= 1929]
        self.assertEqual(sorted(ids), [1910, 1911, 1912, 1913, 1914])
        self.assertIn(r"settings.messageShot, \.messageShot)", source)
        self.assertIn(r"settings.powerSaving, \.powerSaving)", source)
        self.assertIn("[1910, 1911]", source)
        self.assertIn("[1912, 1913, 1914]", source)


class PowerSaving(unittest.TestCase):
    def test_maps_onto_existing_energy_profile(self):
        source = read("submodules/TelegramUI/Sources/SharedAccountContext.swift")
        self.assertGreaterEqual(source.count("settings.powerSaving"), 1)
        self.assertGreaterEqual(source.count("strongSelf.immediateForkExtrasSettings.powerSaving"), 2)
        self.assertIn("EnergyUsageSettings.powerSavingDefault", source)


class MessageShot(unittest.TestCase):
    def test_respects_copy_protection_secret_chats_and_view_once(self):
        source = read(SHOT)
        gate = source.split("public func messageShotIsAllowed", 1)[1].split("private func", 1)[0]
        for needle in ["chatCopyProtected", "isCopyProtected()", "Namespaces.Peer.SecretChat", "containsSecretMedia"]:
            self.assertIn(needle, gate)
        # The screen itself refuses to exist for a protected selection.
        self.assertIn("init?(context: AccountContext", source)
        self.assertIn("guard messageShotIsAllowed(", source)

    def test_renders_through_chat_message_preview_items_and_keeps_spoilers(self):
        source = read(SHOT)
        self.assertIn("makeChatMessagePreviewItem(", source)
        self.assertNotIn("MediaSpoilerMessageAttribute", source)
        self.assertNotIn("Spoiler", source)

    def test_menu_entry_is_gated_by_setting_and_protection(self):
        source = read("submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift")
        entry = source.split("if extras.messageShot", 1)[1].split("if extras.selectFromAuthor", 1)[0]
        self.assertIn("!chatPresentationInterfaceState.copyProtectionEnabled", entry)
        self.assertIn("!isCopyProtected", entry)
        self.assertIn("messageShotIsAllowed(", entry)
        self.assertIn("MessageShotScreen(", entry)
        self.assertIn('"//submodules/TelegramUI/Components/MessageShotScreen"', read("submodules/TelegramUI/BUILD"))


if __name__ == "__main__":
    unittest.main()
