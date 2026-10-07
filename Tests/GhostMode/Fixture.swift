struct PeerId: Hashable {
    let value: Int64
    var namespace: Int32 { 0 }
    init(_ value: Int64) { self.value = value }
    func toInt64() -> Int64 { value }
}
struct MessageId {
    typealias Namespace = Int32
    let peerId: PeerId
    let namespace: Namespace
    let id: Int32
}
struct MessageIndex { let id: MessageId }
enum Namespaces {
    enum Peer { static let CloudUser: Int32 = 0; static let CloudGroup: Int32 = 1; static let CloudChannel: Int32 = 2 }
    enum Message { static let Cloud: Int32 = 0 }
}
enum ForkGhostModeSettings { static var suppressMessageReads = true }
struct Peer { var isForumOrMonoForum = false }
enum Operation { case Push, Validate }
enum PeerReadState: Equatable {
    case idBased(maxIncomingReadId: Int32, maxOutgoingReadId: Int32, maxKnownId: Int32, count: Int32, markedUnread: Bool)
    var isUnread: Bool {
        if case let .idBased(_, _, _, count, marked) = self { return count > 0 || marked }
        return false
    }
}
final class Transaction {
    var states: [PeerId: PeerReadState] = [:]
    var operations: [PeerId: Operation] = [:]
    var forum = false
    func getPeer(_ id: PeerId) -> Peer? { Peer(isForumOrMonoForum: forum) }
    func getPeerChatListIndex(_ id: PeerId) -> Int? { 1 }
    func getPeerReadStates(_ id: PeerId) -> [(Int32, PeerReadState)]? { states[id].map { [(Int32(0), $0)] } }
    func getPeerReadStateSynchronizationOperation(_ id: PeerId) -> Operation? { operations[id] }
    func setNeedsIncomingReadStateSynchronization(_ id: PeerId) { operations[id] = .Validate }
    func resetIncomingReadStates(_ values: [PeerId: [Int32: PeerReadState]]) {
        for (id, value) in values { states[id] = value[0]; operations[id] = nil }
    }
    func applyIncomingReadMaxId(_ id: MessageId) {
        if case let .idBased(read, outgoing, known, count, _)? = states[id.peerId] {
            states[id.peerId] = .idBased(maxIncomingReadId: max(read, id.id), maxOutgoingReadId: outgoing, maxKnownId: known, count: max(0, count - max(0, id.id - read)), markedUnread: false)
        }
    }
}
