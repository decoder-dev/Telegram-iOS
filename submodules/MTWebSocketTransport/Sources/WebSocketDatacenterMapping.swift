import Foundation

/// DC-number -> `kwsN.web.telegram.org` hostname/path mapping, reproducing the behavior observed in
/// `Flowseal/tg-ws-proxy` (commit `b2a8074c59c52cabde7fe295280b614cc6c01fce`, `proxy/config.py` /
/// `proxy/utils.py`). See `docs/websocket-transport.md` for the full derivation.
public enum WebSocketDatacenter {
    public static let productionPath = "/apiws"
    public static let testPath = "/apiws_test"

    /// Ordered candidate hostnames to try for a given DC. Media connections prefer the `-1` host first;
    /// non-media connections prefer the base host first (matches tg-ws-proxy's `ws_domains`).
    /// DC 203 (an extra Telegram IP outside the mainline 1-5 set) folds to DC 2's hostnames, as it does
    /// for the WS endpoint in tg-ws-proxy.
    public static func hostnames(datacenterId: Int, isMedia: Bool) -> [String] {
        var dc = abs(datacenterId)
        if dc == 203 {
            dc = 2
        }
        let base = "kws\(dc).web.telegram.org"
        let alternate = "kws\(dc)-1.web.telegram.org"
        return isMedia ? [alternate, base] : [base, alternate]
    }

    public static func path(isTestingEnvironment: Bool) -> String {
        return isTestingEnvironment ? WebSocketDatacenter.testPath : WebSocketDatacenter.productionPath
    }

    public static func foldedDatacenterId(_ datacenterId: Int) -> Int {
        var dc = abs(datacenterId)
        if dc == 203 {
            dc = 2
        }
        return dc
    }
}

/// Alternate front (CF Worker / custom origin) that terminates TLS on its own hostname and proxies
/// WebSocket bytes to `kws{N}.web.telegram.org`. SNI on the phone is the front host — not Telegram.
public struct WebSocketFrontTemplate: Equatable, Codable {
    /// Connect host. May contain `"{dc}"`. Example: `"front.example.com"` or `"kws{dc}.front.example.com"`.
    public var host: String
    public var port: UInt16
    /// Path. May contain `"{dc}"`. Example: `"/dc/{dc}/apiws"`. Trailing `/apiws` becomes `/apiws_test` in test env.
    public var pathTemplate: String
    public var httpHostTemplate: String?
    public var tlsServerNameTemplate: String?

    public init(host: String, port: UInt16 = 443, pathTemplate: String, httpHostTemplate: String? = nil, tlsServerNameTemplate: String? = nil) {
        self.host = host
        self.port = port
        self.pathTemplate = pathTemplate
        self.httpHostTemplate = httpHostTemplate
        self.tlsServerNameTemplate = tlsServerNameTemplate
    }
}

public enum WebSocketEndpointKind: Equatable {
    case telegramGateway
    case front
}

public struct WebSocketEndpointCandidate: Equatable {
    public let host: String
    public let port: UInt16
    public let path: String
    public let httpHost: String
    public let tlsServerName: String
    public let kind: WebSocketEndpointKind

    public init(host: String, port: UInt16 = 443, path: String, httpHost: String? = nil, tlsServerName: String? = nil, kind: WebSocketEndpointKind = .telegramGateway) {
        self.host = host
        self.port = port
        self.path = path
        self.httpHost = httpHost ?? host
        self.tlsServerName = tlsServerName ?? host
        self.kind = kind
    }
}

public struct WebSocketEndpointPlanConfig: Equatable {
    public enum Order: Equatable {
        case frontsFirst
        case telegramFirst
    }

    public var fronts: [WebSocketFrontTemplate]
    public var order: Order

    public init(fronts: [WebSocketFrontTemplate] = [], order: Order = .frontsFirst) {
        self.fronts = fronts
        self.order = order
    }

    public static let telegramOnly = WebSocketEndpointPlanConfig(fronts: [], order: .telegramFirst)
}

