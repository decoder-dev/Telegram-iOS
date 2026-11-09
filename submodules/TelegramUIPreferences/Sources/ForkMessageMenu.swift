import Foundation

/// The message long-press menu items that Extras › Message Actions › Message Menu can hide or move. Cases follow the
/// order the menu adds them in, which is the stock order. Raw values are stored in ForkExtrasSettings, so never rename one.
public enum ForkMessageMenuItem: String, CaseIterable {
    case reply
    case editHistory
    case copy
    case translate
    case saveMedia
    case saveToFiles
    case convertAudio
    case viewReplies
    case edit
    case pin
    case copyLink
    case saveGif
    case forward
    case saveStickerToPhotos
    case mediaInfo
    case saveToSavedMessages
    case screenshot
    case bookmarks
    case selectFromAuthor
    case repeatMessage
    case summarize
    case messageJson
    case report
    case shadowBan
    case statistics
    case delete
    case select

    /// Select and Select All live in their own block under a separator at the bottom of the menu, so they can be
    /// hidden but not moved.
    public var isMovable: Bool {
        return self != .select
    }

    /// The order the user arranged, followed by any item it doesn't mention (one added in a later version) in stock order.
    public static func order(stored: [String]) -> [ForkMessageMenuItem] {
        var result: [ForkMessageMenuItem] = []
        for item in stored.compactMap({ ForkMessageMenuItem(rawValue: $0) }) + ForkMessageMenuItem.allCases where !result.contains(item) {
            result.append(item)
        }
        return result
    }
}
