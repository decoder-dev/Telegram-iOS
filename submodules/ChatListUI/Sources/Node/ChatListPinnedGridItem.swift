import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AvatarNode

/// One pinned chat in the grid at the top of the chat list.
struct ChatListPinnedGridPeer: Equatable {
    var peer: EnginePeer
    var isSavedMessages: Bool
    var title: String
    var isUnread: Bool
    var unreadCount: Int32
    var isMuted: Bool
    /// The newest message, shown in a small bubble above the avatar while the chat is unread.
    var preview: String?
    var isTyping: Bool
}

/// The Messages look: pinned chats are a grid of large round avatars above the list, three to a row, as in iOS
/// Messages. A tap opens the chat; a long press offers Unpin and Mute or Unmute. In edit mode the pinned chats go
/// back to rows, so they can still be reordered.
final class ChatListPinnedGridItem: ListViewItem {
    let context: AccountContext
    let presentationData: ChatListPresentationData
    let peers: [ChatListPinnedGridPeer]
    let interaction: ChatListNodeInteraction

    var neighborDescriptor: AnyEquatable {
        return AnyEquatable.noNeighborInfluence
    }

    let selectable: Bool = false

    init(context: AccountContext, presentationData: ChatListPresentationData, peers: [ChatListPinnedGridPeer], interaction: ChatListNodeInteraction) {
        self.context = context
        self.presentationData = presentationData
        self.peers = peers
        self.interaction = interaction
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatListPinnedGridItemNode()
            let (nodeLayout, apply) = node.asyncLayout()(self, params)
            node.insets = nodeLayout.insets
            node.contentSize = nodeLayout.contentSize
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in
                        apply(synchronousLoads)
                    })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let nodeValue = node() as? ChatListPinnedGridItemNode else {
                return
            }
            let layout = nodeValue.asyncLayout()
            async {
                let (nodeLayout, apply) = layout(self, params)
                Queue.mainQueue().async {
                    completion(nodeLayout, { _ in
                        apply(false)
                    })
                }
            }
        }
    }
}

private enum PinnedGridMetrics {
    static let columns = 3
    static let horizontalInset: CGFloat = 16.0
    static let topInset: CGFloat = 10.0
    static let bottomInset: CGFloat = 14.0
    static let previewHeight: CGFloat = 26.0
    static let titleSpacing: CGFloat = 6.0
    static let rowSpacing: CGFloat = 12.0

    static func avatarDiameter(width: CGFloat, fontSize: PresentationFontSize) -> CGFloat {
        let column = floor((width - horizontalInset * 2.0) / CGFloat(columns))
        return min(84.0, floor(column * 0.72))
    }

    static func titleHeight(fontSize: PresentationFontSize) -> CGFloat {
        return ceil(Font.regular(floor(fontSize.itemListBaseFontSize * 13.0 / 17.0)).lineHeight)
    }

    static func cellHeight(width: CGFloat, fontSize: PresentationFontSize) -> CGFloat {
        return previewHeight + avatarDiameter(width: width, fontSize: fontSize) + titleSpacing + titleHeight(fontSize: fontSize)
    }
}

final class ChatListPinnedGridItemNode: ListViewItemNode {
    private var item: ChatListPinnedGridItem?
    private var cells: [EnginePeer.Id: ChatListPinnedGridCellNode] = [:]
    private let separatorNode: ASDisplayNode

