"""Exercise nonblocking chat-list sync and notification update recovery."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "submodules/TelegramCore/Sources/State/FetchChatList.swift"
ACCOUNT_STATE_SOURCE = SOURCE.with_name("AccountStateManager.swift")
APPLICATION_SOURCE = ROOT / "submodules/TelegramUI/Sources/ApplicationContext.swift"

class WiringTests(unittest.TestCase):
    def test_missing_peer_does_not_wait_forever(self):
        source = SOURCE.read_text(encoding="utf-8")
        offset = source[source.index("let offset: Signal<"):source.index("\n        return offset\n")]
        self.assertEqual(offset.count("{"), offset.count("}"), "Extract complete offset block")
        self.assertNotIn("loadedPeerWithId", offset)
        self.assertIn("postbox.transaction", offset)
        self.assertIn("transaction.getPeer(upperBound.id.peerId)", offset)
        self.assertIn("resolvedChatListOffset(upperBound: upperBound", offset)

    def test_diagnostics_do_not_log_peer_ids_or_content(self):
        for name in ["FetchChatList.swift", "Holes.swift", "ResetState.swift"]:
            source = (SOURCE.parent / name).read_text(encoding="utf-8")
            lines = [line for line in source.splitlines() if 'Logger.shared.log("ChatListSync"' in line]
            self.assertTrue(lines)
            for line in lines:
                self.assertNotIn("peerId)", line)
                self.assertNotIn(".text", line)
                self.assertNotIn(".title", line)

    def test_only_nonempty_local_notification_batches_are_published(self):
        source = ACCOUNT_STATE_SOURCE.read_text(encoding="utf-8")
        start = source.index("let incomingNotificationIds = notificationMessageCandidates(")
        batch = source[start:source.index("let minReactionTimestamp", start)]
        self.assertIn("deleted: events.deletedMessageIds", batch)
        self.assertIn("for id in incomingNotificationIds", batch)
        self.assertIn("if let strongSelf = self, !messages.isEmpty", batch)
        self.assertIn("strongSelf.notificationMessagesPipe.putNext(messages)", batch)
        self.assertIn("guard !message.isLocallyDeleted", source)
        self.assertIn("$0.id != message.id && !$0.isLocallyDeleted", source)

    def test_foreground_notification_rechecks_deleted_messages_after_lookup(self):
        source = APPLICATION_SOURCE.read_text(encoding="utf-8")
        start = source.index("self.notificationMessagesDisposable.set")
        notifications = source[start:source.index("self.termsOfServiceUpdatesDisposable.set", start)]
        self.assertIn("guard !archiveNotificationShouldRedact(transaction: transaction,", notifications)
        self.assertIn("messages.compactMap { transaction.getMessage($0.id) }.filter { !$0.isLocallyDeleted && !TelegramShadowBan.isHidden($0) }", notifications)
        self.assertIn("currentFirstMessage.id == firstMessage.id", notifications)
        self.assertLess(notifications.index("currentFirstMessage.id == firstMessage.id"), notifications.index("playIncomingMessageSound()"))

    def test_standalone_poll_retries_stale_state_and_lets_too_long_fall_back(self):
        source = ACCOUNT_STATE_SOURCE.read_text(encoding="utf-8")
        start = source.index("        public func standalonePollDifference()")
        poll = source[start:source.index("        private func insertProcessEvents", start)]
        self.assertNotIn("preconditionFailure()", poll)
        self.assertIn(".single((nil, true))", poll.split("case .differenceTooLong:", 1)[1].split("default:", 1)[0])
        self.assertIn(".single((nil, false))", poll.split("if state.initialState.state != authorizedState", 1)[1])
        self.assertIn("return (nil, false)", poll.split("if replayedState != nil", 1)[1])
        self.assertIn("return isTerminalWithoutDifference", poll)


def run_swift():
    source = SOURCE.read_text(encoding="utf-8")
    start = source.index("func resolvedChatListOffset(")
    function = source[start:source.index("\n}", start) + 2]
    offset_start = source.index("        let offset: Signal<")
    offset_block = source[offset_start:source.index("\n        return offset\n", offset_start)]
    offset_source = "func loadOffset(postbox: Postbox, upperBound: MessageIndex) -> Signal<(Int32, Int32, Api.InputPeer), NoError> {\n" + offset_block + "\nreturn offset\n}"
    account_state = ACCOUNT_STATE_SOURCE.read_text(encoding="utf-8")
    start = account_state.index("func notificationMessageCandidates(")
    notification_candidates = account_state[start:account_state.index("\n}", start) + 2]
    fixture = r"""
