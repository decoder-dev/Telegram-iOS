import Foundation
import SwiftSignalKit
import MtProtoKit
import WebProxyTransport
import TelegramVLESS


public enum ProxyServerStatus: Equatable {
    case notChecked
    case checking
    case notAvailable
    case available(Double)
}

private let proxyStatusPingTimeout: Double = 7.0

private func pingProxyStatus(context: MTContext, datacenterId: Int, settings: MTSocksProxySettings) -> Signal<ProxyServerStatus, NoError> {
    return Signal { subscriber in
        let disposable = MTProxyConnectivity.pingProxy(with: context, datacenterId: datacenterId, settings: settings).start(next: { next in
            if let next = next as? MTProxyConnectivityStatus {
                if !next.reachable {
                    subscriber.putNext(.notAvailable)
                } else {
                    subscriber.putNext(.available(next.roundTripTime))
                }
                subscriber.putCompletion()
            }
        })
        return ActionDisposable {
            disposable?.dispose()
        }
    }
    |> timeout(proxyStatusPingTimeout, queue: Queue.concurrentDefaultQueue(), alternate: .single(.notAvailable))
}

private func socksSettingsForPing(server: ProxyServerSettings) -> MTSocksProxySettings? {
    switch server.connection {
        case let .socks5(username, password):
            return MTSocksProxySettings(ip: server.host, port: UInt16(clamping: server.port), username: username, password: password, secret: nil)
        case let .mtp(secret):
            return MTSocksProxySettings(ip: server.host, port: UInt16(clamping: server.port), username: nil, password: nil, secret: secret)
        case .web:
            return nil
        case .vless:
            // The embedded runtime exposes an authenticated loopback SOCKS5; resolve it
            // through the manager so the ping goes through the actual VLESS tunnel.
            guard let url = server.vlessProxyURL else {
                return nil
            }
            guard let endpoint = VlessManager.shared.loopbackEndpoint(for: url) else {
                return nil
            }
            return MTSocksProxySettings(ip: endpoint.host, port: UInt16(clamping: endpoint.port), username: endpoint.user, password: endpoint.password, secret: nil)
    }
}

private func webConfiguration(for server: ProxyServerSettings) -> LegacyWebProxyConfiguration? {
    guard case let .web(secret, path) = server.connection, path.isEmpty else {
        return nil
    }
    return LegacyWebProxyConfiguration(hostname: server.host, secret: secret)
}

private final class ProxyServerItemContext {
    private var disposable = MetaDisposable()
    private var stateDisposable = MetaDisposable()
    private var sidecarEventToken: WebProxyManager.SidecarEventToken?
    var value: ProxyServerStatus = .checking
    
    init(queue: Queue, context: MTContext, datacenterId: Int, server: ProxyServerSettings, updated: @escaping (ProxyServerStatus) -> Void) {
        if let url = server.vlessProxyURL {
            // Observing a saved profile must never replace the application's active tunnel.
            var previousEndpoint: VlessProxySink?
            let refresh: () -> Void = { [weak self] in
                guard let self else { return }
                guard let endpoint = VlessManager.shared.loopbackEndpoint(for: url) else {
                    previousEndpoint = nil
                    self.disposable.set(nil)
                    updated(.notChecked)
                    return
                }
                guard endpoint != previousEndpoint else { return }
                previousEndpoint = endpoint
                updated(.checking)
                let settings = MTSocksProxySettings(ip: endpoint.host, port: UInt16(clamping: endpoint.port), username: endpoint.user, password: endpoint.password, secret: nil)
                self.disposable.set((pingProxyStatus(context: context, datacenterId: datacenterId, settings: settings)
                |> deliverOn(queue)).start(next: updated))
            }
            self.stateDisposable.set((VlessManager.shared.stateEvents |> deliverOn(queue)).start(next: { _ in refresh() }))
            queue.async { refresh() }
            return
        }
        if let configuration = webConfiguration(for: server) {
            self.startWebProxyPing(queue: queue, context: context, datacenterId: datacenterId, server: server, configuration: configuration, updated: updated)
            return
        }
        if case .web = server.connection {
            // The path-aware carrier has no isolated ping API. Do not report a
            // saved profile as failed, and never start it just to observe status.
            queue.async { updated(.notChecked) }
            return
        }
        guard let settings = socksSettingsForPing(server: server) else {
            queue.async {
                updated(.notAvailable)
            }
            return
        }
        self.disposable.set((pingProxyStatus(context: context, datacenterId: datacenterId, settings: settings)
        |> runOn(queue)).start(next: { status in
            updated(status)
        }))
    }
    
    private func startWebProxyPing(queue: Queue, context: MTContext, datacenterId: Int, server: ProxyServerSettings, configuration: LegacyWebProxyConfiguration, updated: @escaping (ProxyServerStatus) -> Void) {
        guard case let .web(secret, path) = server.connection, path.isEmpty else {
            queue.async {
                updated(.notAvailable)
            }
            return
        }
        
        let runPing: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            guard let endpoint = WebProxyManager.shared.loopbackEndpoint(for: configuration) else {
                self.disposable.set(nil)
                queue.async {
                    updated(.notChecked)
                }
                return
            }
            let settings = MTSocksProxySettings(ip: endpoint.host, port: endpoint.port, username: nil, password: nil, secret: secret)
            self.disposable.set((pingProxyStatus(context: context, datacenterId: datacenterId, settings: settings)
            |> runOn(queue)).start(next: { status in
                updated(status)
            }))
        }
        
