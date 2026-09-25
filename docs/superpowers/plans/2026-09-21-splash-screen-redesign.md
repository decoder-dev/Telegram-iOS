# u多担保开屏页 1:1 还原实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完全1:1还原HTML原型中的u多担保开屏页，采用纯SwiftUI实现，0张图片资源，组件化架构

**Architecture:** 将开屏页拆分为可复用组件（背景层/徽章/按钮/视图），使用SwiftUI原生能力实现所有视觉效果（渐变、blur、阴影、动画），支持4语言本地化

**Tech Stack:** SwiftUI, iOS 14.0+, SF Symbols, Bazel

---

## 文件映射

### 新建文件
- `submodules/TelegramCustom/Sources/Core/Components/Shapes/GridPattern.swift` - 网格Shape
- `submodules/TelegramCustom/Sources/Core/Components/Backgrounds/GradientOrbView.swift` - 渐变发光球
- `submodules/TelegramCustom/Sources/Core/Components/Backgrounds/GridPatternView.swift` - 网格视图
- `submodules/TelegramCustom/Sources/Core/Components/Backgrounds/AnimatedBackgroundView.swift` - 完整背景
- `submodules/TelegramCustom/Sources/Core/Components/Badges/OfficialBadgeView.swift` - OFFICIAL徽章
- `submodules/TelegramCustom/Sources/Core/Components/Badges/FeaturePillView.swift` - 功能标签
- `submodules/TelegramCustom/Sources/Core/Components/Badges/VerifiedCheckmarkView.swift` - 认证勾选
- `submodules/TelegramCustom/Sources/Core/Components/Buttons/SkipButtonView.swift` - 跳过按钮
- `submodules/TelegramCustom/Sources/Core/Components/Buttons/NeonButtonView.swift` - 荧光按钮
- `submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashLogoSectionView.swift` - Logo区域

### 修改文件
- `submodules/TelegramCustom/Sources/Core/Utils/ColorPalette.swift` - 新增9个颜色
- `submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashScreenView.swift` - 完全重写
- `submodules/TelegramCustom/Resources/zh-Hans.lproj/Localizable.strings` - 新增10个key
- `submodules/TelegramCustom/Resources/en.lproj/Localizable.strings` - 新增10个key
- `submodules/TelegramCustom/Resources/ja.lproj/Localizable.strings` - 新增10个key
- `submodules/TelegramCustom/Resources/ko.lproj/Localizable.strings` - 新增10个key

---

## Task 1: 扩展颜色系统

**Files:**
- Modify: `submodules/TelegramCustom/Sources/Core/Utils/ColorPalette.swift`

- [ ] **Step 1: 在ColorPalette中新增9个颜色常量**

在 `ColorPalette` enum 的 `public static let textTertiary` 后面添加：

```swift
// HTML原型新增颜色
public static let backgroundBlack = Color(hex: "000000")
public static let surface1 = Color(hex: "0A0A0A")
public static let surface2 = Color(hex: "151515")
public static let surface3 = Color(hex: "202020")
public static let borderClr = Color(hex: "292929")
public static let txtMuted = Color(hex: "666666")
public static let brandDark = Color(hex: "a3cc3b")
public static let emerald400 = Color(hex: "34d399")
public static let emerald500 = Color(hex: "10b981")
```

- [ ] **Step 2: 验证颜色定义**

运行构建验证语法：
```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过，无错误

- [ ] **Step 3: Commit颜色扩展**

```bash
git add submodules/TelegramCustom/Sources/Core/Utils/ColorPalette.swift
git commit -m "feat(splash): add 9 colors for u-duo splash redesign

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 实现网格Shape

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Shapes/GridPattern.swift`

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p submodules/TelegramCustom/Sources/Core/Components/Shapes
```

- [ ] **Step 2: 创建GridPattern.swift文件**

