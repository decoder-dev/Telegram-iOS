import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit

public func addAccessibilityChildren(of node: ASDisplayNode, container: Any, to list: inout [Any]) {
    if node.isAccessibilityElement {
        let element = UIAccessibilityElement(accessibilityContainer: container)
        element.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(node.bounds, in: node.view)
        element.accessibilityLabel = node.accessibilityLabel
        element.accessibilityValue = node.accessibilityValue
        element.accessibilityTraits = node.accessibilityTraits
        element.accessibilityHint = node.accessibilityHint
        element.accessibilityIdentifier = node.accessibilityIdentifier
        
        //node.accessibilityFrame = UIAccessibilityConvertFrameToScreenCoordinates(node.bounds, node.view)
        list.append(element)
    } else if let accessibilityElements = node.accessibilityElements {
        list.append(contentsOf: accessibilityElements)
    }
}

public func firstAccessibilityElement(in view: UIView) -> Any? {
    guard !view.isHidden, view.alpha > 0.01, !view.accessibilityElementsHidden else {
        return nil
    }
    if view.isAccessibilityElement {
        return view
    }
    if let accessibilityElements = view.accessibilityElements {
        for element in accessibilityElements {
            if let elementView = element as? UIView {
                if let result = firstAccessibilityElement(in: elementView) {
                    return result
                }
            } else {
                return element
            }
        }
    }
    for subview in view.subviews {
        if let result = firstAccessibilityElement(in: subview) {
            return result
        }
    }
    return nil
}

public func smartInvertColorsEnabled() -> Bool {
    if #available(iOSApplicationExtension 11.0, iOS 11.0, *), UIAccessibility.isInvertColorsEnabled {
        return true
    } else {
        return false
    }
}

public func systemBodyFontSize() -> Signal<CGFloat, NoError> {
    return Signal { subscriber in
        subscriber.putNext(UIFont.preferredFont(forTextStyle: .body).pointSize)

        let observer = NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main, using: { notification in
            let font: UIFont
            if let rawCategory = notification.userInfo?[UIContentSizeCategory.newValueUserInfoKey] as? String {
                let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(rawValue: rawCategory))
                font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            } else {
                font = UIFont.preferredFont(forTextStyle: .body)
            }
            subscriber.putNext(font.pointSize)
        })
        return ActionDisposable {
            Queue.mainQueue().async {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    |> runOn(Queue.mainQueue())
    |> distinctUntilChanged
}

public func isReduceMotionEnabled() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        subscriber.putNext(UIAccessibility.isReduceMotionEnabled)
        
        let observer = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(UIAccessibility.isReduceMotionEnabled)
        })
        
        return ActionDisposable {
            Queue.mainQueue().async {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    } |> runOn(Queue.mainQueue())
}

public func isSpeakSelectionEnabled() -> Bool {
    return UIAccessibility.isSpeakSelectionEnabled
}

public func isSpeakSelectionEnabledSignal() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        subscriber.putNext(UIAccessibility.isSpeakSelectionEnabled)
        
        let observer = NotificationCenter.default.addObserver(forName: UIAccessibility.speakSelectionStatusDidChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(UIAccessibility.isSpeakSelectionEnabled)
        })
        
        return ActionDisposable {
            Queue.mainQueue().async {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    } |> runOn(Queue.mainQueue())
}

public func isBoldTextEnabled() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        subscriber.putNext(UIAccessibility.isBoldTextEnabled)
        
        let observer = NotificationCenter.default.addObserver(forName: UIAccessibility.boldTextStatusDidChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(UIAccessibility.isBoldTextEnabled)
        })
        
        return ActionDisposable {
            Queue.mainQueue().async {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    |> runOn(Queue.mainQueue())
}

public func isReduceTransparencyEnabled() -> Bool {
    UIAccessibility.isReduceTransparencyEnabled
}
