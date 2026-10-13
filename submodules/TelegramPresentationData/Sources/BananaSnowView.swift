import Foundation
import UIKit
import SwiftSignalKit

public enum BananaSnowSettings {
    public static let didChangeNotification = Notification.Name("BananaSnowSettings.didChange")
    private static let state = Atomic<Bool>(value: false)
    public static var enabled: Bool {
        get { state.with { $0 } }
        set {
            let previous = state.swap(newValue)
            if previous != newValue { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
        }
    }
}

/// Falling snow behind the Extras ▸ Profile and effects ▸ Snow toggle (`BananaSnowSettings.enabled`).
/// Adapted from Donutgram's `DGSnowView` (kittenello/Donutgram, `DGSnowEffect`).
///
/// It snows only while the toggle is on, the app is in the foreground and the view is in a window;
/// otherwise the view holds no flakes and no timer, so hosts keep it installed permanently. The parent
/// owns the frame, and the view never takes touches.
///
/// Every flake is a `CALayer` that Core Animation moves along a precomputed path, so the main thread
/// only works when flakes are born, a few times a second. Flakes can be born mid-flight, which lets
/// the snow fill the view at once whenever it (re)starts. The look follows Telegram Desktop's
/// `Ui::Snowflakes`: round dots and six-armed flakes.
public final class BananaSnowView: UIView {
    private struct Flake {
        let layer: CALayer
        let isSnowflake: Bool
        let deathTime: Double
    }

    private struct Sprites {
        let dot: CGImage?
        let snowflake: CGImage?
    }

    private static let tickInterval: Double = 0.2
    /// Flakes born per second per point of width: about 50 in the air on a phone.
    private static let birthRatePerPoint: Double = 1.0 / 140.0
    /// After a longer pause between ticks (a stalled main thread) the snow is laid out anew instead of
    /// being caught up birth by birth.
    private static let maxTickGap: Double = 2.0
    private static let keyframeInterval: Double = 0.5
    private static let snowflakeShare: Double = 0.4
    private static let minSpeed: Double = 28.0
    private static let maxSpeed: Double = 72.0
    private static let maxSide: CGFloat = 14.0

    private var isDark = false
    private var isInBackground = false
    private var sprites: Sprites?
    private var flakes: [Flake] = []
    /// The size the paths of the flakes in the air were laid out for.
    private var flakesSize = CGSize()
    private var timer: SwiftSignalKit.Timer?
    private var lastTickTime: Double = 0.0
    private var pendingBirths: Double = 0.0
    private var observers: [NSObjectProtocol] = []

