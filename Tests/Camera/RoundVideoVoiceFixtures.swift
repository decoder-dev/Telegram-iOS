import AudioToolbox
import CoreMedia
import ForkVoiceDSP
import Foundation

private let timestamp = CMTime(value: 42, timescale: 1)

private func sampleBuffer<Sample>(from samples: [Sample], sampleRate: Int32, channels: Int, flags: UInt32, planar: Bool = false) -> CMSampleBuffer {
    let sampleByteCount = MemoryLayout<Sample>.size
    let frameCount = samples.count / channels
    let bytesPerFrame = sampleByteCount * (planar ? 1 : channels)
    var stream = AudioStreamBasicDescription(
        mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: flags | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian | (planar ? kAudioFormatFlagIsNonInterleaved : 0),
        mBytesPerPacket: UInt32(bytesPerFrame), mFramesPerPacket: 1, mBytesPerFrame: UInt32(bytesPerFrame),
        mChannelsPerFrame: UInt32(channels), mBitsPerChannel: UInt32(sampleByteCount * 8), mReserved: 0
    )
    var format: CMAudioFormatDescription?
    precondition(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &stream, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr)

    var block: CMBlockBuffer?
    samples.withUnsafeBytes { data in
        let memory = malloc(data.count)!
        memcpy(memory, data.baseAddress!, data.count)
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: memory, blockLength: data.count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr)
    }

    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: sampleRate), presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
    var result: CMSampleBuffer?
    let status = withUnsafePointer(to: bytesPerFrame) { sampleSize in
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: planar ? 0 : 1, sampleSizeArray: planar ? nil : sampleSize, sampleBufferOut: &result)
    }
    precondition(status == noErr)
    return result!
}

private func data(in sampleBuffer: CMSampleBuffer) -> Data {
    let block = CMSampleBufferGetDataBuffer(sampleBuffer)!
    var samplePointer: UnsafeMutablePointer<CChar>?
    precondition(CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &samplePointer) == kCMBlockBufferNoErr)
    return Data(bytes: samplePointer!, count: CMBlockBufferGetDataLength(block))
}

private func verify(_ original: CMSampleBuffer, effect: RoundVideoVoiceEffect) {
    let originalSamples = data(in: original)
    let processed = effect.process(original)!
    precondition(data(in: original) == originalSamples, "Capture buffers must not be modified")
    precondition(data(in: processed).count == originalSamples.count && data(in: processed) != originalSamples)
    precondition(CMSampleBufferGetNumSamples(processed) == CMSampleBufferGetNumSamples(original))
    precondition(CMSampleBufferGetPresentationTimeStamp(processed) == timestamp)
    precondition(CMSampleBufferGetDuration(processed) == CMSampleBufferGetDuration(original))
}

@main
private struct RoundVideoVoiceFixtures {
    static func main() {
        ForkVoiceCaptureSetRoundVideoParams(nil)
        precondition(RoundVideoVoiceEffectConfiguration.current() == nil)

        var params = ForkVoiceParams()
        ForkVoiceParamsSetIdentity(&params)
        params.ringModMix = 0.9
        params.ringModHz = 55.0
        ForkVoiceCaptureSetRoundVideoParams(&params)
        let snapshot = RoundVideoVoiceEffectConfiguration.current()!
        ForkVoiceCaptureSetRoundVideoParams(nil)
        precondition(RoundVideoVoiceEffectConfiguration.current() == nil)

        let initial = snapshot.makeEffect()
        let resumed = snapshot.makeEffect()
        let voice = [Int16](repeating: 8192, count: 256)
        verify(sampleBuffer(from: voice, sampleRate: 48000, channels: 1, flags: kAudioFormatFlagIsSignedInteger), effect: initial)
        verify(sampleBuffer(from: voice, sampleRate: 16000, channels: 1, flags: kAudioFormatFlagIsSignedInteger), effect: initial)
        verify(sampleBuffer(from: voice, sampleRate: 48000, channels: 2, flags: kAudioFormatFlagIsSignedInteger), effect: resumed)
        verify(sampleBuffer(from: [Float](repeating: 0.25, count: 512), sampleRate: 44100, channels: 2, flags: kAudioFormatFlagIsFloat, planar: true), effect: resumed)
        let unsupported = sampleBuffer(from: [Int8](repeating: 50, count: 256), sampleRate: 48000, channels: 1, flags: kAudioFormatFlagIsSignedInteger)
        precondition(resumed.process(unsupported) == nil)
        print("Round-video voice effect preserves timing and the capture buffer across recording segments")
    }
}
