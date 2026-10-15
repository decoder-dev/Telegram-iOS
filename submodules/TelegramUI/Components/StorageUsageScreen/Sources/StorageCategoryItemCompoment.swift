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

private func storageCategoryUsesDarkForeground(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
    func linear(_ value: CGFloat) -> CGFloat {
        let value = min(1.0, max(0.0, value))
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
}

private final class StorageCategoryAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let activate = self.activate else { return false }
        activate()
        return true
    }
}

final class StorageCategoryItemComponent: Component {
    enum ActionType {
        case toggle
        case generic
    }
    
    let theme: PresentationTheme
    let strings: PresentationStrings
    let category: StorageCategoriesComponent.CategoryData
    let isExpandedLevel: Bool
    let isExpanded: Bool
    let hasNext: Bool
    let action: (StorageUsageScreenComponent.Category, ActionType) -> Void
    
    init(
        theme: PresentationTheme,
        strings: PresentationStrings,
        category: StorageCategoriesComponent.CategoryData,
        isExpandedLevel: Bool,
        isExpanded: Bool,
        hasNext: Bool,
        action: @escaping (StorageUsageScreenComponent.Category, ActionType) -> Void
    ) {
        self.theme = theme
        self.strings = strings
        self.category = category
        self.isExpandedLevel = isExpandedLevel
        self.isExpanded = isExpanded
        self.hasNext = hasNext
        self.action = action
    }
    
    static func ==(lhs: StorageCategoryItemComponent, rhs: StorageCategoryItemComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.category != rhs.category {
            return false
        }
        if lhs.isExpandedLevel != rhs.isExpandedLevel {
            return false
        }
        if lhs.isExpanded != rhs.isExpanded {
            return false
        }
        if lhs.hasNext != rhs.hasNext {
            return false
        }
        return true
    }
    
    class View: HighlightTrackingButton {
        private let checkLayer: CheckLayer
        private let title = ComponentView<Empty>()
        private let titleValue = ComponentView<Empty>()
        private let label = ComponentView<Empty>()
        private var iconView: UIImageView?
        private let separatorLayer: SimpleLayer
        
        private let checkButtonArea: HighlightTrackingButton
        
        private let subcategoryClippingContainer: UIView
        private var itemViews: [StorageUsageScreenComponent.Category: ComponentView<Empty>] = [:]
        
        private var component: StorageCategoryItemComponent?
        private weak var componentState: EmptyComponentState?
        private lazy var headerAccessibilityElement = StorageCategoryAccessibilityElement(accessibilityContainer: self)
        private lazy var selectionAccessibilityElement = StorageCategoryAccessibilityElement(accessibilityContainer: self)
        
        private var highlightBackgroundFrame: CGRect?
        private var highlightBackgroundLayer: SimpleLayer?
        
