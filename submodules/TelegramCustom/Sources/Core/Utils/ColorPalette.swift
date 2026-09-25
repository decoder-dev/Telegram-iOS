import SwiftUI

/// 统一色板 - 集中管理所有自定义颜色
public enum ColorPalette {
    // MARK: - Brand Colors

    /// 品牌主色：荧光绿 #CFFF55
    public static let brandNeon = Color(hex: "CFFF55")

    /// 品牌主色（UIKit 版本）
    public static let brandNeonUI = UIColor(hex: "CFFF55")

    /// 品牌辅助色：深色荧光绿
    public static let brandNeonDark = Color(hex: "A8D646")

    // MARK: - Background Colors

    /// 纯黑背景
    public static let backgroundBlack = Color.black

    /// 深灰背景
    public static let backgroundDark = Color(hex: "1C1C1E")

    /// 卡片背景
    public static let cardBackground = Color(hex: "2C2C2E")

    // MARK: - Text Colors

    /// 主文本：白色
    public static let textPrimary = Color.white

    /// 次要文本：60% 透明度白色
    public static let textSecondary = Color.white.opacity(0.6)

    /// 三级文本：40% 透明度白色
    public static let textTertiary = Color.white.opacity(0.4)

    // MARK: - HTML原型新增颜色

    /// Surface 1
    public static let surface1 = Color(hex: "0A0A0A")

    /// Surface 2
    public static let surface2 = Color(hex: "151515")

    /// Surface 3
    public static let surface3 = Color(hex: "202020")

    /// 边框颜色
    public static let borderClr = Color(hex: "292929")

    /// 静音文本颜色
    public static let txtMuted = Color(hex: "666666")

    /// 品牌暗色
    public static let brandDark = Color(hex: "a3cc3b")

    /// Emerald 400
    public static let emerald400 = Color(hex: "34d399")

    /// Emerald 500
    public static let emerald500 = Color(hex: "10b981")

    // MARK: - Accent Colors

    /// 成功/确认色
    public static let success = Color(hex: "34C759")

    /// 错误/警告色
    public static let error = Color(hex: "FF3B30")

    /// 信息提示色
    public static let info = Color(hex: "007AFF")

    // MARK: - Web3 Specific

    /// 钱包渐变色 1
    public static let walletGradientStart = Color(hex: "667EEA")

    /// 钱包渐变色 2
    public static let walletGradientEnd = Color(hex: "764BA2")
}

// MARK: - Color Extensions

extension Color {
    /// 从十六进制字符串初始化颜色
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    /// 从十六进制字符串初始化颜色（UIKit 版本）
    public convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
