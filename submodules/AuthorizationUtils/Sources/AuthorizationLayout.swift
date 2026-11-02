import Foundation
import UIKit
import AsyncDisplayKit
import Display

public struct AuthorizationLayoutItem {
    public var node: ASDisplayNode?
    public var view: UIView?
    public var size: CGSize
    public var spacingBefore: AuthorizationLayoutItemSpacing
    public var spacingAfter: AuthorizationLayoutItemSpacing
    
    public init(node: ASDisplayNode, size: CGSize, spacingBefore: AuthorizationLayoutItemSpacing, spacingAfter: AuthorizationLayoutItemSpacing) {
        self.node = node
        self.size = size
        self.spacingBefore = spacingBefore
        self.spacingAfter = spacingAfter
    }


    public init(view: UIView, size: CGSize, spacingBefore: AuthorizationLayoutItemSpacing, spacingAfter: AuthorizationLayoutItemSpacing) {
        self.view = view
        self.size = size
        self.spacingBefore = spacingBefore
        self.spacingAfter = spacingAfter
    }
}

public func layoutAuthorizationItems(bounds: CGRect, items: [AuthorizationLayoutItem], transition: ContainedViewLayoutTransition, failIfDoesNotFit: Bool) -> Bool {
    guard let frames = authorizationLayoutFrames(bounds: bounds, sizes: items.map { $0.size }, spacings: items.flatMap { [$0.spacingBefore, $0.spacingAfter] }, failIfDoesNotFit: failIfDoesNotFit) else {
        return false
    }
    for (item, frame) in zip(items, frames) {
        if let view = item.view {
            transition.updateFrame(view: view, frame: frame)
        } else if let node = item.node {
            transition.updateFrame(node: node, frame: frame)
        }
    }
    return true
}
