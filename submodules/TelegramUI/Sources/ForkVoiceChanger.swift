import Foundation
import SwiftSignalKit
import ForkVoiceDSP

/// Fork (Ghostgram): the voice changer of voice messages. The recorder changes every block before the waveform, the
/// level meter and the Opus encoder see it, so the real voice is never written and every way of sending (at once,
/// after listening, pause and continue, drafts, trimming) gets the changed file.
///
/// The effect graph in `ForkVoiceDSP` also processes outgoing call and round video audio.
public enum ForkVoiceChangerPreset: Int32, CaseIterable {
    case anonymous = 0
    case female = 1
    case male = 2
    case child = 3
    case robot = 4
    case custom = 5
    case doctorLivesey = 6
}

public enum ForkVoiceChanger {
    public struct State: Equatable {
        public var enabled: Bool
        public var preset: Int32
        /// Custom preset: semitones −12…12, reverb and echo 0…100.
        public var customPitch: Int32
        public var customReverb: Int32
        public var customEcho: Int32

        public init(enabled: Bool, preset: Int32, customPitch: Int32, customReverb: Int32, customEcho: Int32) {
            self.enabled = enabled
            self.preset = preset
            self.customPitch = customPitch
            self.customReverb = customReverb
            self.customEcho = customEcho
        }
    }

    private static let state = Atomic<State>(value: State(enabled: false, preset: 0, customPitch: 0, customReverb: 0, customEcho: 0))

    /// Main thread, from `SharedAccountContext` when the Extras settings change. The recorder reads it on its own queue
    /// when a recording starts.
    public static func update(_ value: State, calls: Bool, roundVideos: Bool) {
        let _ = self.state.swap(value)
        var captureState = value
        captureState.enabled = calls || roundVideos
        if var params = self.params(for: captureState) {
            withUnsafePointer(to: &params) { pointer in
                ForkVoiceCaptureSetCallParams(calls ? pointer : nil)
                ForkVoiceCaptureSetRoundVideoParams(roundVideos ? pointer : nil)
            }
        } else {
            ForkVoiceCaptureSetCallParams(nil)
            ForkVoiceCaptureSetRoundVideoParams(nil)
        }
    }

    public static var current: State {
        return self.state.with { $0 }
    }

    static func params(for state: State) -> ForkVoiceParams? {
        guard state.enabled else {
            return nil
        }
        var p = ForkVoiceParams()
        ForkVoiceParamsSetIdentity(&p)
        switch ForkVoiceChangerPreset(rawValue: state.preset) ?? .anonymous {
        case .anonymous:
            // Lower and darker, compressed, with breath and a slow random pitch drift, which makes shifting the
            // voice back harder.
            p.pitchSemitones = -3.5
            p.timbre = -0.35
            p.bassDb = 2.0
            p.trebleDb = -2.0
            p.distortion = 0.18
            p.reverbMix = 0.12
            p.reverbSize = 0.35
            p.jitter = 0.6
            p.breathiness = 0.15
            p.compression = 0.45
        case .female:
            p.pitchSemitones = 5.0
            p.timbre = 0.45
            p.trebleDb = 2.0
            p.reverbMix = 0.04
        case .male:
            p.pitchSemitones = -3.5
            p.timbre = -0.45
            p.bassDb = 3.0
            p.reverbMix = 0.03
        case .child:
            p.pitchSemitones = 7.0
            p.timbre = 0.65
            p.trebleDb = 3.0
            p.reverbMix = 0.05
        case .robot:
            p.ringModHz = 55.0
            p.ringModMix = 0.65
            p.distortion = 0.35
            p.bitcrushBits = 10.0
            p.telephone = 0.3
            p.reverbMix = 0.18
            p.reverbSize = 0.3
            p.echoMix = 0.12
            p.echoDelayMs = 70.0
            p.echoFeedback = 0.25
            p.compression = 0.5
        case .custom:
            p.pitchSemitones = Float(max(-12, min(12, state.customPitch)))
            p.reverbMix = Float(max(0, min(100, state.customReverb))) / 100.0
            p.reverbSize = 0.5
            p.echoMix = Float(max(0, min(100, state.customEcho))) / 100.0
            p.echoDelayMs = 180.0
            p.echoFeedback = 0.3
        case .doctorLivesey:
            // Paperny's dialogue centers around 190 Hz. The reference sits at 198 Hz because the
            // adaptive pitch loop measurably undershoots on real speech (smoothing + unvoiced
            // frames), and 198 lands the output average on ~190. Tuned against a formant-synth
            // Livesey reference (F0, band energies, spectral centroid): mild presence lift, mids
            // stepped back, a touch of saturation and air for the chesty, larger-than-life read.
            p.referencePitchHz = 198.0
            p.timbre = 0.1
            p.bassDb = 0.0
            p.midDb = -1.0
            p.trebleDb = 0.75
            p.distortion = 0.1
            p.compression = 0.2
            p.reverbMix = 0.07
            p.reverbSize = 0.2
        }
        // A custom preset left at zero changes nothing: the recorder then skips the chain.
        return ForkVoiceParamsIsIdentity(&p) ? nil : p
    }

