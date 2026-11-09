import Foundation
import UIKit
import AsyncDisplayKit

private var sharedIsReduceTransparencyEnabled = UIAccessibility.isReduceTransparencyEnabled

public final class NavigationBackgroundNode: ASDisplayNode {
    private var _color: UIColor

    public var color: UIColor {
        return self._color
    }
    
    private var enableBlur: Bool
    private var enableSaturation: Bool
    private var customBlurRadius: CGFloat?

    public var effectView: UIVisualEffectView?
    private let backgroundNode: ASDisplayNode
    
    public var backgroundView: UIView {
        return self.backgroundNode.view
    }

    private var validLayout: (CGSize, CGFloat)?
    
    public var backgroundCornerRadius: CGFloat {
        if let (_, cornerRadius) = self.validLayout {
            return cornerRadius
        } else {
            return 0.0
        }
    }

    // Fork (Extras › Glass Chat Elements): Liquid Glass tinted with the node's colour in place of the
    // tinted blur, on iOS 26+. Only chat pills turn it on; nothing here is created while it is off.
    private var chatGlassRequested = false
    private var chatGlassView: UIVisualEffectView?
    private var appliedChatGlassTint: UIColor?

    /// Liquid Glass needs iOS 26; with Reduce Transparency the pill keeps its solid fill.
    public static var isChatGlassAvailable: Bool {
        if #available(iOS 26.0, *) {
            return !UIAccessibility.isReduceTransparencyEnabled
        } else {
            return false
        }
    }

    /// Draws the node as Liquid Glass tinted with its colour. Returns whether the glass is on, so a caller
    /// that shows a wallpaper-coloured copy of the pill instead of this node can hide that copy.
    @discardableResult
    public func setChatGlass(_ enabled: Bool) -> Bool {
        let effective = enabled && NavigationBackgroundNode.isChatGlassAvailable
        if self.chatGlassRequested != effective {
            self.chatGlassRequested = effective
            self.updateChatGlass()
        }
        return effective
    }

    public var isChatGlass: Bool {
        return self.chatGlassRequested
    }

    private func updateChatGlass() {
        guard self.isNodeLoaded else {
            return
        }
        if #available(iOS 26.0, *), self.chatGlassRequested {
            let glassView: UIVisualEffectView
            if let current = self.chatGlassView {
                glassView = current
            } else {
                glassView = UIVisualEffectView(effect: nil)
                glassView.isUserInteractionEnabled = false
                glassView.layer.cornerCurve = .continuous
                self.view.insertSubview(glassView, at: 0)
                self.chatGlassView = glassView
                self.appliedChatGlassTint = nil
            }
            // The pills carry light text on a dark fill (or dark text on a light one): the glass follows the fill.
            var white: CGFloat = 0.0
            var alpha: CGFloat = 0.0
            if !self._color.getWhite(&white, alpha: &alpha) {
                white = 0.0
            }
            let interfaceStyle: UIUserInterfaceStyle = white < 0.6 ? .dark : .light
            if glassView.overrideUserInterfaceStyle != interfaceStyle {
                glassView.overrideUserInterfaceStyle = interfaceStyle
                self.appliedChatGlassTint = nil
            }
            if self.appliedChatGlassTint != self._color {
                let effect = UIGlassEffect(style: .regular)
                effect.tintColor = self._color.alpha > 0.01 ? self._color : nil
                glassView.effect = effect
                self.appliedChatGlassTint = self._color
            }
            if let (size, cornerRadius) = self.validLayout {
                glassView.frame = CGRect(origin: CGPoint(), size: size)
                glassView.layer.cornerRadius = cornerRadius
            }
            self.backgroundNode.isHidden = true
            self.effectView?.isHidden = true
        } else if let glassView = self.chatGlassView {
            self.chatGlassView = nil
            self.appliedChatGlassTint = nil
            glassView.removeFromSuperview()
            self.backgroundNode.isHidden = false
            self.effectView?.isHidden = false
        }
    }

    public init(color: UIColor, enableBlur: Bool = true, enableSaturation: Bool = true, customBlurRadius: CGFloat? = nil) {
        self._color = .clear
        self.enableBlur = enableBlur
        self.enableSaturation = enableSaturation
        self.customBlurRadius = customBlurRadius

        self.backgroundNode = ASDisplayNode()

        super.init()

        self.addSubnode(self.backgroundNode)

        self.updateColor(color: color, transition: .immediate)
    }

    
    public override func didLoad() {
        super.didLoad()
        
        if self.scheduledUpdate {
            self.scheduledUpdate = false
            self.updateBackgroundBlur(forceKeepBlur: false)
        }
        if self.chatGlassRequested {
            self.updateChatGlass()
        }
    }
    
    private var scheduledUpdate = false
    
    private func updateBackgroundBlur(forceKeepBlur: Bool) {
        guard self.isNodeLoaded else {
            self.scheduledUpdate = true
            return
        }
        if self.enableBlur && !sharedIsReduceTransparencyEnabled && ((self._color.alpha > .ulpOfOne && self._color.alpha < 0.95) || forceKeepBlur) {
            if self.effectView == nil {
                let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

                for subview in effectView.subviews {
                    if subview.description.contains("VisualEffectSubview") {
                        subview.isHidden = true
                    }
                }

                if let sublayer = effectView.layer.sublayers?[0], let filters = sublayer.filters {
                    sublayer.backgroundColor = nil
                    sublayer.isOpaque = false
                    var allowedKeys: [String] = [
                        "gaussianBlur"
                    ]
                    if self.enableSaturation {
                        allowedKeys.append("colorSaturate")
                    }
                    sublayer.filters = filters.filter { filter in
                        guard let filter = filter as? NSObject else {
                            return true
                        }
                        let filterName = String(describing: filter)
                        if !allowedKeys.contains(filterName) {
                            return false
                        }
                        if let customBlurRadius = self.customBlurRadius, filterName == "gaussianBlur" {
                            filter.setValue(customBlurRadius as NSNumber, forKey: "inputRadius")
                        }
                        return true
                    }
                }

                if let (size, cornerRadius) = self.validLayout {
                    effectView.frame = CGRect(origin: CGPoint(), size: size)
                    ContainedViewLayoutTransition.immediate.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
                    effectView.clipsToBounds = !cornerRadius.isZero
                }
                self.effectView = effectView
                self.view.insertSubview(effectView, at: 0)
                if let chatGlassView = self.chatGlassView {
                    effectView.isHidden = true
                    self.view.insertSubview(chatGlassView, at: 0)
                }
            }
        } else if let effectView = self.effectView {
            self.effectView = nil
            effectView.removeFromSuperview()
        }
    }

    public func updateColor(color: UIColor, enableBlur: Bool? = nil, enableSaturation: Bool? = nil, forceKeepBlur: Bool = false, transition: ContainedViewLayoutTransition) {
        let effectiveEnableBlur = enableBlur ?? self.enableBlur
        let effectiveEnableSaturation = enableSaturation ?? self.enableSaturation
        
        if self._color.isEqual(color) && self.enableBlur == effectiveEnableBlur && self.enableSaturation == effectiveEnableSaturation {
            return
        }
        self._color = color
        self.enableBlur = effectiveEnableBlur
        self.enableSaturation = effectiveEnableSaturation

        if sharedIsReduceTransparencyEnabled {
            transition.updateBackgroundColor(node: self.backgroundNode, color: self._color.withAlphaComponent(1.0))
        } else {
            transition.updateBackgroundColor(node: self.backgroundNode, color: self._color)
        }

        self.updateBackgroundBlur(forceKeepBlur: forceKeepBlur)
        if self.chatGlassView != nil {
            self.updateChatGlass()
        }
    }

    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, transition: ContainedViewLayoutTransition, beginWithCurrentState: Bool = true) {
        self.validLayout = (size, cornerRadius)
        if let chatGlassView = self.chatGlassView {
            transition.updateFrame(view: chatGlassView, frame: CGRect(origin: CGPoint(), size: size))
            transition.updateCornerRadius(layer: chatGlassView.layer, cornerRadius: cornerRadius)
        }

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        transition.updateFrame(node: self.backgroundNode, frame: contentFrame, beginWithCurrentState: true)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            transition.updateFrame(layer: effectView.layer, frame: contentFrame, beginWithCurrentState: true)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    transition.updateFrame(layer: sublayer, frame: contentFrame, beginWithCurrentState: true)
                }
            }
        }

        transition.updateCornerRadius(node: self.backgroundNode, cornerRadius: cornerRadius)
        if let effectView = self.effectView {
            transition.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
            effectView.clipsToBounds = !cornerRadius.isZero
        }
    }
    
    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, animator: ControlledTransitionAnimator) {
        self.validLayout = (size, cornerRadius)
        if let chatGlassView = self.chatGlassView {
            animator.updateFrame(layer: chatGlassView.layer, frame: CGRect(origin: CGPoint(), size: size), completion: nil)
            animator.updateCornerRadius(layer: chatGlassView.layer, cornerRadius: cornerRadius, completion: nil)
        }

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        animator.updateFrame(layer: self.backgroundNode.layer, frame: contentFrame, completion: nil)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            animator.updateFrame(layer: effectView.layer, frame: contentFrame, completion: nil)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    animator.updateFrame(layer: sublayer, frame: contentFrame, completion: nil)
                }
            }
        }

        animator.updateCornerRadius(layer: self.backgroundNode.layer, cornerRadius: cornerRadius, completion: nil)
        if let effectView = self.effectView {
            animator.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius, completion: nil)
            effectView.clipsToBounds = !cornerRadius.isZero
        }
    }
}

