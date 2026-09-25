import SwiftUI

/// 网格背景Shape，绘制等距垂直和水平线
@available(iOS 14.0, *)
public struct GridPattern: Shape {
    public let spacing: CGFloat

    public init(spacing: CGFloat = 24) {
        self.spacing = spacing
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // 垂直线
        stride(from: 0, to: rect.width, by: spacing).forEach { x in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }

        // 水平线
        stride(from: 0, to: rect.height, by: spacing).forEach { y in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }

        return path
    }
}
