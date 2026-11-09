import Foundation
import UIKit
import AsyncDisplayKit
import TelegramCore
import Display
import SwiftSignalKit
import TelegramPresentationData
import ChatTitleActivityNode
import LocalizedPeerData

/// The Messages look: when the other side of a one-to-one chat types, the row shows a small grey bubble with
/// three bouncing dots instead of the word "typing". Groups keep the text, which says who types.
private final class ChatListTypingBubbleNode: ASDisplayNode {
    static let size = CGSize(width: 38.0, height: 20.0)

    private let backgroundNode: ASImageNode
    private var dots: [CALayer] = []
    private var currentFill: UIColor?

    override init() {
        self.backgroundNode = ASImageNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.displaysAsynchronously = false
        super.init()
        self.addSubnode(self.backgroundNode)
        for _ in 0 ..< 3 {
            let dot = CALayer()
            dot.cornerRadius = 2.75
            self.layer.addSublayer(dot)
            self.dots.append(dot)
        }
    }

    func update(fill: UIColor, dotColor: UIColor) {
        if self.currentFill != fill {
            self.currentFill = fill
            self.backgroundNode.image = generateStretchableFilledCircleImage(diameter: ChatListTypingBubbleNode.size.height, color: fill)
        }
        let size = ChatListTypingBubbleNode.size
        self.backgroundNode.frame = CGRect(origin: CGPoint(), size: size)
        let dotSize: CGFloat = 5.5
        let spacing: CGFloat = 3.5
        var x = floor((size.width - dotSize * 3.0 - spacing * 2.0) / 2.0)
        for dot in self.dots {
            dot.backgroundColor = dotColor.cgColor
            dot.frame = CGRect(x: x, y: floor((size.height - dotSize) / 2.0), width: dotSize, height: dotSize)
            x += dotSize + spacing
        }
        self.startAnimating()
    }

    private func startAnimating() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        for (index, dot) in self.dots.enumerated() where dot.animation(forKey: "typing") == nil {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0.35, 1.0, 0.35, 0.35]
            animation.keyTimes = [0.0, 0.25, 0.5, 1.0]
            animation.duration = 1.2
            animation.repeatCount = .infinity
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            animation.fillMode = .backwards
            animation.isRemovedOnCompletion = false
            dot.add(animation, forKey: "typing")
        }
    }

    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        if !self.isHidden {
            self.startAnimating()
        }
    }
}

final class ChatListInputActivitiesNode: ASDisplayNode {
    private let activityNode: ChatTitleActivityNode
    private let typingBubbleNode: ChatListTypingBubbleNode
    
    override init() {
        self.activityNode = ChatTitleActivityNode()
        self.typingBubbleNode = ChatListTypingBubbleNode()
        self.typingBubbleNode.isHidden = true
        
        super.init()
        
        self.addSubnode(self.activityNode)
        self.addSubnode(self.typingBubbleNode)
    }
    
