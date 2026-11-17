"""Audit iteration 2 (docs/quality/full_app_audit.md): VoIP push completion, hidden accounts in Siri and the widget
picker, the settings-import protection prompt, the duress log-out of hidden accounts, document-picker lifetimes, the sticker-shape race, saved deleted media
copies and two outgoing-text-rule defects. Source-text checks; Swift builds in CI."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8').replace('\r\n', '\n')


class VoipPush(unittest.TestCase):
    def test_completion_waits_for_the_callkit_report(self):
        source = read('submodules/TelegramUI/Sources/AppDelegate.swift')
        body = source[source.index('    private func pushRegistryImpl('):]
        body = body[:body.index('\n    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor')]
        after = body[body.index('let phoneNumber = payloadJson["phoneNumber"] as? String'):]
        # From the point the call kind is known, nothing calls completion directly: only finishPush does.
        self.assertNotIn('                completion()\n', after)
        self.assertEqual(after.count('            completion()\n'), 1)
        # Both kinds of call finish the push right after reporting to CallKit.
        self.assertEqual(after.count('                        )\n                        finishPush()\n'), 2)
        # A resolve that never finishes still reports a call before giving the push back.
        self.assertIn('self.reportFailedIncomingCallKitCall()\n                finishPush()', after)
        self.assertTrue(body.rstrip().endswith('// `completion` runs from `finishPush`, once the call is reported (or given up on).\n    }'.rstrip()))


class HiddenAccounts(unittest.TestCase):
    def test_siri_and_widget_picker_skip_hidden_accounts(self):
        source = read('Telegram/SiriIntents/IntentHandler.swift')
        self.assertIn('self.allAccounts.set(combineLatest(accountRecords, hiddenAccounts)', source)
        self.assertIn('if hiddenAccounts.isHidden(record.id.int64) {\n                    continue', source)
        self.assertIn('return records.filter { !hiddenAccounts.isHidden($0.0.int64) }', source)
        self.assertNotIn('self.allAccounts.set(.single(', source)


class DuressLogOut(unittest.TestCase):
    def test_hidden_accounts_go_with_their_owner(self):
        source = read('submodules/TelegramUIPreferences/Sources/DuressPasscode.swift')
        body = source[source.index('        case .logOut:'):source.index('        case .eraseAll:')]
        # A logged-out owner drops out of the hidden-accounts map, which would show what it hid.
        self.assertIn('transaction.getSharedData(ApplicationSpecificSharedDataKeys.hiddenAccountsSettings)', body)
        self.assertIn('chosen.formUnion(hidden.hiddenAccountIds(ownerAccountId: ownerId))', body)
        self.assertLess(body.index('chosen.formUnion'), body.index('return (action, records.map'))
        strings = read('submodules/SettingsUI/Sources/DuressPasscodeController.swift')
        self.assertIn('together with the accounts they hide', strings)
        self.assertIn('the accounts you check and the accounts they hide', strings)


class SettingsImport(unittest.TestCase):
    def test_protective_switches_change_only_on_purpose(self):
        backup = read('submodules/SettingsUI/Sources/BananaSettingsBackup.swift')
        for key in ['instantPasscodeLock', 'panicShakeLock', 'confirmTelegramLinks', 'allowSecretScreenshots', 'streamerMode']:
            self.assertIn('"%s",' % key, backup)
        self.assertIn('return protectiveKeys.contains(key) || key.hasPrefix("security") || key.hasPrefix("ghost")', backup)
        settings = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        stored = set(re.findall(r'try container\.encode\(self\.\w+, forKey: "(\w+)"\)', settings))
        for key in ['instantPasscodeLock', 'panicShakeLock', 'confirmTelegramLinks', 'confirmShareLinks', 'allowSecretScreenshots', 'streamerMode', 'securityBlockQrLogin', 'ghostDontReadMessages']:
            self.assertIn(key, stored, key)
        about = read('submodules/SettingsUI/Sources/BananaAboutController.swift')
        self.assertIn('TextAlertAction(type: .destructiveAction, title: BananaAboutStrings.importAll', about)


class Lifetimes(unittest.TestCase):
    def test_document_picker_delegates_live_with_their_picker(self):
        for name in ['submodules/SettingsUI/Sources/ForkExtrasController.swift', 'submodules/SettingsUI/Sources/BananaAboutController.swift']:
            source = read(name)
            self.assertNotIn('static let shared = ForkExtrasMessageSavingImportPresenter()', source)
            self.assertNotIn('static let shared = BananaSettingsFilePicker()', source)
            self.assertIn('forkAttachDocumentPickerDelegate(picker, ', source)
        self.assertIn('objc_setAssociatedObject(picker, &forkDocumentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)', read('submodules/SettingsUI/Sources/ForkExtrasController.swift'))


class Races(unittest.TestCase):
    def test_sticker_shape_is_written_atomically(self):
        self.assertIn('BananaMediaTweaks.setStickerShape(settings.stickerShape)', read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift'))
        self.assertNotIn('mediaTweaks.stickerShape = ', read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift'))
        self.assertIn('let _ = state.modify { current in', read('submodules/TelegramCore/Sources/Arena/BananaMediaTweaks.swift'))


class SavedAttachments(unittest.TestCase):
    def test_copy_exists_before_the_original_is_deleted(self):
        source = read('submodules/TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift')
        body = source[source.index('static func scheduleCopy(message: Message, mediaBox: MediaBox) -> String? {'):]
        self.assertLess(body.index('if clonefile(source, dest.path, 0) == 0 {'), body.index('ioQueue.async {'))
        # Copies get a fresh date: the unreferenced-file sweep goes by it.
        self.assertEqual(source.count('markFresh(dest.path)'), 3)


class TextRules(unittest.TestCase):
    def test_anti_caps_counts_only_cased_letters(self):
        source = read('submodules/TelegramCore/Sources/PendingMessages/ForkOutgoingTextRules.swift')
        self.assertIn('guard casedLetters >= 4, uncasedLetters * 4 <= casedLetters else {', source)
        self.assertIn('guard Double(uppercase) / Double(casedLetters) >= 0.8 else {', source)

    def test_every_batch_takes_the_same_hop_while_rules_are_on(self):
        source = read('submodules/TelegramCore/Sources/PendingMessages/ForkOutgoingTextRules.swift')
        body = source[source.index('func forkApplyOutgoingTextRules('):]
        self.assertNotIn('hasText', body)
        self.assertLess(body.index('if state.isEmpty {'), body.index('return account.postbox.transaction'))


if __name__ == '__main__':
    unittest.main()
