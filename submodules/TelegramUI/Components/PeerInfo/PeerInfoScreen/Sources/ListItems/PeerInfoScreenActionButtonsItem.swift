import Foundation
import UIKit
import Display
import AsyncDisplayKit
import AccountContext
import TelegramPresentationData
import TelegramCore
import PresentationDataUtils
import ContextUI

private let actionButtonDiameter: CGFloat = 48.0
private let actionButtonSpacing: CGFloat = 20.0
private let actionCardVerticalInset: CGFloat = 16.0

/// Text and icon for one header button. Split out of PeerInfoHeaderNode's own switch so the header
/// and this card describe the same button the same way.
struct PeerInfoHeaderButtonContent {
    let text: String
    let icon: PeerInfoHeaderButtonIcon
}

func peerInfoHeaderButtonContent(
    key: PeerInfoHeaderButtonKey,
    presentationData: PresentationData,
    peer: EnginePeer?,
    peerNotificationSettings: TelegramPeerNotificationSettings?,
    threadNotificationSettings: TelegramPeerNotificationSettings?,
    globalNotificationSettings: EngineGlobalNotificationSettings?
) -> PeerInfoHeaderButtonContent {
    switch key {
    case .message:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMessage, icon: .message)
    case .discussion:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonDiscuss, icon: .message)
    case .call:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonCall, icon: .call)
    case .videoCall:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonVideoCall, icon: .videoCall)
    case .voiceChat:
        if case let .channel(channel) = peer, case .broadcast = channel.info {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonLiveStream, icon: .voiceChat)
        } else {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonVoiceChat, icon: .voiceChat)
        }
    case .mute:
        let chatIsMuted = peerInfoIsChatMuted(peer: peer, peerNotificationSettings: peerNotificationSettings, threadNotificationSettings: threadNotificationSettings, globalNotificationSettings: globalNotificationSettings)
        if chatIsMuted {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonUnmute, icon: .unmute)
        } else {
            return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMute, icon: .mute)
        }
    case .more:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMore, icon: .more)
    case .addMember:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonAddMember, icon: .addMember)
    case .search:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonSearch, icon: .search)
    case .leave:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonLeave, icon: .leave)
    case .stop:
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonStop, icon: .stop)
    case .addContact:
        // PeerInfoHeaderButtonIcon has no case for this, and `peerInfoHeaderButtons` never emits it —
        // only `peerInfoHeaderActionButtons` does, and that returns [] unconditionally upstream. Fall
        // back to the message icon rather than trapping, so restoring that function cannot crash here.
        return PeerInfoHeaderButtonContent(text: presentationData.strings.PeerInfo_ButtonMessage, icon: .message)
    }
}

final class PeerInfoScreenActionButtonsItem: PeerInfoScreenItem {
    let id: AnyHashable = AnyHashable("profile_action_buttons")
    let buttonKeys: [PeerInfoHeaderButtonKey]
    let highlightedButton: PeerInfoHeaderButtonKey?
    let peer: EnginePeer?
    let peerNotificationSettings: TelegramPeerNotificationSettings?
    let threadNotificationSettings: TelegramPeerNotificationSettings?
    let globalNotificationSettings: EngineGlobalNotificationSettings?
    let performAction: (PeerInfoHeaderButtonKey, PeerInfoHeaderButtonNode?, ContextGesture?) -> Void
    
    init(
        buttonKeys: [PeerInfoHeaderButtonKey],
        highlightedButton: PeerInfoHeaderButtonKey?,
        peer: EnginePeer?,
        peerNotificationSettings: TelegramPeerNotificationSettings?,
        threadNotificationSettings: TelegramPeerNotificationSettings?,
        globalNotificationSettings: EngineGlobalNotificationSettings?,
        performAction: @escaping (PeerInfoHeaderButtonKey, PeerInfoHeaderButtonNode?, ContextGesture?) -> Void
    ) {
        self.buttonKeys = buttonKeys
        self.highlightedButton = highlightedButton
        self.peer = peer
        self.peerNotificationSettings = peerNotificationSettings
        self.threadNotificationSettings = threadNotificationSettings
        self.globalNotificationSettings = globalNotificationSettings
        self.performAction = performAction
    }
    
    func node() -> PeerInfoScreenItemNode {
        return PeerInfoScreenActionButtonsItemNode()
    }
}

private final class PeerInfoScreenActionButtonsItemNode: PeerInfoScreenItemNode {
    private let maskNode: ASImageNode
    private var buttonNodes: [PeerInfoHeaderButtonKey: PeerInfoHeaderButtonNode] = [:]
    private var item: PeerInfoScreenActionButtonsItem?
    private var presentationData: PresentationData?
    
    override init() {
        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false
        super.init()
        self.addSubnode(self.maskNode)
    }
    
