import Foundation
import UIKit
import Display
import ComponentFlow
import AnimatedStickerComponent
import ButtonComponent
import TelegramPresentationData
import AccountContext
import MultilineTextComponent
import BalancedTextComponent

public final class EmptyStateIndicatorComponent: Component {
    public let context: AccountContext
    public let theme: PresentationTheme
    public let animationName: String?
    public let title: String?
    public let text: String
    public let actionTitle: String?
    public let fitToHeight: Bool
    public let action: () -> Void
    public let additionalActionTitle: String?
    public let additionalAction: () -> Void
    public let additionalActionSeparator: String?
    public let fontSize: CGFloat
    public let reduceMotion: Bool
    
    public init(
        context: AccountContext,
        theme: PresentationTheme,
        fitToHeight: Bool,
        animationName: String?,
        title: String?,
        text: String,
        actionTitle: String?,
        action: @escaping () -> Void,
        additionalActionTitle: String?,
        additionalAction: @escaping () -> Void,
        additionalActionSeparator: String? = nil,
        fontSize: CGFloat? = nil,
        reduceMotion: Bool? = nil
    ) {
        self.context = context
        self.theme = theme
        self.fitToHeight = fitToHeight
        self.animationName = animationName
        self.title = title
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
        self.additionalActionTitle = additionalActionTitle
        self.additionalAction = additionalAction
        self.additionalActionSeparator = additionalActionSeparator
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.fontSize = fontSize ?? presentationData.listsFontSize.baseDisplaySize
        self.reduceMotion = reduceMotion ?? presentationData.reduceMotion
    }

    public static func ==(lhs: EmptyStateIndicatorComponent, rhs: EmptyStateIndicatorComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.fontSize != rhs.fontSize || lhs.reduceMotion != rhs.reduceMotion {
            return false
        }
        if lhs.fitToHeight != rhs.fitToHeight {
            return false
        }
        if lhs.animationName != rhs.animationName {
            return false
        }
        if lhs.title != rhs.title {
            return false
        }
        if lhs.text != rhs.text {
            return false
        }
        if lhs.actionTitle != rhs.actionTitle {
            return false
        }
        if lhs.additionalActionTitle != rhs.additionalActionTitle {
            return false
        }
        if lhs.additionalActionSeparator != rhs.additionalActionSeparator {
            return false
        }
        return true
    }

    public final class View: UIView {
        private var component: EmptyStateIndicatorComponent?
        private weak var componentState: EmptyComponentState?

        private let scrollView = UIScrollView()
        private let contentView = UIView()
        private let animation = ComponentView<Empty>()
        private let title = ComponentView<Empty>()
        private let text = ComponentView<Empty>()
        private var button: ComponentView<Empty>?
        private var additionalButton: ComponentView<Empty>?
        private var additionalSeparatorLeft: SimpleLayer?
        private var additionalSeparatorRight: SimpleLayer?
        private var additionalSeparatorText: ComponentView<Empty>?
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
            self.scrollView.contentInsetAdjustmentBehavior = .never
            self.scrollView.scrollsToTop = false
            self.scrollView.showsVerticalScrollIndicator = false
            self.scrollView.alwaysBounceVertical = false
            self.scrollView.isDirectionalLockEnabled = true
            self.scrollView.addSubview(self.contentView)
            self.addSubview(self.scrollView)
        }

        required public init(coder: NSCoder) {
            preconditionFailure()
        }

