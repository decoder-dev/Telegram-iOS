import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct LoginScreenView: View {
    @StateObject private var viewModel = LoginViewModel()
    let onTelegramLogin: () -> Void

    public init(onTelegramLogin: @escaping () -> Void) {
        self.onTelegramLogin = onTelegramLogin
    }

    public var body: some View {
        ZStack {
            // 黑色背景
            ColorPalette.backgroundBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 上部内容区
                VStack(spacing: 24) {
                    LogoView()
                    TitleSectionView()
                }
                .padding(.top, 200)
                .padding(.horizontal, 24)

                Spacer()

                // 底部按钮区
                VStack(spacing: 12) {
                    TelegramLoginButton(action: onTelegramLogin)
                    QuickAccessButton(action: viewModel.handleQuickAccess)
                    LegalTextView()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}
