"""Fault-injection check for the production settings-screen migration commit."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/SettingsUI/Sources/ArchiveSettingsController.swift').read_text(encoding='utf-8')
start = source.index('        if archiveSettings.legacyLockPasswordHash != nil')
end = source.index('\n\n        let controllerState', start)
fixtures = '''
import Foundation
struct Settings {
    var legacyLockPasswordHash: String?
    var isPasswordConfigured: Bool
    func clearingLegacyPasswordHash() -> Settings {
        var value = self; value.legacyLockPasswordHash = nil; return value
    }
    func withUpdatedIsPasswordConfigured(_ configured: Bool) -> Settings {
        var value = self; value.isPasswordConfigured = configured; return value
    }
}
final class Engine {
    var settings: Settings
    init(_ settings: Settings) { self.settings = settings }
}
struct Account { let peerId = 1 }
struct Context { let account = Account(); let engine: Engine }
struct ResultSignal { func startStandalone() -> Int { 0 } }
func updateChatArchiveSettings(engine: Engine, _ f: (Settings) -> Settings) -> ResultSignal {
    engine.settings = f(engine.settings); return ResultSignal()
}
enum ArchivePasswordKeychain {
    static var stored = false
    static func hasPassword(peerId: Int) -> Bool { stored }
}
func applySettingsMigration(context: Context) {
    let archiveSettings = context.engine.settings
'''
tests = '''
}
for alreadyConfigured in [false, true] {
    let engine = Engine(Settings(legacyLockPasswordHash: "legacy", isPasswordConfigured: alreadyConfigured))
    ArchivePasswordKeychain.stored = false
    applySettingsMigration(context: Context(engine: engine))
    precondition(engine.settings.legacyLockPasswordHash == "legacy", "Lost only credential after failed migration")
    precondition(engine.settings.isPasswordConfigured == alreadyConfigured)
    ArchivePasswordKeychain.stored = true
    applySettingsMigration(context: Context(engine: engine))
    precondition(engine.settings.legacyLockPasswordHash == nil)
    precondition(engine.settings.isPasswordConfigured, "Notification protection was not mirrored")
}
print("Archive migration preserves credentials on failure and mirrors protection on success: passed")
'''
with tempfile.TemporaryDirectory(prefix='archive-migration-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixtures + source[start:end] + tests, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
