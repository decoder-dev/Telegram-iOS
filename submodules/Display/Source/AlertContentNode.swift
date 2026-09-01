import Foundation
import UIKit
import AsyncDisplayKit

open class AlertContentNode: ASDisplayNode {
    open var requestLayout: ((ContainedViewLayoutTransition) -> Void)?

    public var usesAccessibilityContentSizeCategory: Bool {
        let category = self.isNodeLoaded ? self.view.traitCollection.preferredContentSizeCategory : UITraitCollection.current.preferredContentSizeCategory
        return category.isAccessibilityCategory
    }

    open var accessibilityInitialFocusNode: ASDisplayNode? {
        return nil
    }
    
    open var dismissOnOutsideTap: Bool {
        return true
    }
    
    open func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        assertionFailure()
        
        return CGSize()
    }
    
    open func updateTheme(_ theme: AlertControllerTheme) {
        
    }
    
    open func contentSizeCategoryUpdated() {

    }

    open func performHighlightedAction() {
        
    }
    
    open func decreaseHighlightedIndex() {
        
    }
    
    open func increaseHighlightedIndex() {

    }
}
