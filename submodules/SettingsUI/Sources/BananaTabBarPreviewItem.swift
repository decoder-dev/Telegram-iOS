// Adapted from kittenello/Donutgram, commit b4fc6aca7b.
import UIKit
import AsyncDisplayKit
import Display
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ComponentFlow
import ComponentDisplayAdapters
import TabBarComponent
import UIKitRuntimeUtils

final class BananaTabBarPreviewItem: ListViewItem, ItemListItem {
    let context: AccountContext
    let theme: PresentationTheme
    let strings: PresentationStrings
    let sectionId: ItemListSectionId
    let layout: BananaTabBarLayout

    init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings, sectionId: ItemListSectionId, layout: BananaTabBarLayout) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.sectionId = sectionId
        self.layout = layout
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = BananaTabBarPreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { (nil, { _ in apply(.immediate) }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let node = node() as? BananaTabBarPreviewItemNode {
                let makeLayout = node.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async { completion(layout, { _ in apply(animation.transition) }) }
                }
            }
        }
    }
}

private final class BananaTabBarPreviewItemNode: ListViewItemNode, ItemListItemNode {
    var tag: ItemListItemTag? { nil }
    private let block = UIView()
    private let hiddenLabel = UILabel()
    private let tabBar = ComponentView<Empty>()
    private var tabs: [UITabBarItem] = []

    init() {
        super.init(layerBacked: false)
    }

    override func didLoad() {
        super.didLoad()
        self.view.addSubview(self.block)
        self.block.addSubview(self.hiddenLabel)
        self.block.isUserInteractionEnabled = false
        self.block.layer.cornerRadius = 22.0
        self.block.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.block.clipsToBounds = true
        self.hiddenLabel.font = .systemFont(ofSize: 14.0)
        self.hiddenLabel.textAlignment = .center
        self.hiddenLabel.numberOfLines = 0
        self.hiddenLabel.isAccessibilityElement = true
    }

    func displayHighlight() {
        // Preview is decorative and does not accept focus actions.
    }

    private var currentTheme: PresentationTheme?

    func asyncLayout() -> (BananaTabBarPreviewItem, ListViewItemLayoutParams, ItemListNeighbors) -> (ListViewItemNodeLayout, (ContainedViewLayoutTransition) -> Void) {
        return { item, params, neighbors in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 112.0), insets: itemListNeighborsGroupedInsets(neighbors, params))
            return (layout, { [weak self] transition in
                self?.apply(item: item, params: params, transition: transition)
            })
        }
    }

    private func apply(item: BananaTabBarPreviewItem, params: ListViewItemLayoutParams, transition: ContainedViewLayoutTransition) {
        let _ = self.view
        let firstLayout = self.tabBar.view == nil
        let transition: ContainedViewLayoutTransition = UIAccessibility.isReduceMotionEnabled || firstLayout ? .immediate : .animated(duration: 0.35, curve: .spring)
        self.currentTheme = item.theme
        self.block.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        let width = max(1.0, params.width - params.leftInset - params.rightInset)
        transition.updateFrame(view: self.block, frame: CGRect(x: params.leftInset, y: 0.0, width: width, height: 112.0))

        if self.tabs.isEmpty {
            self.tabs = (0 ..< 4).map { _ in UITabBarItem(title: nil, image: nil, selectedImage: nil) }
        }
        let titles = [item.strings.Contacts_Title, item.strings.Calls_TabTitle, item.strings.DialogList_Title, item.strings.Settings_Title]
        let symbols = ["person.2.fill", "phone.fill", "bubble.left.and.bubble.right.fill", "gearshape.fill"]
        let animations = ["TabContacts", "TabCalls", "TabChats", "TabSettings"]
        for (index, tab) in self.tabs.enumerated() {
            tab.title = titles[index]
            let image = UIImage(systemName: symbols[index], withConfiguration: UIImage.SymbolConfiguration(pointSize: 25.0, weight: .regular))
            tab.image = generateTintedImage(image: image, color: item.theme.rootController.tabBar.textColor)
            tab.selectedImage = generateTintedImage(image: image, color: item.theme.rootController.tabBar.selectedTextColor)
            tab.animationName = UIAccessibility.isReduceMotionEnabled ? nil : animations[index]
        }
        var visibleTabs: [UITabBarItem] = []
        if item.layout.contacts { visibleTabs.append(self.tabs[0]) }
        if item.layout.calls { visibleTabs.append(self.tabs[1]) }
        visibleTabs.append(contentsOf: [self.tabs[2], self.tabs[3]])
        let size = self.tabBar.update(
            transition: ComponentTransition(transition),
            component: AnyComponent(TabBarComponent(
                theme: item.theme,
                isLiftedStateEnabled: false,
                strings: item.strings,
                items: visibleTabs.map { TabBarComponent.Item(content: .tabBarItem($0), action: { _ in }, doubleTapAction: nil, contextAction: nil) },
                search: TabBarComponent.Search(isActive: false, activate: {}, deactivate: {}),
                selectedId: AnyHashable(ObjectIdentifier(self.tabs[2])),
                outerInsets: .zero,
                layout: item.layout
            )),
            environment: {},
            containerSize: CGSize(width: max(1.0, width - 24.0), height: 64.0)
        )
        if let tabBarView = self.tabBar.view {
            if tabBarView.superview == nil { self.block.addSubview(tabBarView) }
            transition.updateFrame(view: tabBarView, frame: CGRect(x: (width - size.width) * 0.5, y: 24.0, width: size.width, height: size.height))
            ComponentTransition(transition).setAlpha(view: tabBarView, alpha: item.layout.hidden ? 0.0 : 1.0)
            tabBarView.accessibilityElementsHidden = true
        }
        self.hiddenLabel.text = item.strings.primaryComponent.languageCode.hasPrefix("ru") ? "Панель вкладок скрыта" : "Tab bar hidden"
        self.hiddenLabel.textColor = item.theme.list.itemSecondaryTextColor
        transition.updateFrame(view: self.hiddenLabel, frame: CGRect(x: 20.0, y: 24.0, width: max(1.0, width - 40.0), height: 64.0))
        ComponentTransition(transition).setAlpha(view: self.hiddenLabel, alpha: item.layout.hidden ? 1.0 : 0.0)
        self.hiddenLabel.accessibilityElementsHidden = !item.layout.hidden
    }
}
