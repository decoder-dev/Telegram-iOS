import SwiftUI
import TelegramCustomCore

/// OFFICIAL角标徽章
@available(iOS 14.0, *)
public struct OfficialBadgeView: View {
    let text: String

    public init(text: String = "OFFICIAL") {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .foregroundColor(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(ColorPalette.brandNeon)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .textCase(.uppercase)
    }
}
