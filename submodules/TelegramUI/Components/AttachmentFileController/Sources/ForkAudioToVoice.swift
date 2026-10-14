// "Send music as voice message", ported from Donutgram (github.com/kittenello/donutgram,
// commit a5e267f, DonutgramAudioToVoice.swift). The track is decoded with AVAssetReader to
// 48 kHz mono 16-bit PCM, re-encoded to Ogg/Opus with the same writer the voice recorder uses,
// and returned as a local voice-note file with a 100-sample waveform.
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import OpusBinding
import AudioWaveform

private enum ForkAudioToVoiceError: Error {
    case failed
}

func forkAudioToVoice(context: AccountContext, reference: AnyMediaReference) -> Signal<TelegramMediaFile?, NoError> {
    guard let file = reference.media as? TelegramMediaFile else {
        return .single(nil)
    }
    // MediaBox's raw cache path has no extension. AVFoundation needs the original format hint,
    // especially for music fetched from the profile rather than a local file picker.
    let originalExtension = file.fileName.map { ($0 as NSString).pathExtension.lowercased() } ?? ""
    let fallbackExtensions: [String: String] = [
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3",
        "audio/mp4": "m4a",
        "audio/x-m4a": "m4a",
        "audio/flac": "flac",
        "audio/x-flac": "flac",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/aac": "aac",
        "audio/ogg": "ogg",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
        "video/x-m4v": "m4v"
    ]
    // The name is the sender's. It only needs to hint the container, so anything but a short plain
    // alphanumeric extension is ignored in favour of the MIME type.
    let isPlainExtension = !originalExtension.isEmpty && originalExtension.count <= 8 && originalExtension.unicodeScalars.allSatisfy { ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) }
    let pathExtension = isPlainExtension ? originalExtension : fallbackExtensions[file.mimeType.lowercased()]
    let mediaBox = context.account.postbox.mediaBox
    let resourceData = Signal<MediaResourceData, ForkAudioToVoiceError> { subscriber in
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .other, userContentType: MediaResourceUserContentType(file: file), reference: reference.resourceReference(file.resource)).start(error: { _ in
            subscriber.putError(.failed)
        })
        let data = (mediaBox.resourceData(file.resource, pathExtension: pathExtension, option: .complete(waitUntilFetchStatus: true))
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            subscriber.putNext(data)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetch.dispose()
            data.dispose()
        }
    }
    return resourceData
    |> mapToSignal { data -> Signal<TelegramMediaFile?, ForkAudioToVoiceError> in
        return Signal { subscriber in
            let cancelled = Atomic(value: false)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool {
                    forkEncodeVoice(path: data.path, cancelled: cancelled)
                }
                if cancelled.with({ $0 }) {
                    return
                }
                guard let result else {
                    subscriber.putError(.failed)
                    return
                }
                subscriber.putNext(forkMakeVoiceFile(mediaBox: mediaBox, result: result))
                subscriber.putCompletion()
            }
            return ActionDisposable {
                let _ = cancelled.swap(true)
            }
        }
    }
    |> `catch` { _ -> Signal<TelegramMediaFile?, NoError> in
        return .single(nil)
    }
}

/// The sound of a video (or a round video) re-encoded as a voice message. The decoder reads whichever audio track the
/// container has, so this is the same conversion as for music; a video with no audio track yields nil.
public func forkVideoToVoice(context: AccountContext, fileReference: FileMediaReference) -> Signal<TelegramMediaFile?, NoError> {
    return forkAudioToVoice(context: context, reference: fileReference.abstract)
}

