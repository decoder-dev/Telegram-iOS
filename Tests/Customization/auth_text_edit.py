"""Execute the authorization text delegate with UIKit's UTF-16 edit ranges."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
source = (ROOT / 'submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift').read_text()
begin = source.index('    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {')
end = source.index('\n    func checkValidity(', begin)
method = source[begin:end]
fixture = r'''
import Foundation
final class UITextField {
    var text: String?
    init(_ text: String?) { self.text = text }
}
final class Delegate {
    var inProgress = false
    var submissions = 0
    var candidate: String?
    func proceedPressed() { submissions += 1 }
    func checkValidity(text: String, isPaste: Bool) -> Bool { candidate = text; return true }
'''
checks = r'''
}
let delegate = Delegate()
var cases = 0
for (text, fragment, replacement, expected) in [
    ("🇷🇺 тест", " ", "_", "🇷🇺_тест"),
    ("🧑🏽‍💻 код", "код", "слово", "🧑🏽‍💻 слово"),
    ("a\u{301} phrase", "phrase", "word", "a\u{301} word"),
    ("كلمة سر", "سر", "مرور", "كلمة مرور"),
    ("😀token", "token", "", "😀"),
    ("abc", "b", "😀", "a😀c")
] {
    let range = NSRange(text.range(of: fragment)!, in: text)
    precondition(delegate.textField(UITextField(text), shouldChangeCharactersIn: range, replacementString: replacement))
    precondition(delegate.candidate == expected, "Incorrect UTF-16 edit for \(text)")
    cases += 1
}
for range in [NSRange(location: 1, length: 0), NSRange(location: 0, length: 1), NSRange(location: 5, length: 0)] {
    precondition(!delegate.textField(UITextField("😀a"), shouldChangeCharactersIn: range, replacementString: "x"))
    cases += 1
}
precondition(delegate.textField(UITextField(nil), shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "word"))
precondition(delegate.candidate == "word")
precondition(!delegate.textField(UITextField(""), shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "  "))
precondition(!delegate.textField(UITextField("word"), shouldChangeCharactersIn: NSRange(location: 4, length: 0), replacementString: "\n"))
precondition(delegate.submissions == 1)
delegate.inProgress = true
precondition(!delegate.textField(UITextField("word"), shouldChangeCharactersIn: NSRange(location: 4, length: 0), replacementString: "x"))
precondition(!delegate.textField(UITextField("word"), shouldChangeCharactersIn: NSRange(location: 4, length: 0), replacementString: "\n"))
precondition(delegate.submissions == 1)
print("Authorization editing: \(cases) Unicode ranges and five state checks passed")
'''

with tempfile.TemporaryDirectory(prefix='liquid-auth-edit-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture + method + checks)
    subprocess.run(['swift', str(path)], check=True, cwd=ROOT)
