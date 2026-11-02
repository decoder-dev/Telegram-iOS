import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import AppBundle
import ActivityIndicator
import AccountContext
import TelegramCore
import ComponentFlow
import ArchiveInfoScreen
import ComponentDisplayAdapters
import SwiftSignalKit
import ChatListHeaderComponent
import ButtonComponent
import MultilineTextComponent

final class ChatListEmptyNode: ASDisplayNode {
    enum Subject {
        case chats(hasArchive: Bool)
        case archive
        case filter(showEdit: Bool)
        case forum(hasGeneral: Bool)
    }
    private let action: () -> Void
    private let secondaryAction: () -> Void
    private let openArchiveSettings: () -> Void
    
    private let context: AccountContext
    private var theme: PresentationTheme
    private var strings: PresentationStrings
    private var fontSize: CGFloat
    private var reduceMotion: Bool
    private let contentScrollNode = ASScrollNode()
    private let buttonTitleMeasureNode = ImmediateTextNode()
    
    let subject: Subject
    private(set) var isLoading: Bool
    private let textNode: ImmediateTextNode
    private let descriptionNode: ImmediateTextNode
    private let animationNode: AnimatedStickerNode
    private let button = ComponentView<Empty>()
    private var buttonText: String?
    private let buttonIsShimmering: Bool
    private let secondaryButtonNode: HighlightableButtonNode
    private let activityIndicator: ActivityIndicator
    
    private var emptyArchive: ComponentView<Empty>?
    
    private var animationSize: CGSize = CGSize()
    private var buttonIsHidden: Bool
    
    private var validLayout: (size: CGSize, insets: UIEdgeInsets)?
    private var scrollingOffset: (navigationHeight: CGFloat, offset: CGFloat)?
    
    private var globalPrivacySettings: GlobalPrivacySettings = .default
    private var archiveSettingsDisposable: Disposable?
    
    init(context: AccountContext, subject: Subject, isLoading: Bool, presentationData: PresentationData, action: @escaping () -> Void, secondaryAction: @escaping () -> Void, openArchiveSettings: @escaping () -> Void) {
        self.context = context
        let theme = presentationData.theme
        self.theme = theme
        self.strings = presentationData.strings
        self.fontSize = presentationData.listsFontSize.baseDisplaySize
        self.reduceMotion = presentationData.reduceMotion
        
        self.action = action
        self.secondaryAction = secondaryAction
        self.openArchiveSettings = openArchiveSettings
        self.subject = subject
        self.isLoading = isLoading
        
        self.animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: self.context.lottieRenderingSettings)
        
        self.textNode = ImmediateTextNode()
        self.textNode.displaysAsynchronously = false
        self.textNode.maximumNumberOfLines = 0
        self.textNode.isUserInteractionEnabled = false
        self.textNode.textAlignment = .center
        self.textNode.lineSpacing = 0.1
        
        self.descriptionNode = ImmediateTextNode()
        self.descriptionNode.displaysAsynchronously = false
        self.descriptionNode.maximumNumberOfLines = 0
        self.descriptionNode.isUserInteractionEnabled = false
        self.descriptionNode.textAlignment = .center
        self.descriptionNode.lineSpacing = 0.1
        
        var gloss = true
        if case .filter = subject {
            gloss = false
        } else if case .chats(true) = subject {
            gloss = false
        }
        
        self.buttonIsShimmering = gloss
        
        self.secondaryButtonNode = HighlightableButtonNode()
        
        self.activityIndicator = ActivityIndicator(type: .custom(theme.list.itemAccentColor, 22.0, 1.0, false))
        
        var buttonIsHidden = false
        let animationName: String
        if case let .filter(showEdit) = subject {
            animationName = "ChatListFilterEmpty"
            buttonIsHidden = !showEdit
        } else {
            animationName = "ChatListEmpty"
        }
        self.buttonIsHidden = buttonIsHidden
        
        super.init()
        
        self.animationSize = CGSize(width: 124.0, height: 124.0)
        
