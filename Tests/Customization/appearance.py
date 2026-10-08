"""Round-trip production appearance preferences, including old installations."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift").read_text(encoding="utf-8")
source = source[:source.index("/// Last opened chat-list folder.")]
for module in ("TelegramCore", "SwiftSignalKit", "Postbox"):
    source = source.replace(f"import {module}\n", "")
fixture = r'''
import Foundation
public struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
    public var stringValue: String
    public var intValue: Int? { nil }
    public init(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { return nil }
    public init(stringLiteral value: String) { self.stringValue = value }
}
public enum MessageSavingBridge { public static let defaultDeletedMark = "deleted" }
enum ForkPresentationLanguage { static let prefersRussianStrings = false }
'''
tests = r'''
let decoder = JSONDecoder()
let encoder = JSONEncoder()
let old = try decoder.decode(ForkExtrasSettings.self, from: Data("{}".utf8))
precondition(!old.bottomChatFoldersEnabled, "Existing installations must keep folders at the top")
let paths: [WritableKeyPath<ForkExtrasSettings, Bool>] = [
    \.bottomChatFoldersEnabled, \.avatarGlowEnabled, \.reactionGlowEnabled,
    \.showContactsTab, \.wideTabBar, \.integratedTabSearch, \.tabSearchOnLeft
]
for path in paths {
    for enabled in [true, false, true, false] {
        var settings = old
        settings[keyPath: path] = enabled
        let loaded = try decoder.decode(ForkExtrasSettings.self, from: encoder.encode(settings))
        precondition(loaded == settings, "Appearance choice lost during persistence")
        precondition(loaded[keyPath: path] == enabled)
        if enabled != old[keyPath: path] { precondition(loaded != old) }
    }
}
print("Appearance preferences: old defaults, toggling, equality and persistence passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "main.swift"
    path.write_text(fixture + source + tests, encoding="utf-8")
    subprocess.run(["swift", "-swift-version", "5", str(path)], check=True, timeout=120)