        self.sidecarEventToken = WebProxyManager.shared.addSidecarEventHandler { _ in
            queue.async { runPing() }
        }
        runPing()
    }
    
    deinit {
        self.disposable.dispose()
        self.stateDisposable.dispose()
        if let sidecarEventToken = self.sidecarEventToken {
            WebProxyManager.shared.removeSidecarEventHandler(sidecarEventToken)
        }
    }
}

/// Bound initial health probes, keep input priority, and reject callbacks from replaced profiles.
struct ProxyStatusProbeQueue<Key: Hashable> {
    private(set) var tokens: [Key: Int] = [:]
    private(set) var running = Set<Key>()
    private var pending: [Key] = []
    private var generation = 0
    let limit: Int

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    mutating func update(_ keys: [Key]) {
        let valid = Set(keys)
        self.tokens = self.tokens.filter { valid.contains($0.key) }
        self.running = self.running.intersection(valid)
        self.pending = self.pending.filter { valid.contains($0) }
        for key in keys where self.tokens[key] == nil {
            self.generation += 1
            self.tokens[key] = self.generation
            self.pending.append(key)
        }
    }

    mutating func takeNext() -> [(Key, Int)] {
        var result: [(Key, Int)] = []
        while self.running.count < self.limit, !self.pending.isEmpty {
            let key = self.pending.removeFirst()
            guard let token = self.tokens[key] else { continue }
            self.running.insert(key)
            result.append((key, token))
        }
        return result
    }

    mutating func complete(_ key: Key, token: Int) -> Bool {
        guard self.tokens[key] == token else { return false }
        return self.running.remove(key) != nil
    }
}

final class ProxyServersStatusesImpl {
    private let queue: Queue
    private let network: Network
    private var probes = ProxyStatusProbeQueue<ProxyServerSettings>(limit: 4)
    
    private var contexts: [ProxyServerSettings: ProxyServerItemContext] = [:]
    private var serversDisposable: Disposable?
    
    private var currentValues: [ProxyServerSettings: ProxyServerStatus] = [:] {
        didSet {
            self.values.set(.single(self.currentValues))
        }
    }
    let values = Promise<[ProxyServerSettings: ProxyServerStatus]>([:])
    
    init(queue: Queue, network: Network, servers: Signal<[ProxyServerSettings], NoError>) {
        self.queue = queue
        self.network = network
        
        self.serversDisposable = (servers
            |> deliverOn(self.queue)).start(next: { [weak self] servers in
                if let strongSelf = self {
                    let validKeys = Set<ProxyServerSettings>(servers)
                    var removeKeys: [ProxyServerSettings] = []
                    for (key, _) in strongSelf.contexts {
                        if !validKeys.contains(key) {
                            removeKeys.append(key)
                        }
                    }
                    for key in removeKeys {
                        let _ = strongSelf.contexts.removeValue(forKey: key)
                    }
                    strongSelf.probes.update(servers)
                    strongSelf.startNextProbes()
                    strongSelf.updateValues()
                }
            })
    }
    
    deinit {
        self.serversDisposable?.dispose()
    }

    private func startNextProbes() {
        assert(self.queue.isCurrent())
        for (key, token) in self.probes.takeNext() {
            let context = ProxyServerItemContext(queue: self.queue, context: self.network.context, datacenterId: self.network.datacenterId, server: key, updated: { [weak self] value in
                // Defer until insertion, even when a profile reports a synchronous result.
                self?.queue.justDispatch { [weak self] in
                    guard let self, self.probes.tokens[key] == token else { return }
                    self.contexts[key]?.value = value
                    if value != .checking, self.probes.complete(key, token: token) {
                        self.startNextProbes()
                    }
                    self.updateValues()
                }
            })
            self.contexts[key] = context
        }
    }
    
    private func updateValues() {
        assert(self.queue.isCurrent())
        
        var values: [ProxyServerSettings: ProxyServerStatus] = [:]
        for key in self.probes.tokens.keys {
            values[key] = self.contexts[key]?.value ?? .notChecked
        }
        self.currentValues = values
    }
}

public final class ProxyServersStatuses {
    private let impl: QueueLocalObject<ProxyServersStatusesImpl>
    
    public init(network: Network, servers: Signal<[ProxyServerSettings], NoError>) {
        let queue = Queue()
        self.impl = QueueLocalObject(queue: queue, generate: {
            return ProxyServersStatusesImpl(queue: queue, network: network, servers: servers)
        })
    }
    
    public func statuses() -> Signal<[ProxyServerSettings: ProxyServerStatus], NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.values.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return ActionDisposable {
                self.impl.with({ _ in })
                disposable.dispose()
            }
        }
    }
}
