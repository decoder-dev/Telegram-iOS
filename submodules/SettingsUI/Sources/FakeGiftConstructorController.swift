import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
@preconcurrency import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import StickerResources

public struct OfficialGiftBackdrop: Equatable, Sendable {
    public let name: String
    public let hex: String
    public let innerColor: Int32
    public let outerColor: Int32
    public let patternColor: Int32

    public init(name: String, hex: String, innerColor: UInt32, outerColor: UInt32, patternColor: UInt32) {
        self.name = name
        self.hex = hex
        self.innerColor = Int32(bitPattern: innerColor)
        self.outerColor = Int32(bitPattern: outerColor)
        self.patternColor = Int32(bitPattern: patternColor)
    }

    public static let all: [OfficialGiftBackdrop] = [
        OfficialGiftBackdrop(name: "Cosmic", hex: "#9C27B0", innerColor: 0xFF9C27B0, outerColor: 0xFF4A148C, patternColor: 0xFF7B1FA2),
        OfficialGiftBackdrop(name: "Emerald", hex: "#00E676", innerColor: 0xFF00E676, outerColor: 0xFF1B5E20, patternColor: 0xFF00C853),
        OfficialGiftBackdrop(name: "Ruby", hex: "#FF1744", innerColor: 0xFFFF1744, outerColor: 0xFF880E4F, patternColor: 0xFFD50000),
        OfficialGiftBackdrop(name: "Sapphire", hex: "#2979FF", innerColor: 0xFF2979FF, outerColor: 0xFF0D47A1, patternColor: 0xFF1565C0),
        OfficialGiftBackdrop(name: "Amber", hex: "#FFB300", innerColor: 0xFFFFB300, outerColor: 0xFFFF6F00, patternColor: 0xFFFF8F00),
        OfficialGiftBackdrop(name: "Obsidian", hex: "#424242", innerColor: 0xFF424242, outerColor: 0xFF000000, patternColor: 0xFF212121),
        OfficialGiftBackdrop(name: "Neon", hex: "#00E5FF", innerColor: 0xFF00E5FF, outerColor: 0xFFD500F9, patternColor: 0xFF7C4DFF),
        OfficialGiftBackdrop(name: "Gold", hex: "#FFD700", innerColor: 0xFFFFD700, outerColor: 0xFFB8860B, patternColor: 0xFFDAA520),
        OfficialGiftBackdrop(name: "Sunset", hex: "#FF6D00", innerColor: 0xFFFF6D00, outerColor: 0xFFDD2C00, patternColor: 0xFFE65100),
        OfficialGiftBackdrop(name: "Azure", hex: "#00B0FF", innerColor: 0xFF00B0FF, outerColor: 0xFF0091EA, patternColor: 0xFF0288D1),
        OfficialGiftBackdrop(name: "Amethyst", hex: "#BA68C8", innerColor: 0xFFBA68C8, outerColor: 0xFF6A1B9A, patternColor: 0xFF8E24AA),
        OfficialGiftBackdrop(name: "Midnight", hex: "#283593", innerColor: 0xFF283593, outerColor: 0xFF0D1B2A, patternColor: 0xFF1A237E),
        OfficialGiftBackdrop(name: "Mint", hex: "#00BFA5", innerColor: 0xFF00BFA5, outerColor: 0xFF004D40, patternColor: 0xFF00897B),
        OfficialGiftBackdrop(name: "Platinum", hex: "#ECEFF1", innerColor: 0xFFECEFF1, outerColor: 0xFF78909C, patternColor: 0xFFB0BEC5)
    ]
}

public struct OfficialGiftModelItem: Equatable, @unchecked Sendable {
    public let id: Int64
    public let title: String
    public let file: TelegramMediaFile?

    public init(id: Int64, title: String, file: TelegramMediaFile?) {
        self.id = id
        self.title = title
        self.file = file
    }
}

final class FakeGiftPreviewItem: ListViewItem, ItemListItem {
    var sectionId: ItemListSectionId
    let theme: PresentationTheme
    let context: AccountContext
    let modelTitle: String
    let file: TelegramMediaFile?
    let backdrop: OfficialGiftBackdrop
    let patternName: String
    let number: Int32

