import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import CallScreen
import GlassBackgroundComponent
import AvatarNode
import TelegramUIPreferences
import AccountContext
import AnimatedCountLabelNode
import ComponentFlow
import ReactionSelectionNode

private let blue = UIColor(rgb: 0x007fff)
private let lightBlue = UIColor(rgb: 0x00affe)
private let green = UIColor(rgb: 0x33c659)
private let activeBlue = UIColor(rgb: 0x00a0b9)
private let purple = UIColor(rgb: 0x3252ef)
private let pink = UIColor(rgb: 0xef436c)
private let latePurple = UIColor(rgb: 0xaa56a6)
private let latePink = UIColor(rgb: 0xef476f)

private func textForTimeout(value: Int32) -> String {
    if value < 3600 {
        let minutes = value / 60
        let seconds = value % 60
        let secondsPadding = seconds < 10 ? "0" : ""
        return "\(minutes):\(secondsPadding)\(seconds)"
    } else {
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let minutesPadding = minutes < 10 ? "0" : ""
        let seconds = value % 60
        let secondsPadding = seconds < 10 ? "0" : ""
        return "\(hours):\(minutesPadding)\(minutes):\(secondsPadding)\(seconds)"
    }
}

private class CallStatusBarBackgroundNode: ASDisplayNode {
    enum State {
        case connecting
        case cantSpeak
        case late
        case active
        case speaking
    }
    private let wavesLayer: CallStatusBarWavesLayer
    private let initialTimestamp = CACurrentMediaTime()
    
    var audioLevel: Float = 0.0  {
        didSet {
            self.wavesLayer.updateAudioLevel(CGFloat(self.audioLevel))
            self.updateBreath()
        }
    }
    
    /// A soft light that rises from the bottom edge of the bar with the voice on the call, like the bar breathing in
    /// time with the conversation. It rises quickly and falls slowly so speech reads as swells, not flicker, and it only
    /// exists where the wave animations do (energy settings with full translucency).
    private let breathLayer = CAGradientLayer()
    private var smoothedLevel: Float = 0.0
    var breathingEnabled: Bool = false {
        didSet {
            if self.breathingEnabled != oldValue {
                if !self.breathingEnabled {
                    self.smoothedLevel = 0.0
                    self.breathLayer.opacity = 0.0
                }
            }
        }
    }
    
    private func updateBreath() {
        guard self.breathingEnabled else {
            return
        }
        let level = min(1.0, max(0.0, self.audioLevel))
        self.smoothedLevel = level > self.smoothedLevel ? self.smoothedLevel + (level - self.smoothedLevel) * 0.7 : self.smoothedLevel * 0.82
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        self.breathLayer.opacity = 0.06 + 0.64 * self.smoothedLevel
        CATransaction.commit()
    }
    
    private func updateBreathColors() {
        let glow = self.palette.statusBarHighlight
        self.breathLayer.colors = [glow.withAlphaComponent(0.0).cgColor, glow.withAlphaComponent(0.55).cgColor]
    }
    
    var connectingColor: UIColor = UIColor(rgb: 0xb6b6bb) {
        didSet {
            if self.connectingColor.rgb != oldValue.rgb {
                self.updateGradientColors()
            }
        }
    }
    
    var state: State = .connecting {
        didSet {
            if self.state != oldValue {
                self.updateGradientColors()
            }
        }
    }
    
    /// The theme's call colours: the connected and speaking bars follow the theme, like the call screen does.
    /// The "can't speak" and "late" gradients keep their fixed colours, which carry meaning.
    var palette: CallScreenPalette = .classicDay {
        didSet {
            if self.palette != oldValue {
                self.updateGradientColors()
                self.updateBreathColors()
            }
        }
    }
    
    var isDarkAppearance: Bool = false {
        didSet {
            self.wavesLayer.isDarkAppearance = self.isDarkAppearance
        }
    }
    
