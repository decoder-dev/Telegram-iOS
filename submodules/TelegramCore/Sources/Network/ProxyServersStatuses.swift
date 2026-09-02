import Foundation
import SwiftSignalKit
import MtProtoKit
import WebProxyTransport


public enum ProxyServerStatus: Equatable {
    case checking
    case notAvailable
    case available(Double)
}

private let proxyStatusPingTimeout: Double = 15.0

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
    }
}

private func webConfiguration(for server: ProxyServerSettings) -> WebProxyConfiguration? {
    guard case let .web(secret) = server.connection else {
        return nil
    }
    return WebProxyConfiguration(hostname: server.host, secret: secret)
}

private final class ProxyServerItemContext {
    private var disposable = MetaDisposable()
    private var sidecarEventToken: WebProxyManager.SidecarEventToken?
    var value: ProxyServerStatus = .checking
    
    init(queue: Queue, context: MTContext, datacenterId: Int, server: ProxyServerSettings, updated: @escaping (ProxyServerStatus) -> Void) {
        if let configuration = webConfiguration(for: server) {
            self.startWebProxyPing(queue: queue, context: context, datacenterId: datacenterId, server: server, configuration: configuration, updated: updated)
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
    
    private func startWebProxyPing(queue: Queue, context: MTContext, datacenterId: Int, server: ProxyServerSettings, configuration: WebProxyConfiguration, updated: @escaping (ProxyServerStatus) -> Void) {
        guard case let .web(secret) = server.connection else {
            queue.async {
                updated(.notAvailable)
            }
            return
        }
        
        let runPing: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            guard WebProxyManager.shared.isReady(for: configuration),
                  let endpoint = WebProxyManager.shared.activeLoopbackEndpoint else {
                queue.async {
                    updated(.checking)
                }
                return
            }
            let settings = MTSocksProxySettings(ip: endpoint.host, port: endpoint.port, username: nil, password: nil, secret: secret)
            self.disposable.set((pingProxyStatus(context: context, datacenterId: datacenterId, settings: settings)
            |> runOn(queue)).start(next: { status in
                updated(status)
            }))
        }
        
        WebProxyManager.shared.configure(activeWebProxy: configuration)
        self.sidecarEventToken = WebProxyManager.shared.addSidecarEventHandler { _ in
            runPing()
        }
        runPing()
    }
    
    deinit {
        self.disposable.dispose()
        if let sidecarEventToken = self.sidecarEventToken {
            WebProxyManager.shared.removeSidecarEventHandler(sidecarEventToken)
        }
    }
}

final class ProxyServersStatusesImpl {
    private let queue: Queue
    
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
        
        self.serversDisposable = (servers
            |> deliverOn(self.queue)).start(next: { [weak self] servers in
                if let strongSelf = self {
                    let validKeys = Set<ProxyServerSettings>(servers)
                    for key in validKeys {
                        if strongSelf.contexts[key] == nil {
                            let context = ProxyServerItemContext(queue: strongSelf.queue, context: network.context, datacenterId: network.datacenterId, server: key, updated: { value in
                                queue.async {
                                    if let strongSelf = self {
                                        strongSelf.contexts[key]?.value = value
                                        strongSelf.updateValues()
                                    }
                                }
                            })
                            strongSelf.contexts[key] = context
                        }
                    }
                    var removeKeys: [ProxyServerSettings] = []
                    for (key, _) in strongSelf.contexts {
                        if !validKeys.contains(key) {
                            removeKeys.append(key)
                        }
                    }
                    for key in removeKeys {
                        let _ = strongSelf.contexts.removeValue(forKey: key)
                    }
                    if !removeKeys.isEmpty {
                        strongSelf.updateValues()
                    }
                }
            })
    }
    
    deinit {
        self.serversDisposable?.dispose()
    }
    
    private func updateValues() {
        assert(self.queue.isCurrent())
        
        var values: [ProxyServerSettings: ProxyServerStatus] = [:]
        for (key, context) in self.contexts {
            values[key] = context.value
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
