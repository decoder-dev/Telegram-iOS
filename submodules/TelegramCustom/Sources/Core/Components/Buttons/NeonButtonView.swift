import SwiftUI
import TelegramCustomCore

/// 荧光按钮（渐变背景 + 双层阴影发光）
@available(iOS 14.0, *)
public struct NeonButtonView: View {
    let title: String
    let icon: String?
    let action: () -> Void

    public init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.black)

                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [ColorPalette.brandNeon, ColorPalette.brandDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: ColorPalette.brandNeon.opacity(0.4), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}
