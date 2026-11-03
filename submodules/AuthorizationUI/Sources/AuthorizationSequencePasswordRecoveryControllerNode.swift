import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import AuthorizationUtils

final class AuthorizationSequencePasswordRecoveryControllerNode: ASDisplayNode, UITextFieldDelegate {
    private let strings: PresentationStrings
    private let theme: PresentationTheme
    private let formNode = AuthorizationFormNode()
    private var emailPattern: String = ""
    
    private let titleNode: ASTextNode
    private let noticeNode: ASTextNode
    private let noAccessNode: HighlightableButtonNode
    
    private let codeField: TextFieldNode
    private let codeSeparatorNode: ASDisplayNode
    
    private var layoutArguments: (ContainerViewLayout, CGFloat)?
    
    var currentCode: String {
        return self.codeField.textField.text ?? ""
    }
    
    var recoverWithCode: ((String) -> Void)?
    var noAccess: (() -> Void)?
    
    var inProgress: Bool = false {
        didSet {
            self.codeField.alpha = self.inProgress ? 0.6 : 1.0
            self.noAccessNode.isUserInteractionEnabled = !self.inProgress
        }
    }
    
    init(strings: PresentationStrings, theme: PresentationTheme, listFontSize: CGFloat = 17.0) {
        self.strings = strings
        self.theme = theme
        
        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        self.titleNode.attributedText = NSAttributedString(string: strings.TwoStepAuth_RecoveryTitle, font: Font.light(30.0), textColor: self.theme.list.itemPrimaryTextColor)
        
        self.noticeNode = ASTextNode()
        self.noticeNode.isUserInteractionEnabled = false
        self.noticeNode.displaysAsynchronously = false
        self.noticeNode.attributedText = NSAttributedString(string: strings.TwoStepAuth_RecoveryCodeHelp, font: Font.regular(listFontSize), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.noticeNode.lineSpacing = 0.1
        
        self.noAccessNode = HighlightableButtonNode()
        self.noAccessNode.displaysAsynchronously = false
        self.noAccessNode.titleNode.maximumNumberOfLines = 0
        
        self.codeSeparatorNode = ASDisplayNode()
        self.codeSeparatorNode.isLayerBacked = true
        self.codeSeparatorNode.backgroundColor = self.theme.list.itemPlainSeparatorColor
        
        let fieldFont = Font.regular(floor(listFontSize * 20.0 / 17.0))
        self.codeField = TextFieldNode()
        self.codeField.textField.font = fieldFont
        self.codeField.textField.textColor = self.theme.list.itemPrimaryTextColor
        self.codeField.textField.textAlignment = .center
        self.codeField.textField.attributedPlaceholder = NSAttributedString(string: self.strings.TwoStepAuth_RecoveryCode, font: fieldFont, textColor: self.theme.list.itemPlaceholderTextColor)
        self.codeField.textField.returnKeyType = .done
        self.codeField.textField.keyboardAppearance = self.theme.rootController.keyboardColor.keyboardAppearance
        self.codeField.textField.disableAutomaticKeyboardHandling = [.forward, .backward]
        self.codeField.textField.tintColor = self.theme.list.itemAccentColor
        self.codeField.textField.textContentType = .oneTimeCode
        self.codeField.textField.autocorrectionType = .no
        self.codeField.textField.autocapitalizationType = .none
        self.codeField.textField.accessibilityLabel = self.strings.TwoStepAuth_RecoveryCode
        
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
        self.formNode.addSubnode(self.noAccessNode)
        self.formNode.addSubnode(self.noticeNode)
        self.titleNode.isAccessibilityElement = true
        self.titleNode.accessibilityTraits = [.header]
        self.noticeNode.isAccessibilityElement = true
        self.noAccessNode.accessibilityTraits = [.button]
        self.formNode.requestLayout = { [weak self] in
            guard let self, let (layout, navigationHeight) = self.layoutArguments else {
                return
            }
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
        }
        
        self.noAccessNode.addTarget(self, action: #selector(self.noAccessPressed), forControlEvents: .touchUpInside)
    }
    
    func updateData(emailPattern: String) {
        self.emailPattern = emailPattern
        self.noAccessNode.setAttributedTitle(NSAttributedString(string: self.strings.TwoStepAuth_RecoveryEmailUnavailable(emailPattern).string, font: Font.regular(16.0), textColor: self.theme.list.itemAccentColor, paragraphAlignment: .center), for: [])
        if let (layout, navigationHeight) = self.layoutArguments {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.layoutArguments = (layout, navigationBarHeight)
        
        var insets = layout.insets(options: [.input])
        insets.top = navigationBarHeight
        
        self.titleNode.attributedText = NSAttributedString(string: self.strings.TwoStepAuth_RecoveryTitle, font: Font.semibold(UIFont.preferredFont(forTextStyle: .title1).pointSize), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.noticeNode.attributedText = NSAttributedString(string: self.strings.TwoStepAuth_RecoveryCodeHelp, font: UIFont.preferredFont(forTextStyle: .body), textColor: self.theme.list.itemSecondaryTextColor, paragraphAlignment: .center)
        let actionTitle = self.strings.TwoStepAuth_RecoveryEmailUnavailable(self.emailPattern).string
        self.noAccessNode.setAttributedTitle(NSAttributedString(string: actionTitle, font: UIFont.preferredFont(forTextStyle: .body), textColor: self.theme.list.itemAccentColor, paragraphAlignment: .center), for: [])
        self.noAccessNode.accessibilityLabel = actionTitle
        let fieldFont = UIFont.preferredFont(forTextStyle: .title3)
        self.codeField.textField.font = fieldFont
        self.codeField.textField.attributedPlaceholder = NSAttributedString(string: self.strings.TwoStepAuth_RecoveryCode, font: fieldFont, textColor: self.theme.list.itemPlaceholderTextColor)
        
        // iPhone Duo: beside a side strip the content keeps to the band between the side insets. With equal
        // insets (every other phone) it keeps the full width.
        let insetsDiffer = layout.safeInsets.left != layout.safeInsets.right
        let bandMinX: CGFloat = insetsDiffer ? layout.safeInsets.left : 0.0
        let bandWidth: CGFloat = insetsDiffer ? layout.size.width - layout.safeInsets.left - layout.safeInsets.right : layout.size.width
        let contentWidth = max(1.0, min(430.0, bandWidth) - 48.0)
        
        let titleSize = self.titleNode.measure(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        
        let noticeSize = self.noticeNode.measure(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        var noAccessSize = self.noAccessNode.measure(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude))
        noAccessSize.height = max(PresentationLayoutMetrics.minimumInteractiveSize, noAccessSize.height + 16.0)
        
        var items: [AuthorizationLayoutItem] = []
        items.append(AuthorizationLayoutItem(node: self.titleNode, size: titleSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        items.append(AuthorizationLayoutItem(node: self.noticeNode, size: noticeSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 10.0, maxValue: 10.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        items.append(AuthorizationLayoutItem(node: self.codeField, size: CGSize(width: contentWidth, height: max(PresentationLayoutMetrics.minimumInteractiveSize, ceil(fieldFont.lineHeight) + 16.0)), spacingBefore: AuthorizationLayoutItemSpacing(weight: 32.0, maxValue: 100.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        items.append(AuthorizationLayoutItem(node: self.codeSeparatorNode, size: CGSize(width: contentWidth, height: UIScreenPixel), spacingBefore: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        items.append(AuthorizationLayoutItem(node: self.noAccessNode, size: noAccessSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 48.0, maxValue: 100.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        self.formNode.update(bounds: CGRect(x: bandMinX, y: insets.top, width: bandWidth, height: layout.size.height - insets.top - insets.bottom - 20.0), items: items, focusedNode: self.codeField.textField.isFirstResponder ? self.codeField : nil, transition: transition)
    }
    
    func activateInput() {
        self.codeField.textField.becomeFirstResponder()
    }
    
    func animateError() {
        self.codeField.layer.addShakeAnimation()
    }
    
    @objc func passwordFieldTextChanged(_ textField: UITextField) {
        
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if !self.inProgress {
            self.recoverWithCode?(self.currentCode)
        }
        return false
    }
    
    @objc func noAccessPressed() {
        guard !self.inProgress else {
            return
        }
        self.noAccess?()
    }
}

