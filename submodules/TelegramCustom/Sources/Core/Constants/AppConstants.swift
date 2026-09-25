import Foundation

/// 应用常量 - 全局配置
public enum AppConstants {
    // MARK: - App Info

    public static let appName = "Web3 Telegram"
    public static let appVersion = "1.0.0"

    // MARK: - Splash Screen

    /// 开屏页倒计时秒数
    public static let splashCountdownSeconds = 30

    // MARK: - Feature Flags

    /// 是否启用 Web3 功能
    public static let isWeb3Enabled = true

    /// 是否启用 NFT 画廊
    public static let isNFTGalleryEnabled = false

    // MARK: - URLs

    public static let termsOfServiceURL = URL(string: "https://example.com/terms")!
    public static let privacyPolicyURL = URL(string: "https://example.com/privacy")!
}