```swift
import SwiftUI

/// 网格背景Shape，绘制等距垂直和水平线
@available(iOS 14.0, *)
public struct GridPattern: Shape {
    public let spacing: CGFloat

    public init(spacing: CGFloat = 24) {
        self.spacing = spacing
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // 垂直线
        stride(from: 0, to: rect.width, by: spacing).forEach { x in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }

        // 水平线
        stride(from: 0, to: rect.height, by: spacing).forEach { y in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }

        return path
    }
}
```

- [ ] **Step 3: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Shapes/GridPattern.swift
git commit -m "feat(splash): add GridPattern shape for background

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 实现网格视图组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Backgrounds/GridPatternView.swift`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p submodules/TelegramCustom/Sources/Core/Components/Backgrounds
```

- [ ] **Step 2: 创建GridPatternView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 网格背景视图，24px间距，半透明灰色线条
@available(iOS 14.0, *)
public struct GridPatternView: View {
    public init() {}

    public var body: some View {
        GridPattern(spacing: 24)
            .stroke(Color(hex: "1f2937").opacity(0.2), lineWidth: 1)
            .opacity(0.7)
    }
}
```

- [ ] **Step 3: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Backgrounds/GridPatternView.swift
git commit -m "feat(splash): add GridPatternView component

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 实现渐变发光球组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Backgrounds/GradientOrbView.swift`

- [ ] **Step 1: 创建GradientOrbView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 渐变发光球，支持自定义位置、大小、颜色和动画
@available(iOS 14.0, *)
public struct GradientOrbView: View {
    let size: CGFloat
    let colors: [Color]
    let blurRadius: CGFloat
    let offset: CGSize
    let animate: Bool

    @State private var isAnimating = false

    public init(
        size: CGFloat = 320,
        colors: [Color] = [ColorPalette.brandNeon.opacity(0.3), ColorPalette.emerald500.opacity(0.15), .clear],
        blurRadius: CGFloat = 60,
        offset: CGSize = CGSize(width: -96, height: -96),
        animate: Bool = true
    ) {
        self.size = size
        self.colors = colors
        self.blurRadius = blurRadius
        self.offset = offset
        self.animate = animate
    }

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blurRadius)
            .offset(offset)
            .scaleEffect(isAnimating ? 1.05 : 0.95)
            .opacity(isAnimating ? 0.4 : 0.8)
            .onAppear {
                if animate {
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
            }
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Backgrounds/GradientOrbView.swift
git commit -m "feat(splash): add GradientOrbView with animation support

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 实现完整动画背景组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Backgrounds/AnimatedBackgroundView.swift`

- [ ] **Step 1: 创建AnimatedBackgroundView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 完整动画背景：3个渐变发光球 + 网格
@available(iOS 14.0, *)
public struct AnimatedBackgroundView: View {
    public init() {}

    public var body: some View {
        ZStack {
            // 左上角渐变球（动画）
            GradientOrbView(
                size: 320,
                colors: [ColorPalette.brandNeon.opacity(0.3), ColorPalette.emerald500.opacity(0.15), .clear],
                blurRadius: 60,
                offset: CGSize(width: -96, height: -96),
                animate: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 右下角渐变球（静态）
            GradientOrbView(
                size: 320,
                colors: [ColorPalette.brandNeon.opacity(0.25), Color.blue.opacity(0.1), .clear],
                blurRadius: 60,
                offset: CGSize(width: 96, height: 96),
                animate: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // 中央发光球（静态）
            GradientOrbView(
                size: 288,
                colors: [ColorPalette.brandNeon.opacity(0.15), .clear],
                blurRadius: 40,
                offset: CGSize(width: 0, height: -100),
                animate: false
            )

            // 网格背景
            GridPatternView()
        }
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Backgrounds/AnimatedBackgroundView.swift
git commit -m "feat(splash): add AnimatedBackgroundView with 3 orbs + grid

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 实现OFFICIAL徽章组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Badges/OfficialBadgeView.swift`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p submodules/TelegramCustom/Sources/Core/Components/Badges
```

- [ ] **Step 2: 创建OfficialBadgeView.swift**

```swift
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
            .tracking(0.5)
    }
}
```

- [ ] **Step 3: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Badges/OfficialBadgeView.swift
git commit -m "feat(splash): add OfficialBadgeView component

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 实现功能标签组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Badges/FeaturePillView.swift`

