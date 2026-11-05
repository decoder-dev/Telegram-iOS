import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import ChatListUI

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
