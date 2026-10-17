import Foundation
import UIKit
import Photos
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import WallpaperBackgroundNode
import UndoUI

/// Whether the given messages may be rendered to an image. A screenshot is a copy, so it follows the rules
/// of every other copy path: never for copy-protected chats, secret chats or view-once / short-lived media.
public func messageShotIsAllowed(messages: [EngineRawMessage], chatCopyProtected: Bool) -> Bool {
    if messages.isEmpty || chatCopyProtected {
        return false
    }
    for message in messages {
        if message.isCopyProtected() {
            return false
        }
        if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        if message.containsSecretMedia {
            return false
        }
    }
    return true
}

private func messageShotText(_ russian: String, _ english: String) -> String {
    return ForkPresentationLanguage.prefersRussianStrings ? russian : english
}

private final class MessageShotChipNode: HighlightTrackingButtonNode {
    private let backgroundNode: ASImageNode
    private let labelNode: ImmediateTextNode

    override init(pointerStyle: PointerStyle? = nil) {
        self.backgroundNode = ASImageNode()
        self.backgroundNode.displaysAsynchronously = false
        self.labelNode = ImmediateTextNode()
        self.labelNode.displaysAsynchronously = false

        super.init(pointerStyle: pointerStyle)

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.labelNode)
    }

    /// A toggle chip when `width` is nil (sized to its title), otherwise a full-width action button.
    func update(title: String, isSelected: Bool, isAction: Bool, width: CGFloat?, theme: PresentationTheme) -> CGSize {
        let textColor = isSelected ? theme.list.itemCheckColors.foregroundColor : (isAction ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor)
        self.labelNode.attributedText = NSAttributedString(string: title, font: isAction ? Font.semibold(15.0) : Font.regular(14.0), textColor: textColor)
        let titleSize = self.labelNode.updateLayout(CGSize(width: 240.0, height: 100.0))
        let size: CGSize
        if let width {
            size = CGSize(width: width, height: 44.0)
        } else {
            size = CGSize(width: titleSize.width + 24.0, height: 30.0)
        }
        self.labelNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: floorToScreenPixels((size.height - titleSize.height) / 2.0)), size: titleSize)
        self.backgroundNode.image = generateStretchableFilledCircleImage(
            radius: size.height / 2.0,
            color: isSelected ? theme.list.itemCheckColors.fillColor : theme.list.itemBlocksBackgroundColor
        )
        self.backgroundNode.frame = CGRect(origin: CGPoint(), size: size)
        return size
    }
}

private final class MessageShotScreenNode: ASDisplayNode {
    private let context: AccountContext
    private let messages: [EngineRawMessage]

    private var presentationData: PresentationData
    private let initialWallpaper: TelegramWallpaper
    private let preservesWallpaperAcrossThemes: Bool
    private var showWallpaper: Bool = true
    private var darkTheme: Bool

    private let previewContainerNode: ASDisplayNode
    private let previewScrollNode: ASScrollNode
    private let previewContentNode: ASDisplayNode
    private let wallpaperBackgroundNode: WallpaperBackgroundNode
    private let messagesContainerNode: ASDisplayNode
    private var messageNodes: [ListViewItemNode]?

    private let panelNode: ASDisplayNode
    private let panelSeparatorNode: ASDisplayNode
    private let wallpaperChipNode: MessageShotChipNode
    private let darkChipNode: MessageShotChipNode
    private let shareNode: MessageShotChipNode
    private let saveNode: MessageShotChipNode

    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var messagesBoundingFrame: CGRect?

    var presentToast: ((String) -> Void)?
    var presentNativeController: ((UIViewController) -> Void)?

