import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import MtProtoKit
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import UrlEscaping
import UrlHandling
import QrCodeUI
import WebProxyTransport
import TelegramVLESS

private final class ProxyServerSettingsControllerArguments {
    let context: AccountContext?
    let updateState: ((ProxyServerSettingsControllerState) -> ProxyServerSettingsControllerState) -> Void
    let share: () -> Void
    let usePasteboardSettings: () -> Void
    
    init(context: AccountContext?, updateState: @escaping ((ProxyServerSettingsControllerState) -> ProxyServerSettingsControllerState) -> Void, share: @escaping () -> Void, usePasteboardSettings: @escaping () -> Void) {
        self.context = context
        self.updateState = updateState
        self.share = share
        self.usePasteboardSettings = usePasteboardSettings
    }
}

private enum ProxySettingsSection: Int32 {
    case pasteboard
    case mode
    case connection
    case credentials
    case share
}

private enum ProxySettingsEntry: ItemListNodeEntry {
    case usePasteboardSettings(PresentationTheme, String)
    
    case modeSocks5(PresentationTheme, String, Bool)
    case modeMtp(PresentationTheme, String, Bool)
    case modeWeb(PresentationTheme, String, Bool)
    case webInfo(PresentationTheme, String)
    case modeVless(PresentationTheme, String, Bool)
    case vlessInfo(PresentationTheme, VlessEditorFeedback)
    case socks5Info(PresentationTheme, String)
    case mtpInfo(PresentationTheme, String)
    
    case connectionHeader(PresentationTheme, String)
    case connectionServer(PresentationTheme, PresentationStrings, String, String)
    case connectionVless(PresentationTheme, String)
    case connectionPort(PresentationTheme, PresentationStrings, String, String)
    
    case credentialsHeader(PresentationTheme, String)
    case credentialsUsername(PresentationTheme, PresentationStrings, String, String)
    case credentialsPassword(PresentationTheme, PresentationStrings, String, String)
    case credentialsSecret(PresentationTheme, PresentationStrings, String, String)
    
    case share(PresentationTheme, String, Bool)
    
    var section: ItemListSectionId {
        switch self {
            case .usePasteboardSettings:
                return ProxySettingsSection.pasteboard.rawValue
            case .modeSocks5, .modeMtp, .modeWeb, .webInfo, .modeVless, .socks5Info, .mtpInfo:
                return ProxySettingsSection.mode.rawValue
            case .connectionHeader, .connectionServer, .connectionVless, .vlessInfo, .connectionPort:
                return ProxySettingsSection.connection.rawValue
            case .credentialsHeader, .credentialsUsername, .credentialsPassword, .credentialsSecret:
                return ProxySettingsSection.credentials.rawValue
            case .share:
                return ProxySettingsSection.share.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .usePasteboardSettings: return 0
            case .modeSocks5: return 1
            case .socks5Info: return 2
            case .modeMtp: return 3
            case .mtpInfo: return 4
            case .modeWeb: return 5
            case .webInfo: return 6
            case .modeVless: return 7
            case .vlessInfo: return 11
            case .connectionHeader: return 8
            case .connectionServer: return 9
            case .connectionVless: return 10
            case .connectionPort: return 12
            case .credentialsHeader: return 13
            case .credentialsUsername: return 14
            case .credentialsPassword: return 15
            case .credentialsSecret: return 16
            case .share: return 17
        }
    }

