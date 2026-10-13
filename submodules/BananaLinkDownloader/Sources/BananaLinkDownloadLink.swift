import Foundation

/// A message whose whole text is one TikTok or YouTube Shorts link.
public enum BananaLinkDownloadLink: Equatable {
    case tiktok(url: URL)
    case youtubeShorts(videoId: String, url: URL)

    /// The link as sent (with https:// added when the user omitted the scheme).
    public var url: URL {
        switch self {
        case let .tiktok(url):
            return url
        case let .youtubeShorts(_, url):
            return url
        }
    }

    /// Mirrors `parse_link` in the Python reference.
    public static func parse(_ text: String) -> BananaLinkDownloadLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return nil
        }
        let lowercased = trimmed.lowercased()
        let candidate: String
        if lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://") {
            candidate = trimmed
        } else if trimmed.contains("://") {
            return nil
        } else {
            candidate = "https://" + trimmed
        }
        guard let url = URL(string: candidate), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        let segments = bananaPathSegments(url.path)
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            if BananaTikTokExtractor.itemId(fromPathSegments: segments) != nil {
                return .tiktok(url: url)
            }
            if (host == "vm.tiktok.com" || host == "vt.tiktok.com") && segments.count == 1 && bananaIsShortCode(segments[0]) {
                return .tiktok(url: url)
            }
            if segments.count == 2 && segments[0] == "t" && bananaIsShortCode(segments[1]) {
                return .tiktok(url: url)
            }
            return nil
        }
        if host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" {
            if segments.count == 2 && segments[0] == "shorts" && bananaIsYouTubeVideoId(segments[1]) {
                return .youtubeShorts(videoId: segments[1], url: url)
            }
        }
        return nil
    }
}
