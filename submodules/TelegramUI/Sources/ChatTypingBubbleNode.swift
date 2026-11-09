import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import TelegramPresentationData

/// The Messages look: while the other side types, a grey incoming bubble with three bouncing dots sits where the
/// reply will appear, under the newest message. ChatControllerNode makes room for it at the bottom of the history,
/// moves it with the history while it scrolls, and shows and hides it. With Reduce Motion the dots stand still.
final class ChatTypingBubbleNode: ASDisplayNode {
    static let size = CGSize(width: 64.0, height: 38.0)
    /// The space the history leaves for it under the newest message.
    static let reservedHeight: CGFloat = 46.0

    private let bubbleNode: ASImageNode
    private let tailLargeNode: ASImageNode
    private let tailSmallNode: ASImageNode
    private var dotLayers: [CALayer] = []
    private var currentFillColor: UIColor?
    private var currentDotColor: UIColor?

    override init() {
        self.bubbleNode = ASImageNode()
        self.bubbleNode.displaysAsynchronously = false
        self.bubbleNode.isLayerBacked = true
        self.tailLargeNode = ASImageNode()
        self.tailLargeNode.displaysAsynchronously = false
        self.tailLargeNode.isLayerBacked = true
        self.tailSmallNode = ASImageNode()
        self.tailSmallNode.displaysAsynchronously = false
        self.tailSmallNode.isLayerBacked = true

        super.init()

        self.isUserInteractionEnabled = false
        self.addSubnode(self.tailSmallNode)
        self.addSubnode(self.tailLargeNode)
        self.addSubnode(self.bubbleNode)
        for _ in 0 ..< 3 {
            let dot = CALayer()
            dot.cornerRadius = 4.5
            self.layer.addSublayer(dot)
            self.dotLayers.append(dot)
        }
        self.isAccessibilityElement = true
        self.accessibilityTraits = [.staticText]
    }

    func update(theme: PresentationTheme, wallpaper: TelegramWallpaper, accessibilityLabel: String) {
        let bubble = theme.chat.message.incoming.bubble
        let fill = (wallpaper.hasWallpaper ? bubble.withWallpaper.fill : bubble.withoutWallpaper.fill).first ?? UIColor(rgb: 0xE9E9EB)
        let dotColor = theme.chat.message.incoming.secondaryTextColor.withMultipliedAlpha(0.8)
        if self.currentFillColor != fill {
            self.currentFillColor = fill
            self.bubbleNode.image = generateStretchableFilledCircleImage(diameter: ChatTypingBubbleNode.size.height, color: fill)
            self.tailLargeNode.image = generateFilledCircleImage(diameter: 12.0, color: fill)
            self.tailSmallNode.image = generateFilledCircleImage(diameter: 6.0, color: fill)
        }
        if self.currentDotColor != dotColor {
            self.currentDotColor = dotColor
            for dot in self.dotLayers {
                dot.backgroundColor = dotColor.cgColor
            }
        }
        self.accessibilityLabel = accessibilityLabel
    }

    func updateBubbleLayout() -> CGSize {
        let size = ChatTypingBubbleNode.size
        // The bubble sits a little right of the tail circles, which trail off its lower-left corner as in Messages.
        let bubbleFrame = CGRect(origin: CGPoint(x: 6.0, y: 0.0), size: size)
        self.bubbleNode.frame = bubbleFrame
        self.tailLargeNode.frame = CGRect(origin: CGPoint(x: bubbleFrame.minX - 1.0, y: bubbleFrame.maxY - 10.0), size: CGSize(width: 12.0, height: 12.0))
        self.tailSmallNode.frame = CGRect(origin: CGPoint(x: bubbleFrame.minX - 6.0, y: bubbleFrame.maxY - 1.0), size: CGSize(width: 6.0, height: 6.0))
        let dotSize: CGFloat = 9.0
        let spacing: CGFloat = 5.0
        let dotsWidth = dotSize * 3.0 + spacing * 2.0
        var x = bubbleFrame.minX + floor((size.width - dotsWidth) / 2.0)
        for dot in self.dotLayers {
            dot.frame = CGRect(origin: CGPoint(x: x, y: bubbleFrame.minY + floor((size.height - dotSize) / 2.0)), size: CGSize(width: dotSize, height: dotSize))
            x += dotSize + spacing
        }
        return CGSize(width: bubbleFrame.maxX, height: bubbleFrame.maxY + 5.0)
    }

    /// The dots rise and brighten one after another, forever, as in Messages.
    private func startDots() {
        guard ChatBubbleMotion.allowsMotion else {
            for dot in self.dotLayers {
                dot.removeAllAnimations()
                dot.opacity = 1.0
            }
            return
        }
        let period: CFTimeInterval = 1.2
        for (index, dot) in self.dotLayers.enumerated() {
            if dot.animation(forKey: "typing") != nil {
                continue
            }
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.45, 1.0, 0.45, 0.45]
            opacity.keyTimes = [0.0, 0.25, 0.5, 1.0]
            let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
            lift.values = [0.0, -3.0, 0.0, 0.0]
            lift.keyTimes = [0.0, 0.25, 0.5, 1.0]
            let group = CAAnimationGroup()
            group.animations = [opacity, lift]
            group.duration = period
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            group.fillMode = .backwards
            group.isRemovedOnCompletion = false
            dot.add(group, forKey: "typing")
        }
    }

    private func stopDots() {
        for dot in self.dotLayers {
            dot.removeAnimation(forKey: "typing")
        }
    }

    /// Grows out of its tail with a little overshoot.
    func animateIn() {
        self.startDots()
        guard ChatBubbleMotion.allowsMotion else {
            self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            return
        }
        let size = self.bounds.size
        let anchor = CGPoint(x: 0.0, y: size.height)
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let scale: CGFloat = 0.3
        self.layer.animateSpring(from: scale as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.5, stiffness: 340.0, damping: 18.0)
        self.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: (anchor.x - center.x) * (1.0 - scale), y: (anchor.y - center.y) * (1.0 - scale))), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, stiffness: 340.0, damping: 18.0, additive: true)
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
    }

    /// Shrinks back into its tail and calls `completion` when it is gone.
    func animateOut(completion: @escaping () -> Void) {
        self.stopDots()
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false, completion: { _ in
            completion()
        })
        if ChatBubbleMotion.allowsMotion {
            self.layer.animateScale(from: 1.0, to: 0.4, duration: 0.18, removeOnCompletion: false)
        }
    }

    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        // Animations are dropped while the node is off screen (another tab, the app in the background).
        if self.alpha > 0.0 {
            self.startDots()
        }
    }
}
