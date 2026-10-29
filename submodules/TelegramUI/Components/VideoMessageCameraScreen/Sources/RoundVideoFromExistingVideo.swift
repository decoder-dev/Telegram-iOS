import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit
import TelegramCore

/// Fork: where a picked video lands in the square the round-video camera records. Pure, so it can be tested apart
/// from AVFoundation: everything here is in the video's displayed frame (after its preferred transform), in pixels.
public struct RoundVideoExportGeometry: Equatable {
    /// A recording stops at a minute; so does a picked video.
    public static let maximumDuration: Double = 60.0
    /// The camera's largest side (`VideoMessageExportSettings.maximumDimension`). A smaller crop is never enlarged.
    public static let maximumSide: CGFloat = 480.0
    /// Encoders work in 16-pixel blocks; a crop smaller than one is not a video.
    public static let blockSize: CGFloat = 16.0

    /// The square that is kept.
    public let crop: CGRect
    /// The side of the output square.
    public let outputSide: CGFloat
    /// The part of the video that is kept, in seconds.
    public let timeRange: Range<Double>

    /// `normalizedCrop` is a fraction (0...1) of `displaySize`; it is clamped to the frame and squared on its centre.
    /// `trimRange` nil keeps the whole video. Nil when nothing usable is left.
    public init?(displaySize: CGSize, normalizedCrop: CGRect, duration: Double, trimRange: Range<Double>?) {
        guard displaySize.width >= Self.blockSize, displaySize.height >= Self.blockSize, duration.isFinite, duration > 0.0 else {
            return nil
        }
        let frame = CGRect(origin: .zero, size: displaySize)
        var crop = CGRect(
            x: normalizedCrop.minX * displaySize.width,
            y: normalizedCrop.minY * displaySize.height,
            width: normalizedCrop.width * displaySize.width,
            height: normalizedCrop.height * displaySize.height
        ).intersection(frame)
        if crop.isNull || min(crop.width, crop.height) < Self.blockSize {
            crop = frame
        }
        let side = min(crop.width, crop.height)
        self.crop = CGRect(x: crop.midX - side / 2.0, y: crop.midY - side / 2.0, width: side, height: side)
        self.outputSide = max(Self.blockSize, min(Self.maximumSide, (side / Self.blockSize).rounded(.down) * Self.blockSize))

        let start = min(max(0.0, trimRange?.lowerBound ?? 0.0), duration)
        let requestedEnd = trimRange.map { $0.upperBound > start ? $0.upperBound : duration } ?? duration
        let end = min(requestedEnd, duration, start + Self.maximumDuration)
        guard end > start else {
            return nil
        }
        self.timeRange = start ..< end
    }

    /// Maps the track's own pixels to the output square: the preferred transform puts them in the displayed frame,
    /// from where the crop moves to the origin and is scaled to the output side.
    public func layerTransform(preferredTransform: CGAffineTransform) -> CGAffineTransform {
        let scale = self.outputSide / self.crop.width
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -self.crop.minX, y: -self.crop.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }
}

public enum RoundVideoPreparationError: Error, CustomStringConvertible {
    case noVideoTrack
    case nothingToKeep
    case exportUnavailable
    case exportFailed(Error?)
    case thumbnailFailed

    public var description: String {
        switch self {
        case .noVideoTrack:
            return "no video track"
        case .nothingToKeep:
            return "the crop or the trim leaves nothing"
        case .exportUnavailable:
            return "no export session for the asset"
        case let .exportFailed(error):
            return "export failed: \(String(describing: error))"
        case .thumbnailFailed:
            return "no first frame"
        }
    }
}

/// Fork: makes a picked video into what the round-video camera records, for `VideoMessageCameraScreen`'s
/// `existingVideo`: the square of `normalizedCrop`, at most a minute of `trimRange`, H.264 in SDR. The bitrate does
/// not matter here, since the screen always runs its own video-message export on send.
public func prepareRoundVideo(asset: AVAsset, normalizedCrop: CGRect, trimRange: Range<Double>?) -> Signal<VideoMessageCameraScreen.CaptureResult.Video, RoundVideoPreparationError> {
    return Signal { subscriber in
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            subscriber.putError(.noVideoTrack)
            return EmptyDisposable
        }
        let transformedSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        guard let geometry = RoundVideoExportGeometry(
            displaySize: CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height)),
            normalizedCrop: normalizedCrop,
            duration: asset.duration.seconds,
            trimRange: trimRange
        ) else {
            subscriber.putError(.nothingToKeep)
            return EmptyDisposable
        }

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(geometry.layerTransform(preferredTransform: videoTrack.preferredTransform), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: geometry.outputSide, height: geometry.outputSide)
        let frameRate = videoTrack.nominalFrameRate > 0.0 ? min(30.0, videoTrack.nominalFrameRate) : 30.0
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        videoComposition.instructions = [instruction]
        // A round video is SDR. Left to an HDR source's primaries (HLG, Dolby Vision), H.264 carries it washed out.
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        // 1280x720 encodes H.264 whatever the source's codec, and is larger than any output square.
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            subscriber.putError(.exportUnavailable)
            return EmptyDisposable
        }
        let outputUrl = roundVideoTemporaryFileUrl()
        exportSession.outputURL = outputUrl
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: geometry.timeRange.lowerBound, preferredTimescale: 600),
            end: CMTime(seconds: geometry.timeRange.upperBound, preferredTimescale: 600)
        )
        exportSession.videoComposition = videoComposition

        let imageGenerator = Atomic<AVAssetImageGenerator?>(value: nil)
        Logger.shared.log("RoundVideo", "export: crop=\(geometry.crop) side=\(geometry.outputSide) range=\(geometry.timeRange) fps=\(frameRate)")
        exportSession.exportAsynchronously {
            guard exportSession.status == .completed else {
                try? FileManager.default.removeItem(at: outputUrl)
                subscriber.putError(.exportFailed(exportSession.error))
                return
            }
            let result = AVURLAsset(url: outputUrl)
            let generator = AVAssetImageGenerator(asset: result)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: geometry.outputSide, height: geometry.outputSide)
            let _ = imageGenerator.swap(generator)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)], completionHandler: { _, image, _, _, _ in
                guard let image else {
                    try? FileManager.default.removeItem(at: outputUrl)
                    subscriber.putError(.thumbnailFailed)
                    return
                }
                let duration = result.duration.seconds
                subscriber.putNext(VideoMessageCameraScreen.CaptureResult.Video(
                    videoPath: outputUrl.path,
                    dimensions: PixelDimensions(width: Int32(geometry.outputSide), height: Int32(geometry.outputSide)),
                    duration: duration.isFinite ? duration : geometry.timeRange.upperBound - geometry.timeRange.lowerBound,
                    thumbnail: UIImage(cgImage: image)
                ))
                subscriber.putCompletion()
            })
        }

        return ActionDisposable {
            if exportSession.status == .exporting || exportSession.status == .waiting {
                exportSession.cancelExport()
            }
            imageGenerator.with { $0 }?.cancelAllCGImageGeneration()
        }
    }
}

/// A fresh file in the round videos' own temporary folder. The file must outlive the screen (the message's resource
/// reads it until the upload is done), so nothing removes it there; files from earlier days are removed here instead.
private func roundVideoTemporaryFileUrl() -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("round-video", isDirectory: true)
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let staleDate = Date(timeIntervalSinceNow: -24.0 * 60.0 * 60.0)
    if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
        for file in files {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < staleDate {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    return directory.appendingPathComponent("\(Int64.random(in: 0 ..< Int64.max)).mp4")
}
