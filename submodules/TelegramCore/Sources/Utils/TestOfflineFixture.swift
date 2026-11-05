import Foundation
import Postbox
import SwiftSignalKit

/// Simulator QA (`--ui-test --ui-test-fixture`): a signed-in account that exists only on the device.
///
/// Telegram's test servers no longer provision accounts for random `99966XYYYY` numbers (every code is
/// PHONE_CODE_INVALID), so the QA run cannot sign in anywhere. Instead this writes, into the `--ui-test` data
/// directory only, what a sign-in leaves behind: an `AuthorizedAccountState` for a made-up user, the account record
/// made current, and a few chats with messages, read states and one archived chat. The real app then opens it like
/// any account and draws its real screens from it.
///
/// It must never reach a server: the made-up account has no authorization, and a server's 401 would log it out. The
/// proxy settings are a SOCKS5 proxy on a closed loopback port (as `Tests/ComposerHarness` does), with the WebSocket
/// transport and its direct fallback off, so every connection is refused on the machine itself.
public func test_createOfflineFixtureAccount(
    rootPath: String,
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    networkArguments: NetworkInitializationArguments,
    encryptionParameters: ValueBoxEncryptionParameters
) -> Signal<Never, NoError> {
    let hermeticProxy = accountManager.transaction { transaction -> AccountRecordId? in
        let _ = updateProxySettingsInteractively(transaction: transaction) { _ in
            let loopback = ProxyServerSettings(host: "127.0.0.1", port: 1, connection: .socks5(username: nil, password: nil))
            return ProxySettings(enabled: true, servers: [loopback], activeServer: loopback, useForCalls: false, webSocketTransportEnabled: false, webSocketFallbackToDirect: false)
        }
        let record = transaction.createAuth([.environment(AccountEnvironmentAttribute(environment: .production))])
        return record?.id
    }

    return hermeticProxy
    |> mapToSignal { recordId -> Signal<AccountResult, NoError> in
        guard let recordId else {
            return .complete()
        }
        return accountWithId(
            accountManager: accountManager,
            networkArguments: networkArguments,
            id: recordId,
            encryptionParameters: encryptionParameters,
            supplementary: true,
            isSupportUser: false,
            rootPath: rootPath,
            beginWithTestingEnvironment: false,
            backupData: nil,
            auxiliaryMethods: AccountAuxiliaryMethods(fetchResource: { _, _, _, _ in
                return nil
            }, fetchResourceMediaReferenceHash: { _ in
                return .single(nil)
            }, prepareSecretThumbnailData: { _ in
                return nil
            }, backgroundUpload: { _, _, _ in
                return .single(nil)
            }),
            shouldKeepAutoConnection: false
        )
    }
    |> take(1)
    |> mapToSignal { result -> Signal<Never, NoError> in
        guard case let .unauthorized(account) = result else {
            return .complete()
        }
        return account.postbox.transaction { transaction -> Void in
            test_seedOfflineFixture(transaction: transaction, seedConfiguration: account.postbox.seedConfiguration, appVersion: networkArguments.appVersion)
        }
        |> mapToSignal { _ -> Signal<Never, NoError> in
            return accountManager.transaction { transaction -> Void in
                switchToAuthorizedAccount(transaction: transaction, account: account, isSupportUser: false)
            }
            |> ignoreValues
        }
    }
}

private let fixtureSelfPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777001))

private func fixtureUser(_ id: Int64, _ firstName: String, _ lastName: String?, phone: String? = nil) -> TelegramUser {
    return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id)), accessHash: nil, firstName: firstName, lastName: lastName, username: nil, phone: phone, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
}

