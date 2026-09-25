import SwiftUI
import TelegramCustomCore

/// 功能标签（图标 + 文字 + 边框）
@available(iOS 14.0, *)
public struct FeaturePillView: View {
    let icon: String
    let text: String

    public init(icon: String, text: String) {
        self.icon = icon
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(ColorPalette.brandNeon)

            Text(text)
                .font(.system(size: 10))
                .foregroundColor(ColorPalette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(ColorPalette.surface2.opacity(0.8))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorPalette.borderClr.opacity(0.8), lineWidth: 1)
        )
    }
}
