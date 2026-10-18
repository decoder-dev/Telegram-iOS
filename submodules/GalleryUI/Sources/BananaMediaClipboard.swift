import Foundation
import UIKit
import AVFoundation
import AccountContext
import TelegramCore
import SwiftSignalKit
import SaveToCameraRoll

func bananaMediaClipboardImage(context: AccountContext, mediaReference: AnyMediaReference, timestamp: Double? = nil) -> Signal<UIImage?, NoError> {
    return fetchMediaData(context: context, userLocation: .other, mediaReference: mediaReference)
    |> filter { value, _ in
        if case let .data(data) = value { return data.isComplete }
        return false
    }
    |> take(1)
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { value, _ -> UIImage? in
        guard case let .data(data) = value else { return nil }
        guard let timestamp else { return UIImage(contentsOfFile: data.path) }
        let asset = AVURLAsset(url: URL(fileURLWithPath: data.path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let duration = CMTimeGetSeconds(asset.duration)
        let requested = timestamp.isFinite ? max(0.0, timestamp) : 0.0
        let time = duration.isFinite && duration > 0 ? min(requested, max(0, duration - 0.001)) : requested
        guard let image = try? generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil) else { return nil }
        return UIImage(cgImage: image)
    }
}