        override init(frame: CGRect) {
            self.checkLayer = CheckLayer()
            self.separatorLayer = SimpleLayer()
            
            self.checkButtonArea = HighlightTrackingButton()
            
            self.subcategoryClippingContainer = UIView()
            self.subcategoryClippingContainer.clipsToBounds = true
            
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(self.contentSizeCategoryChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
            self.isAccessibilityElement = false
            self.checkButtonArea.isAccessibilityElement = false
            self.selectionAccessibilityElement.isAccessibilityElement = true
            self.selectionAccessibilityElement.activate = { [weak self] in
                self?.checkPressed()
            }
            self.headerAccessibilityElement.isAccessibilityElement = true
            self.headerAccessibilityElement.accessibilityTraits = .button
            self.headerAccessibilityElement.activate = { [weak self] in
                self?.pressed()
            }
            
            self.addSubview(self.subcategoryClippingContainer)
            
            self.layer.addSublayer(self.separatorLayer)
            self.layer.addSublayer(self.checkLayer)
            
            self.addSubview(self.checkButtonArea)
            
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
                        self.layer.insertSublayer(highlightBackgroundLayer, above: self.separatorLayer)
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
            
            self.checkButtonArea.addTarget(self, action: #selector(self.checkPressed), for: .touchUpInside)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc private func pressed() {
            guard let component = self.component else {
                return
            }
            component.action(component.category.key, .generic)
        }
        
        @objc private func checkPressed() {
            guard let component = self.component else {
                return
            }
            component.action(component.category.key, .toggle)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func contentSizeCategoryChanged() {
            if self.component?.theme.isMessagesTheme == true { self.componentState?.updated(transition: .immediate) }
        }
        
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let result = super.hitTest(point, with: event) else {
                return nil
            }
            if result === self.subcategoryClippingContainer {
                return self
            }
            return result
        }
        
        func update(component: StorageCategoryItemComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let themeUpdated = self.component?.theme !== component.theme || self.component?.category.color != component.category.color
            
            self.component = component
            self.componentState = state
            let usesMessages = component.theme.isMessagesTheme
            let titleFont = usesMessages ? UIFont.preferredFont(forTextStyle: .body) : Font.regular(17.0)
            let detailFont = usesMessages ? UIFont.preferredFont(forTextStyle: .subheadline) : Font.regular(17.0)
            let fractionFont = usesMessages ? UIFont.preferredFont(forTextStyle: .caption1) : Font.regular(17.0)
            
            var leftInset: CGFloat = 62.0
            var additionalLeftInset: CGFloat = 0.0
            
            if component.isExpandedLevel {
                additionalLeftInset += 45.0
            }
            leftInset += additionalLeftInset
            
            let rightInset: CGFloat = 16.0
            
            var availableWidth: CGFloat = max(1.0, availableSize.width - leftInset - rightInset)
            
            if !component.category.subcategories.isEmpty {
                let iconView: UIImageView
                if let current = self.iconView {
                    iconView = current
                    if themeUpdated {
                        iconView.image = PresentationResourcesItemList.disclosureArrowImage(component.theme)
                    }
                } else {
                    iconView = UIImageView()
                    iconView.image = PresentationResourcesItemList.disclosureArrowImage(component.theme)
                    self.iconView = iconView
                    self.addSubview(iconView)
                }
                
                if let image = iconView.image {
                    availableWidth -= image.size.width + 6.0
                    transition.setBounds(view: iconView, bounds: CGRect(origin: CGPoint(), size: image.size))
                }
            } else if let iconView = self.iconView {
                self.iconView = nil
                iconView.removeFromSuperview()
            }
            
            let fractionString: String
            if component.category.sizeFraction != 0.0 {
                let fractionValue: Double = floor(component.category.sizeFraction * 100.0 * 10.0) / 10.0
                if fractionValue < 0.1 {
                    fractionString = "<0.1%"
                } else if abs(Double(Int(fractionValue)) - fractionValue) < 0.001 {
                    fractionString = "\(Int(fractionValue))%"
                } else {
                    fractionString = "\(fractionValue)%"
                }
            } else {
                fractionString = ""
            }
            
            let sizeText = dataSizeString(Int(component.category.size), formatting: DataSizeStringFormatting(strings: component.strings, decimalSeparator: "."))
            let rowContentWidth = availableWidth
            let labelSize = self.label.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: sizeText, font: detailFont, textColor: component.theme.list.itemSecondaryTextColor)))),
                environment: {},
                containerSize: CGSize(width: usesMessages ? max(1.0, rowContentWidth * 0.35) : availableWidth, height: 100.0)
            )
            availableWidth = max(1.0, availableWidth - labelSize.width - 1.0)
            
            let titleValueSize = self.titleValue.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: fractionString, font: fractionFont, textColor: component.theme.list.itemSecondaryTextColor)))),
                environment: {},
                containerSize: CGSize(width: usesMessages ? max(1.0, rowContentWidth * 0.25) : availableWidth, height: 100.0)
            )
            availableWidth = max(1.0, availableWidth - titleValueSize.width - 4.0)
            
            let titleSize = self.title.update(
                transition: transition,
                component: AnyComponent(MultilineTextComponent(text: .plain(NSAttributedString(string: component.category.title, font: titleFont, textColor: component.theme.list.itemPrimaryTextColor)), maximumNumberOfLines: usesMessages ? 0 : 1)),
                environment: {},
                containerSize: CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
            )
            
            var height: CGFloat = usesMessages ? MessagesAppearanceMetrics.rowHeight(contentHeight: max(titleSize.height, labelSize.height, titleValueSize.height), verticalInset: 12.0) : 52.0
            let rowHeight = height
            
            let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: floor((height - titleSize.height) / 2.0)), size: titleSize)
            let titleValueFrame = CGRect(origin: CGPoint(x: titleFrame.maxX + 4.0, y: floor((height - titleValueSize.height) / 2.0)), size: titleValueSize)
            
            var labelFrame = CGRect(origin: CGPoint(x: availableSize.width - rightInset - labelSize.width, y: floor((height - labelSize.height) / 2.0)), size: labelSize)
            
            if let iconView = self.iconView, let image = iconView.image {
                labelFrame.origin.x -= image.size.width - 6.0
                
                transition.setPosition(view: iconView, position: CGPoint(x: availableSize.width - rightInset + 6.0 - floor(image.size.width * 0.5), y: floor(height * 0.5)))
                let angle: CGFloat = component.isExpanded ? CGFloat.pi : 0.0
                transition.setTransform(view: iconView, transform: CATransform3DMakeRotation(CGFloat.pi * 0.5 - angle, 0.0, 0.0, 1.0))
            }
            
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.isUserInteractionEnabled = false
                    self.addSubview(titleView)
                }
                transition.setFrame(view: titleView, frame: titleFrame)
            }
            if let titleValueView = self.titleValue.view {
                if titleValueView.superview == nil {
                    titleValueView.isUserInteractionEnabled = false
                    self.addSubview(titleValueView)
                }
                
                if titleValueView.bounds.size != titleValueFrame.size {
                    titleValueView.frame = titleValueFrame
                } else {
                    transition.setFrame(view: titleValueView, frame: titleValueFrame)
                }
            }
            if let labelView = self.label.view {
                if labelView.superview == nil {
                    labelView.isUserInteractionEnabled = false
                    self.addSubview(labelView)
                }
                transition.setFrame(view: labelView, frame: labelFrame)
            }
            
            var copyCheckLayer: CheckLayer?
            if themeUpdated {
                if !transition.animation.isImmediate {
                    let copyLayer = CheckLayer(theme: self.checkLayer.theme)
                    copyLayer.frame = self.checkLayer.frame
                    copyLayer.setSelected(self.checkLayer.selected, animated: false)
                    self.layer.addSublayer(copyLayer)
                    copyCheckLayer = copyLayer
                    transition.setAlpha(layer: copyLayer, alpha: 0.0, completion: { [weak copyLayer] _ in
                        copyLayer?.removeFromSuperlayer()
                    })
                    self.checkLayer.opacity = 0.0
                    transition.setAlpha(layer: self.checkLayer, alpha: 1.0)
                }
                
                var checkForeground = component.theme.list.itemCheckColors.foregroundColor
                if usesMessages {
                    var red: CGFloat = 0.0
                    var green: CGFloat = 0.0
                    var blue: CGFloat = 0.0
                    var alpha: CGFloat = 0.0
                    if component.category.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                        checkForeground = storageCategoryUsesDarkForeground(red: red, green: green, blue: blue) ? .black : .white
                    }
                }
                self.checkLayer.theme = CheckNodeTheme(
                    backgroundColor: component.category.color,
                    strokeColor: checkForeground,
                    borderColor: component.theme.list.itemCheckColors.strokeColor,
                    overlayBorder: false,
                    hasInset: false,
                    hasShadow: false
                )
            }
            
            let checkDiameter: CGFloat = 22.0
            let checkFrame = CGRect(origin: CGPoint(x: titleFrame.minX - 20.0 - checkDiameter, y: floor((height - checkDiameter) / 2.0)), size: CGSize(width: checkDiameter, height: checkDiameter))
            transition.setFrame(layer: self.checkLayer, frame: checkFrame)
            
            if let copyCheckLayer {
                transition.setFrame(layer: copyCheckLayer, frame: checkFrame)
            }
            
            transition.setFrame(view: self.checkButtonArea, frame: CGRect(origin: CGPoint(x: additionalLeftInset, y: 0.0), size: CGSize(width: leftInset - additionalLeftInset, height: height)))
            
            if self.checkLayer.selected != component.category.isSelected {
                self.checkLayer.setSelected(component.category.isSelected, animated: !transition.animation.isImmediate)
            }
            
            if themeUpdated {
                self.separatorLayer.backgroundColor = component.theme.list.itemBlocksSeparatorColor.cgColor
            }
            transition.setFrame(layer: self.separatorLayer, frame: CGRect(origin: CGPoint(x: leftInset, y: height), size: CGSize(width: availableSize.width - leftInset, height: UIScreenPixel)))
            
            transition.setAlpha(layer: self.separatorLayer, alpha: (component.isExpanded || component.hasNext) ? 1.0 : 0.0)
            
            self.highlightBackgroundFrame = CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: height + ((component.isExpanded || component.hasNext) ? UIScreenPixel : 0.0)))
            
            var validKeys = Set<StorageUsageScreenComponent.Category>()
            if component.isExpanded {
                for i in 0 ..< component.category.subcategories.count {
                    let category = component.category.subcategories[i]
                    validKeys.insert(category.key)
                    
                    var itemTransition = transition
                    let itemView: ComponentView<Empty>
                    if let current = self.itemViews[category.key] {
                        itemView = current
                    } else {
                        itemTransition = .immediate
                        itemView = ComponentView()
                        self.itemViews[category.key] = itemView
                    }
                    
                    itemView.parentState = state
                    let itemSize = itemView.update(
                        transition: itemTransition,
                        component: AnyComponent(StorageCategoryItemComponent(
                            theme: component.theme,
                            strings: component.strings,
                            category: category,
                            isExpandedLevel: true,
                            isExpanded: false,
                            hasNext: i != component.category.subcategories.count - 1,
                            action: { [weak self] key, _ in
                                guard let self else {
                                    return
                                }
                                self.component?.action(key, .toggle)
                            }
                        )),
                        environment: {},
                        containerSize: CGSize(width: availableSize.width, height: 1000.0)
                    )
                    let itemFrame = CGRect(origin: CGPoint(x: 0.0, y: height), size: itemSize)
                    if let itemComponentView = itemView.view {
                        if itemComponentView.superview == nil {
                            self.subcategoryClippingContainer.addSubview(itemComponentView)
                            if !transition.animation.isImmediate {
                                itemComponentView.alpha = 0.0
                                transition.setAlpha(view: itemComponentView, alpha: 1.0)
                            }
                        }
                        itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                    }
                    
                    height += itemSize.height
                }
            }
            
            var removeKeys: [StorageUsageScreenComponent.Category] = []
            for (key, itemView) in self.itemViews {
                if !validKeys.contains(key) {
                    if let itemComponentView = itemView.view {
                        transition.setAlpha(view: itemComponentView, alpha: 0.0, completion: { [weak itemComponentView] _ in
                            itemComponentView?.removeFromSuperview()
                        })
                    }
                    removeKeys.append(key)
                }
            }
            for key in removeKeys {
                self.itemViews.removeValue(forKey: key)
            }
            
            transition.setFrame(view: self.subcategoryClippingContainer, frame: CGRect(origin: CGPoint(), size: CGSize(width: availableSize.width, height: height)))
            self.selectionAccessibilityElement.accessibilityLabel = component.category.title
            self.selectionAccessibilityElement.accessibilityValue = [fractionString, sizeText].filter { !$0.isEmpty }.joined(separator: ", ")
            self.selectionAccessibilityElement.accessibilityTraits = component.category.isSelected ? [.button, .selected] : [.button]
            if component.category.subcategories.isEmpty {
                self.selectionAccessibilityElement.accessibilityFrameInContainerSpace = CGRect(x: 0.0, y: 0.0, width: availableSize.width, height: rowHeight)
                self.accessibilityElements = [self.selectionAccessibilityElement]
            } else {
                self.selectionAccessibilityElement.accessibilityFrameInContainerSpace = self.checkButtonArea.frame
                self.headerAccessibilityElement.accessibilityLabel = component.category.title
                self.headerAccessibilityElement.accessibilityValue = self.selectionAccessibilityElement.accessibilityValue
                self.headerAccessibilityElement.accessibilityFrameInContainerSpace = CGRect(x: leftInset, y: 0.0, width: max(1.0, availableSize.width - leftInset), height: rowHeight)
                var elements: [Any] = [self.selectionAccessibilityElement, self.headerAccessibilityElement]
                if component.isExpanded {
                    for category in component.category.subcategories {
                        if let view = self.itemViews[category.key]?.view {
                            elements.append(view)
                        }
                    }
                }
                self.accessibilityElements = elements
            }
            
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
