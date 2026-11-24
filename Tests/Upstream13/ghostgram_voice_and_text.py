"""Ports from Ghostgram: the voice changer of voice messages, the playback equalizer, outgoing text rules (word
replacement, anti-caps), No Call Rating Prompt and the estimated registration date. Source-text checks; Swift and C
build in CI."""
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
SHARED = 'submodules/TelegramUI/Sources/SharedAccountContext.swift'
DSP_BUILD = 'submodules/ForkVoiceDSP/BUILD'
DSP_HEADER = 'submodules/ForkVoiceDSP/PublicHeaders/ForkVoiceDSP/ForkVoiceDSP.h'
DSP_SOURCE = 'submodules/ForkVoiceDSP/Sources/ForkVoiceDSP.c'
CHANGER = 'submodules/TelegramUI/Sources/ForkVoiceChanger.swift'
RECORDER = 'submodules/TelegramUI/Sources/ManagedAudioRecorder.swift'
TELEGRAM_UI_BUILD = 'submodules/TelegramUI/BUILD'
MEDIA_BUILD = 'submodules/MediaPlayer/BUILD'
RENDERER = 'submodules/MediaPlayer/Sources/MediaPlayerAudioRenderer.swift'
PLAYER = 'submodules/MediaPlayer/Sources/MediaPlayer.swift'
CHUNK_PLAYER = 'submodules/MediaPlayer/Sources/ChunkMediaPlayerV2.swift'
TEXT_RULES = 'submodules/TelegramCore/Sources/PendingMessages/ForkOutgoingTextRules.swift'
ENQUEUE = 'submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift'
CALL = 'submodules/TelegramCallsUI/Sources/CallController.swift'
PROFILE = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift'
ANCHORS = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ForkRegDateAnchors.swift'
ESTIMATE = 'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/ForkRegDateEstimate.swift'

FIELDS = [
    ('voiceChangerEnabled', 'Bool', 'false'),
    ('voiceChangerInCallsEnabled', 'Bool', 'false'),
    ('voiceChangerInRoundVideosEnabled', 'Bool', 'false'),
    ('voiceChangerPreset', 'Int32', '0'),
    ('voiceChangerPitch', 'Int32', '0'),
    ('voiceChangerReverb', 'Int32', '0'),
    ('voiceChangerEcho', 'Int32', '0'),
    ('antiCaps', 'Bool', 'false'),
    ('textReplacementRules', '[String]', '[]'),
    ('disableCallRating', 'Bool', 'false'),
    ('estimateRegistrationDate', 'Bool', 'false'),
    ('equalizerEnabled', 'Bool', 'false'),
    ('equalizerVideos', 'Bool', 'false'),
    ('equalizerBand60', 'Int32', '0'),
    ('equalizerBand230', 'Int32', '0'),
    ('equalizerBand910', 'Int32', '0'),
    ('equalizerBand3600', 'Int32', '0'),
    ('equalizerBand14000', 'Int32', '0'),
]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


class Settings(unittest.TestCase):
    def test_every_field_is_declared_defaulted_decoded_and_encoded(self):
        source = read(SETTINGS)
        for name, kind, default in FIELDS:
            self.assertIn('public var %s: %s' % (name, kind), source)
            self.assertIn('self.%s = %s\n' % (name, default), source)
            self.assertRegex(source, r'self\.%s = .*decodeIfPresent\(%s\.self, forKey: "%s"\)' % (name, re.escape(kind), name))
            self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_runtime_receives_the_settings(self):
        source = read(SHARED)
        self.assertIn('ForkVoiceChanger.State(enabled: settings.voiceChangerEnabled, preset: settings.voiceChangerPreset', source)
        self.assertIn('calls: settings.voiceChangerInCallsEnabled', source)
        self.assertIn('roundVideos: settings.voiceChangerInRoundVideosEnabled', source)
        self.assertIn('ForkOutgoingTextSettings.current = ForkOutgoingTextSettings.State(rules: ForkOutgoingTextSettings.parseRules(settings.textReplacementRules), antiCaps: settings.antiCaps)', source)
        self.assertIn('ForkPlaybackEqualizerSettings.publish(enabled: settings.equalizerEnabled, gains: [settings.equalizerBand60, settings.equalizerBand230, settings.equalizerBand910, settings.equalizerBand3600, settings.equalizerBand14000], videos: settings.equalizerVideos)', source)

    def test_new_rows_have_unique_ids_and_groups(self):
        source = read(EXTRAS)
        for row_id in list(range(2440, 2449)) + [2450, 2451, 2453, 2455, 2456, 2457, 2458] + list(range(2460, 2469)):
            self.assertEqual(len(re.findall(r'\(%d,' % row_id, source)), 1, row_id)
        self.assertIn('[2440, 2441, 2447, 2448, 2442, 2443, 2444, 2445, 2446],', source)
        self.assertIn('[2460, 2461, 2462, 2463, 2464, 2465, 2466, 2467, 2468],', source)
        self.assertIn('[2450, 2451, 2452, 2453]', source)
        # The rules editor has no id literal: its stableId is fixed in the enum.
        self.assertIn('case .textReplacementRules: return 2452', source)
        self.assertEqual(source.count('2452'), 2)
        self.assertIn('[2455, 2456],', source)
        self.assertIn('[2457, 2458],', source)
        # Every picker row opens its own list.
        for row_id, key in [(2442, 'voiceChangerPreset'), (2443, 'voiceChangerPitch'), (2444, 'voiceChangerReverb'), (2445, 'voiceChangerEcho'), (2462, 'equalizerBand60'), (2466, 'equalizerBand14000')]:
            self.assertRegex(source, r'case %d:\n(?:.*\n){2}\s+keyPath = \\\.%s' % (row_id, key))
        self.assertIn('.textReplacementRules(settings.textReplacementRules.joined(separator: "\\n")),', source)


