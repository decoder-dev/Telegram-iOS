import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils

/// Scene 45: how the app reaches Telegram right now, read from the network's own state.
///
/// Every value comes from a live source: the connection status of the network, the active proxy server (its kind and
/// host only, never a secret, a password or a link) and the last check `ProxyServersStatuses` made of that server. A
/// value the app does not know is shown as not known, never as a made-up number.
private enum ProxyConnectionStatusStrings {
    private static var ru: Bool {
        return ForkPresentationLanguage.prefersRussianStrings
    }

    static var title: String { ru ? "Статус соединения" : "Connection Status" }
    static var connected: String { ru ? "Подключено" : "Connected" }
    static var connecting: String { ru ? "Подключение…" : "Connecting…" }
    static var updating: String { ru ? "Обновление…" : "Updating…" }
    static var noProxy: String { ru ? "Без прокси" : "No proxy" }
    static var header: String { ru ? "СОЕДИНЕНИЕ" : "CONNECTION" }
    static var route: String { ru ? "Маршрут" : "Route" }
    static var routeProxy: String { ru ? "Через прокси" : "Through a proxy" }
    static var routeDirect: String { ru ? "Напрямую" : "Direct" }
    static var state: String { ru ? "Состояние" : "State" }
    static var stateReady: String { ru ? "Готово" : "Ready" }
    static var lastResponse: String { ru ? "Последний отклик" : "Last Response" }
    static func milliseconds(_ value: Int) -> String { ru ? "\(value) мс" : "\(value) ms" }
    static var footer: String { ru ? "Отклик — время проверки выбранного сервера. Секреты и ключи подключения здесь не показываются." : "The response is the time the selected server took to answer a check. Connection secrets and keys are never shown here." }
}

private enum ProxyConnectionStatusEntry: ItemListNodeEntry {
    case card(title: String, detail: String, connected: Bool)
    case header(String)
    case route(String, String)
    case state(String, String)
    case lastResponse(String, String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .card:
            return 0
        case .header, .route, .state, .lastResponse, .footer:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .card:
            return 0
        case .header:
            return 1
        case .route:
            return 2
        case .state:
            return 3
        case .lastResponse:
            return 4
        case .footer:
            return 5
        }
    }

    static func <(lhs: ProxyConnectionStatusEntry, rhs: ProxyConnectionStatusEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .card(title, detail, _):
            // The state and the server, as a row with its value: no card, no icon.
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .route(title, value), let .state(title, value), let .lastResponse(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// The kind of a server, as the proxy list names it.
func proxyConnectionKindTitle(_ connection: ProxyServerConnection) -> String {
    switch connection {
    case .socks5:
        return "SOCKS5"
    case .mtp:
        return "MTProto"
    case .web:
        return "WEB"
    case .vless:
        return "VLESS"
    }
}

private func proxyConnectionStatusEntries(strings: PresentationStrings, proxySettings: ProxySettings, statuses: [ProxyServerSettings: ProxyServerStatus], connectionStatus: ConnectionStatus) -> [ProxyConnectionStatusEntry] {
    let title: String
    let stateValue: String
    var connected = false
    switch connectionStatus {
    case .waitingForNetwork:
        title = strings.State_WaitingForNetwork
        stateValue = strings.State_WaitingForNetwork
    case .connecting:
        title = ProxyConnectionStatusStrings.connecting
        stateValue = ProxyConnectionStatusStrings.connecting
    case .updating:
        title = ProxyConnectionStatusStrings.connected
        stateValue = ProxyConnectionStatusStrings.updating
        connected = true
    case .online:
        title = ProxyConnectionStatusStrings.connected
        stateValue = ProxyConnectionStatusStrings.stateReady
        connected = true
    }

    var entries: [ProxyConnectionStatusEntry] = []
    let server = proxySettings.effectiveActiveServer
    if let server {
        entries.append(.card(title: title, detail: "\(proxyConnectionKindTitle(server.connection)) · \(server.host)", connected: connected))
    } else {
        entries.append(.card(title: title, detail: ProxyConnectionStatusStrings.noProxy, connected: connected))
    }
    entries.append(.header(ProxyConnectionStatusStrings.header))
    entries.append(.route(ProxyConnectionStatusStrings.route, server == nil ? ProxyConnectionStatusStrings.routeDirect : ProxyConnectionStatusStrings.routeProxy))
    entries.append(.state(ProxyConnectionStatusStrings.state, stateValue))
    if let server {
        let response: String
        if case .web = server.connection {
            // ProxyServersStatuses never pings a WEB server; the proxy list says the same.
            response = strings.SocksProxySetup_ProxyStatusNotTested
        } else {
            switch statuses[server] {
            case let .available(rtt):
                response = ProxyConnectionStatusStrings.milliseconds(Int(rtt * 1000.0))
            case .checking:
                response = strings.SocksProxySetup_ProxyStatusChecking
            case .notAvailable:
                response = strings.SocksProxySetup_ProxyStatusUnavailable
            case .notChecked, .none:
                response = strings.SocksProxySetup_ProxyStatusNotTested
            }
        }
        entries.append(.lastResponse(ProxyConnectionStatusStrings.lastResponse, response))
    }
    entries.append(.footer(ProxyConnectionStatusStrings.footer))
    return entries
}

/// Opened from the connection card at the top of the proxy list; shares that list's signals, so its pings keep running.
func proxyConnectionStatusController(
    presentationData: PresentationData,
    updatedPresentationData: Signal<PresentationData, NoError>,
    proxySettings: Signal<ProxySettings, NoError>,
    statuses: Signal<[ProxyServerSettings: ProxyServerStatus], NoError>,
    connectionStatus: Signal<ConnectionStatus, NoError>
) -> ViewController {
    let signal = combineLatest(queue: .mainQueue(), updatedPresentationData, proxySettings, statuses, connectionStatus)
    |> map { presentationData, proxySettings, statuses, connectionStatus -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ProxyConnectionStatusStrings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: proxyConnectionStatusEntries(strings: presentationData.strings, proxySettings: proxySettings, statuses: statuses, connectionStatus: connectionStatus), style: .blocks, animateChanges: true)
        return (controllerState, (listState, 0))
    }
    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: updatedPresentationData |> map { ItemListPresentationData($0) }, state: signal, tabBarItem: nil)
    return controller
}
