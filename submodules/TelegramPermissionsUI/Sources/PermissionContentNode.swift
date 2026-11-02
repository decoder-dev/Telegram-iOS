import Foundation
import LottieSettings
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import TelegramPresentationData
import TextFormat
import TelegramPermissions
import ComponentFlow
import ButtonComponent
import MultilineTextComponent
import ComponentDisplayAdapters
import Markdown
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import AppBundle
import AccountContext

public enum PermissionContentIcon: Equatable {
    case image(UIImage?)
    case icon(PermissionControllerCustomIcon)
    case animation(String)
    
    public func imageForTheme(_ theme: PresentationTheme) -> UIImage? {
        switch self {
            case let .image(image):
                return image
            case let .icon(icon):
                return theme.overallDarkAppearance ? (icon.dark ?? icon.light) : icon.light
            case .animation:
                return nil
        }
    }
}

public final class PermissionContentNode: ASDisplayNode {
    private var theme: PresentationTheme
    private var fontSize: CGFloat
    private var reduceMotion: Bool
    public let kind: Int32
    private let filterHitTest: Bool

    private let scrollNode: ASScrollNode
    private let iconNode: ASImageNode
    private let animationNode: AnimatedStickerNode?
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateTextNode
    private let textNode: ImmediateTextNode
    private let actionButton = ComponentView<Empty>()
    private let footerNode: ImmediateTextNode
    private let privacyPolicyButton: HighlightableButtonNode

    private let icon: PermissionContentIcon
    private let title: String
    private let subtitle: String?
    private let text: String
    private let buttonTitle: String
    private let privacyPolicyTitle: String
    private let footerText: String?
    private let textAlignment: NSTextAlignment

    public var buttonAction: (() -> Void)?
    public var openPrivacyPolicy: (() -> Void)?
    public var validLayout: (CGSize, UIEdgeInsets)?

