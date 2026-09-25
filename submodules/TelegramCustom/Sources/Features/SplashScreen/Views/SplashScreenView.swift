import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
public struct SplashScreenView: View {
    @StateObject private var viewModel = SplashViewModel()
    let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // 黑色底色
            ColorPalette.backgroundBlack
                .ignoresSafeArea()

            // 动画背景层
            AnimatedBackgroundView()
                .ignoresSafeArea()

            // 内容层
            VStack(spacing: 0) {
                // 顶部跳过按钮
                HStack {
                    Spacer()
                    SkipButtonView(countdown: viewModel.countdown) {
                        viewModel.cancelTimer()
                        onComplete()
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 20)
                }

                Spacer()

                // 中央Logo区域
                SplashLogoSectionView()
                    .padding(.horizontal, 8)

                Spacer()

                // 底部按钮区域
                VStack(spacing: 8) {
                    NeonButtonView(
                        title: "splash.button.enter".localized,
                        icon: "arrow.right"
                    ) {
                        viewModel.cancelTimer()
                        onComplete()
                    }
                    .padding(.horizontal, 24)

                    Text("splash.footer.guarantee".localized)
                        .font(.system(size: 10))
                        .foregroundColor(ColorPalette.txtMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            viewModel.startCountdown(completion: onComplete)
        }
    }
}
