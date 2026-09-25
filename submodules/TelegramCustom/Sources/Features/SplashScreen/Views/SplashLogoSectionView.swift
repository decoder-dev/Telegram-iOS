import SwiftUI
import TelegramCustomCore

/// Logo区域：Shield图标 + USDT + OFFICIAL + 认证 + 标题 + 副标题 + feature标签
@available(iOS 14.0, *)
public struct SplashLogoSectionView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // Logo + USDT + OFFICIAL
            ZStack(alignment: .topTrailing) {
                // 外层发光
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                ColorPalette.brandNeon.opacity(0.4),
                                ColorPalette.emerald400.opacity(0.2),
                                ColorPalette.brandNeon.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 112, height: 112)
                    .blur(radius: 20)

                // 主Logo容器
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [ColorPalette.surface2, ColorPalette.surface1, ColorPalette.backgroundBlack],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 112, height: 112)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(ColorPalette.brandNeon.opacity(0.5), lineWidth: 1)
                        )
                        .shadow(color: ColorPalette.brandNeon.opacity(0.4), radius: 25, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)

                    // Shield图标 + USDT徽章
                    ZStack {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 48))
                            .foregroundColor(ColorPalette.brandNeon)

                        Text("USDT")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ColorPalette.brandNeon)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.black, lineWidth: 1)
                            )
                            .offset(y: 14)
                    }
                }

                // OFFICIAL角标
                OfficialBadgeView(text: "OFFICIAL")
                    .offset(x: 8, y: -8)
            }
            .frame(width: 112, height: 112)

            // 认证勾选
            VerifiedCheckmarkView(text: "splash.badge.verified".localized)

            // 标题区域
            VStack(spacing: 8) {
                Text("splash.title.line1".localized)
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("splash.title.line2".localized)
                    .font(.system(size: 24, weight: .black))
                    .lineLimit(1)
                    .overlay(
                        LinearGradient(
                            colors: [ColorPalette.brandNeon, .white, ColorPalette.brandNeon.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .mask(
                        Text("splash.title.line2".localized)
                            .font(.system(size: 24, weight: .black))
                            .lineLimit(1)
                    )
            }

            // 副标题
            Text("splash.subtitle".localized)
                .font(.system(size: 12))
                .foregroundColor(ColorPalette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            // Feature标签行
            HStack(spacing: 8) {
                FeaturePillView(icon: "lock.fill", text: "splash.feature.multisig".localized)
                FeaturePillView(icon: "shield.checkered", text: "splash.feature.verification".localized)
                FeaturePillView(icon: "hammer.fill", text: "splash.feature.arbitration".localized)
            }
            .padding(.top, 4)
        }
    }
}
