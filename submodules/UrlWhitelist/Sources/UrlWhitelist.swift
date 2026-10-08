import Foundation

private let whitelistedHosts: Set<String> = Set([
    "t.me",
    "telegram.me",
    "telegra.ph",
    "telesco.pe",
    "fragment.com"
])

public func isConcealedUrlWhitelisted(_ url: URL) -> Bool {
    if var host = url.host?.lowercased() {
        let www = "www."
        if host.hasPrefix(www) {
            host.removeFirst(www.count)
        }
        if whitelistedHosts.contains(host) {
            return true
        }
    }
    if let host = url.host?.lowercased(), host == "telegram.org" {
        let whitelistedNativePrefixes: Set<String> = Set([
            "/blog/",
            "/tour/"
        ])

        for nativePrefix in whitelistedNativePrefixes {
            if url.path.starts(with: nativePrefix) {
                return true
            }
        }
    }
    return false
}

/// Every character that may appear in a URL, unencoded.
private let urlCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")

/// The address the external-URL opener makes of `url` when that address has a login part
/// (`user[:password]@`) in front of its host, otherwise nil.
///
/// What precedes the `@` is what a reader takes for the destination: in `https://telegram.org\u{2215}test\u{2215}@evil.org`
/// the `\u{2215}` characters are not slashes, so the authority runs on to the `@`, `telegram.org\u{2215}test\u{2215}` is the
/// user name and the link opens evil.org. Opening such a link is confirmed with a prompt that shows the
/// address without the login part (`urlRemovingLoginPart`).
///
/// The scheme is supplied as the opener supplies it. Where Foundation rejects the address, the invalid
/// characters are encoded as later system versions do, which can only add a prompt.
/// `tel:` and `calshow:` links leave the opener before it parses anything, and `mailto:` ones carry no host.
public func externalUrlWithLoginPart(_ url: String) -> URL? {
    let lowercasedUrl = url.lowercased()
    if lowercasedUrl.hasPrefix("tel:") || lowercasedUrl.hasPrefix("calshow:") {
        return nil
    }
    var urlWithScheme = url
    if !url.contains("://") && !url.hasPrefix("mailto:") {
        urlWithScheme = "http://" + url
    }
    var parsedUrlValue = URL(string: urlWithScheme)
    if parsedUrlValue == nil, let encoded = urlWithScheme.addingPercentEncoding(withAllowedCharacters: urlCharacters) {
        parsedUrlValue = URL(string: encoded)
    }
    guard let parsedUrl = parsedUrlValue, parsedUrl.scheme != "mailto" else {
        return nil
    }
    if parsedUrl.user == nil && parsedUrl.password == nil {
        return nil
    }
    return parsedUrl
}

/// `url` without its login part, which is the address it really opens.
public func urlRemovingLoginPart(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url
    }
    components.user = nil
    components.password = nil
    return components.url ?? url
}

public func parseUrl(url: String, wasConcealed: Bool) -> (string: String, concealed: Bool) {
    var parsedUrlValue: URL?
    if url.hasPrefix("tel:") {
        return (url, false)
    } else if url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://"), let parsed = URL(string: url) {
        parsedUrlValue = parsed
    } else if let parsed = URL(string: "https://" + url) {
        parsedUrlValue = parsed
    } else if let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let parsed = URL(string: encoded) {
        parsedUrlValue = parsed
    }
    let host = parsedUrlValue?.host ?? url
    
    let rawHost = (host as NSString).removingPercentEncoding ?? host
    var latin = CharacterSet()
    latin.insert(charactersIn: "A"..."Z")
    latin.insert(charactersIn: "a"..."z")
    latin.insert(charactersIn: "0"..."9")
    var punctuation = CharacterSet()
    punctuation.insert(charactersIn: ".-/+_?=")
    var hasLatin = false
    var hasNonLatin = false
    for c in rawHost {
        if c.unicodeScalars.allSatisfy(punctuation.contains) {
        } else if c.unicodeScalars.allSatisfy(latin.contains) {
            hasLatin = true
        } else {
            hasNonLatin = true
        }
    }
    var concealed = wasConcealed
    if hasLatin && hasNonLatin {
        concealed = true
    }
    
    var rawDisplayUrl: String
    if hasNonLatin {
        rawDisplayUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
    } else {
        rawDisplayUrl = url
    }
    
    if let parsedUrlValue = parsedUrlValue, isConcealedUrlWhitelisted(parsedUrlValue) {
        concealed = false
    }
    
    let whitelistedSchemes: [String] = [
        "tel",
    ]
    if let parsedUrlValue = parsedUrlValue, let scheme = parsedUrlValue.scheme, whitelistedSchemes.contains(scheme) {
        concealed = false
    }
    
    if url.hasPrefix("tg://premium_multigift") || url.hasPrefix("tg://premium_offer") {
        concealed = false
    }
    
    return (rawDisplayUrl, concealed)
}
