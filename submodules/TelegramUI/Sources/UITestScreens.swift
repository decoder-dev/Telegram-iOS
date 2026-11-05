import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import ChatListUI
import SettingsUI
import TelegramUIPreferences

private var uiTestScreenStarted = false

/// Simulator QA: `--ui-test --ui-test-screen <name>` opens that screen a few seconds after the
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
    // The fork does not follow the system appearance (one selected theme, no automatic switching), so a dark
    // screenshot needs the dark theme selected: `--ui-test-theme <day|night|cream|graphite>`.
    if let themeIndex = arguments.firstIndex(of: "--ui-test-theme"), themeIndex + 1 < arguments.count {
        let builtin: PresentationBuiltinThemeReference?
        switch arguments[themeIndex + 1] {
        case "day": builtin = .dayClassic
        case "night": builtin = .night
        case "cream": builtin = .bananaGramCream
        case "graphite": builtin = .bananaGramGraphite
        default: builtin = nil
        }
        if let builtin {
            let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                return settings.withUpdatedTheme(.builtin(builtin))
            }).startStandalone()
        }
    }
    Queue.mainQueue().after(3.0) {
        // `url:<tg link>` opens one of the app's own links in place (`simctl openurl` stops at a system confirmation).
        if screen.hasPrefix("url:"), let url = URL(string: String(screen.dropFirst(4))) {
            applicationContext.openUrl(url, external: true)
            return
        }
        switch screen {
        case "settings":
            rootController.openSettings(edit: false)
        case "contacts":
            rootController.openContacts()
        case "archive":
            rootController.pushViewController(ChatListControllerImpl(context: context, location: .chatList(groupId: .archive), controlsHistoryPreload: false, enableDebugActions: false))
        case "search":
            rootController.openChatsController(activateSearch: true)
        case "compose":
            rootController.pushViewController(context.sharedContext.makeComposeController(context: context))
        case "archive-settings":
            rootController.pushViewController(archiveSettingsController(context: context))
        case "banana-security":
            rootController.pushViewController(bananaSecurityController(context: context))
        case "accounts":
            rootController.pushViewController(accountOrderController(context: context))
        case "extras":
            rootController.pushViewController(forkExtrasController(context: context))
        case "saved":
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
            |> deliverOnMainQueue).startStandalone(next: { peer in
                guard let peer else {
                    return
                }
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: rootController, context: context, chatLocation: .peer(peer)))
            })
        default:
            // `chat:user:<id>` / `chat:channel:<id>` opens a fixture chat; `extras:<page>` an Extras page.
            let parts = screen.split(separator: ":").map(String.init)
            if parts.count == 3, parts[0] == "chat", let id = Int64(parts[2]) {
                let namespace = parts[1] == "channel" ? Namespaces.Peer.CloudChannel : Namespaces.Peer.CloudUser
                let peerId = EnginePeer.Id(namespace: namespace, id: EnginePeer.Id.Id._internalFromInt64Value(id))
                let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> deliverOnMainQueue).startStandalone(next: { peer in
                    guard let peer else {
                        return
                    }
                    context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: rootController, context: context, chatLocation: .peer(peer)))
                })
            } else if parts.count == 2, parts[0] == "extras" {
                let focus: ForkExtrasControllerFocus?
                switch parts[1] {
                case "appearance": focus = .appearance
                case "ninja": focus = .ninja
                case "ghost": focus = .ghost
                case "privacy": focus = .privacy
                case "chatList": focus = .chatList
                case "tabBar": focus = .tabBar
                case "messages": focus = .messages
                case "sending": focus = .messageSending
                case "actions": focus = .messageActions
                case "voice": focus = .voiceAndRound
                case "media": focus = .media
                case "profile": focus = .profile
                case "network": focus = .network
                default: focus = nil
                }
                if let focus {
                    rootController.pushViewController(forkExtrasController(context: context, focus: focus))
                }
            }
        }
    }
}
