import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import AnimationCache
import MultiAnimationRenderer
import TelegramCore
import AccountContext
import SwiftSignalKit
import EmojiTextAttachmentView
import LokiRng
import TextFormat
import HierarchyTrackingLayer
import PeerInfoPaneNode
import GlassBackgroundComponent
import TelegramStringFormatting

public final class PeerInfoGiftsCoverComponent: Component {
    public let context: AccountContext
    public let peerId: EnginePeer.Id
    public let giftsContext: ProfileGiftsContext
    public let hasBackground: Bool
    public let avatarCenter: CGPoint
    public let avatarSize: CGSize
    public let defaultHeight: CGFloat
    public let avatarTransitionFraction: CGFloat
    public let statusBarHeight: CGFloat
    public let topLeftButtonsSize: CGSize
    public let topRightButtonsSize: CGSize
    public let titleWidth: CGFloat
    /// The title's center on a layout with a side strip (iPhone Duo); nil centers on the full width.
    public let titleCenterX: CGFloat?
    /// Keeps the icons off the navigation buttons and out of a side strip (iPhone Duo).
    public let sideInsets: PeerInfoSideInsets
    public let bottomHeight: CGFloat
    public let action: (ProfileGiftsContext.State.StarGift) -> Void

    public init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        giftsContext: ProfileGiftsContext,
        hasBackground: Bool,
        avatarCenter: CGPoint,
        avatarSize: CGSize,
        defaultHeight: CGFloat,
        avatarTransitionFraction: CGFloat,
        statusBarHeight: CGFloat,
        topLeftButtonsSize: CGSize,
        topRightButtonsSize: CGSize,
        titleWidth: CGFloat,
        titleCenterX: CGFloat?,
        sideInsets: PeerInfoSideInsets,
        bottomHeight: CGFloat,
        action: @escaping (ProfileGiftsContext.State.StarGift) -> Void
    ) {
        self.context = context
        self.peerId = peerId
        self.giftsContext = giftsContext
        self.hasBackground = hasBackground
        self.avatarCenter = avatarCenter
        self.avatarSize = avatarSize
        self.defaultHeight = defaultHeight
        self.avatarTransitionFraction = avatarTransitionFraction
        self.statusBarHeight = statusBarHeight
        self.topLeftButtonsSize = topLeftButtonsSize
        self.topRightButtonsSize = topRightButtonsSize
        self.titleWidth = titleWidth
        self.titleCenterX = titleCenterX
        self.sideInsets = sideInsets
        self.bottomHeight = bottomHeight
        self.action = action
    }

    public static func ==(lhs: PeerInfoGiftsCoverComponent, rhs: PeerInfoGiftsCoverComponent) -> Bool {
        if lhs.context !== rhs.context { return false }
        if lhs.peerId != rhs.peerId { return false }
        if lhs.hasBackground != rhs.hasBackground { return false }
        if lhs.avatarCenter != rhs.avatarCenter { return false }
        if lhs.avatarSize != rhs.avatarSize { return false }
        if lhs.defaultHeight != rhs.defaultHeight { return false }
        if lhs.avatarTransitionFraction != rhs.avatarTransitionFraction { return false }
        if lhs.statusBarHeight != rhs.statusBarHeight { return false }
        if lhs.topLeftButtonsSize != rhs.topLeftButtonsSize { return false }
        if lhs.topRightButtonsSize != rhs.topRightButtonsSize { return false }
        if lhs.titleWidth != rhs.titleWidth { return false }
        if lhs.titleCenterX != rhs.titleCenterX { return false }
        if lhs.sideInsets != rhs.sideInsets { return false }
        if lhs.bottomHeight != rhs.bottomHeight { return false }
        return true
    }

    public final class View: UIView {
        private var currentSize: CGSize?
        private var component: PeerInfoGiftsCoverComponent?
        private var state: EmptyComponentState?

        private var giftsDisposable: Disposable?
        private var gifts: [ProfileGiftsContext.State.StarGift] = []
        private var appliedGiftIds: [Int64] = []

        private var iconLayers: [AnyHashable: GiftIconLayer] = [:]
        private var iconPositions: [PositionGenerator.Position] = []
        private let seed = UInt(Date().timeIntervalSince1970)

        private let trackingLayer = HierarchyTrackingLayer()
        private var isCurrentlyInHierarchy = false
        private var isUpdating = false

        private var orbitLink: CADisplayLink?
        private let orbitStart = CACurrentMediaTime()
        private var orbitIndices: [AnyHashable: (index: Int, count: Int, scale: CGFloat)] = [:]
        private var orbitCenter = CGPoint()
        private var orbitAvatarRadius: CGFloat = 0.0
        private var orbitFraction: CGFloat = 1.0

        private final class OrbitTarget: NSObject {
            weak var view: View?
            init(view: View) { self.view = view }
            @objc func tick() { self.view?.orbitTick() }
        }

        private func orbitAngle(index: Int, count: Int, time: CGFloat) -> (distance: CGFloat, angle: CGFloat) {
            let innerCount = min(count, 6)
            let isInner = index < innerCount
            let ringCount = isInner ? innerCount : max(1, count - innerCount)
            let ringIndex = isInner ? index : index - innerCount
            let offset: CGFloat = isInner ? 0.0 : .pi / CGFloat(ringCount)
            let base = CGFloat.pi * 2.0 * CGFloat(ringIndex) / CGFloat(max(1, ringCount)) + offset - .pi / 2.0
            let speed: CGFloat = isInner ? 0.32 : -0.21
            let distance = self.orbitAvatarRadius + (isInner ? 28.0 : 62.0)
            return (distance, base + time * speed)
        }

        private var draggingId: AnyHashable?
        private var orbitHoldUntil: [AnyHashable: Double] = [:]
        private var dragLastPoint = CGPoint()
        private var dragLastTime: Double = 0.0
        private var dragVelocity = CGPoint()
        private weak var dragDisabledScrollView: UIScrollView?

        @objc private func longPressed(_ gestureRecognizer: UILongPressGestureRecognizer) {
            let location = gestureRecognizer.location(in: self)
            switch gestureRecognizer.state {
            case .began:
                guard GhostSettings.profileV2, self.orbitFraction < 0.001 else { return }
                for (id, iconLayer) in self.iconLayers {
                    if iconLayer.frame.insetBy(dx: -10.0, dy: -10.0).contains(location) {
                        self.draggingId = id
                        break
                    }
                }
                guard let id = self.draggingId, let iconLayer = self.iconLayers[id] else { return }
                var current: UIView? = self.superview
                while let view = current {
                    if let scrollView = view as? UIScrollView, scrollView.isScrollEnabled {
                        scrollView.isScrollEnabled = false
                        self.dragDisabledScrollView = scrollView
                        break
                    }
                    current = view.superview
                }
                self.clipsToBounds = false
                iconLayer.zPosition = 10.0
                self.dragLastPoint = location
                self.dragLastTime = CACurrentMediaTime()
                self.dragVelocity = CGPoint()
                ComponentTransition.spring(duration: 0.4).setPosition(layer: iconLayer, position: location)
                ComponentTransition.spring(duration: 0.4).setScale(layer: iconLayer, scale: 2.4)
                iconLayer.setInteracting(true)
                HapticFeedback().impact(.light)
            case .changed:
                guard let id = self.draggingId, let iconLayer = self.iconLayers[id] else { return }
                let now = CACurrentMediaTime()
                let dt = max(0.001, now - self.dragLastTime)
                let velocity = CGPoint(x: (location.x - self.dragLastPoint.x) / dt, y: (location.y - self.dragLastPoint.y) / dt)
                self.dragVelocity = CGPoint(x: self.dragVelocity.x * 0.6 + velocity.x * 0.4, y: self.dragVelocity.y * 0.6 + velocity.y * 0.4)
                self.dragLastPoint = location
                self.dragLastTime = now
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                iconLayer.position = location
                CATransaction.commit()
                iconLayer.updateStretch(velocity: self.dragVelocity, animated: false)
            default:
                guard let id = self.draggingId else { return }
                self.draggingId = nil
                if let scrollView = self.dragDisabledScrollView {
                    scrollView.isScrollEnabled = true
                    self.dragDisabledScrollView = nil
                }
                guard let iconLayer = self.iconLayers[id] else {
                    self.clipsToBounds = true
                    return
                }
                iconLayer.setInteracting(false)
                iconLayer.updateStretch(velocity: CGPoint(), animated: true)
                let returnDuration = 0.55
                self.orbitHoldUntil[id] = CACurrentMediaTime() + returnDuration
                var target = iconLayer.position
                var scale: CGFloat = 1.0
                if let item = self.orbitIndices[id] {
                    let time = CGFloat(CACurrentMediaTime() + returnDuration - self.orbitStart)
                    let orbit = self.orbitAngle(index: item.index, count: item.count, time: time)
                    target = getAbsolutePosition(distance: orbit.distance, angle: orbit.angle, centerPoint: self.orbitCenter)
                    scale = item.scale
                }
                ComponentTransition.spring(duration: returnDuration).setPosition(layer: iconLayer, position: target)
                ComponentTransition.spring(duration: returnDuration).setScale(layer: iconLayer, scale: scale, completion: { [weak self, weak iconLayer] _ in
                    iconLayer?.zPosition = 0.0
                    if let self, self.draggingId == nil {
                        self.clipsToBounds = true
                    }
                })
            }
        }

        fileprivate func orbitTick() {
            guard self.orbitFraction < 0.001, !self.orbitIndices.isEmpty else { return }
            let time = CGFloat(CACurrentMediaTime() - self.orbitStart)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let now = CACurrentMediaTime()
            for (id, iconLayer) in self.iconLayers {
                guard let item = self.orbitIndices[id] else { continue }
                if let draggingId = self.draggingId, draggingId == id { continue }
                if let holdUntil = self.orbitHoldUntil[id], holdUntil > now { continue }
                let orbit = self.orbitAngle(index: item.index, count: item.count, time: time)
                iconLayer.position = getAbsolutePosition(distance: orbit.distance, angle: orbit.angle, centerPoint: self.orbitCenter)
            }
            CATransaction.commit()
        }

        private func updateOrbitLink() {
            let needed = GhostSettings.profileV2 && self.isCurrentlyInHierarchy && self.orbitFraction < 0.001 && !self.iconLayers.isEmpty
            if needed, self.orbitLink == nil {
                let link = CADisplayLink(target: OrbitTarget(view: self), selector: #selector(OrbitTarget.tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 60.0, preferred: 60.0)
                link.add(to: .main, forMode: .common)
                self.orbitLink = link
            } else if !needed, let link = self.orbitLink {
                link.invalidate()
                self.orbitLink = nil
            }
        }

        override public init(frame: CGRect) {
            super.init(frame: frame)
            self.clipsToBounds = true
            self.layer.addSublayer(self.trackingLayer)

            self.trackingLayer.didEnterHierarchy = { [weak self] in
                guard let self else { return }
                self.isCurrentlyInHierarchy = true
                self.updateAnimations()
                self.updateOrbitLink()
            }
            self.trackingLayer.didExitHierarchy = { [weak self] in
                guard let self else { return }
                self.isCurrentlyInHierarchy = false
                self.updateAnimations()
                self.updateOrbitLink()
            }

            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:)))
            let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.longPressed(_:)))
            longPressRecognizer.minimumPressDuration = 0.18
            longPressRecognizer.allowableMovement = .greatestFiniteMagnitude
            tapRecognizer.require(toFail: longPressRecognizer)
            self.addGestureRecognizer(longPressRecognizer)
            self.addGestureRecognizer(tapRecognizer)
        }

        required public init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            self.giftsDisposable?.dispose()
            self.orbitLink?.invalidate()
            self.dragDisabledScrollView?.isScrollEnabled = true
        }

        @objc private func tapped(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let component = self.component else { return }
            let location = gestureRecognizer.location(in: self)
            for (_, iconLayer) in self.iconLayers {
                let hitFrame = GhostSettings.profileV2 ? iconLayer.frame.insetBy(dx: -8.0, dy: -8.0) : iconLayer.frame
                if iconLayer.opacity > 0.01, hitFrame.contains(location) {
                    component.action(iconLayer.gift)
                    break
                }
            }
        }

        private var accessibilityGiftElements: [AnyHashable: GiftAccessibilityElement] = [:]

        override public var accessibilityElements: [Any]? {
            get {
                guard let component = self.component, component.avatarTransitionFraction < 0.999 else { return [] }
                let dateTimeFormat = component.context.sharedContext.currentPresentationData.with { $0 }.dateTimeFormat
                var elements: [(frame: CGRect, element: GiftAccessibilityElement)] = []
                var validIds = Set<AnyHashable>()
                for (id, iconLayer) in self.iconLayers {
                    guard case let .unique(gift) = iconLayer.gift.gift, iconLayer.opacity > 0.01, self.bounds.intersects(iconLayer.frame) else { continue }
                    validIds.insert(id)
                    let element: GiftAccessibilityElement
                    if let current = self.accessibilityGiftElements[id] {
                        element = current
                    } else {
                        element = GiftAccessibilityElement(accessibilityContainer: self)
                        self.accessibilityGiftElements[id] = element
                    }
                    element.accessibilityLabel = "\(gift.title) #\(formatCollectibleNumber(gift.number, dateTimeFormat: dateTimeFormat))"
                    element.accessibilityTraits = .button
                    element.accessibilityFrameInContainerSpace = iconLayer.frame
                    let starGift = iconLayer.gift
                    element.activate = { [weak self] in
                        guard let self, let component = self.component else { return false }
                        component.action(starGift)
                        return true
                    }
                    elements.append((iconLayer.frame, element))
                }
                for id in self.accessibilityGiftElements.keys where !validIds.contains(id) {
                    self.accessibilityGiftElements.removeValue(forKey: id)
                }
                elements.sort(by: { lhs, rhs in
                    if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
                    return lhs.frame.minX < rhs.frame.minX
                })
                return elements.map(\.element)
            } set(value) {
            }
        }

        public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            for (_, iconLayer) in self.iconLayers {
                let hitFrame = GhostSettings.profileV2 ? iconLayer.frame.insetBy(dx: -8.0, dy: -8.0) : iconLayer.frame
                if iconLayer.opacity > 0.01, hitFrame.contains(point) { return true }
            }
            return false
        }

        func updateAnimations() {
            var index = 0
            for (_, iconLayer) in self.iconLayers {
                if self.isCurrentlyInHierarchy {
                    iconLayer.startAnimations(index: index)
                } else {
                    iconLayer.stopAnimations()
                }
                index += 1
            }
        }

        private var scheduledAnimateIn = false
        public func willAnimateIn() {
            self.scheduledAnimateIn = true
            for (_, layer) in self.iconLayers {
                layer.opacity = 0.0
            }
        }

        public func animateIn() {
            guard let _ = self.currentSize, let component = self.component else { return }
            self.scheduledAnimateIn = false
            for (_, layer) in self.iconLayers {
                layer.opacity = 1.0
                layer.animatePosition(
                    from: component.avatarCenter,
                    to: layer.position,
                    duration: 0.4,
                    timingFunction: kCAMediaTimingFunctionSpring
                )
            }
        }

        func update(component: PeerInfoGiftsCoverComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.isUpdating = true
            defer { self.isUpdating = false }

            let previousComponent = self.component
            self.component = component
            self.state = state
            let previousCurrentSize = self.currentSize
            self.currentSize = availableSize
            let iconSize = CGSize(width: 32.0, height: 32.0)

            let giftIds = self.gifts.map { gift in
                if case let .unique(gift) = gift.gift {
                    return gift.id
                }
                return 0
            }
            if !giftIds.isEmpty && (self.iconPositions.isEmpty || previousCurrentSize?.width != availableSize.width || (previousComponent != nil && (previousComponent?.sideInsets.stripLeft != component.sideInsets.stripLeft || previousComponent?.sideInsets.stripRight != component.sideInsets.stripRight)) || (previousComponent != nil && previousComponent?.hasBackground != component.hasBackground) || self.appliedGiftIds != giftIds) {
                var avatarCenter = component.avatarCenter
                if avatarCenter.y < 0.0 {
                    avatarCenter.y = component.statusBarHeight + 75.0
                }
                var excludeRects: [CGRect] = []
                if component.statusBarHeight > 0.0 {
                    excludeRects.append(CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: component.statusBarHeight + 4.0)))
                }
                excludeRects.append(contentsOf: peerInfoGiftsCoverSideExclusionRects(width: availableSize.width, height: component.defaultHeight, statusBarHeight: component.statusBarHeight, topLeftButtonsSize: component.topLeftButtonsSize, topRightButtonsSize: component.topRightButtonsSize, sideInsets: component.sideInsets))
                excludeRects.append(CGRect(origin: CGPoint(x: component.titleCenterX.map { floor($0 - component.titleWidth / 2.0) } ?? floor((availableSize.width - component.titleWidth) / 2.0), y: avatarCenter.y + component.avatarSize.height / 2.0 + 6.0), size: CGSize(width: component.titleWidth, height: 100.0)))
                if component.bottomHeight > 0.0 {
                    excludeRects.append(CGRect(origin: CGPoint(x: 0.0, y: component.defaultHeight - component.bottomHeight), size: CGSize(width: availableSize.width, height: component.bottomHeight)))
                }
                let positionGenerator = PositionGenerator(
                    containerSize: CGSize(width: availableSize.width, height: component.defaultHeight),
                    centerFrame: component.avatarSize.centered(around: avatarCenter),
                    exclusionZones: excludeRects,
                    minimumDistance: 42.0,
                    edgePadding: 5.0,
                    seed: self.seed
                )
                self.iconPositions = positionGenerator.generatePositions(count: 12, itemSize: iconSize)
            }
            self.appliedGiftIds = giftIds

            if self.giftsDisposable == nil {
                self.giftsDisposable = combineLatest(
                    queue: Queue.mainQueue(),
                    component.giftsContext.state,
                    component.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: component.peerId))
                    |> map { peer -> Int64? in
                        if case let .user(user) = peer, case let .starGift(id, _, _, _, _, _, _, _, _) = user.emojiStatus?.content {
                            return id
                        }
                        return nil
                    }
                    |> distinctUntilChanged
                ).start(next: { [weak self] state, giftStatusId in
                    guard let self else { return }
                    let pinnedGifts = state.gifts.filter { gift in
                        if gift.pinnedToTop {
                            if case let .unique(uniqueGift) = gift.gift {
                                return uniqueGift.id != giftStatusId
                            }
                        }
                        return false
                    }
                    self.gifts = pinnedGifts
                    if !self.isUpdating {
                        self.state?.updated(transition: .spring(duration: 0.4))
                    }
                })
            }

            var validIds = Set<AnyHashable>()
            var index = 0
            let orbiting = GhostSettings.profileV2
            let orbitCount = min(self.gifts.count, 12, self.iconPositions.count)
            let orbitTime = CGFloat(CACurrentMediaTime() - self.orbitStart)
            self.orbitCenter = component.avatarCenter
            self.orbitAvatarRadius = component.avatarSize.width / 2.0
            self.orbitFraction = component.avatarTransitionFraction
            self.orbitIndices.removeAll()
            for gift in self.gifts.prefix(12) {
                guard index < self.iconPositions.count else { break }
                let id: AnyHashable
                if case let .unique(uniqueGift) = gift.gift {
                    id = uniqueGift.slug
                } else {
                    id = index
                }
                validIds.insert(id)
                var iconTransition = transition
                var iconPosition = self.iconPositions[index]
                if orbiting {
                    let orbit = self.orbitAngle(index: index, count: orbitCount, time: orbitTime)
                    iconPosition = PositionGenerator.Position(distance: orbit.distance, angle: orbit.angle, scale: min(1.0, max(0.85, iconPosition.scale)))
                    self.orbitIndices[id] = (index, orbitCount, iconPosition.scale)
                }
                let iconLayer: GiftIconLayer
                if let current = self.iconLayers[id] {
                    iconLayer = current
                } else {
                    iconTransition = .immediate
                    iconLayer = GiftIconLayer(context: component.context, gift: gift, size: iconSize, glowing: component.hasBackground)
                    self.iconLayers[id] = iconLayer
                    self.layer.addSublayer(iconLayer)
                    if self.scheduledAnimateIn {
                        iconLayer.opacity = 0.0
                    } else {
                        iconLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        iconLayer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                    }
                    if self.isCurrentlyInHierarchy {
                        iconLayer.startAnimations(index: index)
                    }
                }
                iconLayer.glowing = component.hasBackground
                if let draggingId = self.draggingId, draggingId == id {
                    index += 1
                    continue
                }

                let itemDistanceFraction = max(0.0, min(0.5, (iconPosition.distance - component.avatarSize.width / 2.0) / 144.0))
                let itemScaleFraction = patternScaleValueAt(fraction: min(1.0, component.avatarTransitionFraction * 1.33), t: itemDistanceFraction, reverse: false)
                func interpolatePosition(from: PositionGenerator.Position, to: PositionGenerator.Position, t: CGFloat) -> PositionGenerator.Position {
                    let clampedT = max(0, min(1, t))
                    let interpolatedDistance = from.distance + (to.distance - from.distance) * clampedT
                    let interpolatedAngle = from.angle + (to.angle - from.angle) * clampedT
                    return PositionGenerator.Position(distance: interpolatedDistance, angle: interpolatedAngle, scale: from.scale)
                }
                let toAngle: CGFloat = .pi * 0.18
                let centerPosition = PositionGenerator.Position(distance: 0.0, angle: iconPosition.angle + toAngle, scale: iconPosition.scale)
                let effectivePosition = interpolatePosition(from: iconPosition, to: centerPosition, t: itemScaleFraction)
                let effectiveAngle = toAngle * itemScaleFraction

                var absolutePosition = getAbsolutePosition(position: effectivePosition, centerPoint: component.avatarCenter)
                var itemScale = iconPosition.scale * (1.0 - itemScaleFraction)
                var itemAlpha = 1.0 - itemScaleFraction
                var itemRotation = effectiveAngle
                if orbiting {
                    let islandPoint = CGPoint(x: availableSize.width / 2.0, y: component.statusBarHeight > 50.0 ? 29.0 : max(10.0, component.statusBarHeight / 2.0))
                    let orbitPoint = getAbsolutePosition(position: iconPosition, centerPoint: component.avatarCenter)
                    let t = max(0.0, min(1.0, itemScaleFraction))
                    let eased = t * t * (3.0 - 2.0 * t)
                    absolutePosition = CGPoint(x: orbitPoint.x + (islandPoint.x - orbitPoint.x) * eased, y: orbitPoint.y + (islandPoint.y - orbitPoint.y) * eased)
                    itemScale = iconPosition.scale * (1.0 - 0.8 * eased)
                    itemAlpha = 1.0 - max(0.0, min(1.0, (t - 0.7) / 0.3))
                    itemRotation = 0.0
                }

                iconTransition.setBounds(layer: iconLayer, bounds: CGRect(origin: .zero, size: iconSize))
                iconTransition.setPosition(layer: iconLayer, position: absolutePosition)
                iconLayer.updateRotation(itemRotation, transition: iconTransition)
                iconTransition.setScale(layer: iconLayer, scale: itemScale)
                if !self.scheduledAnimateIn {
                    iconTransition.setAlpha(layer: iconLayer, alpha: itemAlpha)
                }
                index += 1
            }

            var removeIds: [AnyHashable] = []
            for (id, layer) in self.iconLayers {
                if !validIds.contains(id) {
                    removeIds.append(id)
                    layer.animateScale(from: 1.0, to: 0.01, duration: 0.25, removeOnCompletion: false)
                    layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { _ in
                        layer.removeFromSuperlayer()
                    })
                }
            }
            for id in removeIds {
                self.iconLayers.removeValue(forKey: id)
            }
            self.updateOrbitLink()
            return availableSize
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private var shadowImage: UIImage? = {
    return generateImage(CGSize(width: 44.0, height: 44.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        var locations: [CGFloat] = [0.0, 0.3, 1.0]
        let colors: [CGColor] = [UIColor(rgb: 0xffffff, alpha: 0.65).cgColor, UIColor(rgb: 0xffffff, alpha: 0.65).cgColor, UIColor(rgb: 0xffffff, alpha: 0.0).cgColor]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), startRadius: 0.0, endCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), endRadius: size.width / 2.0, options: .drawsAfterEndLocation)
    })
}()

