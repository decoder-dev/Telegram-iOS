"""Regression contracts for fork behavior across the upstream 13 migration."""
import pathlib
import re
import unittest
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding='utf-8')

class ForkIntegration(unittest.TestCase):
    def test_live_location_reads_obey_ghost_before_cache_and_rpc(self):
        body = read('submodules/TelegramCore/Sources/State/AccountViewTracker.swift').split('public func updateSeenLiveLocationForMessageIds(', 1)[1].split('public func updatedExtendedMediaForMessageIds', 1)[0]
        guard = 'guard !ForkGhostModeSettings.shouldSuppressMessageReads else'
        self.assertEqual(body.count(guard), 2)
        self.assertLess(body.index(guard), body.index('updatedSeenLiveLocationMessageIdsAndTimestamps'))
        transaction = body.split('account.postbox.transaction', 1)[1]
        self.assertLess(transaction.index(guard), transaction.index('account.network.request'))

    def test_secret_media_checks_screenshot_permission_at_event_time(self):
        body = read('submodules/GalleryUI/Sources/SecretMediaPreviewController.swift').split('override public func viewDidAppear(', 1)[1].split('var nodeAnimatesItself', 1)[0]
        self.assertIn('if self.screenCaptureEventsDisposable == nil {', body)
        callback = body.split('.start(next:', 1)[1]
        self.assertLess(callback.index('!ForkSecretScreenshotSettings.allow'), callback.index('enqueueMessages('))

    def test_full_ghost_schedule_includes_story_policy(self):
        source = read('submodules/TelegramUI/Sources/ChatController.swift')
        predicates = re.findall(r'let applyGhostSchedule = .*?&& ForkGhostModeSettings.goOfflineAutomatically', source, re.S)
        self.assertEqual(len(predicates), 2)
        for predicate in predicates:
            self.assertIn('ForkGhostModeSettings.suppressStoryViews', predicate)

    def test_renderer_flags_and_collectible_colors_refresh(self):
        source = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        fingerprint = source.split('struct MessageFilterSettingsFingerprint', 1)[1].split('|> distinctUntilChanged', 1)[0]
        for field in ['hidePaidReactions', 'hideViaBot', 'accentColorSaturation']:
            self.assertIn('var ' + field + ':', fingerprint)
            self.assertIn(field + ': settings.' + field, fingerprint)
        collectible = read('submodules/AccountContext/Sources/PeerNameColors.swift').split('func peerNameColors(dark:', 1)[1].split('func mainColor', 1)[0]
        self.assertIn(').sgSaturationAdjusted', collectible)

    def test_default_greeting_is_hidden_without_fetch_or_space(self):
        source = read('submodules/TelegramUI/Components/Chat/ChatEmptyNode/Sources/ChatEmptyNode.swift')
        block = source.split('let hideDefaultSticker = ', 1)[1].split('let insets = ', 1)[0]
        self.assertIn('customStickerFile == nil &&', block)
        hidden = block.split('if hideDefaultSticker {', 1)[1].split('} else if', 1)[0]
        for statement in ['stickerSize = .zero', 'self.disposable.set(nil)', 'self.didSetupSticker = false']:
            self.assertIn(statement, hidden)
        self.assertNotIn('randomGreetingSticker', hidden)
        self.assertIn('hideDefaultSticker ? 0.0 : 5.0', source)

    def test_quick_translate_retains_capability_and_secret_chat_gates(self):
        body = read('submodules/TranslateUI/Sources/Translate.swift').split('public func canTranslateText(', 1)[1]
        forced = body.split('if forceShow {', 1)[1].split('}', 1)[0]
        self.assertIn('translateButtonAvailable && !text.trimmingCharacters', forced)
        menus = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        gate = menus.split('forceShow: ForkExtrasHotFlags.quickTranslateButton)', 1)[1].split('if canTranslate {', 1)[0]
        self.assertIn('Namespaces.Peer.SecretChat', gate)
        self.assertIn('canTranslate = false', gate)

    def test_real_sticker_fit_blocks_keep_frames_inside_viewport(self):
        blocks = []
        for node, padding in [('ChatMessageStickerItemNode', 'innerImageInset'), ('ChatMessageAnimatedStickerItemNode', 'imageInset')]:
            source = read(f'submodules/TelegramUI/Components/Chat/{node}/Sources/{node}.swift')
            fit = source.split('let stickerLeftMargin = ', 1)[1].split('imageSize = imageSize.aspectFitted', 1)
            block = 'let stickerLeftMargin = ' + fit[0] + 'imageSize = imageSize.aspectFitted' + fit[1].split('\n', 1)[0]
            blocks.append(block.replace('innerImageInset', 'imageInset'))
        if not shutil.which('swift'):
            self.skipTest('Swift unavailable locally; extracted geometry executes in macOS CI')
        utilities = read('submodules/Display/Source/UIKitUtils.swift')
        method = utilities.split('func aspectFitted(_ size: CGSize)', 1)[1].split('func aspectFittedOrSmaller', 1)[0].strip()
        prefix = 'import Foundation\nextension CGSize { func aspectFitted(_ size: CGSize)' + method + '\n}\n'
        fixture = '''
        struct Params { var width: CGFloat; var leftInset: CGFloat; var rightInset: CGFloat }
        struct Insets { var left: CGFloat = 8 }
        struct Bubble { var edgeInset: CGFloat = 4; var contentInsets = Insets() }
        struct Constants { var bubble = Bubble() }
        let layoutConstants = Constants()
        for width: CGFloat in [280, 320, 390, 768] {
          for incoming in [false, true] { for needsShareButton in [false, true] {
            for requested: CGFloat in [92, 184, 276, 360] {
              let params = Params(width: width, leftInset: 8, rightInset: 8)
              let avatarInset: CGFloat = incoming ? 42 : 0
              let deliveryFailedInset: CGFloat = 24
              let imageHorizontalOffset: CGFloat = 12
              let imageInset: CGFloat = 10
              var imageSize = CGSize(width: requested, height: requested * 0.75)
              FIT_BLOCK
              precondition(imageSize.width + imageInset * 2 + stickerLeftMargin + stickerRightMargin + (needsShareButton ? 36 : 0) <= width)
              precondition(imageSize.width <= requested && imageSize.height > 0)
            }
          }}
        }
        '''
        with tempfile.TemporaryDirectory() as tmp:
            for index, block in enumerate(blocks):
                path = pathlib.Path(tmp) / f'fit{index}.swift'
                path.write_text(prefix + fixture.replace('FIT_BLOCK', block), encoding='utf-8')
                subprocess.run(['swift', str(path)], check=True, timeout=120)

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

    def test_round_videos_keep_lens_zoom_presets_by_default(self):
        settings = read('submodules/TelegramUIPreferences/Sources/ExperimentalUISettings.swift')
        self.assertIn('return self.useModernVideoMessagePipeline ?? false', settings)
        screen = read('submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift')
        self.assertIn('immediateExperimentalUISettings.resolvedUseModernVideoMessagePipeline', screen)
        self.assertNotIn('ios_killswitch_disable_neo_round_camera_v2', screen)
        debug = read('submodules/DebugSettingsUI/Sources/DebugController.swift')
        self.assertIn('.useModernVideoMessagePipeline(experimentalSettings.resolvedUseModernVideoMessagePipeline)', debug)
        legacy = read('submodules/Camera/CameraLegacy/Sources/CameraDevice.swift')
        self.assertIn('AVCaptureDevice.default(.builtInTripleCamera', legacy)
        self.assertIn('virtualDeviceSwitchOverVideoZoomFactors', legacy)

    def test_web_proxy_serves_both_relay_protocols(self):
        settings = read('submodules/TelegramCore/Sources/Settings/ProxySettings.swift')
        web = settings.split('case let .web(secret, _):', 1)[1].split('case .vless:', 1)[0]
        # The fork's sidecar route wins when its relay answered; otherwise Telegram 13's carrier.
        self.assertLess(web.index('legacyWebProxyLoopbackEndpoint'), web.index('webProxy: true'))
        self.assertIn('return self.isWebProxy && self.legacyWebProxyLoopbackEndpoint == nil', settings)
        network = read('submodules/TelegramCore/Sources/Network/Network.swift')
        update = network.split('    func updateProxySettings(', 1)[1].split('let updated =', 1)[0]
        self.assertIn('let usesWebProxyCarrier = activeServer?.usesWebProxyCarrier == true', update)
        self.assertIn('self.webProxyActive.set(usesWebProxyCarrier)', update)
        self.assertIn('initialWebProxyActive: initialUsesWebProxyCarrier', network)
        manager = read('submodules/WebProxyTransport/Sources/WebProxyManager.swift')
        self.assertIn('if case WebProxyHttpCarrierError.bootstrapTokenMissing = error {', manager)
        self.assertIn('otherProtocolRecheckInterval', manager)

    def test_audio_and_voice_conversions_are_offered(self):
        menu = read('submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift')
        files = menu.split('func presentICloudFileGallery(', 1)[1].split('\n    func ', 1)[0]
        # Audio picked in Files: choose Audio or Voice Message, only where voice messages are allowed.
        self.assertIn('strongSelf.forkCanSendVoiceMessages()', files)
        self.assertIn('forkAudioToVoice(context: strongSelf.context, bookmarkData: item.urlData)', files)
        self.assertIn('sendResults(voiceFiles)', files)
        self.assertIn('func forkCanSendVoiceMessages() -> Bool', menu)
        conversion = read('submodules/TelegramUI/Components/AttachmentFileController/Sources/ForkAudioToVoice.swift')
        self.assertIn('public func forkAudioToVoice(context: AccountContext, bookmarkData: String)', conversion)
        self.assertIn('startAccessingSecurityScopedResource()', conversion)
        self.assertIn('public func forkVoiceToAudio(', conversion)
        self.assertIn('.Audio(isVoice: false', conversion)
        menus = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('forkVoiceToAudio(context: context', menus)
        self.assertIn('canSendMessagesToChat(chatPresentationInterfaceState) {\n                        let prefersRussian', menus)

    def test_rich_messages_reach_saving_filters_and_forwarding(self):
        page = read('submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift')
        self.assertIn('var fullPlainText: String', page)
        self.assertIn('case let .heading(t, _):', page)
        bridge = read('submodules/TelegramCore/Sources/MessageSaving/MessageSavingBridge.swift')
        self.assertIn('richText.instantPage.fullPlainText', bridge)
        self.assertIn('!message.effectiveMedia.isEmpty', bridge)
        attachments = read('submodules/TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift')
        self.assertEqual(attachments.count('for media in message.effectiveMedia {'), 2)
        state = read('submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift')
        self.assertIn('previousRichText.instantPage.fullPlainText !=', state)
        prefs = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        self.assertIn('body = richText.instantPage.fullPlainText', prefs)
        rich = read('submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift')
        self.assertIn('deleted: item.message.isLocallyDeleted && !item.presentationData.isPreview', rich)
        self.assertEqual(rich.count('ForkBypassDownloadRestrictionsSettings.enabled || (!item.associatedData.isCopyProtectionEnabled'), 2)
        enqueue = read('submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift')
        self.assertIn('text.isEmpty, !sourceMessage.attributes.contains(where: { $0 is RichTextMessageAttribute })', enqueue)

    def test_ghost_read_on_interact_covers_composer_sends_and_reaction_reads_obey_ghost(self):
        chat = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertIn('func beginGhostReadOnInteractForSend()', chat)
        self.assertEqual(chat.count('self.beginGhostReadOnInteractForSend()'), 1)
        load = read('submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift')
        self.assertIn('if scheduleTime == nil {\n                strongSelf.beginGhostReadOnInteractForSend()', load)
        read_actions = read('submodules/TelegramCore/Sources/TelegramEngine/Messages/InstallInteractiveReadMessagesAction.swift')
        body = read_actions.split('func addOrUpdate(messages: [StoreMessage], transaction: Transaction) {', 1)[1][:400]
        self.assertIn('if ForkGhostModeSettings.shouldSuppressMessageReads {\n            return', body)

if __name__ == '__main__':
    unittest.main()
