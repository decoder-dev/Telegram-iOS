import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import AuthorizationUtils
import AuthenticationServices
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import SolidRoundedButtonNode

final class AuthorizationDividerNode: ASDisplayNode {
    private let theme: PresentationTheme
    private let strings: PresentationStrings
    private let titleNode: ImmediateTextNode
    private let leftLineNode: ASDisplayNode
    private let rightLineNode: ASDisplayNode
    
    init(theme: PresentationTheme, strings: PresentationStrings) {
        self.theme = theme
        self.strings = strings
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.attributedText = NSAttributedString(string: strings.Login_Or, font: Font.regular(17.0), textColor: theme.list.itemSecondaryTextColor)

        self.leftLineNode = ASDisplayNode()
        self.leftLineNode.backgroundColor = theme.list.itemPlainSeparatorColor
        
        self.rightLineNode = ASDisplayNode()
        self.rightLineNode.backgroundColor = theme.list.itemPlainSeparatorColor
        
        super.init()
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.leftLineNode)
        self.addSubnode(self.rightLineNode)
    }
    
    func updateLayout(width: CGFloat) -> CGSize {
        self.titleNode.attributedText = NSAttributedString(string: self.strings.Login_Or, font: UIFont.preferredFont(forTextStyle: .body), textColor: self.theme.list.itemSecondaryTextColor)
        let lineSize = CGSize(width: 33.0, height: UIScreenPixel)
        let spacing: CGFloat = 7.0
        
        let titleSize = self.titleNode.updateLayout(CGSize(width: max(1.0, width - (lineSize.width + spacing) * 2.0), height: .greatestFiniteMagnitude))
       
        let height: CGFloat = max(40.0, titleSize.height + 16.0)
        let titleFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((width - titleSize.width) / 2.0), y: floor((height - titleSize.height) / 2.0)), size: titleSize)
        self.titleNode.frame = titleFrame
        self.leftLineNode.frame = CGRect(origin: CGPoint(x: titleFrame.minX - spacing - lineSize.width, y: floorToScreenPixels(height / 2.0)), size: lineSize)
        self.rightLineNode.frame = CGRect(origin: CGPoint(x: titleFrame.maxX + spacing, y: floorToScreenPixels(height / 2.0)), size: lineSize)
        return CGSize(width: width, height: height)
    }
}

final class AuthorizationSequenceEmailEntryControllerNode: ASDisplayNode, UITextFieldDelegate {
    private let strings: PresentationStrings
    private let theme: PresentationTheme
    private let mode: AuthorizationSequenceEmailEntryController.Mode
    private let formNode = AuthorizationFormNode()
    
    private let animationNode: AnimatedStickerNode
    private let titleNode: ASTextNode
    private let noticeNode: ASTextNode
    
    private let dividerNode: AuthorizationDividerNode
    private var signInWithAppleButton: UIControl?
    private let proceedNode: SolidRoundedButtonNode
    
    private let codeField: TextFieldNode
    private let codeSeparatorNode: ASDisplayNode
    
    private var layoutArguments: (ContainerViewLayout, CGFloat)?
    
    var currentEmail: String {
        return self.codeField.textField.text ?? ""
    }
    
    var proceedWithEmail: ((String) -> Void)?
    var signInWithApple: (() -> Void)?
    
    private var appleSignInAllowed = false
        
    var inProgress: Bool = false {
        didSet {
            self.codeField.alpha = self.inProgress ? 0.6 : 1.0
            self.updateButtonsVisibility(transition: .immediate)
            
            if self.inProgress != oldValue {
                if self.inProgress {
                    self.proceedNode.transitionToProgress()
                } else {
                    self.proceedNode.transitionFromProgress()
                }
            }
        }
    }
    
    private let appearanceTimestamp = CACurrentMediaTime()
    