    required init() {
        self.separatorNode = ASDisplayNode()
        self.separatorNode.isLayerBacked = true
        super.init(layerBacked: false)
        self.addSubnode(self.separatorNode)
    }

    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, neighbors: ListViewItemNeighbors) {
        guard let item = item as? ChatListPinnedGridItem else {
            return
        }
        let (_, apply) = self.asyncLayout()(item, params)
        apply(false)
    }

    func asyncLayout() -> (_ item: ChatListPinnedGridItem, _ params: ListViewItemLayoutParams) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        return { [weak self] item, params in
            let width = params.width - params.leftInset - params.rightInset
            let fontSize = item.presentationData.fontSize
            let rows = max(1, (item.peers.count + PinnedGridMetrics.columns - 1) / PinnedGridMetrics.columns)
            let cellHeight = PinnedGridMetrics.cellHeight(width: width, fontSize: fontSize)
            let height = PinnedGridMetrics.topInset + CGFloat(rows) * cellHeight + CGFloat(rows - 1) * PinnedGridMetrics.rowSpacing + PinnedGridMetrics.bottomInset
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: UIEdgeInsets())

            return (layout, { synchronousLoads in
                guard let self else {
                    return
                }
                self.item = item
                self.contentSize = layout.contentSize
                self.insets = layout.insets

                let columnWidth = floor((width - PinnedGridMetrics.horizontalInset * 2.0) / CGFloat(PinnedGridMetrics.columns))
                let avatarDiameter = PinnedGridMetrics.avatarDiameter(width: width, fontSize: fontSize)
                var validIds = Set<EnginePeer.Id>()
                for (index, gridPeer) in item.peers.enumerated() {
                    let row = index / PinnedGridMetrics.columns
                    let column = index % PinnedGridMetrics.columns
                    // A last row that is not full is centred, as in Messages.
                    let itemsInRow = min(PinnedGridMetrics.columns, item.peers.count - row * PinnedGridMetrics.columns)
                    let rowOffset = CGFloat(PinnedGridMetrics.columns - itemsInRow) * columnWidth / 2.0
                    let frame = CGRect(
                        x: params.leftInset + PinnedGridMetrics.horizontalInset + rowOffset + CGFloat(column) * columnWidth,
                        y: PinnedGridMetrics.topInset + CGFloat(row) * (cellHeight + PinnedGridMetrics.rowSpacing),
                        width: columnWidth,
                        height: cellHeight
                    )
                    let cell: ChatListPinnedGridCellNode
                    if let current = self.cells[gridPeer.peer.id] {
                        cell = current
                    } else {
                        cell = ChatListPinnedGridCellNode()
                        self.cells[gridPeer.peer.id] = cell
                        self.addSubnode(cell)
                    }
                    validIds.insert(gridPeer.peer.id)
                    cell.update(item: item, gridPeer: gridPeer, size: frame.size, avatarDiameter: avatarDiameter, synchronousLoads: synchronousLoads)
                    cell.frame = frame
                }
                for (id, cell) in self.cells where !validIds.contains(id) {
                    cell.removeFromSupernode()
                    self.cells.removeValue(forKey: id)
                }

                self.separatorNode.backgroundColor = item.presentationData.theme.chatList.itemSeparatorColor
                self.separatorNode.frame = CGRect(x: params.leftInset + PinnedGridMetrics.horizontalInset, y: height - UIScreenPixel, width: width - PinnedGridMetrics.horizontalInset, height: UIScreenPixel)
            })
        }
    }
}

private final class ChatListPinnedGridCellNode: ASDisplayNode {
    private let avatarNode: AvatarNode
    private let titleNode: ImmediateTextNode
    private let unreadDotNode: ASImageNode
    private let previewBackgroundNode: ASImageNode
    private let previewTextNode: ImmediateTextNode
    private var item: ChatListPinnedGridItem?
    private var gridPeer: ChatListPinnedGridPeer?
    private var currentAvatarDiameter: CGFloat = 0.0