    static func <(lhs: ProxySettingsEntry, rhs: ProxySettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ProxyServerSettingsControllerArguments
        switch self {
            case let .usePasteboardSettings(_, title):
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.usePasteboardSettings()
                })
            case let .modeSocks5(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateState { state in
                        var state = state
                        state.mode = .socks5
                        return state
                    }
                })
            case let .modeMtp(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateState { state in
                        var state = state
                        state.mode = .mtp
                        return state
                    }
                })
            case let .modeWeb(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateState { state in
                        var state = state
                        state.mode = .web
                        state.port = "443"
                        return state
                    }
                })
            case let .modeVless(_, text, value):
                return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: text, style: .left, checked: value, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    arguments.updateState { state in
                        var state = state
                        state.mode = .vless
                        return state
                    }
                })
            case let .vlessInfo(_, feedback):
                if feedback.isError {
                    if let context = arguments.context {
                        let text = NSAttributedString(string: feedback.text, font: Font.regular(presentationData.fontSize.itemListBaseHeaderFontSize), textColor: presentationData.theme.list.itemDestructiveColor)
                        return ItemListTextItem(presentationData: presentationData, text: .custom(context: context, string: text), sectionId: self.section)
                    } else {
                        return ItemListTextItem(presentationData: presentationData, text: .plain(feedback.text), sectionId: self.section)
                    }
                }
                return ItemListTextItem(presentationData: presentationData, text: .plain(feedback.text), sectionId: self.section)
            case let .socks5Info(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .mtpInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .webInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .connectionHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .connectionServer(_, _, placeholder, text):
                return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                    arguments.updateState { current in
                        var state = current
                        state.host = value
                        return state
                    }
                }, action: {})
            case let .connectionVless(_, text):
                // Preserve the complete pasted link: the parser reports oversize input
                // instead of silently truncating credentials or transport parameters.
                return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "vless://…", maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, textUpdated: { value in
                    arguments.updateState { current in
                        var state = current
                        state.host = value
                        return state
                    }
                })
            case let .connectionPort(_, _, placeholder, text):
                return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .number, sectionId: self.section, textUpdated: { value in
                    arguments.updateState { current in
                        var state = current
                        state.port = value
                        return state
                    }
                }, action: {})
            case let .credentialsHeader(_, text):
                return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
            case let .credentialsUsername(_, _, placeholder, text):
                return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, sectionId: self.section, textUpdated: { value in
                    arguments.updateState { current in
                        var state = current
                        state.username = value
                        return state
                    }
                }, action: {})
            case let .credentialsPassword(_, _, placeholder, text):
                return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .password, sectionId: self.section, textUpdated: { value in
                    arguments.updateState { current in
                        var state = current
                        state.password = value
                        return state
                    }
                }, action: {})
            case let .credentialsSecret(_, _, placeholder, text):
                return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { value in
                    arguments.updateState { current in
                        var state = current
                        state.secret = value
                        return state
                    }
                }, action: {})
            case let .share(_, text, enabled):
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.share()
                })
        }
    }
}

private enum ProxyServerSettingsControllerMode {
    case socks5
    case mtp
    case web
    case vless
}

public enum ProxyServerSettingsPreferredMode {
    case socks5
    case mtp
    case web
    case vless
}

private func mapPreferredMode(_ mode: ProxyServerSettingsPreferredMode) -> ProxyServerSettingsControllerMode {
    switch mode {
    case .socks5:
        return .socks5
    case .mtp:
        return .mtp
    case .web:
        return .web
    case .vless:
        return .vless
    }
}

private struct ProxyServerSettingsControllerState: Equatable {
    var mode: ProxyServerSettingsControllerMode {
        didSet {
            if oldValue != mode {
                if oldValue == .vless {
                    vlessDraft = host
                    host = serverDraft
                } else if mode == .vless {
                    serverDraft = host
                    host = vlessDraft
                }
            }
        }
    }
    var vlessDraft = ""
    var serverDraft = ""
    var host: String
    var port: String
    var username: String
    var password: String
    var secret: String
    
    var isComplete: Bool {
        if self.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        switch self.mode {
            case .socks5:
                if Int(self.port).map({ (1...65535).contains($0) }) != true {
                    return false
                }
            case .mtp, .web:
                if MTProxySecret.parse(self.secret) == nil {
                    return false
                }
                if self.mode == .web && (!WebProxyHostname.isValid(self.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) || !isSupportedWebProxySecret(MTProxySecret.parse(self.secret)!.serialize())) {
                    return false
                }
            case .vless:
                // In VLESS mode `host` holds the full `vless://` share link.
                if !isValidVlessProxyURL(self.host.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return false
                }
        }
        if self.mode != .web && self.mode != .vless {
            if Int(self.port).map({ (1...65535).contains($0) }) != true {
                return false
            }
        }
        return true
    }
}

