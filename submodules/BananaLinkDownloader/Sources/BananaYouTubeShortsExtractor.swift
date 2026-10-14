import Foundation

/// Streams chosen for a Short: separate video and audio (muxed later) or one progressive MP4.
enum BananaYouTubeStreams: Equatable {
    case adaptive(BananaRemoteFile, BananaRemoteFile)
    case progressive(BananaRemoteFile)
}

/// InnerTube client identity. Only clients that return direct URLs (no signatureCipher, no "n") are used.
struct BananaYouTubeClient: Equatable {
    let clientId: String
    let userAgent: String
    let context: [String: String]

    static let ios = BananaYouTubeClient(
        clientId: "5",
        userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        context: ["clientName": "IOS", "clientVersion": "20.10.4", "deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iPhone", "osVersion": "18.3.2.22D82", "hl": "en", "gl": "US"]
    )

    static let visionOS = BananaYouTubeClient(
        clientId: "101",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        context: ["clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple", "deviceModel": "RealityDevice17,1", "osName": "visionOS", "osVersion": "26.5.23O471", "hl": "en", "gl": "US"]
    )

    var clientVersion: String {
        return self.context["clientVersion"] ?? ""
    }

    /// googlevideo URLs are fetched with the same user agent as the player request that produced them.
    func mediaRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// A resolved Short: streams, duration in seconds and the client whose URLs these are.
struct BananaYouTubeShort {
    let streams: BananaYouTubeStreams
    let duration: Double
    let client: BananaYouTubeClient
}

/// Talks to YouTube's InnerTube player API directly from the phone. Mirrors `youtube_parse_player`,
/// `youtube_pick_video` and `youtube_pick_audio` in the Python reference.
enum BananaYouTubeShortsExtractor {
    static let maxDuration: Double = 180.0

    static func playerRequest(videoId: String, client: BananaYouTubeClient) -> URLRequest? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            return nil
        }
        let body: [String: Any] = [
            "context": ["client": client.context],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        return request
    }

