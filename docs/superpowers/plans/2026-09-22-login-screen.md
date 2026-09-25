# A02 登录页面实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Web3 × Telegram 的 A02 登录页面，1:1 还原 HTML 原型，集成到闪屏页与 TG 原生登录之间

**Architecture:** MVVM + SwiftUI 架构，与现有 SplashScreen 保持一致。创建 LoginScreenModule，包含 LoginScreenView（主视图）、LoginViewModel（业务逻辑）和 5 个子组件（Logo、标题、两个按钮、法律文案）。复用 TelegramCustomCore 的色板和多语言工具。

**Tech Stack:** SwiftUI (iOS 14+), Bazel 构建系统, 无第三方依赖

---

## 文件结构规划

**新增文件：**
- `submodules/TelegramCustom/Sources/Features/LoginScreen/ViewModels/LoginViewModel.swift` - 业务逻辑（当前为占位）
- `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/LoginScreenView.swift` - 主视图容器
- `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LogoView.swift` - Logo 图标组件
- `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TitleSectionView.swift` - 标题区域
- `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TelegramLoginButton.swift` - 按钮1（蓝色）
- `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/QuickAccessButton.swift` - 按钮2（灰色边框）
- `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LegalTextView.swift` - 法律声明文案

**修改文件：**
- `submodules/TelegramCustom/BUILD` - 添加 LoginScreenModule target
- `submodules/TelegramCustom/Resources/Localizations/zh-Hans.lproj/Localizable.strings` - 追加中文文案
- `submodules/TelegramCustom/Resources/Localizations/en.lproj/Localizable.strings` - 追加英文文案
- `submodules/TelegramCustom/Resources/Localizations/ja.lproj/Localizable.strings` - 追加日文文案
- `submodules/TelegramCustom/Resources/Localizations/ko.lproj/Localizable.strings` - 追加韩文文案

---

## Task 1: 创建目录结构与 ViewModel

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/ViewModels/LoginViewModel.swift`
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/` (目录)

- [ ] **Step 1: 创建 LoginScreen 目录结构**

```bash
mkdir -p submodules/TelegramCustom/Sources/Features/LoginScreen/ViewModels
mkdir -p submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components
```

- [ ] **Step 2: 编写 LoginViewModel.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/ViewModels/LoginViewModel.swift`:

```swift
import Foundation

@available(iOS 14.0, *)
public class LoginViewModel: ObservableObject {

    public init() {}

    /// 处理一键免密登录（当前为占位实现）
    public func handleQuickAccess() {
        // TODO: 未来接入 SDK 和服务器 token 逻辑
        // 当前实现：仅打印日志，不做任何 UI 响应
        print("[LoginViewModel] 一键免密接入功能待开发")
    }
}
```

- [ ] **Step 3: 验证目录结构**

运行：
```bash
ls -la submodules/TelegramCustom/Sources/Features/LoginScreen/ViewModels/
ls -la submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/
```

预期输出：显示 LoginViewModel.swift 和 Components 目录

- [ ] **Step 4: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/
git commit -m "feat(login): add LoginViewModel with placeholder for quick access"
```

---

## Task 2: 实现 LogoView 组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LogoView.swift`

- [ ] **Step 1: 编写 LogoView.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LogoView.swift`:

```swift
import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
struct LogoView: View {
    var body: some View {
        ZStack {
            // 容器：80×80pt 圆角方块
            RoundedRectangle(cornerRadius: 24)
                .fill(ColorPalette.surface2)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(ColorPalette.brandNeon, lineWidth: 1)
                )
                .shadow(color: ColorPalette.brandNeon.opacity(0.25), radius: 10, x: 0, y: 0)

            // Telegram 图标
            Image(systemName: "paperplane.fill")
                .font(.system(size: 40))
                .foregroundColor(ColorPalette.brandNeon)
        }
    }
}
```

- [ ] **Step 2: 验证文件创建**

运行：
```bash
cat submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LogoView.swift | head -10
```

预期输出：显示文件前 10 行内容

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LogoView.swift
git commit -m "feat(login): add LogoView component with neon glow effect"
```

---

## Task 3: 实现 TitleSectionView 组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TitleSectionView.swift`

