"""Exercise real sheet/alert activation methods without the UIKit renderer."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
sheet = (root / 'submodules/Display/Source/ActionSheetButtonItem.swift').read_text()
alert = (root / 'submodules/Display/Source/TextAlertController.swift').read_text()


def method(source, signature):
    start = source.index(signature)
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end].replace('@objc ', '').replace('override ', '')


begin = sheet.index('        self.accessibilityArea.activate = ')
end = sheet.index('\n        }', begin) + len('\n        }')
fixture = '''
struct Item { var enabled = true; var action: () -> Void }
final class Area { var activate: (() -> Bool)? }
final class SheetNode {
    var item: Item?
    let accessibilityArea = Area()
    init() {
'''
fixture += sheet[begin:end] + '\n    }\n'
fixture += method(sheet, '    @objc func buttonPressed()') + '\n'
fixture += method(sheet, '    override func performAction()') + '\n}\n'
fixture += '''
final class AlertNode {
    var actionEnabled = true
    var action: Item
    init(action: Item) { self.action = action }
'''
fixture += method(alert, '    public func performAction()') + '\n'
fixture += method(alert, '    @objc func pressed()') + '\n}\n'
fixture += '''
let sheet = SheetNode()
precondition(sheet.accessibilityArea.activate?() == false)
var actions = 0
for enabled in [true, false, true, false] {
    sheet.item = Item(enabled: enabled, action: { actions += 1 })
    let previous = actions
    sheet.buttonPressed()
    sheet.performAction()
    precondition(sheet.accessibilityArea.activate?() == enabled)
    precondition(actions == previous + (enabled ? 3 : 0))
}
let alert = AlertNode(action: Item(action: { actions += 1 }))
for enabled in [true, false, true, false] {
    alert.actionEnabled = enabled
    let previous = actions
    alert.pressed()
    alert.performAction()
    precondition(actions == previous + (enabled ? 2 : 0))
}
print("Alert actions: touch, keyboard and VoiceOver activation preserve disabled state")
'''
with tempfile.TemporaryDirectory(prefix='liquid-alert-actions-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
