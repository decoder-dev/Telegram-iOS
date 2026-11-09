import Foundation
import NaturalLanguage
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import TelegramUIPreferences

// Google, DeepL and Yandex get an ephemeral session: no cookies, nothing cached on disk.
private let thirdPartyTranslationSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15.0
    configuration.timeoutIntervalForResource = 30.0
    return URLSession(configuration: configuration)
}()

private let formValueAllowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

/// The translators to try, in order: the one chosen in Extras, then, with Automatic Fallback on, every other one that
/// can work. DeepL and Yandex need the user's key; Apple's on-device translation is never a fallback, since it may
/// ask to download a language in the middle of a chat.
public func forkTranslationBackends(settings: ForkExtrasSettings) -> [ForkTranslationBackend] {
    var result: [ForkTranslationBackend] = [settings.translationBackend]
    if settings.translationFallback {
        let others: [ForkTranslationBackend] = [.default, .google, .deepl, .yandex]
        for backend in others where !result.contains(backend) && hasTranslationKey(backend, settings: settings) {
            result.append(backend)
        }
    }
    return result
}

private func hasTranslationKey(_ backend: ForkTranslationBackend, settings: ForkExtrasSettings) -> Bool {
    switch backend {
    case .deepl:
        return !settings.deeplApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .yandex:
        return !settings.yandexApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .default, .system, .google:
        return true
    }
}

/// Translates one text (a draft, a quoted passage) with `backends`, by default the order from Extras, moving on to the
/// next one when a request fails, times out or comes back empty. Only Telegram keeps the entities: the other services
/// get and return plain text.
public func forkTranslateText(context: AccountContext, text: String, entities: [MessageTextEntity], toLang: String, backends: [ForkTranslationBackend]? = nil) -> Signal<(String, [MessageTextEntity]), TelegramCore.TranslationError> {
    let settings = context.sharedContext.immediateForkExtrasSettings
    return firstSuccessful(backends ?? forkTranslationBackends(settings: settings), { backend in
        return translateText(context: context, settings: settings, backend: backend, text: text, entities: entities, toLang: toLang)
    })
}

/// Google, DeepL and Yandex from the translator order as a service for the engine's chat translation, or nil when the
/// order has none of them.
public func forkThirdPartyTranslationService(settings: ForkExtrasSettings) -> ExperimentalInternalTranslationService? {
    let backends = forkTranslationBackends(settings: settings).filter { $0.isThirdParty }
    if backends.isEmpty {
        return nil
    }
    return ThirdPartyChatTranslationService(settings: settings, backends: backends)
}

/// "Translate to Spanish", worded the way the chat's translation bar words it.
public func forkTranslateToTitle(strings: PresentationStrings, language: String) -> String {
    if let name = strings.primaryComponent.dict["Translation.Language.\(language)"] {
        return strings.Conversation_Translation_TranslateTo(name).string
    }
    let name = Locale(identifier: strings.baseLanguageCode).localizedString(forLanguageCode: language) ?? language
    return strings.Conversation_Translation_TranslateToOther(name).string
}

/// The engine hands over the texts of the messages on screen and stores what comes back like Telegram's own
/// translations. Empty texts are not sent and keep their original. A text one service fails on goes to the next; one
/// that every service fails on keeps its original too, and only when nothing was translated does the engine get nil.
private final class ThirdPartyChatTranslationService: ExperimentalInternalTranslationService {
    private let settings: ForkExtrasSettings
    private let backends: [ForkTranslationBackend]

    init(settings: ForkExtrasSettings, backends: [ForkTranslationBackend]) {
        self.settings = settings
        self.backends = backends
    }

