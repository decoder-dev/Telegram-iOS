import Foundation
import UIKit

/// Fork (Extras › Appearance › Motion): iMessage-like motion for chat bubbles. The switches live in
/// ForkExtrasSettings and reach the chat through ArenaSettings; the callers check them and pass the result
/// in, so this file knows nothing about settings. Nothing here moves with Reduce Motion.
public enum ChatBubbleMotion {
    public static var allowsMotion: Bool {
        return !UIAccessibility.isReduceMotionEnabled
    }

    private static var lastHapticTimestamp: Double = 0.0
    private static var sentGenerator: UIImpactFeedbackGenerator?
    private static var receivedGenerator: UIImpactFeedbackGenerator?

    /// A light tap as a sent message takes off. At most one tap every 0.25 s, so an album or a burst of
    /// incoming messages is felt once.
    public static func sentHaptic() {
        guard Thread.isMainThread, self.takeHapticSlot() else {
            return
        }
        let generator = self.sentGenerator ?? UIImpactFeedbackGenerator(style: .light)
        self.sentGenerator = generator
        generator.impactOccurred(intensity: 0.7)
    }

    /// A softer tap when a message arrives in the open chat.
    public static func receivedHaptic() {
        guard Thread.isMainThread, self.takeHapticSlot() else {
            return
        }
        let generator = self.receivedGenerator ?? UIImpactFeedbackGenerator(style: .soft)
        self.receivedGenerator = generator
        generator.impactOccurred(intensity: 0.55)
    }

    private static func takeHapticSlot() -> Bool {
        let timestamp = CACurrentMediaTime()
        if timestamp - self.lastHapticTimestamp < 0.25 {
            return false
        }
        self.lastHapticTimestamp = timestamp
        return true
    }

    /// A new message springs in from its tail: `layer` is the bubble's container, `anchor` the tail corner in
    /// the container's coordinates. The scale overshoots a little and settles, as in Messages.
    public static func popIn(layer: CALayer, anchor: CGPoint) {
        guard self.allowsMotion else {
            return
        }
        let bounds = layer.bounds
        if bounds.width < 1.0 || bounds.height < 1.0 {
            return
        }
        let initialScale: CGFloat = 0.55
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // Scaling about the centre moves the anchor by (anchor - centre) * (1 - scale); the additive offset
        // undoes that, so the tail stays where it is while the bubble grows out of it.
        let offset = CGPoint(x: (anchor.x - center.x) * (1.0 - initialScale), y: (anchor.y - center.y) * (1.0 - initialScale))
        layer.animateSpring(from: initialScale as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.55, stiffness: 320.0, damping: 17.0, key: "forkPopInScale")
        layer.animateSpring(from: NSValue(cgPoint: offset), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.55, stiffness: 320.0, damping: 17.0, additive: true, key: "forkPopInPosition")
        layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.12)
    }

    /// A sent message lands with a small squash: it is pressed down a little and springs back, its bottom
    /// edge staying in place.
    public static func landingSquash(layer: CALayer) {
        guard self.allowsMotion else {
            return
        }
        let height = layer.bounds.height
        if height < 1.0 {
            return
        }
        let scaleY: CGFloat = 0.93
        let squash = CATransform3DConcat(CATransform3DMakeScale(1.0, scaleY, 1.0), CATransform3DMakeTranslation(0.0, height * (1.0 - scaleY) / 2.0, 0.0))
        layer.animateSpring(from: NSValue(caTransform3D: squash), to: NSValue(caTransform3D: CATransform3DIdentity), keyPath: "transform", duration: 0.5, stiffness: 420.0, damping: 15.0, key: "forkLandingSquash")
    }
}

/// Springy scrolling: while the history is dragged, each bubble trails the finger by an amount that grows with
/// its distance from the touch, then catches up on a spring — the bubbles look loosely connected, as in
/// Messages. The offsets are drawn with the item nodes' `sublayerTransform` on top of the transform the item
/// had when it started trailing (selection mode shifts items with it), so layout and hit areas are unaffected.
public final class ChatSpringyScrollController {
    private final class ItemState {
        weak var layer: CALayer?
        let baseTransform: CATransform3D
        var offset: CGFloat = 0.0
        var velocity: CGFloat = 0.0

        init(layer: CALayer) {
            self.layer = layer
            self.baseTransform = layer.sublayerTransform
        }
    }

