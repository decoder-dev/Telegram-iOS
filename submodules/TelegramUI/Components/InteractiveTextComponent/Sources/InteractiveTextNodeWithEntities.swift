import Foundation
import UIKit
import AsyncDisplayKit
import Display
import CoreText
import AppBundle
import ComponentFlow
import TextFormat
import AccountContext
import AnimationCache
import MultiAnimationRenderer
import TelegramCore
import EmojiTextAttachmentView
import AvatarNode
import SwiftSignalKit

private final class InlineStickerItem: Hashable {
    let emoji: ChatTextInputTextCustomEmojiAttribute
    let file: TelegramMediaFile?
    let fontSize: CGFloat
    
    init(emoji: ChatTextInputTextCustomEmojiAttribute, file: TelegramMediaFile?, fontSize: CGFloat) {
        self.emoji = emoji
        self.file = file
        self.fontSize = fontSize
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(emoji.fileId)
        hasher.combine(self.fontSize)
    }
    
    static func ==(lhs: InlineStickerItem, rhs: InlineStickerItem) -> Bool {
        if lhs.emoji.fileId != rhs.emoji.fileId {
            return false
        }
        if lhs.file?.fileId != rhs.file?.fileId {
            return false
        }
        if lhs.fontSize != rhs.fontSize {
            return false
        }
        return true
    }
}

private final class RunDelegateData {
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat
    
    init(ascent: CGFloat, descent: CGFloat, width: CGFloat) {
        self.ascent = ascent
        self.descent = descent
        self.width = width
    }
}

private final class MentionAvatarItem: Hashable {
    let peer: EnginePeer?
    let username: String?
    let glyph: NSAttributedString
    let font: UIFont
    let avatarSize: CGFloat
    let width: CGFloat

    init(peer: EnginePeer?, username: String?, glyph: NSAttributedString, font: UIFont) {
        self.peer = peer
        self.username = username
        self.glyph = glyph
        self.font = font
        self.avatarSize = ceil(font.pointSize)
        self.width = self.avatarSize + 3.0 + ceil(glyph.size().width)
    }

    static func == (lhs: MentionAvatarItem, rhs: MentionAvatarItem) -> Bool {
        return lhs.peer == rhs.peer && lhs.username == rhs.username && lhs.glyph.isEqual(to: rhs.glyph) && lhs.font == rhs.font
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.peer?.id)
        hasher.combine(self.username)
        hasher.combine(self.glyph.string)
        hasher.combine(self.font.fontName)
        hasher.combine(self.font.pointSize)
    }
}

