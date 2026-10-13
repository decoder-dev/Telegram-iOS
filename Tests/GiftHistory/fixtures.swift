import Foundation

typealias StarGiftReference = Int

struct GenericGift: Codable { var id: Int }
struct UniqueGift: Codable {
    enum Attribute: Codable {
        case originalInfo(senderPeerId: Int?, recipientPeerId: Int, date: Int32, text: String?, entities: [Int]?)
        case backdrop
    }
    var id: Int
    var giftId: Int
    var slug: String
    var attributes: [Attribute]
}
enum Gift: Codable { case generic(GenericGift); case unique(UniqueGift) }

struct StarGift: Codable {
    var gift: Gift
    var reference: StarGiftReference?
    var date: Int32
    var _fromPeerId: Int?
    var text: String?
    var number: Int?
}

struct DisappearedGift: Codable {
    var gift: StarGift
    var position: Int32
    var previousReference: StarGiftReference?
    var nextReference: StarGiftReference?
    var lastSeen: Int32
    var isMissing: Bool
}

enum History {
    // PRODUCTION_HELPERS
}

var checks = 0
func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { fatalError(message) }
}

func gift(_ id: Int, reference: Bool = true) -> StarGift {
    // Ordinary bears share their catalog ID; date/sender distinguish instances.
    let kind: Gift = id % 2 == 0 ? .generic(GenericGift(id: 1)) : .unique(UniqueGift(id: id, giftId: 1000 + id, slug: "gift-\(id)", attributes: []))
    return StarGift(gift: kind, reference: reference ? id : nil, date: Int32(id), _fromPeerId: id, text: nil, number: nil)
}

func ids(_ history: [DisappearedGift]) -> [Int] {
    return history.map { Int($0.gift.date) }
}

func snapshot(_ gifts: [StarGift]) -> [DisappearedGift] {
    var result = History.giftsWithDisappeared(current: gifts, history: [])
    for index in result.indices { result[index].lastSeen = 123 }
    return result
}

func roundTrip(_ history: [DisappearedGift]) -> [DisappearedGift] {
    return try! JSONDecoder().decode([DisappearedGift].self, from: JSONEncoder().encode(history))
}

func checkPositions(_ history: [DisappearedGift]) {
    for index in history.indices {
        expect(history[index].position == Int32(index), "noncontiguous saved position")
        expect(history[index].previousReference == (index > 0 ? history[index - 1].gift.reference : nil), "stale previous anchor")
        expect(history[index].nextReference == (index + 1 < history.count ? history[index + 1].gift.reference : nil), "stale next anchor")
    }
}

// Every subset of six gifts, with Telegram references, without them, and mixed.
// Delete missing gifts one at a time and reconstruct the view from its saved cache.
for referenceMode in 0..<3 {
    let original = (1...6).map { gift($0, reference: referenceMode == 0 || (referenceMode == 2 && $0 % 2 == 0)) }
    for mask in 0..<64 {
        let current = original.enumerated().filter { (mask & (1 << $0.offset)) == 0 }.map { $0.element }
        var history = snapshot(original)
        for index in history.indices { history[index].isMissing = (mask & (1 << index)) != 0 }
        history = History.giftsWithDisappeared(current: current, history: history)
        expect(ids(history) == Array(1...6), "disappearance moved an existing gift")
        let missing = history.filter { $0.isMissing }.map { $0.gift }
        // The UI receives only missing entries, unlike the full persisted history.
        expect(ids(History.giftsWithDisappeared(current: current, history: history.filter { $0.isMissing })) == ids(history), "UI and cache order disagree")
        for removed in missing.reversed() {
            let expected = ids(history).filter { $0 != Int(removed.date) }
            history = History.removingDisappearedGift(removed, current: current, history: history)!
            expect(ids(history) == expected, "deleting a gift reordered its survivors")
            checkPositions(history)
            history = roundTrip(history)
            expect(ids(History.giftsWithDisappeared(current: current, history: history)) == expected, "reopening changed the order")
            expect(ids(History.giftsWithDisappeared(current: current, history: history.filter { $0.isMissing })) == expected, "reopened UI changed the order")
        }
        expect(History.removingDisappearedGift(gift(99), current: current, history: history) == nil, "unknown deletion modified history")
        let newCurrent = [gift(99)] + current
        let withNewGift = History.giftsWithDisappeared(current: newCurrent, history: snapshot(original).enumerated().map {
            var entry = $0.element
            entry.isMissing = (mask & (1 << $0.offset)) != 0
            return entry
        })
        if !current.isEmpty {
            expect(ids(withNewGift) == [99] + Array(1...6), "new live gift broke the old order")
        }
    }
}