    /// The key of the voice changer state in a paused recording's resume data; TGOggOpusWriter reads only its own keys.
    static let resumeDataKey = "forkVoiceChanger"

    /// The state a recording began with, from its resume data; nil when the resume data has none (a draft saved by an
    /// older build).
    static func recordedState(resumeData: Data) -> State? {
        guard let stateDict = (try? JSONSerialization.jsonObject(with: resumeData, options: [])) as? [String: Any], let dict = stateDict[self.resumeDataKey] as? [String: Any] else {
            return nil
        }
        guard let enabled = dict["enabled"] as? NSNumber, let preset = dict["preset"] as? NSNumber, let customPitch = dict["customPitch"] as? NSNumber, let customReverb = dict["customReverb"] as? NSNumber, let customEcho = dict["customEcho"] as? NSNumber else {
            return nil
        }
        return State(enabled: enabled.boolValue, preset: preset.int32Value, customPitch: customPitch.int32Value, customReverb: customReverb.int32Value, customEcho: customEcho.int32Value)
    }

    /// `state` as a JSON value for the resume data.
    static func resumeDataValue(_ state: State) -> [String: Any] {
        return [
            "enabled": NSNumber(value: state.enabled),
            "preset": NSNumber(value: state.preset),
            "customPitch": NSNumber(value: state.customPitch),
            "customReverb": NSNumber(value: state.customReverb),
            "customEcho": NSNumber(value: state.customEcho)
        ]
    }

    /// The effect for a recording with `state`, or nil when the voice stays as it is.
    static func makeRecorderEffect(state: State) -> ForkVoiceRecorderEffect? {
        guard let params = self.params(for: state) else {
            return nil
        }
        return ForkVoiceRecorderEffect(params: params, sampleRate: 48000)
    }
}

/// Owns one C voice chain; used only on the recorder's queue.
final class ForkVoiceRecorderEffect {
    /// nil: the chain could not be allocated. The recorder then writes silence, never the voice the user asked to change.
    private let chain: OpaquePointer?
    private let sampleRate: UInt32

    init(params: ForkVoiceParams, sampleRate: UInt32) {
        var params = params
        self.sampleRate = sampleRate
        self.chain = ForkVoiceChainCreate(&params, sampleRate)
        if let chain = self.chain {
            ForkVoiceChainPrepare(chain, sampleRate)
        }
    }

    deinit {
        ForkVoiceChainDestroy(self.chain)
    }

    /// Mono Int16 samples, changed in place; the count never changes.
    func process(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        guard let chain = self.chain else {
            samples.update(repeating: 0, count: count)
            return
        }
        ForkVoiceChainProcessInt16(chain, samples, count, 1, self.sampleRate)
    }
}

/// Fork (Ghostgram): publishes the playback equalizer's band gains to every audio renderer (`ForkPlaybackEqualizer` in
/// UniversalMediaPlayer). Renderers pick a change up on their next block, without a click.
public enum ForkPlaybackEqualizerSettings {
    /// Gains in dB for 60 Hz, 230 Hz, 910 Hz, 3.6 kHz and 14 kHz. Off, or all bands at 0, equalizes nothing.
    public static func publish(enabled: Bool, gains: [Int32], videos: Bool) {
        var values = [Float](repeating: 0.0, count: 5)
        for i in 0 ..< min(values.count, gains.count) {
            values[i] = Float(max(-12, min(12, gains[i])))
        }
        let active = enabled && values.contains(where: { $0 != 0.0 })
        values.withUnsafeBufferPointer { buffer in
            ForkAudioEqualizerSetParameters(buffer.baseAddress!, active, active, active && videos)
        }
    }
}