        public func update(component: EmptyStateIndicatorComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let resetScroll = self.component?.text != component.text || self.component?.title != component.title || self.component?.actionTitle != component.actionTitle
            self.component = component
            self.componentState = state
            let bodyFont = Font.regular(floor(component.fontSize * 15.0 / 17.0))
            let actionFont = Font.semibold(component.fontSize)
            let contentWidth = max(1.0, availableSize.width - 32.0)
            let actionWidth = min(260.0, contentWidth)
            
            var animationSize: CGSize?
            if let animationName = component.animationName {
                animationSize = self.animation.update(
                    transition: transition,
                    component: AnyComponent(AnimatedStickerComponent(
                        account: component.context.account,
                        animation: AnimatedStickerComponent.Animation(source: .bundle(name: animationName), loop: !component.reduceMotion),
                        isAnimating: !component.reduceMotion,
                        size: CGSize(width: 120.0, height: 120.0),
                        lottieSettings: component.context.lottieRenderingSettings
                    )),
                    environment: {},
                    containerSize: CGSize(width: 120.0, height: 120.0)
                )
            }
            
            if animationSize == nil {
                self.animation.view?.removeFromSuperview()
            }

            var titleSize: CGSize?
            if let title = component.title {
                titleSize = self.title.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: title, font: actionFont, textColor: component.theme.list.itemPrimaryTextColor)),
                        horizontalAlignment: .center,
                        maximumNumberOfLines: 0
                    )),
                    environment: {},
                    containerSize: CGSize(width: min(300.0, contentWidth), height: 1000.0)
                )
            }
            if titleSize == nil {
                self.title.view?.removeFromSuperview()
            }
            let textSize = self.text.update(
                transition: .immediate,
                component: AnyComponent(BalancedTextComponent(
                    text: .plain(NSAttributedString(string: component.text, font: bodyFont, textColor: component.theme.list.itemSecondaryTextColor)),
                    horizontalAlignment: .center,
                    maximumNumberOfLines: 0
                )),
                environment: {},
                containerSize: CGSize(width: min(400.0, contentWidth), height: 1000.0)
            )
            var buttonSize: CGSize?
            if let actionTitle = component.actionTitle {
                let button: ComponentView<Empty>
                if let current = self.button {
                    button = current
                } else {
                    button = ComponentView()
                    self.button = button
                }
                
                let actionText = NSAttributedString(string: actionTitle, font: actionFont, textColor: component.theme.list.itemCheckColors.foregroundColor)
                let (actionLayout, _) = TextNode.asyncLayout(nil)(TextNodeLayoutArguments(attributedString: actionText, backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: max(1.0, actionWidth - 26.0), height: .greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: .zero))
                let actionHeight = max(52.0, actionLayout.size.height + 24.0)
                buttonSize = button.update(
                    transition: transition,
                    component: AnyComponent(ButtonComponent(
                        background: ButtonComponent.Background(
                            color: component.theme.list.itemCheckColors.fillColor,
                            foreground: component.theme.list.itemCheckColors.foregroundColor,
                            pressedColor: component.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.9),
                            cornerRadius: 26.0
                        ),
                        content: AnyComponentWithIdentity(id: 0, component: AnyComponent(
                            MultilineTextComponent(text: .plain(actionText), horizontalAlignment: .center, maximumNumberOfLines: 0)
                        )),
                        accessibilityLabel: actionTitle,
                        isEnabled: true,
                        displaysProgress: false,
                        action: { [weak self] in
                            guard let self, let component = self.component else {
                                return
                            }
                            component.action()
                        }
                    )),
                    environment: {},
                    containerSize: CGSize(width: actionWidth, height: actionHeight)
                )
            } else {
                if let button = self.button {
                    self.button = nil
                    button.view?.removeFromSuperview()
                }
            }
            
            var additionalButtonSize: CGSize?
            if let additionalActionTitle = component.additionalActionTitle {
                let additionalButton: ComponentView<Empty>
                if let current = self.additionalButton {
                    additionalButton = current
                } else {
                    additionalButton = ComponentView()
                    self.additionalButton = additionalButton
                }
                
                additionalButtonSize = additionalButton.update(
                    transition: transition,
                    component: AnyComponent(Button(
                        content: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: additionalActionTitle, font: Font.regular(component.fontSize), textColor: component.theme.list.itemAccentColor)),
                            horizontalAlignment: .center,
                            maximumNumberOfLines: 0
                        )),
                        action: { [weak self] in
                            guard let self, let component = self.component else {
                                return
                            }
                            component.additionalAction()
                        }
                    ).minSize(CGSize(width: 0.0, height: PresentationLayoutMetrics.minimumInteractiveSize))),
                    environment: {},
                    containerSize: CGSize(width: actionWidth, height: 1000.0)
                )
                additionalButton.view?.accessibilityLabel = additionalActionTitle
            } else {
                if let additionalButton = self.additionalButton {
                    self.additionalButton = nil
                    additionalButton.view?.removeFromSuperview()
                }
            }
            
            var additionalSeparatorTextSize: CGSize?
            if let additionalActionSeparator = component.additionalActionSeparator {
                let additionalSeparatorText: ComponentView<Empty>
                if let current = self.additionalSeparatorText {
                    additionalSeparatorText = current
                } else {
                    additionalSeparatorText = ComponentView()
                    self.additionalSeparatorText = additionalSeparatorText
                }
                
                let additionalSeparatorLeft: SimpleLayer
                if let current = self.additionalSeparatorLeft {
                    additionalSeparatorLeft = current
                } else {
                    additionalSeparatorLeft = SimpleLayer()
                    self.additionalSeparatorLeft = additionalSeparatorLeft
                    self.contentView.layer.addSublayer(additionalSeparatorLeft)
                }
                
                let additionalSeparatorRight: SimpleLayer
                if let current = self.additionalSeparatorRight {
                    additionalSeparatorRight = current
                } else {
                    additionalSeparatorRight = SimpleLayer()
                    self.additionalSeparatorRight = additionalSeparatorRight
                    self.contentView.layer.addSublayer(additionalSeparatorRight)
                }
                
                additionalSeparatorLeft.backgroundColor = component.theme.list.itemPlainSeparatorColor.cgColor
                additionalSeparatorRight.backgroundColor = component.theme.list.itemPlainSeparatorColor.cgColor
                
                additionalSeparatorTextSize = additionalSeparatorText.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: additionalActionSeparator, font: bodyFont, textColor: component.theme.list.itemSecondaryTextColor))
                    )),
                    environment: {},
                    containerSize: CGSize(width:  min(300.0, contentWidth), height: 100.0)
                )
            } else {
                if let additionalSeparatorLeft = self.additionalSeparatorLeft {
                    self.additionalSeparatorLeft = nil
                    additionalSeparatorLeft.removeFromSuperlayer()
                }
                if let additionalSeparatorRight = self.additionalSeparatorRight {
                    self.additionalSeparatorRight = nil
                    additionalSeparatorRight.removeFromSuperlayer()
                }
                if let additionalSeparatorText = self.additionalSeparatorText {
                    self.additionalSeparatorText = nil
                    additionalSeparatorText.view?.removeFromSuperview()
                }
            }
            
            let animationSpacing: CGFloat = 16.0
            let titleSpacing: CGFloat = 8.0
            let buttonSpacing: CGFloat = 20.0
            let additionalSeparatorHeight = max(32.0, (additionalSeparatorTextSize?.height ?? 0.0) + 12.0)
            
            var totalHeight: CGFloat = 0.0
            
            if let animationSize {
                totalHeight += animationSize.height + animationSpacing
            }
            if let titleSize {
                totalHeight += titleSize.height + titleSpacing
            }
            totalHeight += textSize.height
            if let buttonSize {
                totalHeight += buttonSpacing + buttonSize.height
            }
            if let _ = additionalSeparatorTextSize {
                totalHeight += additionalSeparatorHeight
            }
            if let additionalButtonSize {
                totalHeight += buttonSpacing + additionalButtonSize.height
            }
            
            var contentY: CGFloat
            if component.fitToHeight {
                contentY = 0.0
            } else {
                contentY = max(0.0, floor((availableSize.height - totalHeight) * 0.5))
            }
            let viewportHeight = component.fitToHeight ? totalHeight : max(0.0, availableSize.height)
            let scrollHeight = max(viewportHeight, totalHeight)
            transition.setFrame(view: self.scrollView, frame: CGRect(x: 0.0, y: 0.0, width: availableSize.width, height: viewportHeight))
            transition.setFrame(view: self.contentView, frame: CGRect(x: 0.0, y: 0.0, width: availableSize.width, height: scrollHeight))
            self.scrollView.contentSize = CGSize(width: availableSize.width, height: scrollHeight)
            self.scrollView.isScrollEnabled = !component.fitToHeight && totalHeight > viewportHeight
            if resetScroll {
                self.scrollView.contentOffset = .zero
            } else if self.scrollView.contentOffset.y > scrollHeight - viewportHeight {
                self.scrollView.contentOffset.y = max(0.0, scrollHeight - viewportHeight)
            }

            if let animationSize, let animationView = self.animation.view {
                if animationView.superview == nil {
                    self.contentView.addSubview(animationView)
                }
                transition.setFrame(view: animationView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - animationSize.width) * 0.5), y: contentY), size: animationSize))
                contentY += animationSize.height + animationSpacing
            }
            if let titleSize, let titleView = self.title.view {
                if titleView.superview == nil {
                    self.contentView.addSubview(titleView)
                }
                titleView.isAccessibilityElement = true
                titleView.accessibilityLabel = component.title
                titleView.accessibilityTraits = .header
                transition.setFrame(view: titleView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) * 0.5), y: contentY), size: titleSize))
                contentY += titleSize.height + titleSpacing
            }
            if let textView = self.text.view {
                if textView.superview == nil {
                    self.contentView.addSubview(textView)
                }
                textView.isAccessibilityElement = !component.text.isEmpty
                textView.accessibilityLabel = component.text
                textView.accessibilityTraits = .staticText
                transition.setFrame(view: textView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - textSize.width) * 0.5), y: contentY), size: textSize))
                contentY += textSize.height
            }
            if let buttonSize, let buttonView = self.button?.view {
                contentY += buttonSpacing
                if buttonView.superview == nil {
                    self.contentView.addSubview(buttonView)
                }
                transition.setFrame(view: buttonView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - buttonSize.width) * 0.5), y: contentY), size: buttonSize))
                contentY += buttonSize.height
            }
            
            if let additionalSeparatorTextSize, let additionalSeparatorText = self.additionalSeparatorText, let additionalSeparatorLeft = self.additionalSeparatorLeft, let additionalSeparatorRight = self.additionalSeparatorRight {
                let additionalSeparatorTextFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - additionalSeparatorTextSize.width) * 0.5), y: contentY + floor((additionalSeparatorHeight - additionalSeparatorTextSize.height) * 0.5)), size: additionalSeparatorTextSize)
                if let additionalSeparatorTextView = additionalSeparatorText.view {
                    if additionalSeparatorTextView.superview == nil {
                        self.contentView.addSubview(additionalSeparatorTextView)
                    }
                    transition.setFrame(view: additionalSeparatorTextView, frame: additionalSeparatorTextFrame)
                }
                
                let separatorSpacing: CGFloat = 10.0
                let separatorWidth = max(0.0, min(72.0, (contentWidth - additionalSeparatorTextSize.width) * 0.5 - separatorSpacing))
                
                transition.setFrame(layer: additionalSeparatorLeft, frame: CGRect(origin: CGPoint(x: additionalSeparatorTextFrame.minX - separatorSpacing - separatorWidth, y: additionalSeparatorTextFrame.midY + 1.0), size: CGSize(width: separatorWidth, height: UIScreenPixel)))
                transition.setFrame(layer: additionalSeparatorRight, frame: CGRect(origin: CGPoint(x: additionalSeparatorTextFrame.maxX + separatorSpacing, y: additionalSeparatorTextFrame.midY + 1.0), size: CGSize(width: separatorWidth, height: UIScreenPixel)))
                
                contentY += additionalSeparatorHeight
            }
            
            if let additionalButtonSize, let additionalButtonView = self.additionalButton?.view {
                contentY += buttonSpacing
                if additionalButtonView.superview == nil {
                    self.contentView.addSubview(additionalButtonView)
                }
                transition.setFrame(view: additionalButtonView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - additionalButtonSize.width) * 0.5), y: contentY), size: additionalButtonSize))
                contentY += additionalButtonSize.height
            }
            
            if component.fitToHeight {
                return CGSize(width: availableSize.width, height: totalHeight)
            } else {
                return availableSize
            }
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