    init(strings: PresentationStrings, theme: PresentationTheme, mode: AuthorizationSequenceEmailEntryController.Mode) {
        self.strings = strings
        self.theme = theme
        self.mode = mode
        
        self.animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: .noAccountFallback)
        self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: "IntroMail"), width: 256, height: 256, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
        
        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        self.noticeNode = ASTextNode()
        self.noticeNode.isUserInteractionEnabled = false
        self.noticeNode.displaysAsynchronously = false
        self.noticeNode.lineSpacing = 0.1
        self.noticeNode.attributedText = NSAttributedString(string: self.strings.LoginEmail_Description, font: Font.regular(16.0), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        
        if #available(iOS 13.0, *) {
            self.signInWithAppleButton = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: theme.overallDarkAppearance ? .white : .black)
            (self.signInWithAppleButton as? ASAuthorizationAppleIDButton)?.cornerRadius = 11
        }
        
        self.proceedNode = SolidRoundedButtonNode(title: self.strings.Login_Continue, theme: SolidRoundedButtonTheme(theme: self.theme), glass: false, height: 50.0, cornerRadius: 50.0 * 0.5)
        self.proceedNode.progressType = .embedded
        
        self.codeSeparatorNode = ASDisplayNode()
        self.codeSeparatorNode.isLayerBacked = true
        self.codeSeparatorNode.backgroundColor = self.theme.list.itemPlainSeparatorColor
        
        self.codeField = TextFieldNode()
        self.codeField.textField.font = Font.regular(20.0)
        self.codeField.textField.textColor = self.theme.list.itemPrimaryTextColor
        self.codeField.textField.textAlignment = .natural
        self.codeField.textField.autocorrectionType = .no
        self.codeField.textField.autocapitalizationType = .none
        self.codeField.textField.keyboardType = .emailAddress
        if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
            self.codeField.textField.textContentType = UITextContentType(rawValue: "")
        }
        self.codeField.textField.returnKeyType = .done
        self.codeField.textField.keyboardAppearance = self.theme.rootController.keyboardColor.keyboardAppearance
        self.codeField.textField.disableAutomaticKeyboardHandling = [.forward, .backward]
        self.codeField.textField.tintColor = self.theme.list.itemAccentColor
        self.codeField.textField.placeholder = self.strings.Login_AddEmailPlaceholder
                
        self.dividerNode = AuthorizationDividerNode(theme: self.theme, strings: self.strings)
        
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.backgroundColor = self.theme.list.plainBackgroundColor
        
        self.codeField.textField.delegate = self
        
        self.addSubnode(self.formNode)
        self.formNode.addSubnode(self.codeSeparatorNode)
        self.formNode.addSubnode(self.codeField)
        self.formNode.addSubnode(self.titleNode)
        self.addSubnode(self.proceedNode)
        self.formNode.addSubnode(self.noticeNode)
        self.formNode.addSubnode(self.animationNode)
        self.addSubnode(self.dividerNode)

        self.titleNode.isAccessibilityElement = true
        self.titleNode.accessibilityTraits = [.header]
        self.noticeNode.isAccessibilityElement = true
        self.codeField.textField.accessibilityLabel = self.strings.Login_AddEmailPlaceholder
        self.formNode.requestLayout = { [weak self] in
            guard let self, let (layout, navigationHeight) = self.layoutArguments else {
                return
            }
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
        }
        
        self.codeField.textField.addTarget(self, action: #selector(self.textDidChange), for: .editingChanged)
        self.proceedNode.pressed = { [weak self] in
            self?.proceedPressed()
        }
        self.signInWithAppleButton?.addTarget(self, action: #selector(self.signInWithApplePressed), for: .touchUpInside)
    }
    
    override func didLoad() {
        super.didLoad()
        
        if let signInWithAppleButton = self.signInWithAppleButton {
            self.view.addSubview(signInWithAppleButton)
        }
    }
    
    @objc private func textDidChange() {
        self.updateButtonsVisibility(transition: .animated(duration: 0.2, curve: .easeInOut))
    }
    
    private func updateButtonsVisibility(transition: ContainedViewLayoutTransition) {
        let showAppleSignIn = self.currentEmail.isEmpty && self.appleSignInAllowed
        self.proceedNode.isUserInteractionEnabled = !showAppleSignIn && !self.inProgress
        self.proceedNode.accessibilityElementsHidden = showAppleSignIn
        self.signInWithAppleButton?.isEnabled = showAppleSignIn && !self.inProgress
        self.signInWithAppleButton?.accessibilityElementsHidden = !showAppleSignIn
        if showAppleSignIn {
            transition.updateAlpha(node: self.proceedNode, alpha: 0.0)
            transition.updateAlpha(node: self.dividerNode, alpha: 1.0)
            if let signInWithAppleButton = self.signInWithAppleButton {
                transition.updateAlpha(layer: signInWithAppleButton.layer, alpha: 1.0)
            }
        } else {
            transition.updateAlpha(node: self.proceedNode, alpha: 1.0)
            transition.updateAlpha(node: self.dividerNode, alpha: 0.0)
            if let signInWithAppleButton = self.signInWithAppleButton {
                transition.updateAlpha(layer: signInWithAppleButton.layer, alpha: 0.0)
            }
        }
    }
    
    func updateData(appleSignInAllowed: Bool) {
        self.appleSignInAllowed = appleSignInAllowed
        if let (layout, navigationHeight) = self.layoutArguments {
            self.updateButtonsVisibility(transition: .immediate)
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let previousInputHeight = self.layoutArguments?.0.inputHeight ?? 0.0
        let newInputHeight = layout.inputHeight ?? 0.0
        
        self.layoutArguments = (layout, navigationBarHeight)
        
        var layout = layout
        if CACurrentMediaTime() - self.appearanceTimestamp < 2.0, newInputHeight < previousInputHeight {
            layout = layout.withUpdatedInputHeight(previousInputHeight)
        }
                
        var insets = layout.insets(options: [])
        insets.top = max(layout.statusBarHeight ?? 20.0, navigationBarHeight)
        if let inputHeight = layout.inputHeight {
            insets.bottom = max(inputHeight, insets.bottom)
        }
        
        let titleInset: CGFloat = layout.size.width > 320.0 ? 18.0 : 0.0
        
        self.titleNode.attributedText = NSAttributedString(string: self.mode == .setup ? self.strings.LoginEmail_Title : self.strings.Login_EnterNewEmailTitle, font: Font.bold(UIFont.preferredFont(forTextStyle: .title1).pointSize), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.noticeNode.attributedText = NSAttributedString(string: self.strings.LoginEmail_Description, font: UIFont.preferredFont(forTextStyle: .body), textColor: self.theme.list.itemSecondaryTextColor, paragraphAlignment: .center)
        let fieldFont = UIFont.preferredFont(forTextStyle: .title3)
        self.codeField.textField.font = fieldFont

        
        // iPhone Duo: beside a side strip the content keeps to the band between the side insets. With equal
        // insets (every other phone) it keeps the full width.
        let insetsDiffer = layout.safeInsets.left != layout.safeInsets.right
        let bandMinX: CGFloat = insetsDiffer ? layout.safeInsets.left : 0.0
        let bandWidth: CGFloat = insetsDiffer ? layout.size.width - layout.safeInsets.left - layout.safeInsets.right : layout.size.width
        
        let inset: CGFloat = 24.0
        let maximumWidth: CGFloat = min(430.0, bandWidth)
        
        // The bottom button and the divider above it span iPhone Duo's side strip; they keep clear only of a corner
        // block at the bottom.
        let bottomSideInsets = layout.bottomEdgeSideInsets()
        let bottomBandMinX: CGFloat = insetsDiffer ? bottomSideInsets.left : 0.0
        let bottomBandWidth: CGFloat = insetsDiffer ? layout.size.width - bottomSideInsets.left - bottomSideInsets.right : layout.size.width
        let bottomMaximumWidth: CGFloat = min(430.0, bottomBandWidth)
        
        let animationSize = CGSize(width: 100.0, height: 100.0)
        let titleSize = self.titleNode.measure(CGSize(width: max(1.0, maximumWidth - 48.0), height: CGFloat.greatestFiniteMagnitude))
        
        let noticeSize = self.noticeNode.measure(CGSize(width: max(1.0, maximumWidth - 48.0), height: CGFloat.greatestFiniteMagnitude))
        let proceedHeight = self.proceedNode.updateLayout(width: bottomMaximumWidth - 48.0, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize, transition: transition)
        let proceedSize = CGSize(width: bottomMaximumWidth - 48.0, height: proceedHeight)
        
        var items: [AuthorizationLayoutItem] = []
        
        items.append(AuthorizationLayoutItem(node: self.titleNode, size: titleSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: titleInset, maxValue: titleInset), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        items.append(AuthorizationLayoutItem(node: self.noticeNode, size: noticeSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 18.0, maxValue: 18.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        items.append(AuthorizationLayoutItem(node: self.codeField, size: CGSize(width: max(1.0, maximumWidth - 88.0), height: max(44.0, ceil(fieldFont.lineHeight) + 16.0)), spacingBefore: AuthorizationLayoutItemSpacing(weight: 18.0, maxValue: 30.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        items.append(AuthorizationLayoutItem(node: self.codeSeparatorNode, size: CGSize(width: maximumWidth - 48.0, height: UIScreenPixel), spacingBefore: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        let buttonFrame = CGRect(origin: CGPoint(x: bottomBandMinX + floorToScreenPixels((bottomBandWidth - proceedSize.width) / 2.0), y: layout.size.height - insets.bottom - proceedSize.height - inset), size: proceedSize)
        let dividerSize = self.dividerNode.updateLayout(width: bottomMaximumWidth)
        let formHeight = max(1.0, buttonFrame.minY - (self.appleSignInAllowed ? dividerSize.height : 16.0) - insets.top)
        if formHeight >= AuthorizationFormNode.minimumHeight(for: items) + animationSize.height + 10.0 {
            items.insert(AuthorizationLayoutItem(node: self.animationNode, size: animationSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 10.0, maxValue: 10.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)), at: 0)
            self.animationNode.updateLayout(size: animationSize)
            self.animationNode.isHidden = false
            self.animationNode.visibility = true
        } else {
            self.animationNode.isHidden = true
            self.animationNode.visibility = false
        }
        
        transition.updateFrame(node: self.proceedNode, frame: buttonFrame)
        
        transition.updateFrame(node: self.dividerNode, frame: CGRect(origin: CGPoint(x: bottomBandMinX + floorToScreenPixels((bottomBandWidth - dividerSize.width) / 2.0), y: buttonFrame.minY - dividerSize.height), size: dividerSize))
        
        if let _ = self.signInWithAppleButton, self.appleSignInAllowed {
            self.dividerNode.isHidden = false
        } else {
            self.dividerNode.isHidden = true
        }
        
        self.formNode.update(bounds: CGRect(x: bandMinX, y: insets.top, width: bandWidth, height: formHeight), items: items, focusedNode: self.codeField.textField.isFirstResponder ? self.codeField : nil, transition: transition)
        
        if let signInWithAppleButton = self.signInWithAppleButton, self.appleSignInAllowed {
            signInWithAppleButton.isHidden = false
            transition.updateFrame(view: signInWithAppleButton, frame: self.proceedNode.frame)
        } else {
            self.signInWithAppleButton?.isHidden = true
        }
        self.updateButtonsVisibility(transition: .immediate)
    }
    
    func activateInput() {
        self.codeField.textField.becomeFirstResponder()
    }
    
    func animateError() {
        self.codeField.layer.addShakeAnimation()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.proceedPressed()
        return false
    }
    
    @objc func proceedPressed() {
        guard !self.inProgress else {
            return
        }
        self.proceedWithEmail?(self.currentEmail)
    }
    
    @objc func signInWithApplePressed() {
        guard self.appleSignInAllowed, !self.inProgress else {
            return
        }
        self.signInWithApple?()
    }
}