class VoiceChanger(unittest.TestCase):
    def test_dsp_is_a_plain_c_library_linked_where_used(self):
        build = read(DSP_BUILD)
        self.assertIn('name = "ForkVoiceDSP"', build)
        self.assertIn('"-std=c11"', build)
        self.assertIn('"//submodules/ForkVoiceDSP:ForkVoiceDSP"', read(TELEGRAM_UI_BUILD))
        self.assertIn('"//submodules/ForkVoiceDSP:ForkVoiceDSP"', read(MEDIA_BUILD))
        header = read(DSP_HEADER)
        source = read(DSP_SOURCE)
        for name in ['ForkVoiceChainCreate', 'ForkVoiceChainProcessInt16', 'ForkVoiceChainDestroy', 'ForkAudioEqualizerSetParameters', 'ForkAudioEqualizerProcessInt16', 'ForkVoiceCaptureSetCallParams', 'ForkVoiceCaptureGetCallParams', 'ForkVoiceCaptureSetRoundVideoParams', 'ForkVoiceCaptureGetRoundVideoParams']:
            self.assertIn(name, header)
            self.assertIn(name, source)
        self.assertNotRegex(header + source, r'\bGG[A-Z_]|\bgg_')

    def test_livesey_keeps_the_custom_preset_id_and_has_independent_capture_controls(self):
        source = read(CHANGER)
        self.assertIn('case custom = 5', source)
        self.assertIn('case doctorLivesey = 6', source)
        self.assertIn('p.referencePitchHz = 198.0', source)
        self.assertIn('min(6, max(0,', read(SETTINGS))
        self.assertIn('"Доктор Ливси" : "Doctor Livesey", 6', read(EXTRAS))
        self.assertIn('ForkVoiceCaptureSetCallParams(calls ? pointer : nil)', source)
        self.assertIn('ForkVoiceCaptureSetRoundVideoParams(roundVideos ? pointer : nil)', source)

    def test_livesey_preset_values_match_the_tuned_reference(self):
        # The preset is tuned against a formant-synthesis Livesey reference (F0, band energies,
        # spectral centroid); drifting a value audibly moves the voice away from the character.
        source = read(CHANGER)
        case = source[source.index('case .doctorLivesey:'):]
        case = case[:case.index('}')]
        for line in ['p.referencePitchHz = 198.0', 'p.timbre = 0.1', 'p.bassDb = 0.0',
                     'p.midDb = -1.0', 'p.trebleDb = 0.75', 'p.distortion = 0.1',
                     'p.compression = 0.2', 'p.reverbMix = 0.07', 'p.reverbSize = 0.2']:
            self.assertIn(line, case)

    def test_reference_pitch_correction_is_not_damped(self):
        # The estimator reads the dry input, so the correction applies in full (gain 1.0) and
        # the cap is +/-9 semitones: a 120 Hz voice must reach the 190 Hz region, not stall.
        source = read(DSP_SOURCE)
        self.assertIn('fv_clampf(1.0f * 12.0f * log2f(', source)
        self.assertIn(', -9.0f, 9.0f)', source)

    def test_reference_pitch_moves_low_and_high_voices_toward_the_character(self):
        headers = (ROOT / DSP_HEADER).parent
        fixture = ROOT / 'Tests/Upstream13/ForkVoiceReferencePitch.c'
        with tempfile.TemporaryDirectory(prefix='reference-voice-pitch-') as directory:
            executable = pathlib.Path(directory) / 'pitch-test'
            subprocess.run(['clang', '-std=c11', '-O2', '-I', str(headers), str(ROOT / DSP_SOURCE), str(fixture), '-lm', '-pthread', '-o', str(executable)], check=True, timeout=30)
            subprocess.run([str(executable)], check=True, timeout=30)

    def test_recorder_changes_the_voice_before_the_waveform_and_the_encoder(self):
        source = read(RECORDER)
        effect = source.index('self.voiceChangerEffect?.process(currentEncoderPacket.assumingMemoryBound(to: Int16.self), count: currentEncoderPacketSize / 2)')
        self.assertLess(effect, source.index('self.processWaveformPreview(samples: currentEncoderPacket'))
        self.assertLess(effect, source.index('self.oggWriter.writeFrame(currentEncoderPacket'))
        self.assertIn('self.voiceChangerEffect = ForkVoiceChanger.makeRecorderEffect(state: voiceChangerState)', source)

    def test_a_failed_chain_writes_silence_not_the_real_voice(self):
        source = read(CHANGER)
        body = source[source.index('func process(_ samples: UnsafeMutablePointer<Int16>, count: Int) {'):]
        self.assertLess(body.index('samples.update(repeating: 0, count: count)'), body.index('ForkVoiceChainProcessInt16'))
        self.assertIn('return ForkVoiceParamsIsIdentity(&p) ? nil : p', source)
        self.assertIn('return ForkVoiceRecorderEffect(params: params, sampleRate: 48000)', source)

    def test_equalizer_runs_in_every_player_and_never_on_service_sounds(self):
        renderer = read(RENDERER)
        self.assertIn('context.forkEqualizer?.process(samples: bufferData.advanced(by: dataOffset), byteCount: actualConsumedCount, channels: 2, sampleRate: 44100)', renderer)
        self.assertIn('forkEqualizerKind: ForkPlaybackEqualizerKind? = nil) {', renderer)
        self.assertEqual(read(PLAYER).count('forkEqualizerKind: self.forkEqualizerKind)'), 2)
        self.assertEqual(read(CHUNK_PLAYER).count('loadedPartsMediaData.forkEqualizer?.process(sampleBuffer: sampleBuffer)'), 2)
        # The recorder's tone renderer passes no kind, so it is never equalized.
        self.assertNotIn('forkEqualizerKind', read(RECORDER))


