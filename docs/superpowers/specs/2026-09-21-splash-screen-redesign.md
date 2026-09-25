# u多担保开屏页 1:1 还原设计文档

**日期**: 2026-09-21
**目标**: 完全1:1还原HTML原型中的u多担保开屏页（A01），采用纯SwiftUI实现，组件化架构

---

## 一、项目背景

### 需求
- 将 `/Users/jade/code/code/telegram/web3_telegram_super_app_prototype.html` 中的开屏广告页（A01）完全还原到iOS app
- 支持中文、英文、日文、韩文4种语言本地化
- 使用纯SwiftUI实现，0张图片资源
- 组件化设计，公共能力抽取复用
- 符合条件编译要求，不与upstream冲突

### HTML原型分析
开屏页包含以下视觉元素：
1. **复杂背景层**: 多个渐变发光球 + 网格线 + blur效果
2. **Logo区域**: Shield图标 + USDT徽章 + OFFICIAL角标 + 认证勾选
3. **文案区域**: 主标题（渐变文字）+ 副标题 + feature标签行
4. **交互元素**: 跳过按钮（倒计时）+ 荧光按钮
5. **所有元素均为纯CSS/FontAwesome实现，无图片资源**

---

## 二、技术方案

### 方案选择
**纯SwiftUI实现**（方案A）
- 所有HTML效果用SwiftUI原生能力实现
- 0张图片，完全矢量绘制
- 组件化架构，易于维护和复用

**技术映射**:
| HTML元素 | SwiftUI实现 |
|---------|------------|
| `fa-shield-halved` | SF Symbol: `shield.lefthalf.filled` |
| 渐变球 + blur | `RadialGradient` + `.blur()` |
| 网格线 | 自定义`Shape` 画线 |
| 渐变文字 | `.foregroundStyle(LinearGradient)` |
| 发光效果 | `.shadow(color:radius:)` |
| 动画 | `withAnimation` + `@State` |

---

## 三、架构设计

### 目录结构
```
submodules/TelegramCustom/
├── Sources/
│   ├── Core/
│   │   ├── Constants/
│   │   │   ├── AppConstants.swift         (已有)
│   │   │   └── LayoutConstants.swift      (已有)
│   │   ├── Utils/
│   │   │   ├── ColorPalette.swift         (扩展新颜色)
│   │   │   └── LocalizationManager.swift  (已有)
│   │   └── Components/                     (新增)
│   │       ├── Backgrounds/
│   │       │   ├── GradientOrbView.swift       (渐变发光球)
│   │       │   ├── GridPatternView.swift       (网格背景)
│   │       │   └── AnimatedBackgroundView.swift (完整背景组合)
│   │       ├── Badges/
│   │       │   ├── OfficialBadgeView.swift     (OFFICIAL徽章)
│   │       │   ├── FeaturePillView.swift       (feature标签)
│   │       │   └── VerifiedCheckmarkView.swift (认证勾选)
│   │       ├── Buttons/
│   │       │   ├── NeonButtonView.swift        (荧光按钮)
│   │       │   └── SkipButtonView.swift        (跳过按钮)
│   │       └── Shapes/
│   │           └── GridPattern.swift           (网格Shape)
│   └── Features/
│       └── SplashScreen/
│           ├── Views/
│           │   ├── SplashScreenView.swift      (主视图-组装)
│           │   └── SplashLogoSectionView.swift (logo区域)
│           └── ViewModels/
│               └── SplashViewModel.swift       (已有)
```

### 组件职责

#### 1. **背景层组件**
- `GridPattern.swift`: 自定义Shape，绘制24px网格线
- `GradientOrbView.swift`: 可配置的渐变发光球（位置、大小、颜色、动画）
- `AnimatedBackgroundView.swift`: 组合3个发光球 + 网格层

#### 2. **徽章组件**
- `OfficialBadgeView.swift`: OFFICIAL角标（荧光绿背景+黑色文字）
- `VerifiedCheckmarkView.swift`: 认证勾选（图标+文案+半透明背景）
- `FeaturePillView.swift`: 功能标签（图标+文字+边框）

#### 3. **按钮组件**
- `SkipButtonView.swift`: 跳过按钮（半透明+边框+倒计时）
- `NeonButtonView.swift`: 荧光按钮（渐变+发光+图标）

#### 4. **视图组件**
- `SplashLogoSectionView.swift`: Logo区域（Shield+USDT+OFFICIAL+认证+标题+副标题+标签）
- `SplashScreenView.swift`: 主视图（背景+Logo+按钮，组装所有组件）

---

## 四、核心组件实现细节

