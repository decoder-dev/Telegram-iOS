import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct LogoView: View {
    public init() {}

    public var body: some View {
        ZStack {
            // 容器：80×80pt 圆角方块
            RoundedRectangle(cornerRadius: 24)
                .fill(ColorPalette.surface2)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(ColorPalette.brandNeon, lineWidth: 1)
                )
                .shadow(color: ColorPalette.brandNeon.opacity(0.25), radius: 10, x: 0, y: 0)

            // Telegram 图标
            Image(systemName: "paperplane.fill")
                .font(.system(size: 40))
                .foregroundColor(ColorPalette.brandNeon)
        }
        .accessibilityHidden(true)
    }
}
