"""Record source evidence and validate the imported design handoff."""

import csv
import json
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
BASELINE = json.loads((ROOT / "research/baseline.json").read_text())

# Each entry names a real declaration to look up, rather than trusting the handoff's globs.
ANCHORS = {
    1: ("AuthorizationSequencePhoneEntryController.swift", "AuthorizationSequencePhoneEntryController"),
    2: ("ChatListUI/Sources/ChatListController.swift", "ChatListControllerImpl"),
    3: ("TelegramUI/Sources/ChatController.swift", "ChatControllerImpl"),
    4: ("ChatControllerOpenAttachmentMenu.swift", "presentAttachmentMenu"),
    5: ("ChatListUI/Sources/ChatListController.swift", "ChatListControllerImpl"),
    6: ("PeerInfoScreen/Sources/PeerInfoScreen.swift", "PeerInfoScreenImpl"),
    7: ("TelegramCallsUI/Sources/CallController.swift", "CallController"),
    8: ("MediaPickerScreen.swift", "MediaPickerScreenImpl"),
    9: ("StoryContainerScreen/Sources/StoryContainerScreen.swift", "StoryContainerScreen"),
    10: ("ThemeSettingsController.swift", "themeSettingsController"),
    11: ("ProxyServerSettingsController.swift", "proxyServerSettingsController"),
    12: ("ChatListUI/Sources/ChatListController.swift", "ChatListControllerImpl"),
    13: ("AuthorizationSequenceCodeEntryController.swift", "AuthorizationSequenceCodeEntryController"),
    14: ("ChatListSearchContainerNode.swift", "ChatListSearchContainerNode"),
    15: ("ChatListUI/Sources/ChatListController.swift", "ChatListControllerImpl"),
    16: ("TelegramUI/Sources/ChatController.swift", "ChatControllerImpl"),
    17: ("TelegramUI/Sources/ChatController.swift", "ChatControllerImpl"),
    18: ("ChatControllerOpenMessageReactionContextMenu.swift", "openMessageReactionContextMenu"),
    19: ("ChatEntityKeyboardInputNode.swift", "ChatEntityKeyboardInputNode"),
    20: ("GalleryUI/Sources/GalleryController.swift", "GalleryController"),
    21: ("ChatControllerMediaRecording.swift", "ChatControllerImpl"),
    22: ("PeerInfoScreen/Sources/PeerInfoScreen.swift", "PeerInfoScreenImpl"),
    23: ("CallListController.swift", "CallListController"),
    24: ("PeerInfoScreen/Sources/PeerInfoScreen.swift", "PeerInfoScreenImpl"),
    25: ("ProxyListSettingsController.swift", "proxySettingsController"),
    26: ("ArchiveLockHelpers.swift", "setAccountHidden"),
    27: ("ArchiveLockHelpers.swift", "setArchivePassword"),
    28: ("AccountOrderController.swift", "accountOrderController"),
    29: ("WebAppController.swift", "WebAppController"),
    30: ("ComposePollScreen.swift", "ComposePollScreen"),
    31: ("PremiumIntroScreen.swift", "PremiumIntroScreen"),
    32: ("StorageUsageScreen.swift", "StorageUsageScreen"),
    33: ("NotificationsAndSoundsController.swift", "notificationsAndSoundsController"),
    34: ("TelegramCallsUI/Sources/CallController.swift", "CallController"),
    35: ("PeerInfoScreen/Sources/PeerInfoScreen.swift", "PeerInfoScreenImpl"),
    36: ("ComposeController.swift", "ComposeControllerImpl"),
    37: ("ForkExtrasController.swift", "forkExtrasController"),
    38: ("ForkExtrasController.swift", "ForkExtrasControllerFocus"),
    39: ("ForkExtrasController.swift", "ForkExtrasControllerFocus"),
    40: ("ForkExtrasController.swift", "ForkExtrasControllerFocus"),
    41: ("ForkExtrasController.swift", "ForkExtrasControllerFocus"),
    42: ("ArchiveSettingsController.swift", "archiveSettingsController"),
    43: ("ArchiveLockHelpers.swift", "setArchiveLockTargets"),
    44: ("ProxyServerSettingsController.swift", "proxyServerSettingsController"),
    45: ("ProxyListSettingsController.swift", "proxySettingsController"),
    46: ("PrivacyAndSecurityController.swift", "privacyAndSecurityController"),
    47: ("RecentSessionsController.swift", "recentSessionsController"),
    48: ("BubbleSettingsController.swift", "BubbleSettingsController"),
    49: ("MediaEditorScreen.swift", "MediaEditorScreenImpl"),
    50: ("ChatControllerOpenMessageContextMenu.swift", "ChatControllerImpl"),
    51: ("ForkExtrasController.swift", "forkExtrasController"),
    52: ("ChatListSearchContainerNode.swift", "ChatListSearchContainerNode"),
    53: ("ArchiveLockHelpers.swift", "setArchiveLockTargets"),
    54: ("ThemePreviewController.swift", "ThemePreviewController"),
}


