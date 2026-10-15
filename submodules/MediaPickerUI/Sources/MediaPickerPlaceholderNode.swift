import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import SolidRoundedButtonNode
import PresentationDataUtils

private func mediaPlaceholderGeometry(availableHeight: CGFloat, bodyHeight: CGFloat, imageHeight: CGFloat, portrait: Bool) -> (imageHeight: CGFloat, contentHeight: CGFloat, topOffset: CGFloat) {
    let image = portrait && bodyHeight + imageHeight + 12.0 <= availableHeight ? imageHeight + 12.0 : 0.0
    let content = bodyHeight + image
    return (image, content, max(0.0, floor((availableHeight - content) / 2.0)))
}

final class MediaPickerPlaceholderNode: ASDisplayNode {
    enum Content: Equatable {
        case intro(story: Bool)
        case bannedSendMedia(text: String, canBoost: Bool)
    }
    
    let content: Content
    private let scrollNode = ASScrollNode()
    private var reduceMotion = false
    private var animationReduceMotion: Bool?
    private var validPresentation: (PresentationTheme, PresentationStrings, Bool)?
    
    private var animationNode: AnimatedStickerNode
    private let titleNode: ImmediateTextNode
    private let textNode: ImmediateTextNode
    private let buttonNode: SolidRoundedButtonNode
    private var validLayout: ContainerViewLayout?
    
    private var cameraButtonNode: HighlightTrackingButtonNode
    private var cameraTextNode: ImmediateTextNode
    private var cameraIconNode: ASImageNode
    
    var boostPressed: () -> Void = {}
    var settingsPressed: () -> Void = {}
    var cameraPressed: () -> Void = {}
    
    init(content: Content, lottieSettings: LottieRenderingSettings) {
        self.content = content
        
        self.animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: lottieSettings)
        self.animationNode.visibility = true
        
        self.titleNode = ImmediateTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.textAlignment = .center
        self.titleNode.maximumNumberOfLines = 0
        
        self.textNode = ImmediateTextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.lineSpacing = 0.1
        self.textNode.textAlignment = .center
        self.textNode.maximumNumberOfLines = 0
        
        self.buttonNode = SolidRoundedButtonNode(theme: SolidRoundedButtonTheme(backgroundColor: .black, foregroundColor: .white), glass: true, height: 52.0, cornerRadius: 26.0, isShimmering: true)
        
        self.cameraButtonNode = HighlightTrackingButtonNode()
        self.cameraButtonNode.alpha = 0.0
        self.cameraButtonNode.isUserInteractionEnabled = false
        
        self.cameraTextNode = ImmediateTextNode()
        self.cameraTextNode.isUserInteractionEnabled = false
        
        self.cameraIconNode = ASImageNode()
        self.cameraIconNode.displaysAsynchronously = false
        self.cameraIconNode.isUserInteractionEnabled = false
         
        super.init()
                
        self.addSubnode(self.scrollNode)
        self.scrollNode.view.contentInsetAdjustmentBehavior = .never
        self.scrollNode.view.alwaysBounceVertical = false
        self.scrollNode.addSubnode(self.animationNode)
        self.scrollNode.addSubnode(self.textNode)
        
