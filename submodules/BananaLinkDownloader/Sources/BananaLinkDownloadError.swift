import Foundation

/// Why a link could not be turned into media. `reason` is the Russian text shown on the toast.
public enum BananaLinkDownloadError: Error, Equatable {
    case cancelled
    case tiktokLinkExpired
    case tiktokNotFound
    case tiktokPrivate
    case tiktokStatus(Int)
    case tiktokNoData
    case youtubeLoginRequired
    case youtubeAgeRestricted
    case youtubeUnavailable
    case youtubeTooLong
    case noCompatibleFormat
    case tooLarge
    case batchTooLarge
    case httpStatus(Int)
    case network(URLError.Code)
    case processingFailed

    init(_ error: Error) {
        if let urlError = error as? URLError {
            self = urlError.code == .cancelled ? .cancelled : .network(urlError.code)
        } else {
            self = .network(.unknown)
        }
    }

    public func localizedReason(russian: Bool) -> String {
        switch self {
        case .cancelled:
            return russian ? "Скачивание отменено" : "Download cancelled"
        case .tiktokLinkExpired:
            return russian ? "Ссылка TikTok устарела или неверная" : "The TikTok link expired or is invalid"
        case .tiktokNotFound:
            return russian ? "Видео удалено или недоступно" : "The video was deleted or is unavailable"
        case .tiktokPrivate:
            return russian ? "Закрытый аккаунт" : "The account is private"
        case let .tiktokStatus(code):
            return russian ? "TikTok не отдал видео (код \(code))" : "TikTok could not provide the video (code \(code))"
        case .tiktokNoData:
            return russian ? "TikTok не отдал страницу (проверка на бота)" : "TikTok did not provide the page (possibly a bot check)"
        case .youtubeLoginRequired:
            return russian ? "YouTube просит войти в аккаунт" : "YouTube requires you to sign in"
        case .youtubeAgeRestricted:
            return russian ? "Видео 18+, без входа не скачать" : "Age-restricted videos require a signed-in account"
        case .youtubeUnavailable:
            return russian ? "Видео недоступно" : "The video is unavailable"
        case .youtubeTooLong:
            return russian ? "Это не Shorts, а длинное видео" : "This video is too long to be a Short"
        case .noCompatibleFormat:
            return russian ? "Нет подходящего формата" : "No compatible media format was found"
        case .tooLarge:
            return russian ? "Файл больше 200 МБ" : "A media file exceeds 200 MB"
        case .batchTooLarge:
            return russian ? "Общий объём медиа больше 500 МБ" : "The total media download exceeds 500 MB"
        case let .httpStatus(code):
            return russian ? "Сервер не отдал файл (HTTP \(code))" : "The server could not provide the file (HTTP \(code))"
        case let .network(code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return russian ? "Нет интернета" : "No internet connection"
            case .timedOut:
                return russian ? "Сервер долго не отвечает" : "The server took too long to respond"
            default:
                return URLError(code).localizedDescription
            }
        case .processingFailed:
            return "Не удалось обработать файл"
        }
    }
}
