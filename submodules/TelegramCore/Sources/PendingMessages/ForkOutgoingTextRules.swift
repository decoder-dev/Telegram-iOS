import Foundation
import Postbox
import SwiftSignalKit

/// Fork (Ghostgram): rules applied to the text of outgoing messages when they are enqueued, so every way of sending
/// (the composer, captions, replies, quick replies, scheduled messages) gets them. Two stages, in this order:
/// word replacement (the user's rules, whole words, one pass) and anti-caps (ALL CAPS becomes sentence case).
/// Links, mentions, commands, hashtags, code and custom emoji are never touched, and formatting moves with the text.
/// Bots get exactly what was typed.
public enum ForkOutgoingTextSettings {
    public struct Rule: Equatable {
        public var source: String
        public var replacement: String

        public init(source: String, replacement: String) {
            self.source = source
            self.replacement = replacement
        }
    }

    public struct State: Equatable {
        public var rules: [Rule]
        public var antiCaps: Bool

        public init(rules: [Rule], antiCaps: Bool) {
            self.rules = rules
            self.antiCaps = antiCaps
        }

        public var isEmpty: Bool {
            return self.rules.isEmpty && !self.antiCaps
        }
    }

    private static let value = Atomic<State>(value: State(rules: [], antiCaps: false))

    public static var current: State {
        get { return self.value.with { $0 } }
        set { let _ = self.value.swap(newValue) }
    }

    /// Rules as the settings store them, one per line: `source = replacement`. Lines without `=` or with an empty
    /// source are skipped.
    public static func parseRules(_ lines: [String]) -> [Rule] {
        var result: [Rule] = []
        for line in lines {
            guard let separator = line.firstIndex(of: "=") else {
                continue
            }
            let source = line[line.startIndex ..< separator].trimmingCharacters(in: .whitespaces)
            let replacement = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if source.isEmpty {
                continue
            }
            result.append(Rule(source: source, replacement: replacement))
        }
        return result
    }
}

/// UTF-16 text edits that move the entities with the text.
struct ForkTextEdit: Equatable {
    let range: Range<Int>
    let replacement: String
}

enum ForkOutgoingTextPipeline {
    /// The text and entities after the rules, or nil when nothing changes.
    static func apply(text: String, entities: [MessageTextEntity], state: ForkOutgoingTextSettings.State) -> (String, [MessageTextEntity])? {
        if text.isEmpty || state.isEmpty {
            return nil
        }
        var currentText = text
        var currentEntities = entities
        var changed = false
        if !state.rules.isEmpty {
            let edits = ForkWordReplacementStage.edits(currentText, rules: state.rules, protected: ForkProtectedRanges.compute(currentText, entities: currentEntities))
            if case let (updatedText, updatedEntities)? = ForkOutgoingTextPipeline.applying(edits, to: currentText, entities: currentEntities) {
                currentText = updatedText
                currentEntities = updatedEntities
                changed = true
            }
        }
        if state.antiCaps && !currentText.hasPrefix("/") {
            let edits = ForkAntiCapsStage.edits(currentText, protected: ForkProtectedRanges.compute(currentText, entities: currentEntities))
            if case let (updatedText, updatedEntities)? = ForkOutgoingTextPipeline.applying(edits, to: currentText, entities: currentEntities) {
                currentText = updatedText
                currentEntities = updatedEntities
                changed = true
            }
        }
        return changed ? (currentText, currentEntities) : nil
    }

