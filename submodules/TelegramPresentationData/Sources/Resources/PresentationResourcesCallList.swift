import Foundation
import UIKit
import Display
import AppBundle

private func rotatedImage(_ image: UIImage?) -> UIImage? {
    guard let image = image else {
        return nil
    }
    let size = image.size
    UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else {
        return nil
    }
    context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
    context.rotate(by: .pi)
    context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
    image.draw(at: CGPoint())
    return UIGraphicsGetImageFromCurrentImageContext()
}

public struct PresentationResourcesCallList {
    public static func outgoingIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListOutgoingIcon.rawValue, { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Call List/OutgoingIcon"), color: theme.list.disclosureArrowColor)
        })
    }

    public static func outgoingVideoIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListOutgoingVideoIcon.rawValue, { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Call List/OutgoingVideoIcon"), color: theme.list.disclosureArrowColor)
        })
    }

    public static func incomingIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListIncomingIcon.rawValue, { theme in
            return generateTintedImage(image: rotatedImage(UIImage(bundleImageName: "Call List/OutgoingIcon")), color: theme.list.disclosureArrowColor)
        })
    }

    public static func incomingVideoIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListIncomingVideoIcon.rawValue, { theme in
            return generateTintedImage(image: rotatedImage(UIImage(bundleImageName: "Call List/OutgoingVideoIcon")), color: theme.list.disclosureArrowColor)
        })
    }

    public static func missedIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListMissedIcon.rawValue, { theme in
            return generateTintedImage(image: rotatedImage(UIImage(bundleImageName: "Call List/OutgoingIcon")), color: theme.list.itemDestructiveColor)
        })
    }

    public static func missedVideoIcon(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListMissedVideoIcon.rawValue, { theme in
            return generateTintedImage(image: rotatedImage(UIImage(bundleImageName: "Call List/OutgoingVideoIcon")), color: theme.list.itemDestructiveColor)
        })
    }

    public static func infoButton(_ theme: PresentationTheme) -> UIImage? {
        return theme.image(PresentationResourceKey.callListInfoButton.rawValue, { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Call List/InfoButton"), color: theme.list.itemAccentColor)
        })
    }
}