    init(context: AccountContext, messages: [EngineRawMessage], wallpaper: TelegramWallpaper) {
        self.context = context
        self.messages = messages
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.initialWallpaper = wallpaper
        self.preservesWallpaperAcrossThemes = wallpaper != presentationData.theme.chat.defaultWallpaper
        self.presentationData = presentationData.withUpdated(chatWallpaper: wallpaper)
        self.darkTheme = presentationData.theme.overallDarkAppearance

        self.previewContainerNode = ASDisplayNode()
        self.previewContainerNode.clipsToBounds = true

        self.previewScrollNode = ASScrollNode()
        self.previewContentNode = ASDisplayNode()

        self.wallpaperBackgroundNode = createWallpaperBackgroundNode(context: context, forChatDisplay: false)
        self.wallpaperBackgroundNode.displaysAsynchronously = false

        // The chat list is drawn upside down, and so are its item nodes: flip the container and each node back.
        self.messagesContainerNode = ASDisplayNode()
        self.messagesContainerNode.clipsToBounds = false
        self.messagesContainerNode.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)

        self.panelNode = ASDisplayNode()
        self.panelSeparatorNode = ASDisplayNode()
        self.wallpaperChipNode = MessageShotChipNode()
        self.darkChipNode = MessageShotChipNode()
        self.shareNode = MessageShotChipNode()
        self.saveNode = MessageShotChipNode()

        super.init()

        self.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.panelNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.panelSeparatorNode.backgroundColor = self.presentationData.theme.list.itemBlocksSeparatorColor

        self.addSubnode(self.previewContainerNode)
        self.previewContainerNode.addSubnode(self.previewScrollNode)
        self.previewScrollNode.addSubnode(self.previewContentNode)
        self.previewContentNode.addSubnode(self.wallpaperBackgroundNode)
        self.previewContentNode.addSubnode(self.messagesContainerNode)
        self.addSubnode(self.panelNode)
        self.addSubnode(self.panelSeparatorNode)
        self.panelNode.addSubnode(self.wallpaperChipNode)
        self.panelNode.addSubnode(self.darkChipNode)
        self.panelNode.addSubnode(self.shareNode)
        self.panelNode.addSubnode(self.saveNode)

