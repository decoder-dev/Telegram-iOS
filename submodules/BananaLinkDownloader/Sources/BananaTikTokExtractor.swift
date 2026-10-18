import CryptoKit
import Foundation

/// What a TikTok post contains: one video (file + duration in seconds) or a photo carousel.
enum BananaTikTokItem: Equatable {
    case video(BananaRemoteFile, Double)
    case photos([BananaRemoteFile])
}

/// Tries TikTok first, then resolves the post through TikWM if TikTok blocks access.
enum BananaTikTokExtractor {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    private static let rehydrationMarker = "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\""
    /// TikTok's Akamai ebananae answers some requests with HTTP 200 and a "Site Maintenance" page carrying this line.
    private static let deniedMarker = "Please contact your administrator with the error code"

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

    /// Item id of a post link or of the page a short link redirected to; nil for the home page. A login wall keeps the
    /// post's link in `redirect_url`.
    static func itemId(from url: URL) -> String? {
        if let itemId = BananaTikTokExtractor.itemId(fromPathSegments: bananaPathSegments(url.path)) {
            return itemId
        }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let shared = queryItems.first(where: { $0.name == "share_item_id" })?.value, bananaIsTikTokItemId(shared) {
            return shared
        }
        if url.path == "/login", let target = queryItems.first(where: { $0.name == "redirect_url" })?.value.flatMap({ URL(string: $0) }) {
            return BananaTikTokExtractor.itemId(fromPathSegments: bananaPathSegments(target.path))
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

    /// A short link the way yt-dlp follows it: HEAD as Facebook's link preview bot, which TikTok redirects to the post.
    static func previewRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("facebookexternalhit/1.1", forHTTPHeaderField: "User-Agent")
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
            return .failure(html.contains(BananaTikTokExtractor.deniedMarker) ? .tiktokPageDenied : .tiktokNoData(BananaTikTokExtractor.pageTitle(html)))
        }
        let jsonStart = html.index(after: openEnd)
        guard let close = html.range(of: "</script>", range: jsonStart ..< html.endIndex),
              let data = String(html[jsonStart ..< close.lowerBound]).data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let scope = root["__DEFAULT_SCOPE__"] as? [String: Any],
              let detail = scope["webapp.video-detail"] as? [String: Any] else {
            return .failure(.tiktokNoData(BananaTikTokExtractor.pageTitle(html)))
        }
        let status = bananaIntValue(detail["statusCode"]) ?? 0
        if status == 10204 {
            return .failure(.tiktokNotFound)
        }
        // 10216: private post, 10222: private account (yt-dlp).
        if status == 10216 || status == 10222 {
            return .failure(.tiktokPrivate)
        }
        if status != 0 {
            return .failure(.tiktokStatus(Int(status)))
        }
        guard let itemInfo = detail["itemInfo"] as? [String: Any], let item = itemInfo["itemStruct"] as? [String: Any] else {
            return .failure(.tiktokNoData(BananaTikTokExtractor.pageTitle(html)))
        }
        if let imagePost = item["imagePost"] as? [String: Any] {
            var files: [BananaRemoteFile] = []
            for entry in (imagePost["images"] as? [Any]) ?? [] {
                guard let image = entry as? [String: Any],
                      let url = BananaTikTokExtractor.fileLinks((image["imageURL"] as? [String: Any])?["urlList"]).first else {
                    return .failure(.tiktokNoFile)
                }
                files.append(BananaRemoteFile(url: url, expectedSize: nil, width: Int(bananaIntValue(image["imageWidth"]) ?? 0), height: Int(bananaIntValue(image["imageHeight"]) ?? 0)))
            }
            if files.isEmpty {
                return .failure(.tiktokNoFile)
            }
            return .success(.photos(files))
        }
        let video = (item["video"] as? [String: Any]) ?? [:]
        let duration = Double(bananaIntValue(video["duration"]) ?? 0)
        var best: (bitrate: Int64, links: [URL], play: [String: Any])?
        for entry in (video["bitrateInfo"] as? [Any]) ?? [] {
            guard let variant = entry as? [String: Any],
                  let codec = variant["CodecType"] as? String, codec.lowercased().hasPrefix("h264"),
                  let play = variant["PlayAddr"] as? [String: Any] else {
                continue
            }
            let links = BananaTikTokExtractor.fileLinks(play["UrlList"])
            let bitrate = bananaIntValue(variant["Bitrate"]) ?? 0
            if links.isEmpty || (best.map { $0.bitrate >= bitrate } ?? false) {
                continue
            }
            best = (bitrate, links, play)
        }
        // Every CDN copy of the best variant and of the default stream, in case a CDN refuses this network. Links on
        // www.tiktok.com itself (/aweme/v1/play/) answer 403 outside a browser session and yt-dlp drops them, but some
        // pages carry nothing else, so they go after the CDN ones; the watermarked download is the last resort.
        let streams = (best?.links ?? []) + BananaTikTokExtractor.fileLinks(video["playAddr"])
        let downloads = BananaTikTokExtractor.fileLinks(video["downloadAddr"]) + BananaTikTokExtractor.fileLinks((video["download"] as? [String: Any])?["url"])
        var links: [URL] = []
        for link in BananaTikTokExtractor.cdnFirst(streams) + BananaTikTokExtractor.cdnFirst(downloads) where !links.contains(link) {
            links.append(link)
        }
        guard let first = links.first else {
            // Videos marked "may not be comfortable for some audiences" come without files to anyone not logged in.
            return .failure(item["isContentClassified"] as? Bool == true ? .tiktokAgeRestricted : .tiktokNoFile)
        }
        let play = (best?.links.contains(first) ?? false) ? best?.play : nil
        let width = bananaIntValue(play?["Width"]) ?? bananaIntValue(video["width"]) ?? 0
        let height = bananaIntValue(play?["Height"]) ?? bananaIntValue(video["height"]) ?? 0
        return .success(.video(BananaRemoteFile(url: first, expectedSize: play.flatMap { bananaIntValue($0["DataSize"]) }, width: Int(width), height: Int(height), alternateURLs: Array(links.dropFirst())), duration))
    }

