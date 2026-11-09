"""Translate Before Sending (Swiftgram) and the Google / DeepL / Yandex translators with Automatic Fallback: settings,
Extras rows, the send menu items and the places that pick a translator. Source-text checks; Swift builds in CI."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = 'submodules/TelegramUIPreferences/Sources/ForkExtrasSettings.swift'
EXTRAS = 'submodules/SettingsUI/Sources/ForkExtrasController.swift'
BACKENDS = 'submodules/TranslateUI/Sources/ForkTranslationBackends.swift'
CHAT_TRANSLATION = 'submodules/TranslateUI/Sources/ChatTranslation.swift'
ENGINE = 'submodules/TelegramCore/Sources/TelegramEngine/Messages/Translate.swift'
QUICK = 'submodules/TelegramUI/Components/TextProcessingScreen/Sources/TextProcessingTranslateContentComponent.swift'
SEND_PARAMS = 'submodules/ChatSendMessageActionUI/Sources/ChatSendMessageActionSheetController.swift'
SEND_MENU = 'submodules/ChatSendMessageActionUI/Sources/ChatSendMessageContextScreen.swift'
SEND_OPTIONS = 'submodules/TelegramUI/Sources/Chat/ChatMessageDisplaySendMessageOptions.swift'
DRAFT = 'submodules/TelegramUI/Sources/ChatController+ForkDraftTranslation.swift'

FIELDS = [
    ('translationFallback', 'Bool', 'false'),
    ('deeplApiKey', 'String', '""'),
    ('yandexApiKey', 'String', '""'),
    ('translateBeforeSending', 'Bool', 'false'),
]


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


class TranslatorSettings(unittest.TestCase):
    def test_fields_are_declared_defaulted_decoded_and_encoded(self):
        source = read(SETTINGS)
        for name, kind, default in FIELDS:
            with self.subTest(name=name):
                self.assertIn('    public var %s: %s\n' % (name, kind), source)
                self.assertIn('        self.%s = %s\n' % (name, default), source)
                self.assertIn('self.%s = try container.decodeIfPresent(%s.self, forKey: "%s") ?? %s' % (name, kind, name, default), source)
                self.assertIn('try container.encode(self.%s, forKey: "%s")' % (name, name), source)

    def test_remembered_languages_are_stored_as_two_lists(self):
        # A [Int64: String] map goes through Postbox's encoder as one mixed list, which stops the app; it is stored as
        # the peer ids and the languages side by side.
        source = read(SETTINGS)
        self.assertIn('    public var draftTranslationLanguages: [Int64: String]\n', source)
        self.assertIn('        self.draftTranslationLanguages = [:]\n', source)
        self.assertIn('decodePeerKeyedDictionary(container, String.self, idsKey: "draftTranslationLanguagesIds", valuesKey: "draftTranslationLanguagesValues")', source)
        self.assertIn('try encodePeerKeyedDictionary(self.draftTranslationLanguages, into: &container, idsKey: "draftTranslationLanguagesIds", valuesKey: "draftTranslationLanguagesValues")', source)
        for name in ['localVerificationBadges', 'visualLabels']:
            self.assertIn('try encodePeerKeyedDictionary(self.%s, into: &container' % name, source)
            self.assertNotIn('try container.encode(self.%s, forKey:' % name, source)

    def test_backend_keeps_its_default_and_gains_three_services(self):
        source = read(SETTINGS)
        enum = source.split('public enum ForkTranslationBackend', 1)[1].split('\n}\n', 1)[0]
        for case in ('case `default`', 'case system', 'case google', 'case deepl', 'case yandex'):
            self.assertIn(case, enum)
        self.assertIn('.flatMap(ForkTranslationBackend.init(rawValue:)) ?? .default', source)


class TranslatorRows(unittest.TestCase):
    def test_rows_and_groups(self):
        source = read(EXTRAS)
        self.assertIn('[85, 2300, 2301, 2302, 86, 87]', source)
        self.assertIn('[2304, 2305]', source)
        self.assertIn('.appearanceToggle(2302, russian ? "Резервный переводчик" : "Automatic Fallback", settings.translationFallback, \\.translationFallback)', source)
        self.assertIn('.appearanceToggle(2304, russian ? "Перевод перед отправкой" : "Translate Before Sending", settings.translateBeforeSending, \\.translateBeforeSending)', source)
        self.assertIn('.translationApiKey(2300, "DeepL", settings.deeplApiKey, \\.deeplApiKey)', source)
        self.assertIn('.translationApiKey(2301, russian ? "Яндекс" : "Yandex", settings.yandexApiKey, \\.yandexApiKey)', source)

    def test_keys_are_typed_in_a_secure_field(self):
        source = read(EXTRAS)
        item = source.split('case let .translationApiKey(_, title, value, keyPath):', 1)[1].split('        case ', 1)[0]
        self.assertIn('type: .password', item)

    def test_picker_offers_every_backend(self):
        source = read(EXTRAS)
        picker = source.split('        openTranslationBackend: {\n', 1)[1].split('openTranscriptionBackend:', 1)[0]
        self.assertIn('backends.append(contentsOf: [.google, .deepl, .yandex])', picker)
        self.assertIn('if #available(iOS 18.0, *) {\n                backends.append(.system)', picker)


class TranslatorRequests(unittest.TestCase):
    def test_keys_only_travel_in_the_authorization_header(self):
        source = read(BACKENDS)
        self.assertIn('request.setValue("DeepL-Auth-Key \\(key)", forHTTPHeaderField: "Authorization")', source)
        self.assertIn('request.setValue("Api-Key \\(key)", forHTTPHeaderField: "Authorization")', source)
        self.assertIn('key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"', source)
        self.assertNotIn('auth_key', source)
        self.assertNotIn('print(', source)
        self.assertNotIn('Logger.shared', source)

    def test_requests_are_ephemeral_with_timeouts(self):
        source = read(BACKENDS)
        self.assertIn('URLSessionConfiguration.ephemeral', source)
        self.assertIn('configuration.timeoutIntervalForRequest = 15.0', source)
        self.assertIn('|> timeout(20.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.generic))', source)
        # Google gets the text in a POST body, not in the address.
        self.assertIn('request.httpMethod = "POST"', source.split('private func googleTranslate', 1)[1].split('private func deeplTranslate', 1)[0])

    def test_fallback_order_is_off_unless_switched_on(self):
        source = read(BACKENDS)
        order = source.split('public func forkTranslationBackends(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('var result: [ForkTranslationBackend] = [settings.translationBackend]', order)
        self.assertIn('if settings.translationFallback {', order)


class TranslatorBatching(unittest.TestCase):
    def test_google_goes_three_at_a_time(self):
        source = read(BACKENDS)
        self.assertNotIn('combineLatest(texts.map { googleTranslate(text: $0', source)
        google = source.split('private func googleTranslate(texts: [String]', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('let groupSize = 3', google)
        self.assertIn('for start in stride(from: 0, to: texts.count, by: groupSize) {', google)
        self.assertIn('return combineLatest(group.map { text -> Signal<String?, NoError> in', google)
        # One failed text is nil, not a failed batch.
        self.assertIn('return .single(nil)', google)

    def test_deepl_and_yandex_are_chunked(self):
        source = read(BACKENDS)
        texts = source.split('private func translateTexts(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('stride(from: 0, to: texts.count, by: 50)', texts)
        self.assertIn('translateInChunks(yandexChunks(texts),', texts)
        yandex = source.split('private func yandexChunks(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('if !current.isEmpty && length + textLength > 10000 {', yandex)
        chunks = source.split('private func translateInChunks(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('return previous + translated.map { text -> String? in text }', chunks)
        self.assertIn('return .single(previous + chunk.map { _ -> String? in nil })', chunks)

    def test_only_failed_texts_fall_back(self):
        source = read(BACKENDS)
        fallback = source.split('private func translateWithFallback(', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('let failed = translated.indices.filter { translated[$0] == nil }', fallback)
        self.assertIn('texts: failed.map { texts[$0] }', fallback)
        service = source.split('private final class ThirdPartyChatTranslationService', 1)[1].split('\n}\n', 1)[0]
        self.assertIn('translateWithFallback(self.backends, settings: self.settings, texts: values, toLang: toLang)', service)
        self.assertIn("if !translated.contains(where: { $0 != nil }) {", service)


class TranslatorWiring(unittest.TestCase):
    def test_chat_translation_uses_the_third_party_service(self):
        source = read(CHAT_TRANSLATION)
        self.assertIn('forkThirdPartyTranslationService(settings: forkSettings)', source)
        self.assertIn('translationService: thirdPartyService', source)
        engine = read(ENGINE)
        self.assertIn('translationService: ExperimentalInternalTranslationService? = nil', engine)
        self.assertIn('localTranslation.service.translate(texts: mappedTexts, fromLang: localTranslation.fromLang, toLang: toLang)', engine)

    def test_quick_translate_uses_the_order(self):
        source = read(QUICK)
        self.assertIn('processSignal = forkTranslationSignal(context: component.context, telegram: processSignal', source)
        self.assertIn('forkTranslationBackends(settings: context.sharedContext.immediateForkExtrasSettings)', source)

    def test_send_menu_items(self):
        params = read(SEND_PARAMS)
        self.assertIn('draftTranslation: DraftTranslation? = nil', params)
        menu = read(SEND_MENU)
        self.assertIn('if let draftTranslation = sendMessage.draftTranslation {', menu)
        self.assertIn('id: AnyHashable("translateDraft")', menu)
        self.assertIn('id: AnyHashable("translateDraftLanguage")', menu)
        options = read(SEND_OPTIONS)
        self.assertIn('draftTranslation: mediaPreview == nil ? selfController.forkDraftTranslation() : nil', options)

    def test_draft_translation_gates_and_undo(self):
        source = read(DRAFT)
        gate = source.split('func forkDraftTranslation()', 1)[1].split('let language = ', 1)[0]
        self.assertIn('settings.translateBeforeSending', gate)
        self.assertIn('peerId.namespace != Namespaces.Peer.SecretChat', gate)
        self.assertIn('inputState.content.isEntityExpressible()', gate)
        self.assertIn('self.interfaceInteraction?.updateTextInputStateAndMode', source)
        self.assertIn('undoText: self.presentationData.strings.Undo_Undo', source)


if __name__ == '__main__':
    unittest.main()
