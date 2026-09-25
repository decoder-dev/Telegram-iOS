import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct QuickAccessButton: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))

                Text("login.button.quick".localized)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(ColorPalette.brandNeon)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(ColorPalette.surface2)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ColorPalette.borderClr, lineWidth: 1)
            )
        }
    }
}