    /// Applies non-overlapping edits and moves the entities: a boundary outside every edit shifts by the length change
    /// of the edits before it, a boundary inside an edit moves to that edit's new bounds, empty entities are dropped.
    static func applying(_ edits: [ForkTextEdit], to text: String, entities: [MessageTextEntity]) -> (String, [MessageTextEntity])? {
        let source = Array(text.utf16)
        let length = source.count
        var sorted = edits.filter { $0.range.lowerBound >= 0 && $0.range.upperBound <= length }
        sorted.sort(by: { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.range.upperBound < rhs.range.upperBound
        })
        var accepted: [ForkTextEdit] = []
        var lastEnd = 0
        for edit in sorted {
            if edit.range.lowerBound < lastEnd {
                continue
            }
            let original = String(decoding: source[edit.range], as: UTF16.self)
            if original == edit.replacement {
                continue
            }
            accepted.append(edit)
            lastEnd = edit.range.upperBound
        }
        if accepted.isEmpty {
            return nil
        }

        var result: [UInt16] = []
        result.reserveCapacity(length + 16)
        var mapped: [(old: Range<Int>, new: Range<Int>)] = []
        var cursor = 0
        for edit in accepted {
            if cursor < edit.range.lowerBound {
                result.append(contentsOf: source[cursor ..< edit.range.lowerBound])
            }
            let newStart = result.count
            result.append(contentsOf: Array(edit.replacement.utf16))
            mapped.append((old: edit.range, new: newStart ..< result.count))
            cursor = edit.range.upperBound
        }
        if cursor < length {
            result.append(contentsOf: source[cursor ..< length])
        }

        func map(_ position: Int, isStart: Bool) -> Int {
            var delta = 0
            for item in mapped {
                let old = item.old
                let change = item.new.count - old.count
                if old.upperBound <= position {
                    delta += change
                } else if old.lowerBound < position {
                    return isStart ? item.new.lowerBound : item.new.upperBound
                } else {
                    break
                }
            }
            return position + delta
        }

        var updatedEntities: [MessageTextEntity] = []
        for entity in entities {
            let start = map(entity.range.lowerBound, isStart: true)
            let end = map(entity.range.upperBound, isStart: false)
            if end > start {
                updatedEntities.append(MessageTextEntity(range: start ..< end, type: entity.type))
            }
        }
        return (String(decoding: result, as: UTF16.self), updatedEntities)
    }
}