private final class StarsEffectLayer: SimpleLayer {
    private let emitterLayer = CAEmitterLayer()

    override init() {
        super.init()
        self.addSublayer(self.emitterLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(color: UIColor, size: CGSize) {
        self.color = color
        let emitter = CAEmitterCell()
        emitter.name = "emitter"
        emitter.contents = UIImage(bundleImageName: "Premium/Stars/Particle")?.cgImage
        emitter.birthRate = 8.0
        emitter.lifetime = 2.0
        emitter.velocity = 0.1
        emitter.scale = (size.width / 40.0) * 0.12
        emitter.scaleRange = 0.02
        emitter.alphaRange = 0.1
        emitter.emissionRange = .pi * 2.0
        let staticColors: [Any] = [
            color.withAlphaComponent(0.0).cgColor,
            color.withAlphaComponent(0.58).cgColor,
            color.withAlphaComponent(0.58).cgColor,
            color.withAlphaComponent(0.0).cgColor
        ]
        let staticColorBehavior = CAEmitterCell.createEmitterBehavior(type: "colorOverLife")
        staticColorBehavior.setValue(staticColors, forKey: "colors")
        emitter.setValue([staticColorBehavior], forKey: "emitterBehaviors")
        self.emitterLayer.emitterCells = [emitter]
    }

    private var color: UIColor?

    func update(color: UIColor, size: CGSize) {
        if self.color != color {
            self.setup(color: color, size: size)
        }
        self.emitterLayer.seed = UInt32.random(in: .min ..< .max)
        self.emitterLayer.emitterShape = .circle
        self.emitterLayer.emitterSize = size
        self.emitterLayer.emitterMode = .surface
        self.emitterLayer.frame = CGRect(origin: .zero, size: size)
        self.emitterLayer.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
    }
}

private class GiftIconLayer: SimpleLayer {
    private let context: AccountContext
    let gift: ProfileGiftsContext.State.StarGift
    private let size: CGSize
    var glowing: Bool {
        didSet {
            self.shadowLayer.opacity = self.glowing ? 1.0 : 0.0
            let color: UIColor
            if self.glowing {
                color = .white
            } else if let layerTintColor = self.shadowLayer.layerTintColor {
                color = UIColor(cgColor: layerTintColor)
            } else {
                color = .white
            }
            let side = floor(self.size.width * 1.25)
            let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: self.size))
            self.starsLayer.frame = starsFrame
            self.starsLayer.update(color: color, size: starsFrame.size)
        }
    }