- [ ] **Step 1: 编写 TitleSectionView.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TitleSectionView.swift`:

```swift
import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
struct TitleSectionView: View {
    var body: some View {
        VStack(spacing: 8) {
            // 标题
            Text("login.title".localized)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(ColorPalette.textPrimary)

            // 副标题
            Text("login.subtitle".localized)
                .font(.system(size: 14))
                .foregroundColor(ColorPalette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
        }
    }
}
```

- [ ] **Step 2: 验证文件创建**

运行：
```bash
cat submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TitleSectionView.swift
```

预期输出：显示完整文件内容

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TitleSectionView.swift
git commit -m "feat(login): add TitleSectionView with title and subtitle"
```

---

## Task 4: 实现 TelegramLoginButton 组件（按钮1）

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TelegramLoginButton.swift`

- [ ] **Step 1: 编写 TelegramLoginButton.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TelegramLoginButton.swift`:

```swift
import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
struct TelegramLoginButton: View {
    let action: () -> Void

    var body: some View {
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
```

- [ ] **Step 2: 验证文件创建**

运行：
```bash
wc -l submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TelegramLoginButton.swift
```

预期输出：约 28 行

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/TelegramLoginButton.swift
git commit -m "feat(login): add TelegramLoginButton with blue background"
```

---

## Task 5: 实现 QuickAccessButton 组件（按钮2）

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/QuickAccessButton.swift`

- [ ] **Step 1: 编写 QuickAccessButton.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/QuickAccessButton.swift`:

```swift
import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
struct QuickAccessButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16))

                Text("login.button.quick".localized)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(ColorPalette.brandNeon)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(ColorPalette.surface2)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ColorPalette.borderClr, lineWidth: 1)
            )
        }
    }
}
```

- [ ] **Step 2: 验证文件创建**

运行：
```bash
grep -n "QuickAccessButton" submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/QuickAccessButton.swift
```

预期输出：显示包含 QuickAccessButton 的行号

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/QuickAccessButton.swift
git commit -m "feat(login): add QuickAccessButton with border style"
```

---

## Task 6: 实现 LegalTextView 组件

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LegalTextView.swift`

- [ ] **Step 1: 编写 LegalTextView.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LegalTextView.swift`:

```swift
import SwiftUI
import TelegramCustomCore

@available(iOS 14.0, *)
struct LegalTextView: View {
    var body: some View {
        Text("login.legal".localized)
            .font(.system(size: 11))
            .foregroundColor(ColorPalette.txtMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}
```

- [ ] **Step 2: 验证文件创建**

运行：
```bash
cat submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LegalTextView.swift
```

预期输出：显示完整文件内容

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/Views/Components/LegalTextView.swift
git commit -m "feat(login): add LegalTextView for terms and privacy notice"
```

---

## Task 7: 实现 LoginScreenView 主视图

**Files:**
- Create: `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/LoginScreenView.swift`

- [ ] **Step 1: 编写 LoginScreenView.swift**

创建文件 `submodules/TelegramCustom/Sources/Features/LoginScreen/Views/LoginScreenView.swift`:

```swift
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

- [ ] **Step 2: 验证文件创建**

运行：
```bash
wc -l submodules/TelegramCustom/Sources/Features/LoginScreen/Views/LoginScreenView.swift
```

预期输出：约 44 行

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Sources/Features/LoginScreen/Views/LoginScreenView.swift
git commit -m "feat(login): add LoginScreenView main container"
```

---

## Task 8: 添加多语言文案（中文）

**Files:**
- Modify: `submodules/TelegramCustom/Resources/Localizations/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 在中文语言文件末尾追加登录页文案**

在 `submodules/TelegramCustom/Resources/Localizations/zh-Hans.lproj/Localizable.strings` 文件末尾追加：

```
/* 登录页 */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "去中心化 Web3 生态与轻量社交的融合体。\n继续使用原有账号、联系人与群组。";
"login.button.telegram" = "Telegram 账号快捷登录";
"login.button.quick" = "一键免密接入 (快速体验)";
"login.legal" = "登录即代表您同意《服务条款》与《隐私政策》";
"login.quick.coming_soon" = "功能开发中，敬请期待";
```

- [ ] **Step 2: 验证文案添加**

运行：
```bash
grep "login.title" submodules/TelegramCustom/Resources/Localizations/zh-Hans.lproj/Localizable.strings
```

