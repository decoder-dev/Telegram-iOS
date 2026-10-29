import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit
import TelegramCore

/// Fork: turns an existing video into what the round-video camera records, so `VideoMessageCameraScreen` can show,
/// trim and send it exactly like a recording (`existingVideo`). The camera records a square, so the video is cut to
/// the square `normalizedCrop` (0...1 of the displayed frame), kept to `trimStart..<trimEnd` (at most a minute, as a
/// recording) and drawn at no more than the camera's 480 pt side. The bitrate does not matter here: a video from this
/// path always goes through the screen's own video-message export on send.
public func roundVideoCaptureResult(asset: AVAsset, normalizedCrop: CGRect, trimStart: Double, trimEnd: Double) -> Signal<VideoMessageCameraScreen.CaptureResult.Video?, NoError> {
    return Signal { subscriber in
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let transform = videoTrack.preferredTransform
        let transformedSize = videoTrack.naturalSize.applying(transform)
        let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard displaySize.width >= 16.0, displaySize.height >= 16.0 else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }

        var crop = CGRect(
            x: normalizedCrop.minX * displaySize.width,
            y: normalizedCrop.minY * displaySize.height,
            width: normalizedCrop.width * displaySize.width,
            height: normalizedCrop.height * displaySize.height
        ).intersection(CGRect(origin: .zero, size: displaySize))
        if crop.isNull || crop.width < 16.0 || crop.height < 16.0 {
            crop = CGRect(origin: .zero, size: displaySize)
        }
        let cropSide = min(crop.width, crop.height)
        crop = CGRect(x: crop.midX - cropSide / 2.0, y: crop.midY - cropSide / 2.0, width: cropSide, height: cropSide)

        let outputSide = max(160.0, min(480.0, (cropSide / 16.0).rounded(.down) * 16.0))
        let scale = outputSide / cropSide

        let assetDuration = asset.duration.seconds
        let start = max(0.0, trimStart)
        let end = min(assetDuration.isFinite ? assetDuration : start + 60.0, trimEnd > start ? trimEnd : assetDuration, start + 60.0)
        guard end > start else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))

        // preferredTransform maps the track into the displayed frame; from there the crop moves to the origin and is
        // scaled to the output square.
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(
            transform
                .concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: outputSide, height: outputSide)
        let frameRate = videoTrack.nominalFrameRate > 0.0 ? min(30.0, videoTrack.nominalFrameRate) : 30.0
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rounded()))
        videoComposition.instructions = [instruction]
        // An HDR (HLG or Dolby Vision) recording is tone-mapped to SDR, as a round video is: left to the source's
        // primaries, H.264 would carry it washed out.
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        // 1280x720 stays H.264 whatever the source codec, and is larger than the output square.
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let outputPath = NSTemporaryDirectory() + "round-video-\(Int64.random(in: 0 ..< Int64.max)).mp4"
        let outputUrl = URL(fileURLWithPath: outputPath)
        exportSession.outputURL = outputUrl
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = timeRange
        exportSession.videoComposition = videoComposition

        Logger.shared.log("RoundVideo", "export: display=\(displaySize) crop=\(crop) side=\(outputSide) range=\(start)..\(end) fps=\(frameRate)")
        exportSession.exportAsynchronously {
            guard exportSession.status == .completed else {
                Logger.shared.log("RoundVideo", "export failed: status=\(exportSession.status.rawValue) error=\(String(describing: exportSession.error))")
                try? FileManager.default.removeItem(at: outputUrl)
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return
            }
            let result = AVURLAsset(url: outputUrl)
            let duration = result.duration.seconds
            let imageGenerator = AVAssetImageGenerator(asset: result)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: outputSide, height: outputSide)
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)], completionHandler: { _, image, _, _, _ in
                let thumbnail = image.flatMap { UIImage(cgImage: $0) } ?? UIImage()
                subscriber.putNext(VideoMessageCameraScreen.CaptureResult.Video(
                    videoPath: outputPath,
                    dimensions: PixelDimensions(width: Int32(outputSide), height: Int32(outputSide)),
                    duration: duration.isFinite ? duration : end - start,
                    thumbnail: thumbnail
                ))
                subscriber.putCompletion()
            })
        }

        return ActionDisposable {
            if exportSession.status == .exporting || exportSession.status == .waiting {
                exportSession.cancelExport()
            }
        }
    }
}
