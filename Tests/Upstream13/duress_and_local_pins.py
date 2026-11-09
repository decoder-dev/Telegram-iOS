"""Duress passcode and panic shake (Vartagram, b7tg) and Pin Beyond the Limit (Forkgram, Nekogram): settings,
storage, the lock screen and chat list hooks, and the rows. Source-text checks; the Swift is verified by the Bazel build."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
DURESS = 'submodules/TelegramUIPreferences/Sources/DuressPasscode.swift'
HIDDEN = 'submodules/TelegramUIPreferences/Sources/HiddenAccountsSession.swift'
LOCAL_PINS = 'submodules/TelegramUIPreferences/Sources/LocalPinnedChats.swift'
KEYS = 'submodules/TelegramUIPreferences/Sources/PostboxKeys.swift'
ENTRY = 'submodules/PasscodeUI/Sources/PasscodeEntryController.swift'
APP_LOCK = 'submodules/AppLock/Sources/AppLock.swift'
ROOT_CONTROLLER = 'submodules/TelegramUI/Sources/TelegramRootController.swift'
SECURITY = 'submodules/SettingsUI/Sources/BananaSecurityController.swift'
DURESS_SCREEN = 'submodules/SettingsUI/Sources/DuressPasscodeController.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
CHAT_LIST_PINS = 'submodules/ChatListUI/Sources/Node/ChatListLocalPins.swift'
CHAT_LIST_NODE = 'submodules/ChatListUI/Sources/Node/ChatListNode.swift'
CONTEXT_MENUS = 'submodules/ChatListUI/Sources/ChatContextMenus.swift'

BOOL_FIELDS = ['panicShakeLock', 'pinBeyondLimit']


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def function(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start)]


class Settings(unittest.TestCase):
    def test_switches_are_declared_off_and_round_trip(self):
        source = read(SETTINGS)
        for name in BOOL_FIELDS:
            self.assertIn('    public var %s: Bool\n' % name, source)
            self.assertIn('        self.%s = false\n' % name, source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_duress_action_defaults_to_hiding_and_rejects_unknown_values(self):
        source = read(SETTINGS)
        self.assertIn('        self.duressPasscodeAction = 0\n', source)
        self.assertIn('        self.duressLogOutAccountIds = []\n', source)
        self.assertIn('self.duressPasscodeAction = (0 ... 2).contains(decodedDuressAction) ? decodedDuressAction : 0', source)
        self.assertIn('try container.encode(self.duressPasscodeAction, forKey: "duressPasscodeAction")', source)
        self.assertIn('try container.encode(self.duressLogOutAccountIds, forKey: "duressLogOutAccountIds")', source)
        self.assertIn('case hideSecrets = 0', read(DURESS))


class DuressPasscode(unittest.TestCase):
    def test_only_a_pbkdf2_verifier_is_kept_in_the_keychain(self):
        source = read(DURESS)
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', source)
        self.assertIn('makeLocalSecretVerifier(self.normalized(code, kind: kind))', source)
        self.assertIn('guard let record = self.load(), record.kind == kind else', source)
        self.assertNotIn('UserDefaults', source)
        keychain = read('submodules/TelegramUIPreferences/Sources/ArchivePasswordKeychain.swift')
        self.assertIn('func makeLocalSecretVerifier(_ secret: String) -> String? {\n    return makePBKDF2StoredBlob(password: secret)', keychain)

    def test_lock_screen_checks_the_real_passcode_first(self):
        source = read(ENTRY)
        verify = source[source.index('    private func verifyCode(_ code: String) {'):source.index('    func requestBiometricsBeforePresentation(')]
        self.assertIn('let acceptsDuressPasscode = self.authenticated == nil && self.completed == nil && self.applicationBindings.isMainApp', verify)
        real = verify.index('PasscodeCredentialStore.shared.verify(code, reference: reference, scope: scope, lifetime: lifetime)')
        duress = verify.index('DuressPasscodeKeychain.matches(code, kind: kind)')
        self.assertLess(real, duress)
        self.assertIn('(error as? PasscodeError) == .invalidCode', verify)
        self.assertIn('HiddenAccountsSession.shared.allowReveal()\n                            self.appLockContext.unlock()', verify)
        unlock = verify[verify.index('private func unlockWithDuressPasscode()'):]
        self.assertIn('performDuressPasscodeAction(accountManager: self.accountManager)', unlock)
        self.assertIn('appLockContext.unlock()', unlock)

    def test_actions_hide_first_and_never_touch_unchosen_accounts(self):
        perform = function(read(DURESS), 'public func performDuressPasscodeAction(')
        self.assertLess(perform.index('HiddenAccountsSession.shared.blockReveal()'), perform.index('accountManager.transaction'))
        self.assertIn('ArchiveLockSession.shared.relock()', perform)
        self.assertIn('records.map(\\.id).filter { chosen.contains($0.int64) }', perform)
        self.assertIn('alreadyLoggedOutRemotely: action == .eraseAll', perform)

    def test_reveal_stays_blocked_until_the_real_passcode(self):
        hidden = read(HIDDEN)
        self.assertIn('if !state.revealBlocked && state.owners.values.contains(ownerAccountId) {', hidden)
        self.assertIn('public func blockReveal()', hidden)
        self.assertIn('public func allowReveal()', hidden)
        gesture = read(ROOT_CONTROLLER)
        self.assertIn('if HiddenAccountsSession.shared.state.revealBlocked {\n                return\n            }', gesture)

    def test_duress_passcode_goes_with_the_passcode(self):
        source = read(APP_LOCK)
        self.assertIn('if strongSelf.isLockable && !accessChallengeData.data.isLockable {', source)
        self.assertIn('DuressPasscodeKeychain.clear()', source)

    def test_panic_shake_locks_and_hides_only(self):
        source = read(APP_LOCK)
        self.assertIn('window?.motionShake = { [weak self] in\n            self?.deviceShaken()\n        }', source)
        shaken = source[source.index('private func deviceShaken()'):source.index('private func hideKeyboardForPrivacyCover()')]
        self.assertIn('guard self.panicShakeEnabled else', shaken)
        self.assertIn('if self.recentShakeTimestamps.count < 3 {', shaken)
        self.assertIn('HiddenAccountsSession.shared.relock()', shaken)
        self.assertIn('self.lock()', shaken)
        self.assertNotIn('logout', shaken.lower())

    def test_setup_checks_the_passcode_throttled_and_confirms_with_it(self):
        source = read(DURESS_SCREEN)
        self.assertIn('try PasscodeCredentialStore.shared.verify(code, scope: .settings)', source)
        self.assertIn('fail(DuressPasscodeStrings.sameAsPasscode)', source)
        self.assertIn('settingsPasscodeSessionController(context: context, completion:', source)
        self.assertIn('ArchivePasswordKeychain.matchesPassword(code, peerId: $0)', source)
        self.assertIn('guard enteredKind == kind else', source)
        # Destructive choices ask first; hiding does not.
        self.assertIn('TextAlertAction(type: .destructiveAction, title: DuressPasscodeStrings.confirmAction, action: {', source)
        self.assertIn('guard hiddenState.listing(accountId: id) == .normal else', source)

    def test_rows_on_the_protection_screen(self):
        source = read(SECURITY)
        self.assertIn('pushControllerImpl?(duressPasscodeController(context: context))', source)
        self.assertIn('arguments.update(\\.panicShakeLock, value)', source)


class LocalPins(unittest.TestCase):
    def test_storage_is_per_account(self):
        keys = read(KEYS)
        self.assertIn('case localPinnedChats = 26', keys)
        self.assertEqual(len(re.findall(r'= 26\n', keys.split('private enum ApplicationSpecificSharedDataKeyValues', 1)[0])), 1)
        pins = read(LOCAL_PINS)
        self.assertIn('engine.preferences.update(id: ApplicationSpecificPreferencesKeys.localPinnedChats', pins)

    def test_limit_exceeded_pins_locally_and_unpin_is_local(self):
        source = read(CHAT_LIST_PINS)
        toggle = function(source, 'func toggleChatListItemPinned(')
        self.assertIn('guard case .group(.root) = location, case let .peer(peerId) = itemId else', toggle)
        self.assertIn('if !settings.pinBeyondLimit {', toggle)
        self.assertIn('case .limitExceeded:\n                update = { current in\n                    return [peerId] + current.filter { $0 != peerId }', toggle)
        self.assertIn('if localPinnedPeerIds.contains(peerId) && !serverPinnedItemIds.contains(itemId) {', toggle)
        self.assertIn('toggleChatListItemPinned(context: context, location: location, itemId: itemId)', read(CHAT_LIST_NODE))
        menus = read(CONTEXT_MENUS)
        self.assertIn('toggleChatListItemPinned(context: context, location: location, itemId: .peer(peerId))', menus)
        self.assertIn('let isPinned = pinnedItemIds.contains(.peer(peerId)) || isPinnedLocally', menus)

    def test_local_pins_sit_under_server_pins_once(self):
        merge = function(read(CHAT_LIST_PINS), 'func chatListNodeViewUpdateWithLocalPins(')
        self.assertIn('if localPinnedItems.isEmpty || update.list.hasLater {', merge)
        self.assertIn('nextPinningIndex = max(nextPinningIndex, pinningIndex + 1)', merge)
        self.assertIn('!serverPinnedPeerIds.contains(index.messageIndex.id.peerId)', merge)
        self.assertIn('items.sort(by: { $0.index < $1.index })', merge)
        node = read(CHAT_LIST_NODE)
        self.assertIn('if case .chatList = mode, location == .chatList(groupId: .root) {', node)
        self.assertIn('if showsLocalPins && listLocation.filter == nil {', node)
        self.assertIn('if case .group(.root) = location, !itemIds.contains(itemId) {\n                                return .single(false)', node)

    def test_vanished_chats_are_dropped(self):
        items = function(read(CHAT_LIST_PINS), 'func localPinnedChatListItems(')
        self.assertIn('if !isEnabled || peerIds.isEmpty {', items)
        self.assertIn('TelegramEngine.EngineData.Item.Messages.ChatListGroup.init(id:)', items)
        self.assertIn('if case .root? = groups[peerId] ?? nil {', items)
        self.assertIn('updateLocalPinnedChatIds(engine: engine', items)

    def test_row_uses_its_id_block_on_the_chat_list_page(self):
        source = read(EXTRAS)
        chat_list = re.search(r'\(\.chatList, \[(.*?)\]\),\n', source, re.S).group(1)
        self.assertIn('[2420, 2421]', chat_list)
        self.assertIn('.appearanceToggle(2420, russian ? "Закреплять сверх лимита" : "Pin Beyond the Limit", settings.pinBeyondLimit, \\.pinBeyondLimit)', source)
        self.assertEqual(len(re.findall(r'\.\w+\(242[01],', source)), 2)


if __name__ == '__main__':
    unittest.main()