预期输出：`"login.title" = "Web3 × Telegram";`

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Resources/Localizations/zh-Hans.lproj/Localizable.strings
git commit -m "feat(login): add Chinese localization strings"
```

---

## Task 9: 添加多语言文案（英文）

**Files:**
- Modify: `submodules/TelegramCustom/Resources/Localizations/en.lproj/Localizable.strings`

- [ ] **Step 1: 在英文语言文件末尾追加登录页文案**

在 `submodules/TelegramCustom/Resources/Localizations/en.lproj/Localizable.strings` 文件末尾追加：

```
/* Login Screen */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "Decentralized Web3 ecosystem integrated with lightweight messaging.\nContinue with your existing account, contacts, and groups.";
"login.button.telegram" = "Quick Login with Telegram";
"login.button.quick" = "One-Click Access (Quick Start)";
"login.legal" = "By logging in, you agree to our Terms of Service and Privacy Policy";
"login.quick.coming_soon" = "Feature coming soon";
```

- [ ] **Step 2: 验证文案添加**

运行：
```bash
grep "login.button.telegram" submodules/TelegramCustom/Resources/Localizations/en.lproj/Localizable.strings
```

预期输出：`"login.button.telegram" = "Quick Login with Telegram";`

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Resources/Localizations/en.lproj/Localizable.strings
git commit -m "feat(login): add English localization strings"
```

---

## Task 10: 添加多语言文案（日文）

**Files:**
- Modify: `submodules/TelegramCustom/Resources/Localizations/ja.lproj/Localizable.strings`

- [ ] **Step 1: 在日文语言文件末尾追加登录页文案**

在 `submodules/TelegramCustom/Resources/Localizations/ja.lproj/Localizable.strings` 文件末尾追加：

```
/* ログイン画面 */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "分散型Web3エコシステムと軽量なメッセージングの融合。\n既存のアカウント、連絡先、グループを引き続き使用できます。";
"login.button.telegram" = "Telegramアカウントでログイン";
"login.button.quick" = "ワンクリックアクセス（クイックスタート）";
"login.legal" = "ログインすることで、利用規約とプライバシーポリシーに同意したものとみなされます";
"login.quick.coming_soon" = "機能開発中";
```

- [ ] **Step 2: 验证文案添加**

运行：
```bash
grep "login.title" submodules/TelegramCustom/Resources/Localizations/ja.lproj/Localizable.strings
```

预期输出：`"login.title" = "Web3 × Telegram";`

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Resources/Localizations/ja.lproj/Localizable.strings
git commit -m "feat(login): add Japanese localization strings"
```

---

## Task 11: 添加多语言文案（韩文）

**Files:**
- Modify: `submodules/TelegramCustom/Resources/Localizations/ko.lproj/Localizable.strings`

- [ ] **Step 1: 在韩文语言文件末尾追加登录页文案**

在 `submodules/TelegramCustom/Resources/Localizations/ko.lproj/Localizable.strings` 文件末尾追加：

```
/* 로그인 화면 */
"login.title" = "Web3 × Telegram";
"login.subtitle" = "분산형 Web3 생태계와 가벼운 메시징의 융합.\n기존 계정, 연락처 및 그룹을 계속 사용하세요.";
"login.button.telegram" = "Telegram 계정으로 빠른 로그인";
"login.button.quick" = "원클릭 액세스 (빠른 시작)";
"login.legal" = "로그인하면 서비스 약관 및 개인정보 보호정책에 동의하는 것으로 간주됩니다";
"login.quick.coming_soon" = "기능 개발 중";
```

- [ ] **Step 2: 验证文案添加**

运行：
```bash
grep "login.button.quick" submodules/TelegramCustom/Resources/Localizations/ko.lproj/Localizable.strings
```

预期输出：`"login.button.quick" = "원클릭 액세스 (빠른 시작)";`

- [ ] **Step 3: 提交**

```bash
git add submodules/TelegramCustom/Resources/Localizations/ko.lproj/Localizable.strings
git commit -m "feat(login): add Korean localization strings"
```

---

## Task 12: 更新 BUILD 文件添加 LoginScreenModule

**Files:**
- Modify: `submodules/TelegramCustom/BUILD`

- [ ] **Step 1: 读取当前 BUILD 文件**

运行：
```bash
cat submodules/TelegramCustom/BUILD
```

预期输出：显示现有的 SplashScreenModule 配置

- [ ] **Step 2: 在 SplashScreenModule 之后添加 LoginScreenModule**

在 `# 开屏页模块` 之后、`# 多语言资源` 之前插入：

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
```

- [ ] **Step 3: 更新 TelegramCustom 统一导出的 deps**

将 `TelegramCustom` target 的 `deps` 从：

```python
deps = [
    ":TelegramCustomCore",
    ":SplashScreenModule",
],
```

改为：

```python
deps = [
    ":TelegramCustomCore",
    ":SplashScreenModule",
    ":LoginScreenModule",
],
```

- [ ] **Step 4: 验证 BUILD 文件语法**

运行：
```bash
grep -A 3 "name = \"LoginScreenModule\"" submodules/TelegramCustom/BUILD
```

预期输出：显示 LoginScreenModule 配置

- [ ] **Step 5: 提交**

```bash
git add submodules/TelegramCustom/BUILD
git commit -m "build: add LoginScreenModule to Bazel configuration"
```

---

## Task 13: 编译验证 LoginScreenModule

**Files:**
- Test: `submodules/TelegramCustom/BUILD` (通过 Bazel 编译验证)

- [ ] **Step 1: 编译 LoginScreenModule**

运行：
```bash
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache build --configurationPath build-system/appstore-configuration.json --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git --gitCodesigningType development --gitCodesigningUseCurrent --buildNumber=1 --configuration=debug_sim_arm64
```

预期输出：编译成功，无错误

- [ ] **Step 2: 验证 LoginScreenModule 编译产物**

运行：
```bash
find bazel-bin -name "*LoginScreen*" -type f | head -5
```

预期输出：显示 LoginScreenModule 相关编译产物

- [ ] **Step 3: 如果编译失败，检查错误日志**

如果步骤 1 失败，运行：
```bash
cat /tmp/telegram-build-log.txt | tail -50
```

修正错误后重新编译

---

## Task 14: 集成登录页到 App 启动流程（AppDelegate 修改）

**Files:**
- Modify: `Telegram/Sources/AppDelegate.swift` (具体路径待确认)

**注意**：AppDelegate 的具体路径需要在项目中定位，通常在 `Telegram/Sources/` 下。以下步骤假设为 `Telegram/Sources/AppDelegate.swift`，如路径不同请相应调整。

- [ ] **Step 1: 定位 AppDelegate.swift**

运行：
```bash
find Telegram -name "AppDelegate.swift" -type f
```

预期输出：显示 AppDelegate.swift 的完整路径（记录此路径用于后续步骤）

- [ ] **Step 2: 备份 AppDelegate.swift**

运行：
```bash
cp Telegram/Sources/AppDelegate.swift Telegram/Sources/AppDelegate.swift.bak
```

- [ ] **Step 3: 在 AppDelegate 中找到闪屏页集成代码**

运行：
```bash
grep -n "ENABLE_WEB3_SPLASH" Telegram/Sources/AppDelegate.swift | head -10
```

预期输出：显示 `#if ENABLE_WEB3_SPLASH` 所在行号

