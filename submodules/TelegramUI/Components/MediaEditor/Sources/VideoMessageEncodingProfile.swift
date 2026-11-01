import Foundation

/// Stored with the video's adjustments so a queued export does not read later app preferences.
public struct VideoMessageEncodingProfile: Codable, Equatable {
    public static let defaultMaximumFileSize: Int64 = 12_582_912
    public static let `default` = VideoMessageEncodingProfile(maximumDimension: 480, videoBitrate: 1_200_000, audioBitrate: 64_000, frameRate: 30.0)

    public let maximumDimension: Int
    public let videoBitrate: Int
    public let audioBitrate: Int
    public let frameRate: Double
    public let maximumFileSize: Int64

    public init(maximumDimension: Int, videoBitrate: Int, audioBitrate: Int, frameRate: Double, maximumFileSize: Int64 = defaultMaximumFileSize) {
        self.maximumDimension = maximumDimension > 480 ? 640 : 480
        self.videoBitrate = min(7_500_000, max(64_000, videoBitrate))
        self.audioBitrate = min(128_000, max(32_000, audioBitrate))
        self.frameRate = frameRate == 60.0 ? 60.0 : 30.0
        self.maximumFileSize = min(Self.defaultMaximumFileSize, max(1, maximumFileSize))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maximumDimension: try container.decode(Int.self, forKey: .maximumDimension),
            videoBitrate: try container.decode(Int.self, forKey: .videoBitrate),
            audioBitrate: try container.decode(Int.self, forKey: .audioBitrate),
            frameRate: try container.decode(Double.self, forKey: .frameRate),
            maximumFileSize: try container.decodeIfPresent(Int64.self, forKey: .maximumFileSize) ?? Self.defaultMaximumFileSize
        )
    }

    public func fittingVideoBitrate(duration: Double) -> Int {
        guard duration.isFinite, duration > 0.0 else { return self.videoBitrate }
        // Leave room for the MP4 container, the audio track and encoder rate-control overshoot.
        let payloadBytes = max(0.0, Double(self.maximumFileSize) * 0.94 - 65_536.0)
        let availableVideoRate = payloadBytes * 8.0 / duration - Double(self.audioBitrate)
        return Int(min(Double(self.videoBitrate), max(1_000.0, availableVideoRate)))
    }
}
