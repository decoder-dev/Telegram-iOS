import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import PresentationDataUtils
import AccountContext

enum PrivacyCheckSubject: Int, CaseIterable {
    case phoneNumber, phoneDiscovery, forwards, voiceCalls, callP2P, presence, profilePhoto, bio, birthday
    case twoStepVerification, activeSessions
}

struct PrivacyCheckRow: Equatable {
    let subject: PrivacyCheckSubject
    let title: String
    let audience: String
}

func privacyCheckTitle(russian: Bool) -> String {
    return russian ? "Проверка приватности" : "Privacy check"
}

func privacyCheckAudience(_ setting: SelectivePrivacySettings, russian: Bool) -> String {
    let base: String
    var additions: [String] = []
    switch setting {
    case let .enableEveryone(disableFor):
        base = russian ? "Все" : "Everybody"
        if !disableFor.isEmpty {
            additions.append(russian ? "кроме исключений" : "with exclusions")
        }
    case let .enableContacts(enableFor, disableFor, premium, bots):
        base = russian ? "Контакты" : "Contacts"
        if !enableFor.isEmpty { additions.append(russian ? "другие исключения" : "additional exceptions") }
        if !disableFor.isEmpty { additions.append(russian ? "кроме исключений" : "with exclusions") }
        if premium { additions.append("Premium") }
        if bots { additions.append(russian ? "боты" : "bots") }
    case let .disableEveryone(enableFor, closeFriends, premium, bots):
        if enableFor.isEmpty && !closeFriends && !premium && !bots {
            return russian ? "Никто" : "Nobody"
        }
        base = russian ? "Только разрешённые" : "Allowed exceptions only"
        if !enableFor.isEmpty { additions.append(russian ? "пользователи или группы" : "users or groups") }
        if closeFriends { additions.append(russian ? "близкие друзья" : "close friends") }
        if premium { additions.append("Premium") }
        if bots { additions.append(russian ? "боты" : "bots") }
    }
    return additions.isEmpty ? base : base + " · " + additions.joined(separator: ", ")
}

func privacyCheckRows(settings: AccountPrivacySettings, russian: Bool) -> [PrivacyCheckRow] {
    return [
        PrivacyCheckRow(subject: .phoneNumber, title: russian ? "Видимость номера" : "Phone number visibility", audience: privacyCheckAudience(settings.phoneNumber, russian: russian)),
        PrivacyCheckRow(subject: .phoneDiscovery, title: russian ? "Поиск по номеру" : "Find me by phone number", audience: settings.phoneDiscoveryEnabled ? (russian ? "Все" : "Everybody") : (russian ? "Контакты" : "Contacts")),
        PrivacyCheckRow(subject: .forwards, title: russian ? "Ссылка в пересылках" : "Profile link in forwards", audience: privacyCheckAudience(settings.forwards, russian: russian)),
        PrivacyCheckRow(subject: .voiceCalls, title: russian ? "Кто может звонить" : "Who can call", audience: privacyCheckAudience(settings.voiceCalls, russian: russian)),
        PrivacyCheckRow(subject: .callP2P, title: russian ? "Прямые звонки P2P" : "Peer-to-peer calls", audience: privacyCheckAudience(settings.voiceCallsP2P, russian: russian)),
        PrivacyCheckRow(subject: .presence, title: russian ? "Время посещения" : "Last seen", audience: privacyCheckAudience(settings.presence, russian: russian)),
        PrivacyCheckRow(subject: .profilePhoto, title: russian ? "Основное фото профиля" : "Main profile photo", audience: privacyCheckAudience(settings.profilePhoto, russian: russian)),
        PrivacyCheckRow(subject: .bio, title: russian ? "О себе" : "Bio", audience: privacyCheckAudience(settings.bio, russian: russian)),
        PrivacyCheckRow(subject: .birthday, title: russian ? "День рождения" : "Birthday", audience: privacyCheckAudience(settings.birthday, russian: russian))
    ]
}