    override func update(context: AccountContext, width: CGFloat, safeInsets: UIEdgeInsets, presentationData: PresentationData, item: PeerInfoScreenItem, topItem: PeerInfoScreenItem?, bottomItem: PeerInfoScreenItem?, hasCorners: Bool, transition: ContainedViewLayoutTransition) -> CGFloat {
        guard let item = item as? PeerInfoScreenActionButtonsItem else {
            return 0.0
        }
        self.item = item
        self.presentationData = presentationData
        
        // A subtle lift over the card the row sits on, rather than a literal: white at 10% over the
        // dark card lands on the same grey the reference shows, and the same trick with black gives a
        // visible circle on the light card, where a white lift would disappear.
        let cardColor = presentationData.theme.list.itemBlocksBackgroundColor
        let buttonBackgroundColor: UIColor
        if presentationData.theme.overallDarkAppearance {
            buttonBackgroundColor = UIColor(white: 1.0, alpha: 0.1).blendOver(background: cardColor)
        } else {
            buttonBackgroundColor = UIColor(white: 0.0, alpha: 0.06).blendOver(background: cardColor)
        }

        let height = actionCardVerticalInset * 2.0 + actionButtonDiameter
        let totalButtonsWidth = CGFloat(item.buttonKeys.count) * actionButtonDiameter + CGFloat(max(0, item.buttonKeys.count - 1)) * actionButtonSpacing
        var leftOrigin = floor((width - totalButtonsWidth) / 2.0)
        let buttonY = actionCardVerticalInset
        
        for buttonKey in item.buttonKeys {
            let buttonNode: PeerInfoHeaderButtonNode
            var wasAdded = false
            if let current = self.buttonNodes[buttonKey] {
                buttonNode = current
            } else {
                wasAdded = true
                buttonNode = PeerInfoHeaderButtonNode(key: buttonKey, action: { [weak self] buttonNode, gesture in
                    self?.item?.performAction(buttonNode.key, buttonNode, gesture)
                })
                self.buttonNodes[buttonKey] = buttonNode
                // The button draws its icon and label; its background circle lives in a separate
                // view the owner is expected to place. PeerInfoHeaderNode does that explicitly
                // (`buttonsMaskView.addSubview`), and this item did not — the frame was being set
                // on a view that was in no hierarchy, and the cleanup path below calls
                // `removeFromSuperview` on it, so the #2C2C2E circles simply never rendered.
                // Below the button node, so the icon stays on top.
                self.view.insertSubview(buttonNode.backgroundContainerView, at: 0)
                self.addSubnode(buttonNode)
            }
            
            let buttonFrame = CGRect(origin: CGPoint(x: leftOrigin, y: buttonY), size: CGSize(width: actionButtonDiameter, height: actionButtonDiameter))
            transition.updateFrame(node: buttonNode, frame: buttonFrame)
            transition.updateFrame(view: buttonNode.backgroundContainerView, frame: buttonFrame)
            
            let content = peerInfoHeaderButtonContent(
                key: buttonKey,
                presentationData: presentationData,
                peer: item.peer,
                peerNotificationSettings: item.peerNotificationSettings,
                threadNotificationSettings: item.threadNotificationSettings,
                globalNotificationSettings: item.globalNotificationSettings
            )
            
            var isActive = true
            if let highlightedButton = item.highlightedButton {
                isActive = buttonKey == highlightedButton
            }
            
            buttonNode.update(
                size: buttonFrame.size,
                text: content.text,
                icon: content.icon,
                isActive: isActive,
                presentationData: presentationData,
                backgroundColor: buttonBackgroundColor,
                foregroundColor: presentationData.theme.list.itemPrimaryTextColor,
                fraction: 1.0,
                circularStyle: true,
                transition: wasAdded ? .immediate : transition
            )
            
            if wasAdded {
                buttonNode.alpha = 0.0
                transition.updateAlpha(node: buttonNode, alpha: 1.0)
            }
            
            leftOrigin += actionButtonDiameter + actionButtonSpacing
        }
        
        for key in self.buttonNodes.keys {
            if !item.buttonKeys.contains(key) {
                if let buttonNode = self.buttonNodes.removeValue(forKey: key) {
                    transition.updateAlpha(node: buttonNode, alpha: 0.0) { [weak buttonNode] _ in
                        buttonNode?.backgroundContainerView.removeFromSuperview()
                        buttonNode?.removeFromSupernode()
                    }
                }
            }
        }
        
        let hasRoundedCorners = hasCorners && (topItem == nil || bottomItem == nil)
        let hasTopCorners = hasRoundedCorners && topItem == nil
        let hasBottomCorners = hasRoundedCorners && bottomItem == nil
        self.maskNode.image = hasRoundedCorners ? PresentationResourcesItemList.cornersImage(presentationData.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil
        transition.updateFrame(node: self.maskNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: width, height: height)))
        
        return height
    }
}