/// Reserves room for an avatar without changing the text or any UTF-16 entity offsets.
public func textWithMentionAvatars(_ text: NSAttributedString, entities: [MessageTextEntity], peers: [EnginePeer]) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: text)
    let string = text.string as NSString
    let excludedRanges = entities.compactMap { entity -> NSRange? in
        switch entity.type {
        case .Spoiler, .Code, .Pre:
            return NSRange(location: entity.range.lowerBound, length: entity.range.count)
        default:
            return nil
        }
    }
    var count = 0
    for entity in entities {
        guard count < 40, !entity.range.isEmpty, entity.range.lowerBound >= 0, entity.range.upperBound <= string.length else {
            continue
        }
        let mentionRange = NSRange(location: entity.range.lowerBound, length: entity.range.count)
        guard !excludedRanges.contains(where: { NSIntersectionRange($0, mentionRange).length > 0 }) else {
            continue
        }
        let peer: EnginePeer?
        let username: String?
        switch entity.type {
        case let .TextMention(peerId):
            peer = peers.first(where: { $0.id == peerId })
            username = nil
            guard peer != nil else { continue }
        case .Mention:
            let mention = string.substring(with: mentionRange)
            guard mention.hasPrefix("@") else { continue }
            let name = String(mention.dropFirst())
            guard !name.isEmpty else { continue }
            username = name
            peer = peers.first(where: { peer in
                peer.addressName?.lowercased() == name.lowercased() || peer.usernames.contains(where: { $0.flags.contains(.isActive) && $0.username.lowercased() == name.lowercased() })
            })
        default:
            continue
        }
        let range = string.rangeOfComposedCharacterSequence(at: mentionRange.location)
        guard NSMaxRange(range) <= NSMaxRange(mentionRange), result.attribute(NSAttributedString.Key("Attribute__EmbeddedItem"), at: range.location, effectiveRange: nil) == nil, result.attribute(ChatTextInputAttributes.customEmoji, at: range.location, effectiveRange: nil) == nil, let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont else {
            continue
        }
        let item = MentionAvatarItem(peer: peer, username: username, glyph: result.attributedSubstring(from: range), font: font)
        let metrics = RunDelegateData(ascent: max(font.ascender, item.avatarSize + font.descender), descent: -font.descender, width: item.width)
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateCurrentVersion, dealloc: { pointer in
            Unmanaged<RunDelegateData>.fromOpaque(pointer).release()
        }, getAscent: { pointer in
            return Unmanaged<RunDelegateData>.fromOpaque(pointer).takeUnretainedValue().ascent
        }, getDescent: { pointer in
            return Unmanaged<RunDelegateData>.fromOpaque(pointer).takeUnretainedValue().descent
        }, getWidth: { pointer in
            return Unmanaged<RunDelegateData>.fromOpaque(pointer).takeUnretainedValue().width
        })
        let retainedMetrics = Unmanaged.passRetained(metrics)
        if let delegate = CTRunDelegateCreate(&callbacks, retainedMetrics.toOpaque()) {
            result.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: delegate, range: range)
            result.addAttribute(NSAttributedString.Key("Attribute__EmbeddedItem"), value: AnyHashable(item), range: range)
            count += 1
        } else {
            retainedMetrics.release()
        }
    }
    return result
}

private final class MentionAvatarView: UIView {
    private static var resolvedPeers: [String: EnginePeer] = [:]
    private let avatarNode: AvatarNode
    private let label = UILabel()
    private let disposable = MetaDisposable()
    private let item: MentionAvatarItem

