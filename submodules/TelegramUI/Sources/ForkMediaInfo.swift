import Foundation
import UIKit
import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers
import Postbox
import TelegramCore

/// Regram "media info" (RGMediaMetadata), reduced for Extras ▸ Media: describes a message's photo, video, GIF,
/// audio or file from what is already on the device (the finished file through ImageIO / AVFoundation), else from
/// the attributes the server declared. It never fetches; whatever cannot be read is shown as unknown.
/// Regram's reader for the header of a partially streamed MP4 is not ported.
enum ForkMediaInfo {
    /// Returns the report text for the first media of `message` that can be described, or nil if there is none.
    static func report(mediaBox: MediaBox, media: Media, russian: Bool) -> String? {
        var lines: [(String, String)] = []
        let unknown = russian ? "неизвестно" : "unknown"
        func add(_ key: String, _ value: String?) {
            lines.append((key, value ?? unknown))
        }

        if let image = media as? TelegramMediaImage {
            guard let representation = largestImageRepresentation(image.representations) else {
                return nil
            }
            let path = mediaBox.completedResourcePath(representation.resource)
            let probe = path.flatMap(probeImage(path:))
            add(russian ? "Тип" : "Type", russian ? "Изображение" : "Image")
            add(russian ? "Формат" : "Format", probe?.format)
            add(russian ? "Разрешение" : "Resolution", formatResolution(width: probe?.width ?? Int(representation.dimensions.width), height: probe?.height ?? Int(representation.dimensions.height)))
            add(russian ? "Размер" : "Size", formatBytes(fileSize(path) ?? representation.resource.size))
            return finish(lines, downloaded: path != nil, russian: russian)
        } else if let file = media as? TelegramMediaFile {
            var isVideo = false
            var isAudio = false
            var isAnimated = false
            var declaredDuration: Double?
            var declaredWidth: Int?
            var declaredHeight: Int?
            var declaredCodec: String?
            for attribute in file.attributes {
                switch attribute {
                case let .Video(duration, size, _, _, _, videoCodec):
                    isVideo = true
                    declaredDuration = duration
                    declaredWidth = Int(size.width)
                    declaredHeight = Int(size.height)
                    declaredCodec = videoCodec
                case let .Audio(_, duration, _, _, _):
                    isAudio = true
                    if declaredDuration == nil {
                        declaredDuration = Double(duration)
                    }
                case let .ImageSize(size):
                    if declaredWidth == nil {
                        declaredWidth = Int(size.width)
                        declaredHeight = Int(size.height)
                    }
                case .Animated:
                    isAnimated = true
                default:
                    break
                }
            }
            let isTimeBased = isVideo || isAudio
            let pathExtension = UTType(mimeType: file.mimeType)?.preferredFilenameExtension ?? (isAudio && !isVideo ? "m4a" : "mp4")
            let path = isTimeBased ? mediaBox.completedResourcePath(file.resource, pathExtension: pathExtension) : mediaBox.completedResourcePath(file.resource)
            let bytes = fileSize(path) ?? file.size

            let typeTitle: String
            if isVideo {
                typeTitle = isAnimated ? (russian ? "Анимация" : "Animation") : (russian ? "Видео" : "Video")
            } else if isAudio {
                typeTitle = russian ? "Аудио" : "Audio"
            } else if file.mimeType.hasPrefix("image/") {
                typeTitle = russian ? "Изображение" : "Image"
            } else {
                typeTitle = russian ? "Файл" : "File"
            }
            add(russian ? "Тип" : "Type", typeTitle)
            add(russian ? "Формат" : "Format", file.mimeType.isEmpty ? nil : file.mimeType)

            if isTimeBased {
                let probe = path.flatMap(probeAsset(path:)) ?? AssetProbe()
                let duration = probe.duration ?? declaredDuration
                if !isAudio || isVideo {
                    add(russian ? "Разрешение" : "Resolution", formatResolution(width: probe.width ?? declaredWidth, height: probe.height ?? declaredHeight))
                }
                add(russian ? "Длительность" : "Duration", duration.flatMap(formatDuration))
                add(russian ? "Размер" : "Size", formatBytes(bytes))
                if isVideo {
                    add(russian ? "Частота кадров" : "Frame rate", probe.frameRate.map { String(format: "%.2f fps", $0) })
                }
                var bitrate = probe.bitrate
                if bitrate == nil, let bytes, let duration, duration > 0 {
                    // Whole-file average when the track reports no rate of its own.
                    bitrate = Double(bytes) * 8.0 / duration
                }
                add(russian ? "Битрейт" : "Bitrate", bitrate.map(formatBitrate))
                if isVideo {
                    add(russian ? "Кодек" : "Codec", probe.codec ?? declaredCodec.map(declaredCodecName))
                }
                if !isAnimated {
                    add(russian ? "Аудиокодек" : "Audio codec", probe.audioCodec)
                }
            } else {
                let probe = path.flatMap(probeImage(path:))
                add(russian ? "Разрешение" : "Resolution", formatResolution(width: probe?.width ?? declaredWidth, height: probe?.height ?? declaredHeight))
                add(russian ? "Размер" : "Size", formatBytes(bytes))
            }
            return finish(lines, downloaded: path != nil, russian: russian)
        }
        return nil
    }