- [ ] **Step 1: 创建FeaturePillView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 功能标签（图标 + 文字 + 边框）
@available(iOS 14.0, *)
public struct FeaturePillView: View {
    let icon: String
    let text: String

    public init(icon: String, text: String) {
        self.icon = icon
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(ColorPalette.brandNeon)

            Text(text)
                .font(.system(size: 10))
                .foregroundColor(ColorPalette.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(ColorPalette.surface2.opacity(0.8))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorPalette.borderClr.opacity(0.8), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Badges/FeaturePillView.swift
git commit -m "feat(splash): add FeaturePillView component

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: 实现认证勾选组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Badges/VerifiedCheckmarkView.swift`

- [ ] **Step 1: 创建VerifiedCheckmarkView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 认证勾选徽章（勾选图标 + 文案）
@available(iOS 14.0, *)
public struct VerifiedCheckmarkView: View {
    let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(ColorPalette.brandNeon)

            Text(text)
                .font(.system(size: 12, weight: .extrabold))
                .foregroundColor(ColorPalette.brandNeon)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(ColorPalette.brandNeon.opacity(0.15))
        .cornerRadius(16)
        .overlay(
            Capsule()
                .stroke(ColorPalette.brandNeon.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: ColorPalette.brandNeon.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Badges/VerifiedCheckmarkView.swift
git commit -m "feat(splash): add VerifiedCheckmarkView component

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: 实现跳过按钮组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Buttons/SkipButtonView.swift`

- [ ] **Step 1: 创建目录**

```bash
mkdir -p submodules/TelegramCustom/Sources/Core/Components/Buttons
```

- [ ] **Step 2: 创建SkipButtonView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 跳过按钮（半透明背景 + 倒计时）
@available(iOS 14.0, *)
public struct SkipButtonView: View {
    let countdown: Int
    let action: () -> Void

    public init(countdown: Int, action: @escaping () -> Void) {
        self.countdown = countdown
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("splash.skip.label".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ColorPalette.textSecondary)

                Text("\(countdown)s")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ColorPalette.brandNeon)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            .overlay(
                Capsule()
                    .stroke(ColorPalette.brandNeon.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}
```

- [ ] **Step 3: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 4: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Buttons/SkipButtonView.swift
git commit -m "feat(splash): add SkipButtonView component

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: 实现荧光按钮组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Core/Components/Buttons/NeonButtonView.swift`

- [ ] **Step 1: 创建NeonButtonView.swift**

```swift
import SwiftUI
import TelegramCustomCore

/// 荧光按钮（渐变背景 + 双层阴影发光）
@available(iOS 14.0, *)
public struct NeonButtonView: View {
    let title: String
    let icon: String?
    let action: () -> Void

    public init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .extrabold))
                    .foregroundColor(.black)

                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [ColorPalette.brandNeon, ColorPalette.brandDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: ColorPalette.brandNeon.opacity(0.4), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Core/Components/Buttons/NeonButtonView.swift
git commit -m "feat(splash): add NeonButtonView with glow effects

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: 新增4语言本地化字符串

**Files:**
- Modify: `submodules/TelegramCustom/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `submodules/TelegramCustom/Resources/en.lproj/Localizable.strings`
- Modify: `submodules/TelegramCustom/Resources/ja.lproj/Localizable.strings`
- Modify: `submodules/TelegramCustom/Resources/ko.lproj/Localizable.strings`

- [ ] **Step 1: 更新中文本地化**

在 `submodules/TelegramCustom/Resources/zh-Hans.lproj/Localizable.strings` 末尾追加：

```
// u多担保开屏页
"splash.skip.label" = "跳过广告";
"splash.badge.verified" = "u多担保 • 5000万赔付准备金托底";
"splash.title.line1" = "u多担保 ✕ Telegram";
"splash.title.line2" = "全网极速多签公证平台";
"splash.subtitle" = "支持 OTC、技术开发、营销公关与流量交易担保\n智能合约资金锁仓 + 官方争议仲裁保障";
"splash.feature.multisig" = "多签托管锁仓";
"splash.feature.verification" = "防骗真实性验真";
"splash.feature.arbitration" = "官方公正仲裁";
"splash.button.enter" = "进入 Telegram Web3 登录页";
"splash.footer.guarantee" = "100% 资金由 u多担保 智能合约与赔付准备金双重托底";
```

- [ ] **Step 2: 更新英文本地化**

在 `submodules/TelegramCustom/Resources/en.lproj/Localizable.strings` 末尾追加：

```
// u-Duo Escrow Splash Screen
"splash.skip.label" = "Skip";
"splash.badge.verified" = "u-Duo Escrow • $50M Security Reserve";
"splash.title.line1" = "u-Duo Escrow ✕ Telegram";
"splash.title.line2" = "Ultra-Fast Multi-Sig Platform";
"splash.subtitle" = "Support OTC, Dev, Marketing & Traffic Escrow\nSmart Contract Lock + Official Arbitration";
"splash.feature.multisig" = "Multi-Sig Lock";
"splash.feature.verification" = "Anti-Fraud Check";
"splash.feature.arbitration" = "Official Arbitration";
"splash.button.enter" = "Enter Telegram Web3 Login";
"splash.footer.guarantee" = "100% Funds Secured by Smart Contracts & Reserve";
```

- [ ] **Step 3: 更新日文本地化**

在 `submodules/TelegramCustom/Resources/ja.lproj/Localizable.strings` 末尾追加：

```
// u多担保スプラッシュ画面
"splash.skip.label" = "スキップ";
"splash.badge.verified" = "u多担保 • 5000万ドル準備金";
"splash.title.line1" = "u多担保 ✕ Telegram";
"splash.title.line2" = "高速マルチシグプラットフォーム";
"splash.subtitle" = "OTC、開発、マーケティング、トラフィック取引の担保をサポート\nスマートコントラクトロック＋公式仲裁保証";
"splash.feature.multisig" = "マルチシグ保管";
"splash.feature.verification" = "詐欺防止検証";
"splash.feature.arbitration" = "公式仲裁";
"splash.button.enter" = "Telegram Web3ログインへ";
"splash.footer.guarantee" = "100%の資金がスマートコントラクトと準備金で保証";
```

- [ ] **Step 4: 更新韩文本地化**

在 `submodules/TelegramCustom/Resources/ko.lproj/Localizable.strings` 末尾追加：

```
// u多담보 스플래시 화면
"splash.skip.label" = "건너뛰기";
"splash.badge.verified" = "u多담보 • 5000만 달러 준비금";
"splash.title.line1" = "u多담보 ✕ Telegram";
"splash.title.line2" = "초고속 멀티시그 플랫폼";
"splash.subtitle" = "OTC, 개발, 마케팅, 트래픽 거래 담보 지원\n스마트 계약 잠금 + 공식 중재 보장";
"splash.feature.multisig" = "멀티시그 보관";
"splash.feature.verification" = "사기 방지 검증";
"splash.feature.arbitration" = "공식 중재";
"splash.button.enter" = "Telegram Web3 로그인";
"splash.footer.guarantee" = "100% 자금이 스마트 계약과 준비금으로 보호";
```

- [ ] **Step 5: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 6: Commit**

```bash
git add submodules/TelegramCustom/Resources/*/Localizable.strings
git commit -m "feat(splash): add localized strings for 4 languages

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: 实现Logo区域组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashLogoSectionView.swift`

- [ ] **Step 1: 创建SplashLogoSectionView.swift**

```swift
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
                            .font(.system(size: 11, weight: .extrabold))
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
                    .tracking(-0.5)
                    .lineLimit(1)

                Text("splash.title.line2".localized)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ColorPalette.brandNeon, .white, ColorPalette.brandNeon.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .tracking(-0.5)
                    .lineLimit(1)
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
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashLogoSectionView.swift
git commit -m "feat(splash): add SplashLogoSectionView with all elements

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: 重写SplashScreenView主视图

**Files:**
- Modify: `submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashScreenView.swift`

- [ ] **Step 1: 完全替换SplashScreenView.swift内容**

```swift
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
```

- [ ] **Step 2: 验证编译**

```bash
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64 --continueOnError
```

Expected: 编译通过

- [ ] **Step 3: Commit**

```bash
git add submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashScreenView.swift
git commit -m "feat(splash): rewrite SplashScreenView with new components

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: 完整构建和运行测试

**Files:**
- Test: 完整app构建和运行

- [ ] **Step 1: 完整构建**

```bash
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
```

Expected: 完整构建成功，无错误

- [ ] **Step 2: 安装到模拟器**

```bash
SIM_UUID=117E2ED3-57A8-46CF-9F1D-2B9CAF5040BC ./dev/run-simulator.sh
```

Expected: app启动，开屏页显示

- [ ] **Step 3: 视觉验证checklist**

手动检查：
- [ ] 背景有3个渐变发光球（左上动画、右下静态、中央静态）
- [ ] 网格线清晰可见，24px间距
- [ ] Logo有发光效果，shield图标 + USDT徽章居中
- [ ] OFFICIAL角标在右上角
- [ ] 认证勾选显示正确
- [ ] 主标题第二行有渐变色
- [ ] 3个feature标签正确显示
- [ ] 跳过按钮倒计时从3到0
- [ ] 荧光按钮有发光效果
- [ ] 底部guarantee文案显示

- [ ] **Step 4: 多语言测试**

切换模拟器语言到英文/日文/韩文，重启app验证文案：
```bash
# 英文
xcrun simctl boot 117E2ED3-57A8-46CF-9F1D-2B9CAF5040BC
xcrun simctl spawn 117E2ED3-57A8-46CF-9F1D-2B9CAF5040BC defaults write "Apple Global Domain" AppleLanguages -array en
# 重新安装测试
```

Expected: 所有语言文案正确显示

- [ ] **Step 5: 功能测试**

- 等待3秒，验证自动跳转到登录页
- 点击跳过按钮，验证立即跳转
- 点击荧光按钮，验证立即跳转

Expected: 所有交互正常

- [ ] **Step 6: 性能检查**

启动Instruments查看：
- FPS ≥ 60
- 内存占用 < 10MB

Expected: 性能符合要求

---

## Task 15: 最终commit

**Files:**
- All modified files

- [ ] **Step 1: 查看所有更改**

```bash
git status
git diff --stat
```

Expected: 确认所有文件都已提交

- [ ] **Step 2: 最终验证编译**

```bash
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
```

Expected: 完整构建成功

- [ ] **Step 3: 创建总结commit（如果需要）**

如果有遗漏的小改动：
```bash
git add -A
git commit -m "chore(splash): finalize u-duo splash redesign

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## 自检清单

### Spec覆盖度
- [x] 颜色系统扩展 - Task 1
- [x] 网格背景 - Task 2, 3
- [x] 渐变发光球 - Task 4, 5
- [x] OFFICIAL徽章 - Task 6
- [x] 功能标签 - Task 7
- [x] 认证勾选 - Task 8
- [x] 跳过按钮 - Task 9
- [x] 荧光按钮 - Task 10
- [x] 4语言本地化 - Task 11
- [x] Logo区域组合 - Task 12
- [x] 主视图重写 - Task 13
- [x] 完整测试 - Task 14

### Placeholder检查
- [x] 所有代码步骤包含完整实现
- [x] 所有文件路径精确
- [x] 所有命令包含预期输出
- [x] 无TBD/TODO

### 类型一致性
- [x] ColorPalette新颜色名称一致
- [x] 组件init参数名称一致
- [x] 本地化key名称一致（splash.*）

---

## 执行说明

计划已完成并保存。选择执行方式：

1. **Subagent-Driven (推荐)** - 每个Task分派独立subagent，任务间review
2. **Inline Execution** - 在当前会话批量执行，检查点review