    private let itemsAreRotated: Bool
    private var states: [ObjectIdentifier: ItemState] = [:]
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0.0
    private var anchorY: CGFloat?

    /// Trailing per point of scrolling grows by this much per point of distance from the touch.
    private let resistance: CGFloat = 1.0 / 1300.0
    private let maxOffset: CGFloat = 34.0
    private let stiffness: CGFloat = 250.0
    private let damping: CGFloat = 23.0

    /// `itemsAreRotated`: the items are flipped inside a flipped list (the chat history), so a drawn offset
    /// in the list's coordinates is the opposite offset in the item's own.
    public init(itemsAreRotated: Bool) {
        self.itemsAreRotated = itemsAreRotated
    }

    deinit {
        self.displayLink?.invalidate()
    }

    /// The touch that started the drag, in the list's coordinates.
    public func beganDragging(touchY: CGFloat) {
        self.anchorY = touchY
    }

    /// The content moved by `movement` points in the list's coordinates (every item's frame moved by it).
    /// `items` are the visible item layers with their centres in the same coordinates.
    public func contentMoved(by movement: CGFloat, items: [(layer: CALayer, centerY: CGFloat)]) {
        guard ChatBubbleMotion.allowsMotion, movement != 0.0, abs(movement) < 300.0, var anchorY = self.anchorY else {
            return
        }
        // The finger moves with the content while it drags; after it lifts, the point it left keeps moving too.
        anchorY += movement
        self.anchorY = anchorY
        for (layer, centerY) in items {
            let key = ObjectIdentifier(layer)
            let state: ItemState
            if let current = self.states[key], current.layer === layer {
                state = current
            } else {
                state = ItemState(layer: layer)
                self.states[key] = state
            }
            let distance = abs(centerY - anchorY)
            // The item lags: it is drawn a little behind where the content has taken it.
            state.offset -= movement * min(0.9, distance * self.resistance)
            state.offset = max(-self.maxOffset, min(self.maxOffset, state.offset))
        }
        self.startDisplayLinkIfNeeded()
        self.apply()
    }

    /// Puts every item back at once (the list jumped or reloaded, or the setting went off).
    public func reset() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (_, state) in self.states {
            state.layer?.sublayerTransform = state.baseTransform
        }
        CATransaction.commit()
        self.states.removeAll()
        self.displayLink?.invalidate()
        self.displayLink = nil
    }

    private func startDisplayLinkIfNeeded() {
        if self.displayLink != nil {
            return
        }
        let displayLink = CADisplayLink(target: ChatBubbleMotionDisplayLinkTarget { [weak self] link in
            self?.step(link)
        }, selector: #selector(ChatBubbleMotionDisplayLinkTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: 120.0, preferred: 120.0)
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        self.lastTimestamp = 0.0
    }

    private func step(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        var dt = self.lastTimestamp == 0.0 ? (1.0 / 60.0) : (timestamp - self.lastTimestamp)
        self.lastTimestamp = timestamp
        dt = min(max(dt, 1.0 / 240.0), 1.0 / 30.0)

        var isMoving = false
        for (key, state) in self.states {
            if state.layer == nil {
                self.states.removeValue(forKey: key)
                continue
            }
            // A damped spring towards zero, integrated in small steps so it stays stable at 120 Hz.
            let substeps = 4
            let h = CGFloat(dt) / CGFloat(substeps)
            for _ in 0 ..< substeps {
                let acceleration = -self.stiffness * state.offset - self.damping * state.velocity
                state.velocity += acceleration * h
                state.offset += state.velocity * h
            }
            if abs(state.offset) < 0.05 && abs(state.velocity) < 0.5 {
                state.offset = 0.0
                state.velocity = 0.0
            } else {
                isMoving = true
            }
        }
        if isMoving {
            self.apply()
        } else {
            self.reset()
        }
    }

    private func apply() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (_, state) in self.states {
            let offset = self.itemsAreRotated ? -state.offset : state.offset
            state.layer?.sublayerTransform = CATransform3DTranslate(state.baseTransform, 0.0, offset, 0.0)
        }
        CATransaction.commit()
    }
}

private final class ChatBubbleMotionDisplayLinkTarget: NSObject {
    private let action: (CADisplayLink) -> Void

    init(_ action: @escaping (CADisplayLink) -> Void) {
        self.action = action
    }

    @objc func tick(_ link: CADisplayLink) {
        self.action(link)
    }
}
