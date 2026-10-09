"""Structural checks for the Archive lock entry points. A merge once dropped these silently."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (root / path).read_text(encoding="utf-8")


chat_list = read("submodules/ChatListUI/Sources/ChatListController.swift")
group_selected = chat_list[chat_list.index("mainContainerNode.groupSelected = {"):chat_list.index("mainContainerNode.updatePeerGrouping = {")]
assert "ensureArchiveUnlocked(" in group_selected, "Tapping the Archive row must ask for the password"
preview = chat_list[chat_list.index("case let .groupReference(groupReference):"):]
preview = preview[:preview.index("case let .peer(peerData):")]
assert "ensureArchiveUnlocked(" in preview, "The Archive long-press preview must ask for the password"
assert "ArchiveLockSession.shared.relockedSignal" in chat_list, "An open Archive list must close on relock"
assert chat_list.count("markArchiveLockProtected(") >= 1, "Archive settings opened from the Archive must close on relock"

helpers = read("submodules/ChatListUI/Sources/ArchiveLockHelpers.swift")
assert "presentLostArchivePasswordRecovery(" in helpers, "A password no copy can verify must be recoverable"
assert "biometricsDomainState" in helpers, "Face ID unlock must reject a changed biometric enrollment"

keychain = read("submodules/TelegramUIPreferences/Sources/ArchivePasswordKeychain.swift")
assert re.search(r"let elapsed = max\(0,", keychain), "A clock moved backwards must not extend the cooldown"

service = read("Telegram/NotificationService/Sources/NotificationService.swift")
assert "stagedContent.redactLockedArchive(" in service, "Unredacted text must never be staged before the Archive check"

print("Archive lock entry points, recovery, biometrics, cooldown clamp and notification staging: passed")
