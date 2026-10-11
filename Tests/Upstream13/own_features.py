"""Regression contracts for fork behavior across the upstream 13 migration."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding='utf-8')

class ForkIntegration(unittest.TestCase):
    def test_siri_helpers_are_unique_and_keep_logged_out_account_guard(self):
        source = read('Telegram/SiriIntents/IntentHandler.swift')
        for name in ['firstValueOrNil', 'completing']:
            self.assertEqual(len(re.findall(r'\bfunc ' + name + r'<', source)), 1, name)
        guard = source.split('func usableAccountRecordId(', 1)[1].split('func firstValueOrNil', 1)[0]
        self.assertIn('if case .loggedOut', guard)
        self.assertIn('return nil', guard)
        self.assertIn('self.accountPromise.set(firstValueOrNil(account))', source)

    def test_legacy_hash_metadata_is_not_cleaned_before_migration(self):
        source = read('submodules/TelegramCore/Sources/AccountManager/AccountManagerImpl.swift')
        body = source.split('private func cleanPasscodeMetadataIfNeeded()', 1)[1].split('private func syncAtomicStateToFile()', 1)[0]
        self.assertRegex(body, r'case \.numericalPassword, \.plaintextPassword, \.numericalPasswordHash, \.plaintextPasswordHash:\s*return')

    def test_inline_keyboard_uses_new_api_type_and_resend_is_unique(self):
        source = read('submodules/TelegramCore/Sources/ApiUtils/ReplyMarkupMessageAttribute.swift')
        body = source.split('init(apiRow: Api.KeyboardInlineButtonRow)', 1)[1].split('init(apiRow: Api.KeyboardButtonRow)', 1)[0]
        self.assertIn('ReplyMarkupButton(apiInlineButton: $0)', body)
        enqueue = read('submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift')
        self.assertEqual(enqueue.count('func resentMessageRequestedAttribute('), 1)

    def test_camera_bridge_handles_the_new_collage_result(self):
        source = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        bridge = source.split('public func legacyCameraCapturedMediaSignals(', 1)[1].split('public func makeMediaPickerScreen(', 1)[0]
        self.assertIn('case .draft, .videoCollage, .collage:', bridge)
        self.assertIn('return .complete()', bridge)

    def test_retired_fork_modules_are_not_resurrected_by_upstream(self):
        for path in ['submodules/LegacyComponents/Sources/FLAnimatedImage.m',
                     'submodules/LegacyComponents/Sources/TGPassportAttachMenu.m',
                     'submodules/LegacyComponents/Sources/TGPhotoToolbarView.m',
                     'submodules/LegacyComponents/Sources/TGToolbarButton.m',
                     'submodules/TelegramUI/Components/LegacyCamera/Sources/LegacyCamera.swift',
                     'submodules/openssl/BUILD']:
            self.assertFalse((ROOT / path).exists(), path)
        self.assertTrue((ROOT / 'submodules/LegacyMediaPickerUI/Sources/MediaPickerPhotoToolbarView.swift').is_file())
        self.assertTrue((ROOT / 'submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift').is_file())

    def test_secret_screenshot_policy_survives_new_capture_manager(self):
        source = read('submodules/TelegramUI/Sources/ChatController.swift')
        method = source.split('private func setupScreenCaptureDetectionIfNeeded()', 1)[1].split('override public func viewDidAppear', 1)[0]
        self.assertIn('ForkSecretScreenshotSettings.allow', method)
        self.assertIn('!ForkSecretScreenshotSettings.allow', method)
        self.assertIn('self.screenCaptureManager = nil', method)

    def test_bot_header_obeys_visibility_setting(self):
        source = read('submodules/TelegramUI/Sources/ChatControllerNode.swift')
        self.assertRegex(source, r'if !hideTopPanels, !ForkMessageVisibility.hideBotAutomation, let managingBotPanelNode')

    def test_legacy_passcode_migration_does_not_reenter_file_lock(self):
        source = read('submodules/PasscodeCore/Sources/Passcode.swift')
        verified = source.split('public func migrateVerifiedLegacy(', 1)[1].split('private func wrap(', 1)[0]
        self.assertIn('try self.serialized', verified)
        self.assertIn('try self.migrateLegacyLocked(', verified)
        self.assertNotIn('try self.migrateLegacy(', verified)
        locked = source.split('private func migrateLegacyLocked(', 1)[1].split('/// Authenticate', 1)[0]
        self.assertNotIn('self.serialized', locked)
        self.assertIn('try self.save(record)', locked)

    def test_voice_recording_uses_its_own_preference(self):
        source = read('submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift')
        self.assertIn('pauseMusicOnRecording: self.context.sharedContext.currentMediaInputSettings.with({ $0.pauseMusicOnVoiceRecording })', source)

    def test_schema_230_coverage(self):
        api = '\n'.join(p.read_text(encoding='utf-8') for p in (ROOT / 'submodules/TelegramApi/Sources').glob('Api*.swift'))
        ids = {int(v) & 0xffffffff for v in re.findall(r'appendInt32\((-?\d+)\)', api)}
        schema = read('build-system/SwiftTL/api-230.tl')
        self.assertIn('// LAYER 230', schema)
        for line in schema.splitlines():
            match = re.match(r'([\w.]+)#([0-9a-f]+)\b', line)
            if match and '{X:Type}' not in line and match[1] not in {'true', 'error', 'null', 'vector'}:
                self.assertIn(int(match[2], 16), ids, match[1])

if __name__ == '__main__':
    unittest.main()