- [ ] **Step 4: 修改 AppDelegate.swift 添加登录页集成**

找到 `#if ENABLE_WEB3_SPLASH` 代码块，将：

```swift
let splashView = SplashScreenView {
    DispatchQueue.main.async { [weak self] in
        self?.setupMainWindow()
    }
}
```

改为：

```swift
let splashView = SplashScreenView { [weak self] in
    DispatchQueue.main.async {
        self?.showLoginScreen()
    }
}
```

然后在 `#if ENABLE_WEB3_SPLASH` 块内添加新方法：

```swift
private func showLoginScreen() {
    let loginView = LoginScreenView { [weak self] in
        DispatchQueue.main.async {
            self?.setupMainWindow()
        }
    }

    let hostingController = UIHostingController(rootView: loginView)
    window?.rootViewController = hostingController
}
```

- [ ] **Step 5: 验证修改**

运行：
```bash
grep -A 8 "showLoginScreen" Telegram/Sources/AppDelegate.swift
```

预期输出：显示新增的 showLoginScreen 方法

- [ ] **Step 6: 删除备份文件**

运行：
```bash
rm Telegram/Sources/AppDelegate.swift.bak
```

- [ ] **Step 7: 提交**

```bash
git add Telegram/Sources/AppDelegate.swift
git commit -m "feat(app): integrate LoginScreen between splash and TG native login"
```

---

## Task 15: 完整编译并运行模拟器验证

**Files:**
- Test: 完整 App 编译与运行

- [ ] **Step 1: 完整编译 App**

运行：
```bash
./dev/run-simulator.sh
```

预期输出：编译成功，模拟器启动

- [ ] **Step 2: 观察启动流程**

在模拟器中观察：
1. 显示闪屏页（3秒倒计时或点击按钮）
2. 闪屏页完成后进入登录页
3. 登录页显示 Logo、标题、两个按钮、法律文案

- [ ] **Step 3: 测试按钮 1（Telegram 账号快捷登录）**

点击蓝色按钮，预期：进入 Telegram 原生登录流程

- [ ] **Step 4: 测试按钮 2（一键免密接入）**

如果重新启动到登录页，点击灰色边框按钮，预期：无 UI 响应（控制台打印日志）

- [ ] **Step 5: 检查控制台日志**

运行：
```bash
xcrun simctl spawn booted log stream --predicate 'processImagePath contains "Telegram"' --level debug | grep "LoginViewModel"
```

