import Foundation
import Photos

/// Fork: a gallery video the user chose to send as a round video, for the chat to open in its round-video screen.
public struct MediaPickerRoundVideoRequest {
    public let asset: PHAsset
    /// The square to keep, as a fraction (0...1) of the video's displayed frame.
    public let normalizedCrop: CGRect
    /// The part to keep, in seconds.
    public let trimRange: Range<Double>

    public init(asset: PHAsset, normalizedCrop: CGRect, trimRange: Range<Double>) {
        self.asset = asset
        self.normalizedCrop = normalizedCrop
        self.trimRange = trimRange
    }
}