    let shadowLayer = SimpleLayer()
    let starsLayer = StarsEffectLayer()
    let animationLayer: InlineStickerItemLayer
    let bubbleLayer = SimpleLayer()
    let bubbleTintLayer = CAGradientLayer()
    let bubbleShineLayer = CAGradientLayer()
    let bubbleBackdropLayer: CALayer? = GhostSettings.profileV2 ? createBackdropLayer() : nil

    private func setupBubble(color: UIColor) {
        guard GhostSettings.profileV2 else { return }
        if let backdropLayer = self.bubbleBackdropLayer {
            backdropLayer.setValue(1.0 as NSNumber, forKey: "scale")
            backdropLayer.contentsScale = UIScreen.main.scale
            backdropLayer.rasterizationScale = UIScreen.main.scale
            if let blurFilter = CALayer.blur() {
                blurFilter.setValue(5.0 as NSNumber, forKey: "inputRadius")
                backdropLayer.filters = [blurFilter]
            }
            self.bubbleLayer.addSublayer(backdropLayer)
        }
        self.bubbleTintLayer.colors = [
            color.mixedWith(.white, alpha: 0.3).withAlphaComponent(0.45).cgColor,
            color.withAlphaComponent(0.22).cgColor
        ]
        self.bubbleTintLayer.startPoint = CGPoint(x: 0.2, y: 0.0)
        self.bubbleTintLayer.endPoint = CGPoint(x: 0.8, y: 1.0)
        self.bubbleLayer.addSublayer(self.bubbleTintLayer)
        self.bubbleLayer.addSublayer(self.particleContainer)
        if case let .unique(uniqueGift) = self.gift.gift {
            for attribute in uniqueGift.attributes {
                if case let .pattern(_, file, _) = attribute {
                    self.patternFile = file
                } else if case let .backdrop(_, _, _, _, patternColor, _, _) = attribute {
                    self.patternColor = UIColor(rgb: UInt32(bitPattern: patternColor))
                }
            }
        }
        self.bubbleLayer.borderWidth = 1.0
        self.bubbleLayer.borderColor = UIColor(white: 1.0, alpha: 0.45).cgColor
        self.bubbleLayer.masksToBounds = true
        self.bubbleShineLayer.colors = [
            UIColor(white: 1.0, alpha: 0.4).cgColor,
            UIColor(white: 1.0, alpha: 0.0).cgColor
        ]
        self.bubbleShineLayer.locations = [0.0, 0.55]
        self.bubbleLayer.addSublayer(self.bubbleShineLayer)
        self.shadowLayer.isHidden = true
        self.insertSublayer(self.bubbleLayer, at: 0)
        self.addWobble()
    }

