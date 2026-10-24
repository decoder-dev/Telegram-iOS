import Foundation
import UIKit
import Display
import AppBundle

private let gradientImage = UIImage(bundleImageName: "Item List/Icons/Gradient")
private let backdropImage = UIImage(bundleImageName: "Item List/Icons/Backdrop")
/// The BananaGram themes paint every Settings icon in their own accent instead of the stock multicolour set:
/// one fill colour behind a glyph drawn in the colour the theme uses on top of its accent. Classic themes leave it nil.
public struct ForkSettingsIconTint: Equatable {
    public let fill: UIColor
    public let glyph: UIColor
    
    public init(fill: UIColor, glyph: UIColor) {
        self.fill = fill
        self.glyph = glyph
    }
}

private let settingsIconLock = NSLock()
var forkSettingsIconTintIsActive: Bool {
    settingsIconLock.lock()
    defer { settingsIconLock.unlock() }
    return settingsIconTint != nil
}
private var settingsIconTint: ForkSettingsIconTint?
private var settingsIconCache: [String: UIImage] = [:]

public func forkUpdateSettingsIconTint(_ tint: ForkSettingsIconTint?) {
    settingsIconLock.lock()
    if settingsIconTint != tint {
        settingsIconTint = tint
        settingsIconCache.removeAll()
    }
    settingsIconLock.unlock()
}

private func settingsIconColorKey(_ color: UIColor) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return "\(Int(r * 255)).\(Int(g * 255)).\(Int(b * 255)).\(Int(a * 255))"
}

public func renderSettingsIcon(name: String, scaleFactor: CGFloat = 1.0, backgroundColors: [UIColor]? = nil) -> UIImage? {
    settingsIconLock.lock()
    let tint = settingsIconTint
    settingsIconLock.unlock()
    
    let effectiveColors: [UIColor]?
    if let backgroundColors {
        effectiveColors = tint.flatMap { [$0.fill] } ?? backgroundColors
    } else {
        effectiveColors = nil
    }
    let key = "\(name)|\(scaleFactor)|" + (effectiveColors ?? []).map(settingsIconColorKey).joined(separator: ",") + "|" + (effectiveColors != nil ? tint.map { settingsIconColorKey($0.glyph) } ?? "" : "")
    settingsIconLock.lock()
    let cached = settingsIconCache[key]
    settingsIconLock.unlock()
    if let cached {
        return cached
    }
    let image = renderSettingsIconUncached(name: name, scaleFactor: scaleFactor, backgroundColors: effectiveColors, glyphColor: effectiveColors != nil ? tint?.glyph : nil)
    if let image {
        settingsIconLock.lock()
        settingsIconCache[key] = image
        settingsIconLock.unlock()
    }
    return image
}

private func renderSettingsIconUncached(name: String, scaleFactor: CGFloat, backgroundColors: [UIColor]?, glyphColor: UIColor?) -> UIImage? {
    return generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        if let backgroundColors {
            var locations: [CGFloat] = [0.0, 1.0]
            let colors: [CGColor] = backgroundColors.map(\.cgColor)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
            
            context.drawLinearGradient(gradient, start: CGPoint(x: size.width, y: size.height), end: CGPoint(x: 0.0, y: 0.0), options: CGGradientDrawingOptions())
            
            if let gradientImage, let cgImage = gradientImage.cgImage {
                context.setBlendMode(.plusLighter)
                context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }
            
            if let backdropImage, let cgImage = backdropImage.cgImage {
                context.setBlendMode(.overlay)
                context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
            }
                        
            context.setBlendMode(.normal)
            
            if let image = UIImage(bundleImageName: name), let maskImage = image.cgImage {
                let imageSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
                let imageRect = CGRect(origin: CGPoint(x: (bounds.width - imageSize.width) * 0.5, y: (bounds.height - imageSize.height) * 0.5), size: imageSize)
                
                context.saveGState()
                context.clip(to: imageRect, mask: maskImage)
                context.setFillColor((glyphColor ?? UIColor.white).cgColor)
                context.fill(imageRect)
                context.restoreGState()
            }
            
            let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
            let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
            outerPath.append(innerPath)

            context.saveGState()
            outerPath.usesEvenOddFillRule = true
            context.addPath(outerPath.cgPath)
            context.clip(using: .evenOdd)

            context.setBlendMode(.clear)
            context.fill(CGRect(origin: .zero, size: size))
            context.restoreGState()
        } else {
            if let image = UIImage(bundleImageName: name), let cgImage = image.cgImage {
                let imageSize: CGSize
                if scaleFactor == 1.0 {
                    imageSize = size
                } else {
                    imageSize = CGSize(width: image.size.width * scaleFactor, height: image.size.height * scaleFactor)
                }
                context.draw(cgImage, in: CGRect(origin: CGPoint(x: (bounds.width - imageSize.width) * 0.5, y: (bounds.height - imageSize.height) * 0.5), size: imageSize))
            }
        }
    })
}