/// Ranges the stages never touch: entities whose text must stay as typed, and what the server detects on its own in
/// plain text (links, domains, e-mails, @usernames, /commands, #hashtags, $cashtags).
enum ForkProtectedRanges {
    private static let expressions: [NSRegularExpression] = {
        let patterns = [
            "(?i)\\b(?:https?://|tg://|www\\.)[^\\s]+",
            "(?i)(?<![\\p{L}\\p{N}_@])(?:[\\p{L}\\p{N}](?:[\\p{L}\\p{N}-]{0,61}[\\p{L}\\p{N}])?\\.)+(?:[a-z]{2,24}|рф|бел|укр|срб|мкд|қаз)\\b(?:[/?#][^\\s]*)?",
            "[\\p{L}\\p{N}._%+-]+@[\\p{L}\\p{N}-]+(?:\\.[\\p{L}\\p{N}-]+)+",
            "(?<![\\p{L}\\p{N}_@])@[A-Za-z0-9_]{3,32}",
            "(?<![\\p{L}\\p{N}_/])/[A-Za-z0-9_]{1,64}(?:@[A-Za-z0-9_]{3,32})?",
            "(?<![\\p{L}\\p{N}_#])#[\\p{L}\\p{N}_]+",
            "(?<![\\p{L}\\p{N}_$])\\$[A-Z]{1,8}\\b"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static func isProtected(_ type: MessageTextEntityType) -> Bool {
        switch type {
        case .Url, .TextUrl, .Mention, .TextMention, .BotCommand, .Hashtag, .Email, .PhoneNumber, .BankCard, .Code, .Pre, .CustomEmoji, .FormattedDate, .TonAddress:
            return true
        default:
            return false
        }
    }

    static func compute(_ text: String, entities: [MessageTextEntity]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for entity in entities where ForkProtectedRanges.isProtected(entity.type) {
            result.append(entity.range)
        }
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        for expression in ForkProtectedRanges.expressions {
            for match in expression.matches(in: text, options: [], range: fullRange) where match.range.location != NSNotFound && match.range.length > 0 {
                result.append(match.range.location ..< (match.range.location + match.range.length))
            }
        }
        return ForkProtectedRanges.merged(result)
    }

    static func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    static func intersects(_ range: Range<Int>, _ protected: [Range<Int>]) -> Bool {
        for item in protected {
            if item.lowerBound >= range.upperBound {
                break
            }
            if item.overlaps(range) {
                return true
            }
        }
        return false
    }
}

enum ForkWordReplacementStage {
    static func isWordCharacter(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else {
            // Surrogate halves belong to emoji and other symbols, not to words.
            return false
        }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    /// Whole words, case-insensitive, in one pass over the original text: the earliest match wins, the longest wins a
    /// tie, and no replacement is fed into another rule.
    static func edits(_ text: String, rules: [ForkOutgoingTextSettings.Rule], protected: [Range<Int>]) -> [ForkTextEdit] {
        let string = text as NSString
        let units = Array(text.utf16)
        var matches: [ForkTextEdit] = []
        for rule in rules {
            let source = rule.source
            if source.isEmpty {
                continue
            }
            var searchRange = NSRange(location: 0, length: string.length)
            while searchRange.length > 0 {
                let found = string.range(of: source, options: [.caseInsensitive], range: searchRange)
                if found.location == NSNotFound || found.length == 0 {
                    break
                }
                let range = found.location ..< (found.location + found.length)
                searchRange = NSRange(location: range.upperBound, length: string.length - range.upperBound)
                if range.lowerBound > 0, ForkWordReplacementStage.isWordCharacter(units[range.lowerBound - 1]) {
                    continue
                }
                if range.upperBound < units.count, ForkWordReplacementStage.isWordCharacter(units[range.upperBound]) {
                    continue
                }
                if ForkProtectedRanges.intersects(range, protected) {
                    continue
                }
                let matched = string.substring(with: found)
                matches.append(ForkTextEdit(range: range, replacement: ForkWordReplacementStage.adaptCase(of: matched, to: rule.replacement)))
            }
        }
        matches.sort(by: { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return lhs.range.count > rhs.range.count
        })
        var result: [ForkTextEdit] = []
        var lastEnd = 0
        for match in matches {
            if match.range.lowerBound < lastEnd {
                continue
            }
            result.append(match)
            lastEnd = match.range.upperBound
        }
        return result
    }

    /// "HELLO" → the replacement in capitals, "Hello" → capitalized, anything else → as written in the rule.
    static func adaptCase(of matched: String, to replacement: String) -> String {
        let letters = matched.filter { $0.isLetter }
        if letters.count > 1 && letters.allSatisfy({ $0.isUppercase }) {
            return replacement.uppercased()
        }
        if let first = letters.first, first.isUppercase, let replacementFirst = replacement.first {
            return String(replacementFirst).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}

enum ForkAntiCapsStage {
    /// A text of at least four cased letters that is all, or at least 80%, capitals becomes sentence case. Only letters
    /// that have a case count: in Chinese, Japanese, Arabic or Hindi text an acronym like "NASA" is not shouting.
    static func edits(_ text: String, protected: [Range<Int>]) -> [ForkTextEdit] {
        var items: [(character: Character, range: Range<Int>)] = []
        var offset = 0
        for character in text {
            let length = character.utf16.count
            items.append((character, offset ..< (offset + length)))
            offset += length
        }
        var casedLetters = 0
        var uppercase = 0
        var uncasedLetters = 0
        for item in items where item.character.isLetter && !ForkProtectedRanges.intersects(item.range, protected) {
            if item.character.isUppercase {
                uppercase += 1
                casedLetters += 1
            } else if item.character.isLowercase {
                casedLetters += 1
            } else {
                uncasedLetters += 1
            }
        }
        // Mostly cased script: "这是NASA的API文档" (7 cased, 6 uncased) stays as written.
        guard casedLetters >= 4, uncasedLetters * 4 <= casedLetters else {
            return []
        }
        guard Double(uppercase) / Double(casedLetters) >= 0.8 else {
            return []
        }
        var result: [ForkTextEdit] = []
        var sentenceStart = true
        for item in items {
            let character = item.character
            let isProtected = ForkProtectedRanges.intersects(item.range, protected)
            if character.isLetter {
                if !isProtected {
                    let updated = sentenceStart ? String(character).uppercased() : String(character).lowercased()
                    if updated != String(character) {
                        result.append(ForkTextEdit(range: item.range, replacement: updated))
                    }
                }
                sentenceStart = false
            } else if character == "." || character == "!" || character == "?" || character == "…" || character.isNewline {
                sentenceStart = true
            } else if character.isNumber || isProtected {
                sentenceStart = false
            }
        }
        return result
    }
}

/// Applies the rules to a batch about to be enqueued. Synchronous and a no-op while both rules are off.
func forkApplyOutgoingTextRules(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {
    let state = ForkOutgoingTextSettings.current
    if state.isEmpty {
        return .single(messages)
    }
    // Every batch takes the same postbox hop while a rule is on, text or not: a sticker sent right after a text would
    // otherwise be inserted before it (its single transaction queued ahead of the text's second one) and arrive first.
    return account.postbox.transaction { transaction -> Bool in
        if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {
            return true
        }
        return false
    }
    |> map { isBot -> [EnqueueMessage] in
        if isBot {
            return messages
        }
        return messages.map { message -> EnqueueMessage in
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {
                return message
            }
            let entities = (attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
            guard case let (updatedText, updatedEntities)? = ForkOutgoingTextPipeline.apply(text: text, entities: entities, state: state) else {
                return message
            }
            var updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            if !updatedEntities.isEmpty {
                updatedAttributes.append(TextEntitiesMessageAttribute(entities: updatedEntities))
            }
            return .message(text: updatedText, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        }
    }
}