    private let particleContainer = SimpleLayer()
    private var patternFile: TelegramMediaFile?
    private var patternColor: UIColor = .white
    private var particleTimer: Foundation.Timer?

    private func addWobble() {
        let duration = Double.random(in: 1.6 ..< 2.2)
        let begin = CACurrentMediaTime() + Double.random(in: 0.0 ..< 1.0)
        for (keyPath, sign) in [("transform.scale.x", 1.0), ("transform.scale.y", -1.0)] {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = [0.0, 0.045 * sign, 0.0, -0.045 * sign, 0.0].map { NSNumber(value: $0) }
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.isAdditive = true
            animation.beginTime = begin
            animation.calculationMode = .cubic
            self.bubbleLayer.add(animation, forKey: "ghost.wobble." + keyPath)
        }
    }

    func updateStretch(velocity: CGPoint, animated: Bool) {
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        let amount = min(0.32, speed / 2600.0)
        var transform = CATransform3DIdentity
        if amount > 0.01 {
            let angle = atan2(velocity.y, velocity.x)
            transform = CATransform3DMakeRotation(angle, 0.0, 0.0, 1.0)
            transform = CATransform3DScale(transform, 1.0 + amount, 1.0 - amount * 0.75, 1.0)
            transform = CATransform3DRotate(transform, -angle, 0.0, 0.0, 1.0)
        }
        if animated {
            let previous = self.bubbleLayer.presentation()?.transform ?? self.bubbleLayer.transform
            let animation = CASpringAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: previous)
            animation.toValue = NSValue(caTransform3D: transform)
            animation.mass = 1.0
            animation.stiffness = 260.0
            animation.damping = 9.0
            animation.duration = animation.settlingDuration
            self.bubbleLayer.add(animation, forKey: "ghost.stretch")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.bubbleLayer.transform = transform
        CATransaction.commit()
    }

