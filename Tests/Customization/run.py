import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramPresentationData/Sources/PresentationData.swift').read_text(encoding='utf-8')
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
// New range 4-30, smooth auxiliary curve: floor(4 + (r-4)*0.4)
for radius: Int32 in [4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30] {
    let corners = higChatBubbleCorners(from: .init(mainRadius: radius, auxiliaryRadius: 0, mergeBubbleCorners: false))
    precondition(corners.mainRadius == CGFloat(radius), "Saved radius ignored: \\(radius) -> \\(corners.mainRadius)")
    let expectedAux = floor(4.0 + (CGFloat(radius) - 4.0) * 0.4)
    precondition(corners.auxiliaryRadius == expectedAux, "Auxiliary mismatch at \\(radius): expected \\(expectedAux) got \\(corners.auxiliaryRadius)")
    precondition(!corners.mergeBubbleCorners && !corners.hasTails)
}
for radius: Int32 in [Int32.min, -1, 0, 4, 30, Int32.max] {
    let corners = higChatBubbleCorners(from: .init(mainRadius: radius, auxiliaryRadius: Int32.max, mergeBubbleCorners: true))
    precondition((4...30).contains(corners.mainRadius), "Out of bounds: \\(corners.mainRadius)")
    precondition(corners.auxiliaryRadius <= corners.mainRadius)
    precondition(corners.mergeBubbleCorners)
}
print("Saved bubble geometry and boundary values: passed")
'''
with tempfile.TemporaryDirectory(prefix='telegram-customization-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixture + source[begin:end] + tests, encoding='utf-8')
    subprocess.run(['swift', str(file)], check=True)
