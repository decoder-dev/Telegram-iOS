import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import TelegramPresentationData
import AvatarNode
import AccountContext

struct EditableTokenListToken {
    enum Subject {
        case peer(EnginePeer)
        case category(UIImage?)
        case emoji(String)
    }
    
    let id: AnyHashable
    let title: String
    let fixedPosition: Int?
    let subject: Subject
}

private let caretIndicatorImage = generateVerticallyStretchableFilledCircleImage(radius: 1.0, color: UIColor(rgb: 0x3350ee))

private func caretAnimation() -> CAAnimation {
    let animation = CAKeyframeAnimation(keyPath: "opacity")
    animation.values = [1.0 as NSNumber, 0.0 as NSNumber, 1.0 as NSNumber, 1.0 as NSNumber]
    let firstDuration = 0.3
    let secondDuration = 0.25
    let restDuration = 0.35
    let duration = firstDuration + secondDuration + restDuration
    let keyTimes: [NSNumber] = [0.0 as NSNumber, (firstDuration / duration) as NSNumber, ((firstDuration + secondDuration) / duration) as NSNumber, ((firstDuration + secondDuration + restDuration) / duration) as NSNumber]
    
    animation.keyTimes = keyTimes
    animation.duration = duration
    animation.repeatCount = Float.greatestFiniteMagnitude
    return animation
}

private func generateRemoveIcon(_ color: UIColor) -> UIImage? {
    return generateImage(CGSize(width: 22.0, height: 22.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0 - UIScreenPixel)
        context.setLineCap(.round)
        
        let length: CGFloat = 8.0
        context.move(to: CGPoint(x: 7.0, y: 7.0))
        context.addLine(to: CGPoint(x: 7.0 + length, y: 7.0 + length))
        context.strokePath()
        
        context.move(to: CGPoint(x: 7.0 + length, y: 7.0))
        context.addLine(to: CGPoint(x: 7.0, y: 7.0 + length))
        context.strokePath()
    })
}

final class EditableTokenListNodeTheme {
    let backgroundColor: UIColor
    let separatorColor: UIColor
    let placeholderTextColor: UIColor
    let primaryTextColor: UIColor
    let tokenBackgroundColor: UIColor
    let selectedTextColor: UIColor
    let selectedBackgroundColor: UIColor
    let accentColor: UIColor
    let keyboardColor: PresentationThemeKeyboardColor
    
    init(backgroundColor: UIColor, separatorColor: UIColor, placeholderTextColor: UIColor, primaryTextColor: UIColor, tokenBackgroundColor: UIColor, selectedTextColor: UIColor, selectedBackgroundColor: UIColor, accentColor: UIColor, keyboardColor: PresentationThemeKeyboardColor) {
        self.backgroundColor = backgroundColor
        self.separatorColor = separatorColor
        self.placeholderTextColor = placeholderTextColor
        self.primaryTextColor = primaryTextColor
        self.tokenBackgroundColor = tokenBackgroundColor
        self.selectedTextColor = selectedTextColor
        self.selectedBackgroundColor = selectedBackgroundColor
        self.accentColor = accentColor
        self.keyboardColor = keyboardColor
    }
}

private final class TokenNode: ASDisplayNode {
    private let context: AccountContext
    private let presentationTheme: PresentationTheme
    