    func setInteracting(_ value: Bool) {
        self.particleTimer?.invalidate()
        self.particleTimer = nil
        if value {
            self.spawnParticle()
            let timer = Foundation.Timer(timeInterval: 0.11, repeats: true, block: { [weak self] _ in
                self?.spawnParticle()
            })
            RunLoop.main.add(timer, forMode: .common)
            self.particleTimer = timer
        }
    }

    private func spawnParticle() {
        guard let file = self.patternFile else { return }
        let bounds = self.particleContainer.bounds
        guard bounds.width > 1.0 else { return }
        let side = CGFloat.random(in: 5.0 ..< 9.0)
        let particle = InlineStickerItemLayer(
            context: .account(self.context),
            userLocation: .other,
            attemptSynchronousLoad: false,
            emoji: ChatTextInputTextCustomEmojiAttribute(interactivelySelectedFromPackId: nil, fileId: file.fileId.id, file: file),
            file: file,
            cache: self.context.animationCache,
            renderer: self.context.animationRenderer,
            unique: false,
            placeholderColor: .clear,
            pointSize: CGSize(width: 24.0, height: 24.0),
            dynamicColor: self.patternColor.withAlphaComponent(0.85)
        )
        let x = CGFloat.random(in: side ..< max(side + 1.0, bounds.width - side))
        let from = CGPoint(x: x, y: -side)
        let to = CGPoint(x: x + CGFloat.random(in: -6.0 ..< 6.0), y: bounds.height + side)
        particle.bounds = CGRect(origin: .zero, size: CGSize(width: side, height: side))
        particle.position = to
        particle.transform = CATransform3DMakeRotation(CGFloat.random(in: -0.6 ..< 0.6), 0.0, 0.0, 1.0)
        self.particleContainer.addSublayer(particle)
        particle.animatePosition(from: from, to: to, duration: Double.random(in: 0.9 ..< 1.4), timingFunction: CAMediaTimingFunctionName.easeIn.rawValue, removeOnCompletion: false, completion: { [weak particle] _ in
            particle?.removeFromSuperlayer()
        })
    }

