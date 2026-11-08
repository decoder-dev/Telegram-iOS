"""Donutgram commits of 2026-10-31..11-07, ported: the grey band on a shared profile photo (7f969eda1b, edcb11ccb6),
"Hide AI features" (9b62a5089c, c96a7c82af, f77d1438b7), "Hide phone number in chat title" (9b62a5089c), "Don't
autoplay profile music" (9b62a5089c, f77d1438b7), "Show hidden admin badges" (69259e6c30), "Hide empty reply drafts"
(a657253b26; the chat list line only, not Donutgram's re-sort) and "Bypass sticker restrictions" (9b62a5089c,
ee069f97b3 and fixes). Source-text assertions; the Swift is verified by the full Bazel build."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


NL = '\n'
CONTROLLER = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
SHARED = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
HISTORY = 'submodules/TelegramUI/Sources/ChatHistoryListNode.swift'
BUBBLE = 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift'
TEXT_BUBBLE = 'submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift'
MENUS = 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift'
FLAGS = 'submodules/TelegramCore/Sources/Arena/ForkWhiteGramSettings.swift'

NEW_SWITCHES = {
    'hidePhoneNumberInChatTitle': 2032,
    'disableProfileMusicAutoplay': 2034,
    'showHiddenAdminBadges': 2036,
    'hideEmptyReplyDrafts': 2038,
    'bypassStickerRestrictions': 2040,
}


def body_after(source, start, end=NL + '    }' + NL):
    return source.split(start, 1)[1].split(end, 1)[0]


class SharedProfilePhoto(unittest.TestCase):
    def test_cloud_photo_data_is_not_reused_for_a_new_server_resource(self):
        source = read('submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift')
        body = body_after(source, 'private func canReusePhotoResourceData(', NL + '}' + NL)
        self.assertIn('fromResource.id != toResource.id', body)
        self.assertIn('CloudPeerPhotoSizeMediaResource', body)
        self.assertIn('CloudPhotoSizeMediaResource', body)
        self.assertEqual(source.count('canReusePhotoResourceData(from: from'), 2)

    def test_a_complete_file_of_another_encoding_is_decoded_whole(self):
        source = read('submodules/PhotoResources/Sources/PhotoResources.swift')
        helper = body_after(source, 'private func completePhotoResourceData(', NL + '}' + NL)
        self.assertIn('guard data.complete, data.size != progressiveSize else', helper)
        # The force unwrap is safe only inside the progressive branch, which needs more than one size.
        branch = source.split('let progressiveRepresentation = progressiveImageRepresentation(photoReference.media.representations), progressiveRepresentation.progressiveSizes.count > 1', 1)[1]
        branch = branch.split('if !forceThumbnail || photoReference.media.immediateThumbnailData == nil', 1)[0]
        self.assertIn('completePhotoResourceData(data, progressiveSize: Int64(progressiveRepresentation.progressiveSizes.last!))', branch)


class HideAIFeatures(unittest.TestCase):
    def test_the_input_panel_switch_names_all_ai_features(self):
        controller = read(CONTROLLER)
        self.assertIn('.appearanceToggle(2101, russian ? "Скрыть функции ИИ" : "Hide AI features", settings.hideAIButton, \\.hideAIButton)', controller)
        self.assertIn('With AI hidden, Copy takes the original text.', controller)

    def test_the_flag_is_projected_before_the_history_re_emits(self):
        self.assertIn('ForkAIFeaturesSettings.hidden = settings.hideAIButton', read(SHARED))
        history = read(HISTORY)
        mapping = history.split('let messageFilterSettings: Signal<MessageFilterSettingsFingerprint, NoError>', 1)[1].split('|> distinctUntilChanged', 1)[0]
        self.assertIn('ForkAIFeaturesSettings.hidden = settings.hideAIButton', mapping)
        self.assertIn('hidesAIFeatures: settings.hideAIButton', mapping)

    def test_bubbles_offer_and_show_no_summary_while_hidden(self):
        bubble = read(BUBBLE)
        self.assertIn('if !ForkAIFeaturesSettings.hidden, let _ = item.message.attributes.first(where: { $0 is SummarizationMessageAttribute }) {', bubble)
        self.assertEqual(bubble.count('!ForkAIFeaturesSettings.hidden && item.controllerInteraction.summarizedMessageIds.contains(item.message.id)'), 2)
        self.assertIn('!ForkAIFeaturesSettings.hidden && item.controllerInteraction.summarizedMessageIds.contains(item.message.id)', read(TEXT_BUBBLE))

    def test_copy_takes_the_original_text_while_hidden(self):
        menus = read(MENUS)
        self.assertEqual(menus.count('if !ForkAIFeaturesSettings.hidden, controllerInteraction.summarizedMessageIds.contains(message.id)'), 4)
        self.assertNotIn('if controllerInteraction.summarizedMessageIds.contains(message.id)', menus)

    def test_ai_compose_and_open_summaries_go_away(self):
        node = read('submodules/TelegramUI/Sources/ChatControllerNode.swift')
        self.assertIn('func openAICompose() {' + NL + '        guard !ForkAIFeaturesSettings.hidden else {', node)
        controller = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertIn('self.controllerInteraction?.summarizedMessageIds.removeAll()', controller)


class NewSwitches(unittest.TestCase):
    def test_each_switch_is_off_by_default_and_round_trips(self):
        source = read(SETTINGS)
        for name in NEW_SWITCHES:
            with self.subTest(name=name):
                self.assertIn('public var %s: Bool' % name, source)
                self.assertIn('self.%s = false' % name, source)
                self.assertIn('self.%s = try container.decodeIfPresent(Bool.self, forKey: "%s") ?? false' % (name, name), source)
                self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_each_switch_has_a_row_and_a_footer_in_a_block(self):
        controller = read(CONTROLLER)
        groups = controller.split('private static let regroupedCategories', 1)[1].split('private static let interfaceGroups', 1)[0]
        for name, row in NEW_SWITCHES.items():
            with self.subTest(name=name):
                self.assertIn('.appearanceToggle(%d, ' % row, controller)
                self.assertIn('settings.%s, \\.%s)' % (name, name), controller)
                if row == 2032:
                    # Hide phone number shares the Streamer Mode block and its footer (Apple HIG pass).
                    self.assertIn('[28, 2032, 29]', groups)
                    continue
                self.assertIn('.designFooter(%d, ' % (row + 1), controller)
                self.assertIn('%d, %d' % (row, row + 1), groups)


class HidePhoneNumberInChatTitle(unittest.TestCase):
    def test_title_uses_the_name_while_hidden(self):
        self.assertIn('ForkChatTitleSettings.hidesPhoneNumber = settings.hidePhoneNumberInChatTitle', read(SHARED))
        view = read('submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift')
        self.assertIn('self.hidesPhoneNumber = ForkChatTitleSettings.hidesPhoneNumber', view)
        self.assertIn('if lhs.hidesPhoneNumber != rhs.hidesPhoneNumber {', view)
        for path in ['submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift', 'submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift']:
            with self.subTest(path=path):
                source = read(path)
                self.assertIn('if !peerView.hidesPhoneNumber, !peerView.isContact, let user = peer as? TelegramUser', source)
                self.assertNotIn('if !peerView.isContact, let user = peer as? TelegramUser, !user.flags.contains(.isSupport), user.botInfo == nil, let phone = user.phone', source)


class ProfileMusicAutoplay(unittest.TestCase):
    def test_profile_opens_the_playlist_paused_when_asked(self):
        screen = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift')
        self.assertIn('let autoplays = !self.context.sharedContext.immediateForkExtrasSettings.disableProfileMusicAutoplay', screen)
        self.assertIn('type: .music, control: .playback(autoplays ? .play : .pause))', screen)

    def test_a_new_music_player_honours_a_pause(self):
        manager = read('submodules/TelegramUI/Sources/MediaManager.swift')
        body = manager.split('case .music, .file:', 1)[1].split('strongSelf.musicMediaPlayer?.stop()' + NL + '                            strongSelf.musicMediaPlayer = nil', 1)[0]
        self.assertIn('let initialControl = control', body)
        self.assertIn('if case .playback(.pause) = initialControl {', body)
        self.assertIn('strongSelf.musicMediaPlayer?.control(.playback(.pause))', body)


class HiddenAdminBadges(unittest.TestCase):
    def test_blank_titles_give_way_to_the_standard_badge(self):
        body = body_after(read(FLAGS), 'public static func visibleTitle(_ title: String?) -> String? {')
        self.assertIn('guard self.showsHiddenBadges, let title else {', body)
        self.assertIn('isDefaultIgnorableCodePoint', body)
        self.assertIn('scalar.value != 0x2800', body)
        self.assertIn('ForkAdminTitles.showsHiddenBadges = settings.showHiddenAdminBadges', read(SHARED))

    def test_bubbles_and_member_lists_use_it_for_admins_only(self):
        bubble = read(BUBBLE)
        self.assertIn('case let .creator(rank):' + NL + '                            if let rank = ForkAdminTitles.visibleTitle(rank), !rank.isEmpty {', bubble)
        self.assertIn('case let .admin(rank):' + NL + '                            if let rank = ForkAdminTitles.visibleTitle(rank), !rank.isEmpty {', bubble)
        members = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoMembers.swift')
        body = body_after(members, 'var forkDisplayRank: String? {')
        self.assertIn('case .creator, .admin:' + NL + '            return ForkAdminTitles.visibleTitle(self.rank)', body)
        self.assertIn('case .member:' + NL + '            return self.rank', body)
        pane = read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/Panes/PeerInfoMembersPane.swift')
        self.assertIn('displayRank: member.forkDisplayRank', pane)
        self.assertIn('lhsRank == rhsRank', pane)
        self.assertIn('if let rank = item.member.forkDisplayRank {', read('submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ListItems/PeerInfoScreenMemberItem.swift'))
        self.assertIn('showsHiddenAdminBadges: settings.showHiddenAdminBadges', read(HISTORY))


class EmptyReplyDrafts(unittest.TestCase):
    def test_a_bare_reply_is_recognised(self):
        source = read('submodules/TelegramCore/Sources/SyncCore/SyncCore_SynchronizeableChatInputState.swift')
        body = body_after(source, 'public var isEmptyReply: Bool {')
        self.assertIn('self.replySubject != nil && text.isEmpty && entities.isEmpty && self.messageEffectId == nil && self.suggestedPost == nil', body)

    def test_every_chat_list_draft_carries_the_flag(self):
        flagged = 'isEmptyReply: opaqueState.synchronizeableInputState?.isEmptyReply ?? false)'
        self.assertEqual(read('submodules/ChatListUI/Sources/Node/ChatListNodeLocation.swift').count(flagged), 3)
        self.assertEqual(read('submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift').count(flagged), 1)

    def test_the_chat_list_drops_the_draft_line_while_hidden(self):
        entries = read('submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift')
        self.assertIn('guard let draft, !(hideEmptyReplies && draft.isEmptyReply) else {', entries)
        self.assertEqual(entries.count('forkChatListDraftState('), 3)
        self.assertNotIn('ChatListItemContent.DraftState.init)', entries)
        node = read('submodules/ChatListUI/Sources/Node/ChatListNode.swift')
        self.assertIn('[settings.hideProxySponsor, settings.hideEmptyReplyDrafts]', node)
        self.assertIn('hideProxySponsor: hideProxySponsor, hideEmptyReplyDrafts: hideEmptyReplyDrafts)', node)


class StickerBypass(unittest.TestCase):
    def test_only_chats_that_ban_stickers_but_allow_videos_convert(self):
        source = read('submodules/TelegramCore/Sources/PendingMessages/ForkStickerMediaBypass.swift')
        body = source.split('public func forkCanSendStickerAsMedia(', 1)[1]
        self.assertIn('guard ForkStickerBypassSettings.enabled else {', body)
        self.assertIn('guard isBanned(.banSendStickers), !isBanned(.banSendMedia), !isBanned(.banReadMessages), !isBanned(.banSendVideos) else {', body)
        self.assertIn('if let file, !file.isSticker {', body)
        self.assertIn('ForkStickerBypassSettings.enabled = settings.bypassStickerRestrictions', read(SHARED))

    def test_the_sticker_ui_stays_and_the_send_converts(self):
        self.assertIn('if forkCanSendStickerAsMedia(peer: chatPresentationInterfaceState.renderedPeer?.peer) {' + NL + '                    stickersEnabled = true', read('submodules/TelegramUI/Sources/ChatInterfaceInputContexts.swift'))
        self.assertIn('if !stickersEnabled && !forkCanSendStickerAsMedia(peer: interfaceState.renderedPeer?.peer) {' + NL + '            stickerContent = nil', read('submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift'))
        controller = read('submodules/TelegramUI/Sources/ChatController.swift')
        self.assertIn('if strongSelf.forkIsConvertingSticker {' + NL + '                return false', controller)
        self.assertIn('!forkCanSendStickerAsMedia(peer: peer, file: fileReference.media)', controller)
        self.assertEqual(controller.count('shouldAnimateMessageTransition || sendsStickerAsMedia ? correlationId : nil'), 2)
        send = controller.split('func sendMessages(_ messages: [EnqueueMessage]', 1)[1].split('func enqueueMediaMessages(', 1)[0]
        self.assertIn('self.forkMessagesWithStickerMedia(outgoingMessages)', send)
        self.assertNotIn('enqueueMessages(account: self.context.account, peerId: peerId, messages: self.transformEnqueueMessages(messages, postpone: postpone))', send)

    def test_conversion_writes_a_silent_video_and_cleans_up(self):
        source = read('submodules/TelegramUI/Sources/ChatController+ForkStickerMedia.swift')
        self.assertNotIn('DGSimpleSettings', source)
        self.assertNotIn('dgLocalized', source)
        self.assertIn('.Video(duration: duration, size: PixelDimensions(size), flags: [.isSilent, .supportsStreaming]', source)
        self.assertIn('frameCount: 2, nextFrame: {' + NL + '            return (image, 0.5)', source)
        self.assertIn('EngineTempBox.shared.dispose(temporary)', source)
        self.assertIn('timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))', source)
        self.assertIn('func forkMessagesWithStickerMedia(_ messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {', source)


if __name__ == '__main__':
    unittest.main()
