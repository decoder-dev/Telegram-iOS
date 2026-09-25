import SwiftUI
import TelegramCustomCore

/// 认证勾选徽章（勾选图标 + 文案）
@available(iOS 14.0, *)
public struct VerifiedCheckmarkView: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(ColorPalette.brandNeon)

            Text(text)
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(ColorPalette.brandNeon)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(ColorPalette.brandNeon.opacity(0.15))
        .cornerRadius(16)
        .overlay(
            Capsule()
                .stroke(ColorPalette.brandNeon.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: ColorPalette.brandNeon.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
