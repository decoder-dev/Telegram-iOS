"""Stabilization audit (docs/quality/full_app_audit.md): the defects found and fixed in that pass, pinned so they don't
come back. Source-text checks; Swift builds in CI."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DURESS = 'submodules/TelegramUIPreferences/Sources/DuressPasscode.swift'
STORE = 'submodules/TelegramUIPreferences/Sources/MessageSavingStore.swift'
SHARED = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
SIDECAR = 'submodules/WebProxyTransport/Sources/WebProxySidecar.swift'
DOH = 'submodules/TelegramCore/Sources/State/ManagedAutomaticMtProxy.swift'
ARCHIVE_KEYCHAIN = 'submodules/TelegramUIPreferences/Sources/ArchivePasswordKeychain.swift'
OPEN_URL = 'submodules/TelegramUI/Sources/OpenUrl.swift'


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def function_body(source, signature):
    start = source.index(signature)
    depth = 0
    for index in range(source.index('{', start), len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError('unterminated ' + signature)


class DuressEraseAll(unittest.TestCase):
    def test_erase_all_also_erases_saved_messages_before_the_accounts_go(self):
        source = read(DURESS)
        body = function_body(source, 'public func performDuressPasscodeAction(')
        erase = body.index('if action == .eraseAll {\n            // Saved deleted and edited messages')
        self.assertLess(erase, body.index('MessageSavingStore.eraseEverything()'))
        self.assertLess(body.index('MessageSavingStore.eraseEverything()'), body.index('logoutFromAccount('))

    def test_erase_everything_clears_records_media_and_staging(self):
        body = function_body(read(STORE), 'public static func eraseEverything()')
        for needle in ['self.memory = []', 'self.loadFailed = false', 'self.storeGeneration += 1', 'persistNow()',
                       'MessageSavingBridge.savedAttachmentsDirectory', 'MessageSavingNotificationStaging.removeAll(rootPath: rootPath)']:
            self.assertIn(needle, body)
        # The generation is bumped before the write, so a coalesced older snapshot can't land after it.
        self.assertLess(body.index('self.storeGeneration += 1'), body.index('persistNow()'))


class LaunchPushKeepsPersistedMirrors(unittest.TestCase):
    MIRRORS = [
        'ForkKeepBannedChatsSettings.enabled = settings.keepBannedChats',
        'ForkRemovePingsSettings.enabled = settings.removePings',
        'ForkGhostScheduleSettings.enabled = settings.ghostScheduleMessages',
        'ForkGhostSilentSendSettings.enabled = settings.ghostSendWithoutSound',
    ]

    def test_mirrors_are_written_only_with_the_users_settings(self):
        source = read(SHARED)
        body = function_body(source, 'private static func pushForkExtrasToEngineStatics(')
        guarded = body[body.index('        if applyGhost {\n            ForkKeepBannedChatsSettings'):]
        guarded = guarded[:guarded.index('\n        }\n')]
        for line in self.MIRRORS:
            self.assertEqual(body.count(line), 1, line)
            self.assertIn(line, guarded)
        self.assertIn('Self.pushForkExtrasToEngineStatics(settings, applyAppearance: false, applyGhost: false)', source)
        self.assertIn('SharedAccountContextImpl.pushForkExtrasToEngineStatics(settings)\n', source)


class WebProxySidecarListener(unittest.TestCase):
    def test_mtproxy_listener_is_loopback_only(self):
        source = read(SIDECAR)
        self.assertNotIn('try NWListener(using: .tcp, on: ephemeralPort)', source)
        listener = source.index('let listener = try NWListener(using: listenerParameters)')
        self.assertLess(source.index('listenerParameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)'), listener)


class DoHProxyListFetch(unittest.TestCase):
    def test_body_is_read_only_after_the_handler_finished(self):
        body = function_body(read(DOH), 'private func fetchAutomaticMtProxyListViaDoHTXT(')
        self.assertIn('guard semaphore.wait(timeout: .now() + 9.0) == .success else {\n                    task.cancel()\n                    continue\n                }', body)
        self.assertNotIn('_ = semaphore.wait(', body)


class NoDuressTell(unittest.TestCase):
    def test_pbkdf2_timing_is_not_logged_in_release(self):
        body = function_body(read(ARCHIVE_KEYCHAIN), 'private func pbkdf2HexHash(password: String, salt: Data,')
        self.assertNotIn('NSLog(', body)


class FilterListImport(unittest.TestCase):
    def test_fetch_uses_an_ephemeral_session_that_is_invalidated(self):
        source = read(OPEN_URL)
        self.assertIn('let session = URLSession(configuration: .ephemeral)\n    let task = session.dataTask(with: request) { data, _, _ in', source)
        self.assertIn('    task.resume()\n    session.finishTasksAndInvalidate()\n}', source)
        self.assertIsNone(re.search(r'URLSession\.shared\.dataTask\(with: request\) \{ data, _, _ in\n        Queue\.mainQueue\(\)\.async \{\n            statusController\.dismiss\(\)', source))


if __name__ == '__main__':
    unittest.main()
