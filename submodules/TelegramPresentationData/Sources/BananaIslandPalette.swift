import Foundation

/// The Banana Island's colours for each app icon: the capsule is the icon's background and its label the icon's
/// foreground, so the island under the camera cutout reads as the icon's pair. Colours are sampled from the icons
/// in `Telegram/Telegram-iOS/*.alticon`; the default icon is `BlueIcon`.
public enum BananaIslandPalette {
    public static let iconDidChangeNotification = Notification.Name("BananaIslandPalette.iconDidChange")

    private static let colors: [String: (fill: UInt32, text: UInt32)] = [
        "HalloweenIcon": (0x292035, 0xffb45e),
        "MessagesIcon": (0x0d7030, 0xfbfffc),
        "BlackClassicIcon": (0x2d385b, 0xfffef7),
        "BlackFilledIcon": (0x5d676f, 0xfffef7),
        "BlackIcon": (0x37352e, 0xfffef7),
        "BlueClassicIcon": (0xfdfbf3, 0x292d32),
        "BlueFilledIcon": (0x196e8b, 0xfffef7),
        "BlueIcon": (0xfee48a, 0x211f1b),
        "New1": (0xa9dac3, 0x1f1a17),
        "New2": (0xe3d9f7, 0x211f1b),
        "PatriotPlaneIcon": (0xf6b8a9, 0x211f1b),
        "Premium": (0x423624, 0xfff0bd),
        "PremiumAurora": (0x316c69, 0xfffef7),
        "PremiumBlack": (0x2d2d2d, 0xfffef7),
        "PremiumCarbon": (0x484c4d, 0xfffef7),
        "PremiumEmerald": (0x2b6f58, 0xfffef7),
        "PremiumIce": (0xecf6f9, 0x211f1b),
        "PremiumNight": (0x443c7c, 0xfffef7),
        "PremiumRose": (0xf5cfd7, 0x211f1b),
        "PremiumRoyal": (0x5d4b97, 0xfff0c8),
        "PremiumSunset": (0xf6c4a0, 0x211f1b),
        "PremiumTurbo": (0xd5f594, 0x211f1b),
        "WhiteFilledIcon": (0xfdfdfd, 0x211f1b),
    ]

    /// The fill and label colours for `iconName` (`UIApplication.alternateIconName`, nil for the default icon), or nil
    /// for an icon this table does not know.
    public static func colors(iconName: String?) -> (fill: UInt32, text: UInt32)? {
        return colors[iconName ?? "BlueIcon"]
    }
}
