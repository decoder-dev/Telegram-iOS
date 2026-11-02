"""Run the actual settings-field delegate against UTF-16 edits and queued caret updates.

The small field/queue adapters supply UIKit's text-position contract, not a renderer.
Native coverage of the same paths lives in InputRowLayoutTests.
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
source = (ROOT / 'submodules/ItemListUI/Sources/Items/ItemListSingleLineInputItem.swift').read_text()
begin = source.index('    @objc public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {')
end = source.index('    @objc public func textFieldShouldReturn(', begin)
method = source[begin:end].replace('@objc ', '')
identifier_begin = source.index('private let validIdentifierSet:')
identifier_end = source.index('\n}()', identifier_begin) + len('\n}()')
fixture = r'''
import Foundation
final class DispatchQueue {
    static let main = DispatchQueue()
    var pending: [() -> Void] = []
    func async(execute: @escaping () -> Void) { pending.append(execute) }
    func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { execute() }
    func flush() { let work = pending; pending.removeAll(); work.forEach { $0() } }
}
final class UITextField {
    var text: String?
    var selectedTextRange: NSRange?
    let beginningOfDocument = 0
    init(_ text: String) { self.text = text }
    func position(from: Int, offset: Int) -> Int? {
        let result = from + offset
        return (0...(text?.utf16.count ?? 0)).contains(result) ? result : nil
    }
    func textRange(from: Int, to: Int) -> NSRange? { NSRange(location: from, length: to - from) }
}
struct HapticFeedback { func error() {} }
struct Layer { func addShakeAnimation() {} }
struct TextNode { let layer = Layer() }
enum InputType { case regular, username }
struct Item {
    var enabled = true
    var maxLength = 0
    var type = InputType.regular
    var shouldUpdateText: (String) -> Bool = { _ in true }
    var processPaste: ((String) -> String)?
}
final class Delegate {
    var item: Item? = Item()
    let textNode = TextNode()
    var changes: [String] = []
    func textFieldTextChanged(_ field: UITextField) { changes.append(field.text ?? "") }
'''
checks = r'''
}
let delegate = Delegate()
delegate.item?.processPaste = { _ in "🧑🏽‍💻" }
let field = UITextField("😀 value")
precondition(!delegate.textField(field, shouldChangeCharactersIn: NSRange(location: 3, length: 1), replacementString: "paste"))
precondition(field.text == "😀 🧑🏽‍💻alue")
precondition(field.selectedTextRange == nil)
DispatchQueue.main.flush()
precondition(field.selectedTextRange?.location == 10)
precondition(delegate.changes == ["😀 🧑🏽‍💻alue"])

let stale = UITextField("😀 value")
precondition(!delegate.textField(stale, shouldChangeCharactersIn: NSRange(location: 3, length: 1), replacementString: "paste"))
stale.text = "server"
DispatchQueue.main.flush()
precondition(stale.selectedTextRange == nil, "A queued selection must not replace a newer edit")

delegate.item = Item(type: .username)
let username = UITextField("e\u{301}x")
precondition(!delegate.textField(username, shouldChangeCharactersIn: NSRange(location: 2, length: 0), replacementString: "ä👍"))
precondition(username.text == "e\u{301}ax")
DispatchQueue.main.flush()
precondition(username.selectedTextRange?.location == 3)

delegate.item?.processPaste = { _ in "ä" }
let normalized = UITextField("e\u{301}x")
precondition(!delegate.textField(normalized, shouldChangeCharactersIn: NSRange(location: 2, length: 0), replacementString: "paste"))
precondition(normalized.text == "eax")
DispatchQueue.main.flush()
precondition(normalized.selectedTextRange?.location == 2)

delegate.item = Item()
let invalidBoundary = UITextField("😀a")
let invalidRange = UITextField("a")
precondition(!delegate.textField(invalidBoundary, shouldChangeCharactersIn: NSRange(location: 1, length: 0), replacementString: "x"))
precondition(!delegate.textField(invalidRange, shouldChangeCharactersIn: NSRange(location: 2, length: 0), replacementString: "x"))
delegate.item?.enabled = false
let disabled = UITextField("value")
let count = delegate.changes.count
precondition(!delegate.textField(disabled, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "x"))
precondition(disabled.text == "value" && delegate.changes.count == count)
delegate.item = Item(maxLength: 1)
let empty = UITextField("")
precondition(!delegate.textField(empty, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "ab"))
delegate.item?.shouldUpdateText = { _ in false }
precondition(!delegate.textField(empty, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "a"))
print("Settings input: processed paste, Unicode usernames, caret ownership, invalid ranges and disabled/length/validation gates passed")
'''

with tempfile.TemporaryDirectory(prefix='liquid-settings-edit-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text('import Foundation\n' + source[identifier_begin:identifier_end] + fixture + method + checks)
    subprocess.run(['swift', str(path)], check=True, cwd=ROOT)
