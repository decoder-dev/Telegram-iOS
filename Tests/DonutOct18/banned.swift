public struct PeerId: Hashable {
    let value: Int64
    func toInt64() -> Int64 { value }
}
public protocol Peer { var id: PeerId { get } }
enum Membership { case Member, Removed, Left }
enum GroupRole { case creator, admin, member }
enum Participation { case member, left, kicked }
struct GroupFlags: OptionSet {
    let rawValue: Int
    static let deactivated = GroupFlags(rawValue: 1)
}
struct ChannelFlags: OptionSet {
    let rawValue: Int
    static let isForum = ChannelFlags(rawValue: 1)
}
// The fields of the real peers, in the order of their initializers; the payloads are simplified.
struct TelegramGroup: Peer {
    let id: PeerId
    var title: String = ""
    var photo: [String] = []
    var participantCount: Int = 0
    var role: GroupRole = .member
    var membership: Membership
    var flags: GroupFlags = []
    var defaultBannedRights: String? = nil
    var migrationReference: String? = nil
    var creationDate: Int32 = 0
    var version: Int = 0
}
struct TelegramChannel: Peer {
    let id: PeerId
    var accessHash: Int64? = nil
    var title: String = ""
    var username: String? = nil
    var photo: [String] = []
    var creationDate: Int32 = 0
    var version: Int32 = 0
    var participationStatus: Participation
    var info: String = ""
    var flags: ChannelFlags = []
    var restrictionInfo: String? = nil
    var adminRights: String? = nil
    var bannedRights: String? = nil
    var defaultBannedRights: String? = nil
    var usernames: [String] = []
    var storiesHidden: Bool? = nil
    var nameColor: Int32? = nil
    var backgroundEmojiId: Int64? = nil
    var profileColor: Int32? = nil
    var profileBackgroundEmojiId: Int64? = nil
    var emojiStatus: String? = nil
    var approximateBoostLevel: Int32? = nil
    var subscriptionUntilDate: Int32? = nil
    var verificationIconFileId: Int64? = nil
    var sendPaidMessageStars: Int64? = nil
    var linkedMonoforumId: PeerId? = nil
    var linkedCommunityId: PeerId? = nil
}
struct TelegramCommunity: Peer {
    let id: PeerId
    var participationStatus: Participation = .member
    var collapsedInDialogs: Bool? = true
}
public enum PeerGroupId: Equatable { case root, group(Int32) }
enum PinnedItemId: Hashable { case peer(PeerId) }
enum PeerChatListInclusion: Equatable {
    case notIncluded
    case included(group: String, pin: Int)
}
enum Namespaces {
    enum Message { static let Cloud: Int32 = 0 }
    enum CachedItemCollection { static let bananaBannedChats: Int8 = 102 }
}
enum ForkKeepBannedChatsSettings { static var enabled = false }
final class ValueBoxKey {
    var value: Int64 = 0
    init(length: Int) {}
    func setInt64(_ offset: Int, value: Int64) { self.value = value }
}
struct ItemCacheEntryId: Hashable {
    let collectionId: Int8
    let value: Int64
    init(collectionId: Int8, key: ValueBoxKey) {
        self.collectionId = collectionId
        self.value = key.value
    }
}
struct CodableEntry {
    let data: Data
    init?<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        self.data = data
    }
    func get<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: data) }
}
enum HoleSpace { case everywhere }
final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var inclusions: [PeerId: PeerChatListInclusion] = [:]
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var holes: Set<String> = []
    var cacheReads = 0
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func getPeerChatListInclusion(_ id: PeerId) -> PeerChatListInclusion { inclusions[id] ?? .notIncluded }
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? {
        cacheReads += 1
        return cache[id]
    }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { cache[id] = entry }
    func removeItemCacheEntry(id: ItemCacheEntryId) { cache.removeValue(forKey: id) }
    func setMessageHistoryThreads(peerId: PeerId) -> [Int64] { [5, 9] }
    func addHole(peerId: PeerId, threadId: Int64?, namespace: Int32, space: HoleSpace, range: ClosedRange<Int32>) {
        holes.insert("\(peerId.value):\(threadId ?? 0)")
    }
    func removeHole(peerId: PeerId, threadId: Int64?, namespace: Int32, space: HoleSpace, range: ClosedRange<Int32>) {
        holes.remove("\(peerId.value):\(threadId ?? 0)")
    }
}
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }

