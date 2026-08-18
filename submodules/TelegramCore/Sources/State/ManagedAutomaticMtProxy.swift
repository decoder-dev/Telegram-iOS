import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

/// Public MTProxy lists used by WhiteGram-style auto-fetch (refreshed by the publishers).
private let automaticMtProxyListURLs = [
    "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt",
    "https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_all.txt",
]
private let automaticMtProxyRefreshInterval: Double = 10.0 * 60.0
private let automaticMtProxySelectionDelay: Double = 1.0
private let automaticMtProxyConnectionFallbackDelay: Double = 12.0
private let automaticMtProxyProbeLimit = 40
private let automaticMtProxyStoredLimit = 40

private func automaticMtProxyHostIsIPAddress(_ host: String) -> Bool {
    let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    let ipv4Parts = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
    if ipv4Parts.count == 4 {
        var isIPv4 = true
        for part in ipv4Parts {
            guard let value = Int(part), value >= 0, value <= 255, String(value) == String(part) else {
                isIPv4 = false
                break
            }
        }
        if isIPv4 {
            return true
        }
    }
    if normalizedHost.contains(":") {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        return !normalizedHost.isEmpty && normalizedHost.rangeOfCharacter(from: allowed.inverted) == nil
    }
    return false
}

private func automaticMtProxyHostIsDomainName(_ host: String) -> Bool {
    let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    if normalizedHost.isEmpty || automaticMtProxyHostIsIPAddress(normalizedHost) {
        return false
    }
    let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
    if normalizedHost.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
        return false
    }
    let labels = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else {
        return false
    }
    for label in labels {
        if label.isEmpty || label.count > 63 || label.hasPrefix("-") || label.hasSuffix("-") {
            return false
        }
    }
    return true
}

private func fetchAutomaticMtProxyListText(urlString: String) -> Signal<String, NoError> {
    return Signal { subscriber in
        guard let url = URL(string: urlString) else {
            subscriber.putNext("")
            subscriber.putCompletion()
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                subscriber.putNext(text)
            } else {
                subscriber.putNext("")
            }
            subscriber.putCompletion()
        })
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

private func parseAutomaticMtProxyServers(_ text: String) -> [ProxyServerSettings] {
    var result: [ProxyServerSettings] = []
    var seen = Set<ProxyServerSettings>()
    let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>"))
    for rawToken in text.components(separatedBy: separators) {
        let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: ".,;()[]{}"))
        guard token.hasPrefix("https://t.me/proxy?") || token.hasPrefix("http://t.me/proxy?") || token.hasPrefix("tg://proxy?") else {
            continue
        }
        guard let components = URLComponents(string: token), let queryItems = components.queryItems else {
            continue
        }
        var host: String?
        var port: Int32?
        var secret: Data?
        for item in queryItems {
            switch item.name {
            case "server":
                host = item.value?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            case "port":
                if let value = item.value, let parsed = Int32(value), parsed > 0, parsed <= 65535 {
                    port = parsed
                }
            case "secret":
                if let value = item.value, let parsedSecret = MTProxySecret.parse(value) {
                    secret = parsedSecret.serialize()
                }
            default:
                break
            }
        }
        if let host, automaticMtProxyHostIsDomainName(host), let port, port > 0, port <= 65535, let secret {
            let server = ProxyServerSettings(host: host, port: port, connection: .mtp(secret: secret))
            if seen.insert(server).inserted {
                result.append(server)
            }
        }
    }
    return result
}

private func mergeAutomaticMtProxyServers(_ lists: [[ProxyServerSettings]]) -> [ProxyServerSettings] {
    var seen = Set<ProxyServerSettings>()
    var result: [ProxyServerSettings] = []
    var indices = Array(repeating: 0, count: lists.count)
    var progressed = true
    while progressed && result.count < automaticMtProxyStoredLimit {
        progressed = false
        for i in 0 ..< lists.count {
            var index = indices[i]
            while index < lists[i].count {
                let server = lists[i][index]
                index += 1
                if seen.insert(server).inserted {
                    result.append(server)
                    progressed = true
                    break
                }
            }
            indices[i] = index
            if result.count >= automaticMtProxyStoredLimit {
                break
            }
        }
    }
    return result
}