    private func updateGradientColors() {
        let targetColors: (UIColor, UIColor)
        switch self.state {
            case .connecting:
                targetColors = (self.connectingColor, self.connectingColor)
            case .active:
                targetColors = (self.palette.statusBarActive[0], self.palette.statusBarActive[1])
            case .speaking:
                targetColors = (self.palette.statusBarSpeaking[0], self.palette.statusBarSpeaking[1])
            case .cantSpeak:
                targetColors = (purple, pink)
            case .late:
                targetColors = (latePurple, latePink)
        }
        self.wavesLayer.updateColors(targetColors, animated: CACurrentMediaTime() - self.initialTimestamp > 0.1)
    }
    
    private let hierarchyTrackingNode: HierarchyTrackingNode
    
    var animationsEnabled: Bool = false {
        didSet {
            self.wavesLayer.isFlat = !self.animationsEnabled
        }
    }

    override init() {
        self.wavesLayer = CallStatusBarWavesLayer(colors: (blue, lightBlue))
        
        var updateInHierarchy: ((Bool) -> Void)?
        self.hierarchyTrackingNode = HierarchyTrackingNode({ value in
            updateInHierarchy?(value)
        })
        
        super.init()
        
        self.addSubnode(self.hierarchyTrackingNode)
        
        self.isOpaque = false
        
        updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                strongSelf.wavesLayer.isInWindow = value
            }
        }
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.layer.addSublayer(self.wavesLayer)
        self.breathLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.breathLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.breathLayer.opacity = 0.0
        self.updateBreathColors()
        self.view.layer.addSublayer(self.breathLayer)
    }
    
    override func layout() {
        super.layout()
        
        let wavesFrame = CGRect(origin: CGPoint(), size: CGSize(width: self.bounds.width, height: self.bounds.height + CallStatusBarWavesLayer.bottomOverflow))
        if self.wavesLayer.frame != wavesFrame {
            self.wavesLayer.frame = wavesFrame
            self.wavesLayer.update(barHeight: self.bounds.height)
            self.breathLayer.frame = self.bounds
        }
    }
}

public class CallStatusBarNodeImpl: CallStatusBarNode {
    public enum Content: Equatable {
        case call(SharedAccountContext, Account, PresentationCall)
        case groupCall(SharedAccountContext, Account, PresentationGroupCall)
        
        var sharedContext: SharedAccountContext {
            switch self {
            case let .call(sharedContext, _, _), let .groupCall(sharedContext, _, _):
                return sharedContext
            }
        }
        
        public static func ==(lhs: Content, rhs: Content) -> Bool {
            switch lhs {
            case let .call(sharedContext, account, call):
                if case let .call(rhsSharedContext, rhsAccount, rhsCall) = rhs, sharedContext === rhsSharedContext, account === rhsAccount, call === rhsCall {
                    return true
                } else {
                    return false
                }
            case let .groupCall(sharedContext, account, groupCall):
                if case let .groupCall(rhsSharedContext, rhsAccount, rhsGroupCall) = rhs, sharedContext === rhsSharedContext, account === rhsAccount, groupCall === rhsGroupCall {
                    return true
                } else {
                    return false
                }
            }
        }
    }
    
    private let backgroundNode: CallStatusBarBackgroundNode
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateAnimatedCountLabelNode
    private let speakerNode: ImmediateTextNode
    private var messageView: ComponentView<Empty>?
    
    /// The caller's avatar in the bar of a private call, ringed in the theme's highlight; the ring swells with their voice.
    private var avatarNode: AvatarNode?
    private let avatarRingLayer = CAShapeLayer()
    private var avatarPeerId: EnginePeer.Id?
    
    /// iOS 26 Liquid Glass capsule that holds the avatar, title and timer, tinted with the theme's call colour. The bar's
    /// gradient and waves stay behind it, so the glass refracts them.
    private let glassView = GlassBackgroundView()
    private static let avatarDiameter: CGFloat = 18.0
    private static let avatarSpacing: CGFloat = 6.0
    
    private let audioLevelDisposable = MetaDisposable()
    private let stateDisposable = MetaDisposable()
    private weak var didSetupDataForCall: AnyObject?
    
    private var currentSize: CGSize?
    private var currentContent: Content?
    
    private var presentationData: PresentationData?
    private let presentationDataDisposable = MetaDisposable()
    
