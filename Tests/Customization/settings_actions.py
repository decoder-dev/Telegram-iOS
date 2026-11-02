"""Exercise production row activation paths; UIKit rendering has separate native tests."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
action = (root / 'submodules/ItemListUI/Sources/Items/ItemListActionItem.swift').read_text()
choice = (root / 'submodules/ItemListUI/Sources/Items/ItemListCheckboxItem.swift').read_text()


def member(source, start):
    begin = source.index(start)
    end = source.index('\n    }', begin) + len('\n    }')
    return source[begin:end].replace('override ', '')


def activation(source):
    begin = source.index('        self.activateArea.activate = ')
    end = source.index('\n        }', begin) + len('\n        }')
    return source[begin:end]


fixture = '''
enum ItemListActionKind { case generic, destructive, neutral, disabled }
final class ListView {
    var clears = 0
    func clearHighlightAnimated(_ animated: Bool) { clears += 1 }
}
final class Area { var activate: (() -> Bool)? }
final class ActionItem {
    var kind = ItemListActionKind.generic
    var clearHighlightAutomatically = true
    var action: () -> Void = {}
    var longTapAction: (() -> Void)?
'''
fixture += member(action, '    public var selectable: Bool') + '\n'
fixture += member(action, '    public func selected(listView: ListView)')
fixture += '''
}
final class ChoiceItem {
    var enabled = true
    var action: () -> Void = {}
'''
fixture += member(choice, '    public var selectable: Bool') + '\n'
fixture += member(choice, '    public func selected(listView: ListView)')
fixture += '\n}\nfinal class ActionNode {\n    var item: ActionItem?\n    let activateArea = Area()\n    init() {\n'
fixture += activation(action) + '\n    }\n'
fixture += member(action, '    override public func longTapped()') + '\n'
fixture += member(action, '    override public var canBeLongTapped: Bool')
fixture += '\n}\nfinal class ChoiceNode {\n    var item: ChoiceItem?\n    let activateArea = Area()\n    init() {\n'
fixture += activation(choice) + '\n    }\n}\n'
fixture += '''
let list = ListView()
let actionNode = ActionNode()
precondition(actionNode.activateArea.activate?() == false)
let actionItem = ActionItem()
actionNode.item = actionItem
var taps = 0
var holds = 0
actionItem.action = { taps += 1 }
actionItem.longTapAction = { holds += 1 }
for kind: ItemListActionKind in [.generic, .disabled, .destructive, .neutral, .disabled] {
    actionItem.kind = kind
    let active = kind != .disabled
    let previousTaps = taps
    let previousHolds = holds
    precondition(actionItem.selectable == active)
    actionItem.selected(listView: list)
    precondition(actionNode.activateArea.activate?() == active)
    precondition(actionNode.canBeLongTapped == active)
    actionNode.longTapped()
    precondition(taps == previousTaps + (active ? 2 : 0))
    precondition(holds == previousHolds + (active ? 1 : 0))
}
let choiceNode = ChoiceNode()
precondition(choiceNode.activateArea.activate?() == false)
let choiceItem = ChoiceItem()
choiceNode.item = choiceItem
choiceItem.action = { taps += 1 }
for enabled in [true, false, true, false] {
    choiceItem.enabled = enabled
    let previous = taps
    precondition(choiceItem.selectable == enabled)
    choiceItem.selected(listView: list)
    precondition(choiceNode.activateArea.activate?() == enabled)
    precondition(taps == previous + (enabled ? 2 : 0))
}
print("Settings actions: touch, VoiceOver, long press and reuse respect disabled state")
'''
with tempfile.TemporaryDirectory(prefix='liquid-settings-actions-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
