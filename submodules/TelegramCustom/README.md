# TelegramCustom 模块

## 📁 目录结构

```
TelegramCustom/
├── BUILD                                   # Bazel 构建配置
├── Sources/
│   ├── Core/                              # 核心工具类（全局共享）
│   │   ├── Utils/
│   │   │   ├── ColorPalette.swift        # 统一色板
│   │   │   └── LocalizationManager.swift # 多语言管理
│   │   └── Constants/
│   │       ├── AppConstants.swift        # 应用常量
│   │       └── LayoutConstants.swift     # 布局常量
│   │
│   ├── Features/                          # 功能模块（按业务划分）
│   │   └── SplashScreen/                 # 开屏广告页
│   │       ├── Views/
│   │       │   └── SplashScreenView.swift
│   │       └── ViewModels/
│   │           └── SplashViewModel.swift
│   │
│   └── UI/                                # 通用 UI 组件
│       ├── Components/                    # 可复用组件
│       └── Modifiers/                     # SwiftUI 修饰符
│
└── Resources/
    └── Localizations/                     # 多语言文件
        ├── en.lproj/Localizable.strings   # 英语
        ├── zh-Hans.lproj/                 # 简体中文
        ├── ja.lproj/                      # 日语
        └── ko.lproj/                      # 韩语
```

## 🎯 核心功能

### 1. 开屏广告页（SplashScreen）

- ✅ 1:1 还原 HTML 原型设计
- ✅ 荧光绿品牌色 + 发光效果
- ✅ 3 秒倒计时自动跳转
- ✅ 支持中英日韩 4 种语言
- ✅ 纯 SwiftUI 原生实现（零第三方依赖）

### 2. LoginScreen (登录页)

**位置**: `Sources/Features/LoginScreen/`

**功能**: A02 Web3 × Telegram 登录页，位于闪屏后、TG原生登录前。

**组件**:
- `LoginViewModel`: 登录页视图模型
- `LogoView`: Logo 容器（80×80pt，荧光绿发光）
- `TitleSectionView`: 标题与副标题区域
- `TelegramLoginButton`: Telegram 蓝色登录按钮
- `QuickAccessButton`: 一键免密按钮（边框样式）
- `LegalTextView`: 法律条款文案
- `LoginScreenView`: 主容器视图

**集成**: AppDelegate.swift 中通过 `showLoginScreen()` 调用

**编译**: 需要 `--//Telegram:enableWeb3Splash` 标志

### 2. 统一色板（ColorPalette）

```swift
// 使用示例
ColorPalette.brandNeon        // 荧光绿 #CFFF55
ColorPalette.textPrimary      // 主文本（白色）
ColorPalette.textSecondary    // 次要文本（60% 透明度）
```

### 3. 多语言管理（LocalizationManager）

```swift
// 使用示例
"splash.slogan.main".localized               // 简单本地化
"splash.skip.format".localized(with: 3)      // 带参数
```

### 4. 布局常量（LayoutConstants）

```swift
// 使用示例
LayoutConstants.spacingMD          // 16pt
LayoutConstants.cornerRadiusLG     // 16pt
LayoutConstants.buttonHeightMD     // 44pt
```

## 🔧 集成到主 App

### 方式一：条件编译（推荐，不影响 upstream）

在 `Telegram/Sources/AppDelegate.swift` 的 `application(_:didFinishLaunchingWithOptions:)` 开头添加：

```swift
#if ENABLE_WEB3_SPLASH
import TelegramCustom
import SwiftUI
#endif

func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    #if ENABLE_WEB3_SPLASH
    showWeb3SplashScreen()
    return true
    #else
    setupMainWindow()
    return true
    #endif
}

#if ENABLE_WEB3_SPLASH
private func showWeb3SplashScreen() {
    let splashView = SplashScreenView {
        DispatchQueue.main.async { [weak self] in
            self?.setupMainWindow()
        }
    }

    let hostingController = UIHostingController(rootView: splashView)
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = hostingController
    window?.makeKeyAndVisible()
}
#endif
```

### 构建命令

```bash
# 启用开屏页
bazel build //Telegram:Telegram --define=ENABLE_WEB3_SPLASH=true

# 禁用（默认，upstream 兼容）
bazel build //Telegram:Telegram
```

## 🌍 添加新语言

1. 创建新语言目录：`Resources/Localizations/de.lproj/`（德语示例）
2. 复制 `en.lproj/Localizable.strings` 并翻译
3. 无需修改代码，自动支持

## ➕ 添加新功能模块

```bash
# 示例：添加 Web3 钱包模块
mkdir -p Sources/Features/Web3Wallet/{Views,ViewModels,Services}

# 在 BUILD 文件添加新模块
swift_library(
    name = "Web3WalletModule",
    srcs = glob(["Sources/Features/Web3Wallet/**/*.swift"]),
    deps = [":TelegramCustomCore"],
)
```

## 📦 依赖说明

- ✅ SwiftUI（iOS 13+，系统自带）
- ✅ Foundation（系统自带）
- ❌ 零第三方依赖

## 🚀 优势

| 方面 | 说明 |
|------|------|
| **隔离性** | 独立 `TelegramCustom` 模块，upstream 零冲突 |
| **扩展性** | `Features/` 目录支持无限添加新功能 |
| **可维护性** | 工具类统一管理，避免代码重复 |
| **多语言** | 开箱支持中英日韩，易于扩展 |
| **轻量级** | 纯原生实现，零第三方依赖 |

## 🔄 与 Upstream 同步

```bash
# 拉取官方更新
git fetch upstream
git merge upstream/master

# 只需要 rebase 你在 AppDelegate.swift 的 1 处条件编译
# TelegramCustom/ 目录完全独立，不会有冲突
```

## 📝 后续扩展建议

1. **Web3 钱包**：`Sources/Features/Web3Wallet/`
2. **NFT 画廊**：`Sources/Features/NFTGallery/`
3. **通用组件**：`Sources/UI/Components/PrimaryButton.swift`
4. **动画效果**：`Sources/UI/Modifiers/ShimmerEffect.swift`

---

**作者**: Jade
**创建日期**: 2026-09-21
**许可**: 与主项目保持一致
