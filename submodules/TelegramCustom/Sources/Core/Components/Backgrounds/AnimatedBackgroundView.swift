import SwiftUI
import TelegramCustomCore

/// 完整动画背景：3个渐变发光球 + 网格
@available(iOS 14.0, *)
public struct AnimatedBackgroundView: View {
    public init() {}

    public var body: some View {
        ZStack {
            // 左上角渐变球（动画）
            GradientOrbView(
                size: 320,
                colors: [ColorPalette.brandNeon.opacity(0.3), ColorPalette.emerald500.opacity(0.15), .clear],
                blurRadius: 60,
                offset: CGSize(width: -96, height: -96),
                animate: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 右下角渐变球（静态）
            GradientOrbView(
                size: 320,
                colors: [ColorPalette.brandNeon.opacity(0.25), Color.blue.opacity(0.1), .clear],
                blurRadius: 60,
                offset: CGSize(width: 96, height: 96),
                animate: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // 中央发光球（静态）
            GradientOrbView(
                size: 288,
                colors: [ColorPalette.brandNeon.opacity(0.15), .clear],
                blurRadius: 40,
                offset: CGSize(width: 0, height: -100),
                animate: false
            )

            // 网格背景
            GridPatternView()
        }
    }
}
