import Foundation
import Postbox
import TelegramApi

extension ReplyMarkupButtonAction.PeerTypes {
    init(apiType: [Api.InlineQueryPeerType]) {
        var rawValue: Int32 = 0
        for type in apiType {
            switch type {
            case .inlineQueryPeerTypePM:
                rawValue |= ReplyMarkupButtonAction.PeerTypes.users.rawValue
            case .inlineQueryPeerTypeBotPM:
                rawValue |= ReplyMarkupButtonAction.PeerTypes.bots.rawValue
            case .inlineQueryPeerTypeBroadcast:
                rawValue |= ReplyMarkupButtonAction.PeerTypes.channels.rawValue
            case .inlineQueryPeerTypeChat, .inlineQueryPeerTypeMegagroup:
                rawValue |= ReplyMarkupButtonAction.PeerTypes.groups.rawValue
            case .inlineQueryPeerTypeSameBotPM:
                break
            }
        }
        self.init(rawValue: rawValue)
    }
}

extension ReplyMarkupButtonRequestPeerType {
    init(apiType peerType: Api.RequestPeerType) {
            switch peerType {
            case let .requestPeerTypeUser(requestPeerTypeUserData):
                let (bot, premium) = (requestPeerTypeUserData.bot, requestPeerTypeUserData.premium)
                self = .user(ReplyMarkupButtonRequestPeerType.User(
                    isBot: bot.flatMap({ $0 == .boolTrue }),
                    isPremium: premium.flatMap({ $0 == .boolTrue })
                ))
            case let .requestPeerTypeChat(requestPeerTypeChatData):
                let (flags, hasUsername, forum, userAdminRights, botAdminRights) = (requestPeerTypeChatData.flags, requestPeerTypeChatData.hasUsername, requestPeerTypeChatData.forum, requestPeerTypeChatData.userAdminRights, requestPeerTypeChatData.botAdminRights)
                self = .group(ReplyMarkupButtonRequestPeerType.Group(
                    isCreator: (flags & (1 << 0)) != 0,
                    hasUsername: hasUsername.flatMap({ $0 == .boolTrue }),
                    isForum: forum.flatMap({ $0 == .boolTrue }),
                    botParticipant: (flags & (1 << 5)) != 0,
                    userAdminRights: userAdminRights.flatMap(TelegramChatAdminRights.init(apiAdminRights:)),
                    botAdminRights: botAdminRights.flatMap(TelegramChatAdminRights.init(apiAdminRights:))
                ))
            case let .requestPeerTypeBroadcast(requestPeerTypeBroadcastData):
                let (flags, hasUsername, userAdminRights, botAdminRights) = (requestPeerTypeBroadcastData.flags, requestPeerTypeBroadcastData.hasUsername, requestPeerTypeBroadcastData.userAdminRights, requestPeerTypeBroadcastData.botAdminRights)
                self = .channel(ReplyMarkupButtonRequestPeerType.Channel(
                    isCreator: (flags & (1 << 0)) != 0,
                    hasUsername: hasUsername.flatMap({ $0 == .boolTrue }),
                    userAdminRights: userAdminRights.flatMap(TelegramChatAdminRights.init(apiAdminRights:)),
                    botAdminRights: botAdminRights.flatMap(TelegramChatAdminRights.init(apiAdminRights:))
                ))
            case let .requestPeerTypeCreateBot(data):
                self = .createBot(ReplyMarkupButtonRequestPeerType.CreateBot(
                    suggestedName: data.suggestedName,
                    suggestedUsername: data.suggestedUsername
                ))
            }
    }
}

extension ReplyMarkupButton {
    init(apiButton: Api.KeyboardButton) {
        switch apiButton {
        case let .keyboardButton(button):
            let action: ReplyMarkupButtonAction
            switch button.type {
            case .buttonTypeDefault: action = .text
            case .buttonTypeRequestPhone: action = .requestPhone
            case .buttonTypeRequestGeoLocation: action = .requestMap
            case let .buttonTypeRequestPoll(value): action = .setupPoll(isQuiz: value.quiz.map { $0 == .boolTrue })
            case let .buttonTypeRequestPeer(value):
                action = .requestPeer(peerType: ReplyMarkupButtonRequestPeerType(apiType: value.peerType), buttonId: value.buttonId, maxQuantity: value.maxQuantity)
            case let .inputButtonTypeRequestPeer(value):
                action = .requestPeer(peerType: ReplyMarkupButtonRequestPeerType(apiType: value.peerType), buttonId: value.buttonId, maxQuantity: value.maxQuantity)
            case let .buttonTypeSimpleWebView(value): action = .openWebView(url: value.url, simple: true)
            }
            self.init(title: button.text, titleWhenForwarded: nil, action: action, style: button.style.flatMap(ReplyMarkupButton.Style.init(apiStyle:)))
        }
    }

