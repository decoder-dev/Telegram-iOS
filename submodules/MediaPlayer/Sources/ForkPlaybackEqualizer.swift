import Foundation
import CoreMedia
import ForkVoiceDSP

// Fork (Ghostgram): the playback equalizer of one audio renderer. The band gains are published by the app
// (`ForkAudioEqualizerSetParameters`, from SharedAccountContext); players only own their instances, and no C type
// leaks into this module's public API.

/// What a player plays, for the playback equalizer. Service sounds (the recording tone, the silence
/// that keeps the audio session alive) pass nil and are never equalized.
public enum ForkPlaybackEqualizerKind {
    case audio
    case roundVideo
    case video
}

/// The equalizer of one renderer: filter states live here, the gains are shared.
final class ForkPlaybackEqualizer {
    private let instance: OpaquePointer

    init?(kind: ForkPlaybackEqualizerKind?) {
        guard let kind else {
            return nil
        }
        let cKind: ForkAudioEqualizerKind
        switch kind {
        case .audio:
            cKind = ForkAudioEqualizerKindAudio
        case .roundVideo:
            cKind = ForkAudioEqualizerKindRoundVideo
        case .video:
            cKind = ForkAudioEqualizerKindVideo
        }
        guard let instance = ForkAudioEqualizerCreate(cKind) else {
            return nil
        }
        self.instance = instance
    }

    deinit {
        ForkAudioEqualizerDestroy(self.instance)
    }

    /// Realtime-safe: interleaved Int16, in place.
    func process(samples: UnsafeMutableRawPointer, byteCount: Int, channels: Int, sampleRate: UInt32) {
        let frames = byteCount / (2 * channels)
        if frames <= 0 {
            return
        }
        ForkAudioEqualizerProcessInt16(self.instance, samples.assumingMemoryBound(to: Int16.self), frames, channels, sampleRate)
    }

    /// A decoded LPCM sample buffer, in place, before it is enqueued (player data queue, not realtime).
    /// Anything that is not packed signed 16-bit PCM in one contiguous block is left as it is.
    func process(sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), let description = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }
        let asbd = description.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM, asbd.mBitsPerChannel == 16, (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0, (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0 else {
            return
        }
        let channels = Int(asbd.mChannelsPerFrame)
        guard channels > 0, asbd.mSampleRate > 0.0, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr, let dataPointer, lengthAtOffset == totalLength else {
            return
        }
        self.process(samples: UnsafeMutableRawPointer(dataPointer), byteCount: totalLength, channels: channels, sampleRate: UInt32(asbd.mSampleRate))
    }
}
