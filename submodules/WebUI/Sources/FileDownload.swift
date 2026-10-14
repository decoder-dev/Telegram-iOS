import Foundation
import SwiftSignalKit

private final class BotDownloadRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { isAllowedBotMediaUrl($0.absoluteString) ? request : nil })
    }
}

func botDownloadProgress(received: Int64, expected: Int64) -> Double {
    guard received > 0, expected > 0 else { return 0.0 }
    return min(1.0, Double(received) / Double(expected))
}

func botDownloadReceivedBytes(fileSize: Int64, progress: Double) -> Int64 {
    guard fileSize > 0, progress.isFinite, progress > 0.0 else { return 0 }
    guard progress < 1.0 else { return fileSize }
    let bytes = Double(fileSize) * progress
    // Double(Int64.max) rounds up to 2^63, which must not be converted to Int64.
    guard bytes < Double(fileSize) else { return fileSize }
    return min(fileSize, Int64(bytes))
}

final class FileDownload: NSObject, URLSessionDownloadDelegate {
    let fileName: String
    let fileSize: Int64?
    let isMedia: Bool
    
    private var urlSession: URLSession?
    private var completion: ((URL?, Error?) -> Void)?
    private var progressHandler: ((Double) -> Void)?
    private var task: URLSessionDownloadTask?
    
    private let progressPromise = ValuePromise<Double>(0.0)
    var progressSignal: Signal<Double,  NoError> {
        return self.progressPromise.get()
    }
    
    init(from url: URL, fileName: String, fileSize: Int64?, isMedia: Bool, progressHandler: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        self.fileName = fileName
        self.fileSize = fileSize.flatMap { $0 >= 0 ? $0 : nil }
        self.isMedia = isMedia
        self.completion = completion
        self.progressHandler = progressHandler
        
        super.init()
        
        guard isAllowedBotMediaUrl(url.absoluteString) else {
            DispatchQueue.main.async { self.finish(location: nil, error: URLError(.badURL)) }
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        self.urlSession = session
        
        let downloadTask = session.downloadTask(with: url)
        self.task = downloadTask
        downloadTask.resume()
    }
    
    func cancel() {
        self.task?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { isAllowedBotMediaUrl($0.absoluteString) ? request : nil })
    }

    private func finish(location: URL?, error: Error?) {
        let completion = self.completion
        self.completion = nil
        self.progressHandler = nil
        self.task = nil
        self.urlSession?.finishTasksAndInvalidate()
        self.urlSession = nil
        completion?(location, error)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var totalBytesExpectedToWrite = totalBytesExpectedToWrite
        if totalBytesExpectedToWrite <= 0, let fileSize = self.fileSize {
            totalBytesExpectedToWrite = fileSize
        }
        let progress = botDownloadProgress(received: totalBytesWritten, expected: totalBytesExpectedToWrite)
        self.progressHandler?(progress)
        self.progressPromise.set(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode) else {
            self.finish(location: nil, error: URLError(.badServerResponse))
            return
        }
        self.finish(location: location, error: nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            self.finish(location: nil, error: error)
        } else if self.completion != nil {
            self.finish(location: nil, error: URLError(.badServerResponse))
        }
    }
    
    static func getFileSize(url: String) -> Signal<Int64?, NoError> {
        if #available(iOS 13.0, *) {
            guard isAllowedBotMediaUrl(url), let url = URL(string: url) else {
                return .single(nil)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            
            return Signal { subscriber in
                let session = URLSession(configuration: .ephemeral, delegate: BotDownloadRedirectDelegate(), delegateQueue: nil)
                let task = session.dataTask(with: request) { _, response, error in
                    defer { session.finishTasksAndInvalidate() }
                    if let _ = error {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    var fileSize: Int64?
                    if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode), let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"), let size = Int64(contentLength), size >= 0 {
                        fileSize = size
                    }
                    subscriber.putNext(fileSize)
                    subscriber.putCompletion()
                }
                task.resume()
                return ActionDisposable {
                    task.cancel()
                    session.invalidateAndCancel()
                }
            }
        } else {
            return .single(nil)
        }
    }
}
