// Adapted from kittenello/Donutgram 041d862014 (kittenello, catboysense).
import Foundation
import Postbox
import SwiftSignalKit

/// Matches words and filename prefixes with the same case-insensitive semantics
/// as local chat search. Cloud messages are not in Postbox's secret-chat text index.
public func bananaDeletedMessageMatchesQuery(text: String, query: String) -> Bool {
    func words(_ value: String) -> [String] {
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
    let queryWords = words(query)
    let textWords = words(text)
    return queryWords.allSatisfy { queryWord in
        textWords.contains { $0.hasPrefix(queryWord) }
    }
}

func bananaDeletedMessages(
    transaction: Transaction,
    peerId: PeerId,
    query: String = "",
    fromId: PeerId? = nil,
    tags: MessageTags? = nil,
    reactions: [MessageReaction.Reaction]? = nil,
    threadId: Int64? = nil,
    minDate: Int32? = nil,
    maxDate: Int32? = nil
) -> [Message] {
    return transaction.getMessagesWithLocalTag(.bananaDeleted, peerId: peerId).filter { message in
        guard message.id.namespace == Namespaces.Message.Cloud else { return false }
        if let fromId, message.author?.id != fromId { return false }
        if let tags, !message.tags.contains(tags) { return false }
        if let threadId, message.threadId != threadId { return false }
        if let minDate, minDate != 0, message.timestamp < minDate { return false }
        if let maxDate, maxDate != 0, message.timestamp > maxDate { return false }
        if let reactions, !reactions.isEmpty {
            let messageReactions = message.attributes.compactMap { $0 as? ReactionsMessageAttribute }.flatMap { $0.reactions }
            if !reactions.allSatisfy({ reaction in messageReactions.contains { $0.value == reaction } }) { return false }
        }
        var text = message.text
        for media in message.media {
            if let indexableText = media.indexableText {
                text += " " + indexableText
            }
        }
        return bananaDeletedMessageMatchesQuery(text: text, query: query)
    }.sorted { $0.index > $1.index }
}

/// Includes local results only inside the loaded remote window. Older deletions
/// become visible as server pages arrive, keeping search navigation contiguous.
public func bananaSearchResultIncludingDeletedMessages(_ result: SearchMessagesResult, deletedMessages: [Message]) -> SearchMessagesResult {
    var uniqueLocal: [MessageId: Message] = [:]
    for message in deletedMessages {
        uniqueLocal[message.id] = message
    }
    let remoteIds = Set(result.messages.map { $0.id })
    let extraCount = uniqueLocal.keys.filter { !remoteIds.contains($0) }.count
    let oldestRemoteIndex = result.messages.last?.index
    let visibleLocal = uniqueLocal.values.filter { message in
        result.completed || oldestRemoteIndex.map { message.index >= $0 } == true
    }
    let localIds = Set(visibleLocal.map { $0.id })
    var messages = result.messages.filter { !localIds.contains($0.id) }
    messages.append(contentsOf: visibleLocal)
    messages.sort { $0.index > $1.index }
    return SearchMessagesResult(messages: messages, readStates: result.readStates, threadInfo: result.threadInfo, totalCount: result.totalCount + Int32(clamping: extraCount), completed: result.completed)
}
