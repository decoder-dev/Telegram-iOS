import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

/// Turns downloaded files into what Telegram sends: a muxed MP4, a preview JPEG, re-encoded JPEG photos.
/// Synchronous helpers block on file I/O; call them off the main thread.
enum BananaMediaProcessor {
    struct VideoInfo {
        let duration: Double
        let width: Int
        let height: Int
    }

    /// Joins a video-only MP4 and an AAC track without re-encoding. The moov atom is written first so that
    /// Telegram can stream the result.
    static func mux(videoURL: URL, audioURL: URL, outputURL: URL, completion: @escaping (Result<Void, BananaLinkDownloadError>) -> Void) -> AVAssetExportSession? {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        guard let sourceVideo = videoAsset.tracks(withMediaType: .video).first,
              let sourceAudio = audioAsset.tracks(withMediaType: .audio).first,
              let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let targetAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(.failure(.processingFailed))
            return nil
        }
        let videoDuration = videoAsset.duration
        do {
            try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideo, at: .zero)
            try targetAudio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(audioAsset.duration, videoDuration)), of: sourceAudio, at: .zero)
        } catch {
            completion(.failure(.processingFailed))
            return nil
        }
        targetVideo.preferredTransform = sourceVideo.preferredTransform
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            completion(.failure(.processingFailed))
            return nil
        }
        try? FileManager.default.removeItem(at: outputURL)
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.exportAsynchronously(completionHandler: {
            switch exporter.status {
            case .completed:
                completion(.success(()))
            case .cancelled:
                completion(.failure(.cancelled))
            default:
                completion(.failure(.processingFailed))
            }
        })
        return exporter
    }

    /// Duration and display size (after the track transform); nil when the file has no video track.
    static func videoInfo(_ url: URL) -> VideoInfo? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        let size = track.naturalSize.applying(track.preferredTransform)
        let seconds = asset.duration.seconds
        // The track header is file data: a non-finite or absurd size must not reach `Int(_:)`, which traps.
        let width = abs(size.width).rounded()
        let height = abs(size.height).rounded()
        guard width.isFinite, height.isFinite, width >= 1.0, height >= 1.0, width <= 65535.0, height <= 65535.0 else {
            return nil
        }
        return VideoInfo(duration: seconds.isFinite ? max(0.0, seconds) : 0.0, width: Int(width), height: Int(height))
    }

    /// First frame as a small JPEG for the message preview.
    static func thumbnail(videoURL: URL, maxPixelSize: CGFloat = 320.0) -> BananaJPEGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let image = try? generator.copyCGImage(at: CMTime.zero, actualTime: nil),
              let data = BananaMediaProcessor.jpegData(image, quality: 0.7) else {
            return nil
        }
        return BananaJPEGImage(data: data, width: image.width, height: image.height)
    }

    /// Decodes any image ImageIO understands, applies EXIF orientation, fits it into maxPixelSize (never
    /// upscales) and writes a JPEG. Returns the written size.
    static func normalizePhoto(sourceURL: URL, destinationURL: URL, maxPixelSize: Int = 2560) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.87] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return (image.width, image.height)
    }

    private static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
