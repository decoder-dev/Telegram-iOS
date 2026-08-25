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
}

public struct WebSocketEndpointCandidate: Equatable {
    public let host: String
    public let port: UInt16
    public let path: String

    public init(host: String, port: UInt16 = 443, path: String) {
        self.host = host
        self.port = port
        self.path = path
    }
}

/// Combines `WebSocketDatacenter`'s hostname ordering and path selection into the ordered candidate
/// list a connection attempt should walk through.
public enum WebSocketEndpointPlanner {
    public static func candidates(datacenterId: Int, isMedia: Bool, isTestingEnvironment: Bool) -> [WebSocketEndpointCandidate] {
        let path = WebSocketDatacenter.path(isTestingEnvironment: isTestingEnvironment)
        return WebSocketDatacenter.hostnames(datacenterId: datacenterId, isMedia: isMedia).map {
            WebSocketEndpointCandidate(host: $0, path: path)
        }
    }
}