    override init(layer: Any) {
        guard let layer = layer as? GiftIconLayer else {
            fatalError()
        }

        let context = layer.context
        let gift = layer.gift
        let size = layer.size
        let glowing = layer.glowing

        var file: TelegramMediaFile?
        var color: UIColor = .white
        switch gift.gift {
        case let .generic(gift):
            file = gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, fileValue, _, _) = attribute {
                    file = fileValue
                } else if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
                    color = UIColor(rgb: UInt32(bitPattern: innerColor))
                }
            }
        }

        let emoji = ChatTextInputTextCustomEmojiAttribute(
            interactivelySelectedFromPackId: nil,
            fileId: file?.fileId.id ?? 0,
            file: file
        )
        self.animationLayer = InlineStickerItemLayer(
            context: .account(context),
            userLocation: .other,
            attemptSynchronousLoad: false,
            emoji: emoji,
            file: file,
            cache: context.animationCache,
            renderer: context.animationRenderer,
            unique: true,
            placeholderColor: UIColor.white.withAlphaComponent(0.2),
            pointSize: CGSize(width: size.width * 2.0, height: size.height * 2.0),
            loopCount: 1
        )

        self.shadowLayer.contents = shadowImage?.cgImage
        self.shadowLayer.layerTintColor = color.cgColor
        self.shadowLayer.opacity = glowing ? 1.0 : 0.0

        self.context = context
        self.gift = gift
        self.size = size
        self.glowing = glowing

        super.init()

        let side = floor(size.width * 1.25)
        let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: size))
        self.starsLayer.frame = starsFrame
        self.starsLayer.update(color: glowing ? .white : color, size: starsFrame.size)

        self.addSublayer(self.shadowLayer)
        self.addSublayer(self.starsLayer)
        self.addSublayer(self.animationLayer)
    }

    init(
        context: AccountContext,
        gift: ProfileGiftsContext.State.StarGift,
        size: CGSize,
        glowing: Bool
    ) {
        self.context = context
        self.gift = gift
        self.size = size
        self.glowing = glowing

        var file: TelegramMediaFile?
        var color: UIColor = .white
        switch gift.gift {
        case let .generic(gift):
            file = gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, fileValue, _, _) = attribute {
                    file = fileValue
                } else if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
                    color = UIColor(rgb: UInt32(bitPattern: innerColor))
                }
            }
        }

        let emoji = ChatTextInputTextCustomEmojiAttribute(
            interactivelySelectedFromPackId: nil,
            fileId: file?.fileId.id ?? 0,
            file: file
        )
        self.animationLayer = InlineStickerItemLayer(
            context: .account(context),
            userLocation: .other,
            attemptSynchronousLoad: false,
            emoji: emoji,
            file: file,
            cache: context.animationCache,
            renderer: context.animationRenderer,
            unique: true,
            placeholderColor: UIColor.white.withAlphaComponent(0.2),
            pointSize: CGSize(width: size.width * 2.0, height: size.height * 2.0),
            loopCount: 1
        )

        self.shadowLayer.contents = shadowImage?.cgImage
        self.shadowLayer.layerTintColor = color.cgColor
        self.shadowLayer.opacity = glowing ? 1.0 : 0.0

        super.init()

        let side = floor(size.width * 1.25)
        let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: size))
        self.starsLayer.frame = starsFrame
        self.starsLayer.update(color: glowing ? .white : color, size: starsFrame.size)

        self.addSublayer(self.shadowLayer)
        self.addSublayer(self.starsLayer)
        self.addSublayer(self.animationLayer)
        self.setupBubble(color: color)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.particleTimer?.invalidate()
    }

    override func layoutSublayers() {
        self.shadowLayer.frame = CGRect(origin: .zero, size: self.bounds.size).insetBy(dx: -8.0, dy: -8.0)
        let bubbleFrame = CGRect(origin: .zero, size: self.bounds.size).insetBy(dx: -8.0, dy: -8.0)
        self.bubbleLayer.frame = bubbleFrame
        self.bubbleLayer.cornerRadius = bubbleFrame.width / 2.0
        self.bubbleShineLayer.frame = CGRect(origin: .zero, size: bubbleFrame.size)
        self.bubbleTintLayer.frame = CGRect(origin: .zero, size: bubbleFrame.size)
        self.particleContainer.frame = CGRect(origin: .zero, size: bubbleFrame.size)
        self.bubbleBackdropLayer?.frame = CGRect(origin: .zero, size: bubbleFrame.size)
        self.animationLayer.bounds = CGRect(origin: .zero, size: self.bounds.size)
        self.animationLayer.position = CGPoint(x: self.bounds.width / 2.0, y: self.bounds.height / 2.0)
    }

    func updateRotation(_ angle: CGFloat, transition: ComponentTransition) {
        self.animationLayer.transform = CATransform3DMakeRotation(angle, 0.0, 0.0, 1.0)
    }

    func startAnimations(index: Int) {
        if GhostSettings.profileV2, self.bubbleLayer.superlayer != nil, self.bubbleLayer.animation(forKey: "ghost.wobble.transform.scale.x") == nil {
            self.addWobble()
        }
        let beginTime = Double(index) * 1.5

        if self.animation(forKey: "hover") == nil {
            let upDistance = CGFloat.random(in: 1.0 ..< 2.0)
            let downDistance = CGFloat.random(in: 1.0 ..< 2.0)
            let hoverDuration = TimeInterval.random(in: 3.5 ..< 4.5)
            let hoverAnimation = CABasicAnimation(keyPath: "transform.translation.y")
            hoverAnimation.duration = hoverDuration
            hoverAnimation.fromValue = -upDistance
            hoverAnimation.toValue = downDistance
            hoverAnimation.autoreverses = true
            hoverAnimation.repeatCount = .infinity
            hoverAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hoverAnimation.beginTime = beginTime
            hoverAnimation.isAdditive = true
            self.add(hoverAnimation, forKey: "hover")
        }

        if self.animationLayer.animation(forKey: "wiggle") == nil {
            let fromRotationAngle = CGFloat.random(in: 0.025 ..< 0.05)
            let toRotationAngle = CGFloat.random(in: 0.025 ..< 0.05)
            let wiggleDuration = TimeInterval.random(in: 2.0 ..< 3.0)
            let wiggleAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
            wiggleAnimation.duration = wiggleDuration
            wiggleAnimation.fromValue = -fromRotationAngle
            wiggleAnimation.toValue = toRotationAngle
            wiggleAnimation.autoreverses = true
            wiggleAnimation.repeatCount = .infinity
            wiggleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wiggleAnimation.beginTime = beginTime
            wiggleAnimation.isAdditive = true
            self.animationLayer.add(wiggleAnimation, forKey: "wiggle")
        }

        if self.shadowLayer.animation(forKey: "glow") == nil {
            let glowDuration = TimeInterval.random(in: 2.0 ..< 3.0)
            let glowAnimation = CABasicAnimation(keyPath: "transform.scale")
            glowAnimation.duration = glowDuration
            glowAnimation.fromValue = 1.0
            glowAnimation.toValue = 1.2
            glowAnimation.autoreverses = true
            glowAnimation.repeatCount = .infinity
            glowAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowAnimation.beginTime = beginTime
            self.shadowLayer.add(glowAnimation, forKey: "glow")
        }
    }

    func stopAnimations() {
        self.removeAnimation(forKey: "hover")
        self.animationLayer.removeAnimation(forKey: "wiggle")
        self.shadowLayer.removeAnimation(forKey: "glow")
        self.bubbleLayer.removeAnimation(forKey: "ghost.wobble.transform.scale.x")
        self.bubbleLayer.removeAnimation(forKey: "ghost.wobble.transform.scale.y")
        self.particleTimer?.invalidate()
        self.particleTimer = nil
    }
}