        self.wallpaperChipNode.addTarget(self, action: #selector(self.wallpaperPressed), forControlEvents: .touchUpInside)
        self.darkChipNode.addTarget(self, action: #selector(self.darkPressed), forControlEvents: .touchUpInside)
        self.shareNode.addTarget(self, action: #selector(self.sharePressed), forControlEvents: .touchUpInside)
        self.saveNode.addTarget(self, action: #selector(self.savePressed), forControlEvents: .touchUpInside)

        self.applyWallpaper()
    }

    override func didLoad() {
        super.didLoad()
        self.previewScrollNode.view.alwaysBounceVertical = true
        self.previewScrollNode.view.showsHorizontalScrollIndicator = false
        self.previewScrollNode.view.scrollsToTop = false
        self.previewScrollNode.view.contentInsetAdjustmentBehavior = .never
    }

    private var effectivePresentationData: PresentationData {
        if self.darkTheme == self.presentationData.theme.overallDarkAppearance {
            return self.presentationData
        }
        let theme = self.darkTheme ? defaultDarkColorPresentationTheme : defaultPresentationTheme
        var result = self.presentationData.withUpdated(theme: theme)
        if !self.preservesWallpaperAcrossThemes {
            result = result.withUpdated(chatWallpaper: theme.chat.defaultWallpaper)
        }
        return result
    }

    private func applyWallpaper() {
        let presentationData = self.effectivePresentationData
        self.wallpaperBackgroundNode.update(wallpaper: presentationData.chatWallpaper, animated: false)
        self.wallpaperBackgroundNode.updateBubbleTheme(bubbleTheme: presentationData.theme, bubbleCorners: presentationData.chatBubbleCorners)
        self.wallpaperBackgroundNode.isHidden = !self.showWallpaper
    }

    @objc private func wallpaperPressed() {
        self.showWallpaper = !self.showWallpaper
        self.rebuild()
    }

    @objc private func darkPressed() {
        self.darkTheme = !self.darkTheme
        self.rebuild()
    }

    private func rebuild() {
        if let messageNodes = self.messageNodes {
            for node in messageNodes {
                node.removeFromSupernode()
            }
            self.messageNodes = nil
        }
        self.applyWallpaper()
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }

    /// Messages that belong to one album are drawn as a single bubble group, as in the chat.
    private var groupedMessages: [[EngineRawMessage]] {
        var result: [[EngineRawMessage]] = []
        for message in self.messages {
            if let groupingKey = message.groupingKey, let lastGroupingKey = result.last?.first?.groupingKey, groupingKey == lastGroupingKey {
                result[result.count - 1].append(message)
            } else {
                result.append([message])
            }
        }
        return result
    }

    private func updateMessagesLayout(layout: ContainerViewLayout, containerSize: CGSize, transition: ContainedViewLayoutTransition) -> CGFloat {
        let presentationData = self.effectivePresentationData
        let theme = presentationData.theme.withUpdated(preview: true)

        // Newest first, like the chat history list: item 0 is the bottom one.
        var items: [ListViewItem] = []
        for group in self.groupedMessages.reversed() {
            items.append(self.context.sharedContext.makeChatMessagePreviewItem(context: self.context, messages: group, theme: theme, strings: presentationData.strings, wallpaper: presentationData.chatWallpaper, fontSize: presentationData.chatFontSize, chatBubbleCorners: presentationData.chatBubbleCorners, dateTimeFormat: presentationData.dateTimeFormat, nameOrder: presentationData.nameDisplayOrder, forcedResourceStatus: nil, tapMessage: nil, clickThroughMessage: nil, backgroundNode: self.wallpaperBackgroundNode, availableReactions: nil, accountPeer: nil, isCentered: false, isPreview: true, isStandalone: false, rank: nil, rankRole: nil, isGiftMessageComposerPreview: false))
        }

        let contentWidth = containerSize.width
        let params = ListViewItemLayoutParams(width: contentWidth, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right, availableHeight: layout.size.height)

        func neighbors(_ i: Int) -> ListViewItemNeighbors {
            return ListViewItemNeighbors(previous: i == 0 ? nil : items[i - 1].neighborDescriptor, next: i == (items.count - 1) ? nil : items[i + 1].neighborDescriptor)
        }

        if let messageNodes = self.messageNodes {
            for i in 0 ..< items.count {
                let itemNode = messageNodes[i]
                items[i].updateNode(async: { $0() }, node: {
                    return itemNode
                }, params: params, neighbors: neighbors(i), animation: .None, completion: { (itemLayout, apply) in
                    itemNode.contentSize = itemLayout.contentSize
                    itemNode.insets = itemLayout.insets
                    itemNode.frame = CGRect(origin: itemNode.frame.origin, size: CGSize(width: contentWidth, height: itemLayout.size.height))
                    itemNode.isUserInteractionEnabled = false
                    apply(ListViewItemApply())
                })
            }
        } else {
            var messageNodes: [ListViewItemNode] = []
            for i in 0 ..< items.count {
                var itemNode: ListViewItemNode?
                items[i].nodeConfiguredForParams(async: { $0() }, params: params, synchronousLoads: true, neighbors: neighbors(i), completion: { node, apply in
                    itemNode = node
                    apply().1(ListViewItemApply())
                })
                if let itemNode {
                    itemNode.subnodeTransform = CATransform3DMakeScale(-1.0, 1.0, 1.0)
                    itemNode.isUserInteractionEnabled = false
                    messageNodes.append(itemNode)
                    self.messagesContainerNode.addSubnode(itemNode)
                }
            }
            self.messageNodes = messageNodes
        }

        var bottomOffset: CGFloat = 10.0
        var maxY: CGFloat = 0.0
        if let messageNodes = self.messageNodes {
            for itemNode in messageNodes {
                let itemFrame = CGRect(origin: CGPoint(x: 0.0, y: bottomOffset), size: itemNode.frame.size)
                transition.updateFrame(node: itemNode, frame: itemFrame)
                maxY = max(maxY, itemFrame.maxY)
                bottomOffset += itemNode.frame.height
            }
        }

        let contentHeight = max(containerSize.height, maxY + 10.0)
        let contentSize = CGSize(width: containerSize.width, height: contentHeight)
        if let messageNodes = self.messageNodes {
            for itemNode in messageNodes {
                itemNode.updateFrame(itemNode.frame, within: contentSize)
            }
        }

        if maxY > 10.0 {
            self.messagesBoundingFrame = CGRect(x: 0.0, y: contentHeight - maxY, width: containerSize.width, height: maxY - 10.0)
        } else {
            self.messagesBoundingFrame = nil
        }
        return contentHeight
    }

    private func updatePanel(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) -> CGFloat {
        let theme = self.presentationData.theme
        let sideInset: CGFloat = 16.0 + layout.safeInsets.left
        let availableWidth = layout.size.width - sideInset * 2.0

        var y: CGFloat = 12.0
        let wallpaperSize = self.wallpaperChipNode.update(title: messageShotText("Обои", "Wallpaper"), isSelected: self.showWallpaper, isAction: false, width: nil, theme: theme)
        let darkSize = self.darkChipNode.update(title: messageShotText("Тёмная тема", "Dark theme"), isSelected: self.darkTheme, isAction: false, width: nil, theme: theme)
        transition.updateFrame(node: self.wallpaperChipNode, frame: CGRect(origin: CGPoint(x: sideInset, y: y), size: wallpaperSize))
        transition.updateFrame(node: self.darkChipNode, frame: CGRect(origin: CGPoint(x: sideInset + wallpaperSize.width + 8.0, y: y), size: darkSize))
        y += wallpaperSize.height + 16.0

        let spacing: CGFloat = 8.0
        let actionWidth = floor((availableWidth - spacing) / 2.0)
        let shareSize = self.shareNode.update(title: messageShotText("Поделиться", "Share"), isSelected: true, isAction: true, width: actionWidth, theme: theme)
        let saveSize = self.saveNode.update(title: messageShotText("В Фото", "Save to Photos"), isSelected: false, isAction: true, width: actionWidth, theme: theme)
        transition.updateFrame(node: self.shareNode, frame: CGRect(origin: CGPoint(x: sideInset, y: y), size: shareSize))
        transition.updateFrame(node: self.saveNode, frame: CGRect(origin: CGPoint(x: sideInset + actionWidth + spacing, y: y), size: saveSize))
        y += shareSize.height + 12.0

        return y + layout.intrinsicInsets.bottom
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)

        let panelHeight = self.updatePanel(layout: layout, transition: transition)
        let panelFrame = CGRect(origin: CGPoint(x: 0.0, y: layout.size.height - panelHeight), size: CGSize(width: layout.size.width, height: panelHeight))
        transition.updateFrame(node: self.panelNode, frame: panelFrame)
        transition.updateFrame(node: self.panelSeparatorNode, frame: CGRect(origin: panelFrame.origin, size: CGSize(width: layout.size.width, height: UIScreenPixel)))

        let previewFrame = CGRect(origin: CGPoint(x: 0.0, y: navigationBarHeight), size: CGSize(width: layout.size.width, height: max(1.0, panelFrame.minY - navigationBarHeight)))
        transition.updateFrame(node: self.previewContainerNode, frame: previewFrame)
        transition.updateFrame(node: self.previewScrollNode, frame: CGRect(origin: CGPoint(), size: previewFrame.size))

        let contentHeight = self.updateMessagesLayout(layout: layout, containerSize: previewFrame.size, transition: transition)
        let contentSize = CGSize(width: previewFrame.width, height: contentHeight)
        self.previewContentNode.frame = CGRect(origin: CGPoint(), size: contentSize)
        self.previewScrollNode.view.contentSize = contentSize
        self.wallpaperBackgroundNode.frame = CGRect(origin: CGPoint(), size: contentSize)
        self.wallpaperBackgroundNode.updateLayout(size: contentSize, displayMode: .aspectFill, transition: transition)
        self.messagesContainerNode.frame = CGRect(origin: CGPoint(), size: contentSize)

        let maximumOffset = max(0.0, contentHeight - previewFrame.height)
        let contentOffset = min(maximumOffset, max(0.0, self.previewScrollNode.view.contentOffset.y))
        if self.previewScrollNode.view.contentOffset.y != contentOffset {
            self.previewScrollNode.view.contentOffset = CGPoint(x: 0.0, y: contentOffset)
        }
    }

    private func renderImage() -> UIImage? {
        guard let boundingFrame = self.messagesBoundingFrame else {
            return nil
        }
        var cropFrame = boundingFrame.insetBy(dx: 0.0, dy: -8.0)
        cropFrame = cropFrame.intersection(self.previewContentNode.bounds)
        guard cropFrame.width > 1.0, cropFrame.height > 1.0 else {
            return nil
        }

        let maximumPixelDimension: CGFloat = 16_384.0
        let maximumPixelCount: CGFloat = 64_000_000.0
        let dimensionScale = maximumPixelDimension / max(cropFrame.width, cropFrame.height)
        let pixelCountScale = sqrt(maximumPixelCount / max(1.0, cropFrame.width * cropFrame.height))
        let scale = max(0.1, min(3.0, min(dimensionScale, pixelCountScale)))
        UIGraphicsBeginImageContextWithOptions(cropFrame.size, false, scale)
        defer {
            UIGraphicsEndImageContext()
        }
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        context.translateBy(x: -cropFrame.minX, y: -cropFrame.minY)
        self.previewContentNode.view.drawHierarchy(in: self.previewContentNode.bounds, afterScreenUpdates: true)
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    @objc private func sharePressed() {
        guard let image = self.renderImage(), let data = image.pngData() else {
            self.presentToast?(messageShotText("Не удалось создать изображение", "Couldn't create the image"))
            return
        }
        let tempFileUrl = URL(fileURLWithPath: NSTemporaryDirectory() + "message-shot-\(UInt32.random(in: 0 ..< UInt32.max)).png")
        try? FileManager.default.removeItem(at: tempFileUrl)
        try? data.write(to: tempFileUrl)

        let activityController = UIActivityViewController(activityItems: [tempFileUrl], applicationActivities: nil)
        if let window = self.view.window {
            activityController.popoverPresentationController?.sourceView = window
            activityController.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.size.height - 1.0), size: CGSize(width: 1.0, height: 1.0))
        }
        self.presentNativeController?(activityController)
    }

    @objc private func savePressed() {
        guard let image = self.renderImage() else {
            self.presentToast?(messageShotText("Не удалось создать изображение", "Couldn't create the image"))
            return
        }
        let savedText = messageShotText("Сохранено в Фото", "Saved to Photos")
        let failedText = messageShotText("Не удалось сохранить", "Couldn't save")
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }, completionHandler: { [weak self] success, _ in
            Queue.mainQueue().async {
                self?.presentToast?(success ? savedText : failedText)
            }
        })
    }
}