    static func parsePlayerResponse(_ data: Data, videoId: String, client: BananaYouTubeClient) -> Result<BananaYouTubeShort, BananaLinkDownloadError> {
        guard let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
            return .failure(.youtubeUnavailable)
        }
        let playability = (root["playabilityStatus"] as? [String: Any]) ?? [:]
        let status = (playability["status"] as? String) ?? ""
        let reason = (playability["reason"] as? String) ?? ""
        if status != "OK" {
            if status.hasPrefix("AGE_") || (status == "LOGIN_REQUIRED" && reason.range(of: "\\bage\\b", options: [.regularExpression, .caseInsensitive]) != nil) {
                return .failure(.youtubeAgeRestricted)
            }
            if status == "LOGIN_REQUIRED" {
                return .failure(.youtubeLoginRequired)
            }
            return .failure(.youtubeUnavailable)
        }
        let details = (root["videoDetails"] as? [String: Any]) ?? [:]
        guard (details["videoId"] as? String) == videoId else {
            return .failure(.youtubeUnavailable)
        }
        let duration = Double(bananaIntValue(details["lengthSeconds"]) ?? 0)
        if duration > BananaYouTubeShortsExtractor.maxDuration {
            return .failure(.youtubeTooLong)
        }
        let streaming = (root["streamingData"] as? [String: Any]) ?? [:]
        let adaptive = ((streaming["adaptiveFormats"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        if let video = BananaYouTubeShortsExtractor.pickVideo(adaptive), let audio = BananaYouTubeShortsExtractor.pickAudio(adaptive) {
            return .success(BananaYouTubeShort(streams: .adaptive(video, audio), duration: duration, client: client))
        }
        let progressive = ((streaming["formats"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        if let file = BananaYouTubeShortsExtractor.pickVideo(progressive) {
            return .success(BananaYouTubeShort(streams: .progressive(file), duration: duration, client: client))
        }
        return .failure(.noCompatibleFormat)
    }

    /// Best H.264 MP4 with a direct URL, up to 1080p on the short side, chosen by real width/height.
    /// Absurd sizes (a side over 16384) are skipped.
    static func pickVideo(_ formats: [[String: Any]]) -> BananaRemoteFile? {
        var best: (area: Int64, bitrate: Int64, file: BananaRemoteFile)?
        for format in formats {
            guard let mimeType = format["mimeType"] as? String, mimeType.hasPrefix("video/mp4"), mimeType.contains("avc1"),
                  let url = BananaMediaURLPolicy.allowedURL(format["url"] as? String) else {
                continue
            }
            let width = bananaIntValue(format["width"]) ?? 0
            let height = bananaIntValue(format["height"]) ?? 0
            if width <= 0 || height <= 0 || min(width, height) > 1080 || max(width, height) > 16384 {
                continue
            }
            let area = width * height
            let bitrate = bananaIntValue(format["bitrate"]) ?? 0
            if let current = best, (current.area, current.bitrate) >= (area, bitrate) {
                continue
            }
            best = (area, bitrate, BananaRemoteFile(url: url, expectedSize: bananaIntValue(format["contentLength"]), width: Int(width), height: Int(height)))
        }
        return best?.file
    }

    /// Original-language AAC: no auto-dubs, no "stable volume" (DRC) copies, highest bitrate.
    static func pickAudio(_ formats: [[String: Any]]) -> BananaRemoteFile? {
        var candidates: [[String: Any]] = []
        for format in formats {
            guard let mimeType = format["mimeType"] as? String, mimeType.hasPrefix("audio/mp4"), mimeType.contains("mp4a"),
                  let urlString = format["url"] as? String, !urlString.isEmpty else {
                continue
            }
            if (format["isDrc"] as? Bool) == true {
                continue
            }
            if let track = format["audioTrack"] as? [String: Any], (track["isAutoDubbed"] as? Bool) == true {
                continue
            }
            candidates.append(format)
        }
        let defaults = candidates.filter { format in
            return ((format["audioTrack"] as? [String: Any])?["audioIsDefault"] as? Bool) == true
        }
        if !defaults.isEmpty {
            candidates = defaults
        }
        var best: (bitrate: Int64, file: BananaRemoteFile)?
        for format in candidates {
            guard let url = BananaMediaURLPolicy.allowedURL(format["url"] as? String) else {
                continue
            }
            let bitrate = bananaIntValue(format["bitrate"]) ?? 0
            if let current = best, current.bitrate >= bitrate {
                continue
            }
            best = (bitrate, BananaRemoteFile(url: url, expectedSize: bananaIntValue(format["contentLength"]), width: 0, height: 0))
        }
        return best?.file
    }

    /// iOS client first; visionOS when iOS refuses. The first client's error is reported if both fail.
    static func resolve(videoId: String, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaYouTubeShort, BananaLinkDownloadError>) -> Void) {
        BananaYouTubeShortsExtractor.requestPlayer(videoId: videoId, client: .ios, fetcher: fetcher, completion: { result in
            guard case let .failure(error) = result, error != .youtubeTooLong, error != .cancelled else {
                completion(result)
                return
            }
            BananaYouTubeShortsExtractor.requestPlayer(videoId: videoId, client: .visionOS, fetcher: fetcher, completion: { fallback in
                if case .success = fallback {
                    completion(fallback)
                } else {
                    completion(.failure(error))
                }
            })
        })
    }

    private static func requestPlayer(videoId: String, client: BananaYouTubeClient, fetcher: BananaMediaFetcher, completion: @escaping (Result<BananaYouTubeShort, BananaLinkDownloadError>) -> Void) {
        guard let request = BananaYouTubeShortsExtractor.playerRequest(videoId: videoId, client: client) else {
            completion(.failure(.youtubeUnavailable))
            return
        }
        fetcher.fetchData(request, completion: { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(response):
                completion(BananaYouTubeShortsExtractor.parsePlayerResponse(response.data, videoId: videoId, client: client))
            }
        })
    }
}
