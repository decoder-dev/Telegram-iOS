import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import SliderComponent
import ItemListUI
import PresentationDataUtils
import AppBundle

func bubbleRadiusSliderValue(_ radius: Int) -> CGFloat {
    return CGFloat(max(4, min(30, radius)) - 4)
}

func bubbleRadiusFromSliderValue(_ value: CGFloat) -> Int {
    guard value.isFinite else { return 4 }
    return Int(max(0, min(26, value)).rounded()) + 4
}

class BubbleSettingsRadiusItem: ListViewItem, ItemListItem {
    let accessibilityLabel: String
    let theme: PresentationTheme
    let value: Int
    let disableLeadingInset: Bool
    let displayIcons: Bool
    let disableDecorations: Bool
    let force: Bool
    let enabled: Bool
    let sectionId: ItemListSectionId
    let updated: (Int) -> Void
    let tag: ItemListItemTag?
    
    init(theme: PresentationTheme, accessibilityLabel: String, value: Int, enabled: Bool = true, disableLeadingInset: Bool = false, displayIcons: Bool = true, disableDecorations: Bool = false, force: Bool = false, sectionId: ItemListSectionId, updated: @escaping (Int) -> Void, tag: ItemListItemTag? = nil) {
        self.accessibilityLabel = accessibilityLabel
        self.theme = theme
        self.value = value
        self.enabled = enabled
        self.disableLeadingInset = disableLeadingInset
        self.displayIcons = displayIcons
        self.disableDecorations = disableDecorations
        self.force = force
        self.sectionId = sectionId
        self.updated = updated
        self.tag = tag
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = BubbleSettingsRadiusItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? BubbleSettingsRadiusItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

class BubbleSettingsRadiusItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let valueNode = ASTextNode()
    private let accessibilityArea = AccessibilityAreaNode()
    private var sliderView: EditorStyleSliderView?
    private let leftIconNode: ASImageNode
    private let rightIconNode: ASImageNode
    private let disabledOverlayNode: ASDisplayNode
    
    private var item: BubbleSettingsRadiusItem?
    private var layoutParams: ListViewItemLayoutParams?
    
    var tag: ItemListItemTag? {
        return self.item?.tag
    }
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.maskNode = ASImageNode()
        
        self.leftIconNode = ASImageNode()
        self.leftIconNode.displaysAsynchronously = false
        self.leftIconNode.displayWithoutProcessing = true
        
        self.rightIconNode = ASImageNode()
        self.rightIconNode.displaysAsynchronously = false
        self.rightIconNode.displayWithoutProcessing = true
        
        self.disabledOverlayNode = ASDisplayNode()
        
        super.init(layerBacked: false)
        
        self.addSubnode(self.leftIconNode)
        self.addSubnode(self.rightIconNode)
        
        self.addSubnode(self.disabledOverlayNode)
        self.addSubnode(self.valueNode)
        self.addSubnode(self.accessibilityArea)
        self.accessibilityArea.accessibilityTraits = [.adjustable]
        self.accessibilityArea.increment = { [weak self] in self?.adjustRadius(by: 1) }
        self.accessibilityArea.decrement = { [weak self] in self?.adjustRadius(by: -1) }
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.isAccessibilityElement = false
        
        let sliderView = EditorStyleSliderView()
        sliderView.isAccessibilityElement = false
        sliderView.enablePanHandling = true
        sliderView.trackCornerRadius = 2.0
        sliderView.lineSize = 4.0
        sliderView.dotSize = 8.0
        sliderView.minimumValue = 0.0
        sliderView.maximumValue = 26.0
        sliderView.startValue = 0.0
        sliderView.positionsCount = 27
        sliderView.useLinesForPositions = true
        sliderView.disablesInteractiveTransitionGestureRecognizer = true
        if let item = self.item, let params = self.layoutParams {
            sliderView.isUserInteractionEnabled = item.enabled
            
            sliderView.value = bubbleRadiusSliderValue(item.value)
            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
            sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
            sliderView.trackColor = item.enabled ? item.theme.list.itemAccentColor : item.theme.list.itemDisabledTextColor
            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
            
            let sliderInset: CGFloat = item.displayIcons ? 38.0 : 16.0
            
            sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + sliderInset, y: 8.0), size: CGSize(width: max(0.0, params.width - params.leftInset - params.rightInset - sliderInset * 2.0 - 40.0), height: 44.0))
        }
        self.view.insertSubview(sliderView, belowSubview: self.disabledOverlayNode.view)
        sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.sliderView = sliderView
    }
    
    func asyncLayout() -> (_ item: BubbleSettingsRadiusItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item
        
        return { item, params, neighbors in
            var updatedLeftIcon: UIImage?
            var updatedRightIcon: UIImage?
            
            var themeUpdated = false
            if currentItem?.theme !== item.theme {
                themeUpdated = true
                
                updatedLeftIcon = generateTintedImage(image: UIImage(bundleImageName: "Instant View/SettingsFontMinIcon"), color: item.theme.list.itemPrimaryTextColor)
                updatedRightIcon = generateTintedImage(image: UIImage(bundleImageName: "Instant View/SettingsFontMaxIcon"), color: item.theme.list.itemPrimaryTextColor)
            }
            
            let contentSize: CGSize
            var insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            
            contentSize = CGSize(width: params.width, height: 60.0)
            insets = itemListNeighborsGroupedInsets(neighbors, params)
            
            if item.disableLeadingInset {
                insets.top = 0.0
                insets.bottom = 0.0
            }
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.layoutParams = params
                    let radius = bubbleRadiusFromSliderValue(bubbleRadiusSliderValue(item.value))
                    strongSelf.accessibilityArea.accessibilityLabel = item.accessibilityLabel
                    strongSelf.accessibilityArea.accessibilityValue = "\(radius)"
                    strongSelf.accessibilityArea.frame = CGRect(origin: .zero, size: layoutSize)
                    strongSelf.valueNode.attributedText = NSAttributedString(string: "\(radius)", font: Font.regular(16.0), textColor: item.theme.list.itemPrimaryTextColor)
                    let valueSize = strongSelf.valueNode.measure(CGSize(width: 40.0, height: 44.0))
                    strongSelf.valueNode.frame = CGRect(x: params.width - params.rightInset - 16.0 - valueSize.width, y: floor((60.0 - valueSize.height) / 2.0), width: valueSize.width, height: valueSize.height)
                    
                    if item.enabled {
                        strongSelf.accessibilityArea.accessibilityTraits.remove(.notEnabled)
                    } else {
                        strongSelf.accessibilityArea.accessibilityTraits.insert(.notEnabled)
                    }
                    
                    strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    
                    strongSelf.disabledOverlayNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor.withAlphaComponent(0.4)
                    strongSelf.disabledOverlayNode.isHidden = item.enabled
                    strongSelf.disabledOverlayNode.frame = CGRect(origin: CGPoint(x: params.leftInset, y: 8.0), size: CGSize(width: params.width - params.leftInset - params.rightInset, height: 44.0))
                    
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                    }
                    
                    let hasCorners = itemListHasRoundedBlockLayout(params) && !item.disableDecorations
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                    case .sameSection(false):
                        strongSelf.topStripeNode.isHidden = true
                    default:
                        hasTopCorners = true
                        strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    let bottomStripeInset: CGFloat
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                        case .sameSection(false):
                            bottomStripeInset = params.leftInset + 16.0
                            bottomStripeOffset = -separatorHeight
                            strongSelf.bottomStripeNode.isHidden = false
                        default:
                            bottomStripeInset = 0.0
                            bottomStripeOffset = 0.0
                            hasBottomCorners = true
                            strongSelf.bottomStripeNode.isHidden = hasCorners
                    }
                    
                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                    
                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                    
                    if let updatedLeftIcon = updatedLeftIcon {
                        strongSelf.leftIconNode.image = updatedLeftIcon
                    }
                    if let image = strongSelf.leftIconNode.image {
                        strongSelf.leftIconNode.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 25.0), size: CGSize(width: image.size.width, height: image.size.height))
                    }
                    if let updatedRightIcon = updatedRightIcon {
                        strongSelf.rightIconNode.image = updatedRightIcon
                    }
                    if let image = strongSelf.rightIconNode.image {
                        strongSelf.rightIconNode.frame = CGRect(origin: CGPoint(x: params.width - params.rightInset - 14.0 - image.size.width, y: 21.0), size: CGSize(width: image.size.width, height: image.size.height))
                    }
                    
                    strongSelf.leftIconNode.isHidden = !item.displayIcons
                    strongSelf.rightIconNode.isHidden = !item.displayIcons
                    
                    if let sliderView = strongSelf.sliderView {
                        sliderView.isUserInteractionEnabled = item.enabled
                        sliderView.trackColor = item.enabled ? item.theme.list.itemAccentColor : item.theme.list.itemDisabledTextColor
                        
                        if themeUpdated {
                            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                            sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
                            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
                        }
                        
                        let value: CGFloat = bubbleRadiusSliderValue(item.value)
                        sliderView.value = value
                        
                        let sliderInset: CGFloat = item.displayIcons ? 38.0 : 16.0
                        sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + sliderInset, y: 8.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - sliderInset * 2.0, height: 44.0))
                    }
                }
            })
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
    private func adjustRadius(by delta: Int) {
        guard let item = self.item, item.enabled else { return }
        let current = bubbleRadiusFromSliderValue(bubbleRadiusSliderValue(item.value))
        let value = max(4, min(30, current + delta))
        if value != current { item.updated(value) }
    }

    @objc func sliderValueChanged() {
        guard let sliderView = self.sliderView else {
            return
        }
        guard let item = self.item, item.enabled else { return }
        let value = bubbleRadiusFromSliderValue(sliderView.value)
        if value != item.value { item.updated(value) }
    }
}
