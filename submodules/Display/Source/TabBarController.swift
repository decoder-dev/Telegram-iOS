import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

public protocol TabBarController: ViewController {
    var currentController: ViewController? { get }
    var controllers: [ViewController] { get }
    var selectedIndex: Int { get set }
    
    func setControllers(_ controllers: [ViewController], selectedIndex: Int?)
    
    func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition)
    
    func frameForControllerTab(controller: ViewController) -> CGRect?
    func isPointInsideContentArea(point: CGPoint) -> Bool
    
    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition)
    func updateIsTabBarHidden(_ value: Bool, transition: ContainedViewLayoutTransition)
    func updateLayout(transition: ContainedViewLayoutTransition)
    
    func updateControllerLayout(controller: ViewController)
}

public extension TabBarController {
    /// The controller `selectedIndex` points at, or nil when it points at nothing.
    ///
    /// `selectedIndex` reports 0 when no tab has been selected yet, so on an empty controller list
    /// it names an element that does not exist, and the list is rebuilt on launch, on every
    /// account switch, and whenever the Calls tab is toggled. Callers were subscripting
    /// `controllers` with it directly — some with no bounds check at all — which is a trap waiting
    /// on timing rather than on anything the caller can see. Use this instead of the subscript.
    var selectedController: ViewController? {
        let index = self.selectedIndex
        guard index >= 0, index < self.controllers.count else {
            return nil
        }
        return self.controllers[index]
    }
}