import Foundation
struct PeerId: Hashable { var namespace: Int32 }
struct MessageId: Hashable { var peerId: PeerId; var id: Int32; var namespace: Int32 = 0 }
struct GlobalMessageIdsNamespace: Hashable { var peerIdNamespace: Int32; var messageIdNamespace: Int32 }
enum DeletedMessageId: Hashable { case global(Int32), messageId(MessageId) }
struct MessageIndex { var id: MessageId; var timestamp: Int32 }
enum Namespaces { enum Peer { static let Empty: Int32 = -1 } }
enum Api { enum InputPeer: Equatable { case inputPeerEmpty, user(Int64), channel(Int64), group(Int64) } }
struct Peer { var input: Api.InputPeer? }
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { return peer.input }
enum NoError: Error {}
struct Signal<T, E: Error> { var values: [T] }
func single<T, E: Error>(_ value: T, _ error: E.Type) -> Signal<T, E> { return Signal(values: [value]) }
struct Transaction { var peer: Peer?; func getPeer(_ id: PeerId) -> Peer? { return peer } }
struct Postbox {
    var peer: Peer?
    func transaction<T>(_ f: (Transaction) -> T) -> Signal<T, NoError> {
        return Signal(values: [f(Transaction(peer: peer))])
    }
}
struct Logger {
    static let shared = Logger()
    func log(_ category: String, _ message: String) {}
}
"""
    tests = r"""
let cursor = MessageIndex(id: MessageId(peerId: PeerId(namespace: 0), id: 456), timestamp: 123)
for peer in [nil, Peer(input: nil)] as [Peer?] {
    let signal = loadOffset(postbox: Postbox(peer: peer), upperBound: cursor)
    precondition(signal.values.count == 1, "Missing peer must emit, not suspend pagination")
    precondition(signal.values[0].0 == 123 && signal.values[0].1 == 456)
    let result = resolvedChatListOffset(upperBound: cursor, peer: peer)
    precondition(result.0 == 123 && result.1 == 456 && result.2 == .inputPeerEmpty)
}
for input in [Api.InputPeer.user(1), .channel(2), .group(3)] {
    let result = resolvedChatListOffset(upperBound: cursor, peer: Peer(input: input))
    precondition(result.0 == 123 && result.1 == 456 && result.2 == input)
}
let initial = MessageIndex(id: MessageId(peerId: PeerId(namespace: Namespaces.Peer.Empty), id: 1), timestamp: Int32.max)
let result = resolvedChatListOffset(upperBound: initial, peer: Peer(input: .user(1)))
precondition(result.0 == 0 && result.1 == 0 && result.2 == .inputPeerEmpty)
// Recovering the peer keeps the same date/id boundary and adds its input peer.
let recovered = resolvedChatListOffset(upperBound: cursor, peer: Peer(input: .channel(2)))
precondition(recovered.0 == cursor.timestamp && recovered.1 == cursor.id.id)
print("Chat list offsets: absent peer, unusable peer, initial page, users/groups/channels and recovery passed")

let globalPeer = PeerId(namespace: 0)
let channelPeer = PeerId(namespace: 2)
let globalNamespaces: Set<GlobalMessageIdsNamespace> = [GlobalMessageIdsNamespace(peerIdNamespace: 0, messageIdNamespace: 0)]
let globalDeletion = MessageId(peerId: globalPeer, id: 30)
let channelWithSameId = MessageId(peerId: channelPeer, id: 30)
let differentMessageNamespace = MessageId(peerId: globalPeer, id: 30, namespace: 1)
let exactDeletion = MessageId(peerId: channelPeer, id: 31)
precondition(notificationMessageCandidates(
    incoming: [globalDeletion, channelWithSameId, channelWithSameId, differentMessageNamespace, exactDeletion],
    deleted: [.global(30), .messageId(exactDeletion)],
    globalNamespaces: globalNamespaces
) == [channelWithSameId, differentMessageNamespace])
precondition(notificationMessageCandidates(incoming: [], deleted: [], globalNamespaces: globalNamespaces).isEmpty)
print("Notification candidates: deletions, namespace boundaries and duplicate IDs passed")
"""
    with tempfile.TemporaryDirectory(prefix="chat-list-sync-") as tmp:
        path = pathlib.Path(tmp) / "main.swift"
        path.write_text("\n\n".join([fixture, function, offset_source, notification_candidates, tests]), encoding="utf-8")
        subprocess.run(["swift", str(path)], check=True)
        for name in ["FetchChatList.swift", "Holes.swift", "ResetState.swift", "AccountStateManager.swift"]:
            subprocess.run(["swiftc", "-frontend", "-parse", str(SOURCE.parent / name)], check=True)
        subprocess.run(["swiftc", "-frontend", "-parse", str(APPLICATION_SOURCE)], check=True)

if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(WiringTests))
    if not result.wasSuccessful():
        sys.exit(1)
    if "--structural-only" not in sys.argv:
        run_swift()
