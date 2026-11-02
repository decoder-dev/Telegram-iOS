import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AuthorizationUtils

final class AuthorizationFormNode: ASScrollNode {
    var requestLayout: (() -> Void)?
    private var preferenceObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [UIContentSizeCategory.didChangeNotification, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            self.preferenceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.requestLayout?()
            })
        }
    }

    deinit {
        for observer in self.preferenceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func didLoad() {
        super.didLoad()
        self.view.contentInsetAdjustmentBehavior = .never
        self.view.scrollsToTop = false
        self.view.isDirectionalLockEnabled = true
    }

    static func minimumHeight(for items: [AuthorizationLayoutItem]) -> CGFloat {
        return items.reduce(CGFloat(24.0)) { height, item in
            return height + item.size.height + min(item.spacingBefore.weight, item.spacingBefore.maxValue) + min(item.spacingAfter.weight, item.spacingAfter.maxValue)
        }
    }

    func update(bounds: CGRect, items: [AuthorizationLayoutItem], focusedNode: ASDisplayNode? = nil, transition: ContainedViewLayoutTransition) {
        let viewport = CGRect(origin: bounds.origin, size: CGSize(width: max(1.0, bounds.width), height: max(1.0, bounds.height)))
        transition.updateFrame(node: self, frame: viewport)
        let minimumHeight = Self.minimumHeight(for: items)
        let contentHeight = max(viewport.height, ceil(minimumHeight))
        let _ = layoutAuthorizationItems(bounds: CGRect(x: 0.0, y: 12.0, width: viewport.width, height: contentHeight - 24.0), items: items, transition: transition, failIfDoesNotFit: false)
        self.view.contentSize = CGSize(width: viewport.width, height: contentHeight)
        self.view.isScrollEnabled = contentHeight > viewport.height
        self.view.showsVerticalScrollIndicator = self.view.isScrollEnabled
        self.view.contentOffset.y = min(max(0.0, self.view.contentOffset.y), contentHeight - viewport.height)
        if let focusedNode = focusedNode {
            let focusFrame = focusedNode.convert(focusedNode.bounds, to: self).insetBy(dx: 0.0, dy: -12.0)
            if !self.view.bounds.contains(focusFrame) {
                self.view.scrollRectToVisible(focusFrame, animated: false)
            }
        }
    }
}