    init(theme: PresentationTheme, context: AccountContext, sectionId: ItemListSectionId, modelTitle: String, file: TelegramMediaFile?, backdrop: OfficialGiftBackdrop, patternName: String, number: Int32) {
        self.theme = theme
        self.context = context
        self.sectionId = sectionId
        self.modelTitle = modelTitle
        self.file = file
        self.backdrop = backdrop
        self.patternName = patternName
        self.number = number
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FakeGiftPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FakeGiftPreviewItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class FakeGiftPreviewItemNode: ListViewItemNode, ItemListItemNode {
    var tag: ItemListItemTag?
    private let cardContainerNode = ASDisplayNode()
    private let gradientLayer = CAGradientLayer()
    private var animationNode: AnimatedStickerNode?
    private let numberBadgeNode = ASTextNode()
    private let titleBadgeNode = ASTextNode()

    init() {
        super.init(layerBacked: false)
        self.addSubnode(self.cardContainerNode)
        self.cardContainerNode.layer.cornerRadius = 24.0
        self.cardContainerNode.clipsToBounds = true
        self.cardContainerNode.layer.insertSublayer(self.gradientLayer, at: 0)
        self.cardContainerNode.addSubnode(self.numberBadgeNode)
        self.cardContainerNode.addSubnode(self.titleBadgeNode)
    }

    func asyncLayout() -> (_ item: FakeGiftPreviewItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, _ in
            let cardWidth = params.width - params.leftInset - params.rightInset - 32.0
            let cardHeight: CGFloat = 200.0
            let contentSize = CGSize(width: params.width, height: cardHeight + 16.0)
            let insets = UIEdgeInsets(top: 8.0, left: 0.0, bottom: 8.0, right: 0.0)
            return (ListViewItemNodeLayout(contentSize: contentSize, insets: insets), {
                guard let self else { return }
                self.cardContainerNode.frame = CGRect(x: params.leftInset + 16.0, y: 8.0, width: cardWidth, height: cardHeight)
                self.gradientLayer.frame = self.cardContainerNode.bounds
                self.gradientLayer.colors = [
                    UIColor(rgb: UInt32(bitPattern: item.backdrop.innerColor)).cgColor,
                    UIColor(rgb: UInt32(bitPattern: item.backdrop.outerColor)).cgColor
                ]
                self.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
                self.gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)

                self.numberBadgeNode.attributedText = NSAttributedString(string: "#\(item.number)", font: Font.bold(16.0), textColor: .white)
                let numberSize = self.numberBadgeNode.measure(CGSize(width: 120.0, height: 30.0))
                self.numberBadgeNode.frame = CGRect(x: cardWidth - numberSize.width - 16.0, y: 14.0, width: numberSize.width, height: numberSize.height)

                self.titleBadgeNode.attributedText = NSAttributedString(string: "\(item.modelTitle) • \(item.backdrop.name)", font: Font.medium(14.0), textColor: UIColor(white: 1.0, alpha: 0.9))
                let titleSize = self.titleBadgeNode.measure(CGSize(width: cardWidth - 32.0, height: 30.0))
                self.titleBadgeNode.frame = CGRect(x: 16.0, y: cardHeight - titleSize.height - 14.0, width: titleSize.width, height: titleSize.height)

                if let file = item.file {
                    let animNode: AnimatedStickerNode
                    if let existing = self.animationNode {
                        animNode = existing
                    } else {
                        animNode = DefaultAnimatedStickerNodeImpl()
                        self.animationNode = animNode
                        self.cardContainerNode.addSubnode(animNode)
                    }
                    let animSize: CGFloat = 120.0
                    animNode.frame = CGRect(x: floor((cardWidth - animSize) / 2.0), y: floor((cardHeight - animSize) / 2.0) - 6.0, width: animSize, height: animSize)
                    animNode.setup(source: AnimatedStickerResourceSource(account: item.context.account, resource: file.resource, isVideo: file.isVideoSticker), width: 240, height: 240, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
                } else {
                    self.animationNode?.stop()
                    self.animationNode?.removeFromSupernode()
                    self.animationNode = nil
                }
            })
        }
    }

    deinit {
        self.animationNode?.stop()
        self.animationNode?.removeFromSupernode()
    }
}

final class FakeGiftModelsCarouselItem: ListViewItem, ItemListItem {
    var sectionId: ItemListSectionId
    let theme: PresentationTheme
    let context: AccountContext
    let models: [OfficialGiftModelItem]
    let selectedId: Int64
    let onSelect: (OfficialGiftModelItem) -> Void

