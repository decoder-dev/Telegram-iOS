import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramPresentationData/Sources/PresentationData.swift').read_text()
begin = source.index('public func higChatBubbleCorners(')
end = source.index('\n}', begin) + 2
fixture = '''import Foundation
public struct PresentationChatBubbleSettings {
    var mainRadius: Int32
    var auxiliaryRadius: Int32
    var mergeBubbleCorners: Bool
}
public struct PresentationChatBubbleCorners {
    var mainRadius: CGFloat
    var auxiliaryRadius: CGFloat
    var mergeBubbleCorners: Bool
    var hasTails: Bool
}
'''
tests = '''
for radius: Int32 in [8, 10, 12, 14, 16, 18, 20, 22, 24] {
    let corners = higChatBubbleCorners(from: .init(mainRadius: radius, auxiliaryRadius: radius / 2, mergeBubbleCorners: false))
    precondition(corners.mainRadius == CGFloat(radius), "Saved radius ignored")
    precondition(corners.auxiliaryRadius == CGFloat(radius / 2), "Adjacent radius ignored")
    precondition(!corners.mergeBubbleCorners && !corners.hasTails)
}
for radius: Int32 in [Int32.min, -1, 0, 8, 24, Int32.max] {
    let corners = higChatBubbleCorners(from: .init(mainRadius: radius, auxiliaryRadius: Int32.max, mergeBubbleCorners: true))
    precondition((8...24).contains(corners.mainRadius))
    precondition(corners.auxiliaryRadius <= corners.mainRadius)
    precondition(corners.mergeBubbleCorners)
}
print("Saved bubble geometry and boundary values: passed")
'''
with tempfile.TemporaryDirectory(prefix='telegram-customization-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixture + source[begin:end] + tests)
    subprocess.run(['swift', str(file)], check=True)
