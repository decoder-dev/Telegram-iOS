import Foundation

public enum PresentationLayoutMetrics {
    public static let minimumInteractiveSize: CGFloat = 44.0
    public static let multilineTextThreshold: CGFloat = 23.0
    public static let listHorizontalInset: CGFloat = 16.0
    /// Chat list rows follow Apple Messages: a 46 pt avatar in a 74 pt row (46 + 2 × 14) at the default text size.
    public static let chatListAvatarDiameter: CGFloat = 46.0
    public static let chatListAvatarTextSpacing: CGFloat = 12.0
    public static let chatListRowVerticalInset: CGFloat = 14.0
}
