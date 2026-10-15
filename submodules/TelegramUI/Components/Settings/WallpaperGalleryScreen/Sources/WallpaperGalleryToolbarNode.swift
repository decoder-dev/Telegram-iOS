import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ManagedAnimationNode
import ComponentFlow
import PremiumLockButtonSubtitleComponent
import ButtonComponent
import MultilineTextComponent

public enum WallpaperGalleryToolbarCancelButtonType {
    case cancel
    case discard
}

public enum WallpaperGalleryToolbarDoneButtonType {
    case set
    case setPeer(String, Bool)
    case setChannel
    case proceed
    case apply
    case none
}

public protocol WallpaperGalleryToolbar: ASDisplayNode {
    var cancelButtonType: WallpaperGalleryToolbarCancelButtonType { get set }
    var doneButtonType: WallpaperGalleryToolbarDoneButtonType { get set }

    var cancel: (() -> Void)? { get set }
    var done: ((Bool) -> Void)? { get set }

    func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings)

    func updateLayout(size: CGSize, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition)
}

public final class WallpaperGalleryToolbarNode: ASDisplayNode, WallpaperGalleryToolbar {
    class ButtonNode: ASDisplayNode {
        private var strings: PresentationStrings
        private var theme: PresentationTheme?
        private var title: String = ""
        private var enabled: Bool = true

        private let doneButton = HighlightTrackingButtonNode()
        private var doneButtonBackgroundNode: WallpaperOptionBackgroundNode
        private let doneButtonTitleNode: ImmediateTextNode
        private var doneButtonSubtitle: ComponentView<Empty>?

        private let doneButtonSolidBackgroundNode: ASDisplayNode
        private let doneButtonSolidTitleNode: ImmediateTextNode

        private let animationNode: SimpleAnimationNode

        var action: () -> Void = {}

        var isLocked: Bool = false {
            didSet {
                self.animationNode.isHidden = !self.isLocked
                if self.isLocked != oldValue, !self.bounds.isEmpty {
                    self.updateSize(self.bounds.size)
                }
            }
        }

        var requiredLevel: Int? {
            didSet {
                if self.requiredLevel != oldValue, !self.bounds.isEmpty {
                    self.updateSize(self.bounds.size)
                }
            }
        }

        init(strings: PresentationStrings) {
            self.strings = strings

            self.doneButtonBackgroundNode = WallpaperOptionBackgroundNode(isDark: false)

            self.doneButtonTitleNode = ImmediateTextNode()
            self.doneButtonTitleNode.displaysAsynchronously = false
            self.doneButtonTitleNode.isUserInteractionEnabled = false

            self.doneButtonSolidBackgroundNode = ASDisplayNode()
            self.doneButtonSolidBackgroundNode.alpha = 0.0
            self.doneButtonSolidBackgroundNode.clipsToBounds = true
            self.doneButtonSolidBackgroundNode.layer.cornerRadius = 26.0
            if #available(iOS 13.0, *) {
                self.doneButtonSolidBackgroundNode.layer.cornerCurve = .continuous
            }
            self.doneButtonSolidBackgroundNode.isUserInteractionEnabled = false

            self.doneButtonSolidTitleNode = ImmediateTextNode()
            self.doneButtonSolidTitleNode.alpha = 0.0
            self.doneButtonSolidTitleNode.displaysAsynchronously = false
            self.doneButtonSolidTitleNode.isUserInteractionEnabled = false

            self.animationNode = SimpleAnimationNode(animationName: "premium_unlock", size: CGSize(width: 30.0, height: 30.0), lottieSettings: .noAccountFallback)
            self.animationNode.customColor = .white
            self.animationNode.isHidden = true

            super.init()

            self.doneButton.isExclusiveTouch = true

            self.addSubnode(self.doneButtonBackgroundNode)
            self.doneButtonBackgroundNode.contentView.addSubnode(self.doneButtonTitleNode)

            self.addSubnode(self.doneButtonSolidBackgroundNode)
            self.addSubnode(self.doneButtonSolidTitleNode)

            self.addSubnode(self.animationNode)

            self.view.addSubview(self.doneButton.view)

            self.doneButton.addTarget(self, action: #selector(self.pressed), forControlEvents: .touchUpInside)
        }

        func setEnabled(_ enabled: Bool) {
            self.enabled = enabled
            self.doneButton.isEnabled = enabled
            self.doneButton.isUserInteractionEnabled = enabled
            self.doneButton.accessibilityTraits = enabled ? .button : [.button, .notEnabled]
            self.updateContentAlpha(transition: .immediate)
        }