    init(context: AccountContext, item: MentionAvatarItem, synchronousLoad: Bool) {
        self.item = item
        self.avatarNode = AvatarNode(font: Font.regular(max(8.0, item.avatarSize * 0.5)))
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false
        self.label.attributedText = item.glyph
        self.addSubview(self.avatarNode.view)
        self.addSubview(self.label)
        let setPeer: (EnginePeer) -> Void = { [weak self] peer in
            guard let self else { return }
            self.avatarNode.setPeer(context: context, theme: context.sharedContext.currentPresentationData.with { $0 }.theme, peer: peer, synchronousLoad: synchronousLoad, displayDimensions: CGSize(width: item.avatarSize, height: item.avatarSize))
        }
        if let peer = item.peer {
            setPeer(peer)
        } else if let username = item.username {
            let key = "\(context.account.peerId.toInt64()):\(username.lowercased())"
            if let cached = Self.resolvedPeers[key] {
                setPeer(cached)
            } else {
                self.avatarNode.setCustomLetters([String(username.prefix(1)).uppercased()])
                self.disposable.set((context.engine.peers.resolvePeerByName(name: username, referrer: nil)
                |> deliverOnMainQueue).start(next: { result in
                    guard case let .result(peer?) = result else { return }
                    if Self.resolvedPeers.count >= 256 {
                        Self.resolvedPeers.removeAll()
                    }
                    Self.resolvedPeers[key] = peer
                    setPeer(peer)
                }))
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable.dispose()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.avatarNode.frame = CGRect(x: 0.0, y: floor((self.bounds.height - self.item.avatarSize) * 0.5), width: self.item.avatarSize, height: self.item.avatarSize)
        self.label.frame = CGRect(x: self.item.avatarSize + 3.0, y: (self.bounds.height - self.item.font.lineHeight) * 0.5, width: self.bounds.width - self.item.avatarSize - 3.0, height: self.item.font.lineHeight)
    }
}

public final class InteractiveTextNodeWithEntities {
    private var mentionAvatarViews: [Int: (MentionAvatarItem, MentionAvatarView)] = [:]
    public final class Arguments {
        public let context: AccountContext
        public let cache: AnimationCache
        public let renderer: MultiAnimationRenderer
        public let placeholderColor: UIColor
        public let attemptSynchronous: Bool
        public let textColor: UIColor
        public let spoilerEffectColor: UIColor
        public let applyArguments: InteractiveTextNode.ApplyArguments
        
        public init(
            context: AccountContext,
            cache: AnimationCache,
            renderer: MultiAnimationRenderer,
            placeholderColor: UIColor,
            attemptSynchronous: Bool,
            textColor: UIColor,
            spoilerEffectColor: UIColor,
            applyArguments: InteractiveTextNode.ApplyArguments
        ) {
            self.context = context
            self.cache = cache
            self.renderer = renderer
            self.placeholderColor = placeholderColor
            self.attemptSynchronous = attemptSynchronous
            self.textColor = textColor
            self.spoilerEffectColor = spoilerEffectColor
            self.applyArguments = applyArguments
        }
        
        public func withUpdatedPlaceholderColor(_ color: UIColor) -> Arguments {
            return Arguments(
                context: self.context,
                cache: self.cache,
                renderer: self.renderer,
                placeholderColor: color,
                attemptSynchronous: self.attemptSynchronous,
                textColor: self.textColor,
                spoilerEffectColor: self.spoilerEffectColor,
                applyArguments: self.applyArguments
            )
        }
    }
    
    private final class InlineStickerItemLayerData {
        let itemLayer: InlineStickerItemLayer
        var rect: CGRect = CGRect()
        
        init(itemLayer: InlineStickerItemLayer) {
            self.itemLayer = itemLayer
        }
    }
    
    public let textNode: InteractiveTextNode
    
    private var inlineStickerItemLayers: [InlineStickerItemLayer.Key: InlineStickerItemLayerData] = [:]
    private var displayContentsUnderSpoilers: Bool?
    
    private var enableLooping: Bool = true
    
    public private(set) var attributedString: NSAttributedString?
    
    public var visibilityRect: CGRect? {
        didSet {
            if !self.inlineStickerItemLayers.isEmpty && oldValue != self.visibilityRect {
                for (_, itemLayerData) in self.inlineStickerItemLayers {
                    let isItemVisible: Bool
                    if let visibilityRect = self.visibilityRect {
                        if itemLayerData.rect.intersects(visibilityRect) {
                            isItemVisible = true
                        } else {
                            isItemVisible = false
                        }
                    } else {
                        isItemVisible = false
                    }
                    itemLayerData.itemLayer.isVisibleForAnimations = self.enableLooping && isItemVisible
                }
            }
        }
    }
    
    public init() {
        self.textNode = InteractiveTextNode()
    }
    
    private init(textNode: InteractiveTextNode) {
        self.textNode = textNode
    }
    
    public static func asyncLayout(_ maybeNode: InteractiveTextNodeWithEntities?) -> (InteractiveTextNodeLayoutArguments) -> (InteractiveTextNodeLayout, (InteractiveTextNodeWithEntities.Arguments) -> InteractiveTextNodeWithEntities) {
        let makeLayout = InteractiveTextNode.asyncLayout(maybeNode?.textNode)
        return { [weak maybeNode] arguments in
            var updatedString: NSAttributedString?
            if let sourceString = arguments.attributedString {
                let string = NSMutableAttributedString(attributedString: sourceString)
                
                var fullRange = NSRange(location: 0, length: string.length)
                var originalTextId = 0
                while true {
                    var found = false
                    string.enumerateAttribute(ChatTextInputAttributes.customEmoji, in: fullRange, options: [], using: { value, range, stop in
                        if let value = value as? ChatTextInputTextCustomEmojiAttribute, let font = string.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont {
                            let updatedSubstring = NSMutableAttributedString(string: "&")
                            
                            let replacementRange = NSRange(location: 0, length: updatedSubstring.length)
                            updatedSubstring.addAttributes(string.attributes(at: range.location, effectiveRange: nil), range: replacementRange)
                            updatedSubstring.addAttribute(NSAttributedString.Key("Attribute__EmbeddedItem"), value: InlineStickerItem(emoji: value, file: value.file, fontSize: font.pointSize), range: replacementRange)
                            updatedSubstring.addAttribute(originalTextAttributeKey, value: OriginalTextAttribute(id: originalTextId, string: string.attributedSubstring(from: range).string), range: replacementRange)
                            originalTextId += 1
                            
                            let itemSize = (font.pointSize * 24.0 / 17.0)
                            
                            let runDelegateData = RunDelegateData(
                                ascent: font.ascender,
                                descent: font.descender,
                                width: itemSize
                            )
                            var callbacks = CTRunDelegateCallbacks(
                                version: kCTRunDelegateCurrentVersion,
                                dealloc: { dataRef in
                                    Unmanaged<RunDelegateData>.fromOpaque(dataRef).release()
                                },
                                getAscent: { dataRef in
                                    let data = Unmanaged<RunDelegateData>.fromOpaque(dataRef)
                                    return data.takeUnretainedValue().ascent
                                },
                                getDescent: { dataRef in
                                    let data = Unmanaged<RunDelegateData>.fromOpaque(dataRef)
                                    return data.takeUnretainedValue().descent
                                },
                                getWidth: { dataRef in
                                    let data = Unmanaged<RunDelegateData>.fromOpaque(dataRef)
                                    return data.takeUnretainedValue().width
                                }
                            )
                            
                            if let runDelegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(runDelegateData).toOpaque()) {
                                updatedSubstring.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: runDelegate, range: replacementRange)
                            }
                            
                            string.replaceCharacters(in: range, with: updatedSubstring)
                            let updatedRange = NSRange(location: range.location, length: updatedSubstring.length)
                            
                            found = true
                            stop.pointee = ObjCBool(true)
                            fullRange = NSRange(location: updatedRange.upperBound, length: fullRange.upperBound - range.upperBound)
                        }
                    })
                    if !found {
                        break
                    }
                }
                
                updatedString = string
            }
            
            let (layout, apply) = makeLayout(arguments.withAttributedString(updatedString))
            return (layout, { applyArguments in
                let animation: ListViewItemUpdateAnimation = applyArguments.applyArguments.animation
                
                var crossfadeSourceView: UIView?
                if let maybeNode, applyArguments.applyArguments.animation.transition.isAnimated, let animator = applyArguments.applyArguments.animation.animator as? ControlledTransition.LegacyAnimator, animator.transition.isAnimated, maybeNode.textNode.bounds.size != layout.size {
                    crossfadeSourceView = maybeNode.textNode.view.snapshotView(afterScreenUpdates: false)
                }
                
                let result = apply(applyArguments.applyArguments)
                
                if let maybeNode {
                    maybeNode.attributedString = arguments.attributedString
                    
                    maybeNode.updateInteractiveContents(
                        context: applyArguments.context,
                        cache: applyArguments.cache,
                        renderer: applyArguments.renderer,
                        textLayout: layout,
                        placeholderColor: applyArguments.placeholderColor,
                        attemptSynchronousLoad: false,
                        textColor: applyArguments.textColor,
                        spoilerEffectColor: applyArguments.spoilerEffectColor,
                        animation: animation,
                        applyArguments: applyArguments.applyArguments
                    )
                    
                    if let crossfadeSourceView {
                        applyArguments.applyArguments.crossfadeContents?(crossfadeSourceView)
                    }
                    
                    return maybeNode
                } else {
                    let resultNode = InteractiveTextNodeWithEntities(textNode: result)
                    
                    resultNode.attributedString = arguments.attributedString
                    
                    resultNode.updateInteractiveContents(
                        context: applyArguments.context,
                        cache: applyArguments.cache,
                        renderer: applyArguments.renderer,
                        textLayout: layout,
                        placeholderColor: applyArguments.placeholderColor,
                        attemptSynchronousLoad: false,
                        textColor: applyArguments.textColor,
                        spoilerEffectColor: applyArguments.spoilerEffectColor,
                        animation: .None,
                        applyArguments: applyArguments.applyArguments
                    )
                    
                    return resultNode
                }
            })
        }
    }
    
