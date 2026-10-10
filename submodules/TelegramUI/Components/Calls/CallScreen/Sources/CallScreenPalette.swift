import Foundation
import UIKit
import Display
import TelegramPresentationData

/// The colours of the call screen's animated background, one set of four per call state, and the pair
/// of colours the in-call status bar uses. The screen keeps its white-on-colour design in every theme; the
/// theme decides which colours it sits on, so a call in BananaGram Cream is gold, in Graphite it is
/// charcoal with a yellow glow, and in a custom accent it follows that accent.
///
/// Every colour is held to a minimum contrast against the white text and glyphs drawn on it (`minimumContrast`),
/// whether it was written by hand or derived from an accent.
public struct CallScreenPalette: Equatable {
    /// Requesting, ringing, connecting and terminated.
    public var connecting: [UInt32]
    /// A connected call with a usable signal.
    public var active: [UInt32]
    /// A connected call whose signal quality dropped.
    public var weakSignal: [UInt32]
    
    public init(connecting: [UInt32], active: [UInt32], weakSignal: [UInt32]) {
        self.connecting = CallScreenPalette.legible(connecting)
        self.active = CallScreenPalette.legible(active)
        self.weakSignal = CallScreenPalette.legible(weakSignal)
    }
    
    /// Lowest contrast ratio any background colour may have against white. 3:1 is the WCAG floor for large and
    /// bold text, which is what the call screen draws; the hand-written sets below mostly reach 4.5.
    public static let minimumContrast: Double = 3.0
    
