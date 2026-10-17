import Foundation
import TelegramCore

/// Regram "default send formatting" (Extras ▸ Messages ▸ Input). Adds one style to the plain parts of an
/// outgoing text message. Spans the sender formatted by hand keep exactly that formatting, and code, quotes,
/// custom emoji, dates and bot commands are never restyled. `style`: 0 off, 1 bold, 2 italic, 3 underline,
/// 4 strikethrough, 5 spoiler. Entity ranges are UTF-16 offsets, as everywhere in `MessageTextEntity`.
func forkApplyDefaultSendFormatting(text: String, entities: [MessageTextEntity], style: Int32) -> [MessageTextEntity] {
    let styleType: MessageTextEntityType
    switch style {
    case 1:
        styleType = .Bold
    case 2:
        styleType = .Italic
    case 3:
        styleType = .Underline
    case 4:
        styleType = .Strikethrough
    case 5:
        styleType = .Spoiler
    default:
        return entities
    }
    let units = Array(text.utf16)
    let length = units.count
    if length == 0 || text.hasPrefix("/") {
        // A bot command goes out exactly as typed.
        return entities
    }

    var excluded = [Bool](repeating: false, count: length)
    for entity in entities {
        let keepsOwnLook: Bool
        switch entity.type {
        case .Bold, .Italic, .Underline, .Strikethrough, .Spoiler, .Code, .Pre, .BlockQuote, .CustomEmoji, .FormattedDate, .BotCommand:
            keepsOwnLook = true
        default:
            keepsOwnLook = false
        }
        if !keepsOwnLook {
            continue
        }
        let lower = max(0, min(length, entity.range.lowerBound))
        let upper = max(lower, min(length, entity.range.upperBound))
        for index in lower ..< upper {
            excluded[index] = true
        }
    }

    func isBlank(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else {
            return false
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    var added: [MessageTextEntity] = []
    var index = 0
    while index < length {
        if excluded[index] {
            index += 1
            continue
        }
        var end = index
        while end < length && !excluded[end] {
            end += 1
        }
        var lower = index
        var upper = end
        while lower < upper && isBlank(units[lower]) {
            lower += 1
        }
        while upper > lower && isBlank(units[upper - 1]) {
            upper -= 1
        }
        if lower < upper {
            added.append(MessageTextEntity(range: lower ..< upper, type: styleType))
        }
        index = end
    }
    if added.isEmpty {
        return entities
    }
    return (entities + added).sorted(by: { lhs, rhs in
        if lhs.range.lowerBound != rhs.range.lowerBound {
            return lhs.range.lowerBound < rhs.range.lowerBound
        }
        return lhs.range.upperBound > rhs.range.upperBound
    })
}