    override init() {
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 30.0))
        self.titleNode = ImmediateTextNode()
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.textAlignment = .center
        self.titleNode.displaysAsynchronously = false
        self.unreadDotNode = ASImageNode()
        self.unreadDotNode.displaysAsynchronously = false
        self.unreadDotNode.isLayerBacked = true
        self.previewBackgroundNode = ASImageNode()
        self.previewBackgroundNode.displaysAsynchronously = false
        self.previewBackgroundNode.isLayerBacked = true
        self.previewTextNode = ImmediateTextNode()
        self.previewTextNode.maximumNumberOfLines = 1
        self.previewTextNode.displaysAsynchronously = false

        super.init()

        self.addSubnode(self.avatarNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.previewBackgroundNode)
        self.addSubnode(self.previewTextNode)
        self.addSubnode(self.unreadDotNode)
        self.isAccessibilityElement = true
        self.accessibilityTraits = [.button]
    }

    override func didLoad() {
        super.didLoad()
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
        self.view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.longPressGesture(_:))))
    }

    func update(item: ChatListPinnedGridItem, gridPeer: ChatListPinnedGridPeer, size: CGSize, avatarDiameter: CGFloat, synchronousLoads: Bool) {
        let previousPeer = self.gridPeer
        self.item = item
        self.gridPeer = gridPeer
        let theme = item.presentationData.theme
        let fontSize = item.presentationData.fontSize

        let avatarFrame = CGRect(x: floor((size.width - avatarDiameter) / 2.0), y: PinnedGridMetrics.previewHeight, width: avatarDiameter, height: avatarDiameter)
        self.avatarNode.frame = avatarFrame
        if previousPeer?.peer != gridPeer.peer || self.currentAvatarDiameter != avatarDiameter {
            self.currentAvatarDiameter = avatarDiameter
            self.avatarNode.setPeer(context: item.context, theme: theme, peer: gridPeer.peer, overrideImage: gridPeer.isSavedMessages ? .savedMessagesIcon : nil, synchronousLoad: synchronousLoads, displayDimensions: avatarFrame.size)
        }

        self.titleNode.attributedText = NSAttributedString(string: gridPeer.title, font: gridPeer.isUnread ? Font.semibold(floor(fontSize.itemListBaseFontSize * 13.0 / 17.0)) : Font.regular(floor(fontSize.itemListBaseFontSize * 13.0 / 17.0)), textColor: gridPeer.isUnread ? theme.chatList.titleColor : theme.chatList.messageTextColor)
        let titleSize = self.titleNode.updateLayout(CGSize(width: size.width - 4.0, height: 40.0))
        self.titleNode.frame = CGRect(x: floor((size.width - titleSize.width) / 2.0), y: avatarFrame.maxY + PinnedGridMetrics.titleSpacing, width: titleSize.width, height: titleSize.height)

        // The unread dot sits on the avatar's leading edge, with a ring in the list colour so it reads on any photo.
        if gridPeer.isUnread {
            let dotColor = gridPeer.isMuted ? theme.chatList.unreadBadgeInactiveBackgroundColor : theme.chatList.unreadBadgeActiveBackgroundColor
            self.unreadDotNode.image = generateFilledCircleImage(diameter: 16.0, color: dotColor, strokeColor: theme.chatList.backgroundColor, strokeWidth: 2.5)
            self.unreadDotNode.isHidden = false
            let angle = CGFloat.pi * 0.75
            let center = CGPoint(x: avatarFrame.midX + cos(angle) * avatarDiameter / 2.0 * 0.92, y: avatarFrame.midY - sin(angle) * avatarDiameter / 2.0 * 0.92)
            self.unreadDotNode.frame = CGRect(x: center.x - 8.0, y: center.y - 8.0, width: 16.0, height: 16.0)
        } else {
            self.unreadDotNode.isHidden = true
        }

        // A small bubble with the newest message (or the typing dots) above the avatar while the chat is unread.
        let previewText: String? = gridPeer.isTyping ? "•••" : (gridPeer.isUnread ? gridPeer.preview : nil)
        if let previewText, !previewText.isEmpty {
            let bubbleFill = theme.chat.message.incoming.bubble.withoutWallpaper.fill.first ?? theme.list.itemBlocksBackgroundColor
            self.previewTextNode.attributedText = NSAttributedString(string: previewText, font: Font.regular(11.0), textColor: theme.chat.message.incoming.primaryTextColor)
            let textSize = self.previewTextNode.updateLayout(CGSize(width: size.width - 16.0, height: 20.0))
            let bubbleSize = CGSize(width: min(size.width - 4.0, textSize.width + 16.0), height: 22.0)
            let bubbleFrame = CGRect(x: floor((size.width - bubbleSize.width) / 2.0), y: 0.0, width: bubbleSize.width, height: bubbleSize.height)
            self.previewBackgroundNode.image = generateStretchableFilledCircleImage(diameter: 22.0, color: bubbleFill)
            self.previewBackgroundNode.frame = bubbleFrame
            self.previewTextNode.frame = CGRect(x: bubbleFrame.minX + floor((bubbleFrame.width - textSize.width) / 2.0), y: bubbleFrame.minY + floor((bubbleFrame.height - textSize.height) / 2.0), width: textSize.width, height: textSize.height)
            self.previewBackgroundNode.isHidden = false
            self.previewTextNode.isHidden = false
        } else {
            self.previewBackgroundNode.isHidden = true
            self.previewTextNode.isHidden = true
        }

        var label = gridPeer.title
        if gridPeer.isUnread && gridPeer.unreadCount > 0 {
            label += ", " + item.presentationData.strings.VoiceOver_Chat_UnreadMessages(gridPeer.unreadCount)
        }
        self.accessibilityLabel = label
        self.accessibilityValue = gridPeer.isUnread ? gridPeer.preview : nil
    }

    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let item = self.item, let gridPeer = self.gridPeer else {
            return
        }
        item.interaction.peerSelected(gridPeer.peer, nil, nil, nil, false)
    }

    @objc private func longPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let item = self.item, let gridPeer = self.gridPeer else {
            return
        }
        let presentationData = item.context.sharedContext.currentPresentationData.with { $0 }
        let strings = presentationData.strings
        let interaction = item.interaction
        let peerId = gridPeer.peer.id
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: gridPeer.title),
                ActionSheetButtonItem(title: strings.ChatList_Context_Unpin, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    interaction.setItemPinned(.peer(peerId), false)
                }),
                ActionSheetButtonItem(title: gridPeer.isMuted ? strings.ChatList_Context_Unmute : strings.ChatList_Context_Mute, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    interaction.setPeerMuted(peerId, !gridPeer.isMuted)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        HapticFeedback().impact(.medium)
        interaction.present(actionSheet)
    }
}
