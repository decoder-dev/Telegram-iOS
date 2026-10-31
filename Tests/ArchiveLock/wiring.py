"""Structural checks for the Archive lock entry points. A merge once dropped these silently."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (root / path).read_text(encoding="utf-8")


chat_list = read("submodules/ChatListUI/Sources/ChatListController.swift")
group_selected = chat_list[chat_list.index("mainContainerNode.groupSelected = {"):chat_list.index("mainContainerNode.updatePeerGrouping = {")]
assert "ensureArchiveUnlocked(" in group_selected, "Tapping the Archive row must ask for the password"
preview = chat_list[chat_list.index("case let .groupReference(groupReference):"):]
preview = preview[:preview.index("case let .peer(peerData):")]
assert "ensureArchiveUnlocked(" in preview, "The Archive long-press preview must ask for the password"
assert "ArchiveLockSession.shared.relockedSignal" in chat_list, "An open Archive list must close on relock"
assert chat_list.count("markArchiveLockProtected(") >= 1, "Archive settings opened from the Archive must close on relock"

helpers = read("submodules/ChatListUI/Sources/ArchiveLockHelpers.swift")
assert "presentLostArchivePasswordRecovery(" in helpers, "A password no copy can verify must be recoverable"
assert "biometricsDomainState" in helpers, "Face ID unlock must reject a changed biometric enrollment"

keychain = read("submodules/TelegramUIPreferences/Sources/ArchivePasswordKeychain.swift")
assert re.search(r"elapsed = max\(0,", keychain), "A clock moved backwards must not extend the cooldown"
assert "CLOCK_MONOTONIC" in keychain and "lastFailureMonotonic" in keychain, "The cooldown must not be clearable by moving the clock forward"

service = read("Telegram/NotificationService/Sources/NotificationService.swift")
assert "stagedContent.redactLockedArchive(" in service, "Unredacted text must never be staged before the Archive check"


# Hidden accounts (HiddenAccountsSettings): an account with an Archive password hides other signed-in accounts. Every
# way an account is listed, opened or announced goes through the hidden check.
keys = read("submodules/TelegramUIPreferences/Sources/PostboxKeys.swift")
assert "case hiddenAccountsSettings = 24" in keys, "The hidden accounts live in the account manager's shared data"

account_utils = read("submodules/AccountUtils/Sources/AccountUtils.swift")
assert "HiddenAccountsSession.shared.stateSignal" in account_utils and "hiddenState.listing(accountId: accountId)" in account_utils, "The account list must leave hidden accounts out"
assert "hiddenSettings.isHidden(accountId)" in account_utils, "Before the session resolves, the stored settings decide"
assert "accountRecords.append((account, peer, 0))" in account_utils, "A revealed but locked account must not show its unread count"

shared = read("submodules/TelegramUI/Sources/SharedAccountContext.swift")
switch = shared[shared.index("public func switchToAccount(id: AccountRecordId"):shared.index("private func performSwitchToAccount(")]
assert "ensureHiddenAccountUnlocked(context: primary, owner: owner" in switch, "A hidden account opens with its owner's password"
assert "state.revealedOwnerId == ownerId" in switch, "Only the owner's Settings × 10 lets it be opened"
assert "HiddenAccountsSession.shared.unlock(accountId: id.int64)" in switch
assert "HiddenAccountsSession.shared.updateOwners(" in shared and ".isPasswordConfigured ? id.int64 : nil" in shared, "Only owners with a password hide anything"
assert "HiddenAccountsSession.shared.unlockAccounts(ownerAccountId:" in shared, "Opening the owner's Archive opens what it hides"
assert "state.isLocked(accountId: primary.account.id.int64)" in shared, "A locked hidden account on screen must be left"
assert "$0.0.int64 == ownerId" in shared, "Leaving a hidden account goes back to its owner"
assert "WidgetDataContext(basePath: self.basePath, inForeground: self.applicationBindings.applicationInForeground, activeAccounts: visibleAccountContexts" in shared, "Widgets must not see hidden accounts"
assert "accounts: combineLatest(enableSpotlight, visibleAccountContexts" in shared, "Spotlight must not index hidden accounts"
assert "updateHiddenAccountsSettings(accountManager: accountManager, { $0 })" in shared, "Entries of signed-out accounts are dropped"

session_source = read("submodules/TelegramUIPreferences/Sources/ChatArchiveSettings.swift")
relock = session_source[session_source.index("public func bindBackgroundRelock("):session_source.index("public func updateChatArchiveSettings(")]
assert "if !inForeground {\n                    HiddenAccountsSession.shared.relock()" in relock, "Hidden accounts close when the app goes to the background"
assert "keepingAccounts(liveAccountIds)" in session_source

assert "hiddenAccounts.isHidden(recordId.int64)" in service and "Account is hidden, showing nothing" in service, "A hidden account's push must show nothing"
assert "ApplicationSpecificSharedDataKeys.hiddenAccountsSettings" in service
app_delegate = read("submodules/TelegramUI/Sources/AppDelegate.swift")
assert "hiddenAccountIsLocked(accountManager: sharedContext.accountManager" in app_delegate, "CallKit must not name the caller of a hidden account"
call_manager = read("submodules/TelegramCallsUI/Sources/PresentationCallManager.swift")
assert "hiddenAccountIsLocked(accountManager: context.sharedContext.accountManager" in call_manager
share = read("submodules/TelegramUI/Components/ShareExtensionContext/Sources/ShareExtensionContext.swift")
assert "hiddenAccounts.isHidden(accountContext.account.id.int64)" in share, "The share extension must not offer a hidden account"

assert "if HiddenAccountsSession.shared.state.hiddenAccountIds.contains(context.account.id.int64)" in helpers, "The app switcher snapshot must not show a hidden account"
assert "passwordPeerId: peerId" in helpers
hide_toggle = helpers[helpers.index("public func setAccountHidden("):helpers.index("public func removeArchivePassword(")]
assert "verifyPassword: true" in hide_toggle, "Showing a hidden account again needs the owner's password"
assert "current.removingOwner(ownerId)" in helpers, "Removing the Archive password shows what it hid"

archive_settings = read("submodules/SettingsUI/Sources/ArchiveSettingsController.swift")
assert "setAccountHidden(context: context, hiddenAccount: hiddenAccount" in archive_settings, "The owner's Archive settings list the other accounts to hide"
assert "if hiddenSettings.isHidden(ownerId) {" in archive_settings, "A hidden account hides nobody"

root_controller = read("submodules/TelegramUI/Sources/TelegramRootController.swift")
assert "HiddenAccountsSession.shared.reveal(ownerAccountId: accountId)" in root_controller, "Settings × 10 reveals the accounts this one hides"

tab_actions = read("submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsTabActions.swift")
preview = tab_actions[tab_actions.index("func accountContextMenu("):tab_actions.index("var selectedAccount: Account?")]
assert "HiddenAccountsSession.shared.state.isLocked(accountId: id.int64)" in preview, "Long-pressing a locked hidden account must not preview its chats"
switch_row = tab_actions[tab_actions.index("func switchToAccount(id: AccountRecordId)"):tab_actions.index("self.accountsAndPeers.set(.never())")]
assert "HiddenAccountsSession.shared.state.isLocked(accountId: id.int64)" in switch_row, "A cancelled password must not leave the account list frozen"
logout = tab_actions[tab_actions.index("func logoutAccount(id: AccountRecordId)"):tab_actions.index("let presentationData = self.presentationData", tab_actions.index("func logoutAccount(id: AccountRecordId)"))]
assert "ensureHiddenAccountUnlocked(context: self.context, owner: owner" in logout, "Logging out a locked hidden account needs its owner's password"
intents = read("submodules/TelegramIntents/Sources/TelegramIntents.swift")
assert "hiddenAccounts.isHidden(account.id.int64)" in intents, "A hidden account must not donate chats to the share sheet and Siri suggestions"
assert "clearHiddenAccountTraces(context: hiddenAccount)" in hide_toggle, "Hiding an account removes its delivered notifications and donated chats"

# Search, mentions and the share sheet follow the open Archive; notifications, calls and Siri stay strict.
for path in [
    "submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift",
    "submodules/ChatListSearchRecentPeersNode/Sources/ChatListSearchRecentPeersNode.swift",
    "submodules/ShareController/Sources/SharePeersContainerNode.swift",
    "submodules/ShareController/Sources/ShareSearchContainerNode.swift",
    "submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/InputContextQueries.swift",
]:
    text = read(path)
    assert "archiveSearchShouldHide(transaction: transaction," in text, path
    assert "archiveNotificationShouldRedact(transaction: transaction," not in text, path + " must not hide chats of an open Archive"
assert "archiveNotificationShouldRedact(transaction: transaction, peerId: peerId)" in service, "Notifications keep the strict check"
for path in ["submodules/ContactListUI/Sources/ContactListNode.swift", "submodules/CallListUI/Sources/CallListControllerNode.swift"]:
    assert "if !configured || unlocked {" in read(path), path + " must show an open Archive's chats"
assert "accountPeerId: context.account.peerId, isPasswordConfigured:" in helpers, "The session must know its account to answer per-account unlock checks"

print("Archive lock entry points, recovery, biometrics, cooldown clamp, notification staging and hidden accounts: passed")
