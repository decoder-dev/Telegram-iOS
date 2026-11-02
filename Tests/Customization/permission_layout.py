"""Run production permission layout against overflow and optional content states."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramPermissionsUI/Sources/PermissionContentLayout.swift').read_text()
checks = '''
var cases = 0
for width: CGFloat in [272.0, 320.0, 393.0, 720.0] {
    for height: CGFloat in [120.0, 240.0, 480.0, 780.0, 1000.0] {
        for scale: CGFloat in [1.0, 1.4, 2.0, 3.0, 5.0] {
            for options in 0..<8 {
                let subtitle = options & 1 != 0
                let privacy = options & 2 != 0
                let footer = options & 4 != 0
                let textWidth = min(520.0, width - 48.0)
                let layout = PermissionContentLayout(
                    viewport: CGSize(width: width, height: height),
                    illustrationSize: CGSize(width: 220.0, height: 220.0),
                    titleSize: CGSize(width: textWidth, height: 60.0 * scale),
                    subtitleSize: subtitle ? CGSize(width: textWidth, height: 36.0 * scale) : .zero,
                    textSize: CGSize(width: textWidth, height: 100.0 * scale),
                    buttonSize: CGSize(width: min(420.0, textWidth), height: max(52.0, 24.0 * scale + 24.0)),
                    privacySize: privacy ? CGSize(width: textWidth, height: max(44.0, 20.0 * scale + 16.0)) : .zero,
                    footerSize: footer ? CGSize(width: textWidth, height: 50.0 * scale) : .zero
                )
                precondition(layout.contentSize.height >= height)
                precondition(layout.titleFrame.minY >= 24.0)
                let frames = [layout.titleFrame, layout.subtitleFrame, layout.textFrame, layout.buttonFrame, layout.privacyFrame, layout.footerFrame].filter { $0.height > 0.0 }
                for frame in frames {
                    precondition(frame.minX >= 24.0 && frame.maxX <= width - 24.0)
                    precondition(abs(frame.midX - width * 0.5) <= 0.5)
                    precondition(frame.maxY + 24.0 <= layout.contentSize.height)
                }
                for pair in zip(frames, frames.dropFirst()) {
                    precondition(pair.0.maxY <= pair.1.minY)
                }
                precondition(layout.buttonFrame.height >= 44.0)
                if layout.showsIllustration {
                    precondition(layout.contentSize.height == height)
                    precondition(layout.illustrationFrame.maxY + 24.0 <= layout.titleFrame.minY)
                }
                if layout.contentSize.height > height {
                    precondition(!layout.showsIllustration)
                }
                cases += 1
            }
        }
    }
}
print("Permission layout: \\(cases) viewport/text/optional-content combinations passed")
'''
with tempfile.TemporaryDirectory(prefix='liquid-permission-layout-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(source + checks)
    subprocess.run(['swift', str(path)], check=True, cwd=root)
