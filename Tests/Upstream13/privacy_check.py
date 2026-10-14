"""Check own-account privacy summaries using the production rule types and model."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODEL = 'submodules/SettingsUI/Sources/Privacy and Security/PrivacyCheckController.swift'
PARENT = 'submodules/SettingsUI/Sources/Privacy and Security/PrivacyAndSecurityController.swift'


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


class PrivacyCheckTests(unittest.TestCase):
    def test_entry_routes_every_result_to_its_existing_editor(self):
        parent = read(PARENT)
        self.assertIn('entries.append(.privacyCheck(', parent)
        routes = parent.split('arguments.openPrivacyCheck =', 1)[1].split('actionsDisposable.add', 1)[0]
        for subjects, action in [
            ('.phoneNumber, .phoneDiscovery', 'openPhoneNumberPrivacy'),
            ('.voiceCalls, .callP2P', 'openVoiceCallPrivacy'),
            ('.forwards', 'openForwardPrivacy'),
            ('.presence', 'openLastSeenPrivacy'),
            ('.profilePhoto', 'openProfilePhotoPrivacy'),
            ('.bio', 'openBioPrivacy'),
            ('.birthday', 'openBirthdayPrivacy'),
        ]:
            self.assertIn('case ' + subjects + ':\n                arguments.' + action + '()', routes)
        self.assertIn('privacySettingsPromise.set(.single(settings))', routes)

    def test_checker_only_reads_own_settings_and_handles_missing_results(self):
        source = read(MODEL)
        self.assertEqual(source.count('requestAccountPrivacySettings()'), 1)
        self.assertNotIn('URLSession', source)
        self.assertNotIn('Logger.', source)
        self.assertNotIn('UserDefaults', source)
        self.assertNotIn('updateAccount', source)
        self.assertIn('controller.dismissed =', source)
        self.assertIn('disposable.dispose()', source)
        request = source.split('let request =', 1)[1].split('disposable.set', 1)[0]
        self.assertLess(request.index('then(.single(nil))'), request.index('take(1)'))
        self.assertIn('timeout(12.0, queue: .mainQueue(), alternate: .single(nil))', request)
        self.assertIn('guard isActive, let controller else', source)
        self.assertIn('guard let settings else', source)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_privacy_model_preserves_exceptions_and_account_isolation(self):
        rules = read('submodules/TelegramCore/Sources/Settings/PrivacySettings.swift')
        rules = rules[rules.index('public enum SelectivePrivacySettings:'):rules.index('\nextension SelectivePrivacySettings {')]
        model = read(MODEL)
        model = model[model.index('enum PrivacyCheckSubject:'):model.index('// The check only requests')]
        fixture = '''import Foundation
public typealias PeerId = Int64
public struct SelectivePrivacyPeer: Equatable { public let value: Int }
public struct GlobalPrivacySettings: Equatable {}
''' + rules + '\n' + model + '''
func settings(_ rule: SelectivePrivacySettings, discovery: Bool) -> AccountPrivacySettings {
    return AccountPrivacySettings(presence: rule, groupInvitations: rule, voiceCalls: rule, voiceCallsP2P: rule,
        profilePhoto: rule, forwards: rule, phoneNumber: rule, phoneDiscoveryEnabled: discovery,
        voiceMessages: rule, bio: rule, birthday: rule, giftsAutoSave: rule, noPaidMessages: rule,
        savedMusic: rule, globalSettings: GlobalPrivacySettings(), accountRemovalTimeout: 0, messageAutoremoveTimeout: nil)
}
let peer: [PeerId: SelectivePrivacyPeer] = [123: SelectivePrivacyPeer(value: 123)]
let hidden = SelectivePrivacySettings.disableEveryone(enableFor: [:], enableForCloseFriends: false, enableForPremium: false, enableForBots: false)
precondition(privacyCheckAudience(hidden, russian: false) == "Nobody")
precondition(privacyCheckAudience(hidden, russian: true) == "Никто")
// None of the allow exceptions may be silently summarized as Nobody.
for mask in 1..<16 {
    let selected = SelectivePrivacySettings.disableEveryone(enableFor: mask & 1 != 0 ? peer : [:],
        enableForCloseFriends: mask & 2 != 0, enableForPremium: mask & 4 != 0, enableForBots: mask & 8 != 0)
    let en = privacyCheckAudience(selected, russian: false)
    let ru = privacyCheckAudience(selected, russian: true)
    precondition(en != "Nobody" && ru != "Никто")
    if mask & 2 != 0 { precondition(en.contains("close friends")) }
    if mask & 4 != 0 { precondition(en.contains("Premium")) }
    if mask & 8 != 0 { precondition(en.contains("bots")) }
}
for mask in 0..<16 {
    let contacts = SelectivePrivacySettings.enableContacts(enableFor: mask & 1 != 0 ? peer : [:],
        disableFor: mask & 2 != 0 ? peer : [:], enableForPremium: mask & 4 != 0, enableForBots: mask & 8 != 0)
    let summary = privacyCheckAudience(contacts, russian: false)
    precondition(summary.hasPrefix("Contacts"))
    if mask & 1 != 0 { precondition(summary.contains("additional exceptions")) }
    if mask & 2 != 0 { precondition(summary.contains("exclusions")) }
    if mask & 4 != 0 { precondition(summary.contains("Premium")) }
    if mask & 8 != 0 { precondition(summary.contains("bots")) }
}
precondition(privacyCheckAudience(.enableEveryone(disableFor: peer), russian: false).contains("exclusions"))
var first = settings(hidden, discovery: false)
first.voiceCallsP2P = .enableEveryone(disableFor: [:])
let firstRows = privacyCheckRows(settings: first, russian: false)
precondition(firstRows.count == PrivacyCheckSubject.allCases.count)
precondition(Set(firstRows.map { $0.subject.rawValue }).count == firstRows.count)
precondition(firstRows.first(where: { $0.subject == .phoneDiscovery })?.audience == "Contacts")
precondition(firstRows.first(where: { $0.subject == .callP2P })?.audience == "Everybody")
precondition(firstRows.first(where: { $0.subject == .voiceCalls })?.audience == "Nobody")
let second = settings(.enableEveryone(disableFor: [:]), discovery: true)
let secondRows = privacyCheckRows(settings: second, russian: false)
precondition(secondRows.first(where: { $0.subject == .phoneDiscovery })?.audience == "Everybody")
precondition(privacyCheckRows(settings: first, russian: false) == firstRows)
precondition(privacyCheckRows(settings: second, russian: true).allSatisfy { !$0.title.isEmpty && !$0.audience.isEmpty })
'''
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / 'main.swift'
            binary = pathlib.Path(directory) / 'privacy-check'
            source.write_text(fixture, encoding='utf-8')
            subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True, timeout=120)
            subprocess.run([str(binary)], check=True, timeout=30)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_modified_settings_ui_parses(self):
        for path in [MODEL, PARENT]:
            subprocess.run(['swiftc', '-frontend', '-parse', str(ROOT / path)], check=True, timeout=120)


if __name__ == '__main__':
    unittest.main()
