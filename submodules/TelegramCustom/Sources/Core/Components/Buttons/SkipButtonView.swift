import SwiftUI
import TelegramCustomCore

/// 跳过按钮（半透明背景 + 倒计时）
@available(iOS 14.0, *)
public struct SkipButtonView: View {
    let countdown: Int
    let action: () -> Void

    public init(countdown: Int, action: @escaping () -> Void) {
        self.countdown = countdown
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("splash.skip.label".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ColorPalette.textSecondary)

                Text("\(countdown)s")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(ColorPalette.brandNeon)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .overlay(
                Capsule()
                    .stroke(ColorPalette.brandNeon.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}