### 1. ColorPalette 扩展
新增HTML原型中的颜色：
```swift
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

### 2. 网格背景实现
```swift
public struct GridPattern: Shape {
    public let spacing: CGFloat

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

### 3. 渐变发光球
- 使用 `RadialGradient` 创建中心向外的渐变
- `.blur(radius: 60)` 实现发光效果
- 左上角球：`animate: true`，3秒缓动循环动画
- 右下角球、中央球：静态

### 4. 渐变文字
使用 `.foregroundStyle(LinearGradient)` 实现三色渐变：
```swift
.foregroundStyle(
    LinearGradient(
        colors: [ColorPalette.brandNeon, .white, ColorPalette.brandNeon.opacity(0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )
)
```

### 5. Logo区域层次
```
ZStack {
  外层发光blur (RoundedRectangle + blur + animate)
  主容器 (渐变背景 + 边框 + 双层阴影)
  Shield图标 (SF Symbol)
  USDT徽章 (Text + Capsule背景)
  OFFICIAL角标 (OfficialBadgeView，右上角offset)
}
```

### 6. 按钮发光效果
荧光按钮使用双层阴影：
```swift
.shadow(color: ColorPalette.brandNeon.opacity(0.4), radius: 10, x: 0, y: 4)  // 荧光晕
.shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)                // 深度阴影
```

---

## 五、本地化字符串

### 新增Key（4语言）

**中文 (zh-Hans.lproj/Localizable.strings)**:
```
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

**英文 (en.lproj/Localizable.strings)**:
```
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

**日文 (ja.lproj/Localizable.strings)**:
```
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

**韩文 (ko.lproj/Localizable.strings)**:
```
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

---

## 六、性能优化

### 1. 渲染优化
- 网格层使用 `.drawingGroup()` 提升路径绘制性能
- blur半径限制在 ≤60，避免过度GPU消耗

### 2. 动画优化
- 使用 `.animation().repeatForever()` 而非Timer
- 只对左上角发光球启用动画，其他静态

### 3. 内存优化
- 所有组件为值类型（struct）
- 无图片资源，无内存加载开销

---

## 七、AppDelegate 集成

保持现有集成方式不变：
```swift
#if ENABLE_WEB3_SPLASH
if #available(iOS 14.0, *) {
    DispatchQueue.main.async { [weak self] in
        guard let self = self, let mainWindow = self.window else { return }
        let splashView = SplashScreenView {
            DispatchQueue.main.async {
                if let splashWindow = self.splashWindow {
                    splashWindow.isHidden = true
                    self.splashWindow = nil
                }
                mainWindow.makeKeyAndVisible()
            }
        }
        let splashController = UIHostingController(rootView: splashView)
        splashController.view.backgroundColor = .black
        let splashWindow = UIWindow(frame: UIScreen.main.bounds)
        splashWindow.windowLevel = .alert + 1
        splashWindow.rootViewController = splashController
        splashWindow.makeKeyAndVisible()
        self.splashWindow = splashWindow
    }
}
#endif
```

---

## 八、验收标准

### 视觉还原度
- [ ] 背景渐变球位置、颜色、blur效果与HTML一致
- [ ] 网格线密度24px，透明度70%
- [ ] Logo发光效果与HTML一致
- [ ] USDT徽章、OFFICIAL角标位置准确
- [ ] 渐变文字三色过渡自然
- [ ] 按钮发光效果明显
- [ ] 所有圆角、间距与HTML原型误差 < 2px

### 功能完整性
- [ ] 3秒倒计时自动跳转
- [ ] 跳过按钮点击立即跳转
- [ ] 进入按钮点击跳转
- [ ] 左上角发光球动画流畅（3秒循环）
- [ ] 4种语言文案正确显示

### 性能指标
- [ ] 启动到开屏显示 < 200ms
- [ ] 动画帧率 ≥ 60fps
- [ ] 内存占用 < 10MB

### 代码质量
- [ ] 所有组件独立可复用
- [ ] 无硬编码字符串（全部本地化）
- [ ] 无硬编码颜色（全部ColorPalette）
- [ ] 遵循SwiftUI最佳实践
- [ ] 代码通过Bazel编译

---

## 九、未来扩展

### 可复用组件
以下组件可用于其他页面：
- `NeonButtonView`: 任何需要荧光按钮的页面
- `FeaturePillView`: 功能标签展示
- `OfficialBadgeView`: 官方认证标识
- `AnimatedBackgroundView`: 任何需要科技感背景的页面

### 动画增强（可选）
- Logo缩放+旋转进场动画
- 文字逐行淡入
- 按钮呼吸效果

### A/B测试（可选）
- 倒计时时长可配置（3s/5s）
- 不同品牌主题切换（保留架构，替换颜色）

---

## 十、风险与依赖

### 技术风险
- **无风险**: SwiftUI所有能力均为iOS 14+原生支持

### 依赖
- iOS 14.0+
- SF Symbols（系统内置）
- 无第三方库依赖

### 上游冲突
- **无冲突**: 所有代码在 `submodules/TelegramCustom/` 独立模块
- 条件编译 `#if ENABLE_WEB3_SPLASH` 隔离

---

## 十一、实施计划

### 阶段1: 基础组件（2-3小时）
1. 扩展 ColorPalette
2. 实现 GridPattern + GridPatternView
3. 实现 GradientOrbView
4. 实现 AnimatedBackgroundView
5. 新增本地化字符串（4语言）

### 阶段2: UI组件（2-3小时）
1. 实现 OfficialBadgeView
2. 实现 FeaturePillView
3. 实现 VerifiedCheckmarkView
4. 实现 SkipButtonView
5. 实现 NeonButtonView

### 阶段3: 视图组装（1-2小时）
1. 实现 SplashLogoSectionView
2. 更新 SplashScreenView（替换现有实现）
3. 集成测试

### 阶段4: 验收（1小时）
1. 视觉对比HTML原型
2. 4语言测试
3. 性能测试
4. 提交commit

**总预计**: 6-9小时

---

## 十二、参考资料

- HTML原型: `/Users/jade/code/code/telegram/web3_telegram_super_app_prototype.html` (lines 147-215)
- 现有实现: `submodules/TelegramCustom/Sources/Features/SplashScreen/Views/SplashScreenView.swift`
- 颜色系统: `submodules/TelegramCustom/Sources/Core/Utils/ColorPalette.swift`
- SF Symbols: https://developer.apple.com/sf-symbols/
