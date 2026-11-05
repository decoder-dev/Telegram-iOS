import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import ChatListUI

/// Simulator QA: fills a freshly signed-in test-environment account with a few chats, so the chat list, a chat and the
/// profile have real content on the screenshots. Runs once per launch, and only with `--ui-test --ui-test-seed`
/// (`--ui-test` is the separate, disposable test data directory and test servers). Writes `ui-test-seed.done` to
/// Documents when every message has been handed to the send queue.
private var uiTestSeedStarted = false

func runUITestSeedIfRequested(context: AccountContext) {
    let arguments = CommandLine.arguments
    guard arguments.contains("--ui-test"), arguments.contains("--ui-test-seed"), !uiTestSeedStarted else {
        return
    }
    uiTestSeedStarted = true

    let markerUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ui-test-seed.done")
    let _ = try? FileManager.default.removeItem(at: markerUrl)

    let account = context.account
    func send(_ text: String, to peerId: EnginePeer.Id) -> Signal<Void, NoError> {
        return enqueueMessages(account: account, peerId: peerId, messages: [.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])])
        |> map { _ -> Void in
            return Void()
        }
    }

    let channels: [(title: String, posts: [String], archived: Bool)] = [
        ("Заметки о поездке", ["Фотографии с поездки — в альбоме."], true),
        ("Дизайн-сообщество", ["Новые идеи для интерфейса"], false),
        ("Новости BananaGram", ["Вышло обновление клиента: новый список чатов и системная навигация."], false),
        ("Команда BananaGram", ["Макеты списка чатов готовы к проверке.", "Посмотрите, как выглядит крупный текст."], false)
    ]

    var signal: Signal<Void, NoError> = .single(Void())
    for channel in channels {
        signal = signal
        |> then(
            context.engine.peers.createChannel(title: channel.title, description: nil)
            |> map(Optional.init)
            |> `catch` { error -> Signal<EnginePeer.Id?, NoError> in
                NSLog("[UITestSeed] createChannel \(channel.title) failed: \(error)")
                return .single(nil)
            }
            |> mapToSignal { peerId -> Signal<Void, NoError> in
                guard let peerId else {
                    return .complete()
                }
                var posts: Signal<Void, NoError> = .complete()
                for post in channel.posts {
                    posts = posts |> then(send(post, to: peerId))
                }
                if channel.archived {
                    // One chat in the Archive, so the Archive row and the Archive list have content.
                    posts = posts |> then(context.engine.peers.updatePeersGroupIdInteractively(peerIds: [peerId], groupId: .archive) |> map { _ -> Void in } |> then(.single(Void())))
                }
                return posts
            }
        )
    }
    let savedMessages = account.peerId
    for text in ["Эскиз интерфейса", "Список чатов: системная типографика, компактные строки, единые отступы.", "Привет! Как идёт работа над новым дизайном?"] {
        signal = signal |> then(send(text, to: savedMessages))
    }

    let _ = (signal
    |> deliverOnMainQueue).startStandalone(completed: {
        NSLog("[UITestSeed] completed")
        let _ = try? Data("ok".utf8).write(to: markerUrl)
    })
}

private var uiTestScreenStarted = false

/// Simulator QA: `--ui-test --ui-test-screen <chats|saved|settings|contacts|archive>` opens that screen a few seconds after the
/// account is ready, so the workflow can take its screenshot without driving the UI. `chats` is the launch screen.
func runUITestScreenIfRequested(applicationContext: AuthorizedApplicationContext) {
    let arguments = CommandLine.arguments
    guard arguments.contains("--ui-test"), let index = arguments.firstIndex(of: "--ui-test-screen"), index + 1 < arguments.count, !uiTestScreenStarted else {
        return
    }
    uiTestScreenStarted = true
    let screen = arguments[index + 1]
    let context = applicationContext.context
    let rootController = applicationContext.rootController
    Queue.mainQueue().after(3.0) {
        switch screen {
        case "settings":
            rootController.openSettings(edit: false)
        case "contacts":
            rootController.openContacts()
        case "archive":
            rootController.pushViewController(ChatListControllerImpl(context: context, location: .chatList(groupId: .archive), controlsHistoryPreload: false, enableDebugActions: false))
        case "saved":
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
            |> deliverOnMainQueue).startStandalone(next: { peer in
                guard let peer else {
                    return
                }
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: rootController, context: context, chatLocation: .peer(peer)))
            })
        default:
            break
        }
    }
}
