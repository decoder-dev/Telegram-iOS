import SwiftUI
import TelegramCustomCore

/// 渐变发光球，支持自定义位置、大小、颜色和动画
@available(iOS 14.0, *)
public struct GradientOrbView: View {
    let size: CGFloat
    let colors: [Color]
    let blurRadius: CGFloat
    let offset: CGSize
    let animate: Bool

    @State private var isAnimating = false

    public init(
        size: CGFloat = 320,
        colors: [Color] = [ColorPalette.brandNeon.opacity(0.3), ColorPalette.emerald500.opacity(0.15), .clear],
        blurRadius: CGFloat = 60,
        offset: CGSize = CGSize(width: -96, height: -96),
        animate: Bool = true
    ) {
        self.size = size
        self.colors = colors
        self.blurRadius = blurRadius
        self.offset = offset
        self.animate = animate
    }

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blurRadius)
            .offset(offset)
            .scaleEffect(isAnimating ? 1.05 : 0.95)
            .opacity(isAnimating ? 0.4 : 0.8)
            .onAppear {
                if animate {
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
            }
    }
}