// TEST CASES
let id = PeerId(value: 1)
let member = TelegramChannel(id: id, participationStatus: .member)
let banned = TelegramChannel(id: id, participationStatus: .kicked)
let transaction = Transaction()
transaction.peers[id] = member
transaction.inclusions[id] = .included(group: "archive", pin: 3)
transaction.holes = ["1:0", "1:5", "1:9"]
bananaUpdateBannedChat(transaction: transaction, previous: member, updated: banned)
check(transaction.cache.isEmpty, "disabled by default")
ForkKeepBannedChatsSettings.enabled = true
bananaUpdateBannedChat(transaction: transaction, previous: member, updated: banned)
transaction.peers[id] = banned
check(bananaIsPreservedBannedChat(transaction: transaction, peerId: id), "ban archives an existing chat")
check(!shouldExcludePeerFromChatList(transaction: transaction, peerId: id), "sync keeps the archive")
check(transaction.inclusions[id] == .included(group: "archive", pin: 3), "keep folder and pin")
check(transaction.holes.isEmpty, "no unfillable root or forum history holes")
check(bananaIsPreservedBannedChat(peer: banned, groupId: .group(1)), "the chat UI sees a kept chat")
check(!bananaIsPreservedBannedChat(peer: banned, groupId: nil), "a banned chat out of the list keeps the stock no-access screen")
check(!bananaIsPreservedBannedChat(peer: member, groupId: .root), "a member's chat is not an archive")
check(banned.participationStatus == .kicked, "membership must stay banned for input restrictions")

let reopened = Transaction()
reopened.peers = transaction.peers
reopened.inclusions = transaction.inclusions
reopened.cache = transaction.cache
ForkKeepBannedChatsSettings.enabled = false
check(bananaIsPreservedBannedChat(transaction: reopened, peerId: id), "stored archive survives reopening and disabling new captures")
check(!bananaIsPreservedBannedChat(transaction: Transaction(), peerId: id, peer: banned), "account isolation")
reopened.inclusions[id] = .notIncluded
bananaUpdateBannedChat(transaction: reopened, previous: banned, updated: banned)
check(!bananaIsPreservedBannedChat(transaction: reopened, peerId: id), "manual deletion is not undone")
check(shouldExcludePeerFromChatList(transaction: reopened, peerId: id), "sync must not reinsert deleted archive")

bananaUpdateBannedChat(transaction: transaction, previous: banned, updated: member)
transaction.peers[id] = member
check(transaction.cache.isEmpty, "rejoining removes the archive marker")
check(transaction.holes == ["1:0", "1:5", "1:9"], "rejoining resumes history sync")
let readsBefore = transaction.cacheReads
bananaUpdateBannedChat(transaction: transaction, previous: member, updated: member)
bananaUpdateBannedChat(transaction: transaction, previous: nil, updated: member)
check(transaction.cacheReads == readsBefore, "an update of a chat that was not banned does not read the item cache")
check(!shouldExcludePeerFromChatList(transaction: transaction, peerId: id), "member is visible normally")

ForkKeepBannedChatsSettings.enabled = true
let left = TelegramChannel(id: id, participationStatus: .left)
bananaUpdateBannedChat(transaction: transaction, previous: member, updated: left)
check(transaction.cache.isEmpty, "voluntary leave is not a ban")
let unseen = Transaction()
bananaUpdateBannedChat(transaction: unseen, previous: nil, updated: banned)
check(unseen.cache.isEmpty, "do not resurrect unknown or previewed banned chats")
let group = TelegramGroup(id: id, membership: .Member)
let removed = TelegramGroup(id: id, membership: .Removed)
bananaUpdateBannedChat(transaction: transaction, previous: group, updated: removed)
transaction.peers[id] = removed
check(!shouldExcludePeerFromChatList(transaction: transaction, peerId: id), "basic groups are preserved too")
check(!bananaPeerIsBanned(TelegramGroup(id: id, membership: .Removed, flags: .deactivated)), "migrated/deactivated groups are excluded")
check(!bananaPeerIsBanned(TelegramGroup(id: id, membership: .Left)), "voluntary basic-group leave")