    /// The https links in a page value: one link, a list of links, or a list of `{"src": link}` (playAddr comes in
    /// each form), in TikTok's order.
    static func fileLinks(_ value: Any?) -> [URL] {
        let entries: [Any]
        if let list = value as? [Any] {
            entries = list
        } else if let value {
            entries = [value]
        } else {
            entries = []
        }
        var links: [URL] = []
        for entry in entries {
            guard var string = (entry as? String) ?? ((entry as? [String: Any])?["src"] as? String) else {
                continue
            }
            if string.hasPrefix("//") {
                string = "https:" + string
            }
            guard let url = URL(string: string), BananaMediaURLPolicy.isAllowed(url), !links.contains(url) else {
                continue
            }
            links.append(url)
        }
        return links
    }

    /// Links on www.tiktok.com after the CDN ones, each group in its own order.
    private static func cdnFirst(_ links: [URL]) -> [URL] {
        let isPage: (URL) -> Bool = { $0.host?.lowercased() == "www.tiktok.com" }
        return links.filter { !isPage($0) } + links.filter(isPage)
    }

    /// The page's <title>, so the toast tells an unknown page apart (a captcha, a notice, a login form).
    static func pageTitle(_ html: String) -> String? {
        guard let start = html.range(of: "<title", options: .caseInsensitive),
              let open = html[start.upperBound...].firstIndex(of: ">"),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: html.index(after: open) ..< html.endIndex) else {
            return nil
        }
        var title = String(html[html.index(after: open) ..< end.lowerBound])
        for (entity, text) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            title = title.replacingOccurrences(of: entity, with: text)
        }
        title = title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if title.isEmpty {
            return nil
        }
        return title.count > 40 ? String(title.prefix(40)) + "…" : title
    }

    /// The "Please wait..." bot check instead of the page.
    static func isBotCheck(_ html: String) -> Bool {
        if html.contains(BananaTikTokExtractor.rehydrationMarker) {
            return false
        }
        return BananaTikTokExtractor.elementAttribute(html, id: "cs", attribute: "class") != nil || html.contains("Please wait...")
    }

    /// TikTok's bot check makes the browser find `n` with SHA-256(a + "n") = c, store the answer in a cookie and
    /// reload. Solved the way yt-dlp does it (`_solve_challenge_and_set_cookies`): the challenge is base64 JSON in the
    /// class of `#cs`, the cookie name is the class of `#wci`, and `#rci`/`#rs` may name a second cookie and its value.
    /// Nil when there is no challenge this code can answer.
    static func challengeCookies(_ html: String) -> [HTTPCookie]? {
        guard let encoded = BananaTikTokExtractor.elementAttribute(html, id: "cs", attribute: "class"),
              let json = BananaTikTokExtractor.decodeBase64(encoded),
              let challenge = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              challenge["d"] == nil,
              let values = challenge["v"] as? [String: Any],
              let prefix = (values["a"] as? String).flatMap(BananaTikTokExtractor.decodeBase64),
              let expected = (values["c"] as? String).flatMap(BananaTikTokExtractor.decodeBase64),
              let name = BananaTikTokExtractor.elementAttribute(html, id: "wci", attribute: "class"), !name.isEmpty,
              let answer = BananaTikTokExtractor.solveChallenge(prefix: prefix, expected: expected) else {
            return nil
        }
        // The challenge text with the answer added last, as yt-dlp writes it (json.dumps keeps the key order).
        var text = String(decoding: json, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasSuffix("}") else {
            return nil
        }
        text.removeLast()
        text += ",\"d\":\"\(Data(String(answer).utf8).base64EncodedString())\"}"
        guard let cookie = BananaTikTokExtractor.challengeCookie(name: name, value: Data(text.utf8).base64EncodedString()) else {
            return nil
        }
        var cookies = [cookie]
        if let extraName = BananaTikTokExtractor.elementAttribute(html, id: "rci", attribute: "class"), !extraName.isEmpty,
           let extraValue = BananaTikTokExtractor.elementAttribute(html, id: "rs", attribute: "class"), !extraValue.isEmpty,
           let extra = BananaTikTokExtractor.challengeCookie(name: extraName, value: extraValue) {
            cookies.append(extra)
        }
        return cookies
    }

    /// The number in 0...1,000,000 (yt-dlp's bound) whose decimal digits after `prefix` hash to `expected`.
    static func solveChallenge(prefix: Data, expected: Data) -> Int? {
        guard expected.count == SHA256.byteCount else {
            return nil
        }
        var base = SHA256()
        base.update(data: prefix)
        for number in 0 ... 1_000_000 {
            var hash = base
            var digits = String(number)
            digits.withUTF8 { hash.update(bufferPointer: UnsafeRawBufferPointer($0)) }
            if hash.finalize().elementsEqual(expected) {
                return number
            }
        }
        return nil
    }

    /// The page's script sets these for one reload; they are deleted right after it and expire soon anyway.
    private static func challengeCookie(name: String, value: String) -> HTTPCookie? {
        return HTTPCookie(properties: [
            .domain: ".tiktok.com",
            .path: "/",
            .name: name,
            .value: value,
            .expires: Date(timeIntervalSinceNow: 120.0)
        ])
    }

    /// `attribute` of the element whose id is `id`, as in `<p id="cs" class="...">`.
    private static func elementAttribute(_ html: String, id: String, attribute: String) -> String? {
        let tagPattern = "<[a-z][^>]*\\sid\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: id))[\"'][^>]*>"
        let valuePattern = "\\s\(NSRegularExpression.escapedPattern(for: attribute))\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let tagExpression = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]),
              let valueExpression = try? NSRegularExpression(pattern: valuePattern, options: [.caseInsensitive]),
              let tagMatch = tagExpression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(tagMatch.range, in: html) else {
            return nil
        }
        let tag = String(html[tagRange])
        guard let valueMatch = valueExpression.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else {
            return nil
        }
        for group in 1 ... 2 {
            if let range = Range(valueMatch.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    /// Base64 with or without its "=" padding (the challenge in the markup comes without it).
    private static func decodeBase64(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: trimmed + String(repeating: "=", count: (4 - trimmed.count % 4) % 4))
    }

    /// TikTok's own page first. When the page or one of its files fails, the post goes to TikWM, once
    /// (`fallbackLink`): a redirect to a login, challenge or home page does not prove that a share link expired. When
    /// TikWM fails too, the error names both answers. `download` fetches an item's files and calls its argument only
    /// on failure; `willUseFallback` runs before TikWM is asked.
    static func run(_ url: URL, fetcher: BananaMediaFetcher, willUseFallback: @escaping () -> Void, download: @escaping (BananaTikTokItem, @escaping (BananaLinkDownloadError) -> Void) -> Void, failure: @escaping (BananaLinkDownloadError) -> Void) {
        let fallback: (BananaLinkDownloadError, String?) -> Void = { directError, itemId in
            switch directError {
            case .cancelled, .tooLarge, .batchTooLarge, .pageTooLarge, .tiktokPrivate:
                // TikWM serves the same file, so it would be just as large, and it is not logged in either: a private
                // post or account is closed to it too, and its refusal would only hide why.
                failure(directError)
            default:
                willUseFallback()
                BananaTikTokExtractor.resolveFallback(BananaTikTokExtractor.fallbackLink(url, itemId: itemId), fetcher: fetcher, completion: { result in
                    switch result {
                    case let .failure(error):
                        failure(BananaTikTokExtractor.combine(directError, error))
                    case let .success(item):
                        download(item, { error in
                            failure(BananaTikTokExtractor.combine(directError, error))
                        })
                    }
                })
            }
        }
        BananaTikTokExtractor.resolveDirect(url, fetcher: fetcher, completion: { result, itemId in
            switch result {
            case let .failure(error):
                fallback(error, itemId)
            case let .success(item):
                download(item, { error in
                    if case let .httpStatus(code) = error {
                        fallback(.tiktokFileStatus(code), itemId)
                    } else {
                        fallback(error, itemId)
                    }
                })
            }
        })
    }

    /// The link TikWM gets. TikWM reads only the post's id from it (checked live: the same id under another author,
    /// under "/photo/" or alone brings the same post), so a post whose id is known goes as the bare post link, and
    /// any other link goes without its query and fragment: TikTok's share parameters (`_t`, `_r`, `sender_device`)
    /// tie a link to whoever shared it.
    static func fallbackLink(_ url: URL, itemId: String?) -> URL {
        if let itemId = itemId ?? BananaTikTokExtractor.itemId(from: url), let link = BananaTikTokExtractor.pageURL(itemId: itemId) {
            return link
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func combine(_ directError: BananaLinkDownloadError, _ fallbackError: BananaLinkDownloadError) -> BananaLinkDownloadError {
        switch fallbackError {
        case .cancelled, .tooLarge:
            return fallbackError
        default:
            // Both sources failing the same way (no internet) is one reason, not the same one twice.
            return fallbackError == directError ? directError : .tiktokFailed(directError, fallbackError)
        }
    }

    /// Short links (vm./vt./t/) are followed first: they redirect to "/@/video/<id>". When TikTok sends this network to
    /// another page instead (a login wall, the home page), the link is followed again the way yt-dlp does it. The
    /// post's id goes along with the answer once it is known, for `fallbackLink`.
    private static func resolveDirect(_ url: URL, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaTikTokItem, BananaLinkDownloadError>, String?) -> Void) {
        let fetch: (String) -> Void = { itemId in
            BananaTikTokExtractor.fetchItem(itemId: itemId, fetcher: fetcher, completion: { completion($0, itemId) })
        }
        if let itemId = BananaTikTokExtractor.itemId(from: url) {
            fetch(itemId)
            return
        }
        fetcher.fetchData(BananaTikTokExtractor.pageRequest(url), completion: { result in
            switch result {
            case let .failure(error):
                completion(.failure(BananaTikTokExtractor.pageError(error)), nil)
            case let .success(response):
                if let itemId = response.url.flatMap({ BananaTikTokExtractor.itemId(from: $0) }) {
                    fetch(itemId)
                    return
                }
                fetcher.finalURL(BananaTikTokExtractor.previewRequest(url), completion: { preview in
                    if case let .success(previewURL) = preview, let itemId = BananaTikTokExtractor.itemId(from: previewURL) {
                        fetch(itemId)
                    } else if case .failure(.cancelled) = preview {
                        completion(.failure(.cancelled), nil)
                    } else if response.url?.path == "/login" {
                        completion(.failure(.tiktokLoginRequired), nil)
                    } else {
                        completion(.failure(BananaTikTokExtractor.redirectError(response.url?.path ?? "", shortLink: true)), nil)
                    }
                })
            }
        })
    }

    static func resolveFallback(_ url: URL, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaTikTokItem, BananaLinkDownloadError>) -> Void) {
        var components = URLComponents(string: "https://www.tikwm.com/api/")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "hd", value: "1")]
        guard let apiURL = components.url else {
            completion(.failure(.tiktokUnavailable))
            return
        }
        fetcher.fetchData(self.pageRequest(apiURL), completion: { result in
            switch result {
            case let .failure(.httpStatus(code)):
                completion(.failure(.tiktokDownloadServiceStatus(code)))
            case let .failure(error):
                completion(.failure(error))
            case let .success(response):
                completion(self.parseFallback(response.data))
            }
        })
    }

    static func parseFallback(_ data: Data) -> Result<BananaTikTokItem, BananaLinkDownloadError> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              bananaIntValue(root["code"]) == 0, let item = root["data"] as? [String: Any] else {
            return .failure(.tiktokUnavailable)
        }
        func file(_ value: Any?, size: Int64? = nil) -> BananaRemoteFile? {
            guard let value = value as? String, !value.isEmpty,
                  let url = URL(string: value, relativeTo: URL(string: "https://www.tikwm.com/"))?.absoluteURL,
                  BananaMediaURLPolicy.isAllowed(url) else {
                return nil
            }
            return BananaRemoteFile(url: url, expectedSize: size, width: 0, height: 0)
        }
        if let images = item["images"] as? [Any], !images.isEmpty {
            let files = images.compactMap { file($0) }
            guard files.count == images.count else {
                return .failure(.tiktokUnavailable)
            }
            return .success(.photos(files))
        }
        let duration = (item["duration"] as? NSNumber)?.doubleValue ?? 0
        let candidates = [file(item["hdplay"], size: bananaIntValue(item["hd_size"])), file(item["play"], size: bananaIntValue(item["size"]))].compactMap { $0 }
        if let video = candidates.first {
            return .success(.video(BananaRemoteFile(url: video.url, expectedSize: video.expectedSize, width: video.width, height: video.height, alternateURLs: candidates.dropFirst().map { $0.url }), duration))
        }
        return .failure(.tiktokUnavailable)
    }

    private static func fetchItem(itemId: String, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaTikTokItem, BananaLinkDownloadError>) -> Void) {
        guard let url = BananaTikTokExtractor.pageURL(itemId: itemId) else {
            completion(.failure(.tiktokNoData(nil)))
            return
        }
        BananaTikTokExtractor.fetchPage(url, fetcher: fetcher, completion: { result in
            guard case let .success(page) = result, BananaTikTokExtractor.isBotCheck(page.html) else {
                completion(result.flatMap(BananaTikTokExtractor.parse))
                return
            }
            guard let cookies = BananaTikTokExtractor.challengeCookies(page.html) else {
                completion(.failure(.tiktokBotCheck))
                return
            }
            fetcher.setCookies(cookies)
            BananaTikTokExtractor.fetchPage(url, fetcher: fetcher, completion: { result in
                fetcher.deleteCookies(cookies)
                if case let .success(page) = result, BananaTikTokExtractor.isBotCheck(page.html) {
                    completion(.failure(.tiktokBotCheck))
                } else {
                    completion(result.flatMap(BananaTikTokExtractor.parse))
                }
            })
        })
    }

    /// A fetched page and where its redirects ended.
    private struct Page {
        let html: String
        let url: URL?
    }

    private static func fetchPage(_ url: URL, fetcher: BananaMediaFetcher, completion: @escaping (Result<Page, BananaLinkDownloadError>) -> Void) {
        fetcher.fetchData(BananaTikTokExtractor.pageRequest(url), completion: { result in
            completion(result.map { Page(html: String(decoding: $0.data, as: UTF8.self), url: $0.url) }.mapError(BananaTikTokExtractor.pageError))
        })
    }

    /// A post page without the post's data says where TikTok sent the request instead, when it went elsewhere.
    private static func parse(_ page: Page) -> Result<BananaTikTokItem, BananaLinkDownloadError> {
        let result = BananaTikTokExtractor.parsePage(page.html)
        guard case .failure(.tiktokNoData(_)) = result, let url = page.url else {
            return result
        }
        if url.path == "/login" {
            return .failure(.tiktokLoginRequired)
        }
        if BananaTikTokExtractor.itemId(from: url) == nil {
            return .failure(BananaTikTokExtractor.redirectError(url.path, shortLink: false))
        }
        return result
    }

    /// The page TikTok sent a short link or a post to. "/hk/about" is where TikTok sends every request from Hong
    /// Kong, so the network itself goes out there (a VPN server) and no other link would get through either.
    private static func redirectError(_ path: String, shortLink: Bool) -> BananaLinkDownloadError {
        if bananaPathSegments(path).first?.lowercased() == "hk" {
            return .tiktokHongKong
        }
        return shortLink ? .tiktokShortLinkRedirected(path) : .tiktokRedirected(path)
    }

    /// An HTTP error on a page is TikTok refusing the page, not a file.
    private static func pageError(_ error: BananaLinkDownloadError) -> BananaLinkDownloadError {
        if case let .httpStatus(code) = error {
            return .tiktokPageStatus(code)
        }
        return error
    }
}
