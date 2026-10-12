"""Execute production audio permissions and rich-page text traversal in Swift."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding='utf-8')

def execute(source):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / 'main.swift'
        executable = pathlib.Path(directory) / 'fixture'
        path.write_text(source, encoding='utf-8')
        subprocess.run(['swiftc', str(path), '-o', str(executable)], check=True, timeout=120)
        subprocess.run([str(executable)], check=True, timeout=30)

class AudioRichText(unittest.TestCase):
    def test_conversion_send_rechecks_permissions(self):
        picker = read('submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift')
        body = picker.split('let sendResults:', 1)[1].split('func forkCanSendVoiceMessages()', 1)[0]
        guard = 'guard voiceFiles.isEmpty || strongSelf.forkCanSendVoiceMessages() else'
        self.assertEqual(body.count(guard), 2)
        self.assertLess(body.index(guard), body.index('messages.append('))
        paid = body.split('presentPaidMessageAlertIfNeeded', 1)[1]
        self.assertLess(paid.index(guard), paid.index('strongSelf.sendMessages('))
        menu = read('submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift')
        self.assertIn('import Postbox', menu)
        conversion = menu.split('forkVoiceToAudio(context:', 1)[1].split('})))', 1)[0]
        self.assertIn('context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))', conversion)
        self.assertLess(conversion.index('canSendAudioMessagesToPeer(peer, isVoice: false'), conversion.index('return enqueueMessages('))

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_audio_permission_policy(self):
        source = read('submodules/TelegramCore/Sources/Utils/CanSendMessagesToPeer.swift')
        function = source.split('public func canSendAudioMessagesToPeer', 1)[1].split('public func canSendReactionsToPeer', 1)[0]
        execute('''import Foundation
struct TelegramChatBannedRightsFlags: OptionSet {
 let rawValue: Int
 static let banSendVoice = Self(rawValue: 1)
 static let banSendMusic = Self(rawValue: 2)
}
struct Channel {
 let defaults: TelegramChatBannedRightsFlags
 let personal: TelegramChatBannedRightsFlags
 func hasBannedPermission(_ flag: TelegramChatBannedRightsFlags, ignoreDefault: Bool) -> (Int32, Bool)? {
   if personal.contains(flag) { return (1, false) }
   if !ignoreDefault && defaults.contains(flag) { return (1, true) }
   return nil
 }
}
struct Group { let flags: TelegramChatBannedRightsFlags; func hasBannedPermission(_ flag: TelegramChatBannedRightsFlags) -> Bool { flags.contains(flag) } }
enum EnginePeer { case channel(Channel), legacyGroup(Group), user, deleted }
func canSendMessagesToPeer(_ peer: EnginePeer, ignoreDefault: Bool) -> Bool { if case .deleted = peer { return false }; return true }
func canSendAudioMessagesToPeer''' + function + '''
for voice in [false, true] {
 let target: TelegramChatBannedRightsFlags = voice ? .banSendVoice : .banSendMusic
 let other: TelegramChatBannedRightsFlags = voice ? .banSendMusic : .banSendVoice
 precondition(!canSendAudioMessagesToPeer(.deleted, isVoice: voice))
 precondition(canSendAudioMessagesToPeer(.user, isVoice: voice))
 precondition(!canSendAudioMessagesToPeer(.legacyGroup(Group(flags: target)), isVoice: voice))
 precondition(canSendAudioMessagesToPeer(.legacyGroup(Group(flags: other)), isVoice: voice))
 precondition(!canSendAudioMessagesToPeer(.channel(Channel(defaults: target, personal: [])), isVoice: voice))
 precondition(canSendAudioMessagesToPeer(.channel(Channel(defaults: target, personal: [])), isVoice: voice, ignoreDefault: true))
 precondition(!canSendAudioMessagesToPeer(.channel(Channel(defaults: [], personal: target)), isVoice: voice, ignoreDefault: true))
}
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_rich_text_traversal_including_media_captions(self):
        source = read('submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift')
        cases = source.split('public indirect enum InstantPageBlock: PostboxCoding, Equatable {', 1)[1].split('public init(decoder:', 1)[0]
        traversal = source.split('    var fullPlainText: String {', 1)[1].split('    private static func blocksPlainText', 1)[0]
        execute('''import Foundation
struct RichText { let plainText: String; init(_ value: String) { plainText = value } }
typealias MediaId = Int
struct PixelDimensions {}
struct TelegramChannel { let title: String }
struct InstantPageCaption { let text: RichText; let credit: RichText }
struct InstantPageButtonRowAlignment {}
struct InstantPageButton { let text: RichText }
struct InstantPageTableCell { let text: RichText? }
struct InstantPageTableRow { let cells: [InstantPageTableCell] }
struct InstantPageRelatedArticle { let title: String?; let description: String?; let author: String? }
indirect enum InstantPageListItem { case text(RichText, String?, Bool?); case blocks([InstantPageBlock], String?, Bool?); case unknown }
indirect enum InstantPageBlock {''' + cases + '''}
struct InstantPage { let blocks: [InstantPageBlock]
var fullPlainText: String {''' + traversal + '''}
let caption = InstantPageCaption(text: RichText("caption"), credit: RichText("credit"))
let media: [InstantPageBlock] = [
 .image(id: 1, caption: caption, url: nil, webpageId: nil, spoiler: false),
 .video(id: 2, caption: caption, autoplay: false, loop: false, spoiler: false),
 .audio(id: 3, caption: caption), .document(id: 4, caption: caption),
 .webEmbed(url: nil, html: nil, dimensions: nil, caption: caption, stretchToWidth: false, allowScrolling: false, coverId: nil),
 .map(latitude: 0, longitude: 0, zoom: 0, dimensions: PixelDimensions(), caption: caption)
]
for block in media { precondition(InstantPage(blocks: [block]).fullPlainText == "caption\\ncredit") }
let nested: [InstantPageBlock] = [.cover(.collage(items: [.paragraph(RichText("inside"))], caption: caption)), .slideshow(items: [.heading(text: RichText("heading"), level: 1)], caption: caption)]
precondition(InstantPage(blocks: nested).fullPlainText == "inside\\ncaption\\ncredit\\nheading\\ncaption\\ncredit")
let extras: [InstantPageBlock] = [.blockQuote(blocks: [.paragraph(RichText("quote"))], caption: RichText("source"), collapsed: nil), .buttonRow(alignment: InstantPageButtonRowAlignment(), buttons: [InstantPageButton(text: RichText("button"))]), .relatedArticles(title: RichText("related"), articles: [InstantPageRelatedArticle(title: "article", description: "description", author: "author")])]
precondition(InstantPage(blocks: extras).fullPlainText == "quote\\nsource\\nbutton\\nrelated\\narticle\\ndescription\\nauthor")
precondition(InstantPage(blocks: [.divider, .anchor("hidden")]).fullPlainText.isEmpty)
print("Production rich text: media captions, nested blocks and visible text passed")
''')

if __name__ == '__main__':
    unittest.main()