    init(theme: PresentationTheme, context: AccountContext, sectionId: ItemListSectionId, models: [OfficialGiftModelItem], selectedId: Int64, onSelect: @escaping (OfficialGiftModelItem) -> Void) {
        self.theme = theme
        self.context = context
        self.sectionId = sectionId
        self.models = models
        self.selectedId = selectedId
        self.onSelect = onSelect
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FakeGiftModelsCarouselItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { return (nil, { _ in apply() }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FakeGiftModelsCarouselItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class FakeGiftModelCellView: UIButton {
    private var animationNode: AnimatedStickerNode?
    private let label = UILabel()
    private var currentModelId: Int64?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.cornerRadius = 16.0
        self.clipsToBounds = true
        self.label.isUserInteractionEnabled = false
        self.label.font = Font.medium(11.0)
        self.label.textAlignment = .center
        self.label.numberOfLines = 2
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(theme: PresentationTheme, context: AccountContext, model: OfficialGiftModelItem, isSelected: Bool) {
        self.backgroundColor = theme.list.itemBlocksBackgroundColor
        if isSelected {
            self.layer.borderWidth = 2.0
            self.layer.borderColor = theme.list.itemAccentColor.cgColor
        } else {
            self.layer.borderWidth = 1.0
            self.layer.borderColor = theme.list.disclosureArrowColor.withAlphaComponent(0.2).cgColor
        }
        self.label.text = model.title
        self.label.textColor = isSelected ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
        self.label.frame = CGRect(x: 4.0, y: 68.0, width: self.bounds.width - 8.0, height: 26.0)

        if let file = model.file {
            if self.currentModelId != model.id {
                self.currentModelId = model.id
                let animNode: AnimatedStickerNode
                if let existing = self.animationNode {
                    animNode = existing
                } else {
                    animNode = DefaultAnimatedStickerNodeImpl()
                    animNode.isUserInteractionEnabled = false
                    self.animationNode = animNode
                    self.addSubview(animNode.view)
                }
                animNode.frame = CGRect(x: 14.0, y: 10.0, width: 50.0, height: 50.0)
                animNode.setup(source: AnimatedStickerResourceSource(account: context.account, resource: file.resource, isVideo: file.isVideoSticker), width: 100, height: 100, playbackMode: .loop, mode: .direct(cachePathPrefix: nil))
            }
        } else {
            self.cleanupAnimation()
        }
    }

    func cleanupAnimation() {
        self.animationNode?.stop()
        self.animationNode?.view.removeFromSuperview()
        self.animationNode = nil
        self.currentModelId = nil
    }

    deinit { self.cleanupAnimation() }
}

private final class FakeGiftModelsCarouselItemNode: ListViewItemNode, ItemListItemNode {
    var tag: ItemListItemTag?
    private let scrollView = UIScrollView()
    private var itemViews: [FakeGiftModelCellView] = []

    init() {
        super.init(layerBacked: false)
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.view.addSubview(self.scrollView)
    }

    deinit {
        for view in self.itemViews { view.cleanupAnimation() }
    }

    func asyncLayout() -> (_ item: FakeGiftModelsCarouselItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, _ in
            let itemHeight: CGFloat = 110.0
            let contentSize = CGSize(width: params.width, height: itemHeight)
            let insets = UIEdgeInsets(top: 4.0, left: 0.0, bottom: 4.0, right: 0.0)
            return (ListViewItemNodeLayout(contentSize: contentSize, insets: insets), {
                guard let self else { return }
                self.scrollView.frame = CGRect(x: 0.0, y: 0.0, width: params.width, height: itemHeight)
                for view in self.itemViews {
                    view.cleanupAnimation()
                    view.removeFromSuperview()
                }
                self.itemViews.removeAll()
                var currentX: CGFloat = params.leftInset + 16.0
                for model in item.models {
                    let cell = FakeGiftModelCellView(frame: CGRect(x: currentX, y: 5.0, width: 78.0, height: 100.0))
                    cell.setup(theme: item.theme, context: item.context, model: model, isSelected: model.id == item.selectedId)
                    cell.addAction(UIAction(handler: { _ in item.onSelect(model) }), for: .touchUpInside)
                    self.scrollView.addSubview(cell)
                    self.itemViews.append(cell)
                    currentX += 88.0
                }
                self.scrollView.contentSize = CGSize(width: currentX + params.rightInset + 6.0, height: itemHeight)
            })
        }
    }
}

final class FakeGiftBackdropCarouselItem: ListViewItem, ItemListItem {
    var sectionId: ItemListSectionId
    let theme: PresentationTheme
    let backdrops: [OfficialGiftBackdrop]
    let selectedHex: String
    let onSelect: (OfficialGiftBackdrop) -> Void

    init(theme: PresentationTheme, sectionId: ItemListSectionId, backdrops: [OfficialGiftBackdrop], selectedHex: String, onSelect: @escaping (OfficialGiftBackdrop) -> Void) {
        self.theme = theme
        self.sectionId = sectionId
        self.backdrops = backdrops
        self.selectedHex = selectedHex
        self.onSelect = onSelect
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FakeGiftBackdropCarouselItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { return (nil, { _ in apply() }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FakeGiftBackdropCarouselItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

private final class FakeGiftBackdropCarouselItemNode: ListViewItemNode, ItemListItemNode {
    var tag: ItemListItemTag?
    private let scrollView = UIScrollView()
    private var itemViews: [UIView] = []

    init() {
        super.init(layerBacked: false)
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.view.addSubview(self.scrollView)
    }

    func asyncLayout() -> (_ item: FakeGiftBackdropCarouselItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, _ in
            let itemHeight: CGFloat = 86.0
            let contentSize = CGSize(width: params.width, height: itemHeight)
            let insets = UIEdgeInsets(top: 4.0, left: 0.0, bottom: 4.0, right: 0.0)
            return (ListViewItemNodeLayout(contentSize: contentSize, insets: insets), {
                guard let self else { return }
                self.scrollView.frame = CGRect(x: 0.0, y: 0.0, width: params.width, height: itemHeight)
                for view in self.itemViews { view.removeFromSuperview() }
                self.itemViews.removeAll()
                var currentX: CGFloat = params.leftInset + 16.0
                for backdrop in item.backdrops {
                    let isSelected = backdrop.hex.lowercased() == item.selectedHex.lowercased()
                    let container = UIButton(type: .custom)
                    container.frame = CGRect(x: currentX, y: 4.0, width: 62.0, height: itemHeight - 8.0)
                    let circle = UIView(frame: CGRect(x: 8.0, y: 4.0, width: 46.0, height: 46.0))
                    circle.isUserInteractionEnabled = false
                    circle.layer.cornerRadius = 23.0
                    circle.clipsToBounds = true
                    let gradient = CAGradientLayer()
                    gradient.frame = circle.bounds
                    gradient.colors = [
                        UIColor(rgb: UInt32(bitPattern: backdrop.innerColor)).cgColor,
                        UIColor(rgb: UInt32(bitPattern: backdrop.outerColor)).cgColor
                    ]
                    circle.layer.addSublayer(gradient)
                    if isSelected {
                        circle.layer.borderWidth = 3.0
                        circle.layer.borderColor = UIColor.white.cgColor
                        let check = UILabel(frame: circle.bounds)
                        check.text = "✓"
                        check.font = Font.bold(18.0)
                        check.textColor = .white
                        check.textAlignment = .center
                        circle.addSubview(check)
                    }
                    container.addSubview(circle)
                    let label = UILabel(frame: CGRect(x: 0.0, y: 54.0, width: 62.0, height: 16.0))
                    label.isUserInteractionEnabled = false
                    label.text = backdrop.name
                    label.font = Font.medium(11.0)
                    label.textColor = isSelected ? item.theme.list.itemAccentColor : item.theme.list.itemPrimaryTextColor
                    label.textAlignment = .center
                    container.addSubview(label)
                    container.addAction(UIAction(handler: { _ in item.onSelect(backdrop) }), for: .touchUpInside)
                    self.scrollView.addSubview(container)
                    self.itemViews.append(container)
                    currentX += 70.0
                }
                self.scrollView.contentSize = CGSize(width: currentX + params.rightInset + 6.0, height: itemHeight)
            })
        }
    }
}

private final class FakeGiftConstructorArguments {
    let context: AccountContext
    let selectModel: (OfficialGiftModelItem) -> Void
    let selectBackdrop: (OfficialGiftBackdrop) -> Void
    let selectPattern: (String) -> Void
    let updateNumber: (Int32) -> Void
    let saveGift: () -> Void

    init(context: AccountContext, selectModel: @escaping (OfficialGiftModelItem) -> Void, selectBackdrop: @escaping (OfficialGiftBackdrop) -> Void, selectPattern: @escaping (String) -> Void, updateNumber: @escaping (Int32) -> Void, saveGift: @escaping () -> Void) {
        self.context = context
        self.selectModel = selectModel
        self.selectBackdrop = selectBackdrop
        self.selectPattern = selectPattern
        self.updateNumber = updateNumber
        self.saveGift = saveGift
    }
}

private enum FakeGiftConstructorSection: Int32 {
    case preview, model, backdrop, pattern, details, actions
}

private enum FakeGiftConstructorEntry: ItemListNodeEntry {
    case previewCard(modelTitle: String, file: TelegramMediaFile?, backdrop: OfficialGiftBackdrop, patternName: String, number: Int32)
    case modelHeader(String)
    case modelCarousel(models: [OfficialGiftModelItem], selectedId: Int64)
    case backdropHeader(String)
    case backdropCarousel(backdrops: [OfficialGiftBackdrop], selectedHex: String)
    case patternHeader(String)
    case patternOption(index: Int, name: String, isSelected: Bool)
    case detailsHeader(String)
    case numberInput(String, String)
    case saveAction(String)

    var section: ItemListSectionId {
        switch self {
        case .previewCard: return FakeGiftConstructorSection.preview.rawValue
        case .modelHeader, .modelCarousel: return FakeGiftConstructorSection.model.rawValue
        case .backdropHeader, .backdropCarousel: return FakeGiftConstructorSection.backdrop.rawValue
        case .patternHeader, .patternOption: return FakeGiftConstructorSection.pattern.rawValue
        case .detailsHeader, .numberInput: return FakeGiftConstructorSection.details.rawValue
        case .saveAction: return FakeGiftConstructorSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .previewCard: return 500
        case .modelHeader: return 1000
        case .modelCarousel: return 1100
        case .backdropHeader: return 2000
        case .backdropCarousel: return 2100
        case .patternHeader: return 3000
        case let .patternOption(index, _, _): return 3100 + Int32(index)
        case .detailsHeader: return 4000
        case .numberInput: return 4100
        case .saveAction: return 5000
        }
    }

    static func ==(lhs: FakeGiftConstructorEntry, rhs: FakeGiftConstructorEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.previewCard(m1, f1, b1, p1, n1), .previewCard(m2, f2, b2, p2, n2)):
            return m1 == m2 && f1?.fileId == f2?.fileId && b1 == b2 && p1 == p2 && n1 == n2
        case let (.modelCarousel(m1, s1), .modelCarousel(m2, s2)):
            return m1 == m2 && s1 == s2
        case let (.backdropCarousel(b1, s1), .backdropCarousel(b2, s2)):
            return b1 == b2 && s1 == s2
        case let (.patternOption(i1, n1, s1), .patternOption(i2, n2, s2)):
            return i1 == i2 && n1 == n2 && s1 == s2
        case let (.numberInput(t1, v1), .numberInput(t2, v2)):
            return t1 == t2 && v1 == v2
        case let (.modelHeader(t1), .modelHeader(t2)),
             let (.backdropHeader(t1), .backdropHeader(t2)),
             let (.patternHeader(t1), .patternHeader(t2)),
             let (.detailsHeader(t1), .detailsHeader(t2)),
             let (.saveAction(t1), .saveAction(t2)):
            return t1 == t2
        default:
            return false
        }
    }

    static func <(lhs: FakeGiftConstructorEntry, rhs: FakeGiftConstructorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FakeGiftConstructorArguments
        switch self {
        case let .previewCard(modelTitle, file, backdrop, patternName, number):
            return FakeGiftPreviewItem(theme: presentationData.theme, context: args.context, sectionId: self.section, modelTitle: modelTitle, file: file, backdrop: backdrop, patternName: patternName, number: number)
        case let .modelHeader(text), let .backdropHeader(text), let .patternHeader(text), let .detailsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .modelCarousel(models, selectedId):
            return FakeGiftModelsCarouselItem(theme: presentationData.theme, context: args.context, sectionId: self.section, models: models, selectedId: selectedId, onSelect: args.selectModel)
        case let .backdropCarousel(backdrops, selectedHex):
            return FakeGiftBackdropCarouselItem(theme: presentationData.theme, sectionId: self.section, backdrops: backdrops, selectedHex: selectedHex, onSelect: args.selectBackdrop)
        case let .patternOption(_, name, isSelected):
            return ItemListDisclosureItem(presentationData: presentationData, title: name, label: isSelected ? "✓" : "", sectionId: self.section, style: .blocks, action: { args.selectPattern(name) })
        case let .numberInput(title, value):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: value,
                placeholder: "1",
                type: .number,
                sectionId: self.section,
                textUpdated: { text in
                    let clean = text.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if let number = Int32(clean), number > 0 { args.updateNumber(number) }
                },
                action: {}
            )
        case let .saveAction(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: args.saveGift)
        }
    }
}

private struct FakeGiftConstructorState: Equatable, @unchecked Sendable {
    var selectedModel: OfficialGiftModelItem
    var selectedBackdrop: OfficialGiftBackdrop
    var selectedPatternName: String
    var giftNumber: Int32
}

public func fakeGiftConstructorController(context: AccountContext, completion: @escaping () -> Void) -> ViewController {
    let defaultBackdrop = OfficialGiftBackdrop.all.first!
    let defaultModel = OfficialGiftModelItem(id: 1001, title: "Star", file: StarGiftsRealMediaCache.shared.file(for: 1001))
    let initialState = FakeGiftConstructorState(selectedModel: defaultModel, selectedBackdrop: defaultBackdrop, selectedPatternName: "Star", giftNumber: 1)
    let statePromise = ValuePromise<FakeGiftConstructorState>(initialState, ignoreRepeated: true)
    let stateValue = Atomic<FakeGiftConstructorState>(value: initialState)
    var dismissImpl: (() -> Void)?

    let arguments = FakeGiftConstructorArguments(
        context: context,
        selectModel: { model in
            let _ = stateValue.modify { current in
                var updated = current
                updated.selectedModel = model
                statePromise.set(updated)
                return updated
            }
        },
        selectBackdrop: { backdrop in
            let _ = stateValue.modify { current in
                var updated = current
                updated.selectedBackdrop = backdrop
                statePromise.set(updated)
                return updated
            }
        },
        selectPattern: { pattern in
            let _ = stateValue.modify { current in
                var updated = current
                updated.selectedPatternName = pattern
                statePromise.set(updated)
                return updated
            }
        },
        updateNumber: { number in
            let _ = stateValue.modify { current in
                var updated = current
                updated.giftNumber = number
                statePromise.set(updated)
                return updated
            }
        },
        saveGift: {
            let state = stateValue.with { $0 }
            if let file = state.selectedModel.file {
                StarGiftsRealMediaCache.shared.register(file: file, for: state.selectedModel.id)
            }
            let gift = FakeStarGiftItem(
                baseGiftId: state.selectedModel.id,
                backdropColorHex: state.selectedBackdrop.hex,
                patternName: state.selectedPatternName,
                giftNumber: state.giftNumber,
                ownerPeerId: context.account.peerId.id._internalGetInt64Value(),
                sendDate: Int32(Date().timeIntervalSince1970),
                canCraft: true
            )
            FakeProfileManager.shared.addGift(gift, for: context.account.peerId.id._internalGetInt64Value())
            completion()
            dismissImpl?()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get(),
        context.engine.payments.cachedStarGifts()
    )
    |> map { presentationData, state, cachedGifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FakeGiftConstructorEntry] = []
        entries.append(.previewCard(
            modelTitle: state.selectedModel.title,
            file: state.selectedModel.file ?? StarGiftsRealMediaCache.shared.file(for: state.selectedModel.id),
            backdrop: state.selectedBackdrop,
            patternName: state.selectedPatternName,
            number: state.giftNumber
        ))

        var availableModels: [OfficialGiftModelItem] = []
        if let cachedGifts, !cachedGifts.isEmpty {
            for gift in cachedGifts {
                switch gift {
                case let .generic(genericGift):
                    var title = genericGift.title ?? ""
                    if title.isEmpty || title.hasPrefix("Gift #") {
                        title = "Подарок #\(genericGift.id % 1000)"
                    }
                    StarGiftsRealMediaCache.shared.register(file: genericGift.file, for: genericGift.id)
                    availableModels.append(OfficialGiftModelItem(id: genericGift.id, title: title, file: genericGift.file))
                case let .unique(uniqueGift):
                    var file: TelegramMediaFile?
                    for attr in uniqueGift.attributes {
                        if case let .model(_, value, _, _) = attr {
                            file = value
                            break
                        }
                    }
                    if let file {
                        StarGiftsRealMediaCache.shared.register(file: file, for: uniqueGift.id)
                    }
                    availableModels.append(OfficialGiftModelItem(id: uniqueGift.id, title: uniqueGift.title, file: file))
                }
            }
        }
        if availableModels.isEmpty {
            let presets = [(1001, "Звезда"), (1002, "Сердце"), (1003, "Бриллиант"), (1004, "Кубок"), (1005, "Торт"), (1006, "Ракета"), (1007, "Корона"), (1008, "Мишка")]
            for (id, title) in presets {
                availableModels.append(OfficialGiftModelItem(id: Int64(id), title: title, file: StarGiftsRealMediaCache.shared.file(for: Int64(id))))
            }
        }

        entries.append(.modelHeader("МОДЕЛЬ ПОДАРКА (ЖИВАЯ СЕТКА)"))
        entries.append(.modelCarousel(models: availableModels, selectedId: state.selectedModel.id))
        entries.append(.backdropHeader("ОФИЦИАЛЬНЫЙ ФОН TELEGRAM (BACKDROP)"))
        entries.append(.backdropCarousel(backdrops: OfficialGiftBackdrop.all, selectedHex: state.selectedBackdrop.hex))
        entries.append(.patternHeader("УЗОР (PATTERN)"))
        let patterns = ["Star", "Diamond", "Stripes", "Waves", "Crown", "Hearts", "Sparkles"]
        for (index, pattern) in patterns.enumerated() {
            entries.append(.patternOption(index: index, name: pattern, isSelected: state.selectedPatternName == pattern))
        }
        entries.append(.detailsHeader("ПАРАМЕТРЫ ЭКЗЕМПЛЯРА"))
        entries.append(.numberInput("Номер", "#\(state.giftNumber)"))
        entries.append(.saveAction("Добавить подарок в профиль"))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Конструктор подарка"),
            leftNavigationButton: ItemListNavigationButton(
                content: .text(presentationData.strings.Common_Cancel),
                style: .regular,
                enabled: true,
                action: { dismissImpl?() }
            ),
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in controller?.dismiss() }
    return controller
}
