import Foundation

/// Why a link could not be turned into media. `reason` is the Russian text shown on the toast.
public enum BananaLinkDownloadError: Error, Equatable {
    case cancelled
    case tiktokNotFound
    case tiktokPrivate
    case tiktokStatus(Int)
    /// The post page came without the post's data; the title of what came instead, when it has one.
    case tiktokNoData(String?)
    /// TikTok sent the post page, or a short link, to another page: its path.
    case tiktokRedirected(String)
    case tiktokShortLinkRedirected(String)
    /// TikTok left Hong Kong in 2020 and sends every request from there to "/hk/about"; for this app's users that
    /// means a VPN server there, so the toast speaks of the VPN.
    case tiktokHongKong
    case tiktokLoginRequired
    case tiktokAgeRestricted
    case tiktokNoFile
    case tiktokPageStatus(Int)
    case tiktokPageDenied
    case tiktokBotCheck
    case tiktokFileStatus(Int)
    case tiktokUnavailable
    case tiktokDownloadServiceStatus(Int)
    /// TikTok refused (first) and TikWM failed after it (second): TikWM's answer alone hides why TikTok refused.
    indirect case tiktokFailed(BananaLinkDownloadError, BananaLinkDownloadError)
    case youtubeLoginRequired
    case youtubeAgeRestricted
    case youtubeUnavailable
    case youtubeTooLong
    case noCompatibleFormat
    case pageTooLarge
    case batchTooLarge
    case tooLarge
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

    public var reason: String {
        switch self {
        case .cancelled:
            return "Скачивание отменено"
        case .tiktokNotFound:
            return "Видео удалено или недоступно"
        case .tiktokPrivate:
            return "Закрытый аккаунт"
        case let .tiktokStatus(code):
            return "TikTok не отдал видео (код \(code))"
        case let .tiktokNoData(title):
            return "TikTok прислал страницу без видео" + (title.map { ": «\($0)»" } ?? "")
        case let .tiktokRedirected(path):
            return "TikTok открыл \(BananaLinkDownloadError.placeName(path)) вместо видео"
        case let .tiktokShortLinkRedirected(path):
            return "Короткая ссылка TikTok ведёт на \(BananaLinkDownloadError.placeName(path)), а не на видео"
        case .tiktokHongKong:
            return "TikTok не работает через этот VPN, смените сервер"
        case .tiktokLoginRequired:
            return "TikTok просит войти в аккаунт"
        case .tiktokAgeRestricted:
            return "TikTok не отдаёт это видео без входа (18+)"
        case .tiktokNoFile:
            return "TikTok не дал ссылку на файл"
        case let .tiktokPageStatus(code):
            return "TikTok не отдал страницу (HTTP \(code))"
        case .tiktokPageDenied:
            return "TikTok отклонил запрос"
        case .tiktokBotCheck:
            return "TikTok не пропустил проверку на бота"
        case let .tiktokFileStatus(code):
            return "TikTok не отдал файл (HTTP \(code))"
        case .tiktokUnavailable:
            return "Сервис скачивания TikTok не отдал видео"
        case let .tiktokDownloadServiceStatus(code):
            return "Сервис скачивания TikTok вернул HTTP \(code)"
        case let .tiktokFailed(direct, fallback):
            return [direct.reason, fallback.reason].map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.joined(separator: ". ")
        case .youtubeLoginRequired:
            return "YouTube просит войти в аккаунт"
        case .youtubeAgeRestricted:
            return "Видео 18+, без входа не скачать"
        case .youtubeUnavailable:
            return "Видео недоступно"
        case .youtubeTooLong:
            return "Это не Shorts, а длинное видео"
        case .noCompatibleFormat:
            return "Нет подходящего формата"
        case .pageTooLarge: return "Страница источника больше 16 МБ"
        case .batchTooLarge: return "Общий объём медиа больше 500 МБ"
        case .tooLarge:
            return "Файл больше 200 МБ"
        case let .httpStatus(code):
            return "Сервер не отдал файл (HTTP \(code))"
        case let .network(code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "Нет интернета"
            case .timedOut:
                return "Сервер долго не отвечает"
            default:
                return URLError(code).localizedDescription
            }
        case .processingFailed:
            return "Не удалось обработать файл"
        }
    }

    /// A TikTok page path as the toast names it.
    private static func placeName(_ path: String) -> String {
        if path.isEmpty || path == "/" {
            return "главную"
        }
        return path.count > 40 ? String(path.prefix(40)) + "…" : path
    }
    public func localizedReason(russian: Bool) -> String {
        if russian { return self.reason }
        switch self {
        case .cancelled: return "Download cancelled"
        case .tiktokNotFound: return "The video was deleted or is unavailable"
        case .tiktokPrivate: return "The account is private"
        case let .tiktokStatus(code): return "TikTok could not provide the video (code \(code))"
        case let .tiktokNoData(title): return "TikTok returned a page without video" + (title.map { ": \($0)" } ?? "")
        case let .tiktokRedirected(path), let .tiktokShortLinkRedirected(path): return "TikTok redirected to \(path) instead of the post"
        case .tiktokHongKong: return "TikTok does not work through this VPN; change the server"
        case .tiktokLoginRequired: return "TikTok requires sign-in"
        case .tiktokAgeRestricted: return "This TikTok video requires sign-in (18+)"
        case .tiktokNoFile: return "TikTok provided no media URL"
        case let .tiktokPageStatus(code): return "TikTok page returned HTTP \(code)"
        case .tiktokPageDenied: return "TikTok denied the request"
        case .tiktokBotCheck: return "TikTok's bot check did not succeed"
        case let .tiktokFileStatus(code): return "TikTok media returned HTTP \(code)"
        case .tiktokUnavailable: return "The TikTok download service returned no media"
        case let .tiktokDownloadServiceStatus(code): return "The TikTok download service returned HTTP \(code)"
        case let .tiktokFailed(direct, fallback): return [direct.localizedReason(russian: false), fallback.localizedReason(russian: false)].joined(separator: ". ")
        case .youtubeLoginRequired: return "YouTube requires sign-in"
        case .youtubeAgeRestricted: return "Age-restricted videos require sign-in"
        case .youtubeUnavailable: return "The video is unavailable"
        case .youtubeTooLong: return "This video is too long to be a Short"
        case .noCompatibleFormat: return "No compatible media format was found"
        case .pageTooLarge: return "The source page exceeds 16 MB"
        case .tooLarge: return "A media file exceeds 200 MB"
        case .batchTooLarge: return "The total media download exceeds 500 MB"
        case let .httpStatus(code): return "The server returned HTTP \(code)"
        case let .network(code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: return "No internet connection"
            case .timedOut: return "The server took too long to respond"
            default: return URLError(code).localizedDescription
            }
        case .processingFailed: return "Could not process the media file"
        }
    }

}