private func fetchAutomaticMtProxyServers() -> Signal<[ProxyServerSettings], NoError> {
    let fetches = automaticMtProxyListURLs.map { urlString in
        fetchAutomaticMtProxyListText(urlString: urlString)
        |> map(parseAutomaticMtProxyServers)
    }
    return combineLatest(fetches)
    |> map(mergeAutomaticMtProxyServers)
}

private func automaticMtProxySortedAvailable(_ candidates: [ProxyServerSettings], statuses: [ProxyServerSettings: ProxyServerStatus], excluding excluded: ProxyServerSettings? = nil) -> [ProxyServerSettings] {
    var available: [(ProxyServerSettings, Double)] = []
    for server in candidates {
        if let excluded, server == excluded {
            continue
        }
        if case let .available(rtt)? = statuses[server] {
            available.append((server, rtt))
        }
    }
    available.sort { $0.1 < $1.1 }
    return available.map { $0.0 }
}

private final class AutomaticMtProxyContext {
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let network: Network
    private let queue = Queue()
    
    private let fetchedServers = Promise<[ProxyServerSettings]>([])
    private let candidateServers = Promise<[ProxyServerSettings]>([])
    
    private var fetchDisposable: Disposable?
    private var settingsDisposable: Disposable?
    private var statusDisposable: Disposable?
    private var connectionStatusDisposable: Disposable?
    private var refreshTimer: SwiftSignalKit.Timer?
    private var selectionTimer: SwiftSignalKit.Timer?
    private var connectionFallbackTimer: SwiftSignalKit.Timer?
    
    private var currentSettings: ProxySettings = .defaultSettings
    private var currentStatuses: [ProxyServerSettings: ProxyServerStatus] = [:]
    private var excludedActiveServer: ProxyServerSettings?
    private var lastStoredAutomaticServers: [ProxyServerSettings] = []
    
    init(accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network) {
        self.accountManager = accountManager
        self.network = network
    }
    
    func start() {
        let settingsSignal = self.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> map { sharedData -> ProxySettings in
            return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings
        }
        
        self.settingsDisposable = (combineLatest(settingsSignal, self.fetchedServers.get())
        |> deliverOn(self.queue)).start(next: { [weak self] settings, fetchedServers in
            guard let self else {
                return
            }
            let wasEnabled = self.currentSettings.autoFetchPublicMtProxy
            self.currentSettings = settings
            let probe = Array(fetchedServers.prefix(automaticMtProxyProbeLimit))
            if settings.autoFetchPublicMtProxy {
                self.candidateServers.set(.single(probe.isEmpty ? settings.automaticServers : probe))
                if !wasEnabled {
                    self.refreshProxyList()
                }
            } else {
                self.candidateServers.set(.single([]))
                self.excludedActiveServer = nil
            }
        })
        
        let statuses = ProxyServersStatuses(network: self.network, servers: self.candidateServers.get())
        self.statusDisposable = (statuses.statuses()
        |> deliverOn(self.queue)).start(next: { [weak self] statuses in
            guard let self else {
                return
            }
            self.currentStatuses = statuses
            guard self.currentSettings.autoFetchPublicMtProxy else {
                return
            }
            if let active = self.currentSettings.activeServer, case .notAvailable? = statuses[active] {
                self.excludedActiveServer = active
                self.scheduleBestProxySelection()
            } else if self.currentSettings.activeServer == nil {
                self.scheduleBestProxySelection()
            }
        })
        
        self.connectionStatusDisposable = (self.network.connectionStatus
        |> deliverOn(self.queue)).start(next: { [weak self] status in
            self?.connectionStatusUpdated(status)
        })
        
        self.refreshTimer = SwiftSignalKit.Timer(timeout: automaticMtProxyRefreshInterval, repeat: true, completion: { [weak self] in
            self?.refreshProxyList()
        }, queue: self.queue)
        self.refreshTimer?.start()
    }
    
    func dispose() {
        self.fetchDisposable?.dispose()
        self.settingsDisposable?.dispose()
        self.statusDisposable?.dispose()
        self.connectionStatusDisposable?.dispose()
        self.refreshTimer?.invalidate()
        self.selectionTimer?.invalidate()
        self.connectionFallbackTimer?.invalidate()
    }
    
    private func refreshProxyList() {
        guard self.currentSettings.autoFetchPublicMtProxy else {
            return
        }
        self.fetchDisposable?.dispose()
        self.fetchDisposable = (fetchAutomaticMtProxyServers()
        |> deliverOn(self.queue)).start(next: { [weak self] servers in
            guard let self, self.currentSettings.autoFetchPublicMtProxy, !servers.isEmpty else {
                return
            }
            self.fetchedServers.set(.single(servers))
            self.storeFetchedServers(servers)
        })
    }
    