private func proxyServerSettingsControllerEntries(presentationData: PresentationData, state: ProxyServerSettingsControllerState, pasteboardSettings: ProxyServerSettings?) -> [ProxySettingsEntry] {
    var entries: [ProxySettingsEntry] = []
    
    if let _ = pasteboardSettings {
        entries.append(.usePasteboardSettings(presentationData.theme, presentationData.strings.SocksProxySetup_PasteFromClipboard))
    }
    
    entries.append(.modeSocks5(presentationData.theme, presentationData.strings.SocksProxySetup_ProxySocks5, state.mode == .socks5))
    if state.mode == .socks5 {
        entries.append(.socks5Info(presentationData.theme, ForkProxyDescriptionStrings.socks5))
    }
    entries.append(.modeMtp(presentationData.theme, presentationData.strings.SocksProxySetup_ProxyTelegram, state.mode == .mtp))
    if state.mode == .mtp {
        entries.append(.mtpInfo(presentationData.theme, ForkProxyDescriptionStrings.mtp))
    }
    entries.append(.modeWeb(presentationData.theme, ForkWebProxyStrings.proxyType, state.mode == .web))
    if state.mode == .web {
        entries.append(.webInfo(presentationData.theme, ForkWebProxyStrings.callsNote))
    }
    entries.append(.modeVless(presentationData.theme, "VLESS", state.mode == .vless))
    
    let connectionHeaderTitle = state.mode == .vless ? "URL" : presentationData.strings.SocksProxySetup_Connection.uppercased()
    entries.append(.connectionHeader(presentationData.theme, connectionHeaderTitle))
    let serverPlaceholder: String
    if state.mode == .web {
        serverPlaceholder = ForkWebProxyStrings.maskingSite
    } else if state.mode == .vless {
        serverPlaceholder = "vless://…"
    } else {
        serverPlaceholder = presentationData.strings.SocksProxySetup_Hostname
    }
    
    if state.mode == .vless {
        entries.append(.connectionVless(presentationData.theme, state.host))
        entries.append(.vlessInfo(presentationData.theme, vlessEditorInfo(state.host)))
    } else {
        entries.append(.connectionServer(presentationData.theme, presentationData.strings, serverPlaceholder, state.host))
    }
    
    if state.mode != .web && state.mode != .vless {
        entries.append(.connectionPort(presentationData.theme, presentationData.strings, presentationData.strings.SocksProxySetup_Port, state.port))
    }
    
    switch state.mode {
        case .vless:
            break
        case .socks5:
            entries.append(.credentialsHeader(presentationData.theme, presentationData.strings.SocksProxySetup_Credentials))
            entries.append(.credentialsUsername(presentationData.theme, presentationData.strings, presentationData.strings.SocksProxySetup_Username, state.username))
            entries.append(.credentialsPassword(presentationData.theme, presentationData.strings, presentationData.strings.SocksProxySetup_Password, state.password))
        case .mtp, .web:
            entries.append(.credentialsHeader(presentationData.theme, presentationData.strings.SocksProxySetup_RequiredCredentials))
            entries.append(.credentialsSecret(presentationData.theme, presentationData.strings, presentationData.strings.SocksProxySetup_SecretPlaceholder, state.secret))
    }
    
    entries.append(.share(presentationData.theme, presentationData.strings.Conversation_ContextMenuShare, state.isComplete))
    
    return entries
}

