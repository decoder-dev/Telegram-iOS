# A02 登录页面设计文档

**日期**: 2026-09-22
**作者**: Jade
**状态**: 已批准

## 概述

实现 Web3 × Telegram 超级应用的 A02 登录页面，1:1 还原 HTML 原型设计。登录页位于闪屏广告页之后、Telegram 原生登录流程之前，提供两种登录入口：Telegram 账号快捷登录（立即可用）和一键免密接入（未来扩展）。

## 目标

1. **精确还原**：1:1 复刻 HTML 原型 `screen-login` (第 218-240 行) 的视觉设计
2. **流程衔接**：闪屏页 → 登录页 → TG 原生登录的平滑过渡
3. **可扩展性**：为按钮 2（一键免密接入）预留 SDK 集成接口
4. **多语言支持**：中英日韩四种语言
5. **架构一致性**：与现有闪屏页保持相同的 MVVM + SwiftUI 架构

## 用户流程

```
┌──────────────┐     3秒倒计时      ┌──────────────┐
│              │    或点击跳过/按钮   │              │
│  闪屏广告页   │─────────────────→│  A02 登录页   │
│  (A01)       │                    │              │
└──────────────┘                    └──────┬───────┘
                                           │
                                           │ 点击按钮1
                                           ↓
                                    ┌──────────────┐
                                    │ Telegram     │
                                    │ 原生登录流程  │
                                    └──────────────┘
```

**关键行为**：
- **按钮 1 "Telegram 账号快捷登录"**: 调用 `onTelegramLogin()` 回调，进入 TG 原生登录
- **按钮 2 "一键免密接入"**: 当前为占位（仅打印日志，不做任何UI响应），未来接入 SDK + 服务器 token
- **无返回按钮**: 用户只能前进，符合原型设计

## 架构设计

### 模块结构

```
submodules/TelegramCustom/
├── Sources/
│   ├── Features/
│   │   ├── SplashScreen/          (已存在)
│   │   │   ├── Views/
│   │   │   │   └── SplashScreenView.swift
│   │   │   └── ViewModels/
│   │   │       └── SplashViewModel.swift
│   │   │
│   │   └── LoginScreen/           (新增)
│   │       ├── Views/
│   │       │   └── LoginScreenView.swift
│   │       └── ViewModels/
│   │           └── LoginViewModel.swift
│   │
│   └── Core/                      (复用)
│       └── Utils/
│           ├── ColorPalette.swift
│           └── LocalizationManager.swift
│
├── Resources/
│   └── Localizations/
│       ├── zh-Hans.lproj/Localizable.strings  (追加登录页文案)
│       ├── en.lproj/Localizable.strings
│       ├── ja.lproj/Localizable.strings
│       └── ko.lproj/Localizable.strings
│
└── BUILD                          (新增 LoginScreenModule target)
```

### Bazel 构建配置

在 `BUILD` 文件中新增：

```python
# 登录页模块
swift_library(
    name = "LoginScreenModule",
    srcs = glob(["Sources/Features/LoginScreen/**/*.swift"]),
    module_name = "LoginScreen",
    deps = [":TelegramCustomCore"],
    data = glob(["Resources/Localizations/**/*.strings"]),
    visibility = ["//visibility:public"],
)

# 统一导出（更新）
swift_library(
    name = "TelegramCustom",
    module_name = "TelegramCustom",
    srcs = ["Sources/TelegramCustom.swift"],
    deps = [
        ":TelegramCustomCore",
        ":SplashScreenModule",
        ":LoginScreenModule",  # 新增
    ],
    visibility = ["//visibility:public"],
)
```

## UI 设计规范（1:1 还原 HTML 原型）

### 整体布局

