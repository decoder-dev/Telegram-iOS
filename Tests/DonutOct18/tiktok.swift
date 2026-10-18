struct BananaHTTPResponse {
    let data: Data
    let url: URL?
}

final class BananaMediaFetcher {
    var responses: [Result<BananaHTTPResponse, BananaLinkDownloadError>] = []
    var requests: [URLRequest] = []
    var cookieLog: [String] = []
    func fetchData(_ request: URLRequest, completion: @escaping (Result<BananaHTTPResponse, BananaLinkDownloadError>) -> Void) {
        requests.append(request)
        precondition(!responses.isEmpty, "unexpected extra request")
        completion(responses.removeFirst())
    }
    func finalURL(_ request: URLRequest, completion: @escaping (Result<URL, BananaLinkDownloadError>) -> Void) {
        requests.append(request)
        precondition(!responses.isEmpty, "unexpected extra request")
        completion(responses.removeFirst().flatMap { response -> Result<URL, BananaLinkDownloadError> in
            if let url = response.url {
                return .success(url)
            }
            return .failure(.httpStatus(0))
        })
    }
    func setCookies(_ cookies: [HTTPCookie]) {
        cookieLog.append("set " + cookies.map { $0.name }.joined(separator: ","))
    }
    func deleteCookies(_ cookies: [HTTPCookie]) {
        cookieLog.append("delete " + cookies.map { $0.name }.joined(separator: ","))
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

func response(_ object: [String: Any], url: URL? = nil) -> Result<BananaHTTPResponse, BananaLinkDownloadError> {
    return .success(BananaHTTPResponse(data: try! JSONSerialization.data(withJSONObject: object), url: url))
}

func htmlResponse(_ html: String, url: URL) -> Result<BananaHTTPResponse, BananaLinkDownloadError> {
    return .success(BananaHTTPResponse(data: Data(html.utf8), url: url))
}

let post = URL(string: "https://www.tiktok.com/@scout2015/video/6718335390845095173")!
let short = URL(string: "https://vm.tiktok.com/ABC123/?test=a&another=b")!
let home = URL(string: "https://www.tiktok.com/")!
let video: [String: Any] = ["code": 0, "data": ["hdplay": "https://cdn.mediahost.com/video.mp4", "hd_size": "12345", "play": "https://cdn.mediahost.com/sd.mp4", "duration": 15]]
let fetcher = BananaMediaFetcher()
let page = #"{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"statusCode":0,"itemInfo":{"itemStruct":{"video":{"playAddr":"https://cdn.mediahost.com/direct.mp4","duration":5}}}}}}"#
let html = "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\">" + page + "</script>"
// What TikTok's Akamai ebananae answered a GitHub runner with, as HTTP 200 (X-Cache: TCP_DENIED).
let deniedPage = """
<!doctype html>
<html>
<head>
    <title>Site Maintenance</title>
    <style type="text/css">body { text-align: center; padding: 150px; }h1 { font-size: 40px; }body { font: 16px
Helvetica, sans-serif; color: #333; }#error { display: block; text-align: left; width: 650px; margin: 0 auto; }
</style>
</head>
<body>
    <div id="error">
    <h1>Oops! Something went wrong</h1>
    <div>
        <hr>
        <p>Please contact your administrator with the error code: 0.591e2117.1792313912.be90ad69</p>
    </div>
    </div>
</body>
</html
"""

/// The whole TikTok flow against canned answers. `files` are the outcomes of downloading each item in turn:
/// nil means the files arrived and the job is done, an error goes back to the extractor.
func flow(_ url: URL, _ answers: [Result<BananaHTTPResponse, BananaLinkDownloadError>], files: [BananaLinkDownloadError?] = [nil]) -> (items: [BananaTikTokItem], failure: BananaLinkDownloadError?, fallbacks: Int) {
    fetcher.requests.removeAll()
    fetcher.cookieLog.removeAll()
    fetcher.responses = answers
    var items: [BananaTikTokItem] = []
    var failure: BananaLinkDownloadError?
    var fallbacks = 0
    var outcomes = files
    BananaTikTokExtractor.run(url, fetcher: fetcher, willUseFallback: { fallbacks += 1 }, download: { item, failed in
        items.append(item)
        precondition(!outcomes.isEmpty, "unexpected extra download")
        if let error = outcomes.removeFirst() {
            failed(error)
        }
    }, failure: { error in
        precondition(failure == nil, "one final error")
        failure = error
    })
    check(fetcher.responses.isEmpty && outcomes.isEmpty, "every canned answer and download used")
    return (items, failure, fallbacks)
}

func tikwmRequests() -> Int {
    return fetcher.requests.filter { $0.url?.host == "www.tikwm.com" }.count
}

/// The link the provider was asked about in the last flow.
func tikwmLink() -> String? {
    guard let url = fetcher.requests.last(where: { $0.url?.host == "www.tikwm.com" })?.url else {
        return nil
    }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value
}

var run = flow(post, [htmlResponse(html, url: post)])
if case let .video(file, _)? = run.items.first {
    check(file.url.absoluteString == "https://cdn.mediahost.com/direct.mp4", "keep working direct extraction")
} else { fatalError("direct page") }
check(run.failure == nil && run.fallbacks == 0 && fetcher.requests.count == 1, "working direct pages never contact provider")

run = flow(short, [htmlResponse("challenge", url: home), htmlResponse("", url: home), response(video)])
if case let .video(file, duration)? = run.items.first {
    check(file.url.absoluteString == "https://cdn.mediahost.com/video.mp4", "prefer HD")
    check(file.expectedSize == 12345 && duration == 15, "provider metadata")
    check(file.alternateURLs == [URL(string: "https://cdn.mediahost.com/sd.mp4")!], "keep SD from another CDN when HD is blocked")
} else { fatalError("a challenge redirect must use the provider") }
check(run.failure == nil && run.fallbacks == 1 && fetcher.requests.count == 3 && tikwmRequests() == 1, "one fallback request")
check(fetcher.requests[1].httpMethod == "HEAD" && fetcher.requests[1].url == short, "the short link is followed once more before the provider")
check(fetcher.requests[1].value(forHTTPHeaderField: "User-Agent") == "facebookexternalhit/1.1", "as Facebook's preview bot, like yt-dlp")
// TikTok's share parameters tie a link to whoever shared it; the provider needs only the post.
check(tikwmLink() == "https://vm.tiktok.com/ABC123/", "a short link goes to the provider without its query")
let sharedPost = URL(string: "https://www.tiktok.com/@scout2015/photo/6718335390845095173?_t=8share&_r=1&sender_device=pc#comments")!
run = flow(sharedPost, [.failure(.httpStatus(403)), response(video)])
check(run.failure == nil && tikwmLink() == "https://www.tiktok.com/@/video/6718335390845095173", "a known post goes to the provider as the bare post link")

run = flow(post, [.failure(.httpStatus(403)), response(video)])
check(run.items.count == 1 && run.failure == nil && run.fallbacks == 1, "page HTTP 403 must use fallback")

run = flow(post, [.failure(.cancelled)], files: [])
check(run.failure == .cancelled && run.fallbacks == 0 && fetcher.requests.count == 1, "cancellation never contacts fallback")

var result: Result<BananaTikTokItem, BananaLinkDownloadError>?
fetcher.responses = [.failure(.httpStatus(403))]
BananaTikTokExtractor.resolveFallback(short, fetcher: fetcher) { result = $0 }
check(result == .failure(.tiktokDownloadServiceStatus(403)), "distinguish resolver HTTP errors from media errors")

// When both sources fail, the toast names TikTok's answer too: TikWM's alone hid it.
run = flow(post, [.failure(.httpStatus(403)), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokPageStatus(403), .tiktokDownloadServiceStatus(403)), "page and provider errors are both kept")
check(run.failure?.reason == "TikTok не отдал страницу (HTTP 403). Сервис скачивания TikTok вернул HTTP 403", "both reasons on the toast")
run = flow(post, [htmlResponse(deniedPage, url: post), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokPageDenied, .tiktokDownloadServiceStatus(403)), "Akamai's HTTP 200 deny page is named")
check(BananaLinkDownloadError.tiktokFailed(.tiktokNoData(nil), .tiktokUnavailable).reason == "TikTok прислал страницу без видео. Сервис скачивания TikTok не отдал видео", "reason text")
run = flow(post, [.failure(.network(.notConnectedToInternet)), .failure(.network(.notConnectedToInternet))], files: [])
check(run.failure == .network(.notConnectedToInternet) && run.failure?.reason == "Нет интернета", "the same answer from both sources is named once")

// A failed TikTok file goes to TikWM once; TikWM is never asked twice in one job.
run = flow(post, [htmlResponse(html, url: post), response(video)], files: [.httpStatus(403), .httpStatus(403)])
check(run.items.count == 2 && run.fallbacks == 1 && tikwmRequests() == 1, "one provider request per job")
check(run.failure == .tiktokFailed(.tiktokFileStatus(403), .httpStatus(403)), "file errors of both sources are kept")
run = flow(short, [htmlResponse("home", url: home), htmlResponse("", url: home), response(video)], files: [.httpStatus(403)])
check(tikwmRequests() == 1 && run.failure == .tiktokFailed(.tiktokShortLinkRedirected("/"), .httpStatus(403)), "a provider file failure is final")
run = flow(post, [htmlResponse(html, url: post)], files: [.tooLarge])
check(run.failure == .tooLarge && run.fallbacks == 0 && fetcher.requests.count == 1, "the provider's copy would be too large as well")
run = flow(post, [htmlResponse(html, url: post), response(video)], files: [.processingFailed, .tooLarge])
check(run.failure == .tooLarge, "the size limit is reported as it is")

// TikTok's bot check: find n with SHA-256(a + "n") = c, answer in a cookie, reload.
func challengePage(answer: Int, extraCookie: Bool) -> (html: String, json: String) {
    let prefix = Data("banana-challenge-prefix".utf8)
    var hasher = SHA256()
    hasher.update(data: prefix)
    hasher.update(data: Data(String(answer).utf8))
    let digest = Data(hasher.finalize())
    let json = #"{"v":{"a":""# + prefix.base64EncodedString() + #"","b":"x","c":""# + digest.base64EncodedString() + #""},"s":"sig/+"}"#
    var encoded = Data(json.utf8).base64EncodedString()
    while encoded.hasSuffix("=") {
        encoded.removeLast()
    }
    var page = "<html><head><title>Please wait...</title></head><body><p id=\"cs\" class=\"" + encoded + "\"></p><p class=\"_wafchallengeid\" id=\"wci\"></p>"
    if extraCookie {
        page += "<p id=\"rci\" class=\"waforiginalreid\"></p><p id='rs' class='original-value'></p>"
    }
    return (page + "<script>/* solve and reload */</script></body></html>", json)
}

let challenge = challengePage(answer: 54321, extraCookie: true)
check(BananaTikTokExtractor.isBotCheck(challenge.html) && !BananaTikTokExtractor.isBotCheck(html), "bot check recognized only without page data")
check(BananaTikTokExtractor.solveChallenge(prefix: Data("banana-challenge-prefix".utf8), expected: Data(repeating: 0, count: 31)) == nil, "a malformed digest is not searched")
let cookies = BananaTikTokExtractor.challengeCookies(challenge.html) ?? []
check(cookies.map { $0.name } == ["_wafchallengeid", "waforiginalreid"], "cookie names come from the page")
check(cookies.allSatisfy { $0.domain == ".tiktok.com" && $0.path == "/" }, "cookies reach www.tiktok.com")
check(cookies.count == 2 && cookies[1].value == "original-value", "the optional second cookie keeps its value")
let answerText = cookies.first.flatMap { Data(base64Encoded: $0.value) }.map { String(decoding: $0, as: UTF8.self) }
check(answerText == String(challenge.json.dropLast()) + #","d":"NTQzMjE="}"#, "the challenge text with the answer d = base64(\"54321\") added last")

run = flow(post, [htmlResponse(challenge.html, url: post), htmlResponse(html, url: post)])
check(run.failure == nil && run.fallbacks == 0 && run.items.count == 1, "a solved bot check reaches the page")
check(fetcher.requests.count == 2 && fetcher.requests[0].url == fetcher.requests[1].url, "the same page is asked again")
check(fetcher.cookieLog == ["set _wafchallengeid,waforiginalreid", "delete _wafchallengeid,waforiginalreid"], "challenge cookies are set for the reload only")
run = flow(post, [htmlResponse(challenge.html, url: post), htmlResponse(challenge.html, url: post), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokBotCheck, .tiktokDownloadServiceStatus(403)), "a bot check that stays is named")
check(fetcher.cookieLog.last == "delete _wafchallengeid,waforiginalreid", "cookies are removed after a failed reload too")
let unsolvable = challengePage(answer: 1_000_001, extraCookie: false)
check(BananaTikTokExtractor.challengeCookies(unsolvable.html) == nil, "search stops at yt-dlp's bound")
run = flow(post, [htmlResponse(unsolvable.html, url: post), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokBotCheck, .tiktokDownloadServiceStatus(403)) && fetcher.cookieLog.isEmpty, "an unsolved bot check goes to the provider")

// Every CDN copy of the chosen variant, then the default stream; www.tiktok.com links come after them.
let variants = #"{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"statusCode":0,"itemInfo":{"itemStruct":{"video":{"duration":7,"playAddr":"https://v77.cdn.mediahost.com/play.mp4","bitrateInfo":[{"CodecType":"h264","Bitrate":900,"PlayAddr":{"DataSize":"777","Width":576,"Height":1024,"UrlList":["https://www.tiktok.com/aweme/v1/play/?video_id=1","https://v16.cdn.mediahost.com/hd.mp4","https://v19.cdn.mediahost.com/hd.mp4"]}},{"CodecType":"h264","Bitrate":100,"PlayAddr":{"UrlList":["https://v16.cdn.mediahost.com/sd.mp4"]}},{"CodecType":"bytevc1","Bitrate":5000,"PlayAddr":{"UrlList":["https://v16.cdn.mediahost.com/hevc.mp4"]}}]}}}}}}"#
if case let .success(.video(file, duration)) = BananaTikTokExtractor.parsePage("<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\" type=\"application/json\">" + variants + "</script>") {
    check(file.url.absoluteString == "https://v16.cdn.mediahost.com/hd.mp4" && file.expectedSize == 777 && duration == 7, "best h264 variant")
    check(file.alternateURLs.map { $0.absoluteString } == ["https://v19.cdn.mediahost.com/hd.mp4", "https://v77.cdn.mediahost.com/play.mp4", "https://www.tiktok.com/aweme/v1/play/?video_id=1"], "other CDN copies, the default stream, then www.tiktok.com")
} else { fatalError("variants page") }
check(BananaTikTokExtractor.parsePage(deniedPage) == .failure(.tiktokPageDenied), "deny page")

// Where TikTok sends a network instead of the post, named on the toast.
func rehydrated(_ item: [String: Any], status: Int = 0) -> String {
    let scope: [String: Any] = ["__DEFAULT_SCOPE__": ["webapp.video-detail": ["statusCode": status, "itemInfo": ["itemStruct": item]]]]
    return "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\" type=\"application/json\">" + String(decoding: try! JSONSerialization.data(withJSONObject: scope), as: UTF8.self) + "</script>"
}
run = flow(short, [htmlResponse("home", url: home), htmlResponse("", url: post), htmlResponse(html, url: post)])
check(run.failure == nil && run.fallbacks == 0 && run.items.count == 1, "a short link sent home is found by the preview bot's redirect")
check(fetcher.requests.count == 3 && fetcher.requests[2].url == BananaTikTokExtractor.pageURL(itemId: "6718335390845095173"), "then the post page")
let wall = URL(string: "https://www.tiktok.com/login?redirect_url=https%3A%2F%2Fwww.tiktok.com%2F%40scout2015%2Fvideo%2F6718335390845095173%3Fis_from_webapp%3D1")!
check(BananaTikTokExtractor.itemId(from: wall) == "6718335390845095173", "a login wall keeps the post in redirect_url")
run = flow(short, [htmlResponse("login", url: wall), htmlResponse(html, url: post)])
check(run.failure == nil && run.items.count == 1 && fetcher.requests.count == 2, "a short link behind a login wall still finds the post")
run = flow(short, [htmlResponse("login", url: wall), .failure(.httpStatus(403)), response(video)])
check(run.failure == nil && tikwmLink() == "https://www.tiktok.com/@/video/6718335390845095173", "a short link whose post was found goes to the provider as that post")
let login = URL(string: "https://www.tiktok.com/login")!
run = flow(short, [htmlResponse("login", url: login), htmlResponse("", url: login), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokLoginRequired, .tiktokDownloadServiceStatus(403)), "a short link that only reaches the login form")
run = flow(post, [htmlResponse("<title>Log in | TikTok</title>", url: wall), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokLoginRequired, .tiktokDownloadServiceStatus(403)), "a post page behind a login wall")
check(run.failure?.reason == "TikTok просит войти в аккаунт. Сервис скачивания TikTok вернул HTTP 403", "login reason")
run = flow(post, [htmlResponse("<title>TikTok - Make Your Day</title>", url: URL(string: "https://www.tiktok.com/foryou?lang=ru")!), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokRedirected("/foryou"), .tiktokDownloadServiceStatus(403)), "a post page sent to the feed")
check(run.failure?.reason == "TikTok открыл /foryou вместо видео. Сервис скачивания TikTok вернул HTTP 403", "redirect reason")
// TikTok left Hong Kong in 2020: a network that goes out there gets "/hk/about" for a short link and a post alike.
let hongKong = URL(string: "https://www.tiktok.com/hk/about")!
run = flow(short, [htmlResponse("<title>TikTok</title>", url: hongKong), htmlResponse("", url: hongKong), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokHongKong, .tiktokDownloadServiceStatus(403)), "a short link sent to the Hong Kong notice")
check(run.failure?.reason == "TikTok не работает через этот VPN, смените сервер. Сервис скачивания TikTok вернул HTTP 403", "Hong Kong reason")
run = flow(post, [htmlResponse("<title>TikTok</title>", url: hongKong), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokHongKong, .tiktokDownloadServiceStatus(403)), "a post page sent to the Hong Kong notice")
run = flow(post, [htmlResponse("<html><head><TITLE>\n  Verify &amp; continue  </TITLE></head><body></body></html>", url: post), .failure(.httpStatus(403))], files: [])
check(run.failure == .tiktokFailed(.tiktokNoData("Verify & continue"), .tiktokDownloadServiceStatus(403)), "an unknown page is named by its title")
check(run.failure?.reason == "TikTok прислал страницу без видео: «Verify & continue». Сервис скачивания TikTok вернул HTTP 403", "title reason")
run = flow(post, [htmlResponse(html, url: URL(string: "https://www.tiktok.com/video/6718335390845095173")!)])
check(run.failure == nil && run.items.count == 1, "a page with the post's data is used wherever it was served")
check(BananaLinkDownloadError.tiktokShortLinkRedirected("/").reason == "Короткая ссылка TikTok ведёт на главную, а не на видео", "home is named")
check(BananaLinkDownloadError.tiktokRedirected("/@" + String(repeating: "a", count: 60)).reason == "TikTok открыл /@" + String(repeating: "a", count: 38) + "… вместо видео", "long paths are shortened")
check(BananaTikTokExtractor.pageTitle("<title>" + String(repeating: "б", count: 50) + "</title>") == String(repeating: "б", count: 40) + "…", "long titles are shortened")
check(BananaTikTokExtractor.pageTitle("<title> </title>") == nil && BananaTikTokExtractor.pageTitle("no title") == nil, "no title")

// What the post data can carry instead of a usable file.
check(BananaTikTokExtractor.parsePage(rehydrated(["isContentClassified": true, "video": ["duration": 9]])) == .failure(.tiktokAgeRestricted), "18+ posts come without files")
check(BananaTikTokExtractor.parsePage(rehydrated(["video": ["duration": 9]])) == .failure(.tiktokNoFile), "no file links")
check(BananaTikTokExtractor.parsePage(rehydrated(["imagePost": ["images": [["imageURL": ["urlList": []]]]]])) == .failure(.tiktokNoFile), "photo without links")
check(BananaTikTokExtractor.parsePage(rehydrated([:], status: 10216)) == .failure(.tiktokPrivate), "private post")
// TikWM is not logged in either: it is not asked for a private post or account, and the toast says why.
run = flow(post, [htmlResponse(rehydrated([:], status: 10222), url: post)], files: [])
check(run.failure == .tiktokPrivate && run.fallbacks == 0 && tikwmRequests() == 0, "a private post is not sent to the provider")
check(run.failure?.reason == "Закрытый аккаунт", "private reason")
check(BananaTikTokExtractor.parsePage("<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\">{\"__DEFAULT_SCOPE__\":{\"webapp.app-context\":{}}}</script><title>TikTok</title>") == .failure(.tiktokNoData("TikTok")), "page data without the post")
if case let .success(.video(file, _)) = BananaTikTokExtractor.parsePage(rehydrated(["video": ["bitrateInfo": [["CodecType": "h264", "Bitrate": 1, "PlayAddr": ["UrlList": ["https://www.tiktok.com/aweme/v1/play/?video_id=2"]]]]]])) {
    check(file.url.absoluteString == "https://www.tiktok.com/aweme/v1/play/?video_id=2" && file.alternateURLs.isEmpty, "www.tiktok.com links are used when nothing else is there")
} else { fatalError("www-only page") }
if case let .success(.video(file, _)) = BananaTikTokExtractor.parsePage(rehydrated(["video": ["playAddr": [["src": "https://v16.cdn.mediahost.com/play.mp4"], ["src": "//v19.cdn.mediahost.com/play.mp4"]], "downloadAddr": "https://v16.cdn.mediahost.com/watermarked.mp4", "width": 720, "height": 1280]])) {
    check(file.url.absoluteString == "https://v16.cdn.mediahost.com/play.mp4" && file.width == 720 && file.height == 1280 && file.expectedSize == nil, "playAddr as a list of sources")
    check(file.alternateURLs.map { $0.absoluteString } == ["https://v19.cdn.mediahost.com/play.mp4", "https://v16.cdn.mediahost.com/watermarked.mp4"], "protocol-relative copy, then the watermarked download")
} else { fatalError("playAddr list page") }

let photos: [String: Any] = ["code": 0, "data": ["images": ["//cdn.mediahost.com/1.jpg", "https://cdn.mediahost.com/2.jpg"], "play": "https://cdn.mediahost.com/cover.mp4"]]
let photosData = try! JSONSerialization.data(withJSONObject: photos)
if case let .success(.photos(files)) = BananaTikTokExtractor.parseFallback(photosData) {
    check(files.count == 2 && files[0].url.absoluteString == "https://cdn.mediahost.com/1.jpg", "preserve carousel order")
} else { fatalError("carousel must stay photos") }
for bad: [String: Any] in [["code": -1, "msg": "busy"], ["code": 0, "data": [:]], ["code": 0, "data": ["images": ["https://cdn.mediahost.com/1.jpg", "file:///tmp/bad"]]]] {
    check(BananaTikTokExtractor.parseFallback(try! JSONSerialization.data(withJSONObject: bad)) == .failure(.tiktokUnavailable), "no false expired-link error or partial carousel")
}
let sd = try! JSONSerialization.data(withJSONObject: ["code": 0, "data": ["play": "/video/media/play/test.mp4"]])
if case let .success(.video(file, _)) = BananaTikTokExtractor.parseFallback(sd) {
    check(file.url.absoluteString == "https://www.tikwm.com/video/media/play/test.mp4", "relative provider URL")
} else { fatalError("SD fallback") }
check(BananaLinkDownloadLink.parse(short.absoluteString) != nil, "short link accepted")
check(BananaLinkDownloadLink.parse("https://www.youtube.com/shorts/abcdefghijk") != nil, "Shorts still accepted")
print("TikTok fallback checks passed")
