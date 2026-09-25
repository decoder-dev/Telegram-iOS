"""Exercise production VLESS feedback and archive language selection on macOS."""
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (root / path).read_text(encoding="utf-8")

profile = read("submodules/TelegramVLESS/Sources/TelegramVLESS/VlessProfile.swift")
feedback = read("submodules/SettingsUI/Sources/Data and Storage/VlessEditorInfo.swift")
feedback = feedback.replace("import TelegramVLESS\n", "").replace("import TelegramUIPreferences\n", "")
language = read("submodules/TelegramUIPreferences/Sources/ForkPresentationLanguage.swift")
archive = read("submodules/ChatListUI/Sources/ArchiveLockLocalizedString.swift")
archive = archive.replace("import AppBundle\n", "").replace("import TelegramUIPreferences\n", "")

tests = r'''
// Only the app-bundle accessor is a fixture; all localization and parsing logic is production code.
func getAppBundle() -> Bundle { Bundle.main }
let valid = "vless://00000000-0000-0000-0000-000000000001@example.com:443?security=tls&type=ws"
for language in ["ru", "en", "de", "uk"] {
    ForkPresentationLanguage.languageCode = language
    let russian = language == "ru" || language == "uk"
    let empty = vlessEditorInfo(" \n ")
    precondition(!empty.isError && !empty.text.isEmpty)
    let success = vlessEditorInfo(valid)
    precondition(!success.isError && success.text.contains("example.com:443"))
    for invalid in ["not a proxy", valid + "&type=tcp", valid.replacingOccurrences(of: ":443", with: ":65536"), String(repeating: "x", count: 8193)] {
        let result = vlessEditorInfo(invalid)
        precondition(result.isError)
        precondition(result.text.hasPrefix(russian ? "Ошибка: " : "Error: "))
        precondition(!result.text.contains("00000000-0000-0000-0000-000000000001"))
    }
    precondition(ArchiveLockLocalizedString.lockArchive.contains(russian ? "Избранное" : "Saved Messages"))
    precondition(ArchiveLockLocalizedString.keepArchivedPolicy.contains(russian ? "автоматически" : "automatic"))
    let insecure = vlessEditorInfo(valid + "&allowInsecure=1")
    precondition(!insecure.isError)
    precondition(insecure.text.contains(russian ? "Проверка сертификата отключена" : "Certificate verification is disabled"))
}
print("VLESS feedback, invalid/oversize links, certificate warning and app-language consistency: passed")
'''

with tempfile.TemporaryDirectory(prefix="telegram-menu-presentation-") as tmp:
    package = pathlib.Path(tmp)
    source = package / "Sources/MenuPresentation"
    source.mkdir(parents=True)
    dependency = json.dumps(str(root / "submodules/SSignalKit"))
    (package / "Package.swift").write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "MenuPresentation", platforms: [.macOS(.v10_15)], dependencies: [.package(path: PATH)], targets: [.executableTarget(name: "MenuPresentation", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")])])
'''.replace("PATH", dependency), encoding="utf-8")
    (source / "main.swift").write_text(profile + feedback + language + archive + tests, encoding="utf-8")
    subprocess.run(["swift", "run", "--package-path", tmp, "MenuPresentation"], check=True)