// A ban arrives as a stripped object: the kept chat must not lose what only the member's object had.
let forum = TelegramChannel(id: id, accessHash: 1, title: "Форум", username: "forum", photo: ["photo"], creationDate: 100, version: 7, participationStatus: .member, info: "group", flags: .isForum, adminRights: "admin", usernames: ["forum"], nameColor: 3)
let forbidden = TelegramChannel(id: id, accessHash: 2, title: "Форум", participationStatus: .kicked, info: "broadcast", bannedRights: "read")
let kept = bananaPreservedBannedPeer(previous: forum, updated: forbidden) as! TelegramChannel
check(kept.photo == ["photo"] && kept.username == "forum" && kept.usernames == ["forum"] && kept.nameColor == 3, "a kept chat keeps its photo, username and colour")
check(kept.creationDate == 100 && kept.version == 7 && kept.info == "group", "a kept chat keeps its age and kind")
check(kept.flags.contains(.isForum), "a kept forum still opens by topics")
check(kept.participationStatus == .kicked && kept.adminRights == nil && kept.bannedRights == "read" && kept.accessHash == 2, "membership, rights and access hash come from the ban")
check(bananaPeerIsBanned(kept), "a kept chat stays banned for input restrictions")
check((bananaPreservedBannedPeer(previous: nil, updated: forbidden) as! TelegramChannel).accessHash == 2, "without a previous object the new one is stored")
let fullGroup = TelegramGroup(id: id, title: "Группа", photo: ["photo"], participantCount: 5, role: .admin, membership: .Member, creationDate: 50)
let keptGroup = bananaPreservedBannedPeer(previous: fullGroup, updated: TelegramGroup(id: id, title: "Группа", membership: .Removed)) as! TelegramGroup
check(keptGroup.photo == ["photo"] && keptGroup.participantCount == 5 && keptGroup.creationDate == 50, "a kept basic group keeps its photo and members count")
check(keptGroup.membership == .Removed && keptGroup.role == .member, "removal and the lost admin role come from the ban")

// The server's pinned lists leave out a kept chat; it keeps its place among the pins here.
let pins = Transaction()
let keptId = PeerId(value: 10), otherId = PeerId(value: 11), thirdId = PeerId(value: 12)
pins.peers[keptId] = TelegramChannel(id: keptId, participationStatus: .member)
pins.peers[otherId] = TelegramChannel(id: otherId, participationStatus: .member)
pins.inclusions[keptId] = .included(group: "root", pin: 1)
pins.inclusions[otherId] = .included(group: "root", pin: 0)
bananaUpdateBannedChat(transaction: pins, previous: pins.peers[keptId], updated: TelegramChannel(id: keptId, participationStatus: .kicked))
pins.peers[keptId] = TelegramChannel(id: keptId, participationStatus: .kicked)
let localPins: [PinnedItemId] = [.peer(otherId), .peer(keptId), .peer(thirdId)]
check(bananaKeepingPinnedBannedChats(transaction: pins, currentItemIds: localPins, itemIds: [.peer(thirdId), .peer(otherId)]) == [.peer(thirdId), .peer(keptId), .peer(otherId)], "a kept chat keeps its place among the server's pins")
check(bananaKeepingPinnedBannedChats(transaction: pins, currentItemIds: localPins, itemIds: []) == [.peer(keptId)], "a kept chat stays pinned when the server lists no pins")
check(bananaKeepingPinnedBannedChats(transaction: pins, currentItemIds: [.peer(otherId)], itemIds: []).isEmpty, "a chat unpinned elsewhere is unpinned")
check(bananaKeepingPinnedBannedChats(transaction: pins, currentItemIds: localPins, itemIds: [.peer(keptId)]) == [.peer(keptId)], "a kept chat is never pinned twice")
print("banned chat archive checks passed")