    private func isItemVisible(itemRect: CGRect) -> Bool {
        if let visibilityRect = self.visibilityRect {
            return itemRect.intersects(visibilityRect)
        } else {
            return false
        }
    }
    
    private func updateInteractiveContents(
        context: AccountContext,
        cache: AnimationCache,
        renderer: MultiAnimationRenderer,
        textLayout: InteractiveTextNodeLayout?,
        placeholderColor: UIColor,
        attemptSynchronousLoad: Bool,
        textColor: UIColor,
        spoilerEffectColor: UIColor,
        animation: ListViewItemUpdateAnimation,
        applyArguments: InteractiveTextNode.ApplyArguments
    ) {
        self.enableLooping = context.sharedContext.energyUsageSettings.loopEmoji
        
        var displayContentsUnderSpoilers = false
        if let textLayout {
            displayContentsUnderSpoilers = textLayout.displayContentsUnderSpoilers
        }
        
        self.displayContentsUnderSpoilers = displayContentsUnderSpoilers
        
        var nextIndexById: [Int64: Int] = [:]
        var validIds: [InlineStickerItemLayer.Key] = []
        var mentionIndex = 0
        
        if let textLayout {
            for i in 0 ..< textLayout.segments.count {
                let segment = textLayout.segments[i]
                guard let segmentLayer = self.textNode.segmentLayer(index: i), let segmentParams = segmentLayer.params else {
                    continue
                }
                
                for item in segment.embeddedItems {
                    if let mention = item.value as? MentionAvatarItem {
                        let index = mentionIndex
                        mentionIndex += 1
                        let view: MentionAvatarView
                        if let current = self.mentionAvatarViews[index], current.0 == mention {
                            view = current.1
                        } else {
                            self.mentionAvatarViews.removeValue(forKey: index)?.1.removeFromSuperview()
                            view = MentionAvatarView(context: context, item: mention, synchronousLoad: attemptSynchronousLoad)
                            self.mentionAvatarViews[index] = (mention, view)
                        }
                        if view.superview !== segmentLayer.renderNode.view {
                            segmentLayer.renderNode.view.addSubview(view)
                        }
                        view.frame = item.rect.offsetBy(dx: segmentParams.item.contentOffset.x, dy: segmentParams.item.contentOffset.y)
                        view.alpha = item.isHiddenBySpoiler ? 0.0 : 1.0
                    } else if let stickerItem = item.value as? InlineStickerItem {
                        let index: Int
                        if let currentNext = nextIndexById[stickerItem.emoji.fileId] {
                            index = currentNext
                        } else {
                            index = 0
                        }
                        nextIndexById[stickerItem.emoji.fileId] = index + 1
                        let id = InlineStickerItemLayer.Key(id: stickerItem.emoji.fileId, index: index)
                        validIds.append(id)
                        
                        let itemSize = floorToScreenPixels(stickerItem.fontSize * 24.0 / 17.0)
                        
                        var itemFrame = CGRect(origin: item.rect.center, size: CGSize()).insetBy(dx: -itemSize / 2.0, dy: -itemSize / 2.0)
                        itemFrame.origin.x = floorToScreenPixels(itemFrame.origin.x)
                        itemFrame.origin.y = floorToScreenPixels(itemFrame.origin.y)
                        
                        itemFrame.origin.x += segmentParams.item.contentOffset.x
                        itemFrame.origin.y += segmentParams.item.contentOffset.y
                        
                        let itemLayerData: InlineStickerItemLayerData
                        var itemLayerTransition = animation.transition
                        if let current = self.inlineStickerItemLayers[id] {
                            itemLayerData = current
                            itemLayerData.itemLayer.dynamicColor = item.textColor
                            
                            if itemLayerData.itemLayer.superlayer !== segmentLayer.renderNode.layer {
                                segmentLayer.addSublayer(itemLayerData.itemLayer)
                            }
                        } else {
                            itemLayerTransition = .immediate
                            let pointSize = floor(itemSize * 1.3)
                            itemLayerData = InlineStickerItemLayerData(itemLayer: InlineStickerItemLayer(context: context, userLocation: .other, attemptSynchronousLoad: attemptSynchronousLoad, emoji: stickerItem.emoji, file: stickerItem.file, cache: cache, renderer: renderer, placeholderColor: placeholderColor, pointSize: CGSize(width: pointSize, height: pointSize), dynamicColor: item.textColor))
                            self.inlineStickerItemLayers[id] = itemLayerData
                            segmentLayer.renderNode.layer.addSublayer(itemLayerData.itemLayer)
                            
                            itemLayerData.itemLayer.isVisibleForAnimations = self.enableLooping && self.isItemVisible(itemRect: itemFrame.offsetBy(dx: -segmentParams.item.contentOffset.x, dy: -segmentParams.item.contentOffset.x))
                        }
                        
                        itemLayerTransition.updateAlpha(layer: itemLayerData.itemLayer, alpha: item.isHiddenBySpoiler ? 0.0 : 1.0)
                        
                        itemLayerData.itemLayer.frame = itemFrame
                        itemLayerData.rect = itemFrame.offsetBy(dx: -segmentParams.item.contentOffset.x, dy: -segmentParams.item.contentOffset.y)
                    }
                }
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayerData) in self.inlineStickerItemLayers {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayerData.itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemLayers.removeValue(forKey: key)
        }
        for index in Array(self.mentionAvatarViews.keys) where index >= mentionIndex {
            self.mentionAvatarViews.removeValue(forKey: index)?.1.removeFromSuperview()
        }
    }
}

public final class InteractiveTextComponent: Component {
    public final class External {
        public fileprivate(set) var layout: InteractiveTextNodeLayout?
        
