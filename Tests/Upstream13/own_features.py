"""Regression contracts for fork behavior across the upstream 13 migration."""
import os
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
    def test_composer_paste_is_the_pre_telegram13_clipboard_path(self):
        # The clipboard behaves as before the Telegram 13 merge: system paste, no markdown-on-paste,
        # no RTF latch to the native editor, and pasted media wins over the default text paste.
        panel = read('submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift')
        body = panel.split('public func chatInputTextNodeShouldPaste()', 1)[1].split('public func handlePastedMedia', 1)[0]
        self.assertNotIn('pastedMarkdownParser', body)
        self.assertNotIn('rtfRequiresNativeRichInput', body)
        self.assertNotIn('pasteboard.string, !text.isEmpty', body)
        self.assertIn('RichTextEditorClipboard.fragmentUTI', body)
        self.assertIn('if self.pasteRichFragmentFromPasteboard() { return false }', body)
        self.assertIn('if self.handlePastedMedia(perform: true) {', body)
        view = read('submodules/TelegramUI/Components/Chat/ChatInputTextNode/ChatInputTextViewImpl/Sources/ChatInputTextViewImpl.m')
        paste = view.split('- (void)paste:(id)sender', 1)[1].split('- (NSArray *)keyCommands', 1)[0]
        self.assertIn('_shouldPaste == nil || _shouldPaste()', paste)
        self.assertNotIn('insertText', paste)
        self.assertIn('[super paste:sender]', paste)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; actual clipboard representation fallback executes in macOS CI')
    def test_actual_clipboard_falls_back_from_empty_rich_data(self):
        source = read('submodules/TelegramUI/Components/RichTextEditor/Sources/RichTextEditorUIKit/Canvas/DocumentCanvasView+Clipboard.swift')
        body = source[source.index('    func fragment(fromPasteboard'):source.index('    /// A multi-paragraph fragment')]
        fixture = r'''import Foundation
struct Document { var blocks: [String] }
protocol TextPasteboard { var string: String? { get }; func data(forPasteboardType: String) -> Data? }
struct Pasteboard: TextPasteboard {
    var string: String?
    var values: [String: Data] = [:]
    func data(forPasteboardType type: String) -> Data? { values[type] }
}
enum DocumentCodec {
    static func decode(_ data: Data) throws -> Document {
        Document(blocks: data == Data("rich".utf8) ? ["rich"] : [])
    }
}
enum RTFConversion {
    static func fragment(fromRTF data: Data) -> Document? {
        if data == Data("valid".utf8) { return Document(blocks: ["formatted"]) }
        return data.isEmpty ? Document(blocks: []) : nil
    }
}
class DocumentCanvasView {
    static let richTextFragmentUTI = "rich"
    func plainTextFragment(_ text: String) -> Document { Document(blocks: [text]) }
''' + body + r'''}
let view = DocumentCanvasView()
let text = "Привет 🍌\nsecond line"
for type in ["rich", "public.rtf", "com.apple.flat-rtfd"] {
    for data in [Data(), Data("invalid".utf8)] {
        precondition(view.fragment(fromPasteboard: Pasteboard(string: text, values: [type: data]))?.blocks == [text])
    }
}
precondition(view.fragment(fromPasteboard: Pasteboard(string: text, values: ["rich": Data("rich".utf8)]))?.blocks == ["rich"])
precondition(view.fragment(fromPasteboard: Pasteboard(string: text, values: ["rich": Data(), "public.rtf": Data("valid".utf8)]))?.blocks == ["formatted"])
precondition(view.fragment(fromPasteboard: Pasteboard(string: nil)) == nil)
precondition(view.fragment(fromPasteboard: Pasteboard(string: "")) == nil)
print("Actual clipboard reader: empty/invalid rich fallback and representation priority passed")
'''
        self.run_swift_fixture(fixture)

    def test_hidden_tabs_keep_settings_and_a_back_route(self):
        chats = read('submodules/ChatListUI/Sources/ChatListController.swift')
        self.assertIn('combineLatest(peerStatus, accountPeer, appearanceChanges, hiddenTabBar)', chats)
        self.assertIn('tabBarHidden, !stateAndFilterId.state.editing, !isReorderingTabs', chats)
        self.assertIn('root.openSettings(edit: false)', chats)
        root = read('submodules/TelegramUI/Sources/TelegramRootController.swift')
        body = root.split('public func openSettings(edit:', 1)[1].split('public func openBirthdaySetup', 1)[0]
        self.assertIn('immediateForkExtrasSettings.hideTabBar', body)
        self.assertIn('self.pushViewController(settings, animated: true)', body)
        self.assertLess(body.index('self.pushViewController(settings'), body.index('rootTabController.selectedIndex'))
        header = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift')
        self.assertIn('if self.controller?.previousItem != nil {', header)
        component = read('submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/NavigationButtonComponent.swift')
        self.assertIn('self.accessibilityLabel = title', component)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; document-picker delegate executes in macOS CI')
    def test_actual_picker_completes_selection_once(self):
        source = read('submodules/LegacyMediaPickerUI/Sources/LegacyICloudFilePicker.swift')
        body = source[source.index('private final class LegacyICloudFileController'):source.index('public enum LegacyICloudFilePickerMode')]
        fixture = r'''import Foundation
class Logger { static let shared = Logger(); func log(_ tag: String, _ text: String) {} }
enum LegacyControllerPresentation { case modal }
class PresentationTheme {}
class LegacyController {
    init(presentation: LegacyControllerPresentation, theme: PresentationTheme?) {}
    required init(coder: NSCoder) {}
}
class UIDocumentPickerViewController {}
protocol UIDocumentPickerDelegate: AnyObject {}
''' + body + r'''
let picker = UIDocumentPickerViewController()
let first = URL(fileURLWithPath: "/tmp/first.zip"), second = URL(fileURLWithPath: "/tmp/second.zip")
var results: [[URL]] = []
private let delegate = LegacyICloudFileController(presentation: .modal, theme: nil, completion: { results.append($0) })
delegate.documentPicker(picker, didPickDocumentsAt: [first, second])
delegate.documentPicker(picker, didPickDocumentAt: first)
delegate.documentPickerWasCancelled(picker)
precondition(results == [[first, second]])
var cancelled: [[URL]] = []
private let cancelDelegate = LegacyICloudFileController(presentation: .modal, theme: nil, completion: { cancelled.append($0) })
cancelDelegate.documentPickerWasCancelled(picker)
cancelDelegate.documentPicker(picker, didPickDocumentsAt: [first])
precondition(cancelled == [[]])
print("Document picker: actual completion-once delegate passed")
'''
        self.run_swift_fixture(fixture)

    def test_file_preparation_coordinates_reads_with_timeout_and_partial_error(self):
        resource = read('submodules/ICloudResources/Sources/ICloudResources.swift')
        body = resource.split('public func iCloudFileDescription(', 1)[1].split('private final class SecurityScopedAccess', 1)[0]
        self.assertNotIn('NSMetadataQuery', body)
        self.assertIn('NSFileAccessIntent.readingIntent(with: url', body)
        self.assertIn('descriptionWithUrl(intent.url)', body)
        self.assertIn('coordinator.cancel()', body)
        self.assertIn('timeout.schedule(deadline: .now() + 120.0)', body)
        self.assertIn('guard !finished.swap(true) else { return }', body)
        menu = read('submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift')
        body = menu.split('func presentICloudFileGallery(', 1)[1]
        self.assertIn('results.compactMap({ $0 }).count == results.count', body)
        self.assertIn('enqueueMediaMessageDisposable.set(nil)', body)
        self.assertIn('afterDisposed { [weak progress]', body)
        self.assertIn('attachmentController.dismiss(animated: true, completion:', menu)
        picker = read('submodules/LegacyMediaPickerUI/Sources/LegacyICloudFilePicker.swift')
        self.assertIn('controller.retainedPickerDelegate = legacyController', picker)
        self.assertIn('guard !self.didComplete else { return }', picker)
        self.assertIn('self.complete(urls, source: "didPickDocumentsAt")', picker)
        self.assertIn('self.complete([url], source: "didPickDocumentAt")', picker)

    def test_ghost_restore_reconciles_deleted_counts_and_account_exceptions(self):
        source = read('submodules/TelegramCore/Sources/Arena/BananaGhostLocalRead.swift')
        body = source.split('private func bananaRestoreServerReadState(', 1)[1].split('/// Call before an explicit read', 1)[0]
        self.assertIn('return false', body)
        self.assertNotIn('return read.readCount != nil', body)
        self.assertIn('Int32(clamping:', body)
        self.assertIn('ForkGhostModeSettings.isException(accountPeerId: accountPeerId, peerId: peerId)', source)
        sync = read('submodules/TelegramCore/Sources/State/ManagedSynchronizePeerReadStates.swift')
        self.assertNotIn('hidesReadReceipts == self.ghostHidesReadReceipts', sync)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; glow geometry executes in macOS CI')
    def test_actual_glow_fades_inside_row_boundaries(self):
        source = read('submodules/AvatarNode/Sources/AvatarNode.swift')
        start = source.index('func avatarGlowMaskStops(')
        function = source[start:source.index('\n}', start) + 2]
        fixture = 'import Foundation\n' + function + r'''
for height in [1.0, 32.0, 52.0, 80.0, 120.0] {
    for lower in [-50.0, 0.0, 1.0, 12.0, 52.0, 150.0] {
        for upper in [-20.0, 0.0, 32.0, 52.0, 80.0, 200.0] {
            let stops = avatarGlowMaskStops(height: height, lowerBound: lower, upperBound: upper)
            precondition(stops.count == 4 && stops == stops.sorted())
            precondition(stops.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
            let lo = max(0, min(height, lower)), hi = max(lo, min(height, upper))
            precondition(abs(stops[0] * height - lo) < 0.00001)
            precondition(abs(stops[3] * height - hi) < 0.00001)
        }
    }
}
print("Avatar glow: actual mask geometry passed")
'''
        self.run_swift_fixture(fixture)
        item = read('submodules/ChatListUI/Sources/Node/ChatListItem.swift')
        self.assertIn('strongSelf.avatarNode.glowVerticalBounds =', item)
        self.assertIn('glow.mask = mask', source)
        self.assertNotIn('self.layer.mask = mask', source)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; preparation lifecycle executes in macOS CI')
    def test_actual_file_preparation_success_error_timeout_and_cancel(self):
        source = read('submodules/ICloudResources/Sources/ICloudResources.swift')
        body = source[source.index('public func iCloudFileDescription('):source.index('private final class SecurityScopedAccess')]
        body = body.replace('public func', 'func').replace('NSFileCoordinator', 'FakeFileCoordinator').replace('NSFileAccessIntent', 'FakeFileAccessIntent')
        # Exercise the production timeout branch without delaying macOS CI for two minutes.
        body = body.replace('.now() + 120.0', '.now() + 0.05')
        fixture = r'''import Foundation
protocol Disposable { func dispose() }
final class ActionDisposable: Disposable {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    func dispose() { action() }
}
final class Atomic<T> {
    private var value: T; private let lock = NSLock()
    init(value: T) { self.value = value }
    func with<R>(_ f: (T) -> R) -> R { lock.lock(); defer { lock.unlock() }; return f(value) }
    func swap(_ next: T) -> T { lock.lock(); defer { lock.unlock() }; let old = value; value = next; return old }
}
enum NoError: Error {}
struct ICloudFileDescription { let fileName: String }
final class Subscriber<T> {
    let next: (T) -> Void; let completed: () -> Void
    init(next: @escaping (T) -> Void, completed: @escaping () -> Void) { self.next = next; self.completed = completed }
    func putNext(_ value: T) { next(value) }
    func putCompletion() { completed() }
}
final class Signal<T, E: Error> {
    let generator: (Subscriber<T>) -> Disposable
    init(_ generator: @escaping (Subscriber<T>) -> Disposable) { self.generator = generator }
    func start(next: @escaping (T) -> Void, completed: @escaping () -> Void) -> Disposable {
        return generator(Subscriber(next: next, completed: completed))
    }
}
final class SecurityScopedAccess {
    init(url: URL, active: Bool) {}
    func stop() {}
}
func descriptionWithUrl(_ url: URL) -> ICloudFileDescription? { return .init(fileName: url.lastPathComponent) }
final class FakeFileAccessIntent {
    struct Options: OptionSet { let rawValue: Int; static let withoutChanges = Options(rawValue: 1) }
    let url: URL
    init(_ url: URL) { self.url = url }
    static func readingIntent(with url: URL, options: Options) -> FakeFileAccessIntent { .init(url) }
}
final class FakeFileCoordinator {
    static var mode = 0
    static var cancellations = Atomic<Int>(value: 0)
    init(filePresenter: Any?) {}
    func cancel() { let old = Self.cancellations.with { $0 }; let _ = Self.cancellations.swap(old + 1) }
    func coordinate(with intents: [FakeFileAccessIntent], queue: OperationQueue, byAccessor: @escaping (Error?) -> Void) {
        let mode = Self.mode
        if mode == 2 { return } // stalled File Provider
        queue.addOperation { byAccessor(mode == 1 ? NSError(domain: "fixture", code: 1) : nil) }
    }
}
''' + body + r'''
for mode in [0, 1, 2] {
    FakeFileCoordinator.mode = mode
    let done = DispatchSemaphore(value: 0)
    var values: [ICloudFileDescription?] = []
    let subscription = iCloudFileDescription(URL(fileURLWithPath: "/tmp/file-fixture.zip")).start(next: { values.append($0) }, completed: { done.signal() })
    precondition(done.wait(timeout: .now() + 3) == .success)
    precondition(values.count == 1)
    if mode == 0 { precondition(values[0]?.fileName == "file-fixture.zip") } else { precondition(values[0] == nil) }
    subscription.dispose()
}
FakeFileCoordinator.mode = 2
let values = Atomic<Int>(value: 0)
let subscription = iCloudFileDescription(URL(fileURLWithPath: "/tmp/file-fixture.zip")).start(next: { _ in let _ = values.swap(1) }, completed: { let _ = values.swap(1) })
subscription.dispose()
Thread.sleep(forTimeInterval: 0.15)
precondition(values.with { $0 } == 0)
print("File preparation: actual success/error/timeout/cancellation lifecycle passed")
'''
        self.run_swift_fixture(fixture)

    def run_swift_fixture(self, fixture):
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / 'main.swift'
            binary = pathlib.Path(directory) / 'fixture'
            source.write_text(fixture, encoding='utf-8')
            subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)

    def test_message_saving_store_imports_postbox_types_directly(self):
        store = read('submodules/TelegramUIPreferences/Sources/MessageSavingStore.swift')
        self.assertIn('\nimport Postbox\n', store)
        self.assertIn('MessageId(peerId: PeerId(', store)

    def test_live_location_reads_obey_ghost_before_cache_and_rpc(self):
        body = read('submodules/TelegramCore/Sources/State/AccountViewTracker.swift').split('public func updateSeenLiveLocationForMessageIds(', 1)[1].split('public func updatedExtendedMediaForMessageIds', 1)[0]
        guard = 'guard !ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: account.peerId, peerId:'
        self.assertEqual(body.count(guard), 2)
        self.assertLess(body.index(guard), body.index('self.updatedSeenLiveLocationMessageIdsAndTimestamps'))
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
        self.assertIn('self.chatLocation.peerId?.namespace != Namespaces.Peer.SecretChat', predicates[0])

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
        self.assertIn('canSendAudioMessagesToPeer(EnginePeer(audioPeer), isVoice: false', menus)
        self.assertIn('canSendAudioMessagesToPeer(peer, isVoice: false', menus)

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
        self.assertIn('if ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: self.accountPeerId, peerId: self.peerId) {\n            return', body)

    def test_proxy_screens_are_not_stacked_twice(self):
        preview = read('submodules/TelegramUI/Components/ProxyServerPreviewScreen/Sources/ProxyServerPreviewScreen.swift')
        self.assertIn('public let previewServer: ProxyServerSettings', preview)
        self.assertIn('static func pushIfNotPresented(', preview)
        resolved = read('submodules/TelegramUI/Sources/OpenResolvedUrl.swift')
        self.assertEqual(resolved.count('ProxyServerPreviewScreen.pushIfNotPresented('), 2)
        self.assertNotIn('ProxyServerPreviewScreen(context: context, server: server)', resolved)
        openurl = read('submodules/TelegramUI/Sources/OpenUrl.swift')
        self.assertIn('ProxyServerPreviewScreen.pushIfNotPresented(', openurl)
        chatlist = read('submodules/ChatListUI/Sources/ChatListController.swift')
        self.assertIn('presentedProxySettingsController', chatlist)
        self.assertEqual(chatlist.count('makeProxySettingsController(context: self.context)'), 1)


    def test_system_translation_backend_reaches_chat_and_language_list(self):
        for path in ('submodules/TranslateUI/Sources/Translate.swift', 'submodules/TranslateUI/Sources/ChatTranslation.swift', 'submodules/SettingsUI/Sources/Language Selection/LocalizationListControllerNode.swift'):
            self.assertIn('translationBackend == .system', read(path), path)

    def test_session_keychain_switch_is_not_offered_and_copies_are_dropped(self):
        extras = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertNotIn('.sessionBackup(settings.sessionKeychainBackup)', extras)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertNotIn('SessionKeychainBackup.save(', shared)
        self.assertIn('SessionKeychainBackup.deleteAll()', shared)


    def test_extras_are_grouped_by_window_and_menu_entries_moved(self):
        menu = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift')
        self.assertIn('forkCustomizationSettingsTitle(presentationData.strings)', menu)
        self.assertIn('forkDeveloperModeSettingsTitle(presentationData.strings)', menu)
        extras = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        for gone in ('.customization', '.developer', '.archive', 'case hubInterface', 'case hubChat\n'):
            self.assertNotIn(gone, extras)
        for hub in ('hubChatList', 'hubTabBar', 'hubMessages', 'hubMedia', 'hubProfile'):
            self.assertIn('case ' + hub, extras)
        self.assertIn('ForkExtrasEntry.regroupedOwner(of: id)', extras)


    def test_every_titled_extras_row_is_searchable(self):
        extras = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('func searchTitle(strings: PresentationStrings) -> String?', extras)
        self.assertIn('func forkExtrasSearchableRows(', extras)
        search = read('submodules/SettingsUI/Sources/Search/SettingsSearchableItems.swift')
        self.assertIn('forkExtrasSearchableRows(strings: strings)', search)


    def test_settings_icons_follow_bananagram_theme_accent(self):
        icons = read('submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift')
        self.assertIn('public func forkUpdateSettingsIconTint(', icons)
        self.assertIn('(glyphColor ?? UIColor.white).cgColor', icons)
        self.assertNotIn('public static let proxy = renderSettingsIcon', icons)
        for name in ('premium', 'stars', 'premiumGift'):
            self.assertIn('public static var ' + name + ': UIImage?', icons)
        data = read('submodules/TelegramPresentationData/Sources/PresentationData.swift')
        self.assertIn('theme.name.string.hasPrefix("BananaGram")', data)
        self.assertIn('if !theme.preview {', data)


    def test_banana_island_badge_is_shown_below_the_dynamic_island(self):
        metrics = read('submodules/Display/Source/DeviceMetrics.swift')
        self.assertIn('return self.hasTopNotch || self.hasDynamicIsland', metrics)
        window = read('submodules/Display/Source/WindowContent.swift')
        self.assertEqual(window.count('self.badgeFrame(for: image)'), 2)
        # The badge sits in the cutout, at a per-model offset, as the screenshot-only label of the notch or island.
        self.assertIn('y: self.deviceMetrics.appBadgeOffset', window)
        self.assertIn('public var appBadgeBaseOffset: CGFloat', metrics)
        self.assertIn('case .iPhone16ProMax, .iPhoneAir, .iPhone18ProMax:\n                return 22.0', metrics)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('var fillColor = theme.list.itemCheckColors.fillColor', shared)
        # UIKit string drawing needs the y-down context; the plain contextGenerator one drew the badge upside down.
        self.assertIn('generateImage(size, rotatedContext: { _, context in', shared)


    def test_profile_title_leaves_room_for_the_right_buttons(self):
        header = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift')
        self.assertIn('trailingIconsWidth', header)
        self.assertIn('width - rightButtonsReserve * 2.0 - trailingIconsWidth', header)


    def test_wallet_state_retry_backs_off(self):
        wallet = read('submodules/WalletContext/Sources/WalletContextImpl.swift')
        self.assertIn('var serverStateRetryFailureCount = 0', wallet)
        self.assertIn('self.serverStateRetryFailureCount = 0', wallet)
        self.assertIn('min(5 * (1 << max(0, self.serverStateRetryFailureCount - 1)), 300)', wallet)
        self.assertNotIn('Task.sleep(nanoseconds: 5_000_000_000)\n        guard !Task.isCancelled,\n              !self.isShutdown', wallet)


    def test_snow_is_a_wired_extras_toggle(self):
        settings = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        self.assertEqual(settings.count('snowEnabled'), 6)
        self.assertIn('?? false', settings[settings.index('decodeIfPresent(Bool.self, forKey: "snowEnabled")'):][:120])
        controller = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('.appearanceToggle(1541,', controller)
        self.assertIn('[1603, 1500, 1501, 1541, 57]', controller)
        self.assertIn('[1508, 1509, 1735, 54, 1521, 1550, 1519]', controller)
        self.assertIn('hideStickerStatus', read('submodules/TelegramUI/Components/Chat/ChatMessageStickerItemNode/Sources/ChatMessageStickerItemNode.swift') .replace('ForkExtrasHotFlags.hideStickerStatus','hideStickerStatus'))
        # The stable id must stay unique: 1540 is the Appearance hub.
        self.assertEqual(controller.count('.appearanceToggle(1541,'), 1)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('BananaSnowSettings.enabled = settings.snowEnabled', shared)
        view = read('submodules/TelegramPresentationData/Sources/BananaSnowView.swift')
        self.assertIn('BananaSnowSettings.enabled', view)
        self.assertIn('self.isUserInteractionEnabled = false', view)
        self.assertIn('self.updateBananaSnow(size: layout.size)', read('submodules/ChatListUI/Sources/ChatListController.swift'))
        self.assertIn('self.updateBananaSnow(size: layout.size)', read('submodules/TelegramUI/Sources/ChatControllerNode.swift'))


    def test_disappeared_gifts_use_banana_spy_storage(self):
        storage = read('submodules/TelegramCore/Sources/Arena/BananaSpyStorage.swift')
        self.assertIn('public static var trackDisappearedGifts: Bool', storage)
        self.assertIn('bananaDisappearedGifts', read('submodules/TelegramCore/Sources/SyncCore/SyncCore_Namespaces.swift'))
        # Namespaces are Int8: a larger literal is a compile error, and an id used twice would share one cache collection.
        namespaces = read('submodules/TelegramCore/Sources/SyncCore/SyncCore_Namespaces.swift')
        for name, value in re.findall(r'static let (\w+): Int8 = (\d+)', namespaces):
            self.assertLessEqual(int(value), 127, name)
        cached = namespaces[namespaces.index('struct CachedItemCollection'):]
        ids = re.findall(r'static let (\w+): Int8 = (\d+)', cached[:cached.index('\n    }\n')])
        self.assertEqual(len(ids), len({value for _, value in ids}))
        gifts = read('submodules/TelegramCore/Sources/TelegramEngine/Payments/StarGifts.swift')
        # A failed request must not read as an empty profile: that would mark every remembered gift missing.
        self.assertIn('guard succeeded else {', gifts)
        # The history is read and written only by a context that was asked to track it, whole-list only and bounded.
        self.assertIn('private let canTrackDisappearedGifts: Bool', gifts)
        self.assertIn('tracksDisappearedGifts: Bool = false', gifts)
        self.assertIn('private let bananaGiftHistoryMaxDisappearedCount = 200', gifts)
        self.assertIn('func updateTracksDisappearedGifts(_ tracksDisappearedGifts: Bool)', gifts)
        self.assertNotIn('Donutgram', gifts)
        self.assertIn('disappearedGifts: self.isTrackingDisappearedGifts ? self.giftHistory.filter { $0.isMissing } : []', gifts)
        pane = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/GiftsListView.swift')
        self.assertIn('self.openDisappearedGift(product, lastSeen: disappearedDate)', pane)
        self.assertIn('gift.withoutActions()', pane)
        self.assertIn('self.profileGifts.updateTracksDisappearedGifts(enabled)', pane)
        info = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift')
        self.assertIn('tracksDisappearedGifts: BananaSpyStorage.trackDisappearedGifts', info)
        self.assertIn('hasDisappearedGifts', info)
        self.assertIn('BananaSpyStorage.trackDisappearedGiftsDidChangeNotification', pane)
        sheet = read('submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift')
        self.assertIn('deleteDisappearedGift: (() -> Void)? = nil', sheet)
        controller = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('.appearanceToggle(1543,', controller)
        self.assertIn('[55, 56, 1551, 1714, 1552, 1543, 58]', controller)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('BananaSpyStorage.trackDisappearedGifts = settings.showDisappearedGifts', shared)


    def test_round_video_camera_choice(self):
        camera = read('submodules/TelegramCore/Sources/Arena/BananaRoundVideoCamera.swift')
        self.assertIn('public static var opensWithRear: Bool', camera)
        screen = read('submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift')
        self.assertIn('position: opensWithRear ? .back : .front,', screen)
        self.assertIn('BananaRoundVideoCamera.noteCameraInUse(isRear: position == .back)', screen)
        controller = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('[1609, 1515, 1516, 1544, 1545, 1559, 1612]', controller)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('BananaRoundVideoCamera.remembersLast = settings.roundVideoRemembersCamera', shared)


    def test_chat_list_header_options(self):
        header = read('submodules/TelegramPresentationData/Sources/BananaChatListHeader.swift')
        self.assertIn('hidesConnectionStatus', header)
        controller = read('submodules/ChatListUI/Sources/ChatListController.swift')
        self.assertIn('BananaChatListHeader.current.hidesConnectionStatus', controller)
        self.assertIn('BananaChatListHeader.didChangeNotification', controller)
        self.assertIn('[1601, 52, 1499, 1546, 1547, 1548, 1549]', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))
        self.assertIn('BananaChatListHeader.current = BananaChatListHeader(', read('submodules/TelegramUI/Sources/SharedAccountContext.swift'))


    def test_poll_results_before_voting(self):
        poll = read('submodules/TelegramUI/Components/Chat/ChatMessagePollBubbleContentNode/Sources/ChatMessagePollBubbleContentNode.swift')
        self.assertIn('ForkExtrasHotFlags.pollResultsBeforeVoting && !poll.hideResultsUntilClose', poll)
        self.assertIn('self.currentResult != nil && !self.allowsVotingWithResult', poll)
        self.assertEqual(poll.count('_ allowVotingWithResults: Bool, _ constrainedWidth: CGFloat'), 3)
        self.assertIn('[1508, 1509, 1735, 54, 1521, 1550, 1519]', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))
        self.assertIn('pollResultsBeforeVoting: settings.pollResultsBeforeVoting', read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift'))


    def test_presence_display_options(self):
        display = read('submodules/TelegramPresentationData/Sources/BananaPresenceDisplay.swift')
        self.assertIn('exactLastSeen', display)
        formatting = read('submodules/TelegramStringFormatting/Sources/PresenceStrings.swift')
        self.assertIn('let expanded = (expanded && !presenceDisplay.relativeLastSeen) || presenceDisplay.exactLastSeen', formatting)
        item = read('submodules/ChatListUI/Sources/Node/ChatListItem.swift')
        self.assertIn('BananaPresenceDisplay.current.showsOfflineDot', item)
        self.assertEqual(item.count('bananaPresenceIcon('), 7)
        self.assertIn('[55, 56, 1551, 1714, 1552, 1543, 58]', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))


    def test_island_follows_the_app_icon(self):
        palette = read('submodules/TelegramPresentationData/Sources/BananaIslandPalette.swift')
        # One entry per alternate icon in the bundle, and the default icon is BlueIcon.
        icons = sorted(name[:-len('.alticon')] for name in os.listdir(os.path.join(ROOT, 'Telegram/Telegram-iOS')) if name.endswith('.alticon'))
        for icon in icons:
            self.assertIn('"%s":' % icon, palette)
        self.assertIn('colors[iconName ?? "BlueIcon"]', palette)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('BananaIslandPalette.colors(iconName: self.applicationBindings.getAlternateIconName())', shared)
        self.assertIn('Notification.Name("BananaIslandPalette.iconDidChange")', read('submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift'))
        self.assertIn('Notification.Name("BananaIslandPalette.iconDidChange")', palette)
        self.assertIn('[1618, 1531, 1532, 1553, 1619]', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))


    def test_tiktok_and_shorts_link_download(self):
        sources = os.path.join(ROOT, 'submodules/BananaLinkDownloader/Sources')
        names = sorted(os.listdir(sources))
        self.assertEqual(len(names), 9)  # incl. BananaMediaURLPolicy.swift
        for name in names:
            text = (pathlib.Path(sources) / name).read_text(encoding='utf-8')
            self.assertNotIn('donutgram', text.lower())
            self.assertNotRegex(text, r'\bDG[A-Z]')
        chat = read('submodules/TelegramUI/Sources/ChatController+BananaLinkDownload.swift')
        # Off by default and never in a secret chat or a chat where media is banned or paid.
        self.assertIn('ForkExtrasHotFlags.downloadTikTok', chat)
        self.assertIn('Namespaces.Peer.SecretChat', chat)
        self.assertIn('sendPaidMessageStars != nil', chat)
        # A failed or cancelled download sends the original message.
        self.assertIn('outgoing = [template]', chat)
        send = read('submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift')
        self.assertIn('strongSelf.bananaInterceptLinkSend(transformedMessages, peerId: peerId)', send)
        self.assertIn('//submodules/BananaLinkDownloader:BananaLinkDownloader', read('submodules/TelegramUI/BUILD'))
        self.assertIn('self.downloadTikTok = try container.decodeIfPresent(Bool.self, forKey: "downloadTikTok") ?? false', read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'))


    def test_reply_to_a_deleted_message_is_sent_as_a_quote(self):
        quote = read('submodules/TelegramCore/Sources/Arena/BananaDeletedReplyQuote.swift')
        # The server no longer has the message, so the reply attribute must be dropped and the quote put in the text.
        self.assertIn('source.attributes.contains(where: { $0 is DeletedMessageAttribute })', quote)
        self.assertIn('replyToMessageId: nil', quote)
        self.assertIn('Namespaces.Peer.SecretChat', quote)
        enqueue = read('submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift')
        self.assertIn('BananaDeletedReplyQuote.quotedMessage(transaction: transaction, peerId: peerId, message: updatedMessage)', enqueue)
        self.assertIn('[1605, 65, 66],\n            [1557],', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))

    def test_exact_counts_and_voice_send_confirmation(self):
        fmt = read('submodules/TelegramPresentationData/Sources/NumericFormat.swift')
        # Exact counts bypass the "1.2K" shortening, and the flag is a plain atomic.
        self.assertIn('if BananaExactCounts.enabled {\n        return presentationStringsFormattedNumber(Int64(count), "\\u{2009}")', fmt)
        ctl = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('[1557],\n            [1558],', ctl)
        self.assertIn('[1609, 1515, 1516, 1544, 1545, 1559, 1612],', ctl)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('BananaExactCounts.enabled = settings.exactCounts', shared)
        self.assertIn('BananaVoiceSendConfirmation.enabled = settings.confirmVoiceSend', shared)
        # Releasing the record button opens the preview instead of sending, so the user sends from there.
        rec = read('submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift')
        self.assertIn('if BananaVoiceSendConfirmation.enabled, case .send = action {\n            updatedAction = .preview', rec)
        prefs = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        for name in ('exactCounts', 'confirmVoiceSend'):
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), prefs)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), prefs)

    def test_ghost_exceptions_are_per_chat(self):
        core = read('submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift')
        self.assertIn('public static func shouldSuppressMessageReads(accountPeerId: PeerId, peerId: PeerId) -> Bool {\n        return shouldSuppressMessageReads && !isException(accountPeerId: accountPeerId, peerId: peerId)', core)
        self.assertIn('return suppressOutgoingActivity && !isException(accountPeerId: accountPeerId, peerId: peerId)', core)
        # Typing goes through one chokepoint that knows the peer.
        self.assertIn('if ForkGhostModeSettings.suppressesOutgoingActivity(accountPeerId: accountPeerId, peerId: peerId) {', core)
        self.assertIn('ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: stateManager.accountPeerId, peerId: index.id.peerId)', read('submodules/TelegramCore/Sources/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift'))
        self.assertIn('ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: accountPeerId, peerId: message.id.peerId)', read('submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift'))
        install = read('submodules/TelegramCore/Sources/TelegramEngine/Messages/InstallInteractiveReadMessagesAction.swift')
        self.assertEqual(install.count('ForkGhostModeSettings.shouldSuppressMessageReads {'), 0)
        history = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        self.assertIn('ForkGhostModeSettings.shouldSuppressMessageReads(accountPeerId: self.context.account.peerId, peerId: peerId)', history)
        menu = read('submodules/ChatListUI/Sources/ChatContextMenus.swift')
        self.assertIn('ForkGhostModeSettings.setException(accountPeerId: context.account.peerId, peerId: peerId, !isException)', menu)

    def test_queue_threads_and_locations_use_account_scoped_permissions(self):
        queue = read('submodules/TelegramCore/Sources/State/ManagedSynchronizeConsumeMessageContentsOperations.swift')
        self.assertIn('filterByPeerId: peerId, limit: 10', queue)
        self.assertIn('exceptionPeerIds(accountPeerId: stateManager.accountPeerId)', queue)
        self.assertIn('shouldSuppressMessageReads(accountPeerId: stateManager.accountPeerId, peerId: $0.peerId)', queue)
        threads = read('submodules/TelegramCore/Sources/TelegramEngine/Messages/ReplyThreadHistory.swift')
        self.assertIn('shouldSuppressMessageReads(accountPeerId: self.account.peerId, peerId: peerId)', threads)
        self.assertIn('shouldSuppressMessageReads(accountPeerId: strongSelf.account.peerId, peerId: peerId)', threads)

    def test_mass_delete_reports_queued_requests_and_does_not_silently_truncate(self):
        source = read('submodules/ChatListUI/Sources/BananaDeleteOwnMessages.swift')
        self.assertNotIn('maximumMessageCount', source)
        self.assertNotIn('added == 0', source)
        self.assertIn('seen.insert(message.id).inserted', source)
        self.assertIn('if result.completed || nextState == state {', source)
        self.assertIn('complete: result.completed', source)
        self.assertIn('start(completed:', source)  # Engine deletion completes without emitting a Void value.
        self.assertIn('cancelled.swap(true)', source)
        menu = read('submodules/ChatListUI/Sources/ChatContextMenus.swift')
        self.assertIn('case let .deleting(queued, total):', menu)
        self.assertIn('case let .finished(queued, searchComplete):', menu)
        self.assertIn('Search stopped before completion', menu)

    def test_user_cancel_stops_send_without_overwriting_new_input(self):
        source = read('submodules/TelegramUI/Sources/ChatController+BananaLinkDownload.swift')
        self.assertIn('userCancelled = true', source)
        body = source.split('if userCancelled {', 1)[1].split('let outgoing:', 1)[0]
        self.assertIn('backgroundTask.end()', body)
        self.assertIn('effectiveInputState.inputText.length == 0', body)
        self.assertIn('withUpdatedEffectiveInputState(originalInputState)', body)
        self.assertIn('return', body)
        self.assertNotIn('enqueueMessages', body)
        fetcher = read('submodules/BananaLinkDownloader/Sources/BananaMediaFetcher.swift')
        finish = fetcher.split('didFinishDownloadingTo location:', 1)[1].split('didCompleteWithError', 1)[0]
        self.assertLess(finish.index('size.int64Value <= download.maxBytes'), finish.index('moveItem'))

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; account isolation executes in macOS CI')
    def test_actual_exception_store_isolates_accounts_and_persists_revocations(self):
        policy = read('submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift')
        production = policy.split('    private static let exceptionsKey =', 1)[1].split('    /// True when dont-read', 1)[0]
        production = '    private static let exceptionsKey =' + production
        # Use an isolated UserDefaults key while executing the real store, locking and predicates.
        production = production.replace('ForkGhostModeSettings.exceptionPeers.v2', 'BananaGram.fixture.' + os.urandom(8).hex())
        fixture = r'''import Foundation
struct PeerId: Hashable { let value: Int64; init(_ value: Int64) { self.value = value }; func toInt64() -> Int64 { value } }
final class Atomic<T> {
    private var value: T
    init(value: T) { self.value = value }
    func with<R>(_ f: (T) -> R) -> R { f(value) }
    func modify(_ f: (T) -> T) -> T { value = f(value); return value }
}
enum Policy {
    static var shouldSuppressMessageReads = true
    static var suppressOutgoingActivity = true
    static let didChangeNotification = Notification.Name("fixture")
''' + production.replace('public static', 'static') + r'''
    static func verifyPersistence() {
        precondition(loadExceptionPeers() == exceptionPeers.with { $0 })
        UserDefaults.standard.removeObject(forKey: exceptionsKey)
    }
}
let a = PeerId(100), b = PeerId(200), chat = PeerId(300)
Policy.setException(accountPeerId: a, peerId: chat, true)
precondition(!Policy.shouldSuppressMessageReads(accountPeerId: a, peerId: chat))
precondition(Policy.shouldSuppressMessageReads(accountPeerId: b, peerId: chat))
precondition(!Policy.suppressesOutgoingActivity(accountPeerId: a, peerId: chat))
precondition(Policy.suppressesOutgoingActivity(accountPeerId: b, peerId: chat))
precondition(Policy.exceptionPeerIds(accountPeerId: a) == [chat])
Policy.setException(accountPeerId: b, peerId: chat, true)
Policy.setException(accountPeerId: a, peerId: chat, false)
precondition(Policy.shouldSuppressMessageReads(accountPeerId: a, peerId: chat))
precondition(!Policy.shouldSuppressMessageReads(accountPeerId: b, peerId: chat))
Policy.verifyPersistence()
print("Account-scoped ghost exceptions: isolation/persistence/revocation passed")
'''
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / 'main.swift'
            binary = pathlib.Path(directory) / 'fixture'
            source.write_text(fixture, encoding='utf-8')
            subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)

    def test_hide_activity_by_type_and_delete_own_messages(self):
        core = read('submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift')
        self.assertIn('if let activity, BananaActivityHiding.hides(activity), !ForkGhostModeSettings.isException(accountPeerId: accountPeerId, peerId: peerId) {', core)
        hiding = read('submodules/TelegramCore/Sources/Arena/BananaActivityHiding.swift')
        self.assertIn('case .recordingVoice, .recordingInstantVideo:', hiding)
        self.assertIn('case .uploadingFile, .uploadingPhoto, .uploadingVideo, .uploadingInstantVideo:', hiding)
        # The group-call speaking indicator is never one of the hidden kinds.
        self.assertNotIn('speakingInGroupCall', hiding)
        ctl = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('(.ghost, [[1560, 1561, 1562], [1770, 1771, 1772]])', ctl)
        self.assertIn('BananaActivityHiding.update(text: settings.hideTypingText', read('submodules/TelegramUI/Sources/SharedAccountContext.swift'))
        own = read('submodules/ChatListUI/Sources/BananaDeleteOwnMessages.swift')
        self.assertIn('fromId: accountPeerId', own)
        self.assertIn('type: .forEveryone', own)
        self.assertIn('BananaDeleteOwnMessages.isGroup(peer)', read('submodules/ChatListUI/Sources/ChatContextMenus.swift'))

    def test_mutual_contact_row_range_selection_and_video_to_voice(self):
        items = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift')
        # The row sits directly under id, before dc, and never shows for the account itself or a bot.
        self.assertLess(items.index('fork_profile_id'), items.index('fork_mutual_contact'))
        self.assertLess(items.index('fork_mutual_contact'), items.index('fork_dc'))
        self.assertIn('case let .user(user)? = data.peer, user.id != context.account.peerId, user.botInfo == nil', items)
        self.assertIn('user.flags.contains(.mutualContact)', items)
        menu = read('submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift')
        self.assertIn('if let selectionState = self.presentationInterfaceState.interfaceState.selectionState {', menu)
        self.assertIn('withToggledSelectedMessages(rangeIds, value: true)', menu)
        ctx = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('forkVideoToVoice(context: context, fileReference:', ctx)
        self.assertIn('file.isVideo, !file.isAnimated', ctx)
        conv = read('submodules/TelegramUI/Components/AttachmentFileController/Sources/ForkAudioToVoice.swift')
        self.assertIn('"video/mp4": "mp4"', conv)
        self.assertIn('public func forkVideoToVoice', conv)

    def test_profile_action_buttons_are_glass_capsules_in_the_branded_themes(self):
        button = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderButtonNode.swift')
        # Radius is half the height (a capsule) for the mask, the rim and the context-menu source alike.
        self.assertIn('let capsuleRadius = backgroundFrame.height * 0.5', button)
        self.assertNotIn('min(16.0, backgroundFrame.height * 0.5)', button)
        self.assertIn('cornerRadius: capsuleRadius)', button)
        self.assertIn('glassEdgeView.layer.borderWidth = UIScreenPixel', button)
        header = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift')
        # Both profile-colour paths (star gift and ordinary profile colour) use the light veil in BananaGram themes.
        self.assertEqual(header.count('presentationData.theme.bananaGramReference != nil'), 2)

    def test_branded_themes_draw_profile_action_glyphs_as_system_symbols(self):
        button = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderButtonNode.swift')
        self.assertIn('let usesSystemSymbols = presentationData.theme.bananaGramReference != nil', button)
        for symbol in ('bubble.left', 'phone', 'video', 'person.crop.circle.badge.plus', 'magnifyingglass', 'stop.circle'):
            self.assertIn('symbolName = "%s"' % symbol, button)
        # The bundled artwork stays as the fallback for other themes and for a symbol the system lacks.
        self.assertIn('} else if let imageName = imageName, let image = generateTintedImage(image: UIImage(bundleImageName: imageName)', button)


    def test_chat_files_are_imported_as_sandbox_copies(self):
        # The Telegram 13 merge dropped `mode: .import` here, so the picker handed back security-scoped
        # URLs and a bookmark that could not be resolved when the upload ran: files never left the chat.
        menu = read('submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift')
        self.assertIn('legacyICloudFilePicker(theme: strongSelf.presentationData.theme, mode: .import, hasMultiselection: !editingMessage, documentTypes: documentTypes,', menu)
        poll = read('submodules/TelegramUI/Components/ComposePollScreen/Sources/PollAttachmentScreen.swift')
        self.assertIn('legacyICloudFilePicker(theme: presentationData.theme, mode: .import, documentTypes: ["public.item"]', poll)


    def test_background_handler_trims_cached_data_contexts(self):
        app = read('submodules/TelegramUI/Sources/AppDelegate.swift')
        i = app.index('cleared postbox caches on background')
        window = app[i - 1800:i]
        self.assertIn('context.account.postbox.clearCaches()', window)
        self.assertIn('context.account.trimCachedData()', window)

    def test_log_findings_background_work_is_bounded(self):
        # Device logs: three overlapping cleanup tasks each reindexed every media item (~4 GB written a day),
        # and a build without StoreKit products asked the store every 10 seconds for two days.
        app = read('submodules/TelegramUI/Sources/AppDelegate.swift')
        self.assertIn('if self.cleanupTaskRunning.swap(true) {', app)
        self.assertEqual(app.count('self.cleanupTaskRunning.swap(false)'), 3)
        # Device log 2026-10-16/17: five full passes a day; one per 20 hours is enough.
        self.assertIn('last.intValue >= now - 20 * 60 * 60', app)
        self.assertIn('UserDefaults.standard.set(now as NSNumber, forKey: backgroundIndexKey)', app)
        self.assertLess(app.index('forKey: backgroundIndexKey)'), app.index('Executing cleanup task'))
        iap = read('submodules/InAppPurchaseManager/Sources/InAppPurchaseManager.swift')
        self.assertIn('min(10.0 * pow(2.0, Double(min(self.productRequestRetryCount, 7))), 900.0)', iap)
        self.assertIn('self.productRequestRetryCount = 0', iap)
        picker = read('submodules/LegacyMediaPickerUI/Sources/LegacyICloudFilePicker.swift')
        self.assertIn('source: "cancel"', picker)


    def test_call_start_ignores_a_repeat_tap_while_callkit_answers_slowly(self):
        # Device log 19:19: CallKit answered a start 10 s late, the user tapped Call again after 1.4 s and the
        # second tap orphaned the first start. One pending start per peer, and a 1 s watchdog (CallKit
        # performs the action within 10-200 ms when it is healthy).
        src = read('submodules/TelegramCallsUI/Sources/CallKitIntegration.swift')
        start = src.split('func startCall(context: AccountContext, peerId: EnginePeer.Id, phoneNumber: String?, isVideo: Bool', 1)[1]
        self.assertIn('self.currentStartCallAccount != nil, self.currentStartCallPeerId == peerId, CACurrentMediaTime() - self.currentStartCallTimestamp < 6.0', start)
        self.assertLess(start.index('ignoring a repeated start call'), start.index('let uuid = UUID()'))
        self.assertIn('Queue.mainQueue().after(1.0, {\n            fallBack("perform action did not arrive in time")', start)
        self.assertEqual(src.count('self.currentStartCallPeerId = nil'), 2)


    def test_wallet_server_state_requests_respect_the_failure_cooldown(self):
        # Device log: 764 refused wallet.getState calls in 38 h (148 in one hour) because every foreground,
        # network or account event called requestServerWalletState ahead of the retry delay.
        src = read('submodules/WalletContext/Sources/WalletContextImpl.swift')
        request = src.split('func requestServerWalletState(forceRefreshAfterCurrent: Bool = false) {', 1)[1].split('private func performServerWalletStateRequest', 1)[0]
        self.assertIn('!forceRefreshAfterCurrent', request)
        self.assertIn('CFAbsoluteTimeGetCurrent() - self.serverStateLastFailureTimestamp < self.serverStateCooldown() - 0.5', request)
        self.assertIn('self.scheduleServerStateRetry()', request)
        cooldown = src.split('func serverStateCooldown() -> TimeInterval {', 1)[1].split('func requestServerWalletState', 1)[0]
        self.assertIn('self.walletScreenCount > 0 ? base : min(base * 4.0, 900.0)', cooldown)
        self.assertIn('self.serverStateLastFailureTimestamp = CFAbsoluteTimeGetCurrent()', src)
        self.assertIn('let delaySeconds = self.serverStateCooldown()', src)


    def test_untrusted_numbers_and_names_cannot_trap_or_bloat(self):
        settings = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        self.assertNotIn('Int32(UserDefaults.standard.integer', settings)
        self.assertEqual(settings.count('Int32(clamping: UserDefaults.standard.integer'), 2)
        processor = read('submodules/BananaLinkDownloader/Sources/BananaMediaProcessor.swift')
        self.assertIn('guard width.isFinite, height.isFinite, width >= 1.0, height >= 1.0, width <= 65535.0, height <= 65535.0 else {', processor)
        chat = read('submodules/TelegramUI/Sources/ChatController+BananaLinkDownload.swift')
        self.assertNotIn('Int32(video.', chat)
        self.assertNotIn('Int32(photo.', chat)
        self.assertNotIn('Int32(thumbnail.', chat)
        audio = read('submodules/TelegramUI/Components/AttachmentFileController/Sources/ForkAudioToVoice.swift')
        self.assertIn('let isPlainExtension = ', audio)
        self.assertIn('private let forkMaximumVoiceSeconds = 3600', audio)
        self.assertIn('totalBytes > forkMaximumVoiceSeconds * 96000', audio)
        self.assertIn('size <= 64 * 1024 * 1024', audio)


if __name__ == '__main__':
    unittest.main()
