import Foundation
import Postbox
import SwiftSignalKit
import AccountContext
import TelegramCore

/// Extras ▸ chat list context menu "Delete all my messages" for groups: finds every message the account sent
/// in the chat (a server-side search by author, paged) and deletes them for everyone in batches of 100.
enum BananaDeleteOwnMessages {
    /// A search page holds up to 100 messages; the cap keeps a runaway search from looping for a very busy chat.
    static let maximumMessageCount = 5000
    static let deleteBatchSize = 100

    static func isGroup(_ peer: EnginePeer) -> Bool {
        switch peer {
        case .legacyGroup:
            return true
        case let .channel(channel):
            if case .group = channel.info {
                return true
            }
            return false
        default:
            return false
        }
    }

    static func collectOwnMessageIds(context: AccountContext, peerId: EnginePeer.Id) -> Signal<[EngineMessage.Id], NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let accountPeerId = context.account.peerId
            var ids: [EngineMessage.Id] = []
            func loadPage(state: SearchMessagesState?) {
                disposable.set((context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: accountPeerId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: state)
                |> deliverOnMainQueue).start(next: { pair in
                    let result = pair.0
                    let nextState = pair.1
                    var added = 0
                    for message in result.messages {
                        if message.id.peerId == peerId, message.author?.id == accountPeerId, !ids.contains(message.id) {
                            ids.append(message.id)
                            added += 1
                        }
                    }
                    if result.completed || added == 0 || ids.count >= BananaDeleteOwnMessages.maximumMessageCount {
                        subscriber.putNext(ids)
                        subscriber.putCompletion()
                    } else {
                        loadPage(state: nextState)
                    }
                }))
            }
            loadPage(state: nil)
            return disposable
        }
    }

    static func deleteAll(context: AccountContext, peerId: EnginePeer.Id) -> Signal<Int, NoError> {
        return collectOwnMessageIds(context: context, peerId: peerId)
        |> mapToSignal { ids -> Signal<Int, NoError> in
            if ids.isEmpty {
                return .single(0)
            }
            var batches: [[EngineMessage.Id]] = []
            var index = 0
            while index < ids.count {
                batches.append(Array(ids[index ..< min(index + BananaDeleteOwnMessages.deleteBatchSize, ids.count)]))
                index += BananaDeleteOwnMessages.deleteBatchSize
            }
            var signal: Signal<Void, NoError> = .single(Void())
            for batch in batches {
                signal = signal |> then(context.engine.messages.deleteMessagesInteractively(messageIds: batch, type: .forEveryone))
            }
            return signal |> last |> map { _ in ids.count }
        }
    }
}
