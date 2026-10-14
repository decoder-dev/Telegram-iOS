import Foundation

/// Which addresses the downloader is willing to contact.
///
/// The media addresses come out of JSON that a remote service wrote, and the session that fetches them carries
/// TikTok cookies and a tiktok.com referer. Without a check a response could point the download at
/// `file://`, at plain `http://`, at a device on the local network or at a loopback port, and the
/// cookies would travel there too. Redirects are subject to the same rule.
enum BananaMediaURLPolicy {
    /// Hosts that are only ever local, whatever the resolver says.
    private static let blockedSuffixes = [".local", ".localhost", ".internal", ".lan", ".home", ".corp", ".intranet", ".arpa", ".test", ".invalid", ".example"]

    /// `https` on the default port, no embedded credentials, and a public-looking DNS name: at least two
    /// labels, a purely alphabetic top-level label (so every spelling of an IPv4 address, `127.1`,
    /// `0x7f.1` or `2130706433`, is out) and no IPv6 literal.
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              var host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard host.count <= 253, !host.contains(":"), !host.contains("%") else {
            return false
        }
        for suffix in BananaMediaURLPolicy.blockedSuffixes where host.hasSuffix(suffix) {
            return false
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }
        for label in labels {
            guard !label.isEmpty, label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-"),
                  label.unicodeScalars.allSatisfy({ ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) || $0.value == 45 || $0.value == 95 }) else {
                return false
            }
        }
        guard let tld = labels.last, tld.count >= 2, tld.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else {
            return false
        }
        return true
    }

    /// The first string of a JSON list that parses to an allowed address.
    static func firstAllowedURL(in list: [Any]?) -> URL? {
        for entry in list ?? [] {
            if let string = entry as? String, let url = URL(string: string), BananaMediaURLPolicy.isAllowed(url) {
                return url
            }
        }
        return nil
    }

    static func allowedURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), BananaMediaURLPolicy.isAllowed(url) else {
            return nil
        }
        return url
    }
}
