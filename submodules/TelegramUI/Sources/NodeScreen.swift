import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListUI

/// The "Node" tab (opt-in, Extras ▸ Tab bar ▸ Node UI): a rail of the account's chat folders ("nodes")
/// on the left and the chats of the selected node on the right.
private struct NodeScreenFolder: Equatable {
    var id: Int32
    var title: String
    var data: ChatListFilterData?

    static func == (lhs: NodeScreenFolder, rhs: NodeScreenFolder) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
    }
}

private struct NodeScreenRow {
    var peer: EnginePeer
    var title: String
    var preview: String
    var unread: Int32
    var isMuted: Bool
}

private let nodeScreenRailWidth: CGFloat = 76.0

public final class NodeScreen: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData

    private let railScroll = UIScrollView()
    private let table = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    private var folders: [NodeScreenFolder] = [NodeScreenFolder(id: 0, title: "All", data: nil)]
    private var selectedFolderId: Int32 = 0
    private var rows: [NodeScreenRow] = []
    private var validLayout: ContainerViewLayout?

    private var foldersDisposable: Disposable?
    private let chatsDisposable = MetaDisposable()
    private var presentationDisposable: Disposable?

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.title = "Node"
        self.tabBarItem.title = "Node"
        let icon = UIImage(systemName: "square.grid.2x2")
        self.tabBarItem.image = icon
        self.tabBarItem.selectedImage = UIImage(systemName: "square.grid.2x2.fill")

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style

        self.presentationDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
            self.applyTheme()
            self.rebuildRail()
            self.table.reloadData()
        })

        self.foldersDisposable = (context.engine.peers.updatedChatListFilters()
        |> deliverOnMainQueue).start(next: { [weak self] filters in
            guard let self else {
                return
            }
            var folders: [NodeScreenFolder] = [NodeScreenFolder(id: 0, title: self.presentationData.strings.ChatList_Tabs_AllChats, data: nil)]
            for filter in filters {
                if case let .filter(id, title, _, data) = filter {
                    folders.append(NodeScreenFolder(id: id, title: title.text, data: data))
                }
            }
            self.folders = folders
            if !folders.contains(where: { $0.id == self.selectedFolderId }) {
                self.selectedFolderId = 0
            }
            self.rebuildRail()
            self.reloadChats()
        })
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.foldersDisposable?.dispose()
        self.chatsDisposable.dispose()
        self.presentationDisposable?.dispose()
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNodeDidLoad()

        let view = self.displayNode.view
        self.railScroll.showsVerticalScrollIndicator = false
        self.table.dataSource = self
        self.table.delegate = self
        self.table.separatorStyle = .none
        self.table.rowHeight = 72.0
        self.table.register(UITableViewCell.self, forCellReuseIdentifier: "node")
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.emptyLabel.text = "No chats in this node"
        view.addSubview(self.table)
        view.addSubview(self.railScroll)
        view.addSubview(self.emptyLabel)
        self.applyTheme()
        self.rebuildRail()
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
        self.table.backgroundColor = theme.list.blocksBackgroundColor
        self.railScroll.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.emptyLabel.textColor = theme.list.itemSecondaryTextColor
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout

        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottom = layout.intrinsicInsets.bottom
        let height = max(0.0, layout.size.height - top)

        self.railScroll.frame = CGRect(x: 0.0, y: top, width: nodeScreenRailWidth, height: height)
        self.railScroll.contentInset = UIEdgeInsets(top: 8.0, left: 0.0, bottom: bottom + 8.0, right: 0.0)
        self.table.frame = CGRect(x: nodeScreenRailWidth, y: top, width: layout.size.width - nodeScreenRailWidth, height: height)
        self.table.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: bottom, right: 0.0)
        self.emptyLabel.frame = self.table.frame
        self.layoutRail()
    }

    // MARK: Rail

    private func rebuildRail() {
        guard self.isNodeViewLoaded else {
            return
        }
        for subview in self.railScroll.subviews {
            subview.removeFromSuperview()
        }
        let theme = self.presentationData.theme
        for (index, folder) in self.folders.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            let selected = folder.id == self.selectedFolderId
            button.backgroundColor = selected ? theme.list.itemAccentColor : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.5)
            button.layer.cornerRadius = selected ? 16.0 : 26.0
            button.clipsToBounds = true
            let initial = String(folder.title.prefix(2)).uppercased()
            button.setTitle(initial, for: .normal)
            button.setTitleColor(selected ? theme.list.itemCheckColors.foregroundColor : theme.list.itemPrimaryTextColor, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
            button.accessibilityLabel = folder.title
            button.addTarget(self, action: #selector(self.railPressed(_:)), for: .touchUpInside)
            self.railScroll.addSubview(button)
        }
        self.layoutRail()
    }

    private func layoutRail() {
        let size: CGFloat = 52.0
        var y: CGFloat = 0.0
        for subview in self.railScroll.subviews {
            subview.frame = CGRect(x: (nodeScreenRailWidth - size) / 2.0, y: y, width: size, height: size)
            y += size + 10.0
        }
        self.railScroll.contentSize = CGSize(width: nodeScreenRailWidth, height: y)
    }

    @objc private func railPressed(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < self.folders.count else {
            return
        }
        self.selectedFolderId = self.folders[sender.tag].id
        self.rebuildRail()
        self.reloadChats()
    }

    // MARK: Chats

    private func reloadChats() {
        let accountPeerId = self.context.account.peerId
        let strings = self.presentationData.strings
        let nameOrder = self.presentationData.nameDisplayOrder
        var predicate: ChatListFilterPredicate?
        if let data = self.folders.first(where: { $0.id == self.selectedFolderId })?.data {
            predicate = chatListFilterPredicate(filter: data, accountPeerId: accountPeerId)
        }
        self.chatsDisposable.set((self.context.account.viewTracker.tailChatListView(groupId: .root, filterPredicate: predicate, count: 200)
        |> map { view, _ -> [NodeScreenRow] in
            var result: [NodeScreenRow] = []
            for entry in view.entries {
                if case let .MessageEntry(entryData) = entry, let peer = entryData.renderedPeer.chatMainPeer {
                    let enginePeer = EnginePeer(peer)
                    let title = enginePeer.displayTitle(strings: strings, displayOrder: nameOrder)
                    let preview = entryData.messages.first?.text ?? ""
                    result.append(NodeScreenRow(
                        peer: enginePeer,
                        title: title,
                        preview: preview,
                        unread: entryData.readState?.state.count ?? 0,
                        isMuted: entryData.readState?.isMuted ?? false
                    ))
                }
            }
            return result
        }
        |> deliverOnMainQueue).start(next: { [weak self] rows in
            guard let self else {
                return
            }
            self.rows = rows
            if self.isNodeViewLoaded {
                self.emptyLabel.isHidden = !rows.isEmpty
                self.table.reloadData()
            }
        }))
    }

    private var isNodeViewLoaded: Bool {
        return self.isViewLoaded
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.rows.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "node", for: indexPath)
        let theme = self.presentationData.theme
        let row = self.rows[indexPath.row]
        cell.backgroundColor = theme.list.blocksBackgroundColor
        cell.selectionStyle = .default
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.secondaryText = row.preview
        content.textProperties.color = theme.list.itemPrimaryTextColor
        content.textProperties.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        content.secondaryTextProperties.color = theme.list.itemSecondaryTextColor
        content.secondaryTextProperties.numberOfLines = 2
        content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 14.0)
        cell.contentConfiguration = content
        if row.unread > 0 {
            let badge = UILabel()
            badge.text = " \(row.unread) "
            badge.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
            badge.textColor = theme.list.itemCheckColors.foregroundColor
            badge.backgroundColor = row.isMuted ? theme.chatList.unreadBadgeInactiveBackgroundColor : theme.list.itemAccentColor
            badge.layer.cornerRadius = 9.0
            badge.clipsToBounds = true
            badge.sizeToFit()
            badge.frame.size.height = 18.0
            cell.accessoryView = badge
        } else {
            cell.accessoryView = nil
        }
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = self.rows[indexPath.row]
        guard let navigationController = self.navigationController as? NavigationController else {
            return
        }
        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(row.peer), keepStack: .always))
    }
}
