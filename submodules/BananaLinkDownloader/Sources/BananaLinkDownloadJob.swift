import Foundation
import AVFoundation

/// Downloads one TikTok / YouTube Shorts link into files ready to send. Works on its own queue, keeps itself
/// alive until it finishes (so it survives the chat being closed) and reports on the main queue.
public final class BananaLinkDownloadJob {
    public enum ContentKind: Equatable {
        case video
        case photos
    }

    public enum Stage: Equatable {
        case resolving
        case downloading(received: Int64, total: Int64?)
        case processing
    }

    public struct Status: Equatable {
        public let kind: ContentKind?
        public let stage: Stage
    }

    public struct Video {
        public let fileURL: URL
        public let fileName: String
        public let fileSize: Int64
        public let width: Int
        public let height: Int
        public let duration: Double
        public let thumbnail: BananaJPEGImage?
    }

    public struct Photo {
        public let fileURL: URL
        public let fileSize: Int64
        public let width: Int
        public let height: Int
    }

    public enum Output {
        case video(Video)
        case photos([Photo])
    }

    public static let maxFileSize: Int64 = 200 * 1024 * 1024
    /// Caps the combined temporary footprint of a multi-file post while allowing adaptive video + audio.
    public static let maxBatchSize: Int64 = 500 * 1024 * 1024
    static let maxCarouselPhotos = 40

    /// Progress of a group of parallel downloads (the video and audio of a Short, the photos of a carousel).
    private final class Batch {
        var received: [Int64]
        var expected: [Int64?]
        var results: [URL?]
        var remaining: Int
        var nextIndex = 0
        var active = 0
        var failed = false

        init(expected: [Int64?]) {
            self.received = Array(repeating: 0, count: expected.count)
            self.expected = expected
            self.results = Array(repeating: nil, count: expected.count)
            self.remaining = expected.count
        }
    }

    public let link: BananaLinkDownloadLink
    private let maxPhotos: Int?
    private let queue = DispatchQueue(label: "org.bananagram.linkdownloader.job")
    private let fetcher = BananaMediaFetcher()
    private let workDirectory: URL
    private var statusHandler: ((Status) -> Void)?
    private var completion: ((Result<Output, BananaLinkDownloadError>) -> Void)?
    private var retainedSelf: BananaLinkDownloadJob?
    private var kind: ContentKind?
    private var lastStage: Stage?
    private var lastReportTime: CFAbsoluteTime = 0.0
    private var exportSession: AVAssetExportSession?
    private var isFinished = false
    private let cancelLock = NSLock()
    private var cancelRequested = false

    /// Set synchronously by `cancel()`; read on the job queue and again at delivery on the main queue.
    private var isCancelRequested: Bool {
        self.cancelLock.lock()
        defer {
            self.cancelLock.unlock()
        }
        return self.cancelRequested
    }

