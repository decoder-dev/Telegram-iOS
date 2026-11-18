"""Audit iteration 4 (docs/quality/full_app_audit.md): the P3 defects. Saved copies with extensions outside the probe
list, a sticker-to-video export cancelled while it finishes, the banned-GIF conversion of an empty inline result, the
inert No Call Rating Prompt description, WebSocket probe slot ownership, equalizer clipping and the voice changer of a
recording continued from a draft. Source-text checks; Swift builds in CI."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8').replace('\r\n', '\n')


def body(source, start, end='\n    }\n'):
    text = source[source.index(start):]
    return text[:text.index(end)]


class SavedCopyExtensions(unittest.TestCase):
    def test_copies_are_saved_with_an_extension_that_is_probed(self):
        source = read('submodules/TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift')
        known = re.search(r'private static let knownExtensions: \[String\] = \[(.*?)\]', source, re.S).group(1)
        extensions = re.findall(r'"(\w+)"', known)
        for ext in ['mov', 'heif', 'apk', 'bin']:
            self.assertIn(ext, extensions)
        self.assertEqual(extensions, [ext.lower() for ext in extensions])
        destination = body(source, '    private static func destinationURL(')
        self.assertIn('let sourceExtension = (source as NSString).pathExtension.lowercased()', destination)
        self.assertIn('if knownExtensions.contains(sourceExtension) {', destination)
        probe = body(source, '    private static func firstFile(withBase base: String, in directory: URL) -> String? {')
        self.assertIn('ext.uppercased()', probe)


class StickerVideoExport(unittest.TestCase):
    def test_cancel_leaves_a_finishing_writer_alone(self):
        source = read('submodules/TelegramUI/Sources/ChatController+ForkStickerMedia.swift')
        self.assertLess(source.index('let _ = finishing.swap(true)'), source.index('writer.finishWriting {'))
        cancel = source[source.index('        return ActionDisposable {\n            let _ = cancelled.swap(true)'):]
        self.assertLess(cancel.index('if finishing.with({ $0 }) {\n                    return\n                }'), cancel.index('writer.cancelWriting()'))


class BannedGifVideo(unittest.TestCase):
    def test_empty_inline_result_gives_up_at_once(self):
        source = read('submodules/TelegramCore/Sources/PendingMessages/ForkBannedGifVideo.swift')
        convert = source[source.index('private func forkLocalGifVideo('):]
        self.assertLess(convert.index('if file.resource is EmptyMediaResource {\n        return .single(nil)\n    }'), convert.index('let signal'))


class CallRating(unittest.TestCase):
    def test_footer_says_what_the_switch_does(self):
        source = read('submodules/SettingsUI/Sources/ForkExtrasController.swift')
        footer = source[source.index('.designFooter(2456,'):]
        footer = footer[:footer.index('\n')]
        self.assertIn('Telegram does not ask to rate calls at the moment', footer)
        self.assertNotIn('No quality rating sheet after a call.', footer)


class WebSocketProbe(unittest.TestCase):
    def test_only_the_probe_reports_its_outcome(self):
        source = read('submodules/TelegramCore/Sources/Network/MTWebSocketConnectionInterface.swift')
        self.assertNotIn('isProbing', source)
        self.assertIn('func shouldAttemptWebSocket() -> (allowed: Bool, probeToken: Int?) {', source)
        self.assertIn('if state.probeToken == probeToken {', body(source, '    func abortProbe(probeToken: Int?) {'))
        self.assertIn('if state.probeToken != nil, state.probeToken == probeToken {', source)
        self.assertNotIn('abortProbe()', source)
        self.assertNotIn('recordAllEndpointsFailed()\n', source.replace('state.policy.recordAllEndpointsFailed()', ''))
        network = read('submodules/TelegramCore/Sources/Network/Network.swift')
        self.assertIn('fallbackCoordinator: activeFallbackCoordinator, probeToken: decision?.probeToken)', network)


class Equalizer(unittest.TestCase):
    def test_int16_path_is_limited_like_the_float_path(self):
        source = read('submodules/ForkVoiceDSP/Sources/ForkVoiceDSP.c')
        int16 = source[source.index('void ForkAudioEqualizerProcessInt16('):source.index('void ForkAudioEqualizerProcessFloat(')]
        self.assertIn('fv_float_to_int16(fv_soft_limit(fv_eq_run(equalizer, c, (float)frame[c] * scale)))', int16)


class VoiceChangerResume(unittest.TestCase):
    def test_a_continued_recording_keeps_its_voice(self):
        recorder = read('submodules/TelegramUI/Sources/ManagedAudioRecorder.swift')
        self.assertIn('let voiceChangerState = resumeData.flatMap { ForkVoiceChanger.recordedState(resumeData: $0.resumeData) } ?? ForkVoiceChanger.current', recorder)
        self.assertIn('stateDict[ForkVoiceChanger.resumeDataKey] = ForkVoiceChanger.resumeDataValue(self.voiceChangerState)', recorder)
        changer = read('submodules/TelegramUI/Sources/ForkVoiceChanger.swift')
        self.assertIn('static func makeRecorderEffect(state: State) -> ForkVoiceRecorderEffect? {', changer)
        self.assertNotIn('self.params(for: self.current)', changer)


if __name__ == '__main__':
    unittest.main()