private func proxyServerSettings(with state: ProxyServerSettingsControllerState) -> ProxyServerSettings? {
    guard state.isComplete else {
        return nil
    }
    switch state.mode {
        case .socks5:
            guard let port = Int32(state.port) else {
                return nil
            }
            return ProxyServerSettings(host: state.host, port: port, connection: .socks5(username: state.username.isEmpty ? nil : state.username, password: state.password.isEmpty ? nil : state.password))
        case .mtp:
            guard let port = Int32(state.port), let parsedSecret = MTProxySecret.parse(state.secret) else {
                return nil
            }
            return ProxyServerSettings(host: state.host, port: port, connection: .mtp(secret: parsedSecret.serialize()))
        case .vless:
            let url = state.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidVlessProxyURL(url), let data = url.data(using: .utf8),
                  let components = URLComponents(string: url), let host = components.host, let port = components.port else {
                return nil
            }
            // host/port are stored for display; the full URL in the secret is the source of truth.
            return ProxyServerSettings(host: host, port: Int32(port), connection: .vless(secret: data))
        case .web:
            guard let parsedSecret = MTProxySecret.parse(state.secret) else {
                return nil
            }
            // A WEB proxy is a relay hostname reached over HTTPS on 443 with a plain or `dd`
            // MTProxy secret. Rejecting an IP literal or an `ee` TLS-emulation secret here keeps
            // Save disabled instead of storing a proxy that can only fail at connect time.
            let secret = parsedSecret.serialize()
            guard isSupportedWebProxySecret(secret) else {
                return nil
            }
            let host = state.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard isValidWebProxyHostname(host) else {
                return nil
            }
            return ProxyServerSettings(host: host, port: 443, connection: .web(secret: secret))
    }
}

public func proxyServerSettingsController(context: AccountContext, currentSettings: ProxyServerSettings? = nil, preferredInitialMode: ProxyServerSettingsPreferredMode? = nil) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    return proxyServerSettingsController(sharedContext: context.sharedContext, context: context, presentationData: presentationData, updatedPresentationData: context.sharedContext.presentationData, accountManager: context.sharedContext.accountManager, network: context.account.network, currentSettings: currentSettings, preferredInitialMode: preferredInitialMode)
}

