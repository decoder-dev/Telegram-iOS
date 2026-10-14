import Foundation

/// What a TikTok post contains: one video (file + duration in seconds) or a photo carousel.
enum BananaTikTokItem: Equatable {
    case video(BananaRemoteFile, Double)
    case photos([BananaRemoteFile])
}

/// Reads a TikTok post straight from tiktok.com, without third-party services. Mirrors `tiktok_item_id`,
/// `tiktok_page_url` and `tiktok_parse_page` in the Python reference.
enum BananaTikTokExtractor {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private static let rehydrationMarker = "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\""

    static func itemId(fromPathSegments segments: [String]) -> String? {
        if segments.count >= 3 && segments[0].hasPrefix("@") && (segments[1] == "video" || segments[1] == "photo") && bananaIsTikTokItemId(segments[2]) {
            return segments[2]
        }
        if segments.count == 2 && segments[0] == "v" && segments[1].hasSuffix(".html") {
            let candidate = String(segments[1].dropLast(5))
            if bananaIsTikTokItemId(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Item id of a post link or of the page a short link redirected to; nil for the home page (expired link).
    static func itemId(from url: URL) -> String? {
        if let itemId = BananaTikTokExtractor.itemId(fromPathSegments: bananaPathSegments(url.path)) {
            return itemId
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let shared = components?.queryItems?.first(where: { $0.name == "share_item_id" })?.value, bananaIsTikTokItemId(shared) {
            return shared
        }
        return nil
    }

    /// One page serves videos and photo posts; "/photo/<id>" has no data and the author name is not needed.
    static func pageURL(itemId: String) -> URL? {
        return URL(string: "https://www.tiktok.com/@/video/\(itemId)")
    }

    static func pageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(BananaTikTokExtractor.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// CDN requests need the page's cookies (same BananaMediaFetcher) and a tiktok.com referer, otherwise 403.
    static func mediaRequest(_ url: URL) -> URLRequest {
        var request = BananaTikTokExtractor.pageRequest(url)
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        return request
    }

    static func parsePage(_ html: String) -> Result<BananaTikTokItem, BananaLinkDownloadError> {
        guard let marker = html.range(of: BananaTikTokExtractor.rehydrationMarker),
              let openEnd = html[marker.upperBound...].firstIndex(of: ">") else {
            return .failure(.tiktokNoData)
        }
        let jsonStart = html.index(after: openEnd)
        guard let close = html.range(of: "</script>", range: jsonStart ..< html.endIndex),
              let data = String(html[jsonStart ..< close.lowerBound]).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let scope = root["__DEFAULT_SCOPE__"] as? [String: Any],
              let detail = scope["webapp.video-detail"] as? [String: Any] else {
            return .failure(.tiktokNoData)
        }
        let status = bananaIntValue(detail["statusCode"]) ?? 0
        if status == 10204 {
            return .failure(.tiktokNotFound)
        }
        if status == 10222 {
            return .failure(.tiktokPrivate)
        }
        if status != 0 {
            return .failure(.tiktokStatus(Int(status)))
        }
        guard let itemInfo = detail["itemInfo"] as? [String: Any], let item = itemInfo["itemStruct"] as? [String: Any] else {
            return .failure(.tiktokNoData)
        }
        if let imagePost = item["imagePost"] as? [String: Any] {
            var files: [BananaRemoteFile] = []
            for entry in (imagePost["images"] as? [Any]) ?? [] {
                guard let image = entry as? [String: Any],
                      let imageURL = image["imageURL"] as? [String: Any],
                      let url = BananaMediaURLPolicy.firstAllowedURL(in: imageURL["urlList"] as? [Any]) else {
                    return .failure(.tiktokNoData)
                }
                files.append(BananaRemoteFile(url: url, expectedSize: nil, width: Int(bananaIntValue(image["imageWidth"]) ?? 0), height: Int(bananaIntValue(image["imageHeight"]) ?? 0)))
            }
            if files.isEmpty {
                return .failure(.tiktokNoData)
            }
            return .success(.photos(files))
        }
        let video = (item["video"] as? [String: Any]) ?? [:]
        let duration = Double(bananaIntValue(video["duration"]) ?? 0)
        var best: (bitrate: Int64, file: BananaRemoteFile)?
        for entry in (video["bitrateInfo"] as? [Any]) ?? [] {
            guard let variant = entry as? [String: Any],
                  let codec = variant["CodecType"] as? String, codec.lowercased().hasPrefix("h264"),
                  let play = variant["PlayAddr"] as? [String: Any],
                  let url = BananaMediaURLPolicy.firstAllowedURL(in: play["UrlList"] as? [Any]) else {
                continue
            }
            let bitrate = bananaIntValue(variant["Bitrate"]) ?? 0
            if let current = best, current.bitrate >= bitrate {
                continue
            }
            best = (bitrate, BananaRemoteFile(url: url, expectedSize: bananaIntValue(play["DataSize"]), width: Int(bananaIntValue(play["Width"]) ?? 0), height: Int(bananaIntValue(play["Height"]) ?? 0)))
        }
        if let best {
            return .success(.video(best.file, duration))
        }
        if let url = BananaMediaURLPolicy.allowedURL(video["playAddr"] as? String) {
            return .success(.video(BananaRemoteFile(url: url, expectedSize: nil, width: Int(bananaIntValue(video["width"]) ?? 0), height: Int(bananaIntValue(video["height"]) ?? 0)), duration))
        }
        return .failure(.tiktokNoData)
    }

    /// Short links (vm./vt./t/) are followed first: they redirect to "/@/video/<id>" or to the home page when expired.
    static func resolve(_ url: URL, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaTikTokItem, BananaLinkDownloadError>) -> Void) {
        if let itemId = BananaTikTokExtractor.itemId(from: url) {
            BananaTikTokExtractor.fetchItem(itemId: itemId, fetcher: fetcher, completion: completion)
            return
        }
        fetcher.fetchData(BananaTikTokExtractor.pageRequest(url), completion: { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(response):
                guard let finalURL = response.url, let itemId = BananaTikTokExtractor.itemId(from: finalURL) else {
                    completion(.failure(.tiktokLinkExpired))
                    return
                }
                BananaTikTokExtractor.fetchItem(itemId: itemId, fetcher: fetcher, completion: completion)
            }
        })
    }

    private static func fetchItem(itemId: String, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaTikTokItem, BananaLinkDownloadError>) -> Void) {
        guard let url = BananaTikTokExtractor.pageURL(itemId: itemId) else {
            completion(.failure(.tiktokNoData))
            return
        }
        fetcher.fetchData(BananaTikTokExtractor.pageRequest(url), completion: { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(response):
                completion(BananaTikTokExtractor.parsePage(String(decoding: response.data, as: UTF8.self)))
            }
        })
    }
}