    public init(link: BananaLinkDownloadLink, maxPhotos: Int? = nil) {
        self.link = link
        self.maxPhotos = maxPhotos
        self.workDirectory = BananaLinkDownloadJob.rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    public func start(status: @escaping (Status) -> Void, completion: @escaping (Result<Output, BananaLinkDownloadError>) -> Void) {
        self.queue.async {
            self.retainedSelf = self
            self.statusHandler = status
            self.completion = completion
            BananaLinkDownloadJob.removeStaleDirectories()
            do {
                try FileManager.default.createDirectory(at: self.workDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                self.finish(.failure(.processingFailed))
                return
            }
            switch self.link {
            case let .tiktok(url):
                self.report(.resolving)
                self.runTikTok(url)
            case let .youtubeShorts(videoId, _):
                self.kind = .video
                self.report(.resolving)
                self.runYouTube(videoId)
            }
        }
    }

    /// Once `cancel()` returns, `completion` receives `.failure(.cancelled)` unless it has already run: a success
    /// that is still being processed or is on its way to the main queue is converted and its files are removed.
    public func cancel() {
        self.cancelLock.lock()
        self.cancelRequested = true
        self.cancelLock.unlock()
        self.queue.async {
            self.exportSession?.cancelExport()
            self.finish(.failure(.cancelled))
        }
    }

    /// TikTok's own page first, TikWM after it: `BananaTikTokExtractor.run` decides when and names both errors.
    private func runTikTok(_ url: URL) {
        BananaTikTokExtractor.run(url, fetcher: self.fetcher, willUseFallback: {
            self.queue.async {
                self.report(.resolving)
            }
        }, download: { item, failure in
            self.queue.async {
                guard !self.isFinished else {
                    return
                }
                self.downloadTikTok(item, failure: failure)
            }
        }, failure: { error in
            self.queue.async {
                self.finish(.failure(error))
            }
        })
    }

    /// `failure` hands the error back to the extractor, which may try TikWM next.
    private func downloadTikTok(_ item: BananaTikTokItem, failure: @escaping (BananaLinkDownloadError) -> Void) {
        // Each attempt has its own folder: old photo tasks may still be finishing when another source is tried.
        let directory = self.workDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            self.finish(.failure(.processingFailed))
            return
        }
        let failed: (BananaLinkDownloadError) -> Void = { error in
            // cancel() is synchronous: a job that is being cancelled asks no other source.
            if self.isCancelRequested {
                self.finish(.failure(.cancelled))
            } else {
                // A failed attempt's files are never sent, and a success keeps the work folder, so they go now: a page
                // saved as the video, the photos made so far. A task still running cannot move its file in any more.
                try? FileManager.default.removeItem(at: directory)
                failure(error)
            }
        }
        switch item {
        case let .video(file, _):
            self.kind = .video
            let destination = directory.appendingPathComponent("tiktok.mp4")
            self.download([(BananaTikTokExtractor.mediaRequest(file.url), destination, file.expectedSize)], alternatives: [file.alternateURLs.map(BananaTikTokExtractor.mediaRequest)], failure: failed, completion: { urls in
                self.completeVideo(fileURL: urls[0], failure: failed)
            })
        case let .photos(files):
            self.kind = .photos
            var selected = files
            let limit = min(self.maxPhotos ?? Self.maxCarouselPhotos, Self.maxCarouselPhotos)
            if selected.count > limit { selected = Array(selected.prefix(limit)) }
            let items = selected.enumerated().map { index, file in
                return (BananaTikTokExtractor.mediaRequest(file.url), directory.appendingPathComponent("source-\(index)"), file.expectedSize)
            }
            self.download(items, failure: failed, completion: { urls in
                self.completePhotos(urls, failure: failed)
            })
        }
    }

    private func runYouTube(_ videoId: String) {
        BananaYouTubeShortsExtractor.resolve(videoId: videoId, fetcher: self.fetcher, completion: { result in
            self.queue.async {
                guard !self.isFinished else {
                    return
                }
                switch result {
                case let .failure(error):
                    self.finish(.failure(error))
                case let .success(short):
                    let output = self.workDirectory.appendingPathComponent("shorts-\(videoId).mp4")
                    switch short.streams {
                    case let .progressive(file):
                        self.download([(short.client.mediaRequest(file.url), output, file.expectedSize)], completion: { urls in
                            self.completeVideo(fileURL: urls[0])
                        })
                    case let .adaptive(video, audio):
                        let videoPath = self.workDirectory.appendingPathComponent("video.mp4")
                        let audioPath = self.workDirectory.appendingPathComponent("audio.m4a")
                        self.download([
                            (short.client.mediaRequest(video.url), videoPath, video.expectedSize),
                            (short.client.mediaRequest(audio.url), audioPath, audio.expectedSize)
                        ], completion: { urls in
                            self.report(.processing)
                            self.exportSession = BananaMediaProcessor.mux(videoURL: urls[0], audioURL: urls[1], outputURL: output, completion: { muxResult in
                                self.queue.async {
                                    self.exportSession = nil
                                    try? FileManager.default.removeItem(at: urls[0])
                                    try? FileManager.default.removeItem(at: urls[1])
                                    guard !self.isFinished else {
                                        return
                                    }
                                    switch muxResult {
                                    case let .failure(error):
                                        self.finish(.failure(error))
                                    case .success:
                                        self.completeVideo(fileURL: output)
                                    }
                                }
                            })
                        })
                    }
                }
            }
        })
    }

    /// Up to three parallel downloads; `completion` gets the files in the order of `items`.
    private func download(_ items: [(URLRequest, URL, Int64?)], alternatives: [[URLRequest]] = [], failure: ((BananaLinkDownloadError) -> Void)? = nil, completion: @escaping ([URL]) -> Void) {
        let batch = Batch(expected: items.map { $0.2 })
        self.reportBatch(batch)
        self.startNext(items, alternatives: alternatives, batch: batch, failure: failure, completion: completion)
    }

    private func startNext(_ items: [(URLRequest, URL, Int64?)], alternatives: [[URLRequest]], batch: Batch, failure: ((BananaLinkDownloadError) -> Void)?, completion: @escaping ([URL]) -> Void) {
        while batch.active < 3 && batch.nextIndex < items.count {
            let index = batch.nextIndex
            batch.nextIndex += 1
            batch.active += 1
            let (request, destination, _) = items[index]
            self.fetcher.download(request, alternatives: index < alternatives.count ? alternatives[index] : [], to: destination, maxBytes: BananaLinkDownloadJob.maxFileSize, progress: { written, total in
                self.queue.async {
                    guard !batch.failed, !self.isFinished else { return }
                    batch.received[index] = written
                    var aggregate: Int64 = 0
                    for received in batch.received {
                        if bananaWouldExceedByteLimit(total: aggregate, adding: received, limit: BananaLinkDownloadJob.maxBatchSize) {
                            self.finish(.failure(.batchTooLarge))
                            return
                        }
                        aggregate += received
                    }
                    if let total {
                        batch.expected[index] = total
                    }
                    self.reportBatch(batch)
                }
            }, completion: { result in
                self.queue.async {
                    guard !self.isFinished, !batch.failed else {
                        return
                    }
                    batch.active -= 1
                    switch result {
                    case let .failure(error):
                        batch.failed = true
                        if let failure {
                            failure(error)
                        } else {
                            self.finish(.failure(error))
                        }
                    case let .success(url):
                        batch.received[index] = BananaLinkDownloadJob.fileSize(url)
                        var aggregate: Int64 = 0
                        for received in batch.received {
                            if bananaWouldExceedByteLimit(total: aggregate, adding: received, limit: BananaLinkDownloadJob.maxBatchSize) {
                                self.finish(.failure(.batchTooLarge))
                                return
                            }
                            aggregate += received
                        }
                        batch.results[index] = url
                        batch.remaining -= 1
                        if batch.remaining == 0 {
                            completion(batch.results.compactMap { $0 })
                        } else {
                            self.startNext(items, alternatives: alternatives, batch: batch, failure: failure, completion: completion)
                        }
                    }
                }
            })
        }
    }

    private func reportBatch(_ batch: Batch) {
        let received = batch.received.reduce(0, { $0 &+ $1 })
        let total: Int64? = batch.expected.contains(where: { $0 == nil }) ? nil : batch.expected.reduce(0, { $0 &+ ($1 ?? 0) })
        self.report(.downloading(received: received, total: total))
    }

    private func completeVideo(fileURL: URL, failure: ((BananaLinkDownloadError) -> Void)? = nil) {
        self.report(.processing)
        // No video track means the server sent something else (e.g. an HTML page): send the link instead.
        guard let info = BananaMediaProcessor.videoInfo(fileURL) else {
            if let failure { failure(.processingFailed) } else { self.finish(.failure(.processingFailed)) }
            return
        }
        guard BananaLinkDownloadJob.fileSize(fileURL) <= BananaLinkDownloadJob.maxFileSize else {
            self.finish(.failure(.tooLarge))
            return
        }
        let video = Video(
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent,
            fileSize: BananaLinkDownloadJob.fileSize(fileURL),
            width: info.width,
            height: info.height,
            duration: info.duration,
            thumbnail: BananaMediaProcessor.thumbnail(videoURL: fileURL)
        )
        self.finish(.success(.video(video)))
    }

    private func completePhotos(_ sources: [URL], failure: ((BananaLinkDownloadError) -> Void)? = nil) {
        self.report(.processing)
        var photos: [Photo] = []
        for (index, source) in sources.enumerated() {
            if self.isCancelRequested {
                self.finish(.failure(.cancelled))
                return
            }
            // Next to its source, in the attempt's folder, which a failed attempt removes.
            let destination = source.deletingLastPathComponent().appendingPathComponent("photo-\(index).jpg")
            guard let size = BananaMediaProcessor.normalizePhoto(sourceURL: source, destinationURL: destination) else {
                if let failure { failure(.processingFailed) } else { self.finish(.failure(.processingFailed)) }
                return
            }
            try? FileManager.default.removeItem(at: source)
            photos.append(Photo(fileURL: destination, fileSize: BananaLinkDownloadJob.fileSize(destination), width: size.width, height: size.height))
        }
        self.finish(.success(.photos(photos)))
    }

    /// Byte progress is throttled to four reports a second; stage changes always go through.
    private func report(_ stage: Stage) {
        guard !self.isFinished, let handler = self.statusHandler else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if case .downloading = stage, case .downloading? = self.lastStage, now - self.lastReportTime < 0.25 {
            return
        }
        self.lastStage = stage
        self.lastReportTime = now
        let status = Status(kind: self.kind, stage: stage)
        DispatchQueue.main.async {
            handler(status)
        }
    }

    /// Runs exactly once. On failure (or after `cancel()`) the work directory is removed; on success the result
    /// files stay, because Telegram moves them into its cache when the message is sent.
    private func finish(_ result: Result<Output, BananaLinkDownloadError>) {
        guard !self.isFinished else {
            return
        }
        self.isFinished = true
        self.fetcher.cancel()
        self.fetcher.invalidate()
        let effectiveResult: Result<Output, BananaLinkDownloadError> = self.isCancelRequested ? .failure(.cancelled) : result
        if case .failure = effectiveResult {
            try? FileManager.default.removeItem(at: self.workDirectory)
        }
        let completion = self.completion
        self.completion = nil
        self.statusHandler = nil
        self.retainedSelf = nil
        let workDirectory = self.workDirectory
        DispatchQueue.main.async {
            // cancel() may reach the main queue after this success was computed but before it is delivered.
            if case .success = effectiveResult, self.isCancelRequested {
                DispatchQueue.global(qos: .utility).async {
                    try? FileManager.default.removeItem(at: workDirectory)
                }
                completion?(.failure(.cancelled))
            } else {
                completion?(effectiveResult)
            }
        }
    }

    static var rootDirectory: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("bananagram-link-downloads", isDirectory: true)
    }

    /// Leftovers of crashed or never-sent jobs: anything older than a day.
    static func removeStaleDirectories() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: BananaLinkDownloadJob.rootDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else {
            return
        }
        let threshold = Date().addingTimeInterval(-24.0 * 60.0 * 60.0)
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            if modified < threshold {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