    let theme: EditableTokenListNodeTheme
    let token: EditableTokenListToken
    let avatarNode: AvatarNode
    let categoryAvatarNode: ASImageNode
    let emojiTextNode: ImmediateTextNode
    let removeIconNode: ASImageNode
    let titleNode: ASTextNode
    let backgroundNode: ASImageNode
    let selectedBackgroundNode: ASImageNode
    var activate: (() -> Bool)?
    private var titleFont: UIFont {
        return self.presentationTheme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .subheadline) : Font.regular(14.0)
    }
    var isSelected: Bool = false
    //        didSet {
    //            if self.isSelected != oldValue {
    //                self.titleNode.attributedText = NSAttributedString(string: token.title, font: self.titleFont, textColor: self.isSelected ? self.theme.selectedTextColor : self.theme.primaryTextColor)
    //                self.titleNode.redrawIfPossible()
    //                self.backgroundNode.isHidden = self.isSelected
    //                self.selectedBackgroundNode.isHidden = !self.isSelected
    //
    //                self.avatarNode.isHidden = self.isSelected
    //                self.categoryAvatarNode.isHidden = self.isSelected
    //                self.removeIconNode.isHidden = !self.isSelected
    //            }
    //        }
    //    }
    
    init(context: AccountContext, presentationTheme: PresentationTheme, theme: EditableTokenListNodeTheme, token: EditableTokenListToken, isSelected: Bool) {
        self.context = context
        self.presentationTheme = presentationTheme
        self.theme = theme
        self.token = token
        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 13.0))
        self.categoryAvatarNode = ASImageNode()
        self.categoryAvatarNode.displaysAsynchronously = false
        self.categoryAvatarNode.displayWithoutProcessing = true
        self.emojiTextNode = ImmediateTextNode()
        
        self.removeIconNode = ASImageNode()
        self.removeIconNode.alpha = 0.0
        self.removeIconNode.displaysAsynchronously = false
        self.removeIconNode.displayWithoutProcessing = true
        self.removeIconNode.image = generateRemoveIcon(theme.selectedTextColor)
        
        let tokenFont = presentationTheme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .subheadline) : Font.regular(14.0)
        let cornerRadius: CGFloat
        switch token.subject {
        case .peer:
            cornerRadius = max(24.0, ceil(tokenFont.lineHeight) + 6.0)
        case .category:
            cornerRadius = 14.0
        case .emoji:
            cornerRadius = max(24.0, ceil(tokenFont.lineHeight) + 6.0)
        }
        
        self.backgroundNode = ASImageNode()
        self.backgroundNode.displaysAsynchronously = false
        self.backgroundNode.displayWithoutProcessing = true
        self.backgroundNode.image = generateStretchableFilledCircleImage(diameter: cornerRadius, color: theme.tokenBackgroundColor)
        
        self.selectedBackgroundNode = ASImageNode()
        self.selectedBackgroundNode.alpha = 0.0
        self.selectedBackgroundNode.displaysAsynchronously = false
        self.selectedBackgroundNode.displayWithoutProcessing = true
        self.selectedBackgroundNode.image = generateStretchableFilledCircleImage(diameter: cornerRadius, color: theme.selectedBackgroundColor)
                
        super.init()
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.selectedBackgroundNode)
        self.titleNode.attributedText = NSAttributedString(string: token.title, font: self.titleFont, textColor: self.isSelected ? self.theme.selectedTextColor : self.theme.primaryTextColor)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.removeIconNode)
        
        switch token.subject {
        case let .peer(peer):
            self.addSubnode(self.avatarNode)
            self.avatarNode.setPeer(context: context, theme: presentationTheme, peer: peer)
        case let .category(image):
            self.addSubnode(self.categoryAvatarNode)
            self.categoryAvatarNode.image = image
        case let .emoji(emoji):
            self.addSubnode(self.emojiTextNode)
            self.emojiTextNode.attributedText = NSAttributedString(string: emoji, font: Font.regular(17.0), textColor: .white)
        }
        
        self.isAccessibilityElement = true
        self.accessibilityLabel = token.title
        self.accessibilityTraits = .button
        self.updateIsSelected(isSelected, animated: false)
    }

    override func accessibilityActivate() -> Bool {
        return self.activate?() ?? false
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let emojiInset: CGFloat = self.emojiTextNode.supernode == nil ? 0.0 : 3.0
        let titleSize = self.titleNode.measure(CGSize(width: max(1.0, constrainedSize.width - 38.0 - emojiInset), height: constrainedSize.height))
        if self.emojiTextNode.supernode != nil {
            let _ = self.emojiTextNode.updateLayout(constrainedSize)
        }
        return CGSize(width: min(constrainedSize.width, 22.0 + titleSize.width + 16.0 + emojiInset), height: max(28.0, titleSize.height + 10.0))
    }
    
    override func layout() {
        let titleSize = self.titleNode.calculatedSize
        if titleSize.width.isZero {
            return
        }
        self.backgroundNode.frame = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        self.selectedBackgroundNode.frame = self.bounds.insetBy(dx: 2.0, dy: 2.0)
        self.avatarNode.frame = CGRect(origin: CGPoint(x: 3.0, y: floor((self.bounds.height - 22.0) / 2.0)), size: CGSize(width: 22.0, height: 22.0))
        self.categoryAvatarNode.frame = self.avatarNode.frame
        self.removeIconNode.frame = self.avatarNode.frame
        
        var textLeftOffset: CGFloat = 29.0
        if let emojiTextSize = self.emojiTextNode.cachedLayout?.size {
            self.emojiTextNode.frame = CGRect(origin: CGPoint(x: 7.0, y: floor((self.bounds.height - emojiTextSize.height) / 2.0)), size: emojiTextSize)
            textLeftOffset += 3.0
        }
        
        self.titleNode.frame = CGRect(origin: CGPoint(x: textLeftOffset, y: floor((self.bounds.size.height - titleSize.height) / 2.0)), size: titleSize)
    }
    
    func updateIsSelected(_ isSelected: Bool, animated: Bool) {
        guard self.isSelected != isSelected else {
            return
        }
        self.isSelected = isSelected
        self.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        
        self.avatarNode.alpha = isSelected ? 0.0 : 1.0
        self.categoryAvatarNode.alpha = isSelected ? 0.0 : 1.0
        self.emojiTextNode.alpha = isSelected ? 0.0 : 1.0
        self.removeIconNode.alpha = isSelected ? 1.0 : 0.0
        
        if animated && !UIAccessibility.isReduceMotionEnabled && !self.context.sharedContext.currentPresentationData.with({ $0.reduceMotion }) {
            if isSelected {
                self.selectedBackgroundNode.alpha = 1.0
                self.selectedBackgroundNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                
                self.avatarNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                self.avatarNode.layer.animateScale(from: 1.0, to: 0.01, duration: 0.2)
                
                self.categoryAvatarNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                self.categoryAvatarNode.layer.animateScale(from: 1.0, to: 0.01, duration: 0.2)
                
                self.emojiTextNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                self.emojiTextNode.layer.animateScale(from: 1.0, to: 0.01, duration: 0.2)
                
                self.removeIconNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                self.removeIconNode.layer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
            } else {
                self.selectedBackgroundNode.alpha = 0.0
                self.selectedBackgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                
                self.avatarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                self.avatarNode.layer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                
                self.categoryAvatarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                self.categoryAvatarNode.layer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                
                self.emojiTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                self.emojiTextNode.layer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                
                self.removeIconNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                self.removeIconNode.layer.animateScale(from: 1.0, to: 0.01, duration: 0.2)
            }
            
            if let snapshotView = self.titleNode.view.snapshotContentTree() {
                self.titleNode.view.superview?.addSubview(snapshotView)
                snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                    snapshotView?.removeFromSuperview()
                })
            }
            self.titleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        }
        
        self.titleNode.attributedText = NSAttributedString(string: token.title, font: self.titleFont, textColor: self.isSelected ? self.theme.selectedTextColor : self.theme.primaryTextColor)
        self.titleNode.redrawIfPossible()
    }
}