class TextRules(unittest.TestCase):
    def test_rules_run_on_every_enqueued_batch_before_the_rest(self):
        source = read(ENQUEUE)
        body = source[source.index('public func enqueueMessages(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {'):]
        self.assertLess(body.index('forkApplyOutgoingTextRules(account: account, peerId: peerId, messages: messages)'), body.index('forkPrepareBannedGifVideos'))

    def test_bots_forwards_and_protected_text_are_left_alone(self):
        source = read(TEXT_RULES)
        self.assertIn('if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {', source)
        self.assertIn('guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {\n                return message', source)
        self.assertIn('case .Url, .TextUrl, .Mention, .TextMention, .BotCommand, .Hashtag, .Email, .PhoneNumber, .BankCard, .Code, .Pre, .CustomEmoji, .FormattedDate, .TonAddress:', source)
        self.assertIn('if state.antiCaps && !currentText.hasPrefix("/") {', source)
        # Off means no transaction at all.
        self.assertIn('if state.isEmpty {\n        return .single(messages)', source)


class Calls(unittest.TestCase):
    def test_only_the_automatic_rating_sheet_is_skipped(self):
        source = read(CALL)
        guard = source.index('if strongSelf.sharedContext.immediateForkExtrasSettings.disableCallRating {\n                    return')
        self.assertLess(source.index('strongSelf.presentedCallRating = true'), guard)
        self.assertLess(guard, source.index('userInitiated: false'))


