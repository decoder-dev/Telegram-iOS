import Foundation

/// A recording keeps this snapshot even if preferences change while the camera is open.
public struct RoundVideoRecordingProfile: Equatable {
    public let frameRate: Double
    public let outputSide: Int
    public let videoBitrate: Int
    public let audioBitrate: Int

    public init(recordAt60FPS: Bool = false, maximumQuality: Bool = false, limitToVga: Bool = false) {
        self.frameRate = recordAt60FPS ? 60.0 : 30.0
        self.outputSide = maximumQuality && !limitToVga ? 640 : 480
        self.videoBitrate = maximumQuality ? (recordAt60FPS ? 7_500_000 : 5_000_000) : (recordAt60FPS ? 1_500_000 : 1_200_000)
        self.audioBitrate = maximumQuality ? 128_000 : 64_000
    }
}