/// A voice message re-sent as an ordinary audio file. The Opus data is not re-encoded: it is copied into a
/// new local file whose audio attribute is not a voice note, so the server and the other clients list it as
/// music (with `title`) instead of a voice message.
public func forkVoiceToAudio(context: AccountContext, fileReference: FileMediaReference, title: String) -> Signal<TelegramMediaFile?, NoError> {
    let file = fileReference.media
    var duration = 0
    for attribute in file.attributes {
        if case let .Audio(_, value, _, _, _) = attribute {
            duration = value
        }
    }
    let mediaBox = context.account.postbox.mediaBox
    let resourceData = Signal<MediaResourceData, NoError> { subscriber in
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .other, userContentType: MediaResourceUserContentType(file: file), reference: fileReference.resourceReference(file.resource)).start()
        let data = (mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: true))
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            subscriber.putNext(data)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetch.dispose()
            data.dispose()
        }
    }
    return resourceData
    |> mapToSignal { data -> Signal<TelegramMediaFile?, NoError> in
        return Signal { subscriber in
            DispatchQueue.global(qos: .userInitiated).async {
                // A voice note is small; refuse to load an oversized file whole just to copy it.
                let size = ((try? FileManager.default.attributesOfItem(atPath: data.path))?[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0, size <= 64 * 1024 * 1024, let bytes = try? Data(contentsOf: URL(fileURLWithPath: data.path)), !bytes.isEmpty else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                let id = Int64.random(in: Int64.min ... Int64.max)
                let resource = LocalFileMediaResource(fileId: id)
                mediaBox.storeResourceData(resource.id, data: bytes)
                let converted = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "audio/ogg", size: Int64(bytes.count), attributes: [.FileName(fileName: title + ".ogg"), .Audio(isVoice: false, duration: duration, title: title, performer: nil, waveform: nil)], alternativeRepresentations: [])
                subscriber.putNext(converted)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
}

/// Stores the encoded Ogg/Opus data as a local resource and wraps it in a voice-note file.
private func forkMakeVoiceFile(mediaBox: MediaBox, result: (data: Data, duration: Int, waveform: Data)) -> TelegramMediaFile {
    let id = Int64.random(in: Int64.min ... Int64.max)
    let resource = LocalFileMediaResource(fileId: id)
    mediaBox.storeResourceData(resource.id, data: result.data)
    return TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "audio/ogg", size: Int64(result.data.count), attributes: [.Audio(isVoice: true, duration: result.duration, title: nil, performer: nil, waveform: result.waveform)], alternativeRepresentations: [])
}

/// The same conversion for an audio file picked in Files: `bookmarkData` is the
/// `ICloudFileDescription.urlData` of the pick (a base64 security-scoped bookmark), so the file is read
/// where it lives, under the scope the picker granted, without copying it first.
public func forkAudioToVoice(context: AccountContext, bookmarkData: String) -> Signal<TelegramMediaFile?, NoError> {
    let mediaBox = context.account.postbox.mediaBox
    return Signal { subscriber in
        let cancelled = Atomic(value: false)
        DispatchQueue.global(qos: .userInitiated).async {
            var result: (data: Data, duration: Int, waveform: Data)?
            if let bookmark = Data(base64Encoded: bookmarkData) {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) {
                    let scopedAccess = url.startAccessingSecurityScopedResource()
                    if scopedAccess || FileManager.default.isReadableFile(atPath: url.path) {
                        result = autoreleasepool {
                            forkEncodeVoice(path: url.path, cancelled: cancelled)
                        }
                    }
                    if scopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            if cancelled.with({ $0 }) {
                return
            }
            if let result {
                subscriber.putNext(forkMakeVoiceFile(mediaBox: mediaBox, result: result))
            } else {
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        }
        return ActionDisposable {
            let _ = cancelled.swap(true)
        }
    }
}

/// Longest input converted to a voice message, in seconds of 48 kHz mono 16-bit audio.
private let forkMaximumVoiceSeconds = 3600

private func forkEncodeVoice(path: String, cancelled: Atomic<Bool>) -> (data: Data, duration: Int, waveform: Data)? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else {
        return nil
    }
    let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ])
    guard reader.canAdd(output) else {
        return nil
    }
    reader.add(output)
    guard reader.startReading() else {
        return nil
    }
    defer {
        reader.cancelReading()
    }
    let writer = TGOggOpusWriter()
    let dataItem = TGDataItem()
    guard writer.begin(with: dataItem) else {
        return nil
    }

    // The Ogg writer expects 48 kHz mono PCM in 960-sample (20 ms) packets.
    let packetSize = 1920
    var pending = Data()
    var totalBytes = 0
    var peaks: [Int] = []
    func writePacket(_ packet: inout Data) -> Bool {
        var peak = 0
        packet.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                let sample = Int16(bitPattern: UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                peak = max(peak, abs(Int(sample)))
            }
        }
        peaks.append(peak)
        return packet.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Bool in
            return writer.writeFrame(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(bytes.count))
        }
    }
    while reader.status == .reading {
        if cancelled.with({ $0 }) {
            return nil
        }
        let chunk: Data? = autoreleasepool {
            guard let sample = output.copyNextSampleBuffer() else {
                return nil
            }
            // A decoded audio CMSampleBuffer need not expose a CMBlockBuffer via GetDataBuffer,
            // so read it through the audio buffer list (as the recording tone decoder does).
            var audioBuffers = AudioBufferList()
            var retainedBlockBuffer: CMBlockBuffer?
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil, bufferListOut: &audioBuffers, bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &retainedBlockBuffer)
            guard status == noErr, audioBuffers.mNumberBuffers == 1 else {
                return nil
            }
            let count = CMSampleBufferGetNumSamples(sample) * MemoryLayout<Int16>.size
            guard count > 0 else {
                return Data()
            }
            guard let bytes = audioBuffers.mBuffers.mData, Int(audioBuffers.mBuffers.mDataByteSize) >= count else {
                return nil
            }
            // Keep the retained buffer alive until its PCM bytes have been copied.
            return withExtendedLifetime(retainedBlockBuffer) {
                return Data(bytes: bytes, count: count)
            }
        }
        guard let chunk else {
            break
        }
        totalBytes += chunk.count
        // A voice message is not a podcast: refuse to spend minutes of CPU and tens of megabytes of
        // Opus on an hours-long track or a hostile container that claims to be endless.
        if totalBytes > forkMaximumVoiceSeconds * 96000 {
            return nil
        }
        pending.append(chunk)
        var consumed = 0
        while pending.count - consumed >= packetSize {
            if cancelled.with({ $0 }) {
                return nil
            }
            var packet = pending.subdata(in: consumed ..< consumed + packetSize)
            guard writePacket(&packet) else {
                return nil
            }
            consumed += packetSize
        }
        if consumed != 0 {
            pending.removeSubrange(0 ..< consumed)
        }
    }
    guard reader.status == .completed, totalBytes > 0 else {
        return nil
    }
    if !pending.isEmpty {
        pending.append(Data(count: packetSize - pending.count))
        guard writePacket(&pending) else {
            return nil
        }
    }
    guard writer.writeFrame(nil, frameByteCount: 0), let data = dataItem.data(), !data.isEmpty else {
        return nil
    }
    let peak = max(2500, peaks.max() ?? 0)
    var samples = Data(count: 100 * MemoryLayout<Int16>.size)
    samples.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
        let values = bytes.bindMemory(to: Int16.self)
        for index in 0 ..< 100 {
            let start = index * peaks.count / 100
            let end = min(peaks.count, max(start + 1, (index + 1) * peaks.count / 100))
            let value = start < end ? (peaks[start ..< end].max() ?? 0) : 0
            values[index] = Int16(min(31, value * 31 / peak))
        }
    }
    let waveform = AudioWaveform(samples: samples, peak: 31).makeBitstream()
    return (data, Int(ceil(Double(totalBytes) / 96000.0)), waveform)
}