    private var currentPeer: EnginePeer?
    private var currentCallTimer: SwiftSignalKit.Timer?
    private var currentCallState: PresentationCallState?
    private var currentGroupCallState: PresentationGroupCallSummaryState?
    private var currentIsMuted = true
    private var currentCantSpeak = false
    private var currentScheduleTimestamp: Int32?
    private var currentMembers: PresentationGroupCallMembers?
    private var currentIsConnected = true

    private var reactionItems: [ReactionItem]?
    private var messagesState: GroupCallMessagesContext.State?
    private let messagesStateDisposable = MetaDisposable()
    private var currentMessageId: GroupCallMessagesContext.Message.Id?
    
    private let hierarchyTrackingNode: HierarchyTrackingNode
    private var isCurrentlyInHierarchy = true
    
    public override init() {
        self.backgroundNode = CallStatusBarBackgroundNode()
        self.titleNode = ImmediateTextNode()
        self.subtitleNode = ImmediateAnimatedCountLabelNode()
        self.subtitleNode.reverseAnimationDirection = true
        self.speakerNode = ImmediateTextNode()

        var updateInHierarchy: ((Bool) -> Void)?
        self.hierarchyTrackingNode = HierarchyTrackingNode({ value in
            updateInHierarchy?(value)
        })
        
        super.init()

        self.addSubnode(self.hierarchyTrackingNode)
                
        self.addSubnode(self.backgroundNode)
        self.glassView.isUserInteractionEnabled = false
        self.view.insertSubview(self.glassView, aboveSubview: self.backgroundNode.view)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
        self.addSubnode(self.speakerNode)

        updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                strongSelf.isCurrentlyInHierarchy = value
                if value {
                    strongSelf.update()
                }
            }
        }
    }
    
    deinit {
        self.presentationDataDisposable.dispose()
        self.audioLevelDisposable.dispose()
        self.stateDisposable.dispose()
        self.messagesStateDisposable.dispose()
        self.currentCallTimer?.invalidate()
    }
    
    public func update(content: Content) {
        if self.currentContent != content {
            self.currentContent = content
            self.backgroundNode.animationsEnabled = content.sharedContext.energyUsageSettings.fullTranslucency
            if case .call = content {
                self.backgroundNode.breathingEnabled = content.sharedContext.energyUsageSettings.fullTranslucency
            } else {
                self.backgroundNode.breathingEnabled = false
            }
            if self.isCurrentlyInHierarchy {
                self.update()
            }
        }
    }
    
    public override var bottomOverhang: CGFloat {
        return CallStatusBarWavesLayer.bottomOverflow
    }
    
    public override func update(size: CGSize) {
        self.currentSize = size
        self.update()
    }

    private let callTextFont = Font.with(size: 13.0, design: .regular, weight: .regular, traits: [.monospacedNumbers])
    private let groupCallTextFont = Font.with(size: 13.0, design: .regular, weight: .regular, traits: [])
    
    /// Creates, updates or removes the caller's avatar and returns how much horizontal room it takes in front of the title
    /// (zero when there is none). Only a private call has one; a group call's title already names the chat.
    private func updateAvatar(verticalOrigin: CGFloat, contentHeight: CGFloat) -> CGFloat {
        guard case let .call(_, _, call)? = self.currentContent, let peer = self.currentPeer, let presentationData = self.presentationData else {
            if let avatarNode = self.avatarNode {
                self.avatarNode = nil
                self.avatarPeerId = nil
                avatarNode.removeFromSupernode()
                self.avatarRingLayer.removeFromSuperlayer()
            }
            return 0.0
        }
        let diameter = CallStatusBarNodeImpl.avatarDiameter
        let avatarNode: AvatarNode
        if let current = self.avatarNode {
            avatarNode = current
        } else {
            avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 8.0))
            avatarNode.isUserInteractionEnabled = false
            self.avatarNode = avatarNode
            self.avatarPeerId = nil
            self.addSubnode(avatarNode)
            self.avatarRingLayer.fillColor = UIColor.clear.cgColor
            self.avatarRingLayer.lineWidth = 1.5
            self.view.layer.addSublayer(self.avatarRingLayer)
        }
        if self.avatarPeerId != peer.id {
            self.avatarPeerId = peer.id
            avatarNode.setPeer(context: call.context, theme: presentationData.theme, peer: peer, displayDimensions: CGSize(width: diameter, height: diameter))
        }
        self.avatarRingLayer.strokeColor = CallScreenPalette(theme: presentationData.theme).statusBarHighlight.cgColor
        return diameter + CallStatusBarNodeImpl.avatarSpacing
    }
    
    private func layoutAvatar(originX: CGFloat, verticalOrigin: CGFloat, contentHeight: CGFloat) {
        guard let avatarNode = self.avatarNode else {
            return
        }
        let diameter = CallStatusBarNodeImpl.avatarDiameter
        let frame = CGRect(x: originX, y: verticalOrigin + floor((contentHeight - diameter) / 2.0), width: diameter, height: diameter)
        avatarNode.frame = frame
        // The ring sits just outside the avatar, a point clear of it.
        let ringFrame = frame.insetBy(dx: -2.5, dy: -2.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // bounds + position, not `frame`: the ring carries a scale transform while the voice swells it.
        self.avatarRingLayer.bounds = CGRect(origin: CGPoint(), size: ringFrame.size)
        self.avatarRingLayer.position = CGPoint(x: ringFrame.midX, y: ringFrame.midY)
        self.avatarRingLayer.path = UIBezierPath(ovalIn: CGRect(origin: CGPoint(), size: ringFrame.size).insetBy(dx: 0.75, dy: 0.75)).cgPath
        CATransaction.commit()
    }
    
    /// The ring brightens and swells a little with the caller's voice. Cheap: two layer properties, no layout.
    private func updateAvatarRing(level: Float) {
        guard self.avatarNode != nil, self.backgroundNode.breathingEnabled else {
            return
        }
        let value = CGFloat(min(1.0, max(0.0, level)))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        self.avatarRingLayer.opacity = Float(0.45 + 0.55 * value)
        self.avatarRingLayer.transform = CATransform3DMakeScale(1.0 + 0.12 * value, 1.0 + 0.12 * value, 1.0)
        CATransaction.commit()
    }
    
    /// Liquid Glass capsule around the avatar, title and timer. It is a little wider than the cluster (tighter on the
    /// avatar side, where the ring already adds room) and is hidden while a group-call message replaces the title.
    private func layoutGlass(size: CGSize, verticalOrigin: CGFloat, contentHeight: CGFloat, clusterWidth: CGFloat, hasAvatar: Bool, isHidden: Bool) {
        let height: CGFloat = 26.0
        let horizontalPadding: CGFloat = hasAvatar ? 8.0 : 12.0
        let width = min(size.width - 16.0, clusterWidth + horizontalPadding * 2.0)
        let frame = CGRect(x: floor((size.width - width) / 2.0), y: verticalOrigin + floor((contentHeight - height) / 2.0), width: width, height: height)
        let palette = self.presentationData.flatMap { CallScreenPalette(theme: $0.theme) } ?? .classicDay
        self.glassView.frame = frame
        self.glassView.update(size: frame.size, cornerRadius: height / 2.0, isDark: true, tintColor: GlassBackgroundView.TintColor(kind: .custom(style: .default, color: palette.statusBarActive[0].withAlphaComponent(0.32))), transition: .immediate)
        ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateAlpha(layer: self.glassView.layer, alpha: isHidden ? 0.0 : 1.0)
    }
    
    private func update() {
        guard let size = self.currentSize, let content = self.currentContent else {
            return
        }
        
        let wasEmpty = (self.titleNode.attributedText?.string ?? "").isEmpty
        
        let textFont: UIFont
        let setupDataForCall: AnyObject?
        switch content {
        case let .call(_, _, call):
            setupDataForCall = call
            textFont = callTextFont
        case let .groupCall(_, _, call):
            setupDataForCall = call
            textFont = groupCallTextFont
        }
        
        if self.didSetupDataForCall !== setupDataForCall {
            self.didSetupDataForCall = setupDataForCall
            switch content {
                case let .call(sharedContext, account, call):
                    // The node is reused when a group call is followed by a 1:1 call; nothing of the group call may
                    // show while the new call's state is on its way (its peer may never arrive if it is not stored).
                    self.currentPeer = nil
                    self.currentCallState = nil
                    self.currentIsMuted = true
                    self.currentIsConnected = false
                    self.currentGroupCallState = nil
                    self.currentMembers = nil
                    self.currentCantSpeak = false
                    self.currentScheduleTimestamp = nil
                    self.messagesStateDisposable.set(nil)
                    self.messagesState = nil
                    self.backgroundNode.audioLevel = 0.0
                    
                    self.presentationData = sharedContext.currentPresentationData.with { $0 }
                    self.presentationDataDisposable.set((sharedContext.presentationData
                    |> deliverOnMainQueue).start(next: { [weak self] presentationData in
                        if let strongSelf = self, strongSelf.presentationData !== presentationData {
                            strongSelf.presentationData = presentationData
                            strongSelf.update()
                        }
                    }))
                    let callPeer = TelegramEngine(account: account).data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: call.peerId))
                    |> mapToSignal { peer -> Signal<EnginePeer, NoError> in
                        if let peer {
                            return .single(peer)
                        } else {
                            return .never()
                        }
                    }
                    self.stateDisposable.set(
                        (combineLatest(
                            callPeer,
                            call.state,
                            call.isMuted
                        )
                    |> deliverOnMainQueue).start(next: { [weak self] peer, state, isMuted in
                        if let strongSelf = self {
                            strongSelf.currentPeer = peer
                            strongSelf.currentCallState = state
                            strongSelf.currentIsMuted = isMuted
                            
                            let currentIsConnected: Bool
                            switch state.state {
                                case .active, .terminating, .terminated:
                                    currentIsConnected = true
                                default:
                                    currentIsConnected = false
                            }
                        
                            strongSelf.currentIsConnected = currentIsConnected
                            
                            strongSelf.update()
                        }
                    }))
                    self.audioLevelDisposable.set((call.audioLevel
                    |> deliverOnMainQueue).start(next: { [weak self] audioLevel in
                        guard let strongSelf = self else {
                            return
                        }
                        strongSelf.backgroundNode.audioLevel = audioLevel
                        strongSelf.updateAvatarRing(level: audioLevel)
                    }))
                case let .groupCall(sharedContext, account, call):
                    self.presentationData = sharedContext.currentPresentationData.with { $0 }
                    self.presentationDataDisposable.set((sharedContext.presentationData
                    |> deliverOnMainQueue).start(next: { [weak self] presentationData in
                        if let strongSelf = self, strongSelf.presentationData !== presentationData {
                            strongSelf.presentationData = presentationData
                            strongSelf.update()
                        }
                    }))
                    let callPeerView: Signal<EnginePeer?, NoError>
                    if let peerId = call.peerId {
                        callPeerView = TelegramEngine(account: account).data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                    } else {
                        callPeerView = .single(nil)
                    }
                    self.stateDisposable.set(
                        (combineLatest(
                            callPeerView,
                            call.summaryState,
                            call.isMuted,
                            call.members
                        )
                    |> deliverOnMainQueue).start(next: { [weak self] view, state, isMuted, members in
                        if let strongSelf = self {
                            if let view {
                                strongSelf.currentPeer = view
                            } else {
                                strongSelf.currentPeer = nil
                            }
                            strongSelf.currentGroupCallState = state
                            strongSelf.currentMembers = members
                                
                            var isMuted = isMuted
                            var cantSpeak = false
                            if let state = state, let muteState = state.callState.muteState {
                                if !muteState.canUnmute {
                                    isMuted = true
                                    cantSpeak = true
                                }
                            }
                            if state?.callState.scheduleTimestamp != nil {
                                cantSpeak = true
                            }
                            strongSelf.currentIsMuted = isMuted
                            strongSelf.currentCantSpeak = cantSpeak
                            strongSelf.currentScheduleTimestamp = state?.callState.scheduleTimestamp
                            
                            let currentIsConnected: Bool
                            if let state = state, case .connected = state.callState.networkState {
                                currentIsConnected = true
                            } else if state?.callState.scheduleTimestamp != nil {
                                currentIsConnected = true
                            } else {
                                currentIsConnected = false
                            }
                            strongSelf.currentIsConnected = currentIsConnected

                            if strongSelf.isCurrentlyInHierarchy {
                                strongSelf.update()
                            }
                        }
                    }))
                    self.audioLevelDisposable.set((combineLatest(call.myAudioLevel, .single([]) |> then(call.audioLevels))
                    |> deliverOnMainQueue).start(next: { [weak self] myAudioLevel, audioLevels in
                        guard let strongSelf = self else {
                            return
                        }
                        var effectiveLevel: Float = 0.0
                        var audioLevels = audioLevels
                        if !strongSelf.currentIsMuted {
                            audioLevels.append((EnginePeer.Id(0), 0, myAudioLevel, true))
                        }
                        effectiveLevel = audioLevels.map { $0.2 }.max() ?? 0.0
                        strongSelf.backgroundNode.audioLevel = effectiveLevel
                    }))
                
                    if let groupCall = call as? PresentationGroupCallImpl {
                        let _ = (allowedStoryReactions(engine: TelegramEngine(account: account))
                        |> deliverOnMainQueue).start(next: { [weak self] reactionItems in
                            self?.reactionItems = reactionItems
                        })
                        
                        self.messagesStateDisposable.set((groupCall.messagesState
                        |> deliverOnMainQueue).start(next: { [weak self] messagesState in
                            guard let self else {
                                return
                            }
                            if self.messagesState != messagesState {
                                self.messagesState = messagesState
                                
                                if self.isCurrentlyInHierarchy {
                                    self.update()
                                }
                            }
                        }))
                    }
            }
        }
        
        var title: String = ""
        var speakerSubtitle: String = ""

        let textColor = UIColor.white
        var segments: [AnimatedCountLabelNode.Segment] = []
        var displaySpeakerSubtitle = false
        var isLate = false
        
        if let presentationData = self.presentationData {
            if let voiceChatTitle = self.currentGroupCallState?.info?.title, !voiceChatTitle.isEmpty {
                title = voiceChatTitle
            } else if let currentPeer = self.currentPeer {
                title = currentPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            }
            var membersCount: Int32?
            if let groupCallState = self.currentGroupCallState {
                membersCount = Int32(max(1, groupCallState.participantCount))
            } else if let content = self.currentContent, case .groupCall = content {
                membersCount = 1
            }
            
            var speakingPeer: EnginePeer?
            if let members = currentMembers {
                var speakingPeers: [EnginePeer] = []
                for member in members.participants {
                    if let memberPeer = member.peer, members.speakingParticipants.contains(memberPeer.id) {
                        speakingPeers.append(memberPeer)
                    }
                }
                speakingPeer = speakingPeers.first
            }

            if let speakingPeer = speakingPeer {
                speakerSubtitle = speakingPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            }
            displaySpeakerSubtitle = speakerSubtitle != title && !speakerSubtitle.isEmpty
            
            var requiresTimer = false
            if let scheduleTime = self.currentGroupCallState?.info?.scheduleTimestamp {
                requiresTimer = true
                
                let currentTime = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                let elapsedTime = scheduleTime - currentTime
                let timerText: String
                if elapsedTime >= 86400 {
                    timerText = presentationData.strings.VoiceChat_StatusStartsIn(scheduledTimeIntervalString(strings: presentationData.strings, value: elapsedTime)).string
                } else if elapsedTime < 0 {
                    isLate = true
                    timerText = presentationData.strings.VoiceChat_StatusLateBy(textForTimeout(value: abs(elapsedTime))).string
                } else {
                    timerText = presentationData.strings.VoiceChat_StatusStartsIn(textForTimeout(value: elapsedTime)).string
                }
                segments.append(.text(0, NSAttributedString(string: timerText, font: textFont, textColor: textColor)))
            } else if let membersCount = membersCount {
                var membersPart = presentationData.strings.VoiceChat_Status_Members(membersCount)
                if membersPart.contains("[") && membersPart.contains("]") {
                    if let startIndex = membersPart.firstIndex(of: "["), let endIndex = membersPart.firstIndex(of: "]") {
                        membersPart.removeSubrange(startIndex ... endIndex)
                    }
                } else {
                    membersPart = membersPart.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789-,."))
                }
                
                let rawTextAndRanges = presentationData.strings.VoiceChat_Status_MembersFormat("\(membersCount)", membersPart)

                var textIndex = 0
                var latestIndex = 0
                for rangeItem in rawTextAndRanges.ranges {
                    let index = rangeItem.index
                    let range = rangeItem.range
                    var lowerSegmentIndex = range.lowerBound
                    if index != 0 {
                        lowerSegmentIndex = min(lowerSegmentIndex, latestIndex)
                    } else {
                        if latestIndex < range.lowerBound {
                            let part = String(rawTextAndRanges.string[rawTextAndRanges.string.index(rawTextAndRanges.string.startIndex, offsetBy: latestIndex) ..< rawTextAndRanges.string.index(rawTextAndRanges.string.startIndex, offsetBy: range.lowerBound)])
                            segments.append(.text(textIndex, NSAttributedString(string: part, font: textFont, textColor: textColor)))
                            textIndex += 1
                        }
                    }
                    latestIndex = range.upperBound
                    
                    let part = String(rawTextAndRanges.string[rawTextAndRanges.string.index(rawTextAndRanges.string.startIndex, offsetBy: lowerSegmentIndex) ..< rawTextAndRanges.string.index(rawTextAndRanges.string.startIndex, offsetBy: range.upperBound)])
                    if index == 0 {
                        segments.append(.number(Int(membersCount), NSAttributedString(string: part, font: textFont, textColor: textColor)))
                    } else {
                        segments.append(.text(textIndex, NSAttributedString(string: part, font: textFont, textColor: textColor)))
                        textIndex += 1
                    }
                }
                if latestIndex < rawTextAndRanges.string.count {
                    let part = String(rawTextAndRanges.string[rawTextAndRanges.string.index(rawTextAndRanges.string.startIndex, offsetBy: latestIndex)...])
                    segments.append(.text(textIndex, NSAttributedString(string: part, font: textFont, textColor: textColor)))
                    textIndex += 1
                }
            }
            
            let sourceColor = presentationData.theme.chatList.unreadBadgeInactiveBackgroundColor
            let color: UIColor
            if sourceColor.alpha < 1.0 {
                color = presentationData.theme.chatList.unreadBadgeInactiveBackgroundColor.mixedWith(sourceColor.withAlphaComponent(1.0), alpha: sourceColor.alpha)
            } else {
                color = sourceColor
            }
            
            self.backgroundNode.connectingColor = color
            self.backgroundNode.palette = CallScreenPalette(theme: presentationData.theme)
            self.backgroundNode.isDarkAppearance = presentationData.theme.overallDarkAppearance
            
            if requiresTimer {
                if self.currentCallTimer == nil {
                    let timer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                        self?.update()
                    }, queue: Queue.mainQueue())
                    timer.start()
                    self.currentCallTimer = timer
                }
            } else if let currentCallTimer = self.currentCallTimer {
                self.currentCallTimer = nil
                currentCallTimer.invalidate()
            }
        }
        
        if self.subtitleNode.segments != segments && !displaySpeakerSubtitle {
            self.subtitleNode.segments = segments
        }
        
        let contentHeight: CGFloat = 24.0
        let verticalOrigin: CGFloat = size.height - contentHeight
        
        var isDisplayingMessage = false
        let componentTransition: ComponentTransition = .easeInOut(duration: 0.25)
        if case let .groupCall(_, account, call) = self.currentContent, let message = self.messagesState?.messages.last(where: { $0.author?.id != account.peerId }), let author = message.author, let groupCall = call as? PresentationGroupCallImpl {
            if self.currentMessageId != message.id {
                self.currentMessageId = message.id
                
                if let messageView = self.messageView?.view {
                    self.messageView = nil
                    componentTransition.setAlpha(view: messageView, alpha: 0.0, completion: { _ in
                        messageView.removeFromSuperview()
                    })
                }
            }
            let messageView: ComponentView<Empty>
            if let current = self.messageView {
                messageView = current
            } else {
                messageView = ComponentView<Empty>()
                self.messageView = messageView
            }
            
            let messageSize = messageView.update(
                transition: .immediate,
                component: AnyComponent(
                    MessageItemComponent(
                        context: groupCall.accountContext,
                        icon: .peer(author),
                        style: .status,
                        text: message.text,
                        entities: message.entities,
                        availableReactions: self.reactionItems,
                        openPeer: nil
                    )
                ),
                environment: {},
                containerSize: CGSize(width: size.width - 140.0, height: contentHeight)
            )
            if let view = messageView.view {
                if view.superview == nil {
                    view.transform = CGAffineTransformMakeScale(1.0, -1.0)
                    self.view.addSubview(view)
                    componentTransition.animateAlpha(view: view, from: 0.0, to: 1.0)
                }
                view.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - messageSize.width) / 2.0), y: verticalOrigin + floor((contentHeight - messageSize.height) / 2.0) + 1.0), size: messageSize)
            }
            isDisplayingMessage = true
        } else if let messageView = self.messageView?.view {
            self.messageView = nil
            componentTransition.setAlpha(view: messageView, alpha: 0.0, completion: { _ in
                messageView.removeFromSuperview()
            })
        }
        
        let alphaTransition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .easeInOut)
        alphaTransition.updateAlpha(node: self.titleNode, alpha: isDisplayingMessage ? 0.0 : 1.0)
        alphaTransition.updateAlpha(node: self.subtitleNode, alpha: displaySpeakerSubtitle || isDisplayingMessage ? 0.0 : 1.0)
        alphaTransition.updateAlpha(node: self.speakerNode, alpha: displaySpeakerSubtitle && !isDisplayingMessage ? 1.0 : 0.0)
        
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.semibold(13.0), textColor: .white)
        
        if displaySpeakerSubtitle {
            self.speakerNode.attributedText = NSAttributedString(string: speakerSubtitle, font: Font.regular(13.0), textColor: .white)
        }
        
        let spacing: CGFloat = 5.0
        let titleSize = self.titleNode.updateLayout(CGSize(width: 150.0, height: size.height))
        let subtitleSize = self.subtitleNode.updateLayout(size: CGSize(width: 150.0, height: size.height), animated: true)
        let speakerSize = self.speakerNode.updateLayout(CGSize(width: 150.0, height: size.height))
        
        let avatarOffset = self.updateAvatar(verticalOrigin: verticalOrigin, contentHeight: contentHeight)
        
        var totalWidth = titleSize.width
        if totalWidth > 0.0 {
            totalWidth += spacing
        }
        totalWidth += subtitleSize.width
        totalWidth += avatarOffset
        let horizontalOrigin: CGFloat = floor((size.width - totalWidth) / 2.0)
        self.layoutAvatar(originX: horizontalOrigin, verticalOrigin: verticalOrigin, contentHeight: contentHeight)
        let titleOriginX = horizontalOrigin + avatarOffset
        
        self.layoutGlass(size: size, verticalOrigin: verticalOrigin, contentHeight: contentHeight, clusterWidth: totalWidth, hasAvatar: avatarOffset > 0.0, isHidden: isDisplayingMessage)
        
        let sizeChanged = self.titleNode.frame.size.width != titleSize.width
        
        let transition: ContainedViewLayoutTransition = wasEmpty || sizeChanged ? .immediate : .animated(duration: 0.2, curve: .easeInOut)
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: titleOriginX, y: verticalOrigin + floor((contentHeight - titleSize.height) / 2.0)), size: titleSize))
        transition.updateFrame(node: self.subtitleNode, frame: CGRect(origin: CGPoint(x: titleOriginX + titleSize.width + spacing, y: verticalOrigin + floor((contentHeight - subtitleSize.height) / 2.0)), size: subtitleSize))
        
        if displaySpeakerSubtitle {
            let speakerOriginX: CGFloat = title.isEmpty ? floor((size.width - speakerSize.width) / 2.0) : horizontalOrigin + titleSize.width + spacing
            self.speakerNode.frame = CGRect(origin: CGPoint(x: speakerOriginX, y: verticalOrigin + floor((contentHeight - speakerSize.height) / 2.0)), size: speakerSize)
        }
        
        let state: CallStatusBarBackgroundNode.State
        if self.currentIsConnected {
            if self.currentCantSpeak {
                state = isLate ? .late : .cantSpeak
            } else if self.currentIsMuted {
                state = .active
            } else {
                state = .speaking
            }
        } else {
            state = .connecting
        }
        self.backgroundNode.state = state
        self.backgroundNode.frame = CGRect(origin: CGPoint(), size: size)
    }
}
