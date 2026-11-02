"""Run the production header geometry against scroll and snapping boundaries."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListHeaderScrollGeometry.swift'
CHECKS = r'''
var cases = 0
for titleHeight: CGFloat in [0.0, 52.0, 84.0, 110.0] {
    for searchHeight: CGFloat in [0.0, 54.0] {
        let end = titleHeight + searchHeight
        let offsets: [CGFloat] = [-200, -1, 0, 1, titleHeight * 0.5, titleHeight - 1, titleHeight, titleHeight + 1, titleHeight + searchHeight * 0.5, end - 1, end, end + 500]
        for offset in offsets {
            let state = ChatListHeaderScrollGeometry(offset: offset, largeTitleHeight: titleHeight, searchHeight: searchHeight)
            precondition(state.titleOffset >= 0 && state.titleOffset <= titleHeight)
            precondition(state.searchOffset >= 0 && state.searchOffset <= searchHeight)
            precondition(abs(state.titleOffset + state.searchOffset - max(0, min(end, offset))) < 0.0001)
            precondition(state.clippedOffset == min(end, offset))
            precondition((0.0 ... 1.0).contains(state.titleFraction))
            precondition((0.0 ... 1.0).contains(state.searchFraction))
            if offset <= 0 || offset >= end || offset == titleHeight {
                precondition(state.snappingOffset == nil)
            } else {
                let target = state.snappingOffset!
                precondition([CGFloat(0), titleHeight, end].contains(target))
                precondition(abs(target - offset) <= max(titleHeight, searchHeight) * 0.5)
            }
            if titleHeight == 0 && searchHeight > 0 {
                precondition(abs(state.searchFraction - (1 - min(searchHeight, max(0, offset)) / searchHeight)) < 0.0001)
            }
            cases += 1
        }
    }
}
let beforeTitleMidpoint = ChatListHeaderScrollGeometry(offset: 25, largeTitleHeight: 52, searchHeight: 54)
let afterTitleMidpoint = ChatListHeaderScrollGeometry(offset: 27, largeTitleHeight: 52, searchHeight: 54)
let beforeSearchMidpoint = ChatListHeaderScrollGeometry(offset: 78, largeTitleHeight: 52, searchHeight: 54)
let afterSearchMidpoint = ChatListHeaderScrollGeometry(offset: 80, largeTitleHeight: 52, searchHeight: 54)
precondition(beforeTitleMidpoint.snappingOffset == 0)
precondition(afterTitleMidpoint.snappingOffset == 52)
precondition(beforeSearchMidpoint.snappingOffset == 52)
precondition(afterSearchMidpoint.snappingOffset == 106)
print("Header geometry: \(cases) boundary cases and four snap decisions passed")
'''

with tempfile.TemporaryDirectory(prefix='liquid-header-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(SOURCE.read_text() + '\n' + CHECKS)
    subprocess.run(['swift', str(path)], check=True, cwd=ROOT)