private struct PositionGenerator {
    struct Position {
        let distance: CGFloat
        let angle: CGFloat
        let scale: CGFloat

        var relativeCartesian: CGPoint {
            return CGPoint(
                x: self.distance * cos(self.angle),
                y: self.distance * sin(self.angle)
            )
        }
    }

    let containerSize: CGSize
    let centerFrame: CGRect
    let exclusionZones: [CGRect]
    let minimumDistance: CGFloat
    let edgePadding: CGFloat
    let scaleRange: (min: CGFloat, max: CGFloat)
    let innerOrbitRange: (min: CGFloat, max: CGFloat)
    let outerOrbitRange: (min: CGFloat, max: CGFloat)
    let innerOrbitCount: Int

    private let lokiRng: LokiRng

    init(
        containerSize: CGSize,
        centerFrame: CGRect,
        exclusionZones: [CGRect],
        minimumDistance: CGFloat,
        edgePadding: CGFloat,
        seed: UInt,
        scaleRange: (min: CGFloat, max: CGFloat) = (0.7, 1.15),
        innerOrbitRange: (min: CGFloat, max: CGFloat) = (1.4, 2.2),
        outerOrbitRange: (min: CGFloat, max: CGFloat) = (2.5, 3.6),
        innerOrbitCount: Int = 4
    ) {
        self.containerSize = containerSize
        self.centerFrame = centerFrame
        self.exclusionZones = exclusionZones
        self.minimumDistance = minimumDistance
        self.edgePadding = edgePadding
        self.scaleRange = scaleRange
        self.innerOrbitRange = innerOrbitRange
        self.outerOrbitRange = outerOrbitRange
        self.innerOrbitCount = innerOrbitCount
        self.lokiRng = LokiRng(seed0: seed, seed1: 0, seed2: 0)
    }

