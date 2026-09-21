import Foundation
import TelegramVLESS
import TelegramUIPreferences

func vlessEditorInfo(_ url: String) -> String {
    let ru = ForkPresentationLanguage.prefersRussianStrings
    let instruction = ru ? "Вставьте полную ссылку vless:// от вашего провайдера. Звонки используют прокси, если включено «Использовать для звонков»." : "Paste the complete vless:// link from your provider. Calls use the proxy when ‘Use for calls’ is enabled."
    if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return instruction
    }
    switch VlessProfileParser.parse(url) {
    case let .success(profile):
        var details = "\(profile.endpoint.host):\(profile.endpoint.port) · \(profile.transport.rawValue.uppercased()) · \(profile.security.rawValue.uppercased())"
        if profile.allowInsecure {
            details += ru ? "\nПроверка сертификата отключена в ссылке." : "\nCertificate verification is disabled in this link."
        }
        return instruction + "\n\n" + details
    case let .failure(error):
        let message: String
        switch error {
        case .empty: message = instruction
        case .tooLong: message = ru ? "Ссылка длиннее 8192 байт." : "The link exceeds 8192 bytes."
        case .invalidUserId: message = ru ? "Некорректный UUID пользователя." : "Invalid user UUID."
        case .invalidHost, .invalidServerName: message = ru ? "Проверьте адрес сервера и SNI." : "Check the server address and SNI."
        case .invalidPort: message = ru ? "Порт должен быть от 1 до 65535." : "The port must be between 1 and 65535."
        case .invalidPublicKey, .missingRealityPublicKey: message = ru ? "Проверьте публичный ключ REALITY (pbk)." : "Check the REALITY public key (pbk)."
        case .invalidShortId: message = ru ? "Short ID: чётное число шестнадцатеричных символов, не больше 16." : "Short ID must contain an even number of hexadecimal characters, at most 16."
        case .duplicateParameter: message = ru ? "В ссылке повторяется параметр." : "The link contains a duplicate parameter."
        case let .unsupportedParameter(name): message = (ru ? "Неподдерживаемый параметр: " : "Unsupported parameter: ") + String(name.prefix(60))
        case .unsupportedTransport: message = ru ? "Поддерживаются TCP, WebSocket, gRPC, HTTPUpgrade и XHTTP." : "Supported transports: TCP, WebSocket, gRPC, HTTPUpgrade and XHTTP."
        case .unsupportedSecurity: message = ru ? "Поддерживаются TLS, REALITY и none." : "Supported security: TLS, REALITY and none."
        case .unsupportedFlow: message = ru ? "Неподдерживаемый flow." : "Unsupported flow."
        case .unsupportedEncryption: message = ru ? "Некорректный параметр encryption." : "Invalid encryption parameter."
        case .unsupportedFingerprint: message = ru ? "Неподдерживаемый fingerprint (fp)." : "Unsupported fingerprint (fp)."
        case .invalidAlpn: message = ru ? "ALPN: h2 и/или http/1.1 через запятую." : "ALPN: h2 and/or http/1.1, separated by a comma."
        case .invalidExtra: message = ru ? "Параметр extra должен содержать JSON-объект до 4096 байт." : "The extra parameter must be a JSON object of at most 4096 bytes."
        case .invalidAllowInsecure: message = ru ? "allowInsecure: 0, 1, false или true." : "allowInsecure must be 0, 1, false or true."
        default: message = ru ? "Некорректная ссылка. Нужен формат vless://UUID@сервер:порт?параметры." : "Invalid link. Expected vless://UUID@server:port?parameters."
        }
        return instruction + "\n\n" + message
    }
}
