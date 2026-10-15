import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import AccountContext
import SolidRoundedButtonNode

final class AttachmentFileEmptyStateItem: ItemListControllerEmptyStateItem {
    enum Content: Equatable {
        case intro
        case bannedSendMedia(text: String, canBoost: Bool)
    }
    
    let context: AccountContext
    let theme: PresentationTheme
    let strings: PresentationStrings
    let content: Content
    let reduceMotion: Bool
    
    init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings, content: Content) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.content = content
        self.reduceMotion = context.sharedContext.currentPresentationData.with { $0.reduceMotion }
    }
    
    func isEqual(to: ItemListControllerEmptyStateItem) -> Bool {
        if let item = to as? AttachmentFileEmptyStateItem {
            return self.theme === item.theme && self.strings === item.strings && self.content == item.content && self.reduceMotion == item.reduceMotion
        } else {
            return false
        }
    }
    
    func node(current: ItemListControllerEmptyStateItemNode?) -> ItemListControllerEmptyStateItemNode {
        if let current = current as? AttachmentFileEmptyStateItemNode {
            current.item = self
            return current
        } else {
            return AttachmentFileEmptyStateItemNode(item: self)
        }
    }
}

final class AttachmentFileEmptyStateItemNode: ItemListControllerEmptyStateItemNode {
    private var animationNode: AnimatedStickerNode
    private let textNode: ASTextNode
    private let buttonNode: SolidRoundedButtonNode
    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var animationName: String?
    private var animationReduceMotion: Bool?

    private var showsButton: Bool {
        if case .bannedSendMedia(_, true) = self.item.content { return true }
        return false
    }
    
    var item: AttachmentFileEmptyStateItem {
        didSet {
            self.updateThemeAndStrings(theme: self.item.theme, strings: self.item.strings)
            if let (layout, navigationHeight) = self.validLayout {
                self.updateLayout(layout: layout, navigationBarHeight: navigationHeight, transition: .immediate)
            }
        }
    }
    
    init(item: AttachmentFileEmptyStateItem) {
        self.item = item
        
        self.animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: item.context.lottieRenderingSettings)
        self.animationNode.visibility = true
        
        self.textNode = ASTextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.lineSpacing = 0.1
        self.textNode.textAlignment = .center
        
        self.buttonNode = SolidRoundedButtonNode(theme: SolidRoundedButtonTheme(backgroundColor: .black, foregroundColor: .white), height: 52.0, cornerRadius: 26.0, isShimmering: true)
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        self.addSubnode(self.animationNode)
        self.addSubnode(self.textNode)
        
        self.updateThemeAndStrings(theme: self.item.theme, strings: self.item.strings)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilitySettingsChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.accessibilitySettingsChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accessibilitySettingsChanged() {
        self.updateThemeAndStrings(theme: self.item.theme, strings: self.item.strings)
        if let (layout, navigationHeight) = self.validLayout {
            self.updateLayout(layout: layout, navigationBarHeight: navigationHeight, transition: .immediate)
        }
    }
    
    private func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        let text: String
        let name: String
        let playbackMode: AnimatedStickerPlaybackMode
        let reduceMotion = self.item.reduceMotion || UIAccessibility.isReduceMotionEnabled
        switch self.item.content {
            case .intro:
                text = strings.Attachment_FilesIntro
                name = "Files"
                playbackMode = reduceMotion ? .still(.start) : .loop
            case let .bannedSendMedia(banDescription, _):
                text = banDescription
                name = "Banned"
                playbackMode = reduceMotion ? .still(.start) : .once
        }
        if self.animationName != name || self.animationReduceMotion != reduceMotion {
            self.animationName = name
            self.animationReduceMotion = reduceMotion
            self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: name), width: 320, height: 320, playbackMode: playbackMode, mode: .direct(cachePathPrefix: nil))
        }
        let label = text.replacingOccurrences(of: "\n", with: " ")
        self.textNode.attributedText = NSAttributedString(string: label, font: theme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .body) : Font.regular(15.0), textColor: theme.list.freeTextColor, paragraphAlignment: .center)
        self.textNode.isAccessibilityElement = true
        self.textNode.accessibilityLabel = label
        self.buttonNode.title = strings.Attachment_OpenSettings
        self.buttonNode.updateTheme(SolidRoundedButtonTheme(theme: theme))
        if self.showsButton {
            if self.buttonNode.supernode == nil { self.addSubnode(self.buttonNode) }
        } else {
            self.buttonNode.removeFromSupernode()
        }
    }
    
    override func updateLayout(layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)
      
        var imageSize = CGSize(width: 144.0, height: 144.0)
        var insets = layout.insets(options: [.input])
        insets.top = max(insets.top, navigationBarHeight)
        if layout.size.width == 320.0 {
            imageSize = CGSize(width: 112.0, height: 112.0)
        }
        
        let imageSpacing: CGFloat = 12.0
        let buttonSpacing: CGFloat = 15.0
        let bottomSpacing: CGFloat = 33.0
        
        let contentWidth = max(1.0, layout.size.width - layout.safeInsets.left - layout.safeInsets.right - 40.0)
        let availableHeight = max(1.0, layout.size.height - insets.top - insets.bottom)
        let buttonWidth: CGFloat = min(248.0, contentWidth)
        let buttonHeight = self.showsButton ? self.buttonNode.updateLayout(width: buttonWidth, transition: transition) : 0.0
        let buttonBlockHeight = self.showsButton ? buttonSpacing + buttonHeight : 0.0
        
        let textSize = self.textNode.updateLayout(CGSize(width: contentWidth, height: max(1.0, availableHeight - buttonBlockHeight - bottomSpacing)))
        let imageHeight = layout.size.width < layout.size.height && contentWidth >= imageSize.width && imageSize.height + imageSpacing + textSize.height + buttonBlockHeight + bottomSpacing <= availableHeight ? imageSize.height + imageSpacing : 0.0
        
        let totalHeight = imageHeight + textSize.height + buttonBlockHeight + bottomSpacing
        let topOffset = insets.top + max(0.0, floor((availableHeight - totalHeight) / 2.0))
        
        transition.updateAlpha(node: self.animationNode, alpha: imageHeight > 0.0 ? 1.0 : 0.0)
        self.animationNode.visibility = imageHeight > 0.0
        transition.updateFrame(node: self.animationNode, frame: CGRect(origin: CGPoint(x: floor((layout.size.width - imageSize.width) / 2.0), y: topOffset), size: imageSize))
        self.animationNode.updateLayout(size: imageSize)
        
        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: layout.safeInsets.left + floor((layout.size.width - textSize.width - layout.safeInsets.left - layout.safeInsets.right) / 2.0), y: topOffset + imageHeight), size: textSize))
        
        transition.updateFrame(node: self.buttonNode, frame: CGRect(origin: CGPoint(x: layout.safeInsets.left + floor((layout.size.width - buttonWidth - layout.safeInsets.left - layout.safeInsets.right) / 2.0), y: self.textNode.frame.maxY + buttonSpacing), size: CGSize(width: buttonWidth, height: buttonHeight)))
    }
}
