import Foundation
import UIKit
import AsyncDisplayKit
import Display

final class NavigationBarBadgeNode: ASDisplayNode {
    private var fillColor: UIColor
    private var strokeColor: UIColor
    private var textColor: UIColor
    
    private let textNode: ImmediateTextNode
    private let backgroundNode: ASImageNode
    
    private var fontSize: CGFloat
    private var font: UIFont {
        return Font.regular(floor(self.fontSize * 13.0 / 17.0))
    }
    
    var text: String = "" {
        didSet {
            self.textNode.attributedText = NSAttributedString(string: self.text, font: self.font, textColor: self.textColor)
            self.invalidateCalculatedLayout()
        }
    }
    
    init(fillColor: UIColor, strokeColor: UIColor, textColor: UIColor, fontSize: CGFloat = 17.0) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.textColor = textColor
        self.fontSize = fontSize
        
        self.textNode = ImmediateTextNode()
        self.textNode.isUserInteractionEnabled = false
        self.textNode.displaysAsynchronously = false
        
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displaysAsynchronously = false
        self.backgroundNode.image = generateStretchableFilledCircleImage(radius: 9.0, color: fillColor, backgroundColor: nil)
        
        super.init()
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.textNode)
    }
    
    func updateTheme(fillColor: UIColor, strokeColor: UIColor, textColor: UIColor) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.textColor = textColor
        self.backgroundNode.image = generateStretchableFilledCircleImage(radius: 9.0, color: fillColor, backgroundColor: nil)
        self.textNode.attributedText = NSAttributedString(string: self.text, font: self.font, textColor: self.textColor)
        self.textNode.redrawIfPossible()
    }
    
    func updateFontSize(_ fontSize: CGFloat) {
        guard abs(self.fontSize - fontSize) > .ulpOfOne else {
            return
        }
        self.fontSize = fontSize
        self.textNode.attributedText = NSAttributedString(string: self.text, font: self.font, textColor: self.textColor)
        self.textNode.redrawIfPossible()
        self.invalidateCalculatedLayout()
    }
    
    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let badgeSize = self.textNode.updateLayout(constrainedSize)
        let backgroundSize: CGSize
        if self.text.count < 2 {
            backgroundSize = CGSize(width: 18.0, height: 18.0)
        } else {
            backgroundSize = CGSize(width: max(18.0, badgeSize.width + 10.0 + 1.0), height: 18.0)
        }
        let backgroundFrame = CGRect(origin: CGPoint(), size: backgroundSize)
        self.backgroundNode.frame = backgroundFrame
        self.textNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels(backgroundFrame.midX - badgeSize.width / 2.0), y: floorToScreenPixels((backgroundFrame.size.height - badgeSize.height) / 2.0)), size: badgeSize)
        
        return backgroundSize
    }
}