        private var isSolid = false
        func setIsSolid(_ isSolid: Bool, transition: ContainedViewLayoutTransition) {
            guard self.isSolid != isSolid else {
                return
            }
            self.isSolid = isSolid
            self.updateContentAlpha(transition: transition)
            self.updateColors()
        }

        private func updateContentAlpha(transition: ContainedViewLayoutTransition) {
            let alpha: CGFloat = self.enabled ? 1.0 : 0.4
            transition.updateAlpha(node: self.doneButtonBackgroundNode, alpha: self.isSolid ? 0.0 : alpha)
            transition.updateAlpha(node: self.doneButtonSolidBackgroundNode, alpha: self.isSolid ? alpha : 0.0)
            transition.updateAlpha(node: self.doneButtonTitleNode, alpha: self.isSolid ? 0.0 : 1.0)
            transition.updateAlpha(node: self.doneButtonSolidTitleNode, alpha: self.isSolid ? alpha : 0.0)
            transition.updateAlpha(node: self.animationNode, alpha: alpha)
            self.doneButtonSubtitle?.view?.alpha = alpha
        }

        func updateTitle(_ title: String, theme: PresentationTheme, strings: PresentationStrings) {
            self.title = title
            self.theme = theme
            self.strings = strings
            self.doneButton.isAccessibilityElement = true
            self.doneButton.accessibilityLabel = title
            self.updateColors()
        }

        private func updateColors() {
            guard let theme = self.theme else { return }
            self.doneButtonTitleNode.attributedText = NSAttributedString(string: self.title, font: Font.semibold(17.0), textColor: self.dark ? .white : .black)
            self.doneButtonSolidBackgroundNode.backgroundColor = theme.list.itemCheckColors.fillColor
            self.doneButtonSolidTitleNode.attributedText = NSAttributedString(string: self.title, font: Font.semibold(17.0), textColor: theme.list.itemCheckColors.foregroundColor)
            self.animationNode.customColor = self.isSolid ? theme.list.itemCheckColors.foregroundColor : self.dark ? .white : .black
            if !self.bounds.isEmpty {
                self.updateSize(self.bounds.size)
            }
        }