private final class CaretIndicatorNode: ASImageNode {
    override func willEnterHierarchy() {
        super.willEnterHierarchy()
        
        if self.layer.animation(forKey: "blink") == nil {
            self.layer.add(caretAnimation(), forKey: "blink")
        }
    }
}

final class EditableTokenListNode: ASDisplayNode, UITextFieldDelegate {
    private let context: AccountContext
    private var presentationTheme: PresentationTheme
    
    private var theme: EditableTokenListNodeTheme
    private let backgroundNode: NavigationBackgroundNode
    private let scrollNode: ASScrollNode
    private let placeholderNode: ASTextNode
    private var tokenNodes: [TokenNode] = []
    private let separatorNode: ASDisplayNode
    private let textFieldScrollNode: ASScrollNode
    private let textFieldNode: TextFieldNode
    private let caretIndicatorNode: CaretIndicatorNode
    private var selectedTokenId: AnyHashable?
    
    var isFocused: Bool {
        return self.textFieldNode.view.isFirstResponder
    }
    
    var textUpdated: ((String) -> Void)?
    var deleteToken: ((AnyHashable) -> Void)?
    var textReturned: (() -> Void)?
    var isFirstResponderChanged: (() -> Void)?
    
    init(context: AccountContext, presentationTheme: PresentationTheme, theme: EditableTokenListNodeTheme, placeholder: String) {
        self.context = context
        self.presentationTheme = presentationTheme
        self.theme = theme

        self.backgroundNode = NavigationBackgroundNode(color: theme.backgroundColor)
        
        self.scrollNode = ASScrollNode()
        self.scrollNode.view.alwaysBounceVertical = true
        self.scrollNode.view.scrollsToTop = false
        
        self.placeholderNode = ASTextNode()
        self.placeholderNode.isUserInteractionEnabled = false
        self.placeholderNode.maximumNumberOfLines = 1
        self.placeholderNode.displaysAsynchronously = false
        self.placeholderNode.attributedText = NSAttributedString(string: placeholder, font: Font.regular(15.0), textColor: theme.placeholderTextColor)
        
        self.textFieldScrollNode = ASScrollNode()
        self.textFieldScrollNode.view.scrollsToTop = false
        
        self.textFieldNode = TextFieldNode()
        self.textFieldNode.textField.font = Font.regular(15.0)
        self.textFieldNode.textField.textColor = theme.primaryTextColor
        self.textFieldNode.textField.autocorrectionType = .no
        self.textFieldNode.textField.returnKeyType = .done
        self.textFieldNode.textField.keyboardAppearance = theme.keyboardColor.keyboardAppearance
        self.textFieldNode.textField.tintColor = theme.accentColor
        
        self.caretIndicatorNode = CaretIndicatorNode()
        self.caretIndicatorNode.isLayerBacked = true
        self.caretIndicatorNode.displayWithoutProcessing = true
        self.caretIndicatorNode.displaysAsynchronously = false
        self.caretIndicatorNode.image = caretIndicatorImage
        
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        self.separatorNode.backgroundColor = theme.separatorColor
        
        super.init()
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.scrollNode)