    private func storeFetchedServers(_ servers: [ProxyServerSettings]) {
        let fetched = Array(servers.prefix(automaticMtProxyStoredLimit))
        if fetched.isEmpty || fetched == self.lastStoredAutomaticServers {
            return
        }
        self.lastStoredAutomaticServers = fetched
        
        let _ = updateProxySettingsInteractively(accountManager: self.accountManager, { settings in
            var settings = settings
            guard settings.autoFetchPublicMtProxy else {
                return settings
            }
            let previousAutomatic = Set(settings.automaticServers)
            let manual = settings.servers.filter { !previousAutomatic.contains($0) }
            let manualSet = Set(manual)
            let newAutomatic = fetched.filter { !manualSet.contains($0) }
            settings.automaticServers = newAutomatic
            settings.servers = newAutomatic + manual
            if let active = settings.activeServer, previousAutomatic.contains(active), !Set(newAutomatic).contains(active) {
                settings.activeServer = nil
            }
            return settings
        }).start()
        
        self.scheduleBestProxySelection()
    }
    
    private func connectionStatusUpdated(_ status: ConnectionStatus) {
        guard self.currentSettings.autoFetchPublicMtProxy, self.currentSettings.enabled else {
            self.connectionFallbackTimer?.invalidate()
            self.connectionFallbackTimer = nil
            return
        }
        switch status {
        case .online:
            self.excludedActiveServer = nil
            self.connectionFallbackTimer?.invalidate()
            self.connectionFallbackTimer = nil
        case let .connecting(_, proxyHasConnectionIssues):
            if proxyHasConnectionIssues {
                self.excludedActiveServer = self.currentSettings.activeServer
            }
            if proxyHasConnectionIssues || self.currentSettings.activeServer == nil {
                self.scheduleConnectionFallback()
            }
        case .waitingForNetwork, .updating:
            self.scheduleBestProxySelection()
        }
    }
    
    private func scheduleConnectionFallback() {
        if self.connectionFallbackTimer != nil {
            return
        }
        let activeServer = self.currentSettings.activeServer
        self.connectionFallbackTimer = SwiftSignalKit.Timer(timeout: automaticMtProxyConnectionFallbackDelay, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.connectionFallbackTimer = nil
            guard self.currentSettings.autoFetchPublicMtProxy, self.currentSettings.enabled else {
                return
            }
            if let activeServer, self.currentSettings.activeServer == activeServer {
                self.excludedActiveServer = activeServer
            }
            self.scheduleBestProxySelection()
        }, queue: self.queue)
        self.connectionFallbackTimer?.start()
    }
    
    private func scheduleBestProxySelection() {
        self.selectionTimer?.invalidate()
        self.selectionTimer = SwiftSignalKit.Timer(timeout: automaticMtProxySelectionDelay, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.selectionTimer = nil
            self.activateBestProxyIfNeeded()
        }, queue: self.queue)
        self.selectionTimer?.start()
    }
    
    private func activateBestProxyIfNeeded() {
        guard self.currentSettings.autoFetchPublicMtProxy, self.currentSettings.enabled else {
            return
        }
        let pool = self.currentSettings.automaticServers.isEmpty ? self.currentSettings.servers : self.currentSettings.automaticServers
        guard let best = automaticMtProxySortedAvailable(pool, statuses: self.currentStatuses, excluding: self.excludedActiveServer).first else {
            return
        }
        if self.currentSettings.activeServer == best {
            return
        }
        let _ = updateProxySettingsInteractively(accountManager: self.accountManager, { settings in
            var settings = settings
            guard settings.autoFetchPublicMtProxy, settings.enabled else {
                return settings
            }
            if !settings.servers.contains(best) {
                settings.servers.insert(best, at: 0)
            }
            settings.activeServer = best
            return settings
        }).start()
    }
}

func managedAutomaticMtProxy(accountManager: AccountManager<TelegramAccountManagerTypes>, network: Network) -> Signal<Never, NoError> {
    return Signal { subscriber in
        let context = AutomaticMtProxyContext(accountManager: accountManager, network: network)
        context.start()
        return ActionDisposable {
            context.dispose()
        }
    }
}