        func updateSize(_ size: CGSize) {
            let bounds = CGRect(origin: .zero, size: size)
            self.doneButtonBackgroundNode.frame = bounds
            self.doneButtonBackgroundNode.updateLayout(size: size)
            self.doneButtonSolidBackgroundNode.frame = bounds
            self.doneButtonSolidBackgroundNode.layer.cornerRadius = self.theme?.isMessagesTheme == true ? MessagesAppearanceMetrics.actionRadius(height: size.height) : size.height * 0.5

            let constrainedSize = CGSize(width: max(1.0, size.width - 44.0), height: size.height)
            let iconSize = CGSize(width: 30.0, height: 30.0)
            let doneTitleSize = self.doneButtonTitleNode.updateLayout(constrainedSize)

            var totalWidth = doneTitleSize.width
            if self.isLocked {
                totalWidth += iconSize.width + 1.0
            }
            let titleOriginX = floorToScreenPixels((bounds.width - totalWidth) / 2.0)

            self.animationNode.frame = CGRect(origin: CGPoint(x: titleOriginX, y: floorToScreenPixels((bounds.height - iconSize.height) / 2.0)), size: iconSize)

            var titleFrame = CGRect(origin: CGPoint(x: titleOriginX + totalWidth - doneTitleSize.width, y: floorToScreenPixels((bounds.height - doneTitleSize.height) / 2.0)), size: doneTitleSize).offsetBy(dx: bounds.minX, dy: bounds.minY)

            if let requiredLevel = self.requiredLevel {
                let subtitle: ComponentView<Empty>
                if let current = self.doneButtonSubtitle {
                    subtitle = current
                } else {
                    subtitle = ComponentView<Empty>()
                    self.doneButtonSubtitle = subtitle
                }

                let subtitleSize = subtitle.update(
                    transition: .immediate,
                    component: AnyComponent(
                        PremiumLockButtonSubtitleComponent(
                            count: requiredLevel,
                            color: (self.isSolid ? self.theme?.list.itemCheckColors.foregroundColor ?? .white : self.dark ? UIColor.white : UIColor.black).withAlphaComponent(self.theme?.isMessagesTheme == true ? 0.92 : 0.7),
                            strings: self.strings
                        )
                    ),
                    environment: {},
                    containerSize: size
                )

                if let view = subtitle.view {
                    if view.superview == nil {
                        view.isUserInteractionEnabled = false
                        self.view.addSubview(view)
                    }

                    titleFrame.origin.y -= 8.0

                    let subtitleFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - subtitleSize.width) / 2.0), y: titleFrame.maxY + 3.0), size: subtitleSize)
                    view.frame = subtitleFrame
                }
            } else if let subtitle = self.doneButtonSubtitle {
                subtitle.view?.removeFromSuperview()
                self.doneButtonSubtitle = nil
            }

            self.doneButtonTitleNode.frame = titleFrame

            let _ = self.doneButtonSolidTitleNode.updateLayout(constrainedSize)
            self.doneButtonSolidTitleNode.frame = self.doneButtonTitleNode.frame

            self.doneButton.frame = bounds
            self.doneButtonSubtitle?.view?.alpha = self.enabled ? 1.0 : 0.4
        }

        var dark: Bool = false {
            didSet {
                if self.dark != oldValue {
                    self.doneButtonBackgroundNode.isDark = self.dark
                    self.updateColors()
                }
            }
        }

        private var previousActionTime: Double?
        @objc func pressed() {
            let currentTime = CACurrentMediaTime()
            if let previousActionTime = self.previousActionTime, currentTime < previousActionTime + 1.0 {
                return
            }
            self.previousActionTime = currentTime
            self.action()
        }
    }

    private var theme: PresentationTheme
    private var strings: PresentationStrings

    public var cancelButtonType: WallpaperGalleryToolbarCancelButtonType {
        didSet {
            self.updateThemeAndStrings(theme: self.theme, strings: self.strings)
        }
    }
    public var doneButtonType: WallpaperGalleryToolbarDoneButtonType {
        didSet {
            self.updateThemeAndStrings(theme: self.theme, strings: self.strings)
        }
    }

    public var dark: Bool = false {
        didSet {
            self.applyButton.dark = self.dark
            self.applyForBothButton.dark = self.dark
        }
    }

    private let applyButton: ButtonNode
    private let applyForBothButton: ButtonNode

    public var cancel: (() -> Void)?
    public var done: ((Bool) -> Void)?

    var requiredLevel: Int? {
        didSet {
            self.applyButton.requiredLevel = self.requiredLevel
        }
    }

    public init(theme: PresentationTheme, strings: PresentationStrings, cancelButtonType: WallpaperGalleryToolbarCancelButtonType = .cancel, doneButtonType: WallpaperGalleryToolbarDoneButtonType = .set) {
        self.theme = theme
        self.strings = strings
        self.cancelButtonType = cancelButtonType
        self.doneButtonType = doneButtonType

        self.applyButton = ButtonNode(strings: strings)
        self.applyForBothButton = ButtonNode(strings: strings)

        super.init()

        self.addSubnode(self.applyButton)
        self.addSubnode(self.applyForBothButton)

        self.updateThemeAndStrings(theme: theme, strings: strings)

        self.applyButton.action = { [weak self] in
            if let self {
                self.done?(false)
            }
        }
        self.applyForBothButton.action = { [weak self] in
            if let self {
                self.done?(true)
            }
        }
    }

    public func setDoneEnabled(_ enabled: Bool) {
        self.applyButton.setEnabled(enabled)
        self.applyForBothButton.setEnabled(enabled)
    }

    private var isSolid = false
    public func setDoneIsSolid(_ isSolid: Bool, transition: ContainedViewLayoutTransition) {
        guard self.isSolid != isSolid else {
            return
        }

        self.isSolid = isSolid
        self.applyButton.setIsSolid(isSolid, transition: transition)
        self.applyForBothButton.setIsSolid(isSolid, transition: transition)
    }

    public func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        self.theme = theme
        self.strings = strings
        self.applyButton.isUserInteractionEnabled = true

        let applyTitle: String
        var applyForBothTitle: String? = nil
        var applyForBothLocked = false
        switch self.doneButtonType {
        case .set:
            applyTitle = strings.Wallpaper_ApplyForAll
        case let .setPeer(name, isPremium):
            applyTitle = strings.Wallpaper_ApplyForMe
            applyForBothTitle = strings.Wallpaper_ApplyForBoth(name).string
            applyForBothLocked = !isPremium
        case .setChannel:
            applyTitle = strings.Wallpaper_ApplyForChannel
        case .proceed:
            applyTitle = strings.Theme_Colors_Proceed
        case .apply:
            applyTitle = strings.WallpaperPreview_PatternPaternApply
        case .none:
            applyTitle = ""
            self.applyButton.isUserInteractionEnabled = false
        }

        self.applyButton.updateTitle(applyTitle, theme: theme, strings: strings)
        self.applyButton.isHidden = applyTitle.isEmpty
        self.applyButton.accessibilityElementsHidden = applyTitle.isEmpty
        if let applyForBothTitle {
            self.applyForBothButton.updateTitle(applyForBothTitle, theme: theme, strings: strings)
        }
        self.applyForBothButton.isLocked = applyForBothLocked
    }

    public func updateLayout(size: CGSize, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let inset: CGFloat = self.theme.isMessagesTheme ? 16.0 : 30.0
        let leftInset = inset + layout.safeInsets.left
        let rightInset = inset + layout.safeInsets.right
        let buttonHeight: CGFloat = 52.0

        let spacing: CGFloat = 8.0

        let applyFrame = CGRect(origin: CGPoint(x: leftInset, y: 2.0), size: CGSize(width: max(1.0, size.width - leftInset - rightInset), height: buttonHeight))
        let applyForBothFrame = CGRect(origin: CGPoint(x: leftInset, y: applyFrame.maxY + spacing), size: applyFrame.size)

        var showApplyForBothButton = false
        if case .setPeer = self.doneButtonType {
            showApplyForBothButton = true
        }
        transition.updateAlpha(node: self.applyForBothButton, alpha: showApplyForBothButton ? 1.0 : 0.0)
        self.applyForBothButton.isUserInteractionEnabled = showApplyForBothButton
        self.applyForBothButton.accessibilityElementsHidden = !showApplyForBothButton

        self.applyButton.frame = applyFrame
        self.applyButton.updateSize(applyFrame.size)
        self.applyForBothButton.frame = applyForBothFrame
        self.applyForBothButton.updateSize(applyForBothFrame.size)
    }

    @objc func cancelPressed() {
        self.cancel?()
    }
}