        self.addSubnode(self.separatorNode)
        self.scrollNode.addSubnode(self.placeholderNode)
        self.scrollNode.addSubnode(self.textFieldScrollNode)
        self.textFieldScrollNode.addSubnode(self.textFieldNode)
        
        self.textFieldNode.textField.delegate = self
        self.textFieldNode.textField.addTarget(self, action: #selector(self.textFieldChanged(_:)), for: .editingChanged)
        self.textFieldNode.textField.didDeleteBackwardWhileEmpty = { [weak self] in
            if let strongSelf = self {
                if let selectedTokenId = strongSelf.selectedTokenId {
                    strongSelf.deleteToken?(selectedTokenId)
                    strongSelf.updateSelectedTokenId(nil)
                } else if let tokenNode = strongSelf.tokenNodes.last {
                    strongSelf.updateSelectedTokenId(tokenNode.token.id, animated: true)
                }
            }
        }
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }
    
    func updatePresentation(presentationTheme: PresentationTheme, theme: EditableTokenListNodeTheme, placeholder: String) {
        let font = presentationTheme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .subheadline) : Font.regular(15.0)
        let rebuildChips = self.presentationTheme !== presentationTheme || self.textFieldNode.textField.font?.pointSize != font.pointSize
        self.presentationTheme = presentationTheme
        self.theme = theme
        self.backgroundNode.updateColor(color: theme.backgroundColor, transition: .immediate)
        self.separatorNode.backgroundColor = theme.separatorColor
        self.placeholderNode.attributedText = NSAttributedString(string: placeholder, font: font, textColor: theme.placeholderTextColor)
        self.textFieldNode.textField.font = font
        self.textFieldNode.textField.textColor = theme.primaryTextColor
        self.textFieldNode.textField.tintColor = theme.accentColor
        self.textFieldNode.textField.accessibilityLabel = placeholder
        let keyboardAppearance = theme.keyboardColor.keyboardAppearance
        if self.textFieldNode.textField.keyboardAppearance != keyboardAppearance {
            self.textFieldNode.textField.keyboardAppearance = keyboardAppearance
            if self.isFocused { self.textFieldNode.textField.reloadInputViews() }
        }
        self.caretIndicatorNode.image = generateVerticallyStretchableFilledCircleImage(radius: 1.0, color: theme.accentColor)
        if rebuildChips {
            for tokenNode in self.tokenNodes { tokenNode.removeFromSupernode() }
            self.tokenNodes.removeAll()
        }
    }

    func updateLayout(tokens: [EditableTokenListToken], width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled || self.context.sharedContext.currentPresentationData.with({ $0.reduceMotion })
        let transition: ContainedViewLayoutTransition = reduceMotion ? .immediate : transition
        let rowHeight = max(28.0, ceil(self.textFieldNode.textField.font?.lineHeight ?? 18.0) + 10.0)
        let validTokens = Set<AnyHashable>(tokens.map { $0.id })
        
        for i in (0 ..< self.tokenNodes.count).reversed() {
            let tokenNode = tokenNodes[i]
            if !validTokens.contains(tokenNode.token.id) {
                self.tokenNodes.remove(at: i)
                if case .immediate = transition {
                    tokenNode.removeFromSupernode()
                } else {
                    tokenNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak tokenNode] _ in
                        tokenNode?.removeFromSupernode()
                    })
                    tokenNode.layer.animateScale(from: 1.0, to: 0.2, duration: 0.2, removeOnCompletion: false)
                }
            }
        }
        
        if let selectedTokenId = self.selectedTokenId, !validTokens.contains(selectedTokenId) {
            self.selectedTokenId = nil
        }
        
        let sideInset: CGFloat = 12.0 + leftInset
        let rightSideInset: CGFloat = 12.0 + rightInset
        let verticalInset: CGFloat = 6.0
        
        var animationDelay = 0.0
        var currentOffset = CGPoint(x: sideInset, y: verticalInset)
        var currentRowHeight = rowHeight
        for token in tokens {
            var currentNode: TokenNode?
            for node in self.tokenNodes {
                if node.token.id == token.id {
                    if node.token.title == token.title && node.token.fixedPosition == token.fixedPosition {
                        currentNode = node
                    } else {
                        node.removeFromSupernode()
                        self.tokenNodes.removeAll(where: { $0 === node })
                    }
                    break
                }
            }
            let tokenNode: TokenNode
            var animateIn = false
            if let currentNode = currentNode {
                tokenNode = currentNode
            } else {
                tokenNode = TokenNode(context: self.context, presentationTheme: self.presentationTheme, theme: self.theme, token: token, isSelected: self.selectedTokenId == token.id)
                tokenNode.activate = { [weak self, weak tokenNode] in
                    guard let self, let tokenNode else { return false }
                    if tokenNode.isSelected {
                        self.deleteToken?(tokenNode.token.id)
                    } else {
                        self.updateSelectedTokenId(tokenNode.token.id, animated: true)
                    }
                    return true
                }
                self.tokenNodes.append(tokenNode)
                self.scrollNode.addSubnode(tokenNode)
                animateIn = true
            }
            
            let tokenSize = tokenNode.measure(CGSize(width: max(1.0, width - sideInset - rightSideInset), height: CGFloat.greatestFiniteMagnitude))
            if tokenSize.width + currentOffset.x >= width - rightSideInset && !currentOffset.x.isEqual(to: sideInset) {
                currentOffset.x = sideInset
                currentOffset.y += currentRowHeight
                currentRowHeight = rowHeight
            }
            currentRowHeight = max(currentRowHeight, tokenSize.height)
            let tokenFrame = CGRect(origin: CGPoint(x: currentOffset.x, y: currentOffset.y), size: tokenSize)
            currentOffset.x += ceil(tokenSize.width)
            
            if animateIn {
                tokenNode.frame = tokenFrame
                if !reduceMotion {
                    tokenNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                    tokenNode.layer.animateSpring(from: 0.2 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.4)
                }
            } else {
                if case .immediate = transition {
                    transition.updateFrame(node: tokenNode, frame: tokenFrame)
                } else {
                    let previousFrame = tokenNode.frame
                    if !previousFrame.origin.y.isEqual(to: tokenFrame.origin.y) && previousFrame.size.width.isEqual(to: tokenFrame.size.width) {
                        let initialStartPosition = CGPoint(x: previousFrame.midX, y: previousFrame.midY)
                        let initialEndPosition = CGPoint(x: previousFrame.midY > tokenFrame.midY ? -previousFrame.size.width / 2.0 : width, y: previousFrame.midY)
                        let targetStartPosition = CGPoint(x: (previousFrame.midY > tokenFrame.midY ? (width + tokenFrame.size.width) : -tokenFrame.size.width), y: tokenFrame.midY)
                        let targetEndPosition = CGPoint(x: tokenFrame.midX, y: tokenFrame.midY)
                        tokenNode.frame = tokenFrame
                        
                        let initialAnimation = tokenNode.layer.makeAnimation(from: NSValue(cgPoint: initialStartPosition), to: NSValue(cgPoint: initialEndPosition), keyPath: "position", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: 0.12, mediaTimingFunction: nil, removeOnCompletion: true, additive: false, completion: nil)
                        let targetAnimation = tokenNode.layer.makeAnimation(from: NSValue(cgPoint: targetStartPosition), to: NSValue(cgPoint: targetEndPosition), keyPath: "position", timingFunction: kCAMediaTimingFunctionSpring, duration: 0.2 + animationDelay, mediaTimingFunction: nil, removeOnCompletion: true, additive: false, completion: nil)
                        tokenNode.layer.animateGroup([initialAnimation, targetAnimation], key: "slide")
                        animationDelay += 0.025
                    } else {
                        if !previousFrame.size.width.isEqual(to: tokenFrame.size.width) {
                            tokenNode.frame = tokenFrame
                        } else {
                            let initialStartPosition = CGPoint(x: previousFrame.midX, y: previousFrame.midY)
                            let targetEndPosition = CGPoint(x: tokenFrame.midX, y: tokenFrame.midY)
                            tokenNode.frame = tokenFrame
                            
                            let targetAnimation = tokenNode.layer.makeAnimation(from: NSValue(cgPoint: initialStartPosition), to: NSValue(cgPoint: targetEndPosition), keyPath: "position", timingFunction: kCAMediaTimingFunctionSpring, duration: 0.2 + animationDelay, mediaTimingFunction: nil, removeOnCompletion: true, additive: false, completion: nil)
                            tokenNode.layer.animateGroup([targetAnimation], key: "slide")
                            animationDelay += 0.025
                        }
                    }
                }
            }
        }
        
        let placeholderSize = self.placeholderNode.measure(CGSize(width: max(1.0, width - sideInset - rightSideInset), height: CGFloat.greatestFiniteMagnitude))
        if width - currentOffset.x - rightSideInset < placeholderSize.width + 4.0 {
            currentOffset.y += currentRowHeight
            currentOffset.x = sideInset
            currentRowHeight = rowHeight
        }
        currentRowHeight = max(currentRowHeight, rowHeight)
        transition.updateFrame(node: self.placeholderNode, frame: CGRect(origin: CGPoint(x: currentOffset.x + 4.0, y: currentOffset.y + floor((rowHeight - placeholderSize.height) / 2.0)), size: placeholderSize))
        
        let textNodeFrame = CGRect(origin: CGPoint(x: currentOffset.x + 4.0, y: currentOffset.y + UIScreenPixel), size: CGSize(width: max(1.0, width - currentOffset.x - rightSideInset - 8.0), height: rowHeight))
        let caretHeight = max(19.0, (self.textFieldNode.textField.font?.lineHeight ?? 19.0))
        let caretNodeFrame = CGRect(x: textNodeFrame.minX, y: textNodeFrame.minY + floor((rowHeight - caretHeight) / 2.0), width: 2.0, height: caretHeight)
        if case .immediate = transition {
            transition.updateFrame(node: self.textFieldScrollNode, frame: textNodeFrame)
            transition.updateFrame(node: self.textFieldNode, frame: CGRect(origin: CGPoint(), size: textNodeFrame.size))
            transition.updateFrame(node: self.caretIndicatorNode, frame: caretNodeFrame)
        } else {
            let previousFrame = self.textFieldScrollNode.frame
            self.textFieldScrollNode.frame = textNodeFrame
            self.textFieldScrollNode.layer.animateFrame(from: previousFrame, to: textNodeFrame, duration: 0.2 + animationDelay, timingFunction: kCAMediaTimingFunctionSpring)
            
            transition.updateFrame(node: self.textFieldNode, frame: CGRect(origin: CGPoint(), size: textNodeFrame.size))
            
            let previousCaretFrame = self.caretIndicatorNode.frame
            self.caretIndicatorNode.frame = caretNodeFrame
            self.caretIndicatorNode.layer.animateFrame(from: previousCaretFrame, to: caretNodeFrame, duration: 0.2 + animationDelay, timingFunction: kCAMediaTimingFunctionSpring)
        }
        
        let previousContentHeight = self.scrollNode.view.contentSize.height
        let contentHeight = currentOffset.y + currentRowHeight + 1.0 + verticalInset
        let nodeHeight = min(contentHeight, max(140.0, rowHeight * 3.0 + verticalInset * 2.0))
        
        transition.updateFrame(node: self.separatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: width, height: UIScreenPixel)))
        transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: width, height: nodeHeight)))
        
        if !abs(previousContentHeight - contentHeight).isLess(than: CGFloat.ulpOfOne) {
            let contentOffset = CGPoint(x: 0.0, y: max(0.0, contentHeight - nodeHeight))
            if case .immediate = transition {
                self.scrollNode.view.contentOffset = contentOffset
            } else {
                transition.updateBounds(node: self.scrollNode, bounds: CGRect(origin: CGPoint(x: 0.0, y: contentOffset.y), size: self.scrollNode.bounds.size))
            }
        }
        self.scrollNode.view.contentSize = CGSize(width: width, height: contentHeight)

        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: width, height: nodeHeight)))
        self.backgroundNode.update(size: self.backgroundNode.bounds.size, transition: transition)
        
        return nodeHeight
    }
    
    @objc func textFieldChanged(_ textField: UITextField) {
        let text = textField.text ?? ""
        self.placeholderNode.isHidden = !text.isEmpty
        self.updateSelectedTokenId(nil)
        self.textUpdated?(text)
        if !text.isEmpty {
            self.scrollNode.view.scrollRectToVisible(textFieldScrollNode.frame.offsetBy(dx: 0.0, dy: 7.0), animated: true)
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.textReturned?()
        return false
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.isFirstResponderChanged?()
        /*if self.caretIndicatorNode.supernode == self {
            self.caretIndicatorNode.removeFromSupernode()
        }*/
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        self.isFirstResponderChanged?()
        /*if self.caretIndicatorNode.supernode != self.scrollNode {
            self.scrollNode.addSubnode(self.caretIndicatorNode)
        }*/
    }
    
    func setText(_ text: String) {
        self.textFieldNode.textField.text = text
        self.textFieldChanged(self.textFieldNode.textField)
    }
    
    private func updateSelectedTokenId(_ id: AnyHashable?, animated: Bool = false) {
        self.selectedTokenId = id
        for tokenNode in self.tokenNodes {
            tokenNode.updateIsSelected(id == tokenNode.token.id, animated: animated)
        }
        if id != nil && !self.textFieldNode.textField.isFirstResponder {
            self.textFieldNode.textField.becomeFirstResponder()
        }
    }
    
    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            let point = recognizer.location(in: self.view)
            for tokenNode in self.tokenNodes {
                let convertedPoint = self.view.convert(point, to: tokenNode.view)
                if tokenNode.bounds.contains(convertedPoint) {
                    if tokenNode.isSelected {
                        self.deleteToken?(tokenNode.token.id)
                    } else {
                        self.updateSelectedTokenId(tokenNode.token.id, animated: true)
                    }
                    break
                }
            }
        }
    }
}