public final class MessageShotScreen: ViewController {
    private let context: AccountContext
    private let messages: [EngineRawMessage]
    private let wallpaper: TelegramWallpaper
    private var presentationData: PresentationData

    private var controllerNode: MessageShotScreenNode {
        return self.displayNode as! MessageShotScreenNode
    }

    /// Returns nil when the messages may not be rendered (see `messageShotIsAllowed`).
    public init?(context: AccountContext, messages: [EngineRawMessage], wallpaper: TelegramWallpaper, chatCopyProtected: Bool) {
        guard messageShotIsAllowed(messages: messages, chatCopyProtected: chatCopyProtected) else {
            return nil
        }
        self.context = context
        self.messages = messages.sorted(by: { $0.index < $1.index })
        self.wallpaper = wallpaper
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.title = messageShotText("Скриншот", "Screenshot")
        self.navigationPresentation = .modal
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed))
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let controllerNode = MessageShotScreenNode(context: self.context, messages: self.messages, wallpaper: self.wallpaper)
        controllerNode.presentToast = { [weak self] text in
            self?.presentToast(text)
        }
        controllerNode.presentNativeController = { [weak self] controller in
            self?.context.sharedContext.applicationBindings.presentNativeController(controller)
        }
        self.displayNode = controllerNode
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }

    private func presentToast(_ text: String) {
        self.present(UndoOverlayController(
            presentationData: self.presentationData,
            content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
            elevatedLayout: false,
            animateInAsReplacement: false,
            action: { _ in return false }
        ), in: .current)
    }

    @objc private func cancelPressed() {
        self.dismiss()
    }
}
