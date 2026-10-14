"""Execute adapted production search/ghost policies; keep UIKit wiring explicit."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text(encoding='utf-8')
def function(source, name):
    start = source.index('func ' + name)
    if source[max(0, start-7):start] == 'public ': start -= 7
    return source[start:source.index('\n}', start)+2]
def static_method(source, name):
    signature = source.index('static func ' + name)
    start = source.rfind('\n', 0, signature) + 1
    end = source.index('\n    }', signature) + len('\n    }')
    return source[start:end]

def instance_method(source, signature):
    start = source.index(signature)
    start = source.rfind('\n', 0, start) + 1
    return source[start:source.index('\n    }', start) + len('\n    }')]
def execute(source):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / 'main.swift'
        binary = pathlib.Path(directory) / 'fixture'
        path.write_text(source, encoding='utf-8')
        subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True, timeout=120)
        subprocess.run([str(binary)], check=True, timeout=30)

class DonutAdaptation(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_download_file_is_preserved_before_async_consumers_and_failed_moves_clean_up(self):
        source = read('submodules/WebUI/Sources/WebAppController.swift')
        start = source.index('                        let tempFile = EngineTempBox.shared.tempFile(fileName: fileName)', source.index('fileprivate func startDownload('))
        end = source.index('                        let tooltipContent:', start)
        staging = source[start:end]
        execute('''import Foundation
struct TempFile { let path: String }
final class EngineTempBox {
    static let shared = EngineTempBox()
    var disposals = 0
    var root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    func tempFile(fileName: String) -> TempFile {
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return TempFile(path: root.appendingPathComponent(UUID().uuidString + fileName).path)
    }
    func dispose(_ file: TempFile) { disposals += 1; try? FileManager.default.removeItem(atPath: file.path) }
}
final class Tooltip { var dismissed = false; func dismissWithCommitAction() { dismissed = true } }
final class Staging {
    var fileDownloadTooltip: Tooltip? = Tooltip()
    var preservedURL: URL?
    func complete(_ resultUrl: URL, fileName: String) {
''' + staging + '''
        self.preservedURL = url
    }
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.removeItem(at: EngineTempBox.shared.root)
}
let source = directory.appendingPathComponent("download with spaces.tmp")
let bytes = Data([1, 2, 3, 4])
try bytes.write(to: source)
let staging = Staging()
staging.complete(source, fileName: "photo.jpg")
precondition(!FileManager.default.fileExists(atPath: source.path))
let preserved = staging.preservedURL!
let preservedBytes = try Data(contentsOf: preserved)
precondition(preservedBytes == bytes)
// A later asynchronous reader still has a valid path after the download callback returned.
let reader = try FileHandle(forReadingFrom: preserved)
precondition(reader.readDataToEndOfFile() == bytes)
reader.closeFile()
let failure = Staging()
failure.complete(directory.appendingPathComponent("missing"), fileName: "photo.jpg")
precondition(failure.preservedURL == nil && failure.fileDownloadTooltip?.dismissed == true)
precondition(EngineTempBox.shared.disposals == 1)
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_web_store_recovers_corrupt_identifiers_without_merging_accounts(self):
        source = read('submodules/WebUI/Sources/WebAppWebView.swift')
        start = source.index('            var uuid: UUID?')
        end = source.index('            if let uuid {', start)
        selection = source[start:end].replace('UserDefaults.standard', 'defaults')
        browser = read('submodules/BrowserUI/Sources/BrowserWebContent.swift')
        start = browser.index('                    let uuid: UUID')
        end = browser.index('                    configuration.websiteDataStore', start)
        pwa_selection = browser[start:end]
        execute('''import Foundation
struct AccountId { let int64: Int64 }
struct Account { let id: AccountId }
func identifier(accountId: Int64, defaults: UserDefaults) -> UUID? {
    let account = Account(id: AccountId(int64: accountId))
''' + selection + '''
    return uuid
}
func pwaIdentifier(path: String) -> UUID {
    let pwaPath = path
    let uuidPath = path + "/uuid_example.com"
''' + pwa_selection + '''
    return uuid
}
let suite = "WebStoreFixture." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
precondition(identifier(accountId: 1, defaults: defaults) == nil)
let second = identifier(accountId: 2, defaults: defaults)
precondition(second != nil && identifier(accountId: 2, defaults: defaults) == second)
defaults.set("broken-uuid", forKey: "TelegramWebStoreUUID_2")
let repaired = identifier(accountId: 2, defaults: defaults)
precondition(repaired != nil && repaired != second)
precondition(identifier(accountId: 2, defaults: defaults) == repaired)
precondition(identifier(accountId: 1, defaults: defaults) == nil)
let third = identifier(accountId: 3, defaults: defaults)
precondition(third != nil && third != repaired)
defaults.set(42, forKey: "TelegramWebStoreUUID_2")
precondition(identifier(accountId: 2, defaults: defaults) != nil)
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: directory) }
let firstPwa = pwaIdentifier(path: directory.path)
precondition(pwaIdentifier(path: directory.path) == firstPwa)
let uuidFile = directory.appendingPathComponent("uuid_example.com")
try "bad".write(to: uuidFile, atomically: true, encoding: .utf8)
let repairedPwa = pwaIdentifier(path: directory.path)
precondition(repairedPwa != firstPwa)
precondition(pwaIdentifier(path: directory.path) == repairedPwa)
try Data([0xff, 0xfe]).write(to: uuidFile)
let recoveredUtf8 = pwaIdentifier(path: directory.path)
precondition(pwaIdentifier(path: directory.path) == recoveredUtf8)
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_bot_download_progress_and_integer_boundaries(self):
        source = read('submodules/WebUI/Sources/FileDownload.swift')
        execute('import Foundation\n' + function(source, 'botDownloadProgress') + '\n' + function(source, 'botDownloadReceivedBytes') + '''
precondition(botDownloadProgress(received: 0, expected: 0) == 0)
precondition(botDownloadProgress(received: 20, expected: -1) == 0)
precondition(botDownloadProgress(received: -1, expected: 100) == 0)
precondition(botDownloadProgress(received: 50, expected: 100) == 0.5)
precondition(botDownloadProgress(received: Int64.max, expected: 1) == 1)
for size in [Int64(0), 1, 100, Int64.max - 1, Int64.max] {
    for progress in [Double.nan, .infinity, -.infinity, -1, 0, 0.5, 1.0.nextDown, 1, 2] {
        let received = botDownloadReceivedBytes(fileSize: size, progress: progress)
        precondition(received >= 0 && received <= size)
    }
    precondition(botDownloadReceivedBytes(fileSize: size, progress: 1) == size)
}
precondition(botDownloadReceivedBytes(fileSize: -1, progress: 0.5) == 0)
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_bot_download_status_lifecycle_and_redirects(self):
        source = read('submodules/WebUI/Sources/FileDownload.swift')
        download_class = source.split('final class FileDownload:', 1)[1]
        methods = '\n'.join(instance_method(download_class, signature) for signature in [
            'private func finish(',
            'func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo',
            'func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError',
            'func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection',
        ])
        redirect_delegate = source[source.index('private final class BotDownloadRedirectDelegate'):source.index('\nfunc botDownloadProgress')]
        execute('''import Foundation
import Darwin
class URLSession { var invalidations = 0; func finishTasksAndInvalidate() { invalidations += 1 } }
class URLSessionTask {}
class URLSessionDownloadTask: URLSessionTask { var response: URLResponse? }
protocol URLSessionTaskDelegate {}
''' + read('submodules/WebUI/Sources/WebAppUtils.swift') + '\n' + redirect_delegate + '''
final class Harness {
    var urlSession: URLSession?
    var task: URLSessionDownloadTask?
    var completion: ((URL?, Error?) -> Void)?
    var progressHandler: ((Double) -> Void)?
''' + methods + '''
}
func checkStatus(_ status: Int, success: Bool) {
    let session = URLSession(), task = URLSessionDownloadTask(), download = Harness()
    download.urlSession = session
    download.task = task
    task.response = HTTPURLResponse(url: URL(string: "https://example.com/file")!, statusCode: status, httpVersion: nil, headerFields: nil)
    var calls = 0
    download.completion = { url, error in
        calls += 1
        precondition((url != nil) == success && (error == nil) == success)
    }
    download.urlSession(session, downloadTask: task, didFinishDownloadingTo: URL(fileURLWithPath: "/tmp/download-fixture"))
    download.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
    precondition(calls == 1 && session.invalidations == 1)
    precondition(download.urlSession == nil && download.task == nil && download.completion == nil)
}
checkStatus(200, success: true)
checkStatus(206, success: true)
for status in [302, 403, 404, 500] { checkStatus(status, success: false) }
let failed = Harness(), failedSession = URLSession()
failed.urlSession = failedSession
var errors = 0
failed.completion = { url, error in precondition(url == nil && error != nil); errors += 1 }
failed.urlSession(failedSession, task: URLSessionTask(), didCompleteWithError: URLError(.timedOut))
failed.urlSession(failedSession, task: URLSessionTask(), didCompleteWithError: URLError(.cancelled))
precondition(errors == 1 && failedSession.invalidations == 1)
func checkRedirects() {
    let delegate = BotDownloadRedirectDelegate(), harness = Harness()
    let response = HTTPURLResponse(url: URL(string: "https://example.com/file")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
    for (url, allowed) in [
        ("https://cdn.example.com/file", true), ("http://cdn.example.com/file", false),
        ("file:///tmp/private", false), ("https://127.0.0.1/file", false),
        ("https://10.0.0.1/file", false), ("https://[::1]/file", false),
        ("https://user:password@example.com/file", false)
    ] {
        let request = URLRequest(url: URL(string: url)!)
        var callbacks = 0
        let completion: (URLRequest?) -> Void = { next in precondition((next != nil) == allowed); callbacks += 1 }
        delegate.urlSession(URLSession(), task: URLSessionTask(), willPerformHTTPRedirection: response, newRequest: request, completionHandler: completion)
        harness.urlSession(URLSession(), task: URLSessionTask(), willPerformHTTPRedirection: response, newRequest: request, completionHandler: completion)
        precondition(callbacks == 2)
    }
}
checkRedirects()
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_untrusted_video_metadata_cannot_trap_integer_conversion(self):
        source = read('submodules/BananaLinkDownloader/Sources/BananaMediaProcessor.swift')
        method = static_method(source, 'validatedVideoInfo')
        execute('''import Foundation
enum BananaMediaProcessor {
    struct VideoInfo { let duration: Double; let width: Int; let height: Int }
''' + method + '''
}
let valid = BananaMediaProcessor.validatedVideoInfo(width: -1920, height: 1080, duration: 30)
precondition(valid?.width == 1920 && valid?.height == 1080 && valid?.duration == 30)
for invalid in [CGFloat.nan, .infinity, -.infinity, .greatestFiniteMagnitude, 0, 0.1, 65536, CGFloat(Int32.max) + 1] {
    precondition(BananaMediaProcessor.validatedVideoInfo(width: invalid, height: 1080, duration: 30) == nil)
    precondition(BananaMediaProcessor.validatedVideoInfo(width: 1920, height: invalid, duration: 30) == nil)
}
for duration in [Double.nan, .infinity, -.infinity, -1, 0] {
    precondition(BananaMediaProcessor.validatedVideoInfo(width: 1920, height: 1080, duration: duration) == nil)
}
let boundary = BananaMediaProcessor.validatedVideoInfo(width: 65535, height: 1, duration: 1)
precondition(boundary?.width == 65535)
''')

    def test_retention_and_server_pagination_wiring(self):
        search = read('submodules/TelegramCore/Sources/TelegramEngine/Messages/SearchMessages.swift')
        self.assertIn('bananaSearchResultIncludingDeletedMessages(result, deletedMessages: localMessages), updatedState', search)
        self.assertEqual(search.count('bananaIndexRetainedMessages('), 2)  # Current and migrated group.
        delete = read('submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift')
        self.assertIn('localTags: currentMessage.localTags.union(.bananaDeleted)', delete)
        self.assertIn('message.isLocallyDeleted, !message.localTags.contains(.bananaDeleted)', delete)
        self.assertIn('attributes: currentMessage.attributes', delete)
        sparse = read('submodules/TelegramCore/Sources/TelegramEngine/Messages/SparseMessageList.swift')
        self.assertEqual(sparse.count('self.preservedMessagesDisposable?.dispose()'), 2)
        self.assertIn('filter { !$0.message.isLocallyDeleted }', sparse)
        self.assertIn('content: .message(message: message, isLocal: true)', sparse)

    def test_ghost_and_opt_in_consumers(self):
        core = 'submodules/TelegramCore/Sources/'
        for file in ['Account/Account.swift','State/SynchronizeAppLogEventsOperation.swift','State/ManagedSynchronizeAppLogEventsOperations.swift','TelegramEngine/Calls/RateCall.swift','TelegramEngine/Messages/TelegramEngineMessages.swift']:
            self.assertIn('guard ForkTelegramStatisticsSettings.enabled', read(core+file), file)
        self.assertIn('guard !ForkGhostModeSettings.suppressStoryViews', read(core+'State/ManagedSynchronizeViewStoriesOperations.swift'))
        enqueue = read(core+'PendingMessages/EnqueueMessage.swift')
        ghost_policy = read(core+'Arena/BananaGhostPrivacy.swift')
        self.assertIn('peerNamespace: PeerId.Namespace', ghost_policy)
        self.assertIn('peerNamespace: peerId.namespace', enqueue)
        self.assertIn('allowedIndices = messages.indices.filter', enqueue)
        self.assertIn('for (index, id) in zip(allowedIndices, ids)', enqueue)
        self.assertIn('attributes.contains(where: { $0 is OutgoingQuickReplyMessageAttribute })', enqueue)
        for file in ['TelegramEngine/Messages/RequestStartBot.swift','TelegramEngine/Messages/QuickReplyMessages.swift','TelegramEngine/Messages/Polls.swift','TelegramEngine/Messages/BotWebView.swift','TelegramEngine/Messages/ScheduledMessages.swift','PendingMessages/RequestEditMessage.swift','State/MessageReactions.swift']:
            text = read(core+file)
            self.assertIn('bananaRequestGhostOfflineAfterAction(network:', text, file)
            self.assertNotIn('donutgramRequestGhostOfflineAfterAction', text, file)

    def test_island_and_pings_live_wiring(self):
        prefs = read('submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift')
        for key in ['bananaIslandEnabled','bananaIslandShowsName','sendTelegramStatistics','removePings']:
            self.assertIn('decodeIfPresent(Bool.self, forKey: "'+key+'")', prefs)
            self.assertIn('container.encode(self.'+key, prefs)
        window = read('submodules/Display/Source/WindowContent.swift')
        self.assertEqual(window.count('!self.appBadgeEnabled || !self.deviceMetrics.showAppBadge || self.forceBadgeHidden'), 2)
        context = read('submodules/TelegramUI/Sources/SharedAccountContext.swift')
        self.assertIn('strongSelf.updateBananaIslandBadge(strongSelf.immediateForkExtrasSettingsValue', context)
        self.assertIn('self.updateBananaIslandBadge(settings)', context)
        notification = read('Telegram/NotificationService/Sources/NotificationService.swift')
        self.assertIn('guard ForkExtrasNotificationBridge.removePings', notification)
        self.assertIn('then(ordinaryMentionContent)', notification)
        story = read('submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemContentComponent.swift')
        self.assertIn('self.component?.item.id == requestedStoryId', story)
        self.assertIn('previousItem?.id != component.item.id', story)
        menu = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        self.assertIn('arguments.openCategory(.appearance)', menu)
        self.assertIn('(.appearance, [[1618, 1531, 1532, 1553, 1619]])', menu)
        links = read('submodules/SettingsUI/Sources/BananaSettingsLinks.swift')
        self.assertIn('case "island": focus = .appearance', links)
        self.assertIn('case "appearance", "chatlist": focus = .chatList', links)

    def test_link_downloader_bounds_untrusted_responses_and_batches(self):
        fetcher = read('submodules/BananaLinkDownloader/Sources/BananaMediaFetcher.swift')
        job = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadJob.swift')
        error = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadError.swift')
        self.assertIn('private static let maxPageBytes: Int64 = 16 * 1024 * 1024', fetcher)
        self.assertIn('maxBytes: Self.maxPageBytes', fetcher)
        self.assertNotIn('session.dataTask(with:', fetcher)
        self.assertIn('public static let maxBatchSize: Int64 = 500 * 1024 * 1024', job)
        self.assertIn('bananaWouldExceedByteLimit(total: aggregate, adding: received, limit: BananaLinkDownloadJob.maxBatchSize)', job)
        self.assertIn('case batchTooLarge', error)
        self.assertIn('case pageTooLarge', error)
        self.assertIn('error.localizedReason(russian: ForkPresentationLanguage.prefersRussianStrings)', read('submodules/TelegramUI/Sources/ChatController+BananaLinkDownload.swift'))

    def test_static_method_fixture_extraction_stops_at_method_boundary(self):
        tiktok = static_method(read('submodules/BananaLinkDownloader/Sources/BananaTikTokExtractor.swift'), 'parsePage')
        youtube = static_method(read('submodules/BananaLinkDownloader/Sources/BananaYouTubeShortsExtractor.swift'), 'pickVideo')
        self.assertIn('static func parsePage', tiktok)
        self.assertIn('static func pickVideo', youtube)
        self.assertNotIn('func resolve', tiktok)
        self.assertNotIn('func pickAudio', youtube)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_link_downloader_error_localization(self):
        errors = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadError.swift')
        execute(errors + '''
precondition(BananaLinkDownloadError.tooLarge.localizedReason(russian: true) == "Файл больше 200 МБ")
precondition(BananaLinkDownloadError.tooLarge.localizedReason(russian: false) == "A media file exceeds 200 MB")
precondition(BananaLinkDownloadError.batchTooLarge.localizedReason(russian: false).contains("500 MB"))
precondition(BananaLinkDownloadError.youtubeLoginRequired.localizedReason(russian: true).contains("YouTube"))
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_link_downloader_byte_budget_helper(self):
        source = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadModels.swift')
        execute('import Foundation\n' + function(source, 'bananaWouldExceedByteLimit') + '''
let limit: Int64 = 500 * 1024 * 1024
precondition(!bananaWouldExceedByteLimit(total: 0, adding: limit, limit: limit))
precondition(bananaWouldExceedByteLimit(total: limit, adding: 1, limit: limit))
precondition(bananaWouldExceedByteLimit(total: Int64.max, adding: 1, limit: Int64.max))
precondition(bananaWouldExceedByteLimit(total: -1, adding: 0, limit: limit))
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_tiktok_page_parser(self):
        models = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadModels.swift')
        remote_file = models[models.index('struct BananaRemoteFile'):models.index('\n}', models.index('struct BananaRemoteFile')) + 2]
        parser = read('submodules/BananaLinkDownloader/Sources/BananaTikTokExtractor.swift')
        errors = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadError.swift')
        execute('''import Foundation
import CoreFoundation
''' + remote_file + '\n' + function(models, 'bananaIntValue') + '\n' + errors + '\n' + read('submodules/BananaLinkDownloader/Sources/BananaMediaURLPolicy.swift') + '''
enum BananaTikTokItem: Equatable {
    case video(BananaRemoteFile, Double)
    case photos([BananaRemoteFile])
}
enum BananaTikTokExtractor {
    static let rehydrationMarker = "<script id=\\\"__UNIVERSAL_DATA_FOR_REHYDRATION__\\\""
''' + static_method(parser, 'parsePage') + '''
}
func page(status: Int, item: [String: Any]?) -> String {
    var detail: [String: Any] = ["statusCode": status]
    if let item { detail["itemInfo"] = ["itemStruct": item] }
    let root: [String: Any] = ["__DEFAULT_SCOPE__": ["webapp.video-detail": detail]]
    let data = try! JSONSerialization.data(withJSONObject: root)
    return "<script id=\\\"__UNIVERSAL_DATA_FOR_REHYDRATION__\\\">" + String(decoding: data, as: UTF8.self) + "</script>"
}
let item: [String: Any] = [
    "video": ["duration": "24", "bitrateInfo": [
        ["CodecType": "h265", "Bitrate": 9000, "PlayAddr": ["UrlList": ["https://cdn.mediahost.com/hevc.mp4"]]],
        ["CodecType": "h264", "Bitrate": 900, "PlayAddr": ["UrlList": ["https://cdn.mediahost.com/low.mp4"], "DataSize": "100", "Width": 720, "Height": 1280]],
        ["CodecType": "H264", "Bitrate": 1800, "PlayAddr": ["UrlList": ["https://cdn.mediahost.com/high.mp4"], "DataSize": "200", "Width": 1080, "Height": 1920]]
    ]]
]
switch BananaTikTokExtractor.parsePage(page(status: 0, item: item)) {
case let .success(.video(file, duration)):
    precondition(file.url.absoluteString == "https://cdn.mediahost.com/high.mp4")
    precondition(file.expectedSize == 200 && file.width == 1080 && file.height == 1920 && duration == 24)
default: preconditionFailure("expected highest-bitrate H.264 video")
}
let photos: [String: Any] = ["imagePost": ["images": [["imageURL": ["urlList": ["https://cdn.mediahost.com/photo.jpg"]], "imageWidth": "1200", "imageHeight": 800]]]]
switch BananaTikTokExtractor.parsePage(page(status: 0, item: photos)) {
case let .success(.photos(files)):
    precondition(files.count == 1 && files[0].width == 1200 && files[0].height == 800)
default: preconditionFailure("expected photo carousel")
}
if case .failure(.tiktokPrivate) = BananaTikTokExtractor.parsePage(page(status: 10222, item: nil)) {} else { preconditionFailure("private status") }
if case .failure(.tiktokNotFound) = BananaTikTokExtractor.parsePage(page(status: 10204, item: nil)) {} else { preconditionFailure("not-found status") }
if case .failure(.tiktokNoData) = BananaTikTokExtractor.parsePage("<html>challenge</html>") {} else { preconditionFailure("challenge page") }
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_youtube_player_selection(self):
        models = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadModels.swift')
        remote_file = models[models.index('struct BananaRemoteFile'):models.index('\n}', models.index('struct BananaRemoteFile')) + 2]
        parser = read('submodules/BananaLinkDownloader/Sources/BananaYouTubeShortsExtractor.swift')
        errors = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadError.swift')
        methods = '\n'.join(static_method(parser, name) for name in ['parsePlayerResponse', 'pickVideo', 'pickAudio'])
        execute('''import Foundation
import CoreFoundation
''' + remote_file + '\n' + function(models, 'bananaIntValue') + '\n' + errors + '\n' + read('submodules/BananaLinkDownloader/Sources/BananaMediaURLPolicy.swift') + '''
struct BananaYouTubeClient: Equatable { let name: String }
enum BananaYouTubeStreams: Equatable {
    case adaptive(BananaRemoteFile, BananaRemoteFile)
    case progressive(BananaRemoteFile)
}
struct BananaYouTubeShort {
    let streams: BananaYouTubeStreams
    let duration: Double
    let client: BananaYouTubeClient
}
enum BananaYouTubeShortsExtractor {
    static let maxDuration: Double = 180.0
''' + methods + '''
}
let client = BananaYouTubeClient(name: "fixture")
func response(_ videoId: String = "abcdefghijk", _ duration: String = "30", _ formats: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "playabilityStatus": ["status": "OK"],
        "videoDetails": ["videoId": videoId, "lengthSeconds": duration],
        "streamingData": ["adaptiveFormats": formats]
    ])
}
let formats: [[String: Any]] = [
    ["mimeType": "video/mp4; codecs=\\\"avc1.640028\\\"", "url": "https://cdn.mediahost.com/720.mp4", "width": 1280, "height": 720, "bitrate": 900],
    ["mimeType": "video/mp4; codecs=\\\"avc1.640028\\\"", "url": "https://cdn.mediahost.com/1080.mp4", "width": 1920, "height": 1080, "bitrate": 1800],
    ["mimeType": "video/mp4; codecs=\\\"hev1\\\"", "url": "https://cdn.mediahost.com/hevc.mp4", "width": 3840, "height": 2160, "bitrate": 9900],
    ["mimeType": "audio/mp4; codecs=\\\"mp4a.40.2\\\"", "url": "https://cdn.mediahost.com/dub.mp4", "bitrate": 9999, "audioTrack": ["isAutoDubbed": true, "audioIsDefault": true]],
    ["mimeType": "audio/mp4; codecs=\\\"mp4a.40.2\\\"", "url": "https://cdn.mediahost.com/drc.mp4", "bitrate": 9998, "isDrc": true, "audioTrack": ["audioIsDefault": true]],
    ["mimeType": "audio/mp4; codecs=\\\"mp4a.40.2\\\"", "url": "https://cdn.mediahost.com/original-low.mp4", "bitrate": 128, "audioTrack": ["audioIsDefault": true]],
    ["mimeType": "audio/mp4; codecs=\\\"mp4a.40.2\\\"", "url": "https://cdn.mediahost.com/original-high.mp4", "bitrate": 256, "audioTrack": ["audioIsDefault": true]],
    ["mimeType": "audio/mp4; codecs=\\\"mp4a.40.2\\\"", "url": "https://cdn.mediahost.com/non-default.mp4", "bitrate": 512]
]
switch BananaYouTubeShortsExtractor.parsePlayerResponse(response("abcdefghijk", "30", formats), videoId: "abcdefghijk", client: client) {
case let .success(short):
    guard case let .adaptive(video, audio) = short.streams else { preconditionFailure("expected adaptive streams") }
    precondition(video.url.absoluteString == "https://cdn.mediahost.com/1080.mp4" && video.expectedSize == nil)
    precondition(audio.url.absoluteString == "https://cdn.mediahost.com/original-high.mp4")
    precondition(short.duration == 30 && short.client == client)
default: preconditionFailure("expected selected video and original-language audio")
}
if case .failure(.youtubeUnavailable) = BananaYouTubeShortsExtractor.parsePlayerResponse(response("differentid", "30", formats), videoId: "abcdefghijk", client: client) {} else { preconditionFailure("video ID mismatch") }
if case .failure(.youtubeTooLong) = BananaYouTubeShortsExtractor.parsePlayerResponse(response("abcdefghijk", "181", formats), videoId: "abcdefghijk", client: client) {} else { preconditionFailure("long video") }
let progressive: [[String: Any]] = [["mimeType": "video/mp4; codecs=\\\"avc1.640028\\\"", "url": "https://cdn.mediahost.com/progressive.mp4", "width": 720, "height": 1280, "bitrate": 500]]
let progressiveData = try! JSONSerialization.data(withJSONObject: ["playabilityStatus": ["status": "OK"], "videoDetails": ["videoId": "abcdefghijk", "lengthSeconds": "30"], "streamingData": ["formats": progressive]])
if case let .success(short) = BananaYouTubeShortsExtractor.parsePlayerResponse(progressiveData, videoId: "abcdefghijk", client: client) {
    guard case let .progressive(file) = short.streams else { preconditionFailure("expected progressive fallback") }
    precondition(file.url.absoluteString == "https://cdn.mediahost.com/progressive.mp4")
} else { preconditionFailure("expected progressive fallback") }
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_search_filters_and_remote_window(self):
        production = read('submodules/TelegramCore/Sources/MessageSaving/MessageSavingSearch.swift')
        code = 'import Foundation\n' + '''
public struct PeerId: Hashable { let namespace: Int32; let value: Int }
public struct MessageId: Hashable { let peerId: PeerId; let namespace: Int32; let id: Int }
public struct MessageTags: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue } }
struct LocalMessageTags { static let bananaDeleted = Self() }
enum Namespaces { enum Message { static let Cloud: Int32 = 0 } }
struct Author { let id: PeerId }
struct Media { let indexableText: String? }
enum MessageReaction { typealias Reaction = Int }
struct Reaction { let value: Int }
class ReactionsMessageAttribute { let reactions: [Reaction]; init(_ reactions: [Int]) { self.reactions = reactions.map { Reaction(value: $0) } } }
public struct Message { let id: MessageId; let author: Author?; let tags: MessageTags; let threadId: Int64?; let timestamp: Int32; let text: String; let media: [Media]; let attributes: [Any]; var index: Int { Int(timestamp) } }
class Transaction { let messages: [Message]; init(_ messages: [Message]) { self.messages = messages }; func getMessagesWithLocalTag(_ tag: LocalMessageTags, peerId: PeerId) -> [Message] { messages.filter { $0.id.peerId == peerId } } }
public struct SearchMessagesResult { let messages: [Message]; let readStates: [Int: Int]; let threadInfo: [Int: Int]; let totalCount: Int32; let completed: Bool }
''' + '\n'.join(function(production, name) for name in ['bananaDeletedMessageMatchesQuery','bananaDeletedMessages','bananaSearchResultIncludingDeletedMessages']) + '''
let peer = PeerId(namespace: 0, value: 1), other = PeerId(namespace: 0, value: 2)
func message(_ id: Int, _ time: Int32, peerId: PeerId = peer, author: PeerId = peer, topic: Int64? = 5, namespace: Int32 = 0) -> Message {
 Message(id: MessageId(peerId: peerId, namespace: namespace, id: id), author: Author(id: author), tags: MessageTags(rawValue: 1), threadId: topic, timestamp: time, text: "Café report", media: [Media(indexableText: "annual_budget.pdf")], attributes: [ReactionsMessageAttribute([7])])
}
let a = message(10, 100), b = message(20, 200), c = message(30, 300)
let transaction = Transaction([a, b, c, message(40, 400, peerId: other), message(50, 500, namespace: 1)])
precondition(bananaDeletedMessageMatchesQuery(text: "Café annual_budget.PDF", query: "cafe bud"))
precondition(!bananaDeletedMessageMatchesQuery(text: "Café annual_budget.PDF", query: "unknown"))
precondition(bananaDeletedMessages(transaction: transaction, peerId: peer, query: "bud", fromId: peer, tags: MessageTags(rawValue: 1), reactions: [7], threadId: 5, minDate: 150, maxDate: 250).map { $0.id } == [b.id])
precondition(bananaDeletedMessages(transaction: transaction, peerId: peer, fromId: other).isEmpty)
precondition(bananaDeletedMessages(transaction: transaction, peerId: peer, reactions: [8]).isEmpty)
precondition(bananaDeletedMessages(transaction: transaction, peerId: peer, threadId: 6).isEmpty)
precondition(bananaDeletedMessages(transaction: transaction, peerId: peer, tags: MessageTags(rawValue: 2)).isEmpty)
let remote = SearchMessagesResult(messages: [c, b], readStates: [:], threadInfo: [:], totalCount: 5, completed: false)
let merged = bananaSearchResultIncludingDeletedMessages(remote, deletedMessages: [a, b, b])
precondition(merged.messages.map { $0.id } == [c.id, b.id] && merged.totalCount == 6 && !merged.completed)
let completed = SearchMessagesResult(messages: [c, b], readStates: [:], threadInfo: [:], totalCount: 5, completed: true)
precondition(bananaSearchResultIncludingDeletedMessages(completed, deletedMessages: [a, b, b]).messages.map { $0.id } == [c.id, b.id, a.id])
precondition(remote.messages.map { $0.id } == [c.id, b.id])
'''
        execute(code)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_actual_schedule_policy(self):
        production = read('submodules/TelegramCore/Sources/Arena/BananaGhostPrivacy.swift')
        execute('''import Foundation
struct PeerId { struct Namespace: Equatable { let rawValue: Int32 } }
enum Namespaces { enum Peer { static let SecretChat = PeerId.Namespace(rawValue: 3) } }
enum ForkGhostScheduleSettings { static var enabled = false }
enum ForkGhostModeSettings { static var suppressMessageReads = false; static var suppressStoryViews = false; static var suppressOutgoingActivity = false; static var suppressOnline = false; static var goOfflineAutomatically = false }
''' + function(production, 'bananaGhostScheduleAllowed') + '''
for flags in 0..<512 {
 func bit(_ index: Int) -> Bool { flags & (1 << index) != 0 }
 ForkGhostScheduleSettings.enabled = bit(0)
 ForkGhostModeSettings.suppressMessageReads = bit(1)
 ForkGhostModeSettings.suppressStoryViews = bit(2)
 ForkGhostModeSettings.suppressOutgoingActivity = bit(3)
 ForkGhostModeSettings.suppressOnline = bit(4)
 ForkGhostModeSettings.goOfflineAutomatically = bit(5)
 let result = bananaGhostScheduleAllowed(peerNamespace: PeerId.Namespace(rawValue: bit(6) ? 3 : 0), hasUserSchedule: bit(7), isQuickReply: bit(8))
 precondition(result == (flags == 63))
}
''')

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_parse_modified_ui_and_core(self):
        paths = [
            'submodules/WebUI/Sources/WebAppController.swift',
            'submodules/WebUI/Sources/WebAppWebView.swift',
            'submodules/BrowserUI/Sources/BrowserWebContent.swift',
            'submodules/TelegramCore/Sources/TelegramEngine/Messages/SparseMessageList.swift',
            'submodules/TelegramCore/Sources/TelegramEngine/Messages/DeleteMessages.swift',
            'submodules/TelegramUI/Sources/SharedAccountContext.swift',
            'submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/OpenStories.swift',
            'submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/StoryItemContentComponent.swift',
            'submodules/SettingsUI/Sources/ForkExtrasController.swift',
            'Telegram/NotificationService/Sources/NotificationService.swift',
        ]
        for path in paths:
            subprocess.run(['swiftc', '-frontend', '-parse', str(ROOT/path)], check=True, timeout=120)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable locally; executes in macOS CI')
    def test_link_downloader_url_policy_rejects_local_and_insecure_targets(self):
        execute('import Foundation\n' + read('submodules/BananaLinkDownloader/Sources/BananaMediaURLPolicy.swift') + '''
func ok(_ s: String) -> Bool { BananaMediaURLPolicy.isAllowed(URL(string: s)!) }
precondition(ok("https://v16-webapp.tiktokcdn.com/path/video.mp4?x=1"))
precondition(ok("https://rr3---sn-abc.googlevideo.com/videoplayback?id=1"))
precondition(ok("https://www.tiktok.com:443/@/video/1"))
for bad in ["http://v16.tiktokcdn.com/a", "file:///private/var/mobile/a", "ftp://cdn.mediahost.com/a",
            "https://127.0.0.1/a", "https://localhost/a", "https://printer.local/a", "https://192.168.1.1/a",
            "https://2130706433/a", "https://0x7f.1/a", "https://127.1/a", "https://[::1]/a", "https://[fe80::1%25en0]/a",
            "https://intranet/a", "https://nas.lan/a", "https://cdn.mediahost.com:8443/a", "https://user:pw@cdn.mediahost.com/a",
            "https://cdn.mediahost.com@evil.test/a", "https://-bad.mediahost.com/a", "https://a..b.com/a", "https://exa mple.com/a"] {
    if let url = URL(string: bad) { precondition(!BananaMediaURLPolicy.isAllowed(url), bad) }
}
precondition(BananaMediaURLPolicy.firstAllowedURL(in: ["http://x.test/a", 5, "https://cdn.mediahost.com/ok"])?.absoluteString == "https://cdn.mediahost.com/ok")
precondition(BananaMediaURLPolicy.firstAllowedURL(in: ["file:///etc/passwd"]) == nil)
precondition(BananaMediaURLPolicy.allowedURL(nil) == nil && BananaMediaURLPolicy.allowedURL("") == nil)
''')

    def test_link_downloader_applies_the_url_policy_everywhere(self):
        fetcher = read('submodules/BananaLinkDownloader/Sources/BananaMediaFetcher.swift')
        self.assertIn('guard let requestURL = request.url, BananaMediaURLPolicy.isAllowed(requestURL) else {', fetcher)
        self.assertIn('willPerformHTTPRedirection', fetcher)
        self.assertIn('completionHandler(nil)', fetcher)
        for name in ['BananaTikTokExtractor', 'BananaYouTubeShortsExtractor']:
            text = read('submodules/BananaLinkDownloader/Sources/%s.swift' % name)
            self.assertNotIn('URL(string: first)', text)
            self.assertNotIn('URL(string: urlString)', text)
            self.assertIn('BananaMediaURLPolicy.', text)
        job = read('submodules/BananaLinkDownloader/Sources/BananaLinkDownloadJob.swift')
        self.assertIn('static let maxCarouselPhotos = 40', job)


if __name__ == '__main__': unittest.main()
