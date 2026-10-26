import Foundation
import TextFormat

private let forkTrackingLinkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

private func forkTrackingLinkIsCode(_ text: NSAttributedString, range: NSRange) -> Bool {
    var isCode = false
    text.enumerateAttributes(in: range, options: []) { attributes, _, stop in
        if attributes[ChatTextInputAttributes.monospace] != nil {
            isCode = true
        } else if let block = attributes[ChatTextInputAttributes.block] as? ChatTextInputTextQuoteAttribute,
                  case .code = block.kind {
            isCode = true
        }
        if isCode {
            stop.pointee = true
        }
    }
    return isCode
}

/// Clean ordinary outgoing text while preserving retained UTF-16 ranges, formatting and hidden links.
func forkTextWithoutTrackingLinks(_ text: NSAttributedString) -> NSAttributedString {
    guard text.length != 0 else {
        return text
    }
    let source = NSMutableAttributedString(attributedString: text)
    var hiddenLinks: [(NSRange, String)] = []
    text.enumerateAttribute(ChatTextInputAttributes.textUrl, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
        guard let link = value as? ChatTextInputTextUrlAttribute,
              !forkTrackingLinkIsCode(text, range: range) else {
            return
        }
        let cleaned = forkURLWithoutTracking(link.url)
        if cleaned != link.url {
            hiddenLinks.append((range, cleaned))
        }
    }
    for (range, url) in hiddenLinks {
        source.addAttribute(ChatTextInputAttributes.textUrl, value: ChatTextInputTextUrlAttribute(url: url), range: range)
    }
    guard source.string.contains("?"), let detector = forkTrackingLinkDetector else {
        return source
    }
    let string = source.string as NSString
    let matches = detector.matches(in: source.string, options: [], range: NSRange(location: 0, length: source.length))
    let result = NSMutableAttributedString(string: "")
    var cursor = 0
    for match in matches {
        guard let scheme = match.url?.scheme?.lowercased(), scheme == "http" || scheme == "https",
              !forkTrackingLinkIsCode(source, range: match.range),
              let projection = forkTrackingURLProjection(string.substring(with: match.range)) else {
            continue
        }
        result.append(source.attributedSubstring(from: NSRange(location: cursor, length: match.range.location - cursor)))
        for range in projection.ranges {
            result.append(source.attributedSubstring(from: NSRange(location: match.range.location + range.location, length: range.length)))
        }
        cursor = NSMaxRange(match.range)
    }
    if cursor == 0 {
        return source
    }
    result.append(source.attributedSubstring(from: NSRange(location: cursor, length: source.length - cursor)))
    return result
}
