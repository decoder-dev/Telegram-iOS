"""Read All (Donutgram), API ID in Devices and group join date (Swiftgram), a person's messages in groups
(Regram/64Gram): settings, Extras rows and the runtime hooks. Source-text checks; the Swift is built in CI."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
CHAT_LIST = 'submodules/ChatListUI/Sources/ChatListController.swift'
READ_ALL = 'submodules/ChatListUI/Sources/ChatListReadAllChats.swift'
READ_ALL_CORE = 'submodules/TelegramCore/Sources/Arena/BananaReadAllChats.swift'
LOCAL_READ = 'submodules/TelegramCore/Sources/Arena/BananaGhostLocalRead.swift'
SIMPLE_SETTINGS = 'submodules/TelegramCore/Sources/Settings/TelegramSimpleSettings.swift'
SESSION_ITEM = 'submodules/SettingsUI/Sources/Privacy and Security/Recent Sessions/ItemListRecentSessionItem.swift'
SESSIONS = 'submodules/SettingsUI/Sources/Privacy and Security/Recent Sessions/RecentSessionsController.swift'
PROFILE_ITEMS = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift'
PEER_INFO = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift'
COMMON_GROUPS = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoCommonGroupMessages.swift'
MEMBER_CORE = 'submodules/TelegramCore/Sources/Arena/BananaMemberMessages.swift'

FIELDS = [('showSessionApiId', 'true'), ('showGroupJoinDate', 'false'), ('showMessagesFromMember', 'false')]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def page(text, focus):
    body = text.split('private func forkExtrasControllerEntries(', 1)[1]
    start = body.index('\n    case .%s:\n        entries = [\n' % focus)
    return body[start:body.index('\n        ]\n', start)]


class Settings(unittest.TestCase):
    def test_fields_round_trip_with_their_defaults(self):
        source = read(SETTINGS)
        for name, default in FIELDS:
            self.assertIn('    public var %s: Bool\n' % name, source)
            self.assertIn('        self.%s = %s\n' % (name, default), source)
            self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? %s' % (name, name, default), source)
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)


class ExtrasRows(unittest.TestCase):
    def test_rows_use_the_assigned_range_and_pages(self):
        source = read(EXTRAS)
        privacy = page(source, 'privacy')
        profile = page(source, 'profile')
        self.assertIn('.appearanceToggle(2360, russian ? "API ID в «Устройствах»" : "API ID in Devices", settings.showSessionApiId, \\.showSessionApiId)', privacy)
        self.assertIn('.designFooter(2361,', privacy)
        self.assertIn('.appearanceToggle(2362, russian ? "Дата вступления в группу" : "Group Join Date", settings.showGroupJoinDate, \\.showGroupJoinDate)', profile)
        self.assertIn('settings.showMessagesFromMember, \\.showMessagesFromMember)', profile)
        self.assertIn('.designFooter(2364,', profile)
        self.assertIn('            [2360, 2361],\n', source)
        self.assertIn('            [2362, 2363, 2364],\n', source)
        ids = {int(value) for value in re.findall(r'\b(23[6-7]\d)\b', source)}
        self.assertEqual(ids, {2360, 2361, 2362, 2363, 2364})


class ReadAll(unittest.TestCase):
    def test_offered_from_the_chats_tab_and_the_all_chats_folder(self):
        self.assertEqual(read(CHAT_LIST).count('self?.presentReadAllChats()'), 2)

    def test_confirms_and_offers_both_modes(self):
        source = read(READ_ALL)
        self.assertIn('ActionSheetSwitchItem(title: russian ? "Включая архив" : "Include Archived Chats", isOn: false', source)
        self.assertIn('self?.readAllChats(includeArchived: includeArchived, onServer: true)', source)
        self.assertIn('self?.readAllChats(includeArchived: includeArchived, onServer: false)', source)
        # The sheet says that reading on the server goes past Ghost Mode.
        self.assertIn('if ForkGhostModeSettings.suppressMessageReads {', source)

    def test_server_reads_go_out_in_batches(self):
        source = read(READ_ALL)
        self.assertIn('let batchSize = 20', source)
        self.assertIn('engine.messages.togglePeersUnreadMarkInteractively(peerIds: batch, setToValue: false)', source)
        self.assertIn('read |> delay(1.0,', source)

    def test_server_list_includes_chats_read_only_here(self):
        core = read(READ_ALL_CORE)
        self.assertIn('groupIds.append(Namespaces.PeerGroup.archive)', core)
        self.assertIn('TelegramSimpleSettings.shared.ghostLocalReads(', core)
        self.assertIn('bananaApplyDeviceOnlyRead(transaction: transaction, accountPeerId: account.peerId, index: index)', core)

    def test_device_only_reads_outlive_ghost_mode(self):
        local = read(LOCAL_READ)
        self.assertIn('func bananaApplyDeviceOnlyRead(transaction: Transaction, accountPeerId: PeerId, index: MessageIndex) -> Bool', local)
        self.assertIn('if read.deviceOnly || (ForkGhostModeSettings.suppressMessageReads', local)
        self.assertIn('if isCovered || (!read.deviceOnly && (', local)
        self.assertIn('readCount: serverCount - count, deviceOnly: read.deviceOnly)', local)
        settings = read(SIMPLE_SETTINGS)
        self.assertIn('values.count == 5 || values.count == 6', settings)
        self.assertIn('deviceOnly: values.count == 6 && values[5] != 0', settings)
        self.assertIn('bananaApplyDeviceOnlyRead(', read('Tests/GhostMode/Checks.swift'))


class SessionApiId(unittest.TestCase):
    def test_item_shows_the_api_id_and_flags_unofficial_apps(self):
        item = read(SESSION_ITEM)
        self.assertIn('session: RecentAccountSession, showsApiId: Bool = false,', item)
        self.assertIn('if item.showsApiId && item.session.apiId != 0 {', item)
        self.assertIn('let isOfficial = item.session.flags.contains(.isOfficial)', item)
        self.assertEqual(read(SESSIONS).count('showsApiId: arguments.context.sharedContext.immediateForkExtrasSettings.showSessionApiId'), 3)


class GroupJoinDate(unittest.TestCase):
    def test_join_date_comes_from_cached_data(self):
        source = read(PROFILE_ITEMS)
        block = source[source.index('if forkExtras.showGroupJoinDate {'):]
        block = block[:block.index('\n    }\n')]
        self.assertIn('if case .member = channel.participationStatus, !channel.isMonoForum {', block)
        self.assertIn('(data.cachedData as? CachedGroupData)?.participants', block)
        self.assertIn('AnyHashable("fork_join_date")', block)


class MemberMessages(unittest.TestCase):
    def test_profile_entries_are_gated_and_open_the_search(self):
        source = read(PROFILE_ITEMS)
        self.assertIn('sourceGroupId: EnginePeer.Id? = nil', source)
        self.assertIn('if context.sharedContext.immediateForkExtrasSettings.showMessagesFromMember && user.id != context.account.peerId {', source)
        self.assertIn('activateMessageSearch: (.member(user), "")', source)
        self.assertIn('peerInfoCommonGroupMessagesController(context: context, user: EnginePeer(user))', source)
        self.assertIn('let sourceGroupId = self.reactionSourceMessageId == nil ? self.sourceMessageId?.peerId : nil', read(PEER_INFO))

    def test_common_groups_are_searched_one_at_a_time(self):
        core = read(MEMBER_CORE)
        self.assertIn('automaticFloodWait: false', core)
        self.assertIn('error.errorDescription.hasPrefix("FLOOD_WAIT") ? .floodWait : .generic', core)
        source = read(COMMON_GROUPS)
        self.assertIn('delay(Double.random(in: 0.4 ... 0.8), queue: Queue.mainQueue())', source)
        self.assertIn('state.stoppedOnFloodWait = true', source)
        self.assertIn('return lhs.timestamp > rhs.timestamp', source)


if __name__ == '__main__':
    unittest.main()