public final class WallpaperGalleryOldToolbarNode: ASDisplayNode, WallpaperGalleryToolbar {
    private var theme: PresentationTheme
    private var strings: PresentationStrings

    public var cancelButtonType: WallpaperGalleryToolbarCancelButtonType {
        didSet {
            self.updateThemeAndStrings(theme: self.theme, strings: self.strings)
        }
    }
    public var doneButtonType: WallpaperGalleryToolbarDoneButtonType {
        didSet {
            self.updateThemeAndStrings(theme: self.theme, strings: self.strings)
        }
    }

    private let cancelButton = ComponentView<Empty>()
    private let doneButton = ComponentView<Empty>()

    private var cancelTitle: String = ""
    private var doneTitle: String = ""
    private var doneEnabled: Bool = true
    private var validLayout: (CGSize, ContainerViewLayout)?

    public var cancel: (() -> Void)?
    public var done: ((Bool) -> Void)?

    public init(theme: PresentationTheme, strings: PresentationStrings, cancelButtonType: WallpaperGalleryToolbarCancelButtonType = .cancel, doneButtonType: WallpaperGalleryToolbarDoneButtonType = .set) {
        self.theme = theme
        self.strings = strings
        self.cancelButtonType = cancelButtonType
        self.doneButtonType = doneButtonType

        super.init()

        self.updateThemeAndStrings(theme: theme, strings: strings)
    }

    public func setDoneEnabled(_ enabled: Bool) {
        self.doneEnabled = enabled
        if let (size, layout) = self.validLayout {
            self.updateLayout(size: size, layout: layout, transition: .immediate)
        }
    }

    public func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        self.theme = theme
        self.strings = strings

        switch self.cancelButtonType {
            case .cancel:
                self.cancelTitle = strings.Common_Cancel
            case .discard:
                self.cancelTitle = strings.WallpaperPreview_PatternPaternDiscard
        }
        switch self.doneButtonType {
            case .set, .setPeer, .setChannel:
                self.doneTitle = strings.Wallpaper_Set
            case .proceed:
                self.doneTitle = strings.Theme_Colors_Proceed
            case .apply:
                self.doneTitle = strings.WallpaperPreview_PatternPaternApply
            case .none:
                self.doneTitle = ""
        }