    func asyncLayout() -> (CGSize, ChatListPresentationData, UIColor, EnginePeer.Id?, [(EnginePeer, PeerInputActivity)]) -> (CGSize, () -> Void) {
        return { [weak self] boundingSize, presentationData, color, peerId, activities in
            let strings = presentationData.strings
            
            let textFont = Font.regular(15.0)
            
            var state = ChatTitleActivityNodeState.none
            // Messages look: the other side of a one-to-one chat typing is the dots bubble, not the word.
            var showsTypingBubble = false
            if activities.count == 1, activities[0].0.id == peerId, case .typingText = activities[0].1 {
                showsTypingBubble = true
            }
            
            if !activities.isEmpty && !showsTypingBubble {
                var commonKey: Int32? = activities[0].1.key
                for i in 1 ..< activities.count {
                    if activities[i].1.key != commonKey {
                        commonKey = nil
                        break
                    }
                }
                
                let lightColor = color.withAlphaComponent(0.85)
                
                if activities.count == 1 {
                    if activities[0].0.id == peerId {
                        let text: String
                        switch activities[0].1 {
                            case .uploadingVideo:
                                text = strings.Activity_UploadingVideo
                            case .uploadingInstantVideo:
                                text = strings.Activity_UploadingVideoMessage
                            case .uploadingPhoto:
                                text = strings.Activity_UploadingPhoto
                            case .uploadingFile:
                                text = strings.Activity_UploadingDocument
                            case .recordingVoice:
                                text = strings.Activity_RecordingAudio
                            case .recordingInstantVideo:
                                text = strings.Activity_RecordingVideoMessage
                            case .playingGame:
                                text = strings.Activity_PlayingGame
                            case .typingText:
                                text = strings.DialogList_Typing
                            case .choosingSticker:
                                text = strings.Activity_ChoosingSticker
                            case let .interactingWithEmoji(emoticon, _, _):
                                text = strings.Activity_TappingInteractiveEmoji(emoticon).string
                            case .speakingInGroupCall, .seeingEmojiInteraction:
                                text = ""
                        }
                        let string = NSAttributedString(string: text, font: textFont, textColor: color)
                        
                        switch activities[0].1 {
                            case .typingText:
                                state = .typingText(string, lightColor)
                            case .recordingVoice:
                                state = .recordingVoice(string, lightColor)
                            case .recordingInstantVideo:
                                state = .recordingVideo(string, lightColor)
                            case .uploadingFile, .uploadingInstantVideo, .uploadingPhoto, .uploadingVideo:
                                state = .uploading(string, lightColor)
                            case .playingGame:
                                state = .playingGame(string, lightColor)
                            case .speakingInGroupCall:
                                state = .typingText(string, lightColor)
                            case .choosingSticker:
                                state = .choosingSticker(string, lightColor)
                            case .interactingWithEmoji:
                                state = .interactingWithEmoji(string, lightColor)
                            case .seeingEmojiInteraction:
                                state = .none
                        }
                    } else {
                        let text: String
                        if let _ = commonKey {
                            let peerTitle = activities[0].0.compactDisplayTitle
                            switch activities[0].1 {
                                case .uploadingVideo:
                                    text = strings.DialogList_SingleUploadingVideoSuffix(peerTitle).string
                                case .uploadingInstantVideo:
                                    text = strings.DialogList_SingleUploadingVideoSuffix(peerTitle).string
                                case .uploadingPhoto:
                                    text = strings.DialogList_SingleUploadingPhotoSuffix(peerTitle).string
                                case .uploadingFile:
                                    text = strings.DialogList_SingleUploadingFileSuffix(peerTitle).string
                                case .recordingVoice:
                                    text = strings.DialogList_SingleRecordingAudioSuffix(peerTitle).string
                                case .recordingInstantVideo:
                                    text = strings.DialogList_SingleRecordingVideoMessageSuffix(peerTitle).string
                                case .playingGame:
                                    text = strings.DialogList_SinglePlayingGameSuffix(peerTitle).string
                                case .typingText:
                                    text = strings.DialogList_SingleTypingSuffix(peerTitle).string
                                case .choosingSticker:
                                    text = strings.DialogList_SingleChoosingStickerSuffix(peerTitle).string
                                case .speakingInGroupCall, .seeingEmojiInteraction, .interactingWithEmoji:
                                    text = ""
                            }
                        } else {
                            text = activities[0].0.compactDisplayTitle
                        }
                        let string = NSAttributedString(string: text, font: textFont, textColor: color)
                        
                        switch activities[0].1 {
                            case .typingText:
                                state = .typingText(string, lightColor)
                            case .recordingVoice:
                                state = .recordingVoice(string, lightColor)
                            case .recordingInstantVideo:
                                state = .recordingVideo(string, lightColor)
                            case .uploadingFile, .uploadingInstantVideo, .uploadingPhoto, .uploadingVideo:
                                state = .uploading(string, lightColor)
                            case .playingGame:
                                state = .playingGame(string, lightColor)
                            case .speakingInGroupCall:
                                state = .typingText(string, lightColor)
                            case .choosingSticker:
                                state = .choosingSticker(string, lightColor)
                            case .seeingEmojiInteraction, .interactingWithEmoji:
                                state = .none
                        }
                    }
                } else {
                    let string: NSAttributedString
                    if activities.count > 1 {
                        let peerTitle = activities[0].0.compactDisplayTitle
                        if activities.count == 2 {
                            let secondPeerTitle = activities[1].0.compactDisplayTitle
                            string = NSAttributedString(string: strings.DialogList_MultipleTypingPair(peerTitle, secondPeerTitle).string, font: textFont, textColor: color)
                        } else {
                            string = NSAttributedString(string: strings.DialogList_MultipleTyping(peerTitle, strings.DialogList_MultipleTypingSuffix(activities.count - 1).string).string, font: textFont, textColor: color)
                        }
                    } else {
                        string = NSAttributedString(string: strings.DialogList_MultipleTypingSuffix(activities.count).string, font: textFont, textColor: color)
                    }
                    state = .typingText(string, lightColor)
                }
            }
            
            let bubbleFill = presentationData.theme.chat.message.incoming.bubble.withoutWallpaper.fill.first ?? presentationData.theme.list.itemBlocksSeparatorColor
            let dotColor = presentationData.theme.chat.message.incoming.secondaryTextColor
            return (boundingSize, {
                if let strongSelf = self {
                    let _ = strongSelf.activityNode.transitionToState(state, animation: .none)
                    let size = strongSelf.activityNode.updateLayout(CGSize(width: boundingSize.width - 12.0, height: boundingSize.height), alignment: .left)
                    strongSelf.activityNode.frame = CGRect(origin: CGPoint(x: -3.0, y: 1.0), size: size)
                    strongSelf.typingBubbleNode.isHidden = !showsTypingBubble
                    if showsTypingBubble {
                        strongSelf.typingBubbleNode.update(fill: bubbleFill, dotColor: dotColor)
                        strongSelf.typingBubbleNode.frame = CGRect(origin: CGPoint(x: 0.0, y: 2.0), size: ChatListTypingBubbleNode.size)
                    }
                }
            })
        }
    }
}