class CallCaptureVoice(unittest.TestCase):
    def test_shared_and_fallback_microphones_use_the_same_capture_adapter(self):
        source = read('submodules/TgVoipWebrtc/Sources/OngoingCallThreadLocalContext.mm')
        self.assertEqual(source.count('makeCallAudioDeviceIOS('), 4)  # Factory, shared device, 1:1, group.
        self.assertEqual(source.count('make_ref_counted<webrtc::tgcalls_ios_adm::AudioDeviceModuleIOS>'), 1)
        self.assertIn('"//submodules/ForkVoiceDSP:ForkVoiceDSP"', read('submodules/TgVoipWebrtc/BUILD'))

    def test_only_completed_calls_replace_their_voice_capture_device(self):
        source = read('submodules/TgVoipWebrtc/Sources/OngoingCallThreadLocalContext.mm')
        self.assertIn('return !_voiceSettings.enabled && !CallCaptureVoiceSettings::current(disableRecording).enabled;', source)
        shared = read('submodules/TelegramCallsUI/Sources/SharedCallAudioContext.swift')
        self.assertIn('previous?.isVoiceCaptureFinished == true', shared)
        self.assertIn('&& previous?.audioDevice?.canReuseCompletedVoiceCapture(enableMicrophone: enableMicrophone) == false', shared)
        self.assertIn('reuseCurrent, !replaceCompletedVoiceDevice,', shared)
        self.assertIn('replaceCompletedVoiceDevice || (!legacyBehavior && previous.isCallFinished)', shared)
        group = read('submodules/TelegramCallsUI/Sources/PresentationGroupCall.swift')
        self.assertLess(group.index('self.sharedAudioContext?.markVoiceCaptureFinished()'), group.index('self._canBeRemoved.set(.single(true))'))

    def test_capture_preserves_frame_metadata_and_playout(self):
        source = read('submodules/TgVoipWebrtc/Sources/OngoingCallThreadLocalContext.mm')
        capture = source[source.index('struct CallCaptureVoiceSettings {'):source.index('class WrappedAudioDeviceModuleIOS :')]
        fixture = r'''
#include <ForkVoiceDSP/ForkVoiceDSP.h>
#include <array>
#include <cassert>
#include <cstring>
#include <memory>
#include <optional>
#include <utility>
namespace absl { using std::optional; }
namespace rtc {
    template <typename T> using scoped_refptr = std::shared_ptr<T>;
    template <typename T, typename... Args> scoped_refptr<T> make_ref_counted(Args&&... args) {
        return std::make_shared<T>(std::forward<Args>(args)...);
    }
}
namespace webrtc {
    struct AudioTransport {
        virtual ~AudioTransport() = default;
        virtual int32_t RecordedDataIsAvailable(const void*, size_t, size_t, size_t, uint32_t, uint32_t, int32_t, uint32_t, bool, uint32_t&) = 0;
        virtual int32_t RecordedDataIsAvailable(const void*, size_t, size_t, size_t, uint32_t, uint32_t, int32_t, uint32_t, bool, uint32_t&, absl::optional<int64_t>) = 0;
        virtual int32_t NeedMorePlayData(size_t, size_t, size_t, uint32_t, void*, size_t&, int64_t*, int64_t*) = 0;
        virtual void PullRenderData(int, int, size_t, size_t, void*, int64_t*, int64_t*) = 0;
    };
    namespace tgcalls_ios_adm {
        struct AudioDeviceModuleIOS {
            AudioTransport *callback = nullptr;
            bool active = false;
            AudioDeviceModuleIOS(bool, bool, bool, int) {}
            virtual ~AudioDeviceModuleIOS() = default;
            virtual int32_t RegisterAudioCallback(AudioTransport *value) {
                if (active) return -1;
                callback = value;
                return 0;
            }
            int32_t Terminate() { active = false; callback = nullptr; return 0; }
        };
    }
}
''' + capture + r'''
struct Sink: webrtc::AudioTransport {
    size_t captured = 0;
    int16_t received = 0;
    int64_t captureTime = -1;
    int32_t RecordedDataIsAvailable(const void *data, size_t frames, size_t bytesPerFrame, size_t channels, uint32_t rate, uint32_t delay, int32_t drift, uint32_t level, bool pressed, uint32_t &newLevel) override {
        assert(frames == 480 && bytesPerFrame == 2 && channels == 1 && rate == 48000);
        assert(delay == 13 && drift == 0 && level == 8 && pressed);
        captured += frames;
        received = static_cast<const int16_t *>(data)[0];
        newLevel = 9;
        return 21;
    }
    int32_t RecordedDataIsAvailable(const void *data, size_t frames, size_t bytesPerFrame, size_t channels, uint32_t rate, uint32_t delay, int32_t drift, uint32_t level, bool pressed, uint32_t &newLevel, absl::optional<int64_t> time) override {
        captureTime = time.value_or(-1);
        return RecordedDataIsAvailable(data, frames, bytesPerFrame, channels, rate, delay, drift, level, pressed, newLevel);
    }
    int32_t NeedMorePlayData(size_t, size_t, size_t, uint32_t, void *data, size_t &framesOut, int64_t *, int64_t *) override {
        static_cast<int16_t *>(data)[0] = 1234;
        framesOut = 1;
        return 17;
    }
    void PullRenderData(int, int, size_t, size_t, void *data, int64_t *, int64_t *) override {
        static_cast<int16_t *>(data)[0] = 4321;
    }
};
int main() {
    Sink sink;
    auto original = makeCallAudioDeviceIOS(false, false, CallCaptureVoiceSettings::current(false));
    assert(original->RegisterAudioCallback(&sink) == 0 && original->callback == &sink);

    ForkVoiceParams params;
    ForkVoiceParamsSetIdentity(&params);
    params.gainDb = -6.0f;
    ForkVoiceCaptureSetCallParams(&params);
    const auto settings = CallCaptureVoiceSettings::current(false);
    assert(settings.enabled);
    auto device = makeCallAudioDeviceIOS(false, false, settings);
    assert(device->RegisterAudioCallback(&sink) == 0 && device->callback != &sink);
    device->active = true;
    assert(device->RegisterAudioCallback(nullptr) == -1);
    auto *callback = device->callback;
    std::array<int16_t, 480> samples;
    samples.fill(12000);
    uint32_t level = 0;
    assert(callback->RecordedDataIsAvailable(samples.data(), 480, 2, 1, 48000, 13, 0, 8, true, level, 77) == 21);
    assert(sink.captureTime == 77 && sink.captured == 480 && sink.received != 12000 && level == 9);
    assert(samples[0] == 12000);
    assert(callback->RecordedDataIsAvailable(nullptr, 480, 2, 1, 48000, 13, 0, 8, true, level) == 21);
    assert(sink.captured == 960 && sink.received == 0);
    assert(callback->RecordedDataIsAvailable(samples.data(), 480, 8, 1, 48000, 13, 0, 8, true, level) == 0);
    assert(sink.captured == 960);
    int16_t playout = 0;
    size_t framesOut = 0;
    assert(callback->NeedMorePlayData(1, 2, 1, 48000, &playout, framesOut, nullptr, nullptr) == 17);
    assert(playout == 1234 && framesOut == 1);
    callback->PullRenderData(16, 48000, 1, 1, &playout, nullptr, nullptr);
    assert(playout == 4321);
    const auto noMic = CallCaptureVoiceSettings::current(true);
    assert(!noMic.enabled);
    auto stream = makeCallAudioDeviceIOS(true, false, noMic);
    assert(stream->RegisterAudioCallback(&sink) == 0 && stream->callback == &sink);
    ForkVoiceCaptureSetCallParams(nullptr);
    assert(!CallCaptureVoiceSettings::current(false).enabled);
    assert(callback->RecordedDataIsAvailable(samples.data(), 480, 2, 1, 48000, 13, 0, 8, true, level) == 21);
    assert(sink.captured == 1440 && sink.received != 12000);
}
'''
        with tempfile.TemporaryDirectory(prefix='call-capture-voice-') as directory:
            directory = pathlib.Path(directory)
            headers = ROOT / 'submodules/ForkVoiceDSP/PublicHeaders'
            dsp = directory / 'dsp.o'
            program = directory / 'main.cpp'
            executable = directory / 'capture-test'
            program.write_text(fixture, encoding='utf-8')
            subprocess.run(['clang', '-std=c11', '-I', str(headers / 'ForkVoiceDSP'), '-c', str(ROOT / DSP_SOURCE), '-o', str(dsp)], check=True, timeout=30)
            subprocess.run(['clang++', '-std=c++17', '-I', str(headers), str(program), str(dsp), '-o', str(executable)], check=True, timeout=30)
            subprocess.run([str(executable)], check=True, timeout=30)


class RegistrationDate(unittest.TestCase):
    def test_table_is_consistent(self):
        source = read(ANCHORS)
        counts = []
        for name in ['ids', 'points', 'lows', 'highs']:
            match = re.search(r'static let %s: \[Int(?:64|32)\] = \[(.*?)\]' % name, source, re.S)
            values = [int(value) for value in re.findall(r'-?\d+', match.group(1))]
            counts.append(len(values))
            if name == 'ids':
                self.assertEqual(values, sorted(values))
                self.assertEqual(values[0], 0)
        self.assertEqual(len(set(counts)), 1, counts)

    def test_telegram_date_wins_over_the_estimate(self):
        source = read(PROFILE)
        self.assertIn('let estimateText = serverRegistrationDate ?? ForkRegDateEstimate.text(estimate, russian: russian)', source)
        self.assertIn('!(forkExtras.showDC && serverRegistrationDate != nil)', source)
        self.assertIn('case 777000, 333000, 489000, 4244000:', read(ESTIMATE))


if __name__ == '__main__':
    unittest.main()
