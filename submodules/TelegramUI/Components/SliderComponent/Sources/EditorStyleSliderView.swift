import Foundation
import UIKit

/// Horizontal editor-style slider used by `SliderComponent` in place of
/// `TGPhotoEditorSliderView`. Covers the property/gesture surface that
/// SliderComponent actually drives; not a full port of the ObjC control.
public final class EditorStyleSliderView: UIControl, UIGestureRecognizerDelegate {
    public var interactionBegan: (() -> Void)?
    public var interactionEnded: (() -> Void)?

    public var lowerBoundValue: CGFloat = 0.0 { didSet { self.value = self._value; self.setNeedsLayout() } }
    public var lowerBoundTrackColor: UIColor? { didSet { self.setNeedsDisplay() } }
    public var minimumValue: CGFloat = 0.0 { didSet { self.value = self._value; self.setNeedsLayout() } }
    public var maximumValue: CGFloat = 1.0 { didSet { self.value = self._value; self.setNeedsLayout() } }
    public var startValue: CGFloat = 0.0 {
        didSet {
            self.startHidden = abs(self.startValue - self.minimumValue) < .ulpOfOne
            self.setNeedsLayout()
            self.setNeedsDisplay()
        }
    }

    private var _value: CGFloat = 0.0
    public var value: CGFloat {
        get { self._value }
        set {
            var next = min(max(newValue, self.minimumValue), self.maximumValue)
            if self.lowerBoundValue > .ulpOfOne {
                next = max(next, self.lowerBoundValue)
            }
            self._value = next
            self.setNeedsLayout()
        }
    }

    public var useLinesForPositions: Bool = false { didSet { self.setNeedsDisplay() } }
    public var markPositions: Bool = true { didSet { self.setNeedsDisplay() } }
    public var lineSize: CGFloat = 4.0 { didSet { self.setNeedsLayout() } }
    public var backColor: UIColor = .gray { didSet { self.setNeedsDisplay() } }
    public var trackColor: UIColor = .white { didSet { self.setNeedsDisplay() } }
    public var startColor: UIColor = .white { didSet { self.setNeedsDisplay() } }
    public var trackCornerRadius: CGFloat = 0.0 { didSet { self.setNeedsDisplay() } }
    public var bordered: Bool = false { didSet { self.setNeedsDisplay() } }
    public var knobImage: UIImage? {
        get { self.knobView.image }
        set { self.knobView.image = newValue; self.setNeedsLayout() }
    }
    public var positionsCount: Int = 0 {
        didSet {
            self.tapGestureRecognizer.isEnabled = self.positionsCount > 1
            self.setNeedsDisplay()
        }
    }
    public var dotSize: CGFloat = 5.0 { didSet { self.setNeedsDisplay() } }
    public var enablePanHandling: Bool = false {
        didSet { self.panGestureRecognizer.isEnabled = self.enablePanHandling }
    }
    public var hitTestEdgeInsets: UIEdgeInsets = .zero

    private let knobView = UIImageView()
    private let panGestureRecognizer = UIPanGestureRecognizer()
    private let tapGestureRecognizer = UITapGestureRecognizer()
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private let knobPadding: CGFloat = 7.0

    private var startHidden = true
    private var knobTouchStart: CGFloat = 0.0
    private var knobTouchCenterStart: CGFloat = 0.0
    private var knobDragCenter: CGFloat = 0.0
    private var knobHighlighted = false
    private var knobStartedDragging = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isOpaque = false
        self.backgroundColor = nil
        self.contentMode = .redraw
        self.knobView.isUserInteractionEnabled = false
        self.addSubview(self.knobView)

