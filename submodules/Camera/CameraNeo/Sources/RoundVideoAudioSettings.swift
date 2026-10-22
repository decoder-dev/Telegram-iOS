import Foundation
import AVFoundation
import AudioToolbox
import CoreMedia

// Ported from Donutgram: the AAC bit rate a round video's sound is written at when the encoder allows it; what the built-in
// microphone (48 kHz) has always recorded at.
let roundVideoPreferredAudioBitRate = 64_000

// The bit rates the system AAC encoder accepts for mono or stereo sound at `sampleRate`, as it reports them itself:
// single values or closed ranges.
// A headset microphone is much slower than the built-in one: a Bluetooth headset in a call-style route delivers 8, 16
// or 24 kHz, and at 8 and 16 kHz the encoder refuses 64 kbps. The writer's `canApply` does not notice; `startWriting`
// then fails with "Cannot Encode Media", and the recorder gave up the whole round video, which closed after a moment.
func roundVideoApplicableAudioBitRates(sampleRate: Double, channels: UInt32) -> [ClosedRange<Int>] {
    guard sampleRate > 0.0, channels > 0 else {
        return []
    }
    var inputDescription = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2 * channels,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2 * channels,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 16,
        mReserved: 0
    )
    var outputDescription = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatMPEG4AAC,
        mFormatFlags: 0,
        mBytesPerPacket: 0,
        mFramesPerPacket: 1024,
        mBytesPerFrame: 0,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 0,
        mReserved: 0
    )
    var converter: AudioConverterRef?
    guard AudioConverterNew(&inputDescription, &outputDescription, &converter) == noErr, let converter else {
        return []
    }
    defer {
        AudioConverterDispose(converter)
    }

    var size: UInt32 = 0
    guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates, &size, nil) == noErr else {
        return []
    }
    let count = Int(size) / MemoryLayout<AudioValueRange>.size
    guard count > 0 else {
        return []
    }
    var ranges = [AudioValueRange](repeating: AudioValueRange(mMinimum: 0.0, mMaximum: 0.0), count: count)
    let status = ranges.withUnsafeMutableBytes { bytes in
        AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates, &size, bytes.baseAddress!)
    }
    guard status == noErr else {
        return []
    }
    return ranges.prefix(Int(size) / MemoryLayout<AudioValueRange>.size).compactMap { range in
        let lowerBound = Int(range.mMinimum)
        let upperBound = Int(range.mMaximum)
        guard lowerBound > 0, upperBound >= lowerBound else {
            return nil
        }
        return lowerBound ... upperBound
    }
}

// The preferred bit rate if the encoder accepts it, otherwise the highest accepted one below it.
func roundVideoAudioBitRate(applicable: [ClosedRange<Int>]) -> Int? {
    if applicable.contains(where: { $0.contains(roundVideoPreferredAudioBitRate) }) {
        return roundVideoPreferredAudioBitRate
    }
    return applicable.compactMap { range -> Int? in
        guard range.lowerBound <= roundVideoPreferredAudioBitRate else {
            return nil
        }
        return min(range.upperBound, roundVideoPreferredAudioBitRate)
    }.max()
}

// The AAC settings for the microphone samples described by `formatDescription`, or nil if the writer accepts none.
// The bit rate is the preferred one if the encoder lists it, otherwise the highest listed one below it; if the encoder
// lists none, it is left to the encoder.
func roundVideoAudioSettings(
    formatDescription: CMFormatDescription,
    canApply: ([String: Any]) -> Bool
) -> [String: Any]? {
    var settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC
    ]
    if let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
        let sampleRate = streamDescription.pointee.mSampleRate
        let channels = streamDescription.pointee.mChannelsPerFrame
        settings[AVSampleRateKey] = sampleRate
        settings[AVNumberOfChannelsKey] = channels

        let applicable = roundVideoApplicableAudioBitRates(sampleRate: sampleRate, channels: channels)
        if let bitRate = roundVideoAudioBitRate(applicable: applicable) {
            settings[AVEncoderBitRateKey] = bitRate
        }
    }

    var channelLayoutSize = 0
    if let channelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, sizeOut: &channelLayoutSize), channelLayoutSize > 0 {
        settings[AVChannelLayoutKey] = Data(bytes: channelLayout, count: channelLayoutSize)
    }

    if canApply(settings) {
        return settings
    }
    if settings.removeValue(forKey: AVEncoderBitRateKey) != nil, canApply(settings) {
        return settings
    }
    return nil
}