    func translate(texts: [AnyHashable: String], fromLang: String, toLang: String) -> Signal<[AnyHashable: String]?, NoError> {
        // Polls and media without a caption come through as empty texts.
        let keys = texts.keys.filter { !(texts[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if keys.isEmpty {
            return .single([:])
        }
        let values = keys.map { texts[$0] ?? "" }
        return translateWithFallback(self.backends, settings: self.settings, texts: values, toLang: toLang)
        |> map { translated -> [AnyHashable: String]? in
            if !translated.contains(where: { $0 != nil }) {
                return nil
            }
            var result: [AnyHashable: String] = [:]
            for (key, text) in zip(keys, translated) {
                if let text {
                    result[key] = text
                }
            }
            return result
        }
    }
}

/// Translates with the first service and hands only the texts it failed on to the next one.
private func translateWithFallback(_ backends: [ForkTranslationBackend], settings: ForkExtrasSettings, texts: [String], toLang: String) -> Signal<[String?], NoError> {
    guard let backend = backends.first else {
        return .single(texts.map { _ -> String? in nil })
    }
    let rest = Array(backends.dropFirst())
    return translateTexts(backend: backend, settings: settings, texts: texts, toLang: toLang)
    |> mapToSignal { translated -> Signal<[String?], NoError> in
        let failed = translated.indices.filter { translated[$0] == nil }
        if failed.isEmpty || rest.isEmpty {
            return .single(translated)
        }
        return translateWithFallback(rest, settings: settings, texts: failed.map { texts[$0] }, toLang: toLang)
        |> map { retried -> [String?] in
            var result = translated
            for (index, text) in zip(failed, retried) {
                result[index] = text
            }
            return result
        }
    }
}

private func firstSuccessful<T>(_ backends: [ForkTranslationBackend], _ translate: @escaping (ForkTranslationBackend) -> Signal<T, TelegramCore.TranslationError>) -> Signal<T, TelegramCore.TranslationError> {
    guard let backend = backends.first else {
        return .fail(.generic)
    }
    let rest = Array(backends.dropFirst())
    return translate(backend)
    |> `catch` { error -> Signal<T, TelegramCore.TranslationError> in
        if rest.isEmpty {
            return .fail(error)
        }
        return firstSuccessful(rest, translate)
    }
}

private func translateText(context: AccountContext, settings: ForkExtrasSettings, backend: ForkTranslationBackend, text: String, entities: [MessageTextEntity], toLang: String) -> Signal<(String, [MessageTextEntity]), TelegramCore.TranslationError> {
    switch backend {
    case .default:
        return context.engine.messages.translate(text: text, toLang: toLang, entities: entities)
        |> mapToSignal { result -> Signal<(String, [MessageTextEntity]), TelegramCore.TranslationError> in
            guard let result, !result.0.isEmpty else {
                return .fail(.generic)
            }
            return .single(result)
        }
        |> timeout(20.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.generic))
    case .system:
        guard let service = engineExperimentalInternalTranslationService, let fromLang = recognizedLanguage(text) else {
            return .fail(.generic)
        }
        return service.translate(texts: [AnyHashable(0): text], fromLang: fromLang, toLang: toLang)
        |> castError(TelegramCore.TranslationError.self)
        |> mapToSignal { result -> Signal<(String, [MessageTextEntity]), TelegramCore.TranslationError> in
            guard let translated = result?[AnyHashable(0)], !translated.isEmpty else {
                return .fail(.generic)
            }
            return .single((translated, []))
        }
        |> timeout(20.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.generic))
    case .google, .deepl, .yandex:
        return translateTexts(backend: backend, settings: settings, texts: [text], toLang: toLang)
        |> castError(TelegramCore.TranslationError.self)
        |> mapToSignal { translated -> Signal<(String, [MessageTextEntity]), TelegramCore.TranslationError> in
            guard let result = translated.first ?? nil else {
                return .fail(.generic)
            }
            return .single((result, []))
        }
    }
}

private func recognizedLanguage(_ text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(256)))
    guard let language = recognizer.dominantLanguage else {
        return nil
    }
    let code = normalizeTranslationLanguage(language.rawValue)
    return supportedTranslationLanguages.contains(code) ? code : nil
}