private func fixtureChannel(_ id: Int64, _ title: String) -> TelegramChannel {
    return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(id)), accessHash: nil, title: title, username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .broadcast(TelegramChannelBroadcastInfo(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
}

private func test_seedOfflineFixture(transaction: Transaction, seedConfiguration: SeedConfiguration, appVersion: String) {
    // What a real sign-in does to a fresh postbox (`signUpWithName`): no chat list hole to fill, app settings, state.
    if let hole = seedConfiguration.initializeChatListWithHole.topLevel {
        transaction.replaceChatListHole(groupId: .root, index: hole.index, hole: nil)
    }
    if let hole = seedConfiguration.initializeChatListWithHole.groups {
        transaction.replaceChatListHole(groupId: Namespaces.PeerGroup.archive, index: hole.index, hole: nil)
    }
    initializedAppSettingsAfterLogin(transaction: transaction, appVersion: appVersion, syncContacts: false)

    let me = fixtureUser(777001, "Анна", "Смирнова", phone: "79991234567")
    let maria = fixtureUser(1001, "Мария", "Козлова")
    let victor = fixtureUser(1002, "Виктор", "Кравцов")
    let alexey = fixtureUser(1003, "Алексей", "Морозов")
    let team = fixtureChannel(2001, "Команда BananaGram")
    let news = fixtureChannel(2002, "Новости BananaGram")
    let design = fixtureChannel(2003, "Дизайн-сообщество")
    let trip = fixtureChannel(2004, "Заметки о поездке")
    updatePeersCustom(transaction: transaction, peers: [me, maria, victor, alexey, team, news, design, trip], update: { _, updated in updated })
    // What a server would have filled in on first open: the users' cached data, and the three people as contacts, so a
    // private chat opens as one with a contact instead of waiting for data no server will send. A user's chat (Saved
    // Messages included) shows its history only once the business intro is known (`isPossibleIntroLoaded` in
    // ChatHistoryViewForLocation), and `CachedUserData()` leaves it `.unknown`: known-and-absent opens the chat. Empty
    // status settings are a contact's, with no report panel.
    let userIds: Set<PeerId> = [me.id, maria.id, victor.id, alexey.id]
    transaction.updatePeerCachedData(peerIds: userIds, update: { _, current in
        let data = (current as? CachedUserData) ?? CachedUserData()
        return data.withUpdatedBusinessIntro(nil).withUpdatedPeerStatusSettings(PeerStatusSettings())
    })
    transaction.replaceContactPeerIds([maria.id, victor.id, alexey.id])

    let now = Int32(Date().timeIntervalSince1970)
    let minute: Int32 = 60
    let day: Int32 = 24 * 60 * minute

    // (peer, archived, unread count, messages: (seconds ago, outgoing, text))
    let chats: [(peer: Peer, archived: Bool, unread: Int, messages: [(ago: Int32, outgoing: Bool, text: String)])] = [
        (maria as Peer, false, 2, [
            (52 * minute, true, "Привет! Как идёт работа над новым дизайном?"),
            (14 * minute, false, "Отлично, почти готово."),
            (3 * minute, false, "Жду фотографий с поездки 🙂")
        ]),
        (team as Peer, false, 4, [
            (3 * 60 * minute, false, "Сегодня созвон в 11:00."),
            (2 * 60 * minute, false, "Новый набор экранов готов."),
            (40 * minute, false, "Посмотрите список чатов и настройки."),
            (20 * minute, false, "Алексей: макеты обновлены")
        ]),
        (news as Peer, false, 0, [
            (90 * minute, false, "Вышло обновление клиента: новый список чатов и системная навигация.")
        ]),
        (alexey as Peer, false, 0, [
            (day + 5 * 60 * minute, false, "Голосовое сообщение · 0:18"),
            (day + 4 * 60 * minute, true, "Спасибо, послушаю вечером")
        ]),
        (design as Peer, false, 1, [
            (day + 2 * 60 * minute, false, "Новые идеи для интерфейса")
        ]),
        (victor as Peer, false, 0, [
            (3 * day, false, "Пришли, пожалуйста, новые макеты"),
            (3 * day - 30 * minute, true, "Спасибо, посмотрю вечером")
        ]),
        (me as Peer, false, 0, [
            (4 * day, true, "Эскиз интерфейса"),
            (4 * day - 10 * minute, true, "Список чатов: системная типографика, компактные строки, единые отступы.")
        ]),
        (trip as Peer, true, 0, [
            (6 * day, false, "Фотографии с поездки — в альбоме.")
        ])
    ]

    var readStates: [PeerId: [MessageId.Namespace: PeerReadState]] = [:]
    // Cloud message ids of private chats and basic groups are global to the account (`globalMessageIdsPeerIdNamespaces`),
    // so they are numbered across those chats; a channel numbers its own. Overlapping ids left private chats loading.
    var nextGlobalId: Int32 = 1
    for chat in chats {
        let peerId = chat.peer.id
        let usesGlobalIds = peerId.namespace != Namespaces.Peer.CloudChannel
        // Saved Messages are threads keyed by the saved peer; a note written by the account is its own thread.
        let threadId: Int64? = peerId == fixtureSelfPeerId ? fixtureSelfPeerId.toInt64() : nil
        var storeMessages: [StoreMessage] = []
        var lastId: Int32 = 0
        var firstId: Int32 = 1
        for (index, message) in chat.messages.enumerated() {
            let idValue: Int32
            if usesGlobalIds {
                idValue = nextGlobalId
                nextGlobalId += 1
            } else {
                idValue = Int32(index + 1)
            }
            if index == 0 {
                firstId = idValue
            }
            lastId = idValue
            let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: idValue)
            // A channel post's author is the channel; a private chat's incoming message is the other user's.
            let authorId: PeerId = message.outgoing ? fixtureSelfPeerId : peerId
            var flags: StoreMessageFlags = []
            if !message.outgoing {
                flags.insert(.Incoming)
            }
            storeMessages.append(StoreMessage(id: id, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: threadId, timestamp: now - message.ago, flags: flags, tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: authorId, text: message.text, attributes: [], media: []))
        }
        let _ = transaction.addMessages(storeMessages, location: .Random)
        // No history hole: the chat opens on these messages instead of waiting for a server.
        transaction.removeHole(peerId: peerId, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... Int32.max)
        if let threadId {
            transaction.removeHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... Int32.max)
        }
        // The read mark sits `unread` messages before the last one (the ids are not contiguous across chats).
        let unreadFromIndex = max(0, chat.messages.count - chat.unread)
        let maxIncomingReadId: Int32 = unreadFromIndex == 0 ? max(0, firstId - 1) : (usesGlobalIds ? firstId + Int32(unreadFromIndex) - 1 : Int32(unreadFromIndex))
        readStates[peerId] = [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: maxIncomingReadId, maxOutgoingReadId: lastId, maxKnownId: lastId, count: Int32(chat.unread), markedUnread: false)]
        transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: chat.archived ? Namespaces.PeerGroup.archive : .root, pinningIndex: nil, minTimestamp: nil))
    }
    transaction.resetIncomingReadStates(readStates)

    transaction.setState(AuthorizedAccountState(isTestingEnvironment: false, masterDatacenterId: 2, peerId: fixtureSelfPeerId, state: nil, invalidatedChannels: []))
}