    public init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings, kind: Int32, icon: PermissionContentIcon, title: String, subtitle: String? = nil, text: String, buttonTitle: String, secondaryButtonTitle: String? = nil, footerText: String? = nil, buttonAction: @escaping () -> Void, openPrivacyPolicy: (() -> Void)?, filterHitTest: Bool = false) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.theme = theme
        self.fontSize = presentationData.listsFontSize.baseDisplaySize
        self.reduceMotion = presentationData.reduceMotion
        self.kind = kind
        self.buttonAction = buttonAction
        self.openPrivacyPolicy = openPrivacyPolicy
        self.filterHitTest = filterHitTest
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.buttonTitle = buttonTitle
        self.privacyPolicyTitle = secondaryButtonTitle ?? strings.Permissions_PrivacyPolicy
        self.footerText = footerText
        if case .animation = icon {
            self.textAlignment = .natural
        } else {
            self.textAlignment = secondaryButtonTitle != nil ? .natural : .center
        }

        self.scrollNode = ASScrollNode()
        self.iconNode = ASImageNode()
        self.iconNode.isLayerBacked = true
        self.iconNode.displayWithoutProcessing = true
        self.iconNode.displaysAsynchronously = false
        self.iconNode.isUserInteractionEnabled = false
        if case let .animation(name) = icon {
            let animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: context.lottieRenderingSettings)
            animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: name), width: 320, height: 320, playbackMode: presentationData.reduceMotion ? .still(.start) : .once, mode: .direct(cachePathPrefix: nil))
            animationNode.isUserInteractionEnabled = false
            self.animationNode = animationNode
        } else {
            self.animationNode = nil
        }

        self.titleNode = ImmediateTextNode()
        self.subtitleNode = ImmediateTextNode()
        self.textNode = ImmediateTextNode()
        self.footerNode = ImmediateTextNode()
        self.privacyPolicyButton = HighlightableButtonNode()
        self.privacyPolicyButton.titleNode.maximumNumberOfLines = 0
        self.privacyPolicyButton.titleNode.textAlignment = .center
        self.privacyPolicyButton.accessibilityLabel = self.privacyPolicyTitle

        super.init()

        self.addSubnode(self.scrollNode)
        for node in [self.titleNode, self.subtitleNode, self.textNode, self.footerNode] {
            node.maximumNumberOfLines = 0
            node.textAlignment = .center
            node.isUserInteractionEnabled = false
            node.displaysAsynchronously = false
            node.isAccessibilityElement = true
            self.scrollNode.addSubnode(node)
        }
        self.titleNode.accessibilityTraits = .header
        self.textNode.textAlignment = self.textAlignment
        self.scrollNode.addSubnode(self.iconNode)
        if let animationNode = self.animationNode {
            self.scrollNode.addSubnode(animationNode)
        }
        self.scrollNode.addSubnode(self.privacyPolicyButton)
        self.scrollNode.view.contentInsetAdjustmentBehavior = .never
        self.scrollNode.view.scrollsToTop = false
        self.scrollNode.view.alwaysBounceVertical = false
        self.scrollNode.view.isDirectionalLockEnabled = true
        self.updateText()
        self.privacyPolicyButton.addTarget(self, action: #selector(self.privacyPolicyPressed), forControlEvents: .touchUpInside)
    }

    private func updateText() {
        self.iconNode.image = self.icon.imageForTheme(self.theme)
        self.titleNode.attributedText = NSAttributedString(string: self.title, font: Font.bold(floor(self.fontSize * 28.0 / 17.0)), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.titleNode.accessibilityLabel = self.title
        let body = MarkdownAttributeSet(font: Font.regular(self.fontSize), textColor: self.theme.list.itemPrimaryTextColor)
        let link = MarkdownAttributeSet(font: Font.regular(self.fontSize), textColor: self.theme.list.itemAccentColor, additionalAttributes: [TelegramTextAttributes.URL: ""])
        self.textNode.attributedText = parseMarkdownIntoAttributedString(self.text.replacingOccurrences(of: "]", with: "]()"), attributes: MarkdownAttributes(body: body, bold: body, link: link, linkAttribute: { _ in nil }), textAlignment: self.textAlignment)
        self.textNode.accessibilityLabel = self.textNode.attributedText?.string
        let captionFont = Font.regular(floor(self.fontSize * 13.0 / 17.0))
        self.subtitleNode.attributedText = self.subtitle.map { NSAttributedString(string: $0, font: captionFont, textColor: self.theme.list.freeTextColor, paragraphAlignment: .center) }
        self.subtitleNode.accessibilityLabel = self.subtitle
        self.subtitleNode.isHidden = self.subtitle == nil
        self.footerNode.attributedText = self.footerText.map { NSAttributedString(string: $0, font: captionFont, textColor: self.theme.list.freeTextColor, paragraphAlignment: .center) }
        self.footerNode.accessibilityLabel = self.footerText
        self.footerNode.isHidden = self.footerText == nil
        self.privacyPolicyButton.setTitle(self.privacyPolicyTitle, with: Font.regular(self.fontSize), with: self.theme.list.itemAccentColor, for: .normal)
        self.privacyPolicyButton.isHidden = self.openPrivacyPolicy == nil
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else {
            return nil
        }
        if self.filterHitTest && !self.scrollNode.view.isScrollEnabled && (result === self.view || result === self.scrollNode.view) {
            return nil
        }
        return result
    }

    public func updatePresentationData(_ presentationData: PresentationData) {
        self.theme = presentationData.theme
        self.fontSize = presentationData.listsFontSize.baseDisplaySize
        if self.reduceMotion != presentationData.reduceMotion {
            self.reduceMotion = presentationData.reduceMotion
            if let animationNode = self.animationNode, case let .animation(name) = self.icon {
                animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: name), width: 320, height: 320, playbackMode: self.reduceMotion ? .still(.start) : .once, mode: .direct(cachePathPrefix: nil))
            }
        }
        self.updateText()
        if let (size, insets) = self.validLayout {
            self.updateLayout(size: size, insets: insets, transition: .immediate)
        }
    }

    @objc private func privacyPolicyPressed() {
        self.openPrivacyPolicy?()
    }

    public func updateLayout(size: CGSize, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, insets)
        let viewport = CGSize(width: max(1.0, size.width - insets.left - insets.right), height: max(1.0, size.height - insets.top - insets.bottom))
        transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: viewport))
        let textWidth = max(1.0, min(520.0, viewport.width - 48.0))
        let constraint = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        let titleSize = self.titleNode.updateLayout(constraint)
        let subtitleSize = self.subtitleNode.updateLayout(constraint)
        let textSize = self.textNode.updateLayout(constraint)
        let footerSize = self.footerNode.updateLayout(constraint)
        let privacyLabelSize = self.privacyPolicyButton.measure(constraint)
        let privacySize = self.openPrivacyPolicy == nil ? CGSize.zero : CGSize(width: max(44.0, privacyLabelSize.width), height: max(44.0, privacyLabelSize.height + 16.0))
        self.privacyPolicyButton.isHidden = self.openPrivacyPolicy == nil
        let buttonSize = self.actionButton.update(
            transition: ComponentTransition(transition),
            component: AnyComponent(ButtonComponent(
                background: ButtonComponent.Background(style: .glass, color: self.theme.list.itemCheckColors.fillColor, foreground: self.theme.list.itemCheckColors.foregroundColor, pressedColor: self.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.9), cornerRadius: 26.0),
                content: AnyComponentWithIdentity(id: AnyHashable(0), component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: self.buttonTitle, font: Font.semibold(self.fontSize), textColor: self.theme.list.itemCheckColors.foregroundColor)), horizontalAlignment: .center, maximumNumberOfLines: 0))),
                fitToContentHeight: true,
                accessibilityLabel: self.buttonTitle,
                isEnabled: self.buttonAction != nil,
                action: { [weak self] in
                    self?.buttonAction?()
                }
            )),
            environment: {},
            containerSize: CGSize(width: min(420.0, textWidth), height: 52.0)
        )
        var illustrationSize = self.iconNode.image?.size ?? .zero
        if self.animationNode != nil {
            illustrationSize = CGSize(width: 220.0, height: 220.0)
        }
        if illustrationSize.width > textWidth {
            illustrationSize.height *= textWidth / illustrationSize.width
            illustrationSize.width = textWidth
        }
        let layout = PermissionContentLayout(viewport: viewport, illustrationSize: illustrationSize, titleSize: titleSize, subtitleSize: subtitleSize, textSize: textSize, buttonSize: buttonSize, privacySize: privacySize, footerSize: footerSize)
        self.scrollNode.view.contentSize = layout.contentSize
        self.scrollNode.view.isScrollEnabled = layout.contentSize.height > viewport.height
        self.scrollNode.view.showsVerticalScrollIndicator = self.scrollNode.view.isScrollEnabled
        let offset = self.scrollNode.view.contentOffset.y
        self.scrollNode.view.contentOffset = CGPoint(x: 0.0, y: max(0.0, min(offset, layout.contentSize.height - viewport.height)))
        transition.updateFrame(node: self.iconNode, frame: layout.illustrationFrame)
        self.iconNode.isHidden = !layout.showsIllustration
        if let animationNode = self.animationNode {
            transition.updateFrame(node: animationNode, frame: layout.illustrationFrame)
            animationNode.isHidden = !layout.showsIllustration
            animationNode.visibility = layout.showsIllustration
            animationNode.updateLayout(size: illustrationSize)
        }
        transition.updateFrame(node: self.titleNode, frame: layout.titleFrame)
        transition.updateFrame(node: self.subtitleNode, frame: layout.subtitleFrame)
        transition.updateFrame(node: self.textNode, frame: layout.textFrame)
        transition.updateFrame(node: self.footerNode, frame: layout.footerFrame)
        transition.updateFrame(node: self.privacyPolicyButton, frame: layout.privacyFrame)
        if let buttonView = self.actionButton.view {
            if buttonView.superview == nil {
                self.scrollNode.view.addSubview(buttonView)
            }
            transition.updateFrame(view: buttonView, frame: layout.buttonFrame)
        }
        var accessibilityElements: [Any] = [self.titleNode.view]
        if !self.subtitleNode.isHidden {
            accessibilityElements.append(self.subtitleNode.view)
        }
        accessibilityElements.append(self.textNode.view)
        if let buttonView = self.actionButton.view {
            accessibilityElements.append(buttonView)
        }
        if !self.privacyPolicyButton.isHidden {
            accessibilityElements.append(self.privacyPolicyButton.view)
        }
        if !self.footerNode.isHidden {
            accessibilityElements.append(self.footerNode.view)
        }
        self.scrollNode.view.accessibilityElements = accessibilityElements
    }
}
