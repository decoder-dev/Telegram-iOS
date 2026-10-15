import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ComponentFlow
import SwiftSignalKit
import ViewControllerComponent
import ComponentDisplayAdapters
import TelegramPresentationData
import AccountContext
import TelegramCore
import MultilineTextComponent
import EmojiStatusComponent
import TelegramStringFormatting
import CheckNode

final class DataButtonComponent: Component {
    let theme: PresentationTheme
    let title: String
    let action: () -> Void
    let tag: AnyObject?
    
    init(
        theme: PresentationTheme,
        title: String,
        action: @escaping () -> Void,
        tag: AnyObject? = nil
    ) {
        self.theme = theme
        self.title = title
        self.action = action
        self.tag = tag
    }
    
    static func ==(lhs: DataButtonComponent, rhs: DataButtonComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.title != rhs.title {
            return false
        }
        if lhs.tag !== rhs.tag {
            return false
        }
        return true
    }
    
    class View: HighlightTrackingButton, ComponentTaggedView {
        public func matches(tag: Any) -> Bool {
            if let component = self.component, let componentTag = component.tag {
                let tag = tag as AnyObject
                if componentTag === tag {
                    return true
                }
            }
            return false
        }
        
        private let title = ComponentView<Empty>()
        
        private var component: DataButtonComponent?
        private weak var state: EmptyComponentState?
        
        private var highlightBackgroundFrame: CGRect?
        private var highlightBackgroundLayer: SimpleLayer?
        
        override init(frame: CGRect) {
            super.init(frame: frame)

            self.clipsToBounds = true
            self.layer.cornerRadius = 26.0
            
            self.highligthedChanged = { [weak self] isHighlighted in
                guard let self, let component = self.component, let highlightBackgroundFrame = self.highlightBackgroundFrame else {
                    return
                }
                
                if isHighlighted {
                    self.superview?.bringSubviewToFront(self)
                    
                    let highlightBackgroundLayer: SimpleLayer
                    if let current = self.highlightBackgroundLayer {
                        highlightBackgroundLayer = current
                    } else {
                        highlightBackgroundLayer = SimpleLayer()
                        self.highlightBackgroundLayer = highlightBackgroundLayer
                        self.layer.insertSublayer(highlightBackgroundLayer, at: 0)
                        highlightBackgroundLayer.backgroundColor = component.theme.list.itemHighlightedBackgroundColor.cgColor
                    }
                    highlightBackgroundLayer.frame = highlightBackgroundFrame
                    highlightBackgroundLayer.opacity = 1.0
                } else {
                    if let highlightBackgroundLayer = self.highlightBackgroundLayer {
                        self.highlightBackgroundLayer = nil
                        highlightBackgroundLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak highlightBackgroundLayer] _ in
                            highlightBackgroundLayer?.removeFromSuperlayer()
                        })
                    }
                }
            }
            self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc private func pressed() {
            guard let component = self.component else {
                return
            }
            component.action()
        }
        
        func displayHighlight() {
            guard let component = self.component, let frame = self.highlightBackgroundFrame else { return }
            self.highlightBackgroundLayer?.removeFromSuperlayer()
            let layer = SimpleLayer()
            self.highlightBackgroundLayer = layer
            layer.backgroundColor = component.theme.list.itemHighlightedBackgroundColor.cgColor
            layer.frame = frame
            self.layer.insertSublayer(layer, at: 0)
            Queue.mainQueue().after(0.8, { [weak self, weak layer] in
                guard let self, let layer, self.highlightBackgroundLayer === layer, !self.isHighlighted else { return }
                self.highlightBackgroundLayer = nil
                layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak layer] _ in
                    layer?.removeFromSuperlayer()
                })
            })
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            if self.component?.theme.isMessagesTheme == true, previousTraitCollection?.preferredContentSizeCategory != self.traitCollection.preferredContentSizeCategory {
                self.state?.updated(transition: .immediate)
            }
        }
        
        func update(component: DataButtonComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let themeUpdated = self.component?.theme !== component.theme
            
            self.component = component
            self.state = state
            self.layer.cornerRadius = component.theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius : 26.0
            self.isAccessibilityElement = true
            self.accessibilityTraits = .button
            self.accessibilityLabel = component.title

            if themeUpdated {
                self.backgroundColor = component.theme.list.itemBlocksBackgroundColor
                self.highlightBackgroundLayer?.backgroundColor = component.theme.list.itemHighlightedBackgroundColor.cgColor
            }
            
            let titleSize = self.title.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.title, font: component.theme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .body) : Font.regular(17.0), textColor: component.theme.list.itemDestructiveColor)), horizontalAlignment: .center, maximumNumberOfLines: component.theme.isMessagesTheme ? 0 : 1)),
                environment: {},
                containerSize: CGSize(width: max(1.0, availableSize.width - (component.theme.isMessagesTheme ? 32.0 : 0.0)), height: .greatestFiniteMagnitude)
            )
            
            let height: CGFloat = component.theme.isMessagesTheme ? MessagesAppearanceMetrics.rowHeight(contentHeight: titleSize.height, verticalInset: 12.0) : 52.0
            
            let titleFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) / 2.0), y: floor((height - titleSize.height) / 2.0)), size: titleSize)
            
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.isUserInteractionEnabled = false
                    self.addSubview(titleView)
                }
                transition.setFrame(view: titleView, frame: titleFrame)
            }
            
            self.highlightBackgroundFrame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: height))
            self.highlightBackgroundLayer?.frame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: height))
            
            return CGSize(width: availableSize.width, height: height)
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
