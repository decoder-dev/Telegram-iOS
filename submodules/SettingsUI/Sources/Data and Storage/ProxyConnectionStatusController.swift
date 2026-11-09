import Foundation
import UIKit
import Display
import SwiftSignalKit
import MtProtoKit
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
    static var datacentersHeader: String { ru ? "ДАТА-ЦЕНТРЫ TELEGRAM" : "TELEGRAM DATA CENTERS" }
    static var checkAgain: String { ru ? "Проверить снова" : "Check Again" }
    static var datacentersFooter: String { ru ? "Время ответа каждого дата-центра на запрос MTProto — тем же путём, что и сообщения: через прокси, если он включён." : "How long each data center takes to answer an MTProto request, sent the way your messages go: through the proxy if one is on." }
}

private final class ProxyConnectionStatusArguments {
    let checkDatacentersAgain: () -> Void

    init(checkDatacentersAgain: @escaping () -> Void) {
        self.checkDatacentersAgain = checkDatacentersAgain
    }
}

private enum ProxyConnectionStatusEntry: ItemListNodeEntry {
    case card(title: String, detail: String, connected: Bool)
    case header(String)
    case route(String, String)
    case state(String, String)
    case lastResponse(String, String)
    case footer(String)
    case datacentersHeader(String)
    case datacenter(id: Int, value: String)
    case checkDatacentersAgain(String)
    case datacentersFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .card:
            return 0
        case .header, .route, .state, .lastResponse, .footer:
            return 1
        case .datacentersHeader, .datacenter, .checkDatacentersAgain, .datacentersFooter:
            return 2
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
        case .datacentersHeader:
            return 10
        case let .datacenter(id, _):
            return Int32(10 + id)
        case .checkDatacentersAgain:
            return 20
        case .datacentersFooter:
            return 21
        }
    }

    static func <(lhs: ProxyConnectionStatusEntry, rhs: ProxyConnectionStatusEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ProxyConnectionStatusArguments
        switch self {
        case let .card(title, detail, _):
            // The state and the server, as a row with its value: no card, no icon.
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .route(title, value), let .state(title, value), let .lastResponse(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .footer(text), let .datacentersFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .datacentersHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .datacenter(id, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "DC\(id)", label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .checkDatacentersAgain(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.checkDatacentersAgain()
            })
        }
    }
}

/// MTProto's own check of a data center, the one the proxy list makes of a proxy: req_pq_multi to the data center's
/// address and the time until its res_pq comes back. It goes through the proxy the network uses now, or directly.
private func datacenterLatency(network: Network, datacenterId: Int) -> Signal<ProxyServerStatus, NoError> {
    return Signal { subscriber in
        let disposable = MTProxyConnectivity.pingProxy(with: network.context, datacenterId: datacenterId, settings: network.context.apiEnvironment.socksProxySettings).start(next: { next in
            if let next = next as? MTProxyConnectivityStatus {
                subscriber.putNext(next.reachable ? .available(next.roundTripTime) : .notAvailable)
                subscriber.putCompletion()
            }
        })
        return ActionDisposable {
            disposable?.dispose()
        }
    }
    |> timeout(7.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(.notAvailable))
}

private func datacenterLatencies(network: Network) -> Signal<[Int: ProxyServerStatus], NoError> {
    // The test environment has three data centers, production five.
    let ids = network.context.isTestingEnvironment ? [1, 2, 3] : [1, 2, 3, 4, 5]
    return combineLatest(ids.map { id -> Signal<(Int, ProxyServerStatus), NoError> in
        return (Signal<ProxyServerStatus, NoError>.single(.checking) |> then(datacenterLatency(network: network, datacenterId: id)))
        |> map { status in
            return (id, status)
        }
    })
    |> map { values -> [Int: ProxyServerStatus] in
        var result: [Int: ProxyServerStatus] = [:]
        for (id, status) in values {
            result[id] = status
        }
        return result
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

private func proxyConnectionStatusEntries(strings: PresentationStrings, proxySettings: ProxySettings, statuses: [ProxyServerSettings: ProxyServerStatus], connectionStatus: ConnectionStatus, datacenters: [Int: ProxyServerStatus]) -> [ProxyConnectionStatusEntry] {
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

    entries.append(.datacentersHeader(ProxyConnectionStatusStrings.datacentersHeader))
    for id in datacenters.keys.sorted() {
        let value: String
        switch datacenters[id] {
        case let .available(rtt):
            value = ProxyConnectionStatusStrings.milliseconds(Int(rtt * 1000.0))
        case .checking:
            value = strings.SocksProxySetup_ProxyStatusChecking
        case .notAvailable:
            value = strings.SocksProxySetup_ProxyStatusUnavailable
        case .notChecked, .none:
            value = strings.SocksProxySetup_ProxyStatusNotTested
        }
        entries.append(.datacenter(id: id, value: value))
    }
    entries.append(.checkDatacentersAgain(ProxyConnectionStatusStrings.checkAgain))
    entries.append(.datacentersFooter(ProxyConnectionStatusStrings.datacentersFooter))
    return entries
}

/// Opened from the connection card at the top of the proxy list; shares that list's signals, so its pings keep running.
func proxyConnectionStatusController(
    presentationData: PresentationData,
    updatedPresentationData: Signal<PresentationData, NoError>,
    proxySettings: Signal<ProxySettings, NoError>,
    statuses: Signal<[ProxyServerSettings: ProxyServerStatus], NoError>,
    connectionStatus: Signal<ConnectionStatus, NoError>,
    network: Network
) -> ViewController {
    // Each Check Again starts a new round; one runs when the screen opens. Nothing is checked through a WEB proxy.
    let datacentersRound = ValuePromise<Int>(0, ignoreRepeated: false)
    let datacenters = datacentersRound.get()
    |> mapToSignal { _ -> Signal<[Int: ProxyServerStatus], NoError> in
        return proxySettings
        |> take(1)
        |> mapToSignal { proxySettings -> Signal<[Int: ProxyServerStatus], NoError> in
            // MTProto can't check through a WEB proxy, as the proxy list says of the proxy itself.
            if case .web = proxySettings.effectiveActiveServer?.connection {
                return .single([1: .notChecked, 2: .notChecked, 3: .notChecked, 4: .notChecked, 5: .notChecked])
            }
            return datacenterLatencies(network: network)
        }
    }
    let arguments = ProxyConnectionStatusArguments(checkDatacentersAgain: {
        datacentersRound.set(0)
    })

    let signal = combineLatest(queue: .mainQueue(), updatedPresentationData, proxySettings, statuses, connectionStatus, datacenters)
    |> map { presentationData, proxySettings, statuses, connectionStatus, datacenters -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ProxyConnectionStatusStrings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: proxyConnectionStatusEntries(strings: presentationData.strings, proxySettings: proxySettings, statuses: statuses, connectionStatus: connectionStatus, datacenters: datacenters), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: updatedPresentationData |> map { ItemListPresentationData($0) }, state: signal, tabBarItem: nil)
    return controller
}