// Two removed bears at the beginning: deleting either keeps banana/lollipop order.
let current = [gift(3), gift(5), gift(7)]
var bears = snapshot([gift(2), gift(4)] + current)
bears[0].isMissing = true
bears[1].isMissing = true
let afterFirst = History.removingDisappearedGift(gift(2), current: current, history: bears)!
expect(ids(afterFirst) == [4, 3, 5, 7], "first bear removal moved banana")
let afterBoth = History.removingDisappearedGift(gift(4), current: current, history: afterFirst)!
expect(ids(afterBoth) == [3, 5, 7], "second bear removal changed live order")

// Legacy entries may both point to one live predecessor or successor.
for useNext in [false, true] {
    let anchor = gift(1)
    let missing = [2, 4].enumerated().map { index, id in
        DisappearedGift(gift: gift(id), position: Int32(index + 1), previousReference: useNext ? nil : 1, nextReference: useNext ? 1 : nil, lastSeen: 123, isMissing: true)
    }
    expect(ids(History.giftsWithDisappeared(current: [anchor], history: missing)) == (useNext ? [2, 4, 1] : [1, 2, 4]), "shared anchor reversed missing bears")
}

// Reappearance consumes a cached missing gift exactly once, including no-reference gifts.
let returned = gift(2, reference: false)
var disappeared = snapshot([returned, gift(4, reference: false)])
disappeared[0].isMissing = true
disappeared[1].isMissing = true
let reappeared = History.giftsWithDisappeared(current: [returned], history: disappeared)
expect(ids(reappeared) == [2, 4], "reappearance duplicated a bear")
expect(!reappeared[0].isMissing, "returned gift still marked missing")
expect(History.removingDisappearedGift(returned, current: [returned], history: disappeared) == nil, "live gift can be removed from memory")

// A cycle in old anchors must terminate and preserve positional fallback.
let cyclic = [
    DisappearedGift(gift: gift(2), position: 0, previousReference: 4, nextReference: 4, lastSeen: 123, isMissing: true),
    DisappearedGift(gift: gift(4), position: 1, previousReference: 2, nextReference: 2, lastSeen: 123, isMissing: true)
]
expect(ids(History.giftsWithDisappeared(current: [gift(7)], history: cyclic)) == [2, 4, 7], "cyclic legacy anchors changed fallback")

func collectible(_ id: Int, giftId: Int = 1, reference: StarGiftReference?, date: Int32, sender: Int?, original: (sender: Int?, date: Int32)?) -> StarGift {
    let attributes: [UniqueGift.Attribute] = original.map { [.originalInfo(senderPeerId: $0.sender, recipientPeerId: 50, date: $0.date, text: nil, entities: nil)] } ?? []
    return StarGift(gift: .unique(UniqueGift(id: id, giftId: giftId, slug: "collectible-\(id)", attributes: attributes)), reference: reference, date: date, _fromPeerId: sender, text: nil, number: nil)
}

func references(_ history: [DisappearedGift]) -> [StarGiftReference?] {
    return history.map { $0.gift.reference }
}

// A bear upgraded to a collectible gets a new reference and continues the
// bear's entry, whether or not the collectible keeps its original details.
for (upgradedBear, label) in [
    (collectible(500, reference: 70, date: 40, sender: 50, original: (sender: 2, date: 2)), "with details"),
    (collectible(500, reference: 70, date: 40, sender: 2, original: nil), "without details"),
] {
    let bear = gift(2)
    let history = snapshot([gift(1), bear, gift(3)])
    let updated = History.updatedGiftHistory(current: [gift(1), upgradedBear, gift(3)], history: history, previousCheck: 150, observedAt: 200, maxDisappearedCount: 10)
    expect(!updated.contains(where: { $0.isMissing }), "upgrading a bear \(label) recorded it as gone")
    expect(references(updated) == [1, 70, 3], "upgrading a bear \(label) moved it")
    checkPositions(updated)
}

// A collectible from another bear, or of another gift, does not hide the bear.
for other in [
    collectible(501, reference: 71, date: 40, sender: 50, original: (sender: 2, date: 99)),
    collectible(502, giftId: 7, reference: 72, date: 40, sender: 2, original: nil),
] {
    let updated = History.updatedGiftHistory(current: [gift(1), other, gift(3)], history: snapshot([gift(1), gift(2), gift(3)]), previousCheck: 150, observedAt: 200, maxDisappearedCount: 10)
    expect(updated.filter { $0.isMissing }.map { Int($0.gift.date) } == [2], "an unrelated collectible hid a bear")
}

