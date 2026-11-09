// A person's messages in a group, for "Messages in Common Groups" (after Regram and 64Gram).
import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

public enum BananaMemberMessagesError {
    case floodWait
    case generic
}

public extension TelegramEngine.Messages {
    /// The newest messages `fromId` sent in the chat, in one request. A flood wait comes back as
    /// an error instead of being waited out, so a caller going through many chats can stop there
    /// and show what it found.
    func bananaMessages(from fromId: EnginePeer.Id, in peerId: EnginePeer.Id, limit: Int32) -> Signal<[EngineMessage], BananaMemberMessagesError> {
        let account = self.account
        return account.postbox.transaction { transaction -> (Api.InputPeer?, Api.InputPeer?) in
            return (transaction.getPeer(peerId).flatMap(apiInputPeer), transaction.getPeer(fromId).flatMap(apiInputPeer))
        }
        |> castError(BananaMemberMessagesError.self)
        |> mapToSignal { inputPeer, fromPeer -> Signal<[EngineMessage], BananaMemberMessagesError> in
            guard let inputPeer, let fromPeer else {
                return .single([])
            }
            return account.network.request(Api.functions.messages.search(flags: 1 << 0, peer: inputPeer, q: "", fromId: fromPeer, savedPeerId: nil, savedReaction: nil, topMsgId: nil, filter: .inputMessagesFilterEmpty, minDate: 0, maxDate: 0, offsetId: 0, addOffset: 0, limit: limit, maxId: 0, minId: 0, hash: 0), automaticFloodWait: false)
            |> mapError { error -> BananaMemberMessagesError in
                return error.errorDescription.hasPrefix("FLOOD_WAIT") ? .floodWait : .generic
            }
            |> mapToSignal { result -> Signal<[EngineMessage], BananaMemberMessagesError> in
                return account.postbox.transaction { transaction -> [EngineMessage] in
                    let apiMessages: [Api.Message]
                    let apiChats: [Api.Chat]
                    let apiUsers: [Api.User]
                    switch result {
                    case let .messages(messagesData):
                        apiMessages = messagesData.messages
                        apiChats = messagesData.chats
                        apiUsers = messagesData.users
                    case let .messagesSlice(messagesSliceData):
                        apiMessages = messagesSliceData.messages
                        apiChats = messagesSliceData.chats
                        apiUsers = messagesSliceData.users
                    case let .channelMessages(channelMessagesData):
                        apiMessages = channelMessagesData.messages
                        apiChats = channelMessagesData.chats
                        apiUsers = channelMessagesData.users
                    case .messagesNotModified:
                        return []
                    }

                    var peers: [PeerId: Peer] = [:]
                    for user in apiUsers {
                        if let user = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
                            peers[user.id] = user
                        }
                    }
                    for chat in apiChats {
                        if let peer = parseTelegramGroupOrChannel(chat: chat) {
                            peers[peer.id] = peer
                        }
                    }
                    let peerIsForum = peers[peerId]?.isForumOrMonoForum ?? false

                    var messages: [EngineMessage] = []
                    for apiMessage in apiMessages {
                        if let storeMessage = StoreMessage(apiMessage: apiMessage, accountPeerId: account.peerId, peerIsForum: peerIsForum), let message = locallyRenderedMessage(message: storeMessage, peers: peers) {
                            messages.append(EngineMessage(message))
                        }
                    }
                    return messages
                }
                |> castError(BananaMemberMessagesError.self)
            }
        }
    }
}