/// One entry per text, in order: its translation, or nil where this service failed on it.
private func translateTexts(backend: ForkTranslationBackend, settings: ForkExtrasSettings, texts: [String], toLang: String) -> Signal<[String?], NoError> {
    switch backend {
    case .google:
        return googleTranslate(texts: texts, toLang: toLang)
    case .deepl:
        // DeepL takes at most 50 texts per request.
        let chunks = stride(from: 0, to: texts.count, by: 50).map { Array(texts[$0 ..< min($0 + 50, texts.count)]) }
        return translateInChunks(chunks, { chunk in
            return deeplTranslate(texts: chunk, toLang: toLang, apiKey: settings.deeplApiKey)
        })
    case .yandex:
        return translateInChunks(yandexChunks(texts), { chunk in
            return yandexTranslate(texts: chunk, toLang: toLang, apiKey: settings.yandexApiKey)
        })
    case .default, .system:
        return .single(texts.map { _ -> String? in nil })
    }
}

/// Sends the chunks one after another and puts the results back together in order. A chunk that fails leaves nil
/// for its texts and does not stop the ones after it.
private func translateInChunks(_ chunks: [[String]], _ translate: @escaping ([String]) -> Signal<[String], TelegramCore.TranslationError>) -> Signal<[String?], NoError> {
    var signal: Signal<[String?], NoError> = .single([])
    for chunk in chunks {
        signal = signal
        |> mapToSignal { previous -> Signal<[String?], NoError> in
            return translate(chunk)
            |> map { translated -> [String?] in
                return previous + translated.map { text -> String? in text }
            }
            |> `catch` { _ -> Signal<[String?], NoError> in
                return .single(previous + chunk.map { _ -> String? in nil })
            }
        }
    }
    return signal
}

/// Yandex takes at most 10,000 characters per request, all the texts together. A longer text goes alone and fails,
/// which leaves it to the next service.
private func yandexChunks(_ texts: [String]) -> [[String]] {
    var chunks: [[String]] = []
    var current: [String] = []
    var length = 0
    for text in texts {
        let textLength = text.utf16.count
        if !current.isEmpty && length + textLength > 10000 {
            chunks.append(current)
            current = []
            length = 0
        }
        current.append(text)
        length += textLength
    }
    if !current.isEmpty {
        chunks.append(current)
    }
    return chunks
}

/// The free endpoint takes one text per request. Firing one for every message on screen at once got the whole batch
/// rate-limited, so they go three at a time, and a text that fails is left for the next service. When a whole group
/// fails Google is limiting or unreachable, and the rest is not sent at all.
private func googleTranslate(texts: [String], toLang: String) -> Signal<[String?], NoError> {
    let groupSize = 3
    var signal: Signal<[String?], NoError> = .single([])
    for start in stride(from: 0, to: texts.count, by: groupSize) {
        let group = Array(texts[start ..< min(start + groupSize, texts.count)])
        signal = signal
        |> mapToSignal { previous -> Signal<[String?], NoError> in
            if !previous.isEmpty && previous.suffix(groupSize).allSatisfy({ $0 == nil }) {
                return .single(previous + group.map { _ -> String? in nil })
            }
            return combineLatest(group.map { text -> Signal<String?, NoError> in
                return googleTranslate(text: text, toLang: toLang)
                |> map { translated -> String? in
                    return translated
                }
                |> `catch` { _ -> Signal<String?, NoError> in
                    return .single(nil)
                }
            })
            |> map { translated -> [String?] in
                return previous + translated
            }
        }
    }
    return signal
}

