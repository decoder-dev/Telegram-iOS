"""Message filters: matching is bounded in time and anchored to the whole text; a filter list from a link is shown
before it is added and cannot turn filtering on or evict the user's own patterns (31 Oct audit: C-1, C-2, C-9)."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
settings = (root / 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift').read_text(encoding='utf-8')
open_url = (root / 'submodules/TelegramUI/Sources/OpenUrl.swift').read_text(encoding='utf-8')


def block(source, start_marker):
    """The declaration starting at `start_marker`, up to its matching closing brace."""
    start = source.index(start_marker)
    depth = 0
    for index in range(source.index('{', start), len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError('unterminated ' + start_marker)


filters = block(settings, 'public enum ForkRegexMessageFilters {')

# Source contracts.
assert 'regex.firstMatch(' not in filters, 'every match must go through boundedFirstMatch'
assert '[.reportProgress, .withoutAnchoringBounds]' in filters
assert 'case .timedOut:' in filters and 'expensivePatterns.modify' in filters
importer = block(open_url, 'private func handleAyuFiltersImportDeepLink(')
assert 'regexMessageFiltersEnabled' not in importer, 'an imported list must not turn filtering on'
assert 'request.timeoutInterval = 10.0' in importer
assert 'data.count <= ForkRegexMessageFilters.importListByteLimit' in importer
assert 'ForkRegexMessageFilters.importablePatterns(' in importer
assert 'textAlertController(context: context, title: title, text: message, actions: [' in importer, 'the list is confirmed first'
assert '.suffix(64)' not in importer, 'an imported list must not evict the user patterns'

fixture = """
import Foundation
enum ForkRegexMessageFilters {
    static let maxPatterns = 64
    static let matchBudget: Double = 0.02
""" + block(filters, '    enum BoundedMatchResult {') + "\n" \
    + block(filters, '    static func boundedFirstMatch(') + "\n" \
    + block(filters, '    public static func importablePatterns(') + """
}
typealias F = ForkRegexMessageFilters
func range(_ s: String, _ limit: Int = 4096) -> NSRange { NSRange(location: 0, length: min((s as NSString).length, limit)) }

// C-1: catastrophic backtracking is cut off by the budget instead of hanging the caller.
let slow = try! NSRegularExpression(pattern: "(a*)*b")
for count in [32, 512, 4096] {
    let text = String(repeating: "a", count: count) + "!"
    let start = Date()
    let result = F.boundedFirstMatch(slow, in: text, range: range(text))
    let elapsed = Date().timeIntervalSince(start)
    precondition(result == .timedOut, "expected a timeout on \\(count) characters, got \\(result)")
    precondition(elapsed < 0.5, "took \\(elapsed)s on \\(count) characters")
}
precondition(F.boundedFirstMatch(slow, in: "aab", range: range("aab")) == .matched)
let plain = try! NSRegularExpression(pattern: "hello")
precondition(F.boundedFirstMatch(plain, in: "say hello", range: range("say hello")) == .matched)
precondition(F.boundedFirstMatch(plain, in: "goodbye", range: range("goodbye")) == .noMatch)

// C-9: anchors hold at the ends of the whole text, not at the edge of the 4096 window.
let long = String(repeating: "a", count: 4096) + "!"
precondition(F.boundedFirstMatch(try! NSRegularExpression(pattern: "a$"), in: long, range: range(long)) == .noMatch)
precondition(F.boundedFirstMatch(try! NSRegularExpression(pattern: "^a"), in: long, range: range(long)) == .matched)
let tagged = "hello\\n<type>1</type>"
precondition(F.boundedFirstMatch(try! NSRegularExpression(pattern: "<type>1</type>$"), in: tagged, range: range(tagged)) == .matched)

// C-2: what an imported list may add.
let list = "# comment\\nspam\\n(unclosed\\n\\(String(repeating: "x", count: 513))\\nspam\\nmine\\n  ads  \\n"
precondition(F.importablePatterns(fromList: list, existing: ["mine"]) == ["spam", "ads"])
let full = (0 ..< 64).map { "own\\($0)" }
precondition(F.importablePatterns(fromList: "a\\nb", existing: full).isEmpty, "a full list is never evicted")
let almost = (0 ..< 63).map { "own\\($0)" }
precondition(F.importablePatterns(fromList: "a\\nb\\nc", existing: almost) == ["a"])
print("Message filters: bounded matching, whole-text anchors and confirmed, non-evicting import passed")
"""

with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture, encoding='utf-8')
    subprocess.run(['swiftc', '-O', str(path), '-o', str(pathlib.Path(directory) / 'check')], check=True)
    subprocess.run([str(pathlib.Path(directory) / 'check')], check=True, timeout=60)