public func renderAttachAppIcon(iconImage: UIImage?) -> UIImage? {
    return generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
                
        if let iconImage, let cgImage = iconImage.cgImage {
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }

        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.saveGState()
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.saveGState()
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
            context.restoreGState()
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    })
}

let colorRed = UIColor(rgb: 0xFF453A)
let colorGreen = UIColor(rgb: 0x34C759)
let colorBlue = UIColor(rgb: 0x0a84ff)
let colorLightBlue = UIColor(rgb: 0x32ADE6)
let colorTeal = UIColor(rgb: 0x00c7be)
let colorOrange = UIColor(rgb: 0xFF9F0A)
let colorPurple = UIColor(rgb: 0xAF52DE)
let colorGray = UIColor(rgb: 0x8E8E93)
let colorViolet = UIColor(rgb: 0x5E5CE6)

public struct PresentationResourcesSettings {
    public static var proxy: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Proxy", backgroundColors: [colorGreen]) }
    public static var savedMessages: UIImage? { return renderSettingsIcon(name: "Item List/Icons/SavedMessages", backgroundColors: [colorBlue]) }
    public static var recentCalls: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Phone", backgroundColors: [colorGreen]) }
    public static var devices: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Devices", backgroundColors: [colorOrange]) }
    public static var chatFolders: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Folder", backgroundColors: [colorLightBlue]) }
    public static var stickers: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Sticker", backgroundColors: [colorOrange]) }
    public static var notifications: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Notifications", backgroundColors: [colorRed]) }
    public static var security: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Privacy", backgroundColors: [colorGray]) }
    public static var dataAndStorage: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Data", backgroundColors: [colorGreen]) }
    public static var appearance: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Appearance", backgroundColors: [colorLightBlue]) }
    public static var language: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Language", backgroundColors: [colorPurple]) }
    public static var powerSaving: UIImage? { return renderSettingsIcon(name: "Item List/Icons/PowerSaving", backgroundColors: [colorOrange]) }
    public static var developerMode: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Settings", backgroundColors: [colorGray]) }
    public static var business: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Business", backgroundColors: [UIColor(rgb: 0xA95CE3), UIColor(rgb: 0xF16B80)]) }
    public static var myProfile: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Profile", backgroundColors: [colorRed]) }
    
    public static var birthday: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Cake", backgroundColors: [colorBlue]) }
    public static var aiTools: UIImage? { return renderSettingsIcon(name: "Item List/Icons/AITools", backgroundColors: [colorPurple]) }
    public static var yourColor: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Brush", backgroundColors: [colorLightBlue]) }
    
    public static var storageUsage: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Pie", backgroundColors: [colorOrange]) }
    public static var dataUsage: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Stats", backgroundColors: [colorPurple]) }
    
    public static var cellular: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Cellular", backgroundColors: [colorGreen]) }
    public static var wifi: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Wifi", backgroundColors: [colorBlue]) }
    
    public static var privateChats: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Member", backgroundColors: [colorBlue]) }
    public static var groups: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Group", backgroundColors: [colorGreen]) }
    public static var channels: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Channel", backgroundColors: [colorOrange]) }
    public static var stories: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Stories", backgroundColors: [colorViolet]) }
    public static var reactions: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Reactions", backgroundColors: [UIColor(rgb: 0xFF2D55)]) }
    
