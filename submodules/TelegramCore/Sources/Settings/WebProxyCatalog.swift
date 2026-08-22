import Foundation
import SwiftSignalKit
import MtProtoKit

public struct WebProxyCatalogEntry: Equatable, Hashable {
    public let host: String
    public let secret: Data
    
    public init(host: String, secret: Data) {
        self.host = host
        self.secret = secret
    }
    
    public var settings: ProxyServerSettings {
        return ProxyServerSettings(host: self.host, port: 443, connection: .web(secret: self.secret))
    }
}

/// Public WEB-proxy lists (one `tg://webproxy` / `https://t.me/webproxy` link per token).
/// Operators can publish catalogs in the same shape as MTProxy lists.
private let webProxyCatalogURLs = [
    "https://raw.githubusercontent.com/decoder-dev/Telegram-iOS/master/resources/webproxy-catalog.txt",
]

public func parseWebProxyCatalogText(_ text: String) -> [WebProxyCatalogEntry] {
    var result: [WebProxyCatalogEntry] = []
    var seen = Set<WebProxyCatalogEntry>()
    let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>"))
    for rawToken in text.components(separatedBy: separators) {
        let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: ".,;()[]{}"))
        if token.isEmpty || token.hasPrefix("#") {
            continue
        }
        guard token.hasPrefix("https://t.me/webproxy?") || token.hasPrefix("http://t.me/webproxy?") || token.hasPrefix("tg://webproxy?") else {
            continue
        }
        guard let components = URLComponents(string: token), let queryItems = components.queryItems else {
            continue
        }
        var host: String?
        var secret: Data?
        for item in queryItems {
            switch item.name {
            case "server", "host":
                host = item.value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            case "secret":
                if let value = item.value, let parsedSecret = MTProxySecret.parse(value) {
                    secret = parsedSecret.serialize()
                }
            default:
                break
            }
        }
        if let host, !host.isEmpty, let secret, !secret.isEmpty {
            let entry = WebProxyCatalogEntry(host: host, secret: secret)
            if seen.insert(entry).inserted {
                result.append(entry)
            }
        }
    }
    return result
}

private func fetchWebProxyCatalogText(urlString: String) -> Signal<String, NoError> {
    return Signal { subscriber in
        guard let url = URL(string: urlString) else {
            subscriber.putNext("")
            subscriber.putCompletion()
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8.0
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

public func fetchWebProxyCatalog() -> Signal<[WebProxyCatalogEntry], NoError> {
    var signals: [Signal<[WebProxyCatalogEntry], NoError>] = []
    for url in webProxyCatalogURLs {
        signals.append(fetchWebProxyCatalogText(urlString: url)
        |> map(parseWebProxyCatalogText))
    }
    if signals.isEmpty {
        return .single([])
    }
    return combineLatest(signals)
    |> map { lists -> [WebProxyCatalogEntry] in
        var result: [WebProxyCatalogEntry] = []
        var seen = Set<WebProxyCatalogEntry>()
        for list in lists {
            for entry in list {
                if seen.insert(entry).inserted {
                    result.append(entry)
                }
            }
        }
        return result
    }
}
