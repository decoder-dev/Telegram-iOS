"""Exercise production Postbox draft mutation/expiration code without the database runtime."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / "submodules/Postbox/Sources/Postbox.swift").read_text(encoding="utf-8")

def method(marker):
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

fixture = r"""
import Foundation
import CoreFoundation
typealias PeerId = Int64
typealias MessageAttribute = Int
struct PeerAndThreadId: Hashable { let peerId: PeerId; let threadId: Int64? }
enum MessageId { typealias Namespace = Int32 }
final class Metadata {
    var index: UInt32 = 0
    func getNextStableMessageIndexId() -> UInt32 { index += 1; return index }
}
struct TypingDraft: Equatable {
    let id: Int64
    let namespace: Int32
    let stableId: UInt32
    let stableVersion: UInt32
    let threadId: Int64?
    let authorId: PeerId
    let timestamp: Int32
    let text: String
    let attributes: [MessageAttribute]
    let addedAtTimestamp: Double
}
struct TypingDraftUpdate { let value: TypingDraft? }
final class Box {
    var currentTypingDrafts: [PeerAndThreadId: TypingDraft] = [:]
    var currentUpdatedTypingDrafts: [PeerAndThreadId: TypingDraftUpdate] = [:]
    var stoppedTypingDrafts: [PeerAndThreadId: [Int64: Double]] = [:]
    let messageHistoryMetadataTable = Metadata()
""" + method("    fileprivate func combineTypingDrafts(") + "\n" + method("    private func processTypingDraftExpirations(").replace("private func", "func") + r"""
}
final class Transaction {
    let disposed = false
    let postbox: Box?
    init(_ box: Box) { self.postbox = box }
""" + method("    public func stopTypingDraft(").replace("public func", "func") + r"""
}
let box = Box()
let transaction = Transaction(box)
let key = PeerAndThreadId(peerId: 1, threadId: 42)
let allKey = PeerAndThreadId(peerId: 1, threadId: nil)
func put(_ id: Int64, _ text: String) {
    box.combineTypingDrafts(locations: [key, allKey]) { _, _ in
        return (id, 0, 42, 2, 100, text, [1])
    }
}
put(999, "partial")
transaction.stopTypingDraft(location: key, id: 999, keep: true, attributes: [])
put(999, "late packet")
precondition(box.currentTypingDrafts[key]?.text == "partial")
precondition(box.currentTypingDrafts[allKey]?.text == "partial")
precondition(box.currentTypingDrafts[key]?.attributes.isEmpty == true)
box.processTypingDraftExpirations(expirationTimeout: -1)
precondition(box.currentTypingDrafts[key] != nil, "keep_on_stop must retain content")
put(-9, "new generation")
transaction.stopTypingDraft(location: key, id: 999, keep: false, attributes: [])
precondition(box.currentTypingDrafts[key]?.id == -9, "An old stop must not remove a new generation")
box.processTypingDraftExpirations(expirationTimeout: 20)
precondition(box.currentTypingDrafts[key] != nil, "Fresh drafts must not expire")
box.processTypingDraftExpirations(expirationTimeout: -1)
precondition(box.currentTypingDrafts.isEmpty, "Expired drafts must be removed")
put(10, "remove on stop")
transaction.stopTypingDraft(location: key, id: 10, keep: false, attributes: [])
put(10, "late packet")
precondition(box.currentTypingDrafts.isEmpty, "Stopped drafts must not resurrect")
put(11, "next")
precondition(box.currentTypingDrafts.count == 2)
print("Streaming draft expiration, retention, stale-stop and late-packet checks passed")
"""
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "main.swift"
    path.write_text(fixture, encoding="utf-8")
    subprocess.run(["swift", str(path)], check=True)

# Parse touched integration sites too; full type checking happens in the IPA build.
subprocess.run(["swiftc", "-frontend", "-parse", *[str(root / p) for p in ['submodules/BrowserUI/Sources/BrowserMarkdown.swift', 'submodules/InstantPageUI/Sources/InstantPageAnchorPath.swift', 'submodules/InstantPageUI/Sources/InstantPageLayout.swift', 'submodules/InstantPageUI/Sources/InstantPageRenderer.swift', 'submodules/InstantPageUI/Sources/InstantPageTextItem.swift', 'submodules/InstantPageUI/Sources/InstantPageV2AudioContentNode.swift', 'submodules/InstantPageUI/Sources/InstantPageV2Layout.swift', 'submodules/InstantPageUI/Sources/InstantPageV2MediaViews.swift', 'submodules/Postbox/Sources/Postbox.swift', 'submodules/TelegramCore/Sources/Account/AccountIntermediateState.swift', 'submodules/TelegramCore/Sources/ApiUtils/InstantPage.swift', 'submodules/TelegramCore/Sources/ApiUtils/RichText.swift', 'submodules/TelegramCore/Sources/ApiUtils/TelegramMediaAction.swift', 'submodules/TelegramCore/Sources/ApiUtils/TypingDraftMessageAttribute.swift', 'submodules/TelegramCore/Sources/ChatInputContent/ChatInputContentInstantPage.swift', 'submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift', 'submodules/TelegramCore/Sources/State/ApplyUpdateMessage.swift', 'submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift', 'submodules/TelegramCore/Sources/SyncCore/SyncCore_RichText.swift', 'submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaAction.swift', 'submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift', 'submodules/TelegramCore/Sources/TelegramEngine/Payments/StarGifts.swift', 'submodules/TelegramCore/Sources/TelegramEngine/Payments/Stars.swift', 'submodules/TelegramStringFormatting/Sources/InstantPagePreviewText.swift', 'submodules/TelegramStringFormatting/Sources/ServiceMessageStrings.swift', 'submodules/TelegramUI/Components/Chat/ChatMessageGiftBubbleContentNode/Sources/ChatMessageGiftBubbleContentNode.swift', 'submodules/TelegramUI/Components/Chat/ChatMessageRichDataBubbleContentNode/Sources/ChatMessageRichDataBubbleContentNode.swift', 'submodules/TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift', 'submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift', 'submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift', 'submodules/TelegramUI/Sources/ChatController.swift', 'submodules/TelegramUI/Sources/ChatControllerContentData.swift', 'submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift', 'submodules/InstantPageUI/Sources/InstantPageDocumentPreviewController.swift']]], check=True)