    private static func finish(_ lines: [(String, String)], downloaded: Bool, russian: Bool) -> String {
        var text = lines.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        if !downloaded {
            text += "\n\n" + (russian ? "Файл не загружен на устройство: показаны только заявленные сервером значения." : "This file is not downloaded: only the values the server declared are shown.")
        }
        return text
    }

    private static func fileSize(_ path: String?) -> Int64? {
        guard let path, let attributes = try? FileManager.default.attributesOfItem(atPath: path), let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            return nil
        }
        return size.int64Value
    }

    private struct ImageProbe {
        var width: Int?
        var height: Int?
        var format: String?
    }

    private static func probeImage(path: String) -> ImageProbe? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, options) else {
            return nil
        }
        var result = ImageProbe()
        if let type = CGImageSourceGetType(source) {
            let identifier = type as String
            result.format = UTType(identifier)?.preferredFilenameExtension?.uppercased() ?? identifier
        }
        if CGImageSourceGetCount(source) > 0, let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] {
            var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            // EXIF orientations 5-8 are rotated by 90 degrees: report the size as displayed.
            if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 && orientation <= 8 {
                swap(&width, &height)
            }
            result.width = width
            result.height = height
        }
        if result.width == nil && result.format == nil {
            return nil
        }
        return result
    }

    private struct AssetProbe {
        var width: Int?
        var height: Int?
        var duration: Double?
        var frameRate: Float?
        var bitrate: Double?
        var codec: String?
        var audioCodec: String?
    }

    private static func probeAsset(path: String) -> AssetProbe? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path), options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        var result = AssetProbe()
        let duration = asset.duration
        if duration.isValid && !duration.isIndefinite && duration.seconds.isFinite && duration.seconds > 0 {
            result.duration = duration.seconds
        }
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            if size.width != 0 && size.height != 0 {
                result.width = Int(abs(size.width).rounded())
                result.height = Int(abs(size.height).rounded())
            }
            if track.nominalFrameRate > 0 {
                result.frameRate = track.nominalFrameRate
            }
            if track.estimatedDataRate > 0 {
                result.bitrate = Double(track.estimatedDataRate)
            }
            if let subtype = mediaSubType(track.formatDescriptions.first) {
                result.codec = videoCodecName(fourCC(subtype))
            }
        }
        if let track = asset.tracks(withMediaType: .audio).first {
            if let subtype = mediaSubType(track.formatDescriptions.first) {
                result.audioCodec = audioCodecName(fourCC(subtype))
            }
            if result.bitrate == nil, track.estimatedDataRate > 0, asset.tracks(withMediaType: .video).isEmpty {
                result.bitrate = Double(track.estimatedDataRate)
            }
        }
        return result
    }

    private static func mediaSubType(_ description: Any?) -> FourCharCode? {
        guard let description else {
            return nil
        }
        let object = description as AnyObject
        guard CFGetTypeID(object) == CMFormatDescriptionGetTypeID() else {
            return nil
        }
        let formatDescription = object as! CMFormatDescription
        return CMFormatDescriptionGetMediaSubType(formatDescription)
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        return (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func videoCodecName(_ fourcc: String) -> String? {
        switch fourcc {
        case "":
            return nil
        case "avc1", "avc3":
            return "H.264"
        case "hvc1", "hev1":
            return "HEVC"
        case "vp08":
            return "VP8"
        case "vp09":
            return "VP9"
        case "av01":
            return "AV1"
        case "mp4v":
            return "MPEG-4"
        default:
            return fourcc.uppercased()
        }
    }

    private static func audioCodecName(_ fourcc: String) -> String? {
        switch fourcc {
        case "":
            return nil
        case "aac", "mp4a":
            return "AAC"
        case "opus":
            return "Opus"
        case ".mp3":
            return "MP3"
        case "alac":
            return "ALAC"
        case "flac":
            return "FLAC"
        default:
            return fourcc.uppercased()
        }
    }

    private static func declaredCodecName(_ codec: String) -> String {
        switch codec.lowercased() {
        case "h264", "avc":
            return "H.264"
        case "h265", "hevc":
            return "HEVC"
        case "av1", "av01":
            return "AV1"
        case "vp9":
            return "VP9"
        case "vp8":
            return "VP8"
        default:
            return codec.uppercased()
        }
    }

    private static func formatResolution(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }
        return "\(width) × \(height)"
    }

    private static func formatBytes(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else {
            return nil
        }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024.0 && index < units.count - 1 {
            value /= 1024.0
            index += 1
        }
        if index == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.2f %@", value, units[index])
    }

    private static func formatBitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000.0 {
            return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000.0)
        } else if bitsPerSecond >= 1_000.0 {
            return String(format: "%.0f Kbps", bitsPerSecond / 1_000.0)
        }
        return String(format: "%.0f bps", bitsPerSecond)
    }

    private static func formatDuration(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
