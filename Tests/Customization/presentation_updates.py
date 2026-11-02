"""Verify presentation-only changes reach existing call/contact rows."""
import pathlib
import re
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
controllers = [
    'CallListUI/Sources/CallListController.swift',
    'ChatListUI/Sources/ChatListController.swift',
    'TelegramPermissionsUI/Sources/PermissionController.swift',
    'MediaPickerUI/Sources/MediaPickerScreen.swift',
    'LocationUI/Sources/LocationPickerController.swift',
    'ContactListUI/Sources/ContactsController.swift',
    'ContactListUI/Sources/ContactsControllerNode.swift',
]
fixture = '''import Foundation
final class Identity {}
struct Data {
    let theme: Identity
    let strings: Identity
    let listsFontSize: Int
    let reduceMotion: Bool
}
'''
for index, path in enumerate(controllers):
    source = (root / 'submodules' / path).read_text()
    condition = re.search(r'(?:if|guard) (previousTheme !== presentationData.theme[^\n]+)', source)[1].removesuffix(' {').removesuffix(' else')
    fixture += f'''func updates{index}(_ old: Data, _ presentationData: Data) -> Bool {{
    let previousTheme = old.theme
    let previousStrings = old.strings
    let previousFontSize = old.listsFontSize
    let previousReduceMotion = old.reduceMotion
    return {condition}
}}
'''
fixture += '''
let theme = Identity()
let strings = Identity()
let original = Data(theme: theme, strings: strings, listsFontSize: 17, reduceMotion: false)
for updates in [updates0, updates1, updates2, updates3, updates4, updates5, updates6] {
    precondition(!updates(original, original))
    precondition(updates(original, Data(theme: theme, strings: strings, listsFontSize: 23, reduceMotion: false)))
    precondition(updates(original, Data(theme: theme, strings: strings, listsFontSize: 17, reduceMotion: true)))
    precondition(updates(original, Data(theme: Identity(), strings: strings, listsFontSize: 17, reduceMotion: false)))
    precondition(updates(original, Data(theme: theme, strings: Identity(), listsFontSize: 17, reduceMotion: false)))
}
'''
fixture += (root / 'submodules/MergeLists/Sources/Identifiable.swift').read_text()
fixture += (root / 'submodules/MergeLists/Sources/MergeLists.swift').read_text()
source = (root / 'submodules/ContactListUI/Sources/ContactListNode.swift').read_text()
force_update = re.search(r'let forceUpdate = previousData\?\.listsFontSize[^\n]+', source)[0]
merge = re.search(r'let \(deleteIndices, indicesAndItems, updateIndices\) = mergeListsStableWithUpdates\(leftList: fromEntries[^\n]+', source)[0]
fixture += '''
struct Row: Comparable, Identifiable {
    let stableId: Int
    static func < (lhs: Row, rhs: Row) -> Bool { lhs.stableId < rhs.stableId }
}
func transition(_ previousData: Data?, _ presentationData: Data, _ fromEntries: [Row], _ toEntries: [Row]) -> (Int, Int, Int) {
'''
fixture += force_update + '\n' + merge + '\n    return (deleteIndices.count, indicesAndItems.count, updateIndices.count)\n}\n'
fixture += '''
let rows = [Row(stableId: 1), Row(stableId: 2)]
precondition(transition(original, original, rows, rows) == (0, 0, 0))
precondition(transition(original, Data(theme: theme, strings: strings, listsFontSize: 23, reduceMotion: false), rows, rows) == (0, 0, 2))
precondition(transition(original, Data(theme: theme, strings: strings, listsFontSize: 17, reduceMotion: true), rows, rows) == (0, 0, 2))
precondition(transition(nil, original, [], rows) == (0, 2, 0))
precondition(transition(original, Data(theme: theme, strings: strings, listsFontSize: 23, reduceMotion: false), rows, [Row(stableId: 2), Row(stableId: 3)]) == (1, 1, 1))
print("Presentation updates: font/motion/theme/language delivery and contact merge reuse passed")
'''
with tempfile.TemporaryDirectory(prefix='liquid-presentation-updates-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
