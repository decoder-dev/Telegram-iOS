"""Check production empty-state geometry, without substituting for iOS rendering."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/CallListUI/Sources/CallListEmptyStateLayout.swift').read_text()
# The harness compiles a standalone subset; strip module imports that cannot resolve here.
source = '\n'.join(line for line in source.split('\n') if not line.startswith('import '))
metrics = (root / 'submodules/TelegramPresentationData/Sources/PresentationLayoutMetrics.swift').read_text()
checks = '''
var cases = 0
for width: CGFloat in [272.0, 320.0, 393.0, 720.0] {
    for height: CGFloat in [100.0, 240.0, 480.0, 780.0] {
        for textHeight: CGFloat in [38.0, 96.0, 240.0, 800.0] {
            for buttonHeight: CGFloat in [20.0, 64.0, 120.0] {
                let viewport = CGSize(width: width, height: height)
                let layout = CallListEmptyStateLayout(viewport: viewport, illustrationSize: CGSize(width: 148.0, height: 148.0), textSize: CGSize(width: width - 48.0, height: textHeight), buttonContentSize: CGSize(width: width - 48.0, height: buttonHeight))
                precondition(layout.contentSize.height >= height)
                precondition(layout.textFrame.minY >= 24.0)
                precondition(layout.textFrame.maxY + 23.0 <= layout.buttonFrame.minY)
                precondition(layout.buttonFrame.height >= 44.0)
                precondition(layout.buttonFrame.maxY + 24.0 <= layout.contentSize.height)
                for frame in [layout.textFrame, layout.buttonFrame] {
                    precondition(frame.minX >= 24.0 && frame.maxX <= width - 24.0)
                    precondition(frame.midX == width * 0.5)
                }
                if layout.showsIllustration {
                    precondition(layout.illustrationFrame.minY >= 24.0)
                    precondition(layout.illustrationFrame.maxY + 13.0 <= layout.textFrame.minY)
                    precondition(layout.contentSize.height == height)
                }
                if textHeight + 23.0 + max(44.0, buttonHeight + 16.0) + 48.0 > height {
                    precondition(!layout.showsIllustration)
                    precondition(layout.contentSize.height > height)
                }
                cases += 1
            }
        }
    }
}
print("Call empty state: \\(cases) viewport/text/button combinations passed")
'''
with tempfile.TemporaryDirectory(prefix='liquid-calls-layout-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text('#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n' + metrics + '\n' + source + checks)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
