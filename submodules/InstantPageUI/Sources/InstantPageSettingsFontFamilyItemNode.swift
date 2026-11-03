import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

private func generateCheckIcon(_ color: UIColor) -> UIImage? {
    return generateImage(CGSize(width: 14.0, height: 11.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0)
        context.move(to: CGPoint(x: 12.0, y: 1.0))
        context.addLine(to: CGPoint(x: 4.16482734, y: 9.0))
        context.addLine(to: CGPoint(x: 1.0, y: 5.81145833))
        context.strokePath()
    })
}

final class InstantPageSettingsFontFamilyNode: InstantPageSettingsItemNode {
    private let title: String
    private let family: String?
    private let fontSize: CGFloat
    private let tapped: () -> Void
    
    private let labelNode: ASTextNode
    private let checkNode: ASImageNode
    
    var _checked: Bool
    var checked: Bool {
        get {
            return self._checked
        } set(value) {
            self._checked = value
            self.checkNode.isHidden = !value
        }
    }
    
    init(theme: InstantPageSettingsItemTheme, title: String, family: String?, checked: Bool, fontSize: CGFloat = 17.0, tapped: @escaping () -> Void) {
        self.title = title
        self.family = family
        self.fontSize = fontSize
        self._checked = checked
        self.tapped = tapped
        
        self.labelNode = ASTextNode()
        
        self.checkNode = ASImageNode()
        self.checkNode.displayWithoutProcessing = true
        self.checkNode.displaysAsynchronously = false
        self.checkNode.isHidden = !checked
        
        super.init(theme: theme, selectable: true)
        
        self.addSubnode(self.labelNode)
        self.addSubnode(self.checkNode)
        
        self.updateTheme(theme)
    }
    
    override func updateTheme(_ theme: InstantPageSettingsItemTheme) {
        super.updateTheme(theme)
        
        let font: UIFont
        if let family = self.family {
            if let familyFont = UIFont(name: family, size: self.fontSize) {
                font = familyFont
            } else {
                font = UIFont.systemFont(ofSize: self.fontSize)
            }
        } else {
            font = UIFont.systemFont(ofSize: self.fontSize)
        }
        self.labelNode.attributedText = NSAttributedString(string: self.title, font: font, textColor: theme.primaryColor)
        self.checkNode.image = generateCheckIcon(theme.accentColor)
    }
    
    override func updateInternalLayout(width: CGFloat, insets: UIEdgeInsets, previousItem: (InstantPageSettingsItemNodeStatus, InstantPageSettingsItemNode?), nextItem: (InstantPageSettingsItemNodeStatus, InstantPageSettingsItemNode?)) -> (height: CGFloat, separatorInset: CGFloat?) {
        var separatorInset: CGFloat?
        if case .sameSection = previousItem.0, let previousNode = previousItem.1, previousNode is InstantPageSettingsFontFamilyNode {
            separatorInset = 46.0
        }
        let labelSize = self.labelNode.measure(CGSize(width: width - 46.0 - 5.0, height: PresentationLayoutMetrics.minimumInteractiveSize))
        self.labelNode.frame = CGRect(origin: CGPoint(x: 46.0, y: insets.top + floor((PresentationLayoutMetrics.minimumInteractiveSize - labelSize.height) / 2.0)), size: labelSize)
        if let image = self.checkNode.image {
            self.checkNode.frame = CGRect(origin: CGPoint(x: PresentationLayoutMetrics.listHorizontalInset, y: insets.top + floor((PresentationLayoutMetrics.minimumInteractiveSize - image.size.height) / 2.0)), size: image.size)
        }
        return (PresentationLayoutMetrics.minimumInteractiveSize + insets.top + insets.bottom, separatorInset)
    }
    
    override func pressed() {
        self.tapped()
    }
}
