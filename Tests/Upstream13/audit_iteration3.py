"""Audit iteration 3 (docs/quality/full_app_audit.md): the P2 defects left open by iteration 2. Hidden accounts' calls
in Siri suggestions and Phone Recents, the duress reveal block after a relaunch, configured widgets, the open chat after
Don't Read is turned off, saved media of a signed-out account and legacy attachment names, and the translators' API
keys. Source-text checks; Swift builds in CI."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8').replace('\r\n', '\n')


class HiddenAccountCalls(unittest.TestCase):
    def test_no_siri_donation_and_no_recents_while_hidden(self):
        callkit = read('submodules/TelegramCallsUI/Sources/CallKitIntegration.swift')
        start = callkit[callkit.index('    func startCall(context: AccountContext, peerId: EnginePeer.Id, phoneNumber: String?, localContactId: String?'):]
        start = start[:start.index('    func answerCall(uuid: UUID)')]
        self.assertIn('if HiddenAccountsSession.shared.state.owners[context.account.id.int64] == nil {\n            self.donateIntent(', start)
        self.assertIn('interaction.groupIdentifier = startCallIntentGroupIdentifier(accountId: accountId)', callkit)
        self.assertIn('providerConfiguration.includesCallsInRecents = includesCallsInRecents', callkit)
        self.assertIn('self.provider.configuration = CallKitProviderDelegate.providerConfiguration(includesCallsInRecents: !value)', callkit)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('CallKitIntegration.shared?.setKeepsCallsOutOfRecents(hasHiddenAccounts)', shared)
        self.assertIn('self.hiddenAccountCallRecentsDisposable.dispose()', shared)
        helpers = read('submodules/ChatListUI/Sources/ArchiveLockHelpers.swift')
        traces = helpers[helpers.index('private func clearHiddenAccountTraces(context: AccountContext) {'):]
        self.assertIn('deleteStartCallIntents(accountId: context.account.id.int64)', traces[:traces.index('\n}\n')])


class DuressRevealBlock(unittest.TestCase):
    def test_reveal_block_survives_a_relaunch(self):
        duress = read('submodules/TelegramUIPreferences/Sources/DuressPasscode.swift')
        self.assertIn('var revealBlocked: Bool?', duress)
        self.assertIn('public static func isRevealBlocked() -> Bool {', duress)
        hidden = read('submodules/TelegramUIPreferences/Sources/HiddenAccountsSession.swift')
        block = hidden[hidden.index('    public func blockReveal() {'):hidden.index('    /// The real passcode opened the app.')]
        self.assertIn('DuressPasscodeKeychain.setRevealBlocked(true)', block)
        allow = hidden[hidden.index('    public func allowReveal() {'):]
        self.assertIn('DuressPasscodeKeychain.setRevealBlocked(false)', allow[:allow.index('\n    }\n')])
        reveal = hidden[hidden.index('    public func reveal(ownerAccountId: Int64) -> Bool {'):]
        self.assertLess(reveal.index('if self.isRevealBlocked {'), reveal.index('self.update { state in'))
        self.assertIn('if HiddenAccountsSession.shared.isRevealBlocked {', read('submodules/TelegramUI/Sources/TelegramRootController.swift'))


class ConfiguredWidget(unittest.TestCase):
    def test_hidden_accounts_are_left_out(self):
        widget = read('Telegram/WidgetKitWidget/TodayViewController.swift')
        self.assertIn('import TelegramUIPreferences', widget)
        self.assertIn('combineLatest(friendsByAccount.filter { !hiddenAccounts.isHidden($0.0) }.map { $0.1 })', widget)
        self.assertNotIn('let _ = combineLatest(friendsByAccount).start(', widget)
        build = read('Telegram/BUILD')
        lib = build[build.index('    name = "WidgetExtensionLib",'):]
        lib = lib[:lib.index('\n)\n')]
        self.assertIn('"//submodules/TelegramUIPreferences:TelegramUIPreferences",', lib)


class GhostReadsTurnedOff(unittest.TestCase):
    def test_open_chat_reads_again_after_the_restore(self):
        sync = read('submodules/TelegramCore/Sources/State/ManagedSynchronizePeerReadStates.swift')
        restore = sync[sync.index('    private func updateGhostLocalReads() {'):]
        restore = restore[:restore.index('\n    }\n')]
        # Posted only once the restoring transaction is done: a read before it would be undone by it.
        self.assertLess(restore.index('bananaRestoreGhostLocalReads(transaction: transaction'), restore.index('}).start(completed: {'))
        self.assertIn('NotificationCenter.default.post(name: ForkGhostModeSettings.ghostLocalReadsRestoredNotification', restore)
        history = read('submodules/TelegramUI/Sources/ChatHistoryListNode.swift')
        manage = history[history.index('    private func beginReadHistoryManagement() {'):]
        manage = manage[:manage.index('self.canReadHistoryDisposable?.dispose()')]
        self.assertIn('self.holdsReadsForSender.get(), ghostLocalReadsRestored)', manage)
        self.assertIn('let _ = previousMaxIncomingMessageIndexByNamespace.swap([:])', manage)


class SavedMedia(unittest.TestCase):
    def test_signed_out_account_takes_its_saved_messages(self):
        store = read('submodules/TelegramUIPreferences/Sources/MessageSavingStore.swift')
        self.assertIn('public static func eraseAccount(accountPeerId: Int64) {', store)
        shared = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        removed = shared[shared.index('                for id in removedIds {'):]
        removed = removed[:removed.index('self.managedAccountDisposables.set(nil, forKey: id)')]
        self.assertIn('MessageSavingStore.eraseAccount(accountPeerId: removedPeerId.toInt64())', removed)
        # Not while the same user is still signed in under another record.
        self.assertIn('$0.0 != id && $0.1.account.peerId == removedPeerId', removed)

    def test_legacy_names_only_for_channels(self):
        source = read('submodules/TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift')
        lookup = source[source.index('    static func existingCopyPath(peerId: Int64'):]
        lookup = lookup[:lookup.index('\n    }\n')]
        self.assertLess(lookup.index('guard PeerId(peerId).namespace == Namespaces.Peer.CloudChannel else {'), lookup.index('legacyBaseName('))


class TranslatorKeys(unittest.TestCase):
    def test_keys_live_in_the_keychain(self):
        keys = read('submodules/TelegramUIPreferences/Sources/ForkTranslationAPIKeys.swift')
        self.assertIn('kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly', keys)
        self.assertIn('updated.deeplApiKey = ""', keys)
        self.assertIn('updated.yandexApiKey = ""', keys)
        backends = read('submodules/TranslateUI/Sources/ForkTranslationBackends.swift')
        self.assertNotIn('settings.deeplApiKey', backends)
        self.assertNotIn('settings.yandexApiKey', backends)
        extras = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertNotIn('updated[keyPath: keyPath] = value\n                    return updated\n                }.start()\n            }, action: {})', extras)
        self.assertIn('ForkTranslationAPIKeys.setKey(value, for: service)', extras)
        self.assertIn('ForkTranslationAPIKeys.migrateFromSettings(settings, accountManager: accountManager)', read('submodules/TelegramUI/Sources/SharedAccountContext.swift'))


if __name__ == '__main__':
    unittest.main()
