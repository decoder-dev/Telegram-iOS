"""Regression contracts for fork behavior across the upstream 13 migration."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding='utf-8')

class ForkIntegration(unittest.TestCase):
    def test_scene_handlers_bind_application_for_fork_background_tasks(self):
        source = read('submodules/TelegramUI/Sources/AppDelegate.swift')
        for method, end in [('func handleDidEnterBackground()', 'func applicationDidReceiveMemoryWarning'),
                            ('func handleWillEnterForeground()', 'self.runForegroundTasks()')]:
            body = source.split(method, 1)[1].split(end, 1)[0]
            self.assertIn('let application = UIApplication.shared', body)
            self.assertIn('BackgroundKeepAlive(application: application)', body)

    def test_context_menu_uses_shared_edit_policy_and_web_conversion_is_unique(self):
        source = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('import ChatMessageItemCommon', source)
        self.assertNotIn('private func canEditMessage(accountPeerId:', source)
        self.assertNotIn('canPerformEditingActions(', source)
        shared = read('submodules/TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageEditing.swift')
        self.assertIn('public func canEditMessage(accountPeerId:', shared)
        self.assertIn('limits.maxMessageEditingInterval', shared)
        self.assertIn('peer.hasPermission(.pinMessages)', shared)
        urls = read('submodules/TelegramUI/Sources/OpenUrl.swift')
        self.assertEqual(urls.count('case "webproxy":'), 1)
        self.assertIn('params["server"] ?? params["host"]', urls)

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

    def test_reactions_footer_hides_paid_reactions(self):
        source = read('submodules/TelegramUI/Components/Chat/ChatMessageReactionsFooterContentNode/Sources/ChatMessageReactionsFooterContentNode.swift')
        self.assertIn('let reactionsAttribute = forkVisibleMessageReactions(attributes: item.message.attributes', source)
        self.assertNotIn('let reactionsAttribute = mergedMessageReactions(', source)

    def test_ephemeral_no_forwards_follows_copy_protection_setting(self):
        store = read('submodules/TelegramCore/Sources/ApiUtils/StoreMessage_Telegram.swift')
        ephemeral = store.split('init?(apiEphemeralMessage:', 1)[1].split('\n    convenience init', 1)[0]
        self.assertIn('if isForwardingDisabled {\n                storeFlags.insert(.CopyProtected)', ephemeral)
        menus = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertEqual(menus.count('let isForwardingDisabled = !TelegramSimpleSettings.shared.allowCopyProtectedMedia && '), 2)

    def test_proxy_preview_has_one_port_row(self):
        source = read('submodules/TelegramUI/Components/ProxyServerPreviewScreen/Sources/ProxyServerPreviewScreen.swift')
        self.assertEqual(source.count('id: "port"'), 1)
        self.assertLess(source.index('id: "vless-protocol"'), source.index('id: "port"'))

    def test_web_proxy_links_accept_fork_link_forms(self):
        source = read('submodules/TelegramCore/Sources/Settings/ProxySettings.swift')
        parser = source.split('public func parseWebProxySettingsLink(', 1)[1].split('\npublic func ', 1)[0]
        self.assertIn('["t.me", "telegram.me", "telegram.dog"].contains(components.host?.lowercased() ?? "")', parser)
        self.assertIn('scheme == "https" || scheme == "http"', parser)
        self.assertIn('value = "https://" + value', parser)

    def test_save_to_files_never_exports_a_missing_path(self):
        source = read('submodules/TelegramUI/Sources/SaveMediaToFiles.swift')
        export = source.split('let url = URL(fileURLWithPath: symlinkPath)', 1)[0]
        self.assertIn('symlinkPath = data.path', export.rsplit('linkItem', 1)[1])
        self.assertIn('guard FileManager.default.fileExists(atPath: symlinkPath) else', export)

if __name__ == '__main__':
    unittest.main()
