"""Exercise production settings under concurrent updates and reentrant observers."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "submodules/TelegramCore/Sources/Arena/ArenaSettings.swift").read_text(encoding="utf-8")
tests = r"""
let suite = "test.shadow-ban." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let settings = ArenaSettings(defaults: defaults)
DispatchQueue.concurrentPerform(iterations: 100) { index in
    settings.setShadowBanned(true, peerId: Int64(index))
    settings.setShadowBanRevealed(true, chatPeerId: Int64(index))
}
precondition(Set(settings.shadowBanSnapshot.bannedPeerIds) == Set((0..<100).map(Int64.init)))
precondition(Set(settings.shadowBanSnapshot.revealedChatIds) == Set((0..<100).map(Int64.init)))
DispatchQueue.concurrentPerform(iterations: 100) { index in
    settings.setShadowBanned(false, peerId: Int64(index))
    settings.setShadowBanRevealed(false, chatPeerId: Int64(index))
}
precondition(!settings.hasShadowBans && settings.shadowBanSnapshot.revealedChatIds.isEmpty)
let observer = NotificationCenter.default.addObserver(forName: ArenaSettings.shadowBanDidChangeNotification, object: nil, queue: nil) { _ in
    if settings.isShadowBanned(999) { settings.setShadowBanned(false, peerId: 999) }
}
settings.setShadowBanned(true, peerId: 999)
NotificationCenter.default.removeObserver(observer)
precondition(!settings.isShadowBanned(999))
// Rendering must follow the in-process projection, not stale app-group keys.
defaults.set(true, forKey: "avatarGlow")
defaults.set(true, forKey: "reactionGlow")
var glowStates: [(Bool, Bool)] = []
let glowObserver = NotificationCenter.default.addObserver(forName: ArenaSettings.didChangeNotification, object: nil, queue: nil) { _ in
    glowStates.append((settings.avatarGlow, settings.reactionGlow))
}
settings.avatarGlow = true
settings.reactionGlow = true
settings.avatarGlow = false
settings.reactionGlow = false
precondition(!settings.avatarGlow && !settings.reactionGlow)
precondition(glowStates.count == 4)
precondition(glowStates[2].0 == false && glowStates[2].1 == true)
precondition(glowStates[3].0 == false && glowStates[3].1 == false)
settings.avatarGlow = false
precondition(glowStates.count == 4, "Unchanged settings must not invalidate every avatar")
NotificationCenter.default.removeObserver(glowObserver)
print("Concurrent shadow-ban updates and reentrant notifications passed")
"""
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "main.swift"
    path.write_text(source + tests, encoding="utf-8")
    subprocess.run(["swift", "-swift-version", "5", str(path)], check=True, timeout=120)