// The check only requests this account's Telegram privacy settings. It does not
// look up other people, contact external services, log results or change rules.
func privacyCheckController(
    context: AccountContext,
    activeSessionsContext: ActiveSessionsContext,
    settingsLoaded: @escaping (AccountPrivacySettings) -> Void,
    openSetting: @escaping (PrivacyCheckSubject) -> Void
) -> ActionSheetController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let russian = ForkPresentationLanguage.prefersRussianStrings
    let controller = ActionSheetController(presentationData: presentationData)
    let disposable = MetaDisposable()
    var isActive = true
    let cancelGroup = ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Close, color: .accent, action: { [weak controller] in
        isActive = false
        disposable.dispose()
        controller?.dismissAnimated()
    })])
    controller.setItemGroups([
        ActionSheetItemGroup(items: [ActionSheetTextItem(title: russian ? "Получаем настройки приватности…" : "Loading privacy settings…", parseMarkdown: false)]),
        cancelGroup
    ])
    controller.dismissed = { _ in
        isActive = false
        disposable.dispose()
    }

    activeSessionsContext.loadMore()
    let sessionCount = activeSessionsContext.state
    |> filter { !$0.isLoadingMore && $0.sessions.contains(where: { $0.isCurrent }) }
    |> map { Optional($0.sessions.count) }
    |> take(1)
    |> timeout(12.0, queue: .mainQueue(), alternate: .single(nil))

    let twoStep = context.engine.auth.twoStepVerificationConfiguration()
    |> map { configuration -> Bool? in
        if case .set = configuration { return true }
        return false
    }
    |> then(.single(nil))
    |> take(1)
    |> timeout(12.0, queue: .mainQueue(), alternate: .single(nil))

    // The engine can complete without a value on a request error. Convert that
    // case, and a stalled request, to an explicit unavailable result.
    let request = context.engine.privacy.requestAccountPrivacySettings()
    |> map { Optional($0) }
    |> then(.single(nil))
    |> take(1)
    |> timeout(12.0, queue: .mainQueue(), alternate: .single(nil))
    |> deliverOnMainQueue
    disposable.set((combineLatest(request, twoStep, sessionCount)
    |> deliverOnMainQueue).start(next: { [weak controller] settings, twoStepEnabled, sessionCount in
        guard isActive, let controller else { return }
        if let settings { settingsLoaded(settings) }
        let note = russian
            ? "Настройки этого аккаунта. Нажмите на пункт, чтобы изменить его. Прямой звонок может раскрыть IP собеседнику. Публичное фото и уже опубликованные данные здесь не проверяются. Настройки не меняются автоматически."
            : "This account's settings. Tap a row to edit it. A direct call may reveal your IP to the other caller. Public profile photos and previously published data are not checked here. Nothing is changed automatically."
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: privacyCheckTitle(russian: russian) + "\n\n" + note, parseMarkdown: false)]
        let fields = privacyCheckSnapshotFields(settings: settings, twoStepEnabled: twoStepEnabled)
        let comparison = privacyCheckCompareAndStore(accountId: context.account.id.int64, fields: fields)
        let comparisonText: String
        switch comparison {
        case .firstCheck:
            comparisonText = russian ? "Первая успешная проверка: сохранена точка сравнения на этом устройстве." : "First successful check: a baseline was saved on this device."
        case .unchanged:
            comparisonText = russian ? "В проверенных пунктах изменений с прошлой проверки нет." : "No changes in the checked settings since the previous check."
        case let .changed(subjects):
            let titles = (settings.map { privacyCheckRows(settings: $0, russian: russian) } ?? [])
            let names = subjects.map { subject in
                if subject == .twoStepVerification { return russian ? "Двухэтапная защита" : "Two-step verification" }
                return titles.first(where: { $0.subject == subject })?.title ?? ""
            }
            comparisonText = (russian ? "Изменилось с прошлой проверки: " : "Changed since the previous check: ") + names.joined(separator: ", ")
        case .unavailable:
            comparisonText = russian ? "Сравнение недоступно: настройки не получены." : "Comparison unavailable: settings could not be loaded."
        }
        items.append(ActionSheetTextItem(title: comparisonText, parseMarkdown: false))
        var rows = settings.map { privacyCheckRows(settings: $0, russian: russian) } ?? []
        if settings == nil {
            items.append(ActionSheetTextItem(title: russian ? "Настройки приватности недоступны. Закройте проверку и повторите при подключении к сети." : "Privacy settings are unavailable. Close this check and retry when connected.", parseMarkdown: false))
        }
        let unavailable = russian ? "Не удалось проверить" : "Could not check"
        let twoStepStatus = twoStepEnabled.map { $0 ? (russian ? "Включена" : "Enabled") : (russian ? "Не включена" : "Not enabled") } ?? unavailable
        rows.append(PrivacyCheckRow(subject: .twoStepVerification, title: russian ? "Двухэтапная защита" : "Two-step verification", audience: twoStepStatus))
        rows.append(PrivacyCheckRow(subject: .activeSessions, title: russian ? "Устройства и сессии" : "Devices and sessions", audience: sessionCount.map { (russian ? "Активных сессий: " : "Active sessions: ") + String($0) } ?? unavailable))
        for row in rows {
            items.append(ActionSheetButtonItem(title: row.title + "\n" + row.audience, color: .accent, action: { [weak controller] in
                isActive = false
                disposable.dispose()
                controller?.dismissAnimated()
                openSetting(row.subject)
            }))
        }
        controller.setItemGroups([ActionSheetItemGroup(items: items), cancelGroup])
    }))
    return controller
}