def write_csv(name, rows, fields):
    with (ROOT / name).open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def audit():
    catalog = json.loads((ROOT / "reference/METADATA/screen_catalog.json").read_text())
    tracked = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASELINE["source_commit"]], cwd=REPO, text=True).splitlines()
    sources = [path for path in tracked if path.endswith(".swift")]
    mappings, inventory, checks = [], [], []
    progress = json.loads((ROOT / 'research/progress.json').read_text()) if (ROOT / 'research/progress.json').exists() else {}
    for screen in catalog:
        screen_id = screen["id"]
        suffix, symbol = ANCHORS[int(screen_id[:2])]
        matches = [path for path in sources if path.endswith(suffix)]
        path = matches[0] if len(matches) == 1 else ""
        line = 0
        if path:
            source = subprocess.check_output(["git", "show", f'{BASELINE["source_commit"]}:{path}'], cwd=REPO, text=True)
            declaration = re.compile(r"\b(?:class|struct|enum|func|extension)\s+" + re.escape(symbol) + r"\b")
            line = next((i for i, text in enumerate(source.splitlines(), 1) if declaration.search(text)), 0)
        mappings.append(dict(screen_id=screen_id, file=path, symbol=symbol, line=line or "", source_commit=BASELINE["source_commit"], evidence="DECLARATION_FOUND" if line else "CANDIDATE", runtime="NOT_RUN"))
        inventory.append(dict(screen_id=screen_id, title=screen["title"], design=progress.get(screen_id,'IMPORTED_REVIEW_PENDING'), light_svg=f"reference/FIGMA_EDITABLE_SVG/light/{screen_id}.svg", dark_svg=f"reference/FIGMA_EDITABLE_SVG/dark/{screen_id}.svg", prototype=f"prototype/index.html#screen={screen_id}", native="NOT_RUN", approval="PENDING"))
        for theme in ["light", "dark"]:
            svg = ROOT / f"reference/FIGMA_EDITABLE_SVG/{theme}/{screen_id}.svg"
            doc = ET.parse(svg).getroot()
            png = ROOT / f"reference/PNG_3X/{theme}/{screen_id}.png"
            width, height = struct.unpack(">II", png.read_bytes()[16:24])
            checks.append(dict(check=f"assets:{theme}:{screen_id}", status="PASS" if doc.attrib.get("viewBox") == "0 0 393 852" and (width, height) == (1179, 2556) else "FAIL", scope="file integrity and dimensions only"))
    write_csv("research/CODE_TO_SCREEN_MAP.csv", mappings, list(mappings[0]))
    write_csv("research/SCREEN_INVENTORY.csv", inventory, list(inventory[0]))
    ids = {screen["id"] for screen in catalog}
    issues = []
    for path in sorted((ROOT / "reference/METADATA/hotspots").glob("*.json")):
        for index, hit in enumerate(json.loads(path.read_text())):
            reason = []
            if not hit["to"].startswith("@") and hit["to"] not in ids:
                reason.append("missing destination")
            if hit["x"] < 0 or hit["y"] < 0 or hit["x"] + hit["w"] > 393 or hit["y"] + hit["h"] > 852:
                reason.append("outside frame")
            if min(hit["w"], hit["h"]) < 44:
                reason.append("target below 44pt")
            if reason:
                issues.append(dict(screen=path.stem, index=index, label=hit["label"], issues=reason))
    report = dict(asset_checks=checks, inherited_hotspot_issues=issues, mapped_declarations=sum(row["evidence"] == "DECLARATION_FOUND" for row in mappings), total_scenes=len(catalog), native="NOT_RUN", figma="BLOCKED", visual="NOT_REVIEWED")
    (ROOT / "qa/import-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"scenes":len(catalog), "asset_checks":len(checks), "asset_failures":sum(c["status"] == "FAIL" for c in checks), "mapped_declarations":report["mapped_declarations"], "hotspot_issues":len(issues)}, ensure_ascii=False))


if __name__ == "__main__":
    audit()
