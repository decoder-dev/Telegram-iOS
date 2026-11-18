"""Ports from Ghostgram: the voice changer of voice messages, the playback equalizer, outgoing text rules (word
replacement, anti-caps), No Call Rating Prompt and the estimated registration date. Source-text checks; Swift and C
build in CI."""
import pathlib
import re
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
        self.assertIn('ForkVoiceChanger.update(ForkVoiceChanger.State(enabled: settings.voiceChangerEnabled, preset: settings.voiceChangerPreset', source)
        self.assertIn('ForkOutgoingTextSettings.current = ForkOutgoingTextSettings.State(rules: ForkOutgoingTextSettings.parseRules(settings.textReplacementRules), antiCaps: settings.antiCaps)', source)
        self.assertIn('ForkPlaybackEqualizerSettings.publish(enabled: settings.equalizerEnabled, gains: [settings.equalizerBand60, settings.equalizerBand230, settings.equalizerBand910, settings.equalizerBand3600, settings.equalizerBand14000], videos: settings.equalizerVideos)', source)

    def test_new_rows_have_unique_ids_and_groups(self):
        source = read(EXTRAS)
        for row_id in list(range(2440, 2447)) + [2450, 2451, 2453, 2455, 2456, 2457, 2458] + list(range(2460, 2469)):
            self.assertEqual(len(re.findall(r'\(%d,' % row_id, source)), 1, row_id)
        self.assertIn('[2440, 2441, 2442, 2443, 2444, 2445, 2446],', source)
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
        for name in ['ForkVoiceChainCreate', 'ForkVoiceChainProcessInt16', 'ForkVoiceChainDestroy', 'ForkAudioEqualizerSetParameters', 'ForkAudioEqualizerProcessInt16']:
            self.assertIn(name, header)
            self.assertIn(name, source)
        self.assertNotRegex(header + source, r'\bGG[A-Z_]|\bgg_')

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