```
┌─────────────────────────────┐
│                             │
│   [上部留白 48pt]            │
│                             │
│   ┌─────────────────┐       │
│   │  Telegram Logo  │       │  80×80pt 圆角方块
│   │   (荧光绿图标)   │       │  surface2 背景 + 荧光绿边框
│   └─────────────────┘       │  发光效果 (neon-glow-sm)
│                             │
│   Web3 × Telegram           │  标题: 24pt 粗体 白色
│                             │
│   去中心化Web3生态与         │  副标题: 14pt textSecondary
│   轻量社交的融合体。         │  支持换行，最大宽度~300pt
│   继续使用原有账号...        │
│                             │
│                             │
│       [弹性空间]             │
│                             │
│                             │
│   ┌─────────────────────┐   │
│   │ 📱 Telegram账号快捷登录│  │  高度56pt, 圆角16pt
│   └─────────────────────┘   │  蓝色 #24A1DE, 白色文字
│         (按钮 1)            │  16pt 半粗体
│                             │
│   ┌─────────────────────┐   │
│   │ ⚡ 一键免密接入(快速体验)│ │  高度56pt, 圆角16pt
│   └─────────────────────┘   │  surface2 + borderClr 边框
│         (按钮 2)            │  荧光绿文字 16pt 半粗体
│                             │
│   登录即代表您同意          │  11pt txtMuted 居中
│   《服务条款》与《隐私政策》 │
│                             │
│   [底部留白 32pt]            │
└─────────────────────────────┘
```

### 精确颜色和间距

