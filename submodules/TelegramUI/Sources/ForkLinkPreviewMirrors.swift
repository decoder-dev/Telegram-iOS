import Foundation

/// Regram "fix link previews" (Extras ▸ Media ▸ Links and media). Sites that serve Telegram's preview fetcher
/// nothing useful get their preview requested from an embed-friendly mirror instead. Only the preview request
/// is rewritten: the message keeps the link exactly as typed. Rules are Regram's built-in defaults
/// (`RGLinkMetadata.defaultPagePreviewDomains` / `RGLinkPreviewRules`), without its remote rule feed.
enum ForkLinkPreviewMirrors {
    /// Exact host -> mirror host.
    static let mirrorHosts: [String: String] = [
        "x.com": "fixupx.com",
        "www.x.com": "fixupx.com",
        "twitter.com": "fxtwitter.com",
        "www.twitter.com": "fxtwitter.com",
        "instagram.com": "ddinstagram.com",
        "www.instagram.com": "ddinstagram.com",
        "vm.tiktok.com": "vm.vxtiktok.com",
        "www.reddit.com": "www.vxreddit.com",
        "bsky.app": "fxbsky.app",
        "www.pixiv.net": "www.phixiv.net"
    ]

    /// The URL to ask for a preview of, or `url` itself when no rule applies. Query and fragment are dropped
    /// from a rewritten URL (tracking parameters only confuse the mirrors); credentials and non-web schemes
    /// are never rewritten.
    static func previewUrl(_ url: String) -> String {
        let qualified = url.range(of: "://") == nil ? "https://" + url : url
        guard var components = URLComponents(string: qualified),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(),
              let mirror = mirrorHosts[host] else {
            return url
        }
        components.scheme = "https"
        components.host = mirror
        components.port = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? url
    }
}
