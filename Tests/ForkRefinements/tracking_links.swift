import Foundation

let cases: [(String, String)] = [
    ("https://example.org/a?utm_source=chat&id=A%2Fb+c#section", "https://example.org/a?id=A%2Fb+c#section"),
    ("https://example.org/?id=1&utm_campaign=x&next=%2Fkeep%3Fv%3D2&gclid=foo", "https://example.org/?id=1&next=%2Fkeep%3Fv%3D2"),
    ("https://example.org/?UTM%5Fsource=chat#😀", "https://example.org/#😀"),
    ("https://www.youtube.com/watch?v=abc&t=12&si=share", "https://www.youtube.com/watch?v=abc&t=12"),
    ("https://open.spotify.com/track/123?si=share&context=playlist", "https://open.spotify.com/track/123?context=playlist"),
    ("https://youtube.com.evil.example/?si=essential&utm_source=x", "https://youtube.com.evil.example/?si=essential"),
    ("https://example.org/?si=essential&ref=required", "https://example.org/?si=essential&ref=required"),
    ("https://example.org/?utm_source=x&X-Amz-Signature=abc", "https://example.org/?utm_source=x&X-Amz-Signature=abc"),
    ("https://example.org/?sig=abc&utm_source=x", "https://example.org/?sig=abc&utm_source=x"),
    ("https://example.org/?utm_source=x&token=auth", "https://example.org/?utm_source=x&token=auth"),
    ("https://user:password@example.org/?utm_source=x", "https://user:password@example.org/?utm_source=x"),
    ("https://example.org/#view?utm_source=route", "https://example.org/#view?utm_source=route"),
    ("tg://resolve?domain=example&utm_source=x", "tg://resolve?domain=example&utm_source=x"),
    ("mailto:test@example.org?utm_source=x", "mailto:test@example.org?utm_source=x"),
    ("example.org/?utm_source=x&id=1", "example.org/?id=1"),
    ("https://example.org/?utm_source=x&invalid%ZZ=value", "https://example.org/?utm_source=x&invalid%ZZ=value")
]
for (input, expected) in cases {
    precondition(forkURLWithoutTracking(input) == expected, "Unexpected cleanup: \(input)")
}

let url = "https://example.org/😀?utm_source=chat&id=KEEP#anchor"
let original = NSMutableAttributedString(string: "🇷🇺 " + url + " tail")
let marker = NSAttributedString.Key("retained-marker")
original.addAttribute(marker, value: "keep-formatting", range: (original.string as NSString).range(of: "KEEP"))
let cleaned = forkTextWithoutTrackingLinks(original)
precondition(cleaned.string == "🇷🇺 https://example.org/😀?id=KEEP#anchor tail")
precondition(cleaned.attribute(marker, at: (cleaned.string as NSString).range(of: "KEEP").location, effectiveRange: nil) as? String == "keep-formatting")

let hidden = NSAttributedString(string: "Open page", attributes: [
    ChatTextInputAttributes.textUrl: ChatTextInputTextUrlAttribute(url: "https://example.org/?utm_source=x&id=1"),
    marker: "hidden-formatting"
])
let cleanedHidden = forkTextWithoutTrackingLinks(hidden)
precondition(cleanedHidden.string == hidden.string)
precondition((cleanedHidden.attribute(ChatTextInputAttributes.textUrl, at: 0, effectiveRange: nil) as? ChatTextInputTextUrlAttribute)?.url == "https://example.org/?id=1")
precondition(cleanedHidden.attribute(marker, at: 0, effectiveRange: nil) as? String == "hidden-formatting")

for attributes: [NSAttributedString.Key: Any] in [
    [ChatTextInputAttributes.monospace: true],
    [ChatTextInputAttributes.block: ChatTextInputTextQuoteAttribute(kind: .code(language: "text"), isCollapsed: false)]
] {
    let code = NSAttributedString(string: url, attributes: attributes)
    precondition(forkTextWithoutTrackingLinks(code).isEqual(to: code), "Code was changed")
}

let multiple = NSAttributedString(string: "https://a.example/?utm_source=x&id=1 and https://b.example/?id=2&utm_source=y")
precondition(forkTextWithoutTrackingLinks(multiple).string == "https://a.example/?id=1 and https://b.example/?id=2")
precondition(forkTextWithoutTrackingLinks(NSAttributedString(string: "plain text")).string == "plain text")
precondition(forkTextWithoutTrackingLinks(NSAttributedString(string: "")).length == 0)
print("Tracking-link safety, signed URLs, Unicode and retained formatting: passed")
