import Foundation

/// Body and final URL (after redirects) of a successful 2xx request.
struct BananaHTTPResponse {
    let data: Data
    let url: URL?
}

/// One URLSession per job: keeps TikTok cookies between the page and the CDN, reports download progress,
/// enforces the size limit and cancels everything at once. Same pattern as WebUI's FileDownload.
final class BananaMediaFetcher: NSObject, URLSessionDownloadDelegate {
    private struct DownloadResult {
        let fileURL: URL
        let responseURL: URL?
    }

    private final class Download {
        let destination: URL
        let maxBytes: Int64
        let progress: (Int64, Int64?) -> Void
        let completion: (Result<DownloadResult, BananaLinkDownloadError>) -> Void
        var failure: BananaLinkDownloadError?
        var isMoved = false
        var responseURL: URL?

        init(destination: URL, maxBytes: Int64, progress: @escaping (Int64, Int64?) -> Void, completion: @escaping (Result<DownloadResult, BananaLinkDownloadError>) -> Void) {
            self.destination = destination
            self.maxBytes = maxBytes
            self.progress = progress
            self.completion = completion
        }
    }

    private let queue = DispatchQueue(label: "org.bananagram.linkdownloader.fetcher")
    private var session: URLSession?
    private var tasks: [URLSessionTask] = []
    private var downloads: [Int: Download] = [:]
    private var isCancelled = false

    /// TikTok embeds JSON in HTML and YouTube returns player JSON. Keep those untrusted responses off an
    /// unbounded in-memory data task; the download delegate enforces this cap while streaming to disk.
    private static let maxPageBytes: Int64 = 16 * 1024 * 1024

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20.0
        configuration.timeoutIntervalForResource = 600.0
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = self.queue
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    func fetchData(_ request: URLRequest, completion: @escaping (Result<BananaHTTPResponse, BananaLinkDownloadError>) -> Void) {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("bananagram-page-\(UUID().uuidString)")
        self.startDownload(request, to: destination, maxBytes: Self.maxPageBytes, progress: { _, _ in }, completion: { result in
            switch result {
            case let .failure(error):
                completion(.failure(error == .tooLarge ? .pageTooLarge : error))
            case let .success(download):
                defer { try? FileManager.default.removeItem(at: download.fileURL) }
                guard let responseURL = download.responseURL,
                      let data = try? Data(contentsOf: download.fileURL) else {
                    completion(.failure(.processingFailed))
                    return
                }
                guard Int64(data.count) <= Self.maxPageBytes else {
                    completion(.failure(.pageTooLarge))
                    return
                }
                completion(.success(BananaHTTPResponse(data: data, url: responseURL)))
            }
        })
    }

    func download(_ request: URLRequest, to destination: URL, maxBytes: Int64, progress: @escaping (Int64, Int64?) -> Void, completion: @escaping (Result<URL, BananaLinkDownloadError>) -> Void) {
        self.startDownload(request, to: destination, maxBytes: maxBytes, progress: progress, completion: { result in
            completion(result.map { $0.fileURL })
        })
    }

    private func startDownload(_ request: URLRequest, to destination: URL, maxBytes: Int64, progress: @escaping (Int64, Int64?) -> Void, completion: @escaping (Result<DownloadResult, BananaLinkDownloadError>) -> Void) {
        self.queue.async {
            guard !self.isCancelled, let session = self.session else {
                completion(.failure(.cancelled))
                return
            }
            guard maxBytes > 0 else {
                completion(.failure(.tooLarge))
                return
            }
            guard let requestURL = request.url, BananaMediaURLPolicy.isAllowed(requestURL) else {
                completion(.failure(.noCompatibleFormat))
                return
            }
            let task = session.downloadTask(with: request)
            self.downloads[task.taskIdentifier] = Download(destination: destination, maxBytes: maxBytes, progress: progress, completion: completion)
            self.tasks.append(task)
            task.resume()
        }
    }

    func cancel() {
        self.queue.async {
            self.isCancelled = true
            for task in self.tasks {
                task.cancel()
            }
        }
    }

    /// Breaks the session -> delegate retain cycle. Call once, when the job is over.
    func invalidate() {
        self.queue.async {
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    /// A redirect is followed only to an address the policy accepts; anything else ends the request with the
    /// redirect response itself, which then fails as a non-2xx status. Cookies and the referer set for TikTok
    /// never reach a plain-http or local destination this way.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, BananaMediaURLPolicy.isAllowed(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let download = self.downloads[downloadTask.taskIdentifier], download.failure == nil else {
            return
        }
        let expected: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        if totalBytesWritten > download.maxBytes || (expected ?? 0) > download.maxBytes {
            download.failure = .tooLarge
            downloadTask.cancel()
            return
        }
        download.progress(totalBytesWritten, expected)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let download = self.downloads[downloadTask.taskIdentifier], download.failure == nil else {
            return
        }
        download.responseURL = downloadTask.response?.url
        if let httpResponse = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            download.failure = .httpStatus(httpResponse.statusCode)
            return
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value <= download.maxBytes else {
                download.failure = .tooLarge
                return
            }
            if FileManager.default.fileExists(atPath: download.destination.path) {
                try FileManager.default.removeItem(at: download.destination)
            }
            try FileManager.default.moveItem(at: location, to: download.destination)
            download.isMoved = true
        } catch {
            download.failure = .processingFailed
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let download = self.downloads.removeValue(forKey: task.taskIdentifier) else {
            return
        }
        if let failure = download.failure {
            if download.isMoved { try? FileManager.default.removeItem(at: download.destination) }
            download.completion(.failure(failure))
        } else if let error {
            if download.isMoved { try? FileManager.default.removeItem(at: download.destination) }
            download.completion(.failure(BananaLinkDownloadError(error)))
        } else if download.isMoved {
            download.completion(.success(DownloadResult(fileURL: download.destination, responseURL: download.responseURL)))
        } else {
            download.completion(.failure(.processingFailed))
        }
    }
}