// A collectible sold and bought back under a new reference is the same gift,
// and an older missing copy of it is not shown next to it.
let sold = History.updatedGiftHistory(current: [gift(1)], history: snapshot([gift(1), gift(3)]), previousCheck: 150, observedAt: 200, maxDisappearedCount: 10)
expect(sold.filter { $0.isMissing }.map { $0.gift.reference } == [3], "a sold collectible is not missing")
var boughtBack = gift(3)
boughtBack.reference = 33
boughtBack.date = 300
let returnedHistory = History.updatedGiftHistory(current: [gift(1), boughtBack], history: sold, previousCheck: 200, observedAt: 300, maxDisappearedCount: 10)
expect(!returnedHistory.contains(where: { $0.isMissing }) && references(returnedHistory) == [1, 33], "a collectible bought back is shown twice")
let staleCopy = DisappearedGift(gift: gift(3), position: 0, previousReference: nil, nextReference: 33, lastSeen: 123, isMissing: true)
expect(ids(History.giftsWithDisappeared(current: [boughtBack], history: [staleCopy])) == [300], "a stale copy of a live collectible is shown")
expect(History.removingDisappearedGift(gift(3), current: [boughtBack], history: [staleCopy]) == nil, "a live collectible can be removed")

// Until the list is loaded to its end, a missing gift is placed only next to a
// loaded neighbour, never parked after the loaded part.
for referenceMode in 0..<2 {
    let original = (1...6).map { gift($0, reference: referenceMode == 0) }
    var stored = snapshot(original)
    stored[3].isMissing = true
    let missingOnly = stored.filter { $0.isMissing }
    // Without references only the full saved history tells that gift 3 precedes it.
    for (loaded, fromMissing, fromStored) in [([1, 2], [1, 2], [1, 2]), ([1, 2, 3], referenceMode == 0 ? [1, 2, 3, 4] : [1, 2, 3], [1, 2, 3, 4])] {
        let current = loaded.map { original[$0 - 1] }
        expect(ids(History.giftsWithDisappeared(current: current, history: missingOnly, isComplete: false)) == fromMissing, "a missing gift was parked after a partly loaded list")
        expect(ids(History.giftsWithDisappeared(current: current, history: stored, isComplete: false)) == fromStored, "a missing gift was placed by an unloaded neighbour")
    }
    let live = original.filter { $0.date != 4 }
    expect(ids(History.giftsWithDisappeared(current: live, history: missingOnly, isComplete: true)) == Array(1...6), "a complete list lost its missing gift")
}

// A gift that stops showing up was last seen at the previous check, which
// still saw it, even when that check did not rewrite the history.
let checked = History.updatedGiftHistory(current: [gift(1), gift(3)], history: snapshot([gift(1), gift(2), gift(3)]), previousCheck: 150, observedAt: 200, maxDisappearedCount: 10)
expect(checked.map { $0.isMissing } == [false, true, false], "a gone gift was not marked missing")
expect(checked.map { $0.lastSeen } == [200, 150, 200], "last seen times are wrong")
expect(History.updatedGiftHistory(current: [gift(1), gift(3)], history: checked, previousCheck: 200, observedAt: 300, maxDisappearedCount: 10)[1].lastSeen == 150, "a missing gift was seen again")

// Only the most recently seen missing gifts are kept.
var crowded = snapshot((1...5).map { gift($0) })
for (index, lastSeen) in [(1, 10), (2, 30), (3, 20)] {
    crowded[index].isMissing = true
    crowded[index].lastSeen = Int32(lastSeen)
}
let trimmed = History.updatedGiftHistory(current: [gift(1), gift(5)], history: crowded, previousCheck: 150, observedAt: 200, maxDisappearedCount: 2)
expect(ids(trimmed) == [1, 3, 4, 5], "the oldest missing gift was kept")
checkPositions(trimmed)

// Removing a gift while only the first page is loaded keeps the saved order.
var partly = snapshot((0...5).map { gift($0 * 2 + 1) })
partly[1].isMissing = true
partly[5].isMissing = true
let afterRemoval = History.removingDisappearedGift(gift(3), current: [gift(1)], history: partly)!
expect(ids(afterRemoval) == [1, 5, 7, 9, 11], "removal reordered the saved history")
expect(ids(History.giftsWithDisappeared(current: [gift(1), gift(5), gift(7), gift(9)], history: afterRemoval)) == [1, 5, 7, 9, 11], "removal moved another missing gift")

// A gift that arrives twice across a page boundary is counted once.
expect(History.distinctGiftsForHistory([gift(1), gift(2), gift(2), gift(3)]).map { Int($0.date) } == [1, 2, 3], "a repeated gift was kept")
expect(History.distinctGiftsForHistory([gift(2, reference: false), gift(4, reference: false)]).map { Int($0.date) } == [2, 4], "distinct bears were merged")

// Matching goes through the keys, so a large profile is not compared pairwise.
let large = (1...4000).map { gift($0) }
let largeMatches = History.matchGiftHistory(current: large.reversed(), history: snapshot(large))
expect(largeMatches == Array((0..<4000).reversed()), "large profile matched wrongly")

print("Profile gift history: \(checks) checks passed")
