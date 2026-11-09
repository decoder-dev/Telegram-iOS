import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import PresentationDataUtils

/// A BananaGram build published on the fork's GitHub Releases page.
public struct BananaRelease: Equatable {
    public let tag: String
    public let version: String
    public let build: Int
    public let isPrerelease: Bool
    public let notes: String
    public let pageUrl: String
    /// The .ipa's line in the release's SHA256SUMS.txt, so the download can be checked; nil when there is none.
    public let ipaSha256: String?
}

public enum BananaUpdateCheckResult: Equatable {
    case upToDate
    case available(BananaRelease)
    case failed
}

private let bananaReleasesUrl = URL(string: "https://api.github.com/repos/decoder-dev/Telegram-iOS/releases?per_page=30")!
private let bananaLastAutomaticCheckKey = "BananaUpdateCheck.lastAutomaticCheck"

/// No cookies, no cache, nothing about the user: GitHub sees an anonymous request with this User-Agent.
private let bananaUpdateSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20.0
    configuration.httpAdditionalHeaders = ["User-Agent": "BananaGram"]
    return URLSession(configuration: configuration)
}()

/// This build's number. CI passes the run's build number as CFBundleVersion and puts the same number in the release
/// tag (v13.1.2-4511-pre), so the two compare directly.
var bananaCurrentBuild: Int? {
    return (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }
}

var bananaCurrentVersion: String {
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
}

/// The build number in a release tag: 4511 in v13.1.2-4511 and in v13.1.2-4511-pre.
func bananaBuildNumber(tag: String) -> Int? {
    return tag.split(separator: "-").reversed().compactMap({ Int($0) }).first
}

private func bananaFetch(_ url: URL, accept: String?) -> Signal<Data?, NoError> {
    return Signal { subscriber in
        var request = URLRequest(url: url)
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        let task = bananaUpdateSession.dataTask(with: request, completionHandler: { data, response, _ in
            if let response = response as? HTTPURLResponse, response.statusCode == 200 {
                subscriber.putNext(data)
            } else {
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        })
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}

/// The hash on the .ipa's line of a SHA256SUMS.txt (`sha256sum` output: "<hash>  <file name>").
private func bananaIpaSha256(sums: String) -> String? {
    for line in sums.split(whereSeparator: { $0.isNewline }) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count >= 2, parts[0].count == 64, parts[parts.count - 1].lowercased().hasSuffix(".ipa") {
            return String(parts[0]).lowercased()
        }
    }
    return nil
}

/// The newest published release (pre-releases too, if asked), compared with this build.
public func bananaCheckForUpdates(includePrereleases: Bool) -> Signal<BananaUpdateCheckResult, NoError> {
    return bananaFetch(bananaReleasesUrl, accept: "application/vnd.github+json")
    |> mapToSignal { data -> Signal<BananaUpdateCheckResult, NoError> in
        guard let data, let releases = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], let currentBuild = bananaCurrentBuild else {
            return .single(.failed)
        }
        var best: (build: Int, release: [String: Any])?
        for release in releases {
            if release["draft"] as? Bool == true {
                continue
            }
            if !includePrereleases && release["prerelease"] as? Bool == true {
                continue
            }
            guard let tag = release["tag_name"] as? String, let build = bananaBuildNumber(tag: tag) else {
                continue
            }
            if build > (best?.build ?? Int.min) {
                best = (build, release)
            }
        }
        guard let newest = best, newest.build > currentBuild, let tag = newest.release["tag_name"] as? String else {
            return .single(.upToDate)
        }
        let versionPart = tag.split(separator: "-").first.map { String($0) } ?? tag
        let makeRelease: (String?) -> BananaRelease = { sha256 in
            return BananaRelease(
                tag: tag,
                version: versionPart.hasPrefix("v") ? String(versionPart.dropFirst()) : versionPart,
                build: newest.build,
                isPrerelease: newest.release["prerelease"] as? Bool == true,
                notes: (newest.release["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                pageUrl: newest.release["html_url"] as? String ?? "https://github.com/decoder-dev/Telegram-iOS/releases/tag/\(tag)",
                ipaSha256: sha256
            )
        }
        let assets = newest.release["assets"] as? [[String: Any]] ?? []
        guard let sumsAsset = assets.first(where: { $0["name"] as? String == "SHA256SUMS.txt" }), let sumsUrl = (sumsAsset["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            return .single(.available(makeRelease(nil)))
        }
        return bananaFetch(sumsUrl, accept: nil)
        |> map { sums -> BananaUpdateCheckResult in
            let sha256 = sums.flatMap { String(data: $0, encoding: .utf8) }.flatMap(bananaIpaSha256(sums:))
            return .available(makeRelease(sha256))
        }
    }
}

/// On launch, at most once a day and only with Check Automatically on: says so when a newer build is out.
public func bananaCheckForUpdatesAutomatically(sharedContext: SharedAccountContext) {
    let _ = (forkExtrasSettings(accountManager: sharedContext.accountManager)
    |> take(1)
    |> mapToSignal { settings -> Signal<BananaUpdateCheckResult, NoError> in
        guard settings.updateCheckAutomatically else {
            return .complete()
        }
        let now = Date().timeIntervalSince1970
        let lastCheck = UserDefaults.standard.double(forKey: bananaLastAutomaticCheckKey)
        if now >= lastCheck && now < lastCheck + 24.0 * 60.0 * 60.0 {
            return .complete()
        }
        UserDefaults.standard.set(now, forKey: bananaLastAutomaticCheckKey)
        return bananaCheckForUpdates(includePrereleases: settings.updateCheckIncludesPrereleases)
    }
    |> deliverOnMainQueue).start(next: { result in
        guard case let .available(release) = result else {
            return
        }
        let russian = ForkPresentationLanguage.prefersRussianStrings
        let title = russian ? "Доступна новая версия" : "Update Available"
        let text = russian ? "BananaGram \(release.version) (\(release.build)) можно скачать на GitHub." : "BananaGram \(release.version) (\(release.build)) is available on GitHub."
        let alert = textAlertController(sharedContext: sharedContext, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: russian ? "Позже" : "Later", action: {}),
            TextAlertAction(type: .defaultAction, title: russian ? "Открыть" : "Open", action: {
                sharedContext.applicationBindings.openUrl(release.pageUrl)
            })
        ])
        sharedContext.mainWindow?.present(alert, on: .root, blockInteraction: false, completion: {})
    })
}