func proxyServerSettingsController(sharedContext: SharedAccountContext, context: AccountContext? = nil, presentationData: PresentationData, updatedPresentationData: Signal<PresentationData, NoError>, accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network, currentSettings: ProxyServerSettings?, preferredInitialMode: ProxyServerSettingsPreferredMode? = nil) -> ViewController {
    var currentMode: ProxyServerSettingsControllerMode = preferredInitialMode.map(mapPreferredMode) ?? .socks5
    var currentUsername: String?
    var currentPassword: String?
    var currentSecret: String?
    var currentVlessURL: String?
    var pasteboardSettings: ProxyServerSettings?
    if let currentSettings = currentSettings {
        switch currentSettings.connection {
            case let .socks5(username, password):
                currentUsername = username
                currentPassword = password
                currentMode = .socks5
            case let .mtp(secret):
                currentSecret = hexString(secret)
                currentMode = .mtp
            case let .web(secret):
                currentSecret = hexString(secret)
                currentMode = .web
            case let .vless(secret):
                currentMode = .vless
                currentVlessURL = String(data: secret, encoding: .utf8)
        }
    } else if let preferredInitialMode = preferredInitialMode {
        currentMode = mapPreferredMode(preferredInitialMode)
        if currentMode == .web {
            currentSecret = ""
        }
    } else {
        let pasteboardUrl = UIPasteboard.general.string ?? ""
        let trimmedPasteboardUrl = pasteboardUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPasteboardUrl.lowercased().hasPrefix("vless://"), isValidVlessProxyURL(trimmedPasteboardUrl),
           let data = trimmedPasteboardUrl.data(using: .utf8), let components = URLComponents(string: trimmedPasteboardUrl), let host = components.host, let port = components.port {
            pasteboardSettings = ProxyServerSettings(host: host, port: Int32(port), connection: .vless(secret: data))
        } else if let webProxy = parseWebProxyUrl(sharedContext: sharedContext, url: pasteboardUrl) {
            pasteboardSettings = ProxyServerSettings(host: webProxy.host, port: 443, connection: .web(secret: webProxy.secret))
        } else if let proxy = parseProxyUrl(sharedContext: sharedContext, url: pasteboardUrl) {
            if let secret = proxy.secret, let parsedSecret = MTProxySecret.parseData(secret) {
                pasteboardSettings = ProxyServerSettings(host: proxy.host, port: proxy.port, connection: .mtp(secret: parsedSecret.serialize()))
            } else {
                pasteboardSettings = ProxyServerSettings(host: proxy.host, port: proxy.port, connection: .socks5(username: proxy.username, password: proxy.password))
            }
        }
    }

    let initialHost: String
    if currentMode == .vless {
        initialHost = currentVlessURL ?? ""
    } else {
        initialHost = currentSettings?.host ?? ""
    }
    let initialState = ProxyServerSettingsControllerState(mode: currentMode, host: initialHost, port: (currentSettings?.port).flatMap { "\($0)" } ?? "", username: currentUsername ?? "", password: currentPassword ?? "", secret: currentSecret ?? "")
    let stateValue = Atomic(value: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let updateState: ((ProxyServerSettingsControllerState) -> ProxyServerSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var pushControllerImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    
    var shareImpl: (() -> Void)?
    
    let arguments = ProxyServerSettingsControllerArguments(context: context, updateState: { f in
        updateState(f)
    }, share: {
        shareImpl?()
    }, usePasteboardSettings: {
        if let pasteboardSettings = pasteboardSettings {
            updateState { state in
                var state = state
                state.port = "\(pasteboardSettings.port)"
                switch pasteboardSettings.connection {
                    case let .socks5(username, password):
                        state.mode = .socks5
                        state.host = pasteboardSettings.host
                        state.username = username ?? ""
                        state.password = password ?? ""
                    case let .mtp(secret):
                        state.mode = .mtp
                        state.host = pasteboardSettings.host
                        state.secret = hexString(secret)
                    case let .web(secret):
                        state.mode = .web
                        state.host = pasteboardSettings.host
                        state.port = "443"
                        state.secret = hexString(secret)
                    case let .vless(secret):
                        state.mode = .vless
                        state.host = String(data: secret, encoding: .utf8) ?? ""
                }
                return state
            }
        }
    })
    
    let signal = combineLatest(updatedPresentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, ProxyServerSettingsControllerArguments)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)
        
        let leftNavigationButton = ItemListNavigationButton(content: .icon(.close), style: .regular, enabled: true, action: {
            dismissImpl?()
        })
        let rightNavigationButton = ItemListNavigationButton(content: .icon(.done), style: .bold, enabled: state.isComplete, action: {
            if let proxyServerSettings = proxyServerSettings(with: state) {
                let _ = (updateProxySettingsInteractively(accountManager: accountManager, { settings in
                    var settings = settings
                    if let currentSettings = currentSettings {
                        if let index = settings.servers.firstIndex(of: currentSettings) {
                            settings.servers[index] = proxyServerSettings
                            if settings.activeServer == currentSettings {
                                settings.activeServer = proxyServerSettings
                            }
                        }
                    } else {
                        let wasEmpty = settings.servers.isEmpty
                        if !settings.servers.contains(proxyServerSettings) {
                            settings.servers.append(proxyServerSettings)
                        }
                        if wasEmpty && settings.servers.count == 1 {
                            settings.activeServer = proxyServerSettings
                        }
                    }
                    return settings
                }) |> deliverOnMainQueue).start(completed: {
                    dismissImpl?()
                })
            }
        })
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(presentationData.strings.SocksProxySetup_Title), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: proxyServerSettingsControllerEntries(presentationData: presentationData, state: state, pasteboardSettings: pasteboardSettings), style: .blocks, emptyStateItem: nil, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: updatedPresentationData |> map { ItemListPresentationData($0) }, state: signal, tabBarItem: nil)
    controller.navigationPresentation = .modal
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    dismissImpl = { [weak controller] in
        let _ = controller?.dismiss()
    }
    shareImpl = { [weak controller] in
        let state = stateValue.with { $0 }
        guard let server = proxyServerSettings(with: state) else {
            return
        }
        controller?.view.endEditing(true)
        
        let controller = QrCodeScreen(
            sharedContext: sharedContext,
            updatedPresentationData: (presentationData, updatedPresentationData),
            subject: .proxy(server: server, externalLink: false)
        )
        pushControllerImpl?(controller)
    }
    
    return controller
}