    public static var photos: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [colorOrange]) }
    public static var videos: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Video", backgroundColors: [colorRed]) }
    public static var files: UIImage? { return renderSettingsIcon(name: "Item List/Icons/File", backgroundColors: [colorBlue]) }
    public static var gifs: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Gif", backgroundColors: [colorOrange]) }
    public static var stickersGreen: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Sticker", backgroundColors: [colorGreen]) }
    public static var emoji: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Emoji", backgroundColors: [colorLightBlue]) }
    public static var emojiTeal: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Emoji", backgroundColors: [colorTeal]) }
    public static var archivedSticker: UIImage? { return renderSettingsIcon(name: "Item List/Icons/ArchivedSticker", backgroundColors: [colorGreen]) }
    public static var trendingSticker: UIImage? { return renderSettingsIcon(name: "Item List/Icons/TrendingSticker", backgroundColors: [colorOrange]) }
    public static var effects: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Effect", backgroundColors: [colorLightBlue]) }
    public static var photosBlue: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [colorBlue]) }
    public static var clock: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Clock", backgroundColors: [colorPurple]) }
    public static var photosLightBlue: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Photo", backgroundColors: [colorLightBlue]) }
    public static var videosBlue: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Video", backgroundColors: [colorBlue]) }
    
    public static var block: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Block", backgroundColors: [colorRed]) }
    public static var activeSessions: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Language", backgroundColors: [colorBlue]) }
    public static var faceId: UIImage? { return renderSettingsIcon(name: "Item List/Icons/FaceId", backgroundColors: [colorGreen]) }
    public static var lockOrange: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Privacy", backgroundColors: [colorOrange]) }
    public static var passkeys: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [colorViolet]) }
    public static var timer: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Timer", backgroundColors: [colorPurple]) }
    public static var email: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Email", backgroundColors: [colorViolet]) }
    // Not the gear: `developerMode` already uses that glyph, and the two rows are now neighbours in
    // the main Settings list, where they would have read as one item drawn twice.
    public static var forkExtras: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Effect", backgroundColors: [colorTeal]) }
        
    public static var premium: UIImage? {
        if forkSettingsIconTintIsActive {
            return renderSettingsIcon(name: "Item List/Icons/Premium", backgroundColors: [colorBlue])
        }
        return premiumClassic
    }
    
    private static let premiumClassic = generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
                
        let colorsArray: [CGColor] = [
            UIColor(rgb: 0x6b93ff).cgColor,
            UIColor(rgb: 0x6b93ff).cgColor,
            UIColor(rgb: 0x8d77ff).cgColor,
            UIColor(rgb: 0xb56eec).cgColor,
            UIColor(rgb: 0xb56eec).cgColor
        ]
        var locations: [CGFloat] = [0.0, 0.15, 0.5, 0.85, 1.0]
        let gradient = CGGradient(colorsSpace: deviceColorSpace, colors: colorsArray as CFArray, locations: &locations)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        
        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
        }
        
        context.setBlendMode(.normal)
        
        if let image = generateTintedImage(image: UIImage(bundleImageName: "Item List/Icons/Premium"), color: UIColor(rgb: 0xffffff)), let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - image.size.width) / 2.0), y: floorToScreenPixels((bounds.height - image.size.height) / 2.0)), size: image.size))
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    })
    
    public static var ton: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Gram", backgroundColors: [colorBlue]) }
    public static var gramEarnings: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Earnings", backgroundColors: [colorBlue]) }
    
    public static let money = UIImage(bundleImageName: "Settings/Gram")
 
    public static var stars: UIImage? {
        if forkSettingsIconTintIsActive {
            return renderSettingsIcon(name: "Item List/Icons/Stars", backgroundColors: [colorBlue])
        }
        return starsClassic
    }
    
    private static let starsClassic = generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let colorsArray: [CGColor] = [
            UIColor(rgb: 0xfec80f).cgColor,
            UIColor(rgb: 0xdd6f12).cgColor
        ]
        var locations: [CGFloat] = [0.0, 1.0]
        let gradient = CGGradient(colorsSpace: deviceColorSpace, colors: colorsArray as CFArray, locations: &locations)!

        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        
        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
        }
        
        context.setBlendMode(.normal)
        
        if let image = generateTintedImage(image: UIImage(bundleImageName: "Item List/Icons/Stars"), color: UIColor(rgb: 0xffffff)), let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - image.size.width) / 2.0), y: floorToScreenPixels((bounds.height - image.size.height) / 2.0)), size: image.size))
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    })
    
    public static var premiumGift: UIImage? {
        if forkSettingsIconTintIsActive {
            return renderSettingsIcon(name: "Item List/Icons/Gift", backgroundColors: [colorBlue])
        }
        return premiumGiftClassic
    }
    
    private static let premiumGiftClassic = generateImage(CGSize(width: 30.0, height: 30.0), contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let colorsArray: [CGColor] = [
            UIColor(rgb: 0x3ba1f2).cgColor,
            UIColor(rgb: 0x3ba1f2).cgColor,
            UIColor(rgb: 0x39b3b4).cgColor,
            UIColor(rgb: 0x34c27d).cgColor,
            UIColor(rgb: 0x34c27d).cgColor
        ]
        var locations: [CGFloat] = [0.0, 0.15, 0.5, 0.85, 1.0]
        let gradient = CGGradient(colorsSpace: deviceColorSpace, colors: colorsArray as CFArray, locations: &locations)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size.width, y: size.height), options: CGGradientDrawingOptions())
        
        if let gradientImage, let cgImage = gradientImage.cgImage {
            context.setBlendMode(.plusLighter)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        if let backdropImage, let cgImage = backdropImage.cgImage {
            context.setBlendMode(.overlay)
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size))
        }
        
        context.setBlendMode(.normal)
        
        if let image = generateTintedImage(image: UIImage(bundleImageName: "Item List/Icons/Gift"), color: UIColor(rgb: 0xffffff)), let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - image.size.width) / 2.0), y: floorToScreenPixels((bounds.height - image.size.height) / 2.0)), size: image.size))
        }
        
        let outerPath = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8.0)
        outerPath.append(innerPath)

        context.saveGState()
        outerPath.usesEvenOddFillRule = true
        context.addPath(outerPath.cgPath)
        context.clip(using: .evenOdd)

        context.setBlendMode(.clear)
        context.fill(CGRect(origin: .zero, size: size))
        context.restoreGState()
    })
    
    public static var bot: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Bot", backgroundColors: [colorBlue]) }

    public static let passport = renderAttachAppIcon(iconImage: UIImage(bundleImageName: "Settings/Menu/Passport"))
    public static let watch = renderAttachAppIcon(iconImage: UIImage(bundleImageName: "Settings/Menu/Watch"))
    
    public static var support: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Support", backgroundColors: [colorOrange]) }
    public static var faq: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Faq", backgroundColors: [colorLightBlue]) }
    public static var tips: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Tips", backgroundColors: [UIColor(rgb: 0xffcc02)]) }
        
    public static var changePhoneNumber: UIImage? { return renderSettingsIcon(name: "Item List/Icons/ChangePhone", backgroundColors: [colorPurple]) }
    public static var deleteAddAccount: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Member", backgroundColors: [colorBlue]) }
    public static var deleteSetTwoStepAuth: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [colorViolet]) }
    public static var deleteChats: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Delete", backgroundColors: [colorRed]) }
    public static var clearSynced: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Group", backgroundColors: [colorOrange]) }
    
    public static var groupType: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Members", backgroundColors: [colorBlue]) }
    public static var channelType: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Channel", backgroundColors: [colorBlue]) }
    public static var chatHistory: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Chat", backgroundColors: [colorGreen]) }
    public static var topics: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Topics", backgroundColors: [colorLightBlue]) }
    public static var links: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Link", backgroundColors: [colorOrange]) }
    public static var chatAppearance: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Brush", backgroundColors: [colorOrange]) }
    public static var admins: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Admin", backgroundColors: [colorGreen]) }
    public static var subscribers: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Group", backgroundColors: [colorBlue]) }
    public static var stats: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Stats", backgroundColors: [colorViolet]) }
    public static var balance: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Balance", backgroundColors: [colorGreen]) }
    public static var affiliateProgram: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Affiliate", backgroundColors: [colorViolet]) }
    public static var earnStars: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Earn", backgroundColors: [colorGreen]) }
    public static var channelMessages: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Messages", backgroundColors: [colorViolet]) }
    public static var settings: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Settings", backgroundColors: [colorOrange]) }
    public static var antiSpam: UIImage? { return renderSettingsIcon(name: "Item List/Icons/AntiSpam", backgroundColors: [colorGreen]) }
    public static var recentActions: UIImage? { return renderSettingsIcon(name: "Item List/Icons/View", backgroundColors: [colorOrange]) }
    public static var permissions: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Key", backgroundColors: [colorGray]) }
    public static var autoTranslate: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Translation", backgroundColors: [colorPurple]) }
    public static var emojiStatus: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Status", backgroundColors: [colorBlue]) }
    public static var location: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Location", backgroundColors: [colorLightBlue]) }
    public static let groupRequests = renderAttachAppIcon(iconImage: UIImage(bundleImageName: "Chat/Info/GroupRequestsIcon"))
    
    public static var calls: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Phone", backgroundColors: [colorOrange]) }
    public static var messages: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Chat", backgroundColors: [colorViolet]) }
    public static var filesGreen: UIImage? { return renderSettingsIcon(name: "Item List/Icons/File", backgroundColors: [colorGreen]) }
    public static var stickersYellow: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Sticker", backgroundColors: [colorOrange]) }
    public static var music: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Play", backgroundColors: [colorRed]) }
    public static var voices: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Microphone", backgroundColors: [colorPurple]) }
    public static var upload: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Upload", backgroundColors: [colorBlue]) }
    public static var download: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Download", backgroundColors: [colorGreen]) }
    
    public static var welcome: UIImage? { return renderSettingsIcon(name: "Item List/Icons/Hand", backgroundColors: [colorViolet]) }
}