        public init() {
        }
    }
    
    public let external: External?
    public let attributedString: NSAttributedString?
    public let backgroundColor: UIColor?
    public let minimumNumberOfLines: Int
    public let maximumNumberOfLines: Int
    public let truncationType: CTLineTruncationType
    public let alignment: NSTextAlignment
    public let verticalAlignment: TextVerticalAlignment
    public let lineSpacing: CGFloat
    public let cutout: TextNodeCutout?
    public let insets: UIEdgeInsets
    public let lineColor: UIColor?
    public let textShadowColor: UIColor?
    public let textShadowBlur: CGFloat?
    public let textStroke: (UIColor, CGFloat)?
    public let displayContentsUnderSpoilers: Bool
    public let customTruncationToken: ((UIFont, Bool) -> NSAttributedString?)?
    public let expandedBlocks: Set<Int>
    public let context: AccountContext
    public let cache: AnimationCache
    public let renderer: MultiAnimationRenderer
    public let placeholderColor: UIColor
    public let attemptSynchronous: Bool
    public let textColor: UIColor
    public let spoilerEffectColor: UIColor
    public let spoilerTextColor: UIColor
    public let areContentAnimationsEnabled: Bool
    public let spoilerExpandPoint: CGPoint?
    public let crossfadeContents: ((UIView) -> Void)?
    public let canHandleTapAtPoint: ((CGPoint) -> Bool)?
    public let requestToggleBlockCollapsed: ((Int) -> Void)?
    public let requestDisplayContentsUnderSpoilers: ((CGPoint?) -> Void)?
    
