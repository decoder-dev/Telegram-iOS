import Foundation

/// A projection of an original URL, so retained text keeps its original encoding and attributes.
struct ForkTrackingURLProjection {
    let source: String
    let ranges: [NSRange]

    var value: String {
        let string = source as NSString
        return ranges.map { string.substring(with: $0) }.joined()
    }
}

private let forkTrackingQueryNames: Set<String> = [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "ysclid",
    "igshid", "mc_cid", "mc_eid", "srsltid"
]

private let forkSignedQueryNames: Set<String> = [
    "signature", "sig", "hmac", "hash", "token", "access_token", "auth", "authorization",
    "awsaccesskeyid", "key-pair-id", "policy"
]

func forkTrackingURLProjection(_ source: String) -> ForkTrackingURLProjection? {
    let fragment = source.firstIndex(of: "#") ?? source.endIndex
    guard let question = source[..<fragment].firstIndex(of: "?") else {
        return nil
    }
    guard !source.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
    }) else {
        return nil
    }
    let parsed = URLComponents(string: source)
    let components = parsed?.scheme == nil ? URLComponents(string: "https://" + source) : parsed
    guard let components, let scheme = components.scheme?.lowercased(),
          scheme == "https" || scheme == "http", components.url != nil,
          components.user == nil, components.password == nil,
          var host = components.host?.lowercased(), !host.isEmpty else {
        return nil
    }
    if host.hasSuffix(".") {
        host.removeLast()
    }
    let queryStart = source.index(after: question)
    let pairs = source[queryStart..<fragment].split(separator: "&", omittingEmptySubsequences: false)
    var kept: [Substring] = []
    var removed = false
    let shareHost = ["youtube.com", "youtu.be", "spotify.com"].contains(where: {
        host == $0 || host.hasSuffix("." + $0)
    })
    for pair in pairs {
        let encodedKey = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? pair
        guard let key = String(encodedKey).removingPercentEncoding?.lowercased() else {
            return nil
        }
        // Signed links must remain byte-for-byte intact, including their tracking-looking fields.
        if forkSignedQueryNames.contains(key) || key.hasPrefix("x-amz-") || key.hasPrefix("x-goog-") {
            return nil
        }
        if key.hasPrefix("utm_") || forkTrackingQueryNames.contains(key) || (key == "si" && shareHost) {
            removed = true
        } else if !pair.isEmpty {
            kept.append(pair)
        }
    }
    guard removed else {
        return nil
    }
    var ranges = [NSRange(source.startIndex..<question, in: source)]
    if !kept.isEmpty {
        ranges.append(NSRange(question..<queryStart, in: source))
        for (index, pair) in kept.enumerated() {
            if index != 0 {
                ranges.append(NSRange(source.index(before: pair.startIndex)..<pair.startIndex, in: source))
            }
            ranges.append(NSRange(pair.startIndex..<pair.endIndex, in: source))
        }
    }
    if fragment != source.endIndex {
        ranges.append(NSRange(fragment..<source.endIndex, in: source))
    }
    return ForkTrackingURLProjection(source: source, ranges: ranges)
}

func forkURLWithoutTracking(_ source: String) -> String {
    return forkTrackingURLProjection(source)?.value ?? source
}
