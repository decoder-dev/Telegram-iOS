import Foundation
import UIKit

/// Look of a Liquid Glass message bubble (ported from Glassgram). The caller builds it from the
/// Extras settings and hands it to `ChatMessageBackground.setGlass`; nil there means the stock bubble.
public struct ChatMessageGlassBubbleStyle: Equatable {
    /// 0 = colourless glass, 1 = solid theme colour.
    public var tintAlpha: CGFloat
    /// Rim brightness at the top edge, on the sides and at the bottom edge.
    public var rimTopAlpha: CGFloat
    public var rimMiddleAlpha: CGFloat
    public var rimBottomAlpha: CGFloat

    public init(tintAlpha: CGFloat, rimTopAlpha: CGFloat, rimMiddleAlpha: CGFloat, rimBottomAlpha: CGFloat) {
        self.tintAlpha = tintAlpha
        self.rimTopAlpha = rimTopAlpha
        self.rimMiddleAlpha = rimMiddleAlpha
        self.rimBottomAlpha = rimBottomAlpha
    }

    /// Builds a style from the Extras percentages, clamped to 0...100.
    public init(tintPercent: Int32, rimTopPercent: Int32, rimSidesPercent: Int32, rimBottomPercent: Int32) {
        func fraction(_ value: Int32) -> CGFloat {
            return CGFloat(min(100, max(0, value))) / 100.0
        }
        self.init(tintAlpha: fraction(tintPercent), rimTopAlpha: fraction(rimTopPercent), rimMiddleAlpha: fraction(rimSidesPercent), rimBottomAlpha: fraction(rimBottomPercent))
    }

    public var hasRim: Bool {
        return self.rimTopAlpha > 0.0 || self.rimMiddleAlpha > 0.0 || self.rimBottomAlpha > 0.0
    }

    /// Liquid Glass renders short views as frosted "control" glass. The glass view is kept at least
    /// this tall (centred, cut back by the bubble shape mask) so short messages stay clear.
    public static let minGlassHeight: CGFloat = 100.0

    /// Glass bubbles need the iOS 26 Liquid Glass API; below it the stock bubble is drawn.
    public static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }
}

/// A thin ring along the edge of a bubble shape image, used as the rim mask. The theme's own outline
/// images are drawn in its stroke colour, which is fully transparent in many themes, so the ring is
/// derived from the shape's alpha instead: shape minus the shape eroded by ~1pt.
///
/// Cached per shape image on the main thread. The entry holds the shape weakly and is matched by
/// identity, so a recycled object address can never hand back another shape's ring.
private final class GlassRimCacheEntry {
    weak var shape: UIImage?
    let rim: UIImage

    init(shape: UIImage, rim: UIImage) {
        self.shape = shape
        self.rim = rim
    }
}

private var glassRimImageCache: [ObjectIdentifier: GlassRimCacheEntry] = [:]

func makeGlassRimImage(fromShape shape: UIImage) -> UIImage? {
    let key = ObjectIdentifier(shape)
    if let entry = glassRimImageCache[key] {
        if entry.shape === shape {
            return entry.rim
        }
        glassRimImageCache.removeValue(forKey: key)
    }
    guard let cgImage = shape.cgImage else {
        return nil
    }
    let width = cgImage.width
    let height = cgImage.height
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    let rect = CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height))
    let radius = max(1, Int(shape.scale.rounded()))

    // Erode: keep only the pixels that are inside the shape in every direction within `radius`.
    context.draw(cgImage, in: rect)
    context.setBlendMode(.destinationIn)
    for dx in -radius ... radius {
        for dy in -radius ... radius where (dx != 0 || dy != 0) && dx * dx + dy * dy <= radius * radius {
            context.draw(cgImage, in: rect.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy)))
        }
    }
    guard let eroded = context.makeImage() else {
        return nil
    }

    // Ring = shape - eroded shape.
    context.setBlendMode(.copy)
    context.clear(rect)
    context.draw(cgImage, in: rect)
    context.setBlendMode(.destinationOut)
    context.draw(eroded, in: rect)
    guard let ring = context.makeImage() else {
        return nil
    }

    let result = UIImage(cgImage: ring, scale: shape.scale, orientation: .up).resizableImage(withCapInsets: shape.capInsets, resizingMode: shape.resizingMode)
    if glassRimImageCache.count > 64 {
        glassRimImageCache = glassRimImageCache.filter { $0.value.shape != nil }
    }
    glassRimImageCache[key] = GlassRimCacheEntry(shape: shape, rim: result)
    return result
}

/// The bright edge of the glass: a vertical white gradient visible only through the rim ring.
final class GlassRimView: UIView {
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    let outlineView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        if let gradient = self.layer as? CAGradientLayer {
            gradient.locations = [0.0, 0.5, 1.0]
            gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        }
        self.mask = self.outlineView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ style: ChatMessageGlassBubbleStyle) {
        guard let gradient = self.layer as? CAGradientLayer else {
            return
        }
        gradient.colors = [
            UIColor(white: 1.0, alpha: style.rimTopAlpha).cgColor,
            UIColor(white: 1.0, alpha: style.rimMiddleAlpha).cgColor,
            UIColor(white: 1.0, alpha: style.rimBottomAlpha).cgColor
        ]
    }
}