        if let (size, layout) = self.validLayout {
            self.updateLayout(size: size, layout: layout, transition: .immediate)
        }
    }

    public func updateLayout(size: CGSize, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, layout)

        let usesMessages = self.theme.isMessagesTheme
        let sideInset: CGFloat = usesMessages ? 16.0 : 30.0
        let leftInset = sideInset + layout.safeInsets.left
        let rightInset = sideInset + layout.safeInsets.right
        let spacing: CGFloat = usesMessages ? 12.0 : 24.0
        let buttonHeight: CGFloat = 52.0
        let buttonWidth = floor(max(1.0, size.width - leftInset - rightInset - spacing) / 2.0)
        let buttonY = floor((size.height - buttonHeight) / 2.0)
        let cancelFrame = CGRect(x: leftInset, y: buttonY, width: buttonWidth, height: buttonHeight)
        let doneFrame = CGRect(x: cancelFrame.maxX + spacing, y: buttonY, width: max(1.0, size.width - rightInset - cancelFrame.maxX - spacing), height: buttonHeight)

        let glassColor = UIColor(white: 1.0, alpha: 0.0)
        let foregroundColor = self.theme.list.itemPrimaryTextColor
        let cancelColor = usesMessages ? self.theme.list.itemAccentColor : foregroundColor
        let doneColor = usesMessages ? self.theme.list.itemCheckColors.foregroundColor : foregroundColor
        let cornerRadius = usesMessages ? MessagesAppearanceMetrics.actionRadius(height: buttonHeight) : buttonHeight * 0.5
        let componentTransition = ComponentTransition(transition)

        let cancelSize = self.cancelButton.update(
            transition: componentTransition,
            component: AnyComponent(ButtonComponent(
                background: ButtonComponent.Background(
                    style: usesMessages ? .legacy : .actualGlass,
                    color: usesMessages ? self.theme.list.itemBlocksBackgroundColor : glassColor,
                    foreground: cancelColor,
                    pressedColor: usesMessages ? self.theme.list.itemHighlightedBackgroundColor : glassColor,
                    cornerRadius: cornerRadius
                ),
                content: AnyComponentWithIdentity(
                    id: AnyHashable(self.cancelTitle),
                    component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: self.cancelTitle, font: Font.semibold(17.0), textColor: cancelColor)), horizontalAlignment: .center, maximumNumberOfLines: usesMessages ? 2 : 1))
                ),
                action: { [weak self] in
                    self?.cancel?()
                }
            )),
            environment: {},
            containerSize: cancelFrame.size
        )
        if let cancelView = self.cancelButton.view {
            if cancelView.superview == nil {
                self.view.addSubview(cancelView)
            }
            transition.updateFrame(view: cancelView, frame: CGRect(origin: cancelFrame.origin, size: cancelSize))
            cancelView.isAccessibilityElement = true
            cancelView.accessibilityLabel = self.cancelTitle
            cancelView.accessibilityTraits = .button
        }

        let doneIsVisible = !self.doneTitle.isEmpty
        let doneSize = self.doneButton.update(
            transition: componentTransition,
            component: AnyComponent(ButtonComponent(
                background: ButtonComponent.Background(
                    style: usesMessages ? .legacy : .actualGlass,
                    color: usesMessages ? self.theme.list.itemCheckColors.fillColor : glassColor,
                    foreground: doneColor,
                    pressedColor: usesMessages ? self.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.9) : glassColor,
                    cornerRadius: cornerRadius
                ),
                content: AnyComponentWithIdentity(
                    id: AnyHashable(self.doneTitle),
                    component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: self.doneTitle, font: Font.semibold(17.0), textColor: doneColor)), horizontalAlignment: .center, maximumNumberOfLines: usesMessages ? 2 : 1))
                ),
                isEnabled: self.doneEnabled && doneIsVisible,
                tintWhenDisabled: false,
                action: { [weak self] in
                    self?.done?(false)
                }
            )),
            environment: {},
            containerSize: doneFrame.size
        )
        if let doneView = self.doneButton.view {
            if doneView.superview == nil {
                self.view.addSubview(doneView)
            }
            transition.updateFrame(view: doneView, frame: CGRect(origin: doneFrame.origin, size: doneSize))
            componentTransition.setAlpha(view: doneView, alpha: doneIsVisible ? (self.doneEnabled ? 1.0 : 0.4) : 0.0)
            doneView.isUserInteractionEnabled = self.doneEnabled && doneIsVisible
            doneView.isAccessibilityElement = doneIsVisible
            doneView.accessibilityLabel = self.doneTitle
            doneView.accessibilityTraits = self.doneEnabled ? .button : [.button, .notEnabled]
            doneView.accessibilityElementsHidden = !doneIsVisible
        }
    }
}