        switch self.content {
        case .bannedSendMedia(_, true):
            self.scrollNode.addSubnode(self.buttonNode)
            self.buttonNode.pressed = { [weak self] in
                self?.boostPressed()
            }
        case .intro:
            self.scrollNode.addSubnode(self.titleNode)
            self.scrollNode.addSubnode(self.buttonNode)
            
            self.scrollNode.addSubnode(self.cameraButtonNode)
            self.cameraButtonNode.addSubnode(self.cameraTextNode)
            self.cameraButtonNode.addSubnode(self.cameraIconNode)
            
            self.cameraButtonNode.highligthedChanged = { [weak self] highlighted in
                if let strongSelf = self {
                    if highlighted {
                        strongSelf.cameraTextNode.layer.removeAnimation(forKey: "opacity")
                        strongSelf.cameraTextNode.alpha = 0.4
                        strongSelf.cameraIconNode.layer.removeAnimation(forKey: "opacity")
                        strongSelf.cameraIconNode.alpha = 0.4
                    } else {
                        strongSelf.cameraTextNode.alpha = 1.0
                        strongSelf.cameraTextNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                        strongSelf.cameraIconNode.alpha = 1.0
                        strongSelf.cameraIconNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    }
                }
            }
            self.cameraButtonNode.addTarget(self, action: #selector(self.cameraButtonPressed), forControlEvents: .touchUpInside)
            
            self.buttonNode.pressed = { [weak self] in
                self?.settingsPressed()
            }
        default:
            break
        }
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilitySettingsChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilitySettingsChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accessibilitySettingsChanged() {
        guard let layout = self.validLayout, let (theme, strings, hasCamera) = self.validPresentation else { return }
        self.update(layout: layout, theme: theme, strings: strings, hasCamera: hasCamera, reduceMotion: self.reduceMotion, transition: .immediate)
    }

    @objc private func cameraButtonPressed() {
        self.cameraPressed()
    }
    
    private var theme: PresentationTheme?
    func update(layout: ContainerViewLayout, theme: PresentationTheme, strings: PresentationStrings, hasCamera: Bool, reduceMotion: Bool = false, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        self.validPresentation = (theme, strings, hasCamera)
        self.reduceMotion = reduceMotion
        let themeUpdated = self.theme !== theme
        self.theme = theme

        let isIntro: Bool
        let showsButton: Bool
        let title: String
        let text: String
        let name: String
        switch self.content {
        case let .intro(story):
            isIntro = true
            showsButton = true
            title = strings.Attachment_MediaAccessTitle
            text = story ? strings.Attachment_MediaAccessStoryText : strings.Attachment_MediaAccessText
            name = "Photos"
            self.buttonNode.title = strings.Attachment_OpenSettings
        case let .bannedSendMedia(description, canBoost):
            isIntro = false
            showsButton = canBoost
            title = ""
            text = description
            name = "Banned"
            self.buttonNode.title = strings.Attachment_BoostToUnlock
        }
        let showsCamera = isIntro && hasCamera
        let effectiveReduceMotion = reduceMotion || UIAccessibility.isReduceMotionEnabled
        if self.animationReduceMotion != effectiveReduceMotion {
            self.animationReduceMotion = effectiveReduceMotion
            self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: name), width: 320, height: 320, playbackMode: effectiveReduceMotion ? .still(.start) : isIntro ? .loop : .once, mode: .direct(cachePathPrefix: nil))
        }
        if themeUpdated {
            self.buttonNode.updateTheme(SolidRoundedButtonTheme(theme: theme))
            self.cameraIconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Attach Menu/OpenCamera"), color: theme.list.itemAccentColor)
        }
        self.titleNode.attributedText = NSAttributedString(string: title, font: theme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .headline) : Font.medium(17.0), textColor: theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.textNode.attributedText = NSAttributedString(string: text, font: theme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .subheadline) : Font.regular(15.0), textColor: theme.list.freeTextColor, paragraphAlignment: .center)
        self.cameraTextNode.attributedText = NSAttributedString(string: strings.Attachment_OpenCamera, font: theme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .body) : Font.regular(17.0), textColor: theme.list.itemAccentColor, paragraphAlignment: .center)
        self.titleNode.isAccessibilityElement = isIntro
        self.titleNode.accessibilityLabel = title
        self.titleNode.accessibilityTraits = .header
        self.textNode.isAccessibilityElement = true
        self.textNode.accessibilityLabel = text
        self.cameraButtonNode.isAccessibilityElement = showsCamera
        self.cameraButtonNode.accessibilityLabel = strings.Attachment_OpenCamera
        self.cameraButtonNode.accessibilityTraits = .button
        self.cameraButtonNode.accessibilityElementsHidden = !showsCamera
        self.cameraButtonNode.isUserInteractionEnabled = showsCamera
        self.cameraButtonNode.isHidden = !showsCamera
        transition.updateAlpha(node: self.cameraButtonNode, alpha: showsCamera ? 1.0 : 0.0)

        let insets = layout.insets(options: [.input])
        let contentWidth = max(1.0, layout.size.width - layout.safeInsets.left - layout.safeInsets.right - 40.0)
        let availableHeight = max(1.0, layout.size.height - insets.top - insets.bottom - 24.0)
        let buttonWidth = min(248.0, contentWidth)
        let buttonHeight = showsButton ? self.buttonNode.updateLayout(width: buttonWidth, transition: transition) : 0.0
        let titleSize = isIntro ? self.titleNode.updateLayout(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)) : .zero
        let textSize = self.textNode.updateLayout(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let cameraIconSize = self.cameraIconNode.image?.size ?? .zero
        let cameraSize = showsCamera ? self.cameraTextNode.updateLayout(CGSize(width: max(1.0, contentWidth - cameraIconSize.width - 10.0), height: .greatestFiniteMagnitude)) : .zero
        let cameraHeight = showsCamera ? max(44.0, cameraSize.height + 12.0) : 0.0
        let bodyHeight = titleSize.height + (isIntro ? 12.0 : 0.0) + textSize.height + (showsButton ? 20.0 + buttonHeight : 0.0) + (showsCamera ? 13.0 + cameraHeight : 0.0)
        let imageSize = CGSize(width: layout.size.width <= 320.0 ? 112.0 : 144.0, height: layout.size.width <= 320.0 ? 112.0 : 144.0)
        let geometry = mediaPlaceholderGeometry(availableHeight: availableHeight, bodyHeight: bodyHeight, imageHeight: imageSize.height, portrait: layout.size.width < layout.size.height)
        let imageHeight = geometry.imageHeight
        let totalHeight = geometry.contentHeight
        let top = insets.top + 12.0 + geometry.topOffset
        let centerX = layout.safeInsets.left + contentWidth / 2.0 + 20.0

        transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: .zero, size: layout.size))
        self.scrollNode.view.contentSize = CGSize(width: layout.size.width, height: max(layout.size.height, top + totalHeight + insets.bottom + 12.0))
        self.scrollNode.view.scrollIndicatorInsets = insets
        self.animationNode.visibility = imageHeight > 0.0
        self.animationNode.isHidden = imageHeight == 0.0
        transition.updateFrame(node: self.animationNode, frame: CGRect(x: centerX - imageSize.width / 2.0, y: top, width: imageSize.width, height: imageSize.height))
        self.animationNode.updateLayout(size: imageSize)
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: centerX - titleSize.width / 2.0, y: top + imageHeight), size: titleSize))
        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: centerX - textSize.width / 2.0, y: self.titleNode.frame.maxY + (isIntro ? 12.0 : 0.0)), size: textSize))
        transition.updateFrame(node: self.buttonNode, frame: CGRect(x: centerX - buttonWidth / 2.0, y: self.textNode.frame.maxY + 20.0, width: buttonWidth, height: buttonHeight))
        let cameraWidth = min(contentWidth, cameraSize.width + cameraIconSize.width + 10.0)
        transition.updateFrame(node: self.cameraButtonNode, frame: CGRect(x: centerX - cameraWidth / 2.0, y: self.buttonNode.frame.maxY + 13.0, width: cameraWidth, height: cameraHeight))
        transition.updateFrame(node: self.cameraIconNode, frame: CGRect(origin: CGPoint(x: 0.0, y: floor((cameraHeight - cameraIconSize.height) / 2.0)), size: cameraIconSize))
        transition.updateFrame(node: self.cameraTextNode, frame: CGRect(origin: CGPoint(x: cameraIconSize.width + 10.0, y: floor((cameraHeight - cameraSize.height) / 2.0)), size: cameraSize))
    }
}
