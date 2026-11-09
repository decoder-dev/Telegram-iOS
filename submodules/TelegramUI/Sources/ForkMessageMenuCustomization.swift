import Foundation
import ContextUI
import TelegramUIPreferences

private func forkMessageMenuKey(_ item: ContextMenuItem) -> ForkMessageMenuItem? {
    switch item {
    case let .action(action):
        return action.id as? ForkMessageMenuItem
    case let .custom(customItem, _):
        // Delete with an auto-delete countdown is a custom row and has no id to carry.
        return customItem is ChatDeleteMessageContextItem ? .delete : nil
    case .separator:
        return nil
    }
}

/// Applies Extras › Message Actions › Message Menu to a built message menu. Only actions tagged with a
/// ForkMessageMenuItem id disappear or move; everything else (the read-receipts header, Send Gift, Stop Poll...)
/// keeps its slot. Tagged actions are sorted inside the block between two separators and never cross one.
func forkCustomizedMessageMenu(_ items: [ContextMenuItem], settings: ForkExtrasSettings) -> [ContextMenuItem] {
    if settings.messageMenuHiddenItems.isEmpty && settings.messageMenuOrder.isEmpty {
        return items
    }
    let hiddenItems = Set(settings.messageMenuHiddenItems.compactMap { ForkMessageMenuItem(rawValue: $0) })
    var rankByItem: [ForkMessageMenuItem: Int] = [:]
    for (index, item) in ForkMessageMenuItem.order(stored: settings.messageMenuOrder).enumerated() {
        rankByItem[item] = index
    }

    var result = items.filter { item in
        guard let key = forkMessageMenuKey(item) else {
            return true
        }
        return !hiddenItems.contains(key)
    }
    let didRemove = result.count != items.count

    var blockStart = 0
    for index in 0 ... result.count {
        var isBlockEnd = index == result.count
        if !isBlockEnd, case .separator = result[index] {
            isBlockEnd = true
        }
        if !isBlockEnd {
            continue
        }
        var tagged: [(slot: Int, rank: Int)] = []
        for slot in blockStart ..< index {
            if let key = forkMessageMenuKey(result[slot]) {
                tagged.append((slot: slot, rank: rankByItem[key] ?? Int.max))
            }
        }
        // Equal ranks (the Bookmarks rows, Repeat and Forward without author) keep the order the menu added them in.
        let sorted = tagged.sorted { lhs, rhs in
            return lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.slot < rhs.slot
        }
        let unsorted = result
        for (target, source) in zip(tagged, sorted) {
            result[target.slot] = unsorted[source.slot]
        }
        blockStart = index + 1
    }

    if didRemove {
        // A hidden item can empty a whole block: no separator at either end, none doubled up.
        var cleaned: [ContextMenuItem] = []
        for item in result {
            if case .separator = item {
                guard let previous = cleaned.last else {
                    continue
                }
                if case .separator = previous {
                    continue
                }
            }
            cleaned.append(item)
        }
        if let last = cleaned.last, case .separator = last {
            cleaned.removeLast()
        }
        result = cleaned
    }
    return result
}