    func generatePositions(count: Int, itemSize: CGSize) -> [Position] {
        var positions: [Position] = []
        let centerPoint = CGPoint(x: self.centerFrame.midX, y: self.centerFrame.midY)
        let centerRadius = min(self.centerFrame.width, self.centerFrame.height) / 2.0
        let maxAttempts = count * 200
        var attempts = 0
        var leftPositions = 0
        var rightPositions = 0
        let innerCount = min(self.innerOrbitCount, count)

        while positions.count < innerCount && attempts < maxAttempts {
            attempts += 1
            let placeOnLeftSide = rightPositions > leftPositions
            let orbitRangeSize = self.innerOrbitRange.max - self.innerOrbitRange.min
            let distance = (self.innerOrbitRange.min + orbitRangeSize * CGFloat(self.lokiRng.next())) * centerRadius
            let angleOffset: CGFloat = placeOnLeftSide ? .pi/2 : -(.pi/2)
            let angle = angleOffset + CGFloat.pi * CGFloat(self.lokiRng.next())
            let absolutePosition = getAbsolutePosition(distance: distance, angle: angle, centerPoint: centerPoint)

            if absolutePosition.x - itemSize.width/2 < self.edgePadding ||
                absolutePosition.x + itemSize.width/2 > self.containerSize.width - self.edgePadding ||
                absolutePosition.y - itemSize.height/2 < self.edgePadding ||
                absolutePosition.y + itemSize.height/2 > self.containerSize.height - self.edgePadding {
                continue
            }
            let itemRect = CGRect(
                x: absolutePosition.x - itemSize.width/2,
                y: absolutePosition.y - itemSize.height/2,
                width: itemSize.width,
                height: itemSize.height
            )
            if self.isValidPosition(itemRect, existingPositions: positions.map {
                getAbsolutePosition(distance: $0.distance, angle: $0.angle, centerPoint: centerPoint)
            }, itemSize: itemSize) {
                let scaleRangeSize = max(self.scaleRange.min + 0.1, 0.75) - self.scaleRange.max
                let scale = self.scaleRange.max + scaleRangeSize * CGFloat(self.lokiRng.next())
                positions.append(Position(distance: distance, angle: angle, scale: scale))
                if absolutePosition.x < centerPoint.x {
                    leftPositions += 1
                } else {
                    rightPositions += 1
                }
            }
        }

        let maxPossibleDistance = hypot(self.containerSize.width, self.containerSize.height) / 2
        while positions.count < count && attempts < maxAttempts {
            attempts += 1
            let placeOnLeftSide = rightPositions >= leftPositions
            let orbitRangeSize = self.outerOrbitRange.max - self.outerOrbitRange.min
            let distance = (self.outerOrbitRange.min + orbitRangeSize * CGFloat(self.lokiRng.next())) * centerRadius
            let angleOffset: CGFloat = placeOnLeftSide ? .pi/2 : -(.pi/2)
            let angle = angleOffset + CGFloat.pi * CGFloat(self.lokiRng.next())
            let absolutePosition = getAbsolutePosition(distance: distance, angle: angle, centerPoint: centerPoint)
            if absolutePosition.x - itemSize.width/2 < self.edgePadding ||
                absolutePosition.x + itemSize.width/2 > self.containerSize.width - self.edgePadding ||
                absolutePosition.y - itemSize.height/2 < self.edgePadding ||
                absolutePosition.y + itemSize.height/2 > self.containerSize.height - self.edgePadding {
                continue
            }
            let itemRect = CGRect(
                x: absolutePosition.x - itemSize.width/2,
                y: absolutePosition.y - itemSize.height/2,
                width: itemSize.width,
                height: itemSize.height
            )
            if self.isValidPosition(itemRect, existingPositions: positions.map {
                getAbsolutePosition(distance: $0.distance, angle: $0.angle, centerPoint: centerPoint)
            }, itemSize: itemSize) {
                let normalizedDistance = min(distance / maxPossibleDistance, 1.0)
                let scale = self.scaleRange.max - normalizedDistance * (self.scaleRange.max - self.scaleRange.min)
                positions.append(Position(distance: distance, angle: angle, scale: scale))
                if absolutePosition.x < centerPoint.x {
                    leftPositions += 1
                } else {
                    rightPositions += 1
                }
            }
        }
        return positions
    }

    func getAbsolutePosition(distance: CGFloat, angle: CGFloat, centerPoint: CGPoint) -> CGPoint {
        return CGPoint(
            x: centerPoint.x + distance * cos(angle),
            y: centerPoint.y + distance * sin(angle)
        )
    }

    private func isValidPosition(_ rect: CGRect, existingPositions: [CGPoint], itemSize: CGSize) -> Bool {
        if rect.minX < self.edgePadding || rect.maxX > self.containerSize.width - self.edgePadding ||
            rect.minY < self.edgePadding || rect.maxY > self.containerSize.height - self.edgePadding {
            return false
        }
        for zone in self.exclusionZones {
            if rect.intersects(zone) {
                return false
            }
        }
        let effectiveMinDistance = existingPositions.count > 5 ? max(self.minimumDistance * 0.7, 10.0) : self.minimumDistance
        for existingPosition in existingPositions {
            let distance = hypot(existingPosition.x - rect.midX, existingPosition.y - rect.midY)
            if distance < effectiveMinDistance {
                return false
            }
        }
        return true
    }
}

private func getAbsolutePosition(position: PositionGenerator.Position, centerPoint: CGPoint) -> CGPoint {
    return CGPoint(
        x: centerPoint.x + position.distance * cos(position.angle),
        y: centerPoint.y + position.distance * sin(position.angle)
    )
}

private func getAbsolutePosition(distance: CGFloat, angle: CGFloat, centerPoint: CGPoint) -> CGPoint {
    return CGPoint(
        x: centerPoint.x + distance * cos(angle),
        y: centerPoint.y + distance * sin(angle)
    )
}

private func windowFunction(t: CGFloat) -> CGFloat {
    return bezierPoint(0.6, 0.0, 0.4, 1.0, t)
}

private func patternScaleValueAt(fraction: CGFloat, t: CGFloat, reverse: Bool) -> CGFloat {
    let windowSize: CGFloat = 0.8
    let effectiveT: CGFloat
    let windowStartOffset: CGFloat
    let windowEndOffset: CGFloat
    if reverse {
        effectiveT = 1.0 - t
        windowStartOffset = 1.0
        windowEndOffset = -windowSize
    } else {
        effectiveT = t
        windowStartOffset = -windowSize
        windowEndOffset = 1.0
    }
    let windowPosition = (1.0 - fraction) * windowStartOffset + fraction * windowEndOffset
    let windowT = max(0.0, min(windowSize, effectiveT - windowPosition)) / windowSize
    return 1.0 - windowFunction(t: windowT)
}

private final class GiftAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        return self.activate?() ?? false
    }
}
