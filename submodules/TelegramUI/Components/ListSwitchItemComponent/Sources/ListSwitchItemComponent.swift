import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import SwitchComponent
import MultilineTextComponent

public final class ListSwitchItemComponent: Component {
    let theme: PresentationTheme
    let title: String
    let value: Bool
    let valueUpdated: (Bool) -> Void
    
    public init(
        theme: PresentationTheme,
        title: String,
        value: Bool,
        valueUpdated: @escaping (Bool) -> Void
    ) {
        self.theme = theme
        self.title = title
        self.value = value
        self.valueUpdated = valueUpdated
    }
    
    public static func ==(lhs: ListSwitchItemComponent, rhs: ListSwitchItemComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.title != rhs.title {
            return false
        }
        if lhs.value != rhs.value {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        private let title = ComponentView<Empty>()
        private let switchView = ComponentView<Empty>()
        
        private var component: ListSwitchItemComponent?
        private weak var state: EmptyComponentState?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(self.contentSizeCategoryChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        }
        
        required init(coder: NSCoder) {
            preconditionFailure()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func contentSizeCategoryChanged() {
            if self.component?.theme.isMessagesTheme == true { self.state?.updated(transition: .immediate) }
        }

        func update(component: ListSwitchItemComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            self.backgroundColor = component.theme.list.itemBlocksBackgroundColor
            self.layer.cornerRadius = component.theme.isMessagesTheme ? MessagesAppearanceMetrics.sectionCornerRadius : 26.0
            
            var size = CGSize(width: availableSize.width, height: 52.0)
            let rightInset: CGFloat = 16.0
            let leftInset: CGFloat = 16.0
            let spacing: CGFloat = 8.0
            
            let switchSize = self.switchView.update(
                transition: transition,
                component: AnyComponent(SwitchComponent(
                    tintColor: component.theme.isMessagesTheme ? component.theme.list.itemSwitchColors.contentColor : nil,
                    accessibilityLabel: component.title,
                    value: component.value,
                    valueUpdated: { [weak self] value in
                        guard let self else {
                            return
                        }
                        self.component?.valueUpdated(value)
                    }
                )),
                environment: {},
                containerSize: size
            )
            var switchFrame = CGRect(origin: CGPoint(x: size.width - rightInset - switchSize.width, y: floor((size.height - switchSize.height) * 0.5)), size: switchSize)
            if let switchComponentView = self.switchView.view {
                if switchComponentView.superview == nil {
                    self.addSubview(switchComponentView)
                }
                transition.setFrame(view: switchComponentView, frame: switchFrame)
            }
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.title, font: component.theme.isMessagesTheme ? UIFont.preferredFont(forTextStyle: .body) : Font.regular(17.0), textColor: component.theme.list.itemPrimaryTextColor)), maximumNumberOfLines: component.theme.isMessagesTheme ? 0 : 1)),
                environment: {},
                containerSize: CGSize(width: max(1.0, switchFrame.minX - spacing - leftInset), height: .greatestFiniteMagnitude)
            )
            if component.theme.isMessagesTheme {
                size.height = MessagesAppearanceMetrics.rowHeight(contentHeight: max(titleSize.height, switchSize.height), verticalInset: 12.0)
                switchFrame.origin.y = floor((size.height - switchSize.height) * 0.5)
                if let switchComponentView = self.switchView.view { transition.setFrame(view: switchComponentView, frame: switchFrame) }
            }
            let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: floor((size.height - titleSize.height) * 0.5)), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.layer.anchorPoint = CGPoint()
                    self.addSubview(titleView)
                }
                transition.setPosition(view: titleView, position: titleFrame.origin)
                titleView.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
                titleView.isAccessibilityElement = false
                titleView.accessibilityElementsHidden = true
            }
            
            return size
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