        if case .archive = subject {
        } else {
            self.addSubnode(self.contentScrollNode)
            self.contentScrollNode.view.contentInsetAdjustmentBehavior = .never
            self.contentScrollNode.view.scrollsToTop = false
            self.contentScrollNode.view.showsVerticalScrollIndicator = false
            self.contentScrollNode.view.isDirectionalLockEnabled = true
            self.contentScrollNode.addSubnode(self.animationNode)
            self.contentScrollNode.addSubnode(self.textNode)
            self.contentScrollNode.addSubnode(self.descriptionNode)
            self.contentScrollNode.addSubnode(self.secondaryButtonNode)
            self.addSubnode(self.activityIndicator)
            
            self.animationNode.automaticallyLoadFirstFrame = true
            self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: animationName), width: 248, height: 248, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
            self.animationNode.visibility = !self.reduceMotion && !self.isLoading
        }
        
        self.animationNode.isHidden = self.isLoading
        self.textNode.isHidden = self.isLoading
        self.descriptionNode.isHidden = self.isLoading
        self.activityIndicator.isHidden = !self.isLoading
        
        self.secondaryButtonNode.addTarget(self, action: #selector(self.secondaryButtonPressed), forControlEvents: .touchUpInside)
        
        self.updatePresentationData(presentationData)
        
        self.animationNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.animationTapGesture(_:))))
        
        if case .archive = subject {
            let _ = self.context.engine.privacy.updateGlobalPrivacySettings().startStandalone()
            
            self.archiveSettingsDisposable = (context.engine.data.subscribe(
                TelegramEngine.EngineData.Item.Configuration.GlobalPrivacy()
            )
            |> deliverOnMainQueue).startStrict(next: { [weak self] settings in
                guard let self else {
                    return
                }
                self.globalPrivacySettings = settings
                if let (size, insets) = self.validLayout {
                    self.updateLayout(size: size, insets: insets, transition: .immediate)
                }
            })
        }
    }
    
    deinit {
        self.archiveSettingsDisposable?.dispose()
    }
    
    @objc private func buttonPressed() {
        self.action()
    }
    
    @objc private func secondaryButtonPressed() {
        self.secondaryAction()
    }
    
    @objc private func animationTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            if !self.animationNode.isPlaying {
                self.restartAnimation()
            }
        }
    }
    
    func restartAnimation() {
        guard self.animationNode.visibility && !self.reduceMotion && !self.isLoading else {
            return
        }
        self.animationNode.play(firstFrame: false, fromIndex: nil)
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        let theme = presentationData.theme
        let strings = presentationData.strings
        self.theme = theme
        self.strings = strings
        self.fontSize = presentationData.listsFontSize.baseDisplaySize
        self.reduceMotion = presentationData.reduceMotion
        
        let text: String
        var descriptionText = ""
        let buttonText: String?
        switch self.subject {
            case let .chats(hasArchive):
                text = hasArchive ? strings.ChatList_EmptyChatListWithArchive : strings.ChatList_EmptyChatList
                buttonText = strings.ChatList_EmptyChatListNewMessage
            case .archive:
                text = strings.ChatList_EmptyChatList
                buttonText = nil
            case .filter:
                text = strings.ChatList_EmptyChatListFilterTitle
                descriptionText = strings.ChatList_EmptyChatListFilterText
                buttonText = strings.ChatList_EmptyChatListEditFilter
            case .forum:
                text = strings.ChatList_EmptyTopicsTitle
                buttonText = strings.ChatList_EmptyTopicsCreate
                descriptionText = strings.ChatList_EmptyTopicsDescription
        }
        let string = NSMutableAttributedString(string: text, font: Font.semibold(self.fontSize), textColor: theme.list.itemPrimaryTextColor)
        let descriptionString = NSAttributedString(string: descriptionText, font: Font.regular(floor(self.fontSize * 15.0 / 17.0)), textColor: theme.list.itemSecondaryTextColor)
       
        self.textNode.attributedText = string
        self.descriptionNode.attributedText = descriptionString
        self.textNode.isAccessibilityElement = true
        self.textNode.accessibilityTraits = .header
        self.textNode.accessibilityLabel = text
        self.descriptionNode.isAccessibilityElement = !descriptionText.isEmpty
        self.descriptionNode.accessibilityLabel = descriptionText
        self.buttonTitleMeasureNode.maximumNumberOfLines = 0
        self.buttonTitleMeasureNode.attributedText = NSAttributedString(string: buttonText ?? "", font: Font.semibold(self.fontSize), textColor: theme.list.itemCheckColors.foregroundColor)
        self.activityIndicator.isAccessibilityElement = self.isLoading
        self.activityIndicator.accessibilityLabel = strings.Channel_NotificationLoading
        self.contentScrollNode.isHidden = self.isLoading
        
        self.buttonText = buttonText
        self.button.view?.isHidden = buttonText == nil || self.buttonIsHidden || self.isLoading
    
        self.activityIndicator.type = .custom(theme.list.itemAccentColor, 22.0, 1.0, false)
        
        if let (size, insets) = self.validLayout {
            self.updateLayout(size: size, insets: insets, transition: .immediate)
            
            if let scrollingOffset = self.scrollingOffset {
                self.updateScrollingOffset(navigationHeight: scrollingOffset.navigationHeight, offset: scrollingOffset.offset, transition: .immediate)
            }
        }
    }
    
    func updateIsLoading(_ isLoading: Bool) {
        if self.isLoading == isLoading {
            return
        }
        self.isLoading = isLoading
        self.animationNode.isHidden = self.isLoading
        self.textNode.isHidden = self.isLoading
        self.descriptionNode.isHidden = self.isLoading
        self.button.view?.isHidden = self.buttonText == nil || self.buttonIsHidden || self.isLoading
        self.activityIndicator.isHidden = !self.isLoading
        self.activityIndicator.isAccessibilityElement = self.isLoading
        self.contentScrollNode.isHidden = self.isLoading
        self.animationNode.visibility = !self.reduceMotion && !self.isLoading && self.animationNode.alpha > 0.0
    }

    func updateLayout(size: CGSize, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, insets)
        let bandMinX = insets.left != insets.right ? insets.left : 0.0
        let bandWidth = max(0.0, insets.left != insets.right ? size.width - insets.left - insets.right : size.width)
        let availableHeight = max(0.0, size.height - insets.top - insets.bottom)
        let textWidth = max(1.0, bandWidth - 40.0)
        let textSize = self.textNode.updateLayout(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let descriptionSize = self.descriptionNode.updateLayout(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        let buttonWidth = max(1.0, min(270.0, bandWidth - 64.0))
        let buttonTitleSize = self.buttonTitleMeasureNode.updateLayout(CGSize(width: max(1.0, buttonWidth - 26.0), height: .greatestFiniteMagnitude))
        let hasButton = self.buttonText != nil && !self.buttonIsHidden
        let buttonSize = CGSize(width: buttonWidth, height: hasButton ? max(52.0, buttonTitleSize.height + 24.0) : 0.0)
        let secondaryButtonSize = self.secondaryButtonNode.measure(CGSize(width: buttonWidth, height: .greatestFiniteMagnitude))
        let descriptionSpacing: CGFloat = descriptionSize.height > 0.0 ? 8.0 : 0.0
        let buttonSpacing: CGFloat = hasButton ? 20.0 : 0.0
        let secondarySpacing: CGFloat = secondaryButtonSize.height > 0.0 ? 12.0 : 0.0
        let bodyHeight = textSize.height + descriptionSpacing + descriptionSize.height + buttonSpacing + buttonSize.height + secondarySpacing + secondaryButtonSize.height
        let showAnimation = availableHeight >= bodyHeight + self.animationSize.height + 24.0 + 40.0
        let illustrationHeight = showAnimation ? self.animationSize.height + 24.0 : 0.0
        let contentHeight = max(availableHeight, illustrationHeight + bodyHeight + 40.0)
        let contentTop = floor((contentHeight - illustrationHeight - bodyHeight) * 0.5)

        transition.updateFrame(node: self.contentScrollNode, frame: CGRect(x: bandMinX, y: insets.top, width: bandWidth, height: availableHeight))
        self.contentScrollNode.view.contentSize = CGSize(width: bandWidth, height: contentHeight)
        self.contentScrollNode.view.isScrollEnabled = contentHeight > availableHeight
        if self.contentScrollNode.view.contentOffset.y > contentHeight - availableHeight {
            self.contentScrollNode.view.contentOffset.y = max(0.0, contentHeight - availableHeight)
        }
        self.contentScrollNode.isHidden = self.isLoading

        let animationFrame = CGRect(origin: CGPoint(x: floor((bandWidth - self.animationSize.width) * 0.5), y: contentTop), size: self.animationSize)
        self.animationNode.updateLayout(size: self.animationSize)
        transition.updateFrame(node: self.animationNode, frame: animationFrame)
        transition.updateAlpha(node: self.animationNode, alpha: showAnimation ? 1.0 : 0.0)
        self.animationNode.visibility = showAnimation && !self.reduceMotion && !self.isLoading

        let textFrame = CGRect(origin: CGPoint(x: floor((bandWidth - textSize.width) * 0.5), y: contentTop + illustrationHeight), size: textSize)
        let descriptionFrame = CGRect(origin: CGPoint(x: floor((bandWidth - descriptionSize.width) * 0.5), y: textFrame.maxY + descriptionSpacing), size: descriptionSize)
        transition.updateFrame(node: self.textNode, frame: textFrame)
        transition.updateFrame(node: self.descriptionNode, frame: descriptionFrame)

        let buttonFrame = CGRect(origin: CGPoint(x: floor((bandWidth - buttonSize.width) * 0.5), y: descriptionFrame.maxY + buttonSpacing), size: buttonSize)
        if hasButton, let buttonText = self.buttonText {
            let _ = self.button.update(
                transition: ComponentTransition(transition),
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: .glass,
                        color: self.theme.list.itemCheckColors.fillColor,
                        foreground: self.theme.list.itemCheckColors.foregroundColor,
                        pressedColor: self.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.9),
                        cornerRadius: 26.0,
                        isShimmering: self.buttonIsShimmering && !self.reduceMotion
                    ),
                    content: AnyComponentWithIdentity(
                        id: AnyHashable(buttonText),
                        component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: buttonText, font: Font.semibold(self.fontSize), textColor: self.theme.list.itemCheckColors.foregroundColor)),
                            horizontalAlignment: .center,
                            maximumNumberOfLines: 0
                        ))
                    ),
                    accessibilityLabel: buttonText,
                    action: { [weak self] in self?.buttonPressed() }
                )),
                environment: {},
                containerSize: buttonSize
            )
        }
        if let buttonView = self.button.view {
            if buttonView.superview == nil {
                self.contentScrollNode.view.addSubview(buttonView)
            }
            buttonView.isHidden = !hasButton || self.isLoading
            transition.updateFrame(view: buttonView, frame: buttonFrame)
        }
        let secondaryFrame = CGRect(origin: CGPoint(x: floor((bandWidth - secondaryButtonSize.width) * 0.5), y: buttonFrame.maxY + secondarySpacing), size: secondaryButtonSize)
        transition.updateFrame(node: self.secondaryButtonNode, frame: secondaryFrame)

        let indicatorSize = self.activityIndicator.measure(CGSize(width: 100.0, height: 100.0))
        transition.updateFrame(node: self.activityIndicator, frame: CGRect(origin: CGPoint(x: bandMinX + floor((bandWidth - indicatorSize.width) * 0.5), y: insets.top + max(0.0, floor((availableHeight - indicatorSize.height) * 0.5))), size: indicatorSize))
    }

    func updateScrollingOffset(navigationHeight: CGFloat, offset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.scrollingOffset = (navigationHeight, offset)
        
        guard let (size, _) = self.validLayout else {
            return
        }
        
        if case .archive = self.subject {
            let emptyArchive: ComponentView<Empty>
            if let current = self.emptyArchive {
                emptyArchive = current
            } else {
                emptyArchive = ComponentView()
                self.emptyArchive = emptyArchive
            }
            let emptyArchiveSize = emptyArchive.update(
                transition: ComponentTransition(transition),
                component: AnyComponent(ArchiveInfoContentComponent(
                    theme: self.theme,
                    strings: self.strings,
                    settings: self.globalPrivacySettings,
                    openSettings: { [weak self] in
                        guard let self else {
                            return
                        }
                        self.openArchiveSettings()
                    }
                )),
                environment: {
                },
                containerSize: CGSize(width: size.width, height: 10000.0)
            )
            if let emptyArchiveView = emptyArchive.view {
                if emptyArchiveView.superview == nil {
                    self.view.addSubview(emptyArchiveView)
                }
                
                let cancelledOutHeight: CGFloat = max(0.0, ChatListNavigationBar.searchScrollHeight - offset)
                let visibleNavigationHeight: CGFloat = navigationHeight - ChatListNavigationBar.searchScrollHeight + cancelledOutHeight
                
                let additionalOffset = min(0.0, -offset + ChatListNavigationBar.searchScrollHeight)
                
                var archiveFrame = CGRect(origin: CGPoint(x: 0.0, y: visibleNavigationHeight + floorToScreenPixels((size.height - visibleNavigationHeight - emptyArchiveSize.height - 50.0) * 0.5)), size: emptyArchiveSize)
                archiveFrame.origin.y = max(archiveFrame.origin.y, visibleNavigationHeight + 20.0)
                
                if size.height - visibleNavigationHeight - emptyArchiveSize.height - 20.0 < 0.0 {
                    archiveFrame.origin.y += additionalOffset
                }
                
                transition.updateFrame(view: emptyArchiveView, frame: archiveFrame)
            }
        } else if let emptyArchive = self.emptyArchive {
            self.emptyArchive = nil
            emptyArchive.view?.removeFromSuperview()
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.contentScrollNode.supernode === self && !self.contentScrollNode.isHidden && self.contentScrollNode.frame.contains(point) {
            let scrollView = self.contentScrollNode.view
            if scrollView.isScrollEnabled {
                return scrollView.hitTest(self.view.convert(point, to: scrollView), with: event)
            }
            if let buttonView = self.button.view, !buttonView.isHidden {
                let localPoint = self.view.convert(point, to: buttonView)
                if buttonView.bounds.insetBy(dx: -10.0, dy: -10.0).contains(localPoint) {
                    return buttonView.hitTest(localPoint, with: event)
                }
            }
            if !self.secondaryButtonNode.isHidden {
                if let result = self.secondaryButtonNode.view.hitTest(self.view.convert(point, to: self.secondaryButtonNode.view), with: event) {
                    return result
                }
            }
            if self.animationNode.alpha > 0.0 {
                if let result = self.animationNode.view.hitTest(self.view.convert(point, to: self.animationNode.view), with: event) {
                    return result
                }
            }
        }
        if let emptyArchiveView = self.emptyArchive?.view {
            return emptyArchiveView.hitTest(self.view.convert(point, to: emptyArchiveView), with: event)
        }
        return nil
    }
}