预期输出：如果点击了按钮 2，显示 `[LoginViewModel] 一键免密接入功能待开发`

- [ ] **Step 6: 测试多语言切换**

在模拟器中：设置 > 通用 > 语言与地区，切换到英文/日文/韩文，重启 App，验证登录页文案正确显示

- [ ] **Step 7: 截图对比 HTML 原型**

对比登录页与 HTML 原型 `screen-login`，验证：
- Logo 大小、圆角、发光效果
- 标题字体大小、颜色
- 按钮颜色、高度、圆角
- 间距是否 1:1 还原

- [ ] **Step 8: 如果发现视觉差异，记录并修正**

如果发现问题，修正对应组件文件后重新编译

---

## Task 16: 最终提交与文档更新

**Files:**
- Modify: `submodules/TelegramCustom/README.md` (可选)

- [ ] **Step 1: 验证所有文件已提交**

运行：
```bash
git status
```

预期输出：`nothing to commit, working tree clean`

- [ ] **Step 2: 查看提交历史**

运行：
```bash
git log --oneline --graph --all -15
```

预期输出：显示本次实施的所有提交记录

- [ ] **Step 3: （可选）更新 README.md**

在 `submodules/TelegramCustom/README.md` 的 "已实现功能" 部分添加：

```markdown
### 2. 登录页面（LoginScreen）

- ✅ 1:1 还原 HTML 原型设计
- ✅ Telegram 蓝色快捷登录按钮
- ✅ 一键免密接入占位按钮（待 SDK 集成）
- ✅ 支持中英日韩 4 种语言
- ✅ 纯 SwiftUI 原生实现（零第三方依赖）
```

- [ ] **Step 4: 提交 README 更新（如果修改了）**

```bash
git add submodules/TelegramCustom/README.md
git commit -m "docs: update README with LoginScreen feature"
```

- [ ] **Step 5: 推送到远程仓库**

运行：
```bash
git push origin master
```

预期输出：推送成功

---

## 验收清单

完成所有任务后，验证以下成功标准：

- [ ] **视觉还原**：登录页与 HTML 原型视觉 1:1 匹配（颜色、间距、圆角、字体）
- [ ] **按钮 1 行为**：点击 "Telegram 账号快捷登录" 进入 TG 原生登录
- [ ] **按钮 2 占位**：点击 "一键免密接入" 无 UI 响应（控制台有日志）
- [ ] **多语言支持**：切换系统语言（中/英/日/韩）文案正确显示
- [ ] **流程衔接**：闪屏页 → 登录页 → TG 登录平滑过渡
- [ ] **编译成功**：`./dev/run-simulator.sh` 无错误
- [ ] **代码架构**：MVVM 架构与 SplashScreen 保持一致
- [ ] **Git 提交**：所有更改已提交，提交信息清晰

---

## 故障排查

### 问题 1: 编译错误 "Cannot find 'ColorPalette' in scope"

**原因**：LoginScreenModule 未正确依赖 TelegramCustomCore

**解决**：检查 `BUILD` 文件中 LoginScreenModule 的 `deps` 是否包含 `:TelegramCustomCore`

### 问题 2: 运行时闪退 "Could not find resource bundle"

**原因**：多语言资源未正确打包

**解决**：检查 `BUILD` 文件中 LoginScreenModule 的 `data` 是否包含 `glob(["Resources/Localizations/**/*.strings"])`

### 问题 3: 按钮点击无响应

**原因**：回调未正确传递或 ViewModel 方法未调用

**解决**：
1. 检查 LoginScreenView 的 `onTelegramLogin` 回调是否正确传递给 TelegramLoginButton
2. 检查 QuickAccessButton 是否调用 `viewModel.handleQuickAccess`

### 问题 4: 文案显示为 key 而不是翻译文本

**原因**：LocalizationManager 未找到对应 key

**解决**：
1. 检查 `.strings` 文件中 key 是否正确（如 `"login.title"`）
2. 确认使用 `.localized` 扩展方法
3. 清理 Bazel 缓存后重新编译：`bazel clean --expunge`

### 问题 5: AppDelegate 修改后编译失败

**原因**：import 语句缺失或语法错误

**解决**：
1. 确保 AppDelegate 顶部有 `import TelegramCustom` 和 `import SwiftUI`
2. 检查 `showLoginScreen()` 方法是否在 `#if ENABLE_WEB3_SPLASH` 块内
3. 恢复备份文件：`cp Telegram/Sources/AppDelegate.swift.bak Telegram/Sources/AppDelegate.swift`
