"""Exercise the shared authorization layout with its production Swift solver."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'submodules/AuthorizationUtils/Sources/AuthorizationLayoutGeometry.swift'
CHECKS = r'''
let zero = AuthorizationLayoutItemSpacing(weight: 0, maxValue: 0)
let zeroWeight = AuthorizationLayoutItemSpacing(weight: 0, maxValue: 100)
let bounds = CGRect(x: 20, y: 50, width: 320, height: 130)
let sizes = Array(repeating: CGSize(width: 200, height: 10), count: 3)
let capped = authorizationLayoutFrames(bounds: bounds, sizes: sizes, spacings: [
    .init(weight: 100, maxValue: 1), zero,
    .init(weight: 2, maxValue: 10), zero,
    .init(weight: 1, maxValue: 1000), zero
], failIfDoesNotFit: true)!
precondition(capped.map(\.minY) == [51, 71, 170], "Cascading caps must redistribute more than once")
precondition(capped.last!.maxY == bounds.maxY)
let unweighted = authorizationLayoutFrames(bounds: bounds, sizes: sizes, spacings: Array(repeating: zeroWeight, count: 6), failIfDoesNotFit: true)!
precondition(unweighted.first!.minY == 100 && unweighted.last!.maxY == 130)
precondition(unweighted.allSatisfy { $0.minY.isFinite })
precondition(authorizationLayoutFrames(bounds: .zero, sizes: [CGSize(width: 20, height: 44)], spacings: [zero, zero], failIfDoesNotFit: true) == nil)
precondition(authorizationLayoutFrames(bounds: bounds, sizes: [], spacings: [], failIfDoesNotFit: true) == [])

var cases = 0
for width: CGFloat in [240, 320, 393, 768] {
    for height: CGFloat in [0, 44, 150, 300, 600, 1200] {
        for scale: CGFloat in [1, 1.5, 2, 3] {
            let sizes = [CGSize(width: width - 48, height: 34 * scale), CGSize(width: width - 48, height: 80 * scale), CGSize(width: width - 88, height: 44 * scale)]
            let bounds = CGRect(x: 24, y: 62, width: width, height: height)
            let spacings: [AuthorizationLayoutItemSpacing] = [.init(weight: 10, maxValue: 18), zero, .init(weight: 18, maxValue: 18), zero, .init(weight: 32, maxValue: 60), zero]
            let frames = authorizationLayoutFrames(bounds: bounds, sizes: sizes, spacings: spacings, failIfDoesNotFit: false)!
            for (index, frame) in frames.enumerated() {
                precondition(frame.minY.isFinite && frame.minX.isFinite)
                precondition(frame.size == sizes[index])
                precondition(abs(frame.midX - bounds.midX) < 1)
                if index > 0 {
                    precondition(frame.minY >= frames[index - 1].maxY)
                    precondition(frame.minY - frames[index - 1].maxY <= spacings[index * 2].maxValue)
                }
            }
            if sizes.reduce(CGFloat(0), { $0 + $1.height }) <= height {
                precondition(frames.first!.minY >= bounds.minY && frames.last!.maxY <= bounds.maxY)
            }
            let shifted = authorizationLayoutFrames(bounds: bounds.offsetBy(dx: 17, dy: 31), sizes: sizes, spacings: spacings, failIfDoesNotFit: false)!
            precondition(zip(frames, shifted).allSatisfy { $0.offsetBy(dx: 17, dy: 31) == $1 })
            cases += 1
        }
    }
}
print("Authorization layout: \(cases) sizes and five boundary regressions passed")
'''

with tempfile.TemporaryDirectory(prefix='liquid-authorization-') as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(SOURCE.read_text() + '\n' + CHECKS)
    subprocess.run(['swift', str(path)], check=True, cwd=ROOT)
