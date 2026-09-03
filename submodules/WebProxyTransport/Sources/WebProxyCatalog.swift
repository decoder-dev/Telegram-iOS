import Foundation

/// A single entry in the WEB-proxy public catalog.
public struct WebProxyCatalogEntry: Equatable, Decodable {
    public var title: String
    public var host: String
    /// Raw hex of the proxy secret (`dd…` or `ee…` prefix).
    public var secretHex: String

    public init(title: String, host: String, secretHex: String) {
        self.title = title
        self.host = host
        self.secretHex = secretHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.host = try container.decode(String.self, forKey: .host)
        // Accept both `secret` and `secretHex` in the JSON.
        let hex = (try? container.decode(String.self, forKey: .secretHex))
            ?? (try? container.decode(String.self, forKey: .secret))
            ?? ""
        self.secretHex = hex
    }

    private enum CodingKeys: String, CodingKey {
        case title, host, secretHex, secret
    }
}

/// Hardcoded bootstrap list + optional remote directory URLs.
/// Operator fills real entries before shipping; empty keeps the catalog UI hidden by default.
public enum WebProxyCatalogBootstrap {
    public static let entries: [WebProxyCatalogEntry] = [
        // WebProxyCatalogEntry(title: "Example", host: "mask.example.com", secretHex: "dd..."),
    ]

    public static let directoryURLs: [String] = [
        // "https://cdn.example.com/webproxy/catalog.json",
    ]
}

private struct CatalogDirectory: Decodable {
    struct Item: Decodable {
        let title: String
        let host: String
        // server-side can use either key
        let secretHex: String?
        let secret: String?
        var resolvedSecret: String { secretHex ?? secret ?? "" }
    }
    let proxies: [Item]
}

/// Loads WEB-proxy catalog entries (bootstrap first, then remote).
public enum WebProxyCatalog {
    /// Instant access: bootstrap entries only (no network).
    public static var bootstrapEntries: [WebProxyCatalogEntry] {
        return WebProxyCatalogBootstrap.entries
    }

    /// Merge bootstrap + fetched lists and return via callback on the main queue.
    /// Dedupes by lowercase host. Fetch is best-effort; if all URLs fail returns bootstrap only.
    public static func load(completion: @escaping ([WebProxyCatalogEntry]) -> Void) {
        let urls = WebProxyCatalogBootstrap.directoryURLs
        guard !urls.isEmpty else {
            DispatchQueue.main.async { completion(WebProxyCatalogBootstrap.entries) }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var all = WebProxyCatalogBootstrap.entries
            var seen = Set(all.map { $0.host.lowercased() })
            for urlString in urls {
                guard let url = URL(string: urlString) else { continue }
                let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                let sema = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: req) { data, response, _ in
                    defer { sema.signal() }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          let data = data,
                          let dir = try? JSONDecoder().decode(CatalogDirectory.self, from: data) else { return }
                    for item in dir.proxies {
                        guard !item.host.isEmpty, !item.resolvedSecret.isEmpty,
                              WebProxyHostname.isValid(item.host),
                              seen.insert(item.host.lowercased()).inserted else { continue }
                        all.append(WebProxyCatalogEntry(title: item.title.isEmpty ? item.host : item.title,
                                                        host: item.host,
                                                        secretHex: item.resolvedSecret))
                    }
                }.resume()
                sema.wait()
            }
            DispatchQueue.main.async { completion(all) }
        }
    }
}