    override public init(frame: CGRect) {
        super.init(frame: frame)

        self.isOpaque = false
        self.isUserInteractionEnabled = false
        self.accessibilityElementsHidden = true
        self.clipsToBounds = true

        let notificationCenter = NotificationCenter.default
        self.observers.append(notificationCenter.addObserver(forName: BananaSnowSettings.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateIsRunning()
        }))
        // Core Animation drops running animations when the app leaves the foreground, so the snow stops
        // there and is laid out again on return.
        self.observers.append(notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.isInBackground = true
            self?.updateIsRunning()
        }))
        self.observers.append(notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.isInBackground = false
            self?.updateIsRunning()
        }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.timer?.invalidate()
    }

    /// White flakes over dark content, soft blue ones over light content.
    public func update(isDark: Bool) {
        if self.isDark == isDark {
            return
        }
        self.isDark = isDark
        self.sprites = nil

        if self.flakes.isEmpty {
            return
        }
        let sprites = self.currentSprites()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for flake in self.flakes {
            flake.layer.contents = flake.isSnowflake ? sprites.snowflake : sprites.dot
        }
        CATransaction.commit()
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()

        self.updateIsRunning()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        self.updateIsRunning()
    }

    private var birthRate: Double {
        return Double(self.bounds.width) * BananaSnowView.birthRatePerPoint
    }

    private func updateIsRunning() {
        let shouldRun = self.window != nil && !self.isInBackground && !self.bounds.isEmpty && BananaSnowSettings.enabled
        if shouldRun {
            if self.timer == nil {
                let timer = SwiftSignalKit.Timer(timeout: BananaSnowView.tickInterval, repeat: true, completion: { [weak self] in
                    self?.tick()
                }, queue: Queue.mainQueue())
                self.timer = timer
                timer.start()
                self.refill()
            } else if self.flakesSize != self.bounds.size {
                // The flakes in the air follow paths laid out for the old size (rotation, iPad split view).
                self.refill()
            }
        } else if let timer = self.timer {
            timer.invalidate()
            self.timer = nil
            self.removeFlakes(where: { _ in true })
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = now - self.lastTickTime
        if elapsed > BananaSnowView.maxTickGap {
            self.refill()
            return
        }
        self.lastTickTime = now

        self.removeFlakes(where: { $0.deathTime <= now })

        self.pendingBirths += self.birthRate * elapsed
        if self.pendingBirths < 1.0 {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while self.pendingBirths >= 1.0 {
            self.pendingBirths -= 1.0
            // Births are spread over the elapsed interval so that flakes don't fall in step.
            self.addFlake(now: now, age: Double.random(in: 0.0 ... max(0.0, elapsed)))
        }
        CATransaction.commit()
    }

    /// Replaces the flakes with the ones that would be in the air had it been snowing all along.
    private func refill() {
        let now = CACurrentMediaTime()
        self.removeFlakes(where: { _ in true })
        self.flakesSize = self.bounds.size
        self.lastTickTime = now
        self.pendingBirths = 0.0

        // The slowest of the biggest flakes stays in the air the longest.
        let longestFall = (Double(self.bounds.height) + 2.0 * Double(BananaSnowView.maxSide)) / BananaSnowView.minSpeed + BananaSnowView.tickInterval
        let count = Int(self.birthRate * longestFall)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for _ in 0 ..< count {
            self.addFlake(now: now, age: Double.random(in: 0.0 ..< longestFall))
        }
        CATransaction.commit()
    }

    /// Adds a flake born `age` seconds ago, or nothing if it would already have left the view.
    private func addFlake(now: Double, age: Double) {
        let size = self.bounds.size
        // Nearer flakes are bigger, faster and brighter.
        let depth = Double.random(in: 0.0 ... 1.0)
        let isSnowflake = Double.random(in: 0.0 ..< 1.0) < BananaSnowView.snowflakeShare
        let side: CGFloat = isSnowflake ? (8.0 + 6.0 * CGFloat(depth)) : (2.5 + 4.0 * CGFloat(depth))
        let speed = BananaSnowView.minSpeed + (BananaSnowView.maxSpeed - BananaSnowView.minSpeed) * depth

        // A flake born up to a tick ago is still above the top edge, so new flakes never pop into view.
        let startY = -Double(side) - speed * BananaSnowView.tickInterval
        let fallDistance = Double(size.height + side) - startY
        let duration = fallDistance / speed
        if age >= duration {
            return
        }

        // Centring the slanted path on the view keeps most of the fall on screen whichever way it slants.
        let drift = Double.random(in: -0.18 ... 0.18) * fallDistance
        let startX = Double.random(in: 0.0 ... Double(size.width)) - drift / 2.0
        let swayAmplitude = (isSnowflake ? 5.0 : 3.0) + 8.0 * Double.random(in: 0.0 ... 1.0)
        let swayPeriod = Double.random(in: 3.0 ... 6.0)
        let swayPhase = Double.random(in: 0.0 ..< 2.0 * Double.pi)

        let steps = max(1, Int((duration / BananaSnowView.keyframeInterval).rounded(.up)))
        var points: [NSValue] = []
        points.reserveCapacity(steps + 1)
        var endPoint = CGPoint()
        for i in 0 ... steps {
            let progress = Double(i) / Double(steps)
            let time = duration * progress
            let x = startX + drift * progress + swayAmplitude * sin(2.0 * Double.pi * time / swayPeriod + swayPhase)
            let y = startY + fallDistance * progress
            endPoint = CGPoint(x: x, y: y)
            points.append(NSValue(cgPoint: endPoint))
        }

        let sprites = self.currentSprites()
        let flakeLayer = CALayer()
        flakeLayer.contents = isSnowflake ? sprites.snowflake : sprites.dot
        flakeLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
        // The model position is below the bottom edge, where the flake stays if its animation is cut short.
        flakeLayer.position = endPoint
        flakeLayer.opacity = Float(0.45 + 0.55 * depth)

        self.layer.addSublayer(flakeLayer)
        let beginTime = flakeLayer.convertTime(now, from: nil) - age

        // Catmull-Rom through the samples keeps the sway smooth and the fall itself linear.
        let fall = CAKeyframeAnimation(keyPath: "position")
        fall.values = points
        fall.calculationMode = .cubic
        fall.duration = duration
        fall.beginTime = beginTime
        BananaSnowView.limitFrameRate(fall)
        flakeLayer.add(fall, forKey: "fall")

        if isSnowflake {
            let startAngle = Double.random(in: 0.0 ..< 2.0 * Double.pi)
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = startAngle as NSNumber
            spin.toValue = (startAngle + Double.random(in: -0.9 ... 0.9) * duration) as NSNumber
            spin.duration = duration
            spin.beginTime = beginTime
            BananaSnowView.limitFrameRate(spin)
            flakeLayer.add(spin, forKey: "spin")
        }

        self.flakes.append(Flake(layer: flakeLayer, isSnowflake: isSnowflake, deathTime: now - age + duration))
    }

    private func removeFlakes(where predicate: (Flake) -> Bool) {
        if !self.flakes.contains(where: predicate) {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.flakes.removeAll(where: { flake in
            if predicate(flake) {
                flake.layer.removeFromSuperlayer()
                return true
            } else {
                return false
            }
        })
        CATransaction.commit()
    }

    private func currentSprites() -> Sprites {
        if let sprites = self.sprites {
            return sprites
        }
        let color: UIColor = self.isDark ? .white : UIColor(red: 0.56, green: 0.71, blue: 0.9, alpha: 1.0)
        let sprites = Sprites(dot: BananaSnowView.makeDot(color: color), snowflake: BananaSnowView.makeSnowflake(color: color))
        self.sprites = sprites
        return sprites
    }

    /// Slow snow doesn't need 120 Hz: the cap lets a ProMotion screen drop to 60 Hz while nothing else moves.
    private static func limitFrameRate(_ animation: CAAnimation) {
        if #available(iOS 15.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 60.0, preferred: 60.0)
        }
    }

    private static func makeDot(color: UIColor) -> CGImage? {
        let size = CGSize(width: 8.0, height: 8.0)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
        }.cgImage
    }

    /// Telegram Desktop's `PrepareSnowflake`: six arms, each with two short branches at two thirds of its length.
    private static func makeSnowflake(color: UIColor) -> CGImage? {
        let lineWidth: CGFloat = 1.2
        let armLength: CGFloat = 6.0
        let branchLength: CGFloat = armLength / 3.0
        let branchAngle: CGFloat = CGFloat.pi / 6.0
        let side = (armLength + lineWidth / 2.0) * 2.0

        let armEnd = CGPoint(x: 0.0, y: -armLength)
        let branchStart = CGPoint(x: 0.0, y: -armLength * 2.0 / 3.0)
        let branchEnds = [
            CGPoint(x: branchStart.x + branchLength * cos(-branchAngle), y: branchStart.y + branchLength * sin(-branchAngle)),
            CGPoint(x: branchStart.x + branchLength * cos(branchAngle - CGFloat.pi), y: branchStart.y + branchLength * sin(branchAngle - CGFloat.pi))
        ]

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let cgContext = context.cgContext
            cgContext.setStrokeColor(color.cgColor)
            cgContext.setLineWidth(lineWidth)
            cgContext.setLineCap(.round)
            cgContext.translateBy(x: side / 2.0, y: side / 2.0)
            for _ in 0 ..< 6 {
                cgContext.rotate(by: CGFloat.pi / 3.0)
                cgContext.move(to: CGPoint())
                cgContext.addLine(to: armEnd)
                for branchEnd in branchEnds {
                    cgContext.move(to: branchStart)
                    cgContext.addLine(to: branchEnd)
                }
            }
            cgContext.strokePath()
        }.cgImage
    }
}