    init(apiButton: Api.KeyboardInlineButton) {
        switch apiButton {
        case let .keyboardInlineButton(button):
            var forwardedTitle: String?
            let action: ReplyMarkupButtonAction
            switch button.type {
            case let .inlineButtonTypeUrl(value): action = .url(value.url)
            case let .inlineButtonTypeUrlAuth(value):
                forwardedTitle = value.fwdText
                action = .urlAuth(url: value.url, buttonId: value.buttonId)
            case let .inputInlineButtonTypeUrlAuth(value):
                forwardedTitle = value.fwdText
                action = .urlAuth(url: value.url, buttonId: 0)
            case let .inlineButtonTypeWebView(value): action = .openWebView(url: value.url, simple: false)
            case let .inlineButtonTypeCallback(value):
                let data = value.data
                let memory = malloc(max(1, data.size))!
                memcpy(memory, data.data, data.size)
                action = .callback(requiresPassword: (value.flags & 1) != 0, data: MemoryBuffer(memory: memory, capacity: data.size, length: data.size, freeWhenDone: true))
            case .inlineButtonTypeGame: action = .openWebApp
            case .inlineButtonTypeBuy: action = .payment
            case let .inlineButtonTypeSwitchInline(value):
                action = .switchInline(samePeer: (value.flags & 1) != 0, query: value.query, peerTypes: ReplyMarkupButtonAction.PeerTypes(apiType: value.peerTypes ?? []))
            case let .inlineButtonTypeUserProfile(value):
                action = .openUserProfile(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value.userId)))
            case .inputInlineButtonTypeUserProfile: action = .disabled
            case let .inlineButtonTypeCopy(value): action = .copyText(payload: value.copyText)
            case .inlineButtonTypeDisabled: action = .disabled
            }
            self.init(title: button.text, titleWhenForwarded: forwardedTitle, action: action, style: button.style.flatMap(ReplyMarkupButton.Style.init(apiStyle:)))
        }
    }
}

extension ReplyMarkupRow {
    init(apiRow: Api.KeyboardInlineButtonRow) {
        switch apiRow {
        case let .keyboardInlineButtonRow(value):
            self.init(buttons: value.buttons.map { ReplyMarkupButton(apiButton: $0) })
        }
    }

    init(apiRow: Api.KeyboardButtonRow) {
        switch apiRow {
            case let .keyboardButtonRow(keyboardButtonRowData):
                let buttons = keyboardButtonRowData.buttons
                self.init(buttons: buttons.map { ReplyMarkupButton(apiButton: $0) })
        }
    }
}

extension ReplyMarkupMessageAttribute {
    convenience init(apiMarkup: Api.ReplyMarkup) {
        var rows: [ReplyMarkupRow] = []
        var flags = ReplyMarkupMessageFlags()
        var placeholder: String?
        switch apiMarkup {
            case let .replyKeyboardMarkup(replyKeyboardMarkupData):
                let (markupFlags, apiRows, apiPlaceholder) = (replyKeyboardMarkupData.flags, replyKeyboardMarkupData.rows, replyKeyboardMarkupData.placeholder)
                rows = apiRows.map { ReplyMarkupRow(apiRow: $0) }
                if (markupFlags & (1 << 0)) != 0 {
                    flags.insert(.fit)
                }
                if (markupFlags & (1 << 1)) != 0 {
                    flags.insert(.once)
                }
                if (markupFlags & (1 << 2)) != 0 {
                    flags.insert(.personal)
                }
                if (markupFlags & (1 << 4)) != 0 {
                    flags.insert(.persistent)
                }
                placeholder = apiPlaceholder
            case let .replyInlineMarkup(replyInlineMarkupData):
                let apiRows = replyInlineMarkupData.rows
                rows = apiRows.map { ReplyMarkupRow(apiRow: $0) }
                flags.insert(.inline)
                if (replyInlineMarkupData.flags & (1 << 5)) != 0 { flags.insert(.setupReply) }
            case let .replyKeyboardForceReply(replyKeyboardForceReplyData):
                let (forceReplyFlags, apiPlaceholder) = (replyKeyboardForceReplyData.flags, replyKeyboardForceReplyData.placeholder)
                if (forceReplyFlags & (1 << 1)) != 0 {
                    flags.insert(.once)
                }
                if (forceReplyFlags & (1 << 2)) != 0 {
                    flags.insert(.personal)
                }
                flags.insert(.setupReply)
                placeholder = apiPlaceholder
            case let .replyKeyboardHide(replyKeyboardHideData):
                let hideFlags = replyKeyboardHideData.flags
                if (hideFlags & (1 << 2)) != 0 {
                    flags.insert(.personal)
                }
        }
        self.init(rows: rows, flags: flags, placeholder: placeholder)
    }
}