/// Hardcoded bootstrap fronts + directory URLs. Operator fills real Worker hostnames before shipping;
/// empty templates keep the planner on Telegram gateways only.
public enum WebSocketFrontBootstrap {
    public static let templates: [WebSocketFrontTemplate] = [
        // WebSocketFrontTemplate(host: "front.example.com", pathTemplate: "/dc/{dc}/apiws"),
    ]

    public static let directoryURLs: [String] = [
        // "https://front.example.com/fronts.json",
    ]
}

/// Combines `WebSocketDatacenter`'s hostname ordering and path selection into the ordered candidate
/// list a connection attempt should walk through. Optional fronts (CF Worker) are tried first by default.
public enum WebSocketEndpointPlanner {
    public static func candidates(datacenterId: Int, isMedia: Bool, isTestingEnvironment: Bool, config: WebSocketEndpointPlanConfig = .telegramOnly) -> [WebSocketEndpointCandidate] {
        let telegram = telegramCandidates(datacenterId: datacenterId, isMedia: isMedia, isTestingEnvironment: isTestingEnvironment)
        let fronts = frontCandidates(datacenterId: datacenterId, isTestingEnvironment: isTestingEnvironment, templates: config.fronts)
        let combined: [WebSocketEndpointCandidate]
        switch config.order {
        case .frontsFirst:
            combined = fronts + telegram
        case .telegramFirst:
            combined = telegram + fronts
        }
        return dedupe(combined, limit: 8)
    }

    private static func telegramCandidates(datacenterId: Int, isMedia: Bool, isTestingEnvironment: Bool) -> [WebSocketEndpointCandidate] {
        let path = WebSocketDatacenter.path(isTestingEnvironment: isTestingEnvironment)
        return WebSocketDatacenter.hostnames(datacenterId: datacenterId, isMedia: isMedia).map {
            WebSocketEndpointCandidate(host: $0, path: path, kind: .telegramGateway)
        }
    }

    private static func frontCandidates(datacenterId: Int, isTestingEnvironment: Bool, templates: [WebSocketFrontTemplate]) -> [WebSocketEndpointCandidate] {
        let dc = WebSocketDatacenter.foldedDatacenterId(datacenterId)
        var result: [WebSocketEndpointCandidate] = []
        for template in templates {
            let host = expand(template.host, dc: dc)
            guard !host.isEmpty else {
                continue
            }
            var path = expand(template.pathTemplate, dc: dc)
            if path.isEmpty {
                path = WebSocketDatacenter.path(isTestingEnvironment: isTestingEnvironment)
            } else if isTestingEnvironment {
                path = path.replacingOccurrences(of: "/apiws_test", with: "/apiws")
                if path.hasSuffix("/apiws") {
                    path = String(path.dropLast("/apiws".count)) + WebSocketDatacenter.testPath
                }
            }
            let httpHost = expand(template.httpHostTemplate ?? template.host, dc: dc)
            let tlsName = expand(template.tlsServerNameTemplate ?? template.host, dc: dc)
            result.append(WebSocketEndpointCandidate(
                host: host,
                port: template.port == 0 ? 443 : template.port,
                path: path,
                httpHost: httpHost.isEmpty ? host : httpHost,
                tlsServerName: tlsName.isEmpty ? host : tlsName,
                kind: .front
            ))
        }
        return result
    }

    private static func expand(_ template: String, dc: Int) -> String {
        return template.replacingOccurrences(of: "{dc}", with: "\(dc)")
    }

    private static func dedupe(_ candidates: [WebSocketEndpointCandidate], limit: Int) -> [WebSocketEndpointCandidate] {
        var seen = Set<String>()
        var out: [WebSocketEndpointCandidate] = []
        for candidate in candidates {
            let key = "\(candidate.host)|\(candidate.port)|\(candidate.path)"
            if seen.insert(key).inserted {
                out.append(candidate)
                if out.count >= limit {
                    break
                }
            }
        }
        return out
    }
}
