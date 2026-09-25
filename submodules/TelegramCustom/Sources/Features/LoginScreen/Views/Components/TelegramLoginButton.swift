import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct TelegramLoginButton: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))

                Text("login.button.telegram".localized)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color(hex: "24A1DE"))
            .cornerRadius(16)
        }
    }
}
