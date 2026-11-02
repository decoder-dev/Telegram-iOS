import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramPresentationData/Sources/PresentationData.swift').read_text(encoding='utf-8')
begin = source.index('public func higChatBubbleCorners(')
end = source.index('\n}', begin) + 2
theme_source = (root / 'submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift').read_text(encoding='utf-8')
policy_begin = theme_source.index('func shouldPreserveLiquidDefaults(')
policy_end = theme_source.index('\n}', policy_begin) + 2
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
enum PresentationBuiltinThemeReference: CaseIterable {
    case dayClassic, day, night, nightAccent, bananaGramCream, bananaGramGraphite, bananaGramHalloween
}
'''
tests = '''
// New range 4-30, smooth auxiliary curve: floor(4 + (r-4)*0.4)
for radius: Int32 in [4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30] {
    let corners = higChatBubbleCorners(from: .init(mainRadius: radius, auxiliaryRadius: 0, mergeBubbleCorners: false))
    precondition(corners.mainRadius == CGFloat(radius), "Saved radius ignored: \\(radius) -> \\(corners.mainRadius)")
    let expectedAux = floor(4.0 + (CGFloat(radius) - 4.0) * 0.4)
    precondition(corners.auxiliaryRadius == expectedAux, "Auxiliary mismatch at \\(radius): expected \\(expectedAux) got \\(corners.auxiliaryRadius)")
    precondition(!corners.mergeBubbleCorners && corners.hasTails)
}
for radius: Int32 in [Int32.min, -1, 0, 4, 30, Int32.max] {
    let corners = higChatBubbleCorners(from: .init(mainRadius: radius, auxiliaryRadius: Int32.max, mergeBubbleCorners: true))
    precondition((4...30).contains(corners.mainRadius), "Out of bounds: \\(corners.mainRadius)")
    precondition(corners.auxiliaryRadius <= corners.mainRadius)
    precondition(corners.mergeBubbleCorners)
}
print("Saved bubble geometry and boundary values: passed")
for reference in PresentationBuiltinThemeReference.allCases {
    for hasAccent in [false, true] {
        for hasOutgoingAccent in [false, true] {
            for hasBubbleColors in [false, true] {
                let classic = reference == .dayClassic || reference == .day || reference == .night
                for hasExtendingTheme in [false, true] {
                    let expected = classic && !hasAccent && !hasOutgoingAccent && !hasBubbleColors && !hasExtendingTheme
                    precondition(shouldPreserveLiquidDefaults(reference: reference, hasAccent: hasAccent, hasOutgoingAccent: hasOutgoingAccent, hasBubbleColors: hasBubbleColors, hasExtendingTheme: hasExtendingTheme) == expected)
                }
            }
        }
    }
}
print("Liquid defaults, explicit colours and custom themes: 112 combinations passed")
'''
with tempfile.TemporaryDirectory(prefix='telegram-customization-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixture + source[begin:end] + '\n' + theme_source[policy_begin:policy_end] + tests, encoding='utf-8')
    subprocess.run(['swift', str(file)], check=True)

subprocess.run([sys.executable, str(root / 'Tests/Customization/header_scroll.py')], check=True)
subprocess.run([sys.executable, str(root / 'Tests/Customization/authorization_layout.py')], check=True)
subprocess.run([sys.executable, str(root / 'Tests/Customization/auth_text_edit.py')], check=True)
