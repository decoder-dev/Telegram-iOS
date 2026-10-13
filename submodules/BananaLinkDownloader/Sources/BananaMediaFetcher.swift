import Foundation

/// Body and final URL (after redirects) of a successful 2xx request.
struct BananaHTTPResponse {
    let data: Data
    let url: URL?
}

/// One URLSession per job: keeps TikTok cookies between the page and the CDN, reports download progress,
/// enforces the size limit and cancels everything at once. Same pattern as WebUI's FileDownload.
final class BananaMediaFetcher: NSObject, URLSessionDownloadDelegate {
    private final class Download {
        let destination: URL
        let maxBytes: Int64
        let progress: (Int64, Int64?) -> Void
        let completion: (Result<URL, BananaLinkDownloadError>) -> Void
        var failure: BananaLinkDownloadError?
        var isMoved = false

        init(destination: URL, maxBytes: Int64, progress: @escaping (Int64, Int64?) -> Void, completion: @escaping (Result<URL, BananaLinkDownloadError>) -> Void) {
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
        self.queue.async {
            guard !self.isCancelled, let session = self.session else {
                completion(.failure(.cancelled))
                return
            }
            let task = session.dataTask(with: request, completionHandler: { data, response, error in
                if let error {
                    completion(.failure(BananaLinkDownloadError(error)))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(.httpStatus(0)))
                    return
                }
                guard (200 ..< 300).contains(httpResponse.statusCode) else {
                    completion(.failure(.httpStatus(httpResponse.statusCode)))
                    return
                }
                completion(.success(BananaHTTPResponse(data: data ?? Data(), url: httpResponse.url)))
            })
            self.tasks.append(task)
            task.resume()
        }
    }

    func download(_ request: URLRequest, to destination: URL, maxBytes: Int64, progress: @escaping (Int64, Int64?) -> Void, completion: @escaping (Result<URL, BananaLinkDownloadError>) -> Void) {
        self.queue.async {
            guard !self.isCancelled, let session = self.session else {
                completion(.failure(.cancelled))
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
        if let httpResponse = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(httpResponse.statusCode) {
            download.failure = .httpStatus(httpResponse.statusCode)
            return
        }
        do {
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
            download.completion(.failure(failure))
        } else if let error {
            download.completion(.failure(BananaLinkDownloadError(error)))
        } else if download.isMoved {
            download.completion(.success(download.destination))
        } else {
            download.completion(.failure(.processingFailed))
        }
    }
}