    public init(
        external: External? = nil,
        attributedString: NSAttributedString?,
        backgroundColor: UIColor?,
        minimumNumberOfLines: Int,
        maximumNumberOfLines: Int,
        truncationType: CTLineTruncationType,
        alignment: NSTextAlignment,
        verticalAlignment: TextVerticalAlignment,
        lineSpacing: CGFloat,
        cutout: TextNodeCutout?,
        insets: UIEdgeInsets,
        lineColor: UIColor?,
        textShadowColor: UIColor?,
        textShadowBlur: CGFloat?,
        textStroke: (UIColor, CGFloat)?,
        displayContentsUnderSpoilers: Bool,
        customTruncationToken: ((UIFont, Bool) -> NSAttributedString?)?,
        expandedBlocks: Set<Int>,
        context: AccountContext,
        cache: AnimationCache,
        renderer: MultiAnimationRenderer,
        placeholderColor: UIColor,
        attemptSynchronous: Bool,
        textColor: UIColor,
        spoilerEffectColor: UIColor,
        spoilerTextColor: UIColor,
        areContentAnimationsEnabled: Bool,
        spoilerExpandPoint: CGPoint?,
        crossfadeContents: ((UIView) -> Void)? = nil,
        canHandleTapAtPoint: ((CGPoint) -> Bool)? = nil,
        requestToggleBlockCollapsed: ((Int) -> Void)? = nil,
        requestDisplayContentsUnderSpoilers: ((CGPoint?) -> Void)? = nil
    ) {
        self.external = external
        self.attributedString = attributedString
        self.backgroundColor = backgroundColor
        self.minimumNumberOfLines = minimumNumberOfLines
        self.maximumNumberOfLines = maximumNumberOfLines
        self.truncationType = truncationType
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.lineSpacing = lineSpacing
        self.cutout = cutout
        self.insets = insets
        self.lineColor = lineColor
        self.textShadowColor = textShadowColor
        self.textShadowBlur = textShadowBlur
        self.textStroke = textStroke
        self.displayContentsUnderSpoilers = displayContentsUnderSpoilers
        self.customTruncationToken = customTruncationToken
        self.expandedBlocks = expandedBlocks
        self.context = context
        self.cache = cache
        self.renderer = renderer
        self.placeholderColor = placeholderColor
        self.attemptSynchronous = attemptSynchronous
        self.textColor = textColor
        self.spoilerTextColor = spoilerTextColor
        self.areContentAnimationsEnabled = areContentAnimationsEnabled
        self.spoilerExpandPoint = spoilerExpandPoint
        self.crossfadeContents = crossfadeContents
        self.spoilerEffectColor = spoilerEffectColor
        self.canHandleTapAtPoint = canHandleTapAtPoint
        self.requestToggleBlockCollapsed = requestToggleBlockCollapsed
        self.requestDisplayContentsUnderSpoilers = requestDisplayContentsUnderSpoilers
    }
    