open class BlurredBackgroundView: UIView {
    private var _color: UIColor?

    private var enableBlur: Bool
    private var customBlurRadius: CGFloat?

    public private(set) var effectView: UIVisualEffectView?
    private let backgroundView: UIView

    private var validLayout: (CGSize, CGFloat)?
    
    public var backgroundCornerRadius: CGFloat {
        if let (_, cornerRadius) = self.validLayout {
            return cornerRadius
        } else {
            return 0.0
        }
    }

    public init(color: UIColor?, enableBlur: Bool = true, customBlurRadius: CGFloat? = nil) {
        self._color = nil
        self.enableBlur = enableBlur
        self.customBlurRadius = customBlurRadius

        self.backgroundView = UIView()

        super.init(frame: CGRect())

        self.addSubview(self.backgroundView)

        if let color = color {
            self.updateColor(color: color, transition: .immediate)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateBackgroundBlur(forceKeepBlur: Bool) {
        if let color = self._color, self.enableBlur && !sharedIsReduceTransparencyEnabled && ((color.alpha > .ulpOfOne && color.alpha < 0.95) || forceKeepBlur) {
            if self.effectView == nil {
                let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

                for subview in effectView.subviews {
                    if subview.description.contains("VisualEffectSubview") {
                        subview.isHidden = true
                    }
                }

                if let sublayer = effectView.layer.sublayers?[0], let filters = sublayer.filters {
                    sublayer.backgroundColor = nil
                    sublayer.isOpaque = false
                    //sublayer.setValue(true as NSNumber, forKey: "allowsInPlaceFiltering")
                    let allowedKeys: [String] = [
                        "colorSaturate",
                        "gaussianBlur"
                    ]
                    sublayer.filters = filters.filter { filter in
                        guard let filter = filter as? NSObject else {
                            return true
                        }
                        let filterName = String(describing: filter)
                        if !allowedKeys.contains(filterName) {
                            return false
                        }
                        if let customBlurRadius = self.customBlurRadius, filterName == "gaussianBlur" {
                            filter.setValue(customBlurRadius as NSNumber, forKey: "inputRadius")
                        }
                        return true
                    }
                }

                if let (size, cornerRadius) = self.validLayout {
                    effectView.frame = CGRect(origin: CGPoint(), size: size)
                    ContainedViewLayoutTransition.immediate.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
                    effectView.clipsToBounds = !cornerRadius.isZero
                }
                self.effectView = effectView
                self.insertSubview(effectView, at: 0)
            }
        } else if let effectView = self.effectView {
            self.effectView = nil
            effectView.removeFromSuperview()
        }
    }

    public func updateColor(color: UIColor, enableBlur: Bool? = nil, forceKeepBlur: Bool = false, transition: ContainedViewLayoutTransition) {
        let effectiveEnableBlur = enableBlur ?? self.enableBlur

        if self._color == color && self.enableBlur == effectiveEnableBlur {
            return
        }
        self._color = color
        self.enableBlur = effectiveEnableBlur

        if sharedIsReduceTransparencyEnabled {
            transition.updateBackgroundColor(layer: self.backgroundView.layer, color: color.withAlphaComponent(1.0))
        } else {
            transition.updateBackgroundColor(layer: self.backgroundView.layer, color: color)
        }

        self.updateBackgroundBlur(forceKeepBlur: forceKeepBlur)
    }

    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, maskedCorners: CACornerMask = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMinXMinYCorner], transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, cornerRadius)

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        transition.updateFrame(view: self.backgroundView, frame: contentFrame, beginWithCurrentState: true)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            transition.updateFrame(layer: effectView.layer, frame: contentFrame, beginWithCurrentState: true)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    transition.updateFrame(layer: sublayer, frame: contentFrame, beginWithCurrentState: true)
                }
            }
        }
        
        if #available(iOS 11.0, *) {
            self.backgroundView.layer.maskedCorners = maskedCorners
        }

        transition.updateCornerRadius(layer: self.backgroundView.layer, cornerRadius: cornerRadius)
        if let effectView = self.effectView {
            transition.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius)
            effectView.clipsToBounds = !cornerRadius.isZero
            
            if #available(iOS 11.0, *) {
                effectView.layer.maskedCorners = maskedCorners
            }
        }
    }
    
    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, animator: ControlledTransitionAnimator) {
        self.validLayout = (size, cornerRadius)

        let contentFrame = CGRect(origin: CGPoint(), size: size)
        animator.updateFrame(layer: self.backgroundView.layer, frame: contentFrame, completion: nil)
        if let effectView = self.effectView, effectView.frame != contentFrame {
            animator.updateFrame(layer: effectView.layer, frame: contentFrame, completion: nil)
            if let sublayers = effectView.layer.sublayers {
                for sublayer in sublayers {
                    animator.updateFrame(layer: sublayer, frame: contentFrame, completion: nil)
                }
            }
        }

        animator.updateCornerRadius(layer: self.backgroundView.layer, cornerRadius: cornerRadius, completion: nil)
        if let effectView = self.effectView {
            animator.updateCornerRadius(layer: effectView.layer, cornerRadius: cornerRadius, completion: nil)
            effectView.clipsToBounds = !cornerRadius.isZero
        }
    }
}