private func googleTranslate(text: String, toLang: String) -> Signal<String, TelegramCore.TranslationError> {
    var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
    components?.queryItems = [
        URLQueryItem(name: "client", value: "gtx"),
        URLQueryItem(name: "sl", value: "auto"),
        URLQueryItem(name: "tl", value: googleLanguageCode(toLang)),
        URLQueryItem(name: "dt", value: "t"),
        URLQueryItem(name: "ie", value: "UTF-8"),
        URLQueryItem(name: "oe", value: "UTF-8")
    ]
    guard let url = components?.url else {
        return .fail(.generic)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(getRandomUserAgent(), forHTTPHeaderField: "User-Agent")
    request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
    // The text goes in the body: an address has a length limit and ends up in more logs.
    request.httpBody = ("q=" + (text.addingPercentEncoding(withAllowedCharacters: formValueAllowedCharacters) ?? "")).data(using: .utf8)
    return performTranslationRequest(request, count: 1, parse: { json in
        // [[["Hola. ", "Hello. ", ...], ["¿Qué tal?", "How are you?", ...]], null, "en", ...]
        guard let root = json as? [Any], let pieces = root.first as? [Any] else {
            return nil
        }
        return [pieces.compactMap { ($0 as? [Any])?.first as? String }.joined()]
    })
    |> map { translated -> String in
        return translated[0]
    }
}

private func deeplTranslate(texts: [String], toLang: String, apiKey: String) -> Signal<[String], TelegramCore.TranslationError> {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    // Free plan keys end in ":fx" and only work on the free host.
    let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
    let parameters: [String: Any] = ["text": texts, "target_lang": deeplLanguageCode(toLang)]
    guard !key.isEmpty, let url = URL(string: "https://\(host)/v2/translate"), let body = try? JSONSerialization.data(withJSONObject: parameters) else {
        return .fail(.generic)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return performTranslationRequest(request, count: texts.count, parse: { json in
        guard let root = json as? [String: Any], let translations = root["translations"] as? [[String: Any]] else {
            return nil
        }
        return translations.map { ($0["text"] as? String) ?? "" }
    })
}

private func yandexTranslate(texts: [String], toLang: String, apiKey: String) -> Signal<[String], TelegramCore.TranslationError> {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    // An API key belongs to a service account, which already belongs to a folder, so no folderId is sent with it.
    let parameters: [String: Any] = ["texts": texts, "targetLanguageCode": toLang, "format": "PLAIN_TEXT"]
    guard !key.isEmpty, let url = URL(string: "https://translate.api.cloud.yandex.net/translate/v2/translate"), let body = try? JSONSerialization.data(withJSONObject: parameters) else {
        return .fail(.generic)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Api-Key \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return performTranslationRequest(request, count: texts.count, parse: { json in
        guard let root = json as? [String: Any], let translations = root["translations"] as? [[String: Any]] else {
            return nil
        }
        return translations.map { ($0["text"] as? String) ?? "" }
    })
}

/// Runs the request on URLSession's own queue and hands `parse` the JSON of a 200 response. A transport error, any
/// other status, an unexpected body or an empty translation fails, which moves the caller on to the next service.
/// Neither the text nor the key is ever logged.
private func performTranslationRequest(_ request: URLRequest, count: Int, parse: @escaping (Any) -> [String]?) -> Signal<[String], TelegramCore.TranslationError> {
    return Signal { subscriber in
        let task = thirdPartyTranslationSession.dataTask(with: request, completionHandler: { data, response, error in
            guard error == nil, let response = response as? HTTPURLResponse else {
                subscriber.putError(.generic)
                return
            }
            if response.statusCode != 200 {
                subscriber.putError(response.statusCode == 429 ? .limitExceeded : .generic)
                return
            }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data), let result = parse(json), result.count == count, !result.contains(where: { $0.isEmpty }) else {
                subscriber.putError(.generic)
                return
            }
            subscriber.putNext(result)
            subscriber.putCompletion()
        })
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

private func googleLanguageCode(_ code: String) -> String {
    switch code {
    case "zh":
        return "zh-CN"
    case "pt-BR":
        return "pt"
    default:
        return code
    }
}

private func deeplLanguageCode(_ code: String) -> String {
    switch code {
    case "en":
        return "EN-US"
    case "pt", "pt-BR":
        return "PT-BR"
    case "zh":
        return "ZH-HANS"
    case "no":
        return "NB"
    default:
        return code.uppercased()
    }
}
