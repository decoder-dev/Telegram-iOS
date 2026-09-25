import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct LegalTextView: View {
    public init() {}

    public var body: some View {
        Text("login.legal".localized)
            .font(.system(size: 11))
            .foregroundColor(ColorPalette.txtMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}
