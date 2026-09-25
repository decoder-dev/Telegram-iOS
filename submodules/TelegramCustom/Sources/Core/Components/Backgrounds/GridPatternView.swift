import SwiftUI
import TelegramCustomCore

/// 网格背景视图，24px间距，半透明灰色线条
@available(iOS 14.0, *)
public struct GridPatternView: View {
    public init() {}

    public var body: some View {
        GridPattern(spacing: 24)
            .stroke(Color(hex: "1f2937").opacity(0.2), lineWidth: 1)
            .opacity(0.7)
    }
}
