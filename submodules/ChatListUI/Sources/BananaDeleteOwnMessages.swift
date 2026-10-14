import Foundation
import Postbox
import SwiftSignalKit
import AccountContext
import TelegramCore

/// Extras ▸ chat list context menu "Delete all my messages" for groups: finds every message the account sent
/// in the chat (a server-side search by author, paged) and deletes them for everyone in batches of 100.
enum BananaDeleteOwnMessages {
    static let deleteBatchSize = 100

    enum Progress {
        case searching(found: Int)
        case deleting(queued: Int, total: Int)
        case finished(queued: Int, searchComplete: Bool)
    }

    private struct Collection {
        let ids: [EngineMessage.Id]
        let complete: Bool
    }

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

    private static func collectOwnMessageIds(context: AccountContext, peerId: EnginePeer.Id, progress: @escaping (Int) -> Void) -> Signal<Collection, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let cancelled = Atomic<Bool>(value: false)
            let accountPeerId = context.account.peerId
            var ids: [EngineMessage.Id] = []
            var seen = Set<EngineMessage.Id>()
            func loadPage(state: SearchMessagesState?) {
                guard !cancelled.with({ $0 }) else { return }
                disposable.set((context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: accountPeerId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: state)
                |> deliverOnMainQueue).start(next: { pair in
                    guard !cancelled.with({ $0 }) else { return }
                    let result = pair.0
                    let nextState = pair.1
                    for message in result.messages {
                        if message.id.peerId == peerId, message.author?.id == accountPeerId, seen.insert(message.id).inserted {
                            ids.append(message.id)
                        }
                    }
                    progress(ids.count)
                    // An overlapping/filtered page can add no own messages while its cursor advances.
                    // Only end-of-search or a stalled cursor stops pagination; no silent 5000 cap.
                    if result.completed || nextState == state {
                        subscriber.putNext(Collection(ids: ids, complete: result.completed))
                        subscriber.putCompletion()
                    } else {
                        Queue.mainQueue().async { loadPage(state: nextState) }
                    }
                }))
            }
            loadPage(state: nil)
            return ActionDisposable {
                let _ = cancelled.swap(true)
                disposable.dispose()
            }
        }
    }

    /// Reports locally queued requests, not a server-confirmed deletion count. Disposal stops future batches;
    /// requests already put in the durable Telegram deletion queue cannot be recalled.
    static func deleteAll(context: AccountContext, peerId: EnginePeer.Id) -> Signal<Progress, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            let cancelled = Atomic<Bool>(value: false)
            func deleteBatch(_ collection: Collection, offset: Int) {
                guard !cancelled.with({ $0 }) else { return }
                if offset == collection.ids.count {
                    subscriber.putNext(.finished(queued: offset, searchComplete: collection.complete))
                    subscriber.putCompletion()
                    return
                }
                let end = min(offset + deleteBatchSize, collection.ids.count)
                let batch = Array(collection.ids[offset ..< end])
                disposable.set((context.engine.messages.deleteMessagesInteractively(messageIds: batch, type: .forEveryone)
                |> deliverOnMainQueue).start(completed: {
                    guard !cancelled.with({ $0 }) else { return }
                    subscriber.putNext(.deleting(queued: end, total: collection.ids.count))
                    Queue.mainQueue().async { deleteBatch(collection, offset: end) }
                }))
            }
            subscriber.putNext(.searching(found: 0))
            disposable.set(collectOwnMessageIds(context: context, peerId: peerId, progress: { count in
                subscriber.putNext(.searching(found: count))
            }).start(next: { collection in
                Queue.mainQueue().async { deleteBatch(collection, offset: 0) }
            }))
            return ActionDisposable {
                let _ = cancelled.swap(true)
                disposable.dispose()
            }
        }
    }
}