        self.panGestureRecognizer.addTarget(self, action: #selector(self.handlePan(_:)))
        self.panGestureRecognizer.isEnabled = false
        self.panGestureRecognizer.delegate = self
        self.addGestureRecognizer(self.panGestureRecognizer)

        self.tapGestureRecognizer.addTarget(self, action: #selector(self.handleTap(_:)))
        self.tapGestureRecognizer.isEnabled = false
        self.addGestureRecognizer(self.tapGestureRecognizer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if self.hitTestEdgeInsets == .zero || !self.isEnabled || self.isHidden {
            return super.point(inside: point, with: event)
        }
        return self.bounds.inset(by: self.hitTestEdgeInsets).contains(point)
    }

    public override var isTracking: Bool { self.knobHighlighted }

    private var valueRange: CGFloat { max(self.maximumValue - self.minimumValue, .ulpOfOne) }

    private func centerPosition(for value: CGFloat, totalLength: CGFloat) -> CGFloat {
        if self.minimumValue < 0.0 {
            if abs(value) < 0.01 { return totalLength * 0.5 }
            let edge = value > 0.0 ? self.maximumValue : self.minimumValue
            let knob = self.knobView.image?.size.width ?? 0.0
            if value > 0.0 {
                return ((totalLength + knob) * 0.5) + ((totalLength - knob) * 0.5) * abs(value / edge)
            }
            return ((totalLength - knob) * 0.5) * abs((edge - value) / edge)
        }
        return totalLength / self.valueRange * (abs(self.minimumValue) + value)
    }

    private func value(forCenterPosition position: CGFloat, totalLength: CGFloat) -> CGFloat {
        if self.minimumValue < 0.0 {
            let knob = self.knobView.image?.size.width ?? 0.0
            if position < (totalLength - knob) * 0.5 {
                return self.minimumValue + position / ((totalLength - knob) * 0.5) * abs(self.minimumValue)
            } else if position <= (totalLength + knob) * 0.5 {
                return 0.0
            }
            return (position - ((totalLength + knob) * 0.5)) / ((totalLength - knob) * 0.5) * self.maximumValue
        }
        return self.minimumValue + position / totalLength * self.valueRange
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !self.bounds.isEmpty else { return }

        let totalLength = self.bounds.width - self.knobPadding * 2.0
        let knobSize = self.knobView.image?.size ?? .zero
        var knobPosition = self.knobPadding
        if self.knobHighlighted && self.positionsCount < 2 {
            knobPosition += self.knobDragCenter
        } else {
            knobPosition += self.centerPosition(for: self.value, totalLength: totalLength)
        }
        knobPosition = min(max(knobPosition, self.knobPadding), self.knobPadding + totalLength)
        self.knobView.frame = CGRect(
            x: knobPosition - knobSize.width * 0.5,
            y: (self.bounds.height - knobSize.height) * 0.5,
            width: knobSize.width,
            height: knobSize.height
        )
        self.setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !self.bounds.isEmpty else { return }

        let margin = self.knobPadding
        let visualMargin: CGFloat = self.positionsCount > 1 ? margin : 2.0
        let totalLength = self.bounds.width - margin * 2.0
        let visualTotalLength = self.bounds.width - 2.0 * visualMargin
        let sideLength = self.bounds.height
        let knobSize = self.knobView.image?.size.width ?? 0.0

        var knobPosition = self.knobPadding + (self.knobHighlighted
            ? self.knobDragCenter
            : self.centerPosition(for: self.value, totalLength: totalLength))
        knobPosition = min(max(knobPosition, self.knobPadding), self.knobPadding + totalLength)

        let lowerBoundPosition = self.knobPadding + self.centerPosition(for: self.lowerBoundValue, totalLength: totalLength)
        let startPosition = visualMargin + visualTotalLength / self.valueRange * (abs(self.minimumValue) + self.startValue)

        var origin = startPosition
        var track = knobPosition - startPosition
        if track < 0.0 {
            track = abs(track)
            origin -= track
        }

        let backFrame = CGRect(x: visualMargin, y: (sideLength - self.lineSize) * 0.5, width: visualTotalLength, height: self.lineSize)
        let trackFrame = CGRect(x: origin, y: (sideLength - self.lineSize) * 0.5, width: track, height: self.lineSize)
        let startFrame = CGRect(x: startPosition - 2.0, y: (sideLength - 12.0) * 0.5, width: 4.0, height: 12.0)
        let knobFrame = CGRect(x: knobPosition - knobSize * 0.5, y: (sideLength - knobSize) * 0.5, width: knobSize, height: knobSize)

        if self.bordered {
            context.setFillColor(UIColor(white: 0.0, alpha: 0.6).cgColor)
            self.fill(backFrame.insetBy(dx: -1.0, dy: -1.0), radius: self.trackCornerRadius * 2.0, in: context)
            if !self.startHidden {
                self.fill(startFrame.insetBy(dx: -1.0, dy: -1.0), radius: self.trackCornerRadius * 2.0, in: context)
            }
            context.setBlendMode(.copy)
        }

        for passIndex in 0 ..< 2 {
            context.saveGState()
            context.resetClip()

            let passBackColor = self.backColor
            var passTrackColor = self.trackColor
            if passIndex == 0 {
                if self.lowerBoundValue > 0.0, let lowerColor = self.lowerBoundTrackColor {
                    context.beginPath()
                    context.addRect(CGRect(x: 0.0, y: 0.0, width: lowerBoundPosition, height: rect.height))
                    context.clip()
                    passTrackColor = lowerColor
                }
            } else if self.lowerBoundValue > 0.0, self.lowerBoundTrackColor != nil, lowerBoundPosition < rect.width {
                context.beginPath()
                context.addRect(CGRect(x: lowerBoundPosition, y: 0.0, width: rect.width - lowerBoundPosition, height: rect.height))
                context.clip()
            } else {
                context.restoreGState()
                break
            }

            context.setFillColor(passBackColor.cgColor)
            self.fill(backFrame, radius: self.trackCornerRadius, in: context)
            context.setBlendMode(.normal)
            context.setFillColor(passTrackColor.cgColor)
            self.fill(trackFrame, radius: self.trackCornerRadius, in: context)

            if !self.startHidden {
                context.setFillColor(self.startColor.cgColor)
                self.fill(startFrame, radius: self.trackCornerRadius, in: context)
            }
            if self.bordered {
                context.setFillColor(UIColor(white: 0.0, alpha: 0.6).cgColor)
                context.fillEllipse(in: knobFrame.insetBy(dx: 1.0, dy: 1.0))
            }

            if self.positionsCount > 1 {
                let step = totalLength / CGFloat(self.positionsCount - 1)
                for i in 0 ..< self.positionsCount {
                    if !self.markPositions && i != 0 && i != self.positionsCount - 1 { continue }
                    if self.useLinesForPositions {
                        let lineRect = CGRect(
                            x: margin - 2.0 + step * CGFloat(i),
                            y: (sideLength - 12.0) * 0.5,
                            width: 4.0,
                            height: 12.0
                        )
                        context.setFillColor((lineRect.midX < trackFrame.maxX ? passTrackColor : passBackColor).cgColor)
                        self.fill(lineRect, radius: self.trackCornerRadius, in: context)
                    } else {
                        let inset: CGFloat = 1.5
                        let outer = self.dotSize + inset * 2.0
                        var dotRect = CGRect(
                            x: margin - outer * 0.5 + step * CGFloat(i),
                            y: (sideLength - outer) * 0.5,
                            width: outer,
                            height: outer
                        )
                        context.setBlendMode(.clear)
                        context.setFillColor(UIColor.clear.cgColor)
                        context.fillEllipse(in: dotRect)
                        context.setBlendMode(.normal)
                        dotRect = dotRect.insetBy(dx: inset, dy: inset)
                        context.setFillColor((dotRect.midX < trackFrame.maxX ? passTrackColor : passBackColor).cgColor)
                        context.fillEllipse(in: dotRect)
                    }
                }
            }
            context.restoreGState()
        }
    }

    private func fill(_ rect: CGRect, radius: CGFloat, in context: CGContext) {
        if radius > .ulpOfOne {
            context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
            context.closePath()
            context.fillPath()
        } else {
            context.fill(rect)
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self.panGestureRecognizer else { return true }
        let velocity = self.panGestureRecognizer.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        let location = gestureRecognizer.location(in: self)
        switch gestureRecognizer.state {
        case .began: self.beginKnobTracking(at: location)
        case .changed: self.continueKnobTracking(at: location)
        case .ended: self.endKnobTracking()
        case .cancelled: self.cancelKnobTracking()
        default: break
        }
    }

    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let x = gestureRecognizer.location(in: self).x
        let position = (x / max(self.bounds.width, .ulpOfOne)) * CGFloat(self.positionsCount - 1)
        let previous = max(0.0, floor(position))
        let next = min(CGFloat(self.positionsCount - 1), ceil(position))
        let chosen: CGFloat?
        if abs(position - previous) < 0.3 {
            chosen = previous
        } else if abs(position - next) < 0.3 {
            chosen = next
        } else {
            chosen = nil
        }
        guard let chosen else { return }
        self.value = chosen
        self.interactionBegan?()
        self.setNeedsLayout()
        self.sendActions(for: .valueChanged)
        self.interactionEnded?()
        self.feedbackGenerator.selectionChanged()
        self.feedbackGenerator.prepare()
    }

    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !self.enablePanHandling { self.beginKnobTracking(at: touch.location(in: self)) }
        return true
    }

    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !self.enablePanHandling { self.continueKnobTracking(at: touch.location(in: self)) }
        return true
    }

    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if !self.enablePanHandling { self.endKnobTracking() }
    }

    public override func cancelTracking(with event: UIEvent?) {
        if !self.enablePanHandling { self.cancelKnobTracking() }
    }

    private func beginKnobTracking(at location: CGPoint) {
        self.knobHighlighted = true
        self.knobTouchCenterStart = self.knobView.center.x
        self.knobTouchStart = location.x
        self.knobDragCenter = location.x
        self.knobStartedDragging = false
        self.feedbackGenerator.prepare()
        self.cancelParentScrolling(self.superview, depth: 0)
    }

    private func continueKnobTracking(at location: CGPoint) {
        if abs(location.x - self.knobTouchStart) > 1.0 && !self.knobStartedDragging {
            self.knobStartedDragging = true
            self.interactionBegan?()
        }

        var dragCenter = self.knobTouchCenterStart - self.knobTouchStart - self.knobPadding + location.x
        let totalLength = max(self.bounds.width - self.knobPadding * 2.0, .ulpOfOne)
        let previousValue = self.value

        if self.positionsCount > 1 {
            var position = Int(round((dragCenter / totalLength) * CGFloat(self.positionsCount - 1)))
            if self.lowerBoundValue > 0.0 {
                position = max(position, Int(self.lowerBoundValue))
            }
            dragCenter = CGFloat(position) * totalLength / CGFloat(self.positionsCount - 1)
        } else if self.lowerBoundValue > 0.0 {
            dragCenter = max(dragCenter, self.lowerBoundValue * totalLength)
        }

        self.knobDragCenter = dragCenter
        self.value = self.value(forCenterPosition: dragCenter, totalLength: totalLength)

        if previousValue != self.value && (self.positionsCount > 1 || self.value == self.minimumValue || self.value == self.maximumValue || (self.minimumValue != self.startValue && self.value == self.startValue)) {
            self.feedbackGenerator.selectionChanged()
            self.feedbackGenerator.prepare()
        }
        self.setNeedsLayout()
        self.sendActions(for: .valueChanged)
    }

    private func endKnobTracking() {
        self.knobHighlighted = false
        self.sendActions(for: .valueChanged)
        self.setNeedsLayout()
        self.interactionEnded?()
    }

    private func cancelKnobTracking() {
        self.knobHighlighted = false
        self.setNeedsLayout()
        self.interactionEnded?()
    }

    private func cancelParentScrolling(_ parentView: UIView?, depth: Int32) {
        guard depth <= 5, let parentView else { return }
        if let scrollView = parentView as? UIScrollView {
            scrollView.isScrollEnabled = false
            scrollView.isScrollEnabled = true
        } else {
            self.cancelParentScrolling(parentView.superview, depth: depth + 1)
        }
    }
}
