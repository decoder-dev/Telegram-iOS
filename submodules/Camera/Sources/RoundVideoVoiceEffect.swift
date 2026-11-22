import AudioToolbox
import CoreMedia
import ForkVoiceDSP
import Foundation

/// A camera keeps the same voice setting for every segment of one round-video recording.
public struct RoundVideoVoiceEffectConfiguration {
    fileprivate let params: ForkVoiceParams

    static func current() -> RoundVideoVoiceEffectConfiguration? {
        var params = ForkVoiceParams()
        guard ForkVoiceCaptureGetRoundVideoParams(&params) else {
            return nil
        }
        return RoundVideoVoiceEffectConfiguration(params: params)
    }

    public func makeEffect() -> RoundVideoVoiceEffect {
        return RoundVideoVoiceEffect(configuration: self)
    }
}

/// Owned by one recorder and used on that recorder's serial queue.
public final class RoundVideoVoiceEffect {
    private let configuration: RoundVideoVoiceEffectConfiguration
    private var chain: OpaquePointer?
    private var sampleRate: UInt32 = 0

    fileprivate init(configuration: RoundVideoVoiceEffectConfiguration) {
        self.configuration = configuration
    }

    deinit {
        ForkVoiceChainDestroy(self.chain)
    }

    /// Creates a processed buffer without modifying the shared capture data. Failure must stop recording.
    public func process(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format),
              let source = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        let asbd = description.pointee
        let flags = asbd.mFormatFlags
        let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
        let isPlanar = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let channelCount = Int(asbd.mChannelsPerFrame)
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              (flags & kAudioFormatFlagIsBigEndian) == kAudioFormatFlagsNativeEndian,
              asbd.mFramesPerPacket == 1, frameCount > 0, channelCount > 0,
              let sampleRate = UInt32(exactly: asbd.mSampleRate.rounded()), sampleRate > 0,
              isFloat ? asbd.mBitsPerChannel == 32 : asbd.mBitsPerChannel == 16 && (flags & kAudioFormatFlagIsSignedInteger) != 0 else {
            return nil
        }
        let sampleByteCount = isFloat ? MemoryLayout<Float>.size : MemoryLayout<Int16>.size
        let bytesPerFrame = sampleByteCount * channelCount
        let (dataLength, overflow) = bytesPerFrame.multipliedReportingOverflow(by: frameCount)
        guard !overflow, CMBlockBufferGetDataLength(source) == dataLength,
              Int(asbd.mBytesPerFrame) == (isPlanar ? sampleByteCount : bytesPerFrame) else {
            return nil
        }

        if self.sampleRate != sampleRate {
            ForkVoiceChainDestroy(self.chain)
            self.sampleRate = sampleRate
            var params = self.configuration.params
            self.chain = ForkVoiceChainCreate(&params, sampleRate)
        }
        guard let chain = self.chain else {
            return nil
        }

        var copiedBlock: CMBlockBuffer?
        guard CMBlockBufferCreateContiguous(allocator: nil, sourceBuffer: source, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: dataLength, flags: kCMBlockBufferAlwaysCopyDataFlag, blockBufferOut: &copiedBlock) == kCMBlockBufferNoErr,
              let copiedBlock else {
            return nil
        }
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(copiedBlock, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer else {
            return nil
        }
        let samples = UnsafeMutableRawPointer(dataPointer)
        if isFloat {
            self.processSamples(samples.bindMemory(to: Float.self, capacity: frameCount * channelCount), frames: frameCount, channels: channelCount, planar: isPlanar) {
                ForkVoiceChainProcessFloat(chain, $0, frameCount, channelCount, sampleRate)
            }
        } else {
            self.processSamples(samples.bindMemory(to: Int16.self, capacity: frameCount * channelCount), frames: frameCount, channels: channelCount, planar: isPlanar) {
                ForkVoiceChainProcessInt16(chain, $0, frameCount, channelCount, sampleRate)
            }
        }

        // AVCaptureAudioDataOutput delivers constant-duration PCM frames in presentation order.
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing) == noErr else {
            return nil
        }
        var output: CMSampleBuffer?
        let status = withUnsafePointer(to: bytesPerFrame) { sampleSize in
            CMSampleBufferCreateReady(allocator: nil, dataBuffer: copiedBlock, formatDescription: format, sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: isPlanar ? 0 : 1, sampleSizeArray: isPlanar ? nil : sampleSize, sampleBufferOut: &output)
        }
        guard status == noErr, let output else {
            return nil
        }
        CMPropagateAttachments(sampleBuffer, destination: output)
        return output
    }

    private func processSamples<Sample>(_ samples: UnsafeMutablePointer<Sample>, frames: Int, channels: Int, planar: Bool, process: (UnsafeMutablePointer<Sample>) -> Void) {
        guard planar && channels > 1 else {
            process(samples)
            return
        }
        let interleaved = UnsafeMutablePointer<Sample>.allocate(capacity: frames * channels)
        for frame in 0 ..< frames {
            for channel in 0 ..< channels {
                interleaved.advanced(by: frame * channels + channel).initialize(to: samples[channel * frames + frame])
            }
        }
        process(interleaved)
        for frame in 0 ..< frames {
            for channel in 0 ..< channels {
                samples[channel * frames + frame] = interleaved[frame * channels + channel]
            }
        }
        interleaved.deinitialize(count: frames * channels)
        interleaved.deallocate()
    }
}