    public static func ==(lhs: InteractiveTextComponent, rhs: InteractiveTextComponent) -> Bool {
        if lhs.external !== rhs.external {
            return false
        }
        if lhs.attributedString != rhs.attributedString {
            return false
        }
        if lhs.backgroundColor != rhs.backgroundColor {
            return false
        }
        if lhs.minimumNumberOfLines != rhs.minimumNumberOfLines {
            return false
        }
        if lhs.maximumNumberOfLines != rhs.maximumNumberOfLines {
            return false
        }
        if lhs.truncationType != rhs.truncationType {
            return false
        }
        if lhs.alignment != rhs.alignment {
            return false
        }
        if lhs.verticalAlignment != rhs.verticalAlignment {
            return false
        }
        if lhs.lineSpacing != rhs.lineSpacing {
            return false
        }
        if lhs.cutout != rhs.cutout {
            return false
        }
        if lhs.insets != rhs.insets {
            return false
        }
        if lhs.lineColor != rhs.lineColor {
            return false
        }
        if lhs.textShadowColor != rhs.textShadowColor {
            return false
        }
        if lhs.textShadowBlur != rhs.textShadowBlur {
            return false
        }
        if lhs.textStroke?.0 != rhs.textStroke?.0 || lhs.textStroke?.1 != rhs.textStroke?.1 {
            return false
        }
        if lhs.displayContentsUnderSpoilers != rhs.displayContentsUnderSpoilers {
            return false
        }
        if (lhs.customTruncationToken == nil) != (rhs.customTruncationToken == nil) {
            return false
        }
        if lhs.expandedBlocks != rhs.expandedBlocks {
            return false
        }
        if lhs.spoilerExpandPoint != rhs.spoilerExpandPoint {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        private let textNodeWithEntities: InteractiveTextNodeWithEntities
        
        public var textNode: TextNodeProtocol {
            return self.textNodeWithEntities.textNode
        }

        override public init(frame: CGRect) {
            self.textNodeWithEntities = InteractiveTextNodeWithEntities()
            
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(component: InteractiveTextComponent, availableSize: CGSize, state: State, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let makeLayout = InteractiveTextNodeWithEntities.asyncLayout(self.textNodeWithEntities)
            let (layout, apply) = makeLayout(InteractiveTextNodeLayoutArguments(attributedString: component.attributedString, backgroundColor: component.backgroundColor, minimumNumberOfLines: component.minimumNumberOfLines, maximumNumberOfLines: component.maximumNumberOfLines, truncationType: component.truncationType, constrainedSize: availableSize, alignment: component.alignment, verticalAlignment: component.verticalAlignment, lineSpacing: component.lineSpacing, cutout: component.cutout, insets: component.insets, lineColor: component.lineColor, textShadowColor: component.textShadowColor, textShadowBlur: component.textShadowBlur, textStroke: component.textStroke, displayContentsUnderSpoilers: component.displayContentsUnderSpoilers, customTruncationToken: component.customTruncationToken, expandedBlocks: component.expandedBlocks))
            let textFrame = CGRect(origin: CGPoint(), size: layout.size)
            
            var spoilerExpandRect: CGRect?
            if let mappedLocation = component.spoilerExpandPoint {
                let getDistance: (CGPoint, CGPoint) -> CGFloat = { a, b in
                    let v = CGPoint(x: a.x - b.x, y: a.y - b.y)
                    return sqrt(v.x * v.x + v.y * v.y)
                }
                
                var maxDistance: CGFloat = getDistance(mappedLocation, CGPoint(x: 0.0, y: 0.0))
                maxDistance = max(maxDistance, getDistance(mappedLocation, CGPoint(x: textFrame.width, y: 0.0)))
                maxDistance = max(maxDistance, getDistance(mappedLocation, CGPoint(x: textFrame.width, y: textFrame.height)))
                maxDistance = max(maxDistance, getDistance(mappedLocation, CGPoint(x: 0.0, y: textFrame.height)))
                
                let mappedSize = CGSize(width: maxDistance * 2.0, height: maxDistance * 2.0)
                spoilerExpandRect = mappedSize.centered(around: mappedLocation)
            }

            let applyArguments = InteractiveTextNode.ApplyArguments(
                animation: transition.animation.isImmediate ? .None : .System(duration: 0.4, transition: .init(duration: 0.4, curve: .spring, interactive: false)),
                spoilerTextColor: component.spoilerTextColor,
                spoilerEffectColor: component.spoilerEffectColor,
                areContentAnimationsEnabled: component.areContentAnimationsEnabled,
                spoilerExpandRect: spoilerExpandRect,
                crossfadeContents: component.crossfadeContents
            )

            let resultNode = apply(InteractiveTextNodeWithEntities.Arguments(
                context: component.context,
                cache: component.cache,
                renderer: component.renderer,
                placeholderColor: component.placeholderColor,
                attemptSynchronous: component.attemptSynchronous,
                textColor: component.textColor,
                spoilerEffectColor: component.spoilerEffectColor,
                applyArguments: applyArguments
            ))

            if self.textNodeWithEntities.textNode.view.superview == nil {
                self.addSubview(self.textNodeWithEntities.textNode.view)
            }

            resultNode.visibilityRect = CGRect(origin: CGPoint(), size: layout.size)
            resultNode.textNode.view.frame = textFrame
            
            resultNode.textNode.canHandleTapAtPoint = component.canHandleTapAtPoint
            resultNode.textNode.requestToggleBlockCollapsed = component.requestToggleBlockCollapsed
            resultNode.textNode.requestDisplayContentsUnderSpoilers = component.requestDisplayContentsUnderSpoilers
            
            component.external?.layout = resultNode.textNode.cachedLayout

            return layout.size
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: State, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
