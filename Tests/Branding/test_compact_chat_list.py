"""Compact Chat List and Compact Message Preview give a chat row one line of text under the title. The row is centred in
its height, the archive row is compact too, and nothing that needs a second line (author, draft, forum topic, folder
tags) is drawn below the row. Source-text checks; the layout itself is looked at in simulator QA ("compact-" shots)."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ITEM = ROOT / 'submodules/ChatListUI/Sources/Node/ChatListItem.swift'
UI_TEST = ROOT / 'submodules/TelegramUI/Sources/UITestScreens.swift'
QA = ROOT / '.github/workflows/simulator-qa.yml'


class CompactChatListTests(unittest.TestCase):
    def setUp(self):
        self.text = ITEM.read_text(encoding='utf-8')

    def test_either_setting_makes_one_line(self):
        self.assertIn('let singleLinePreview = compactChatList || compactMessagePreview', self.text)
        self.assertIn('if singleLinePreview {\n                useInlineAuthorPrefix = true', self.text)
        self.assertIn('if !itemTags.isEmpty || singleLinePreview {\n                authorAttributedString = nil', self.text)
        self.assertIn('if singleLinePreview, !forumThreads.isEmpty {', self.text)
        # No "You:" in front of your own message in a one-to-one chat, as in the regular row.
        self.assertIn('if !(singleLinePreview && isOneToOne) {', self.text)

    def test_no_second_line_below_the_row(self):
        # Folder tags sit on a line under the text and drafts on an author line; both go in a one-line row.
        self.assertIn('itemTags = singleLinePreview ? [] : peerData.tags', self.text)
        self.assertIn('if !itemTags.isEmpty || singleLinePreview {\n                            let tempAttributedText = foldLineBreaks(draftText)', self.text)
        # A group's inline author prefix in a compact row does not hide its draft.
        self.assertIn('let draftAllowed = inlineAuthorPrefix == nil || (singleLinePreview && !isGroupReferenceRow)', self.text)
        media_draft = self.text.split('if draftAllowed, let mediaDraftContentType {', 1)[1].split('} else if draftAllowed, let draftState', 1)[0]
        self.assertIn('if singleLinePreview {', media_draft)
        self.assertIn('authorAttributedString = nil', media_draft)

    def test_row_is_centred_and_archive_is_compact(self):
        self.assertIn('let singleLineContentHeight = titleLayout.size.height + ceil(textFont.lineHeight)', self.text)
        self.assertIn('itemHeight = singleLineContentHeight + contentTopInset * 2.0', self.text)
        self.assertIn('} else if case .groupReference = item.content {\n                    isSingleLineRow = true', self.text)
        self.assertIn('y: layoutOffset + contentTopInset + contentVerticalOffset', self.text)
        self.assertIn('isSingleLineRow ? singleLineAccessoryOffset :', self.text)
        # The old height reserved a title-font line for 15 pt text and left the text above the row's centre.
        self.assertNotIn('titleLayout.size.height + measureLayout.size.height + titleSpacing + 21.0 - 3.0', self.text)

    def test_simulator_qa_covers_compact(self):
        self.assertIn('"--ui-test-compact"', UI_TEST.read_text(encoding='utf-8'))
        qa = QA.read_text(encoding='utf-8')
        self.assertIn('${QA_ARGS:-}', qa)
        for shot in ('capture compact day "$target"', 'capture compact-xl day chats', 'capture compact-preview day chats', 'capture compact-all day chats'):
            self.assertIn(shot, qa)


if __name__ == '__main__':
    unittest.main()