    public static func contrastAgainstWhite(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xff) / 255.0
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        return 1.05 / (luminance + 0.05)
    }
    
    /// Darkens a colour in small steps until white reads on it.
    private static func legible(_ colors: [UInt32]) -> [UInt32] {
        // The shader reads exactly four colours; a shorter set is padded and a longer one trimmed.
        var colors = Array(colors.prefix(4))
        while colors.count < 4 {
            colors.append(colors.last ?? 0x4A7FC4)
        }
        return colors.map { rgb in
            var color = UIColor(rgb: rgb)
            var steps = 0
            while contrastAgainstWhite(color.rgb) < minimumContrast && steps < 40 {
                color = color.withMultipliedBrightnessBy(0.94)
                steps += 1
            }
            return color.rgb
        }
    }
    
    public static let classicDay = CallScreenPalette(
        connecting: [0x4A7FC4, 0x5560C4, 0x9558C4, 0x6A56C9],
        active: [0x6F8F2E, 0x2E8A78, 0x3A83B8, 0x2C7F68],
        weakSignal: [0xB0407F, 0xC76E15, 0xBC4070, 0xCE5A30]
    )
    
    public static let classicNight = CallScreenPalette(
        connecting: [0x2F5C9E, 0x3A4BA6, 0x7A4AA5, 0x5547B0],
        active: [0x5A8A3A, 0x2E7D6B, 0x2F7FA8, 0x2A7566],
        weakSignal: [0xA3396F, 0xC76A1F, 0xA33A63, 0xCF5A2E]
    )
    
    public static let bananaGramCream = CallScreenPalette(
        connecting: [0xA7761C, 0x8C5F14, 0xB48A2E, 0x7A5200],
        active: [0x9A6A1C, 0x7A5A2A, 0xA67A22, 0x6B4C1E],
        weakSignal: [0xB5532F, 0xC77A22, 0xA64A2E, 0xC96A2B]
    )
    
    public static let bananaGramGraphite = CallScreenPalette(
        connecting: [0x57524A, 0x3E3A33, 0x6B5C2A, 0x35322C],
        active: [0x7A5F22, 0x4F4630, 0x8A6A24, 0x34302A],
        weakSignal: [0x7A3A2A, 0x8A5A22, 0x5A2F2F, 0x7A4A24]
    )
    
    /// A palette for any other accent colour: the connecting set is the accent and its neighbours on the colour wheel, the
    /// connected set is a green or teal pulled towards the accent, and the weak-signal set is the usual warm red-orange.
    public static func derived(accent: UIColor, dark: Bool) -> CallScreenPalette {
        let (hue, rawSaturation, _) = accent.hsb
        let saturation = min(0.75, max(0.45, rawSaturation))
        let brightness: CGFloat = dark ? 0.55 : 0.68
        func color(_ hueShift: CGFloat, _ saturationFactor: CGFloat = 1.0, _ brightnessFactor: CGFloat = 1.0) -> UInt32 {
            var shifted = (hue + hueShift).truncatingRemainder(dividingBy: 1.0)
            if shifted < 0.0 {
                shifted += 1.0
            }
            return UIColor(hue: shifted, saturation: min(1.0, saturation * saturationFactor), brightness: min(1.0, brightness * brightnessFactor), alpha: 1.0).rgb
        }
        // A greenish hue that leans towards the accent instead of ignoring it.
        let greenHue: CGFloat = 0.38
        var towardsGreen = greenHue + (hue - greenHue) * 0.25
        if abs(hue - greenHue) > 0.5 {
            towardsGreen = greenHue
        }
        func green(_ hueShift: CGFloat, _ saturationFactor: CGFloat = 1.0, _ brightnessFactor: CGFloat = 1.0) -> UInt32 {
            var shifted = (towardsGreen + hueShift).truncatingRemainder(dividingBy: 1.0)
            if shifted < 0.0 {
                shifted += 1.0
            }
            return UIColor(hue: shifted, saturation: min(1.0, saturation * 0.95 * saturationFactor), brightness: min(1.0, brightness * brightnessFactor), alpha: 1.0).rgb
        }
        return CallScreenPalette(
            connecting: [color(0.0), color(0.04), color(-0.05, 1.0, 0.92), color(0.08, 0.9, 0.95)],
            active: [green(0.0), green(0.05), green(-0.04, 1.0, 0.92), green(0.09, 0.9, 0.95)],
            weakSignal: classicNight.weakSignal
        )
    }
    
    /// The palette for a theme. The four built-in themes use their hand-tuned sets while they still have their own accent; a
    /// custom accent (or a downloaded theme) derives a set from that accent.
    public init(theme: PresentationTheme) {
        let dark = theme.overallDarkAppearance
        // Not `theme.referenceTheme`: the BananaGram themes are built on Day / Night and keep that reference, so a switch on it
        // never saw them and handed their yellow accent to the derived palette (a green call bar on Graphite).
        switch theme.bananaGramReference ?? theme.referenceTheme {
        case .bananaGramCream:
            self = .bananaGramCream
        case .bananaGramGraphite:
            self = .bananaGramGraphite
        case .day, .dayClassic, .night, .nightAccent:
            let accent = theme.list.itemAccentColor
            let (hue, saturation, _) = accent.hsb
            // Telegram's own blue, whatever its exact shade in a given theme.
            let isStockBlue = saturation > 0.4 && hue > 0.53 && hue < 0.65
            if isStockBlue {
                self = dark ? .classicNight : .classicDay
            } else {
                self = .derived(accent: accent, dark: dark)
            }
        }
    }
    
    /// Gradient for the in-call status bar while the call is connected: the first connecting colour and the first active colour.
    public var statusBarActive: [UIColor] {
        return [UIColor(rgb: self.connecting[0]), UIColor(rgb: self.connecting[1])]
    }
    
    /// A light tone of the theme for what is drawn over the status bar's gradient: the ring around the caller's avatar and the
    /// glow that follows their voice. The connected colour pulled well towards white, so it stays visible on every palette.
    public var statusBarHighlight: UIColor {
        return UIColor(rgb: self.active[0]).mixedWith(UIColor(rgb: 0xFFFFFF), alpha: 0.7)
    }
    
    public var statusBarSpeaking: [UIColor] {
        return [UIColor(rgb: self.active[0]), UIColor(rgb: self.active[1])]
    }
}
