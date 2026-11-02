"""Check actual group height budgeting when text forces individual groups to scroll."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/Display/Source/ActionSheetItemGroupsContainerNode.swift').read_text()
begin = source.index('func actionSheetGroupHeightLimit(')
end = source.index('\n}', begin) + 2
checks = '''
var cases = 0
for totalHeight: CGFloat in [60.0, 100.0, 120.0, 320.0, 780.0] {
    for groupCount in 1...5 {
        for tallIndex in 0..<groupCount {
            let spacing: CGFloat = 8.0
            var usedHeight: CGFloat = 0.0
            let minimumHeight = min(44.0, max(0.0, totalHeight - CGFloat(groupCount - 1) * spacing) / CGFloat(groupCount))
            for index in 0..<groupCount {
                if index > 0 { usedHeight += spacing }
                let heightLimit = actionSheetGroupHeightLimit(totalHeight: totalHeight, usedHeight: usedHeight, groupCount: groupCount, remainingGroupCount: groupCount - index, spacing: spacing)
                let contentHeight: CGFloat = index == tallIndex ? 2000.0 : 57.0
                let height = min(contentHeight, heightLimit)
                precondition(height + 0.0001 >= minimumHeight)
                usedHeight += height
                precondition(usedHeight <= totalHeight + 0.0001)
            }
            cases += 1
        }
    }
}
precondition(actionSheetGroupHeightLimit(totalHeight: 600, usedHeight: 0, groupCount: 2, remainingGroupCount: 2, spacing: 8) >= 57)
precondition(actionSheetGroupHeightLimit(totalHeight: 600, usedHeight: 65, groupCount: 2, remainingGroupCount: 1, spacing: 8) == 535)
print("Sheet groups: \\(cases) height/count/tall-group combinations passed")
'''
with tempfile.TemporaryDirectory(prefix='liquid-sheet-layout-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text('import Foundation\n' + source[begin:end] + checks)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
