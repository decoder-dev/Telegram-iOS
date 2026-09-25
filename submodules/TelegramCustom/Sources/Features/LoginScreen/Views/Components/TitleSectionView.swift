import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct TitleSectionView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // 标题
            Text("login.title".localized)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(ColorPalette.textPrimary)

            // 副标题
            Text("login.subtitle".localized)
                .font(.system(size: 14))
                .foregroundColor(ColorPalette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
        }
    }
}