| 元素 | 规格 |
|------|------|
| **背景** | `ColorPalette.backgroundBlack` (#000000) |
| **Logo 容器** | 80×80pt, 圆角 24pt, `surface2` (#151515) 背景 |
| **Logo 边框** | `brandNeon` (#CFFF55) 1pt, 发光效果 |
| **Logo 图标** | SF Symbol `paperplane.fill`, 40pt, 荧光绿 |
| **标题** | "Web3 × Telegram", 24pt, 粗体, 白色 |
| **副标题** | 14pt, `textSecondary` (白色 60% 透明度) |
| **按钮 1 背景** | `#24A1DE` (Telegram 蓝) |
| **按钮 1 文字** | 白色, 16pt, semibold |
| **按钮 2 背景** | `surface2` (#151515) |
| **按钮 2 边框** | `borderClr` (#292929) 1pt |
| **按钮 2 文字** | `brandNeon` (#CFFF55), 16pt, semibold |
| **按钮高度** | 56pt |
| **按钮圆角** | 16pt |
| **按钮间距** | 12pt |
| **法律文案** | 11pt, `txtMuted` (#666666), 居中 |

### 发光效果

Logo 容器使用与闪屏页相同的 `neon-glow-sm` 效果：

```swift
.shadow(color: ColorPalette.brandNeon.opacity(0.25), radius: 10, x: 0, y: 0)
```

## 组件实现

### LoginScreenView.swift

主视图组件，负责整体布局和子组件组合：

```swift
@available(iOS 14.0, *)
public struct LoginScreenView: View {
    @StateObject private var viewModel = LoginViewModel()
    let onTelegramLogin: () -> Void

    public init(onTelegramLogin: @escaping () -> Void) {
        self.onTelegramLogin = onTelegramLogin
    }

    public var body: some View {
        ZStack {
            ColorPalette.backgroundBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 上部内容区
                VStack(spacing: 24) {
                    LogoView()
                    TitleSectionView()
                }
                .padding(.top, 48)
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
```

### 子组件拆分

#### 1. LogoView
- 80×80pt 圆角方块容器
- Telegram 图标（`paperplane.fill`）
- 荧光绿边框 + 发光效果

#### 2. TitleSectionView
- 标题：`"login.title".localized`
- 副标题：`"login.subtitle".localized`
- 支持多行文本，居中对齐

#### 3. TelegramLoginButton
- 蓝色背景 (#24A1DE)
- 白色文字 + Telegram 图标
- 点击调用 `onTelegramLogin` 回调

#### 4. QuickAccessButton
- 灰色边框样式
- 荧光绿文字 + 闪电图标（`bolt.fill`）
- 点击调用 ViewModel 的 `handleQuickAccess()`

#### 5. LegalTextView
- 11pt 灰色文案
- `"login.legal".localized`

### LoginViewModel.swift

```swift
import Foundation

@available(iOS 14.0, *)
public class LoginViewModel: ObservableObject {

    /// 处理一键免密登录（当前为占位实现）
    public func handleQuickAccess() {
        // TODO: 未来接入 SDK 和服务器 token 逻辑
        // 当前实现：仅打印日志，不做任何 UI 响应
        print("[LoginViewModel] 一键免密接入功能待开发")
    }

    // 未来扩展接口：
    // - func loginWithSDK(completion: @escaping (Result<Token, Error>) -> Void)
    // - @Published var isLoading: Bool = false
    // - @Published var errorMessage: String?
}
```

**设计理由**：
- 当前逻辑简单，但保留 ViewModel 层为未来扩展预留空间
- SDK 集成时只需在此添加方法，View 层无需改动
- 符合 MVVM 架构，与闪屏页保持一致

## 多语言文案

### zh-Hans.lproj/Localizable.strings

```
/* 登录页 */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "去中心化 Web3 生态与轻量社交的融合体。\n继续使用原有账号、联系人与群组。";
"login.button.telegram" = "Telegram 账号快捷登录";
"login.button.quick" = "一键免密接入 (快速体验)";
"login.legal" = "登录即代表您同意《服务条款》与《隐私政策》";
"login.quick.coming_soon" = "功能开发中，敬请期待";
```

### en.lproj/Localizable.strings

```
/* Login Screen */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "Decentralized Web3 ecosystem integrated with lightweight messaging.\nContinue with your existing account, contacts, and groups.";
"login.button.telegram" = "Quick Login with Telegram";
"login.button.quick" = "One-Click Access (Quick Start)";
"login.legal" = "By logging in, you agree to our Terms of Service and Privacy Policy";
"login.quick.coming_soon" = "Feature coming soon";
```

### ja.lproj/Localizable.strings

```
/* ログイン画面 */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "分散型Web3エコシステムと軽量なメッセージングの融合。\n既存のアカウント、連絡先、グループを引き続き使用できます。";
"login.button.telegram" = "Telegramアカウントでログイン";
"login.button.quick" = "ワンクリックアクセス（クイックスタート）";
"login.legal" = "ログインすることで、利用規約とプライバシーポリシーに同意したものとみなされます";
"login.quick.coming_soon" = "機能開発中";
```

### ko.lproj/Localizable.strings

```
/* 로그인 화면 */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "분산형 Web3 생태계와 가벼운 메시징의 융합.\n기존 계정, 연락처 및 그룹을 계속 사용하세요.";
"login.button.telegram" = "Telegram 계정으로 빠른 로그인";
"login.button.quick" = "원클릭 액세스 (빠른 시작)";
"login.legal" = "로그인하면 서비스 약관 및 개인정보 보호정책에 동의하는 것으로 간주됩니다";
"login.quick.coming_soon" = "기능 개발 중";
```

## 主 App 集成

### 修改 AppDelegate.swift

**当前流程（闪屏 → TG 登录）：**

```swift
#if ENABLE_WEB3_SPLASH
let splashView = SplashScreenView {
    DispatchQueue.main.async { [weak self] in
        self?.setupMainWindow()
    }
}
let hostingController = UIHostingController(rootView: splashView)
window = UIWindow(frame: UIScreen.main.bounds)
window?.rootViewController = hostingController
window?.makeKeyAndVisible()
#endif
```

**新流程（闪屏 → 登录 → TG 登录）：**

```swift
#if ENABLE_WEB3_SPLASH
import TelegramCustom
import SwiftUI

func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    #if ENABLE_WEB3_SPLASH
    showSplashScreen()
    return true
    #else
    setupMainWindow()
    return true
    #endif
}

// 1. 显示闪屏页
private func showSplashScreen() {
    let splashView = SplashScreenView { [weak self] in
        DispatchQueue.main.async {
            self?.showLoginScreen()
        }
    }

    let hostingController = UIHostingController(rootView: splashView)
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = hostingController
    window?.makeKeyAndVisible()
}

// 2. 显示登录页
private func showLoginScreen() {
    let loginView = LoginScreenView { [weak self] in
        DispatchQueue.main.async {
            self?.setupMainWindow()  // 进入 TG 原生登录
        }
    }

    let hostingController = UIHostingController(rootView: loginView)
    window?.rootViewController = hostingController
}

// 3. 进入 TG 原生登录流程（已存在的方法）
private func setupMainWindow() {
    // Telegram 原生登录逻辑
}
#endif
```

**关键点**：
- 使用 `window?.rootViewController` 替换而不是 push/present，保持视图层级扁平
- 每个阶段都是根视图替换，无需管理导航栈
- 条件编译 `ENABLE_WEB3_SPLASH` 保持不变，不影响 upstream 同步

## 未来扩展点

### 按钮 2 SDK 集成

当需要接入一键免密登录时，只需修改 `LoginViewModel.swift`：

```swift
@Published var isLoading: Bool = false
@Published var errorMessage: String?

func handleQuickAccess() {
    isLoading = true

    // 调用 SDK
    YourSDK.shared.quickLogin { [weak self] result in
        DispatchQueue.main.async {
            self?.isLoading = false
            switch result {
            case .success(let token):
                // 保存 token 到服务器
                self?.saveTokenToServer(token)
            case .failure(let error):
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}

private func saveTokenToServer(_ token: String) {
    // HTTP 请求到你的服务器
}
```

View 层可相应添加加载指示器：

```swift
QuickAccessButton(action: viewModel.handleQuickAccess)
    .disabled(viewModel.isLoading)
    .overlay(
        viewModel.isLoading ? ProgressView() : nil
    )
```

## 测试策略

### 单元测试

无需编写复杂测试，因为：
1. View 层是纯 SwiftUI 声明式代码
2. ViewModel 当前逻辑为空实现
3. 项目明确说明："App-side unit tests are minimal"（CLAUDE.md 第 61 行）

### 手动测试清单

1. **视觉还原**：与 HTML 原型对比截图，确认颜色、间距、圆角精确匹配
2. **多语言**：切换系统语言（中/英/日/韩），验证文案正确显示
3. **按钮 1 行为**：点击后进入 TG 原生登录流程
4. **按钮 2 行为**：点击无响应（或显示 Toast）
5. **闪屏衔接**：从闪屏页进入登录页过渡流畅
6. **不同屏幕尺寸**：iPhone SE、iPhone 14 Pro Max 布局自适应

## 风险与注意事项

### 风险

1. **颜色精度**：HTML 原型使用 Tailwind CSS，SwiftUI Color 需手动映射十六进制，可能存在微小色差
   - **缓解**：使用 ColorPalette 统一管理，已验证 `#24A1DE` 等关键色值

2. **SF Symbol 图标差异**：`paperplane.fill` 与 HTML 中的 FontAwesome `fa-telegram` 可能视觉略有不同
   - **缓解**：iOS 原生场景下 SF Symbol 更自然，或未来可引入自定义矢量图标

### 注意事项

- **不要修改 Telegram 原生登录流程**：`setupMainWindow()` 是黑盒，仅调用不修改
- **条件编译边界清晰**：所有 Web3 定制代码都在 `#if ENABLE_WEB3_SPLASH` 内
- **upstream 冲突最小化**：AppDelegate 只在条件编译块内新增私有方法

## 实现顺序

1. ✅ 在 `BUILD` 文件添加 `LoginScreenModule` target
2. ✅ 创建 `LoginViewModel.swift`（空实现）
3. ✅ 创建子组件（LogoView, TitleSectionView, 按钮组件等）
4. ✅ 创建 `LoginScreenView.swift` 主视图
5. ✅ 添加多语言文案（四种语言）
6. ✅ 修改 AppDelegate 集成代码
7. ✅ 编译验证（`./dev/run-simulator.sh`）
8. ✅ 手动测试与原型对比

## 成功标准

- [x] 视觉 1:1 还原 HTML 原型（颜色、间距、圆角、字体大小）
- [x] 按钮 1 点击正确进入 TG 原生登录
- [x] 按钮 2 预留接口（当前空实现）
- [x] 支持中英日韩四种语言
- [x] 闪屏 → 登录 → TG 登录流程平滑衔接
- [x] 条件编译开关正常工作（`--define=ENABLE_WEB3_SPLASH=true`）
- [x] 代码架构与闪屏页保持一致（MVVM + SwiftUI）

## 参考资料

- HTML 原型：`/Users/jade/code/code/telegram/web3_telegram_super_app_prototype.html` (第 218-240 行)
- 现有闪屏页实现：`submodules/TelegramCustom/Sources/Features/SplashScreen/`
- 色板定义：`submodules/TelegramCustom/Sources/Core/Utils/ColorPalette.swift`
- 项目 README：`submodules/TelegramCustom/README.md`
