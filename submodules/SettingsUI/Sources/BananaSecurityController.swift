import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

/// BananaGram → Security: switches that stop the steps accounts are stolen through (a login QR passed off as a "vote",
/// the login code typed into a site, a bot or a mini app, the phone number handed to a bot, phishing links, fake
/// "Telegram support"), and the state of the two defences Telegram itself has (two-step verification, sessions).
public enum BananaSecurityStrings {
    private static var ru: Bool {
        return ForkPresentationLanguage.prefersRussianStrings
    }

    static var title: String { ru ? "Безопасность" : "Security" }
    static var hubLabel: String { ru ? "Защита от угона" : "Takeover protection" }
    static var statusHeader: String { ru ? "СОСТОЯНИЕ АККАУНТА" : "ACCOUNT STATUS" }
    static var twoStep: String { ru ? "Двухэтапная проверка" : "Two-Step Verification" }
    static var twoStepOn: String { ru ? "Включена" : "On" }
    static var twoStepOff: String { ru ? "Выключена" : "Off" }
    static var sessions: String { ru ? "Активные сеансы" : "Active Sessions" }
    static var statusFooter: String {
        ru ? "Без облачного пароля один украденный код отдаёт аккаунт целиком, и угонщик ставит свой пароль. Включите его и проверяйте список сеансов: незнакомый сеанс завершайте сразу."
           : "Without a cloud password one stolen code gives the whole account away, and the thief sets a password of their own. Turn it on and check your sessions: end any you do not recognise at once."
    }
    static var protectionsHeader: String { ru ? "ЗАЩИТА" : "PROTECTION" }
    static var blockQrLogin: String { ru ? "Запретить вход по QR-коду" : "Block QR Code Login" }
    static var blockQrLoginText: String {
        ru ? "Сканер «Подключить устройство» не впускает другие устройства. Так угоняют через «голосования», «проверки» и QR в домовых чатах."
           : "The Link Device scanner signs no other device in. Fake \"votes\", \"checks\" and posters in house chats steal accounts this way."
    }
    static var guardLoginCodes: String { ru ? "Не отправлять код входа" : "Never Send the Login Code" }
    static var guardLoginCodesText: String {
        ru ? "Сообщение с кодом, который Telegram прислал за последние 15 минут, никуда не отправится. Код — это ключ от аккаунта."
           : "A message with a code Telegram sent in the last 15 minutes is not sent anywhere. The code is the key to the account."
    }
    static var blockPhoneSharing: String { ru ? "Не отправлять свой номер" : "Never Share My Number" }
    static var blockPhoneSharingText: String {
        ru ? "Боты, мини-приложения и чаты не получат ваш номер по кнопке «Поделиться номером»: с номера начинается вход."
           : "Bots, mini apps and chats do not get your number from a Share My Number button: a login starts with the number."
    }
    static var warnMiniApps: String { ru ? "Предупреждать в мини-приложениях" : "Warn in Mini Apps" }
    static var warnMiniAppsText: String {
        ru ? "При первом открытии каждого мини-приложения: никогда не вводите там код из Telegram или пароль."
           : "The first time each mini app opens: never enter a Telegram code or password there."
    }
    static var confirmExternalLinks: String { ru ? "Подтверждать ссылки на сайты" : "Confirm Website Links" }
    static var confirmExternalLinksText: String {
        ru ? "Перед открытием сайта из сообщения показывается его настоящий адрес."
           : "Before a website opens from a message, its real address is shown."
    }
    static var flagFakeSupport: String { ru ? "Предупреждать о фейковой поддержке" : "Warn About Fake Support" }
    static var flagFakeSupportText: String {
        ru ? "Чат с непроверенным аккаунтом по имени «Telegram», «Безопасность», «Поддержка» и т. п. откроется с предупреждением."
           : "A chat with an unverified account named \"Telegram\", \"Security\", \"Support\" and the like opens with a warning."
    }
    static var protectionsFooter: String {
        ru ? "Telegram никогда не просит код, пароль или номер в чате, на сайте или в боте. Любая такая просьба — попытка угона."
           : "Telegram never asks for a code, a password or your number in a chat, on a site or in a bot. Any such request is a takeover attempt."
    }

    public static var blockedTitle: String { ru ? "Заблокировано" : "Blocked" }
    public static var openSettings: String { ru ? "Настройки безопасности" : "Security Settings" }
    public static var qrLoginBlocked: String {
        ru ? "Вход по QR-коду запрещён в BananaGram → Безопасность. Если кто-то просит отсканировать QR для «голосования» или «проверки», это угон аккаунта."
           : "QR code login is blocked in BananaGram → Security. Anyone asking you to scan a QR to \"vote\" or \"verify\" is stealing the account."
    }
    public static var loginCodeBlocked: String {
        ru ? "В сообщении код входа в Telegram. Его не отправляют никому, даже «поддержке»: с ним заходят в ваш аккаунт."
           : "This message holds your Telegram login code. It is never sent to anyone, not even \"support\": it signs into your account."
    }
    public static var phoneSharingBlocked: String {
        ru ? "Отправка своего номера запрещена в BananaGram → Безопасность. Номер просят, чтобы начать вход в ваш аккаунт."
           : "Sharing your number is blocked in BananaGram → Security. The number is asked for to start a login to your account."
    }
    public static var miniAppWarningTitle: String { ru ? "Мини-приложение" : "Mini App" }
    public static func miniAppWarning(name: String) -> String {
        return ru ? "«\(name)» — стороннее приложение. Никогда не вводите в нём код из Telegram, облачный пароль или номер: так угоняют аккаунты."
                  : "\"\(name)\" is a third-party app. Never enter a Telegram code, your cloud password or your number in it: that is how accounts are stolen."
    }
    public static var fakeSupportTitle: String { ru ? "Осторожно" : "Be Careful" }
    public static func fakeSupportWarning(name: String) -> String {
        return ru ? "«\(name)» — не официальный аккаунт Telegram: у него нет отметки проверки. Настоящая поддержка не пишет первой и не просит коды, пароли и номер."
                  : "\"\(name)\" is not an official Telegram account: it is not verified. Real support never writes first and never asks for codes, passwords or your number."
    }
}

/// A name that pretends to be Telegram staff: the account is a user, not verified, not Telegram's service account, and
/// its name contains one of the words such accounts use.
public func bananaSecurityLooksLikeFakeSupport(peer: EnginePeer) -> Bool {
    guard case let .user(user) = peer, !peer.isVerified, user.id.id._internalGetInt64Value() != 777000 else {
        return false
    }
    let name = "\(user.firstName ?? "") \(user.lastName ?? "") \(user.addressName ?? "")".lowercased()
    let markers = ["telegram", "телеграм", "безопасност", "security", "support", "поддержк", "служба", "модерац", "moderat", "verification", "верификац", "notification", "уведомлен"]
    return markers.contains(where: { name.contains($0) })
}

/// A message text holding a login code: 5 or 6 digits in a row, compared with the codes Telegram's service account sent
/// in the last 15 minutes.
public func bananaSecurityTextContainsLoginCode(_ text: String, codes: Set<String>) -> Bool {
    if codes.isEmpty {
        return false
    }
    let digitsOnly = text.filter { $0.isNumber }
    for code in codes where text.contains(code) || digitsOnly.contains(code) {
        return true
    }
    return false
}

/// The login codes in a service message ("Login code: 12345", "Код для входа в Telegram: 12345").
public func bananaSecurityLoginCodes(inServiceText text: String) -> Set<String> {
    var result = Set<String>()
    var current = ""
    for character in text + " " {
        if character.isASCII && character.isNumber {
            current.append(character)
        } else {
            if current.count == 5 || current.count == 6 {
                result.insert(current)
            }
            current = ""
        }
    }
    return result
}

/// The alert shown instead of something Security forbids, with a way to its settings.
public func bananaSecurityBlockedController(context: AccountContext, text: String, openSettings: (() -> Void)?) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var actions: [TextAlertAction] = []
    if let openSettings {
        actions.append(TextAlertAction(type: .genericAction, title: BananaSecurityStrings.openSettings, action: {
            openSettings()
        }))
    }
    actions.append(TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {}))
    return textAlertController(context: context, title: BananaSecurityStrings.blockedTitle, text: text, actions: actions)
}

private final class BananaSecurityArguments {
    let update: (WritableKeyPath<ForkExtrasSettings, Bool>, Bool) -> Void
    let openTwoStep: () -> Void
    let openSessions: () -> Void

    init(update: @escaping (WritableKeyPath<ForkExtrasSettings, Bool>, Bool) -> Void, openTwoStep: @escaping () -> Void, openSessions: @escaping () -> Void) {
        self.update = update
        self.openTwoStep = openTwoStep
        self.openSessions = openSessions
    }
}

private enum BananaSecuritySection: Int32 {
    case status
    case protections
}

private enum BananaSecurityEntry: ItemListNodeEntry {
    case statusHeader
    case twoStep(Bool?)
    case sessions(Int?)
    case statusFooter
    case protectionsHeader
    case toggle(id: Int32, title: String, text: String, value: Bool, keyPath: WritableKeyPath<ForkExtrasSettings, Bool>)
    case protectionsFooter

    var section: ItemListSectionId {
        switch self {
        case .statusHeader, .twoStep, .sessions, .statusFooter:
            return BananaSecuritySection.status.rawValue
        case .protectionsHeader, .toggle, .protectionsFooter:
            return BananaSecuritySection.protections.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .statusHeader:
            return 0
        case .twoStep:
            return 1
        case .sessions:
            return 2
        case .statusFooter:
            return 3
        case .protectionsHeader:
            return 10
        case let .toggle(id, _, _, _, _):
            return 100 + id
        case .protectionsFooter:
            return 1000
        }
    }

    static func ==(lhs: BananaSecurityEntry, rhs: BananaSecurityEntry) -> Bool {
        switch (lhs, rhs) {
        case (.statusHeader, .statusHeader), (.statusFooter, .statusFooter), (.protectionsHeader, .protectionsHeader), (.protectionsFooter, .protectionsFooter):
            return true
        case let (.twoStep(l), .twoStep(r)):
            return l == r
        case let (.sessions(l), .sessions(r)):
            return l == r
        case let (.toggle(lid, ltitle, ltext, lvalue, _), .toggle(rid, rtitle, rtext, rvalue, _)):
            return lid == rid && ltitle == rtitle && ltext == rtext && lvalue == rvalue
        default:
            return false
        }
    }

    static func <(lhs: BananaSecurityEntry, rhs: BananaSecurityEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BananaSecurityArguments
        switch self {
        case .statusHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: BananaSecurityStrings.statusHeader, sectionId: self.section)
        case let .twoStep(value):
            let label: String
            if let value {
                label = value ? BananaSecurityStrings.twoStepOn : BananaSecurityStrings.twoStepOff
            } else {
                label = ""
            }
            // Off is the one state worth noticing: it is drawn as a red badge.
            let labelStyle: ItemListDisclosureLabelStyle
            if value == false {
                labelStyle = .badge(presentationData.theme.list.itemDestructiveColor)
            } else {
                labelStyle = .text
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: BananaSecurityStrings.twoStep, label: label, labelStyle: labelStyle, sectionId: self.section, style: .blocks, action: {
                arguments.openTwoStep()
            })
        case let .sessions(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: BananaSecurityStrings.sessions, label: count.flatMap { "\($0)" } ?? "", sectionId: self.section, style: .blocks, action: {
                arguments.openSessions()
            })
        case .statusFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(BananaSecurityStrings.statusFooter), sectionId: self.section)
        case .protectionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: BananaSecurityStrings.protectionsHeader, sectionId: self.section)
        case let .toggle(_, title, text, value, keyPath):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: text, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(keyPath, value)
            })
        case .protectionsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(BananaSecurityStrings.protectionsFooter), sectionId: self.section)
        }
    }
}

private func bananaSecurityEntries(settings: ForkExtrasSettings, hasTwoStep: Bool?, sessionsCount: Int?) -> [BananaSecurityEntry] {
    var entries: [BananaSecurityEntry] = []
    entries.append(.statusHeader)
    entries.append(.twoStep(hasTwoStep))
    entries.append(.sessions(sessionsCount))
    entries.append(.statusFooter)
    entries.append(.protectionsHeader)
    entries.append(.toggle(id: 0, title: BananaSecurityStrings.blockQrLogin, text: BananaSecurityStrings.blockQrLoginText, value: settings.securityBlockQrLogin, keyPath: \.securityBlockQrLogin))
    entries.append(.toggle(id: 1, title: BananaSecurityStrings.guardLoginCodes, text: BananaSecurityStrings.guardLoginCodesText, value: settings.securityGuardLoginCodes, keyPath: \.securityGuardLoginCodes))
    entries.append(.toggle(id: 2, title: BananaSecurityStrings.blockPhoneSharing, text: BananaSecurityStrings.blockPhoneSharingText, value: settings.securityBlockPhoneSharing, keyPath: \.securityBlockPhoneSharing))
    entries.append(.toggle(id: 3, title: BananaSecurityStrings.warnMiniApps, text: BananaSecurityStrings.warnMiniAppsText, value: settings.securityWarnMiniApps, keyPath: \.securityWarnMiniApps))
    entries.append(.toggle(id: 4, title: BananaSecurityStrings.confirmExternalLinks, text: BananaSecurityStrings.confirmExternalLinksText, value: settings.securityConfirmExternalLinks, keyPath: \.securityConfirmExternalLinks))
    entries.append(.toggle(id: 5, title: BananaSecurityStrings.flagFakeSupport, text: BananaSecurityStrings.flagFakeSupportText, value: settings.securityFlagFakeSupport, keyPath: \.securityFlagFakeSupport))
    entries.append(.protectionsFooter)
    return entries
}

public func bananaSecurityController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let actionsDisposable = DisposableSet()

    let activeSessionsContext = context.engine.privacy.activeSessions()
    let webSessionsContext = context.engine.privacy.webSessions()

    let hasTwoStep = Promise<Bool?>(nil)
    let twoStepState: Signal<Bool?, NoError> = context.engine.auth.twoStepVerificationConfiguration()
    |> map { configuration -> Bool? in
        if case .set = configuration {
            return true
        } else {
            return false
        }
    }
    hasTwoStep.set(Signal<Bool?, NoError>.single(nil) |> then(twoStepState))

    let arguments = BananaSecurityArguments(
        update: { keyPath, value in
            actionsDisposable.add(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated[keyPath: keyPath] = value
                return updated
            }.start())
        },
        openTwoStep: {
            pushControllerImpl?(privacyAndSecurityController(context: context, activeSessionsContext: activeSessionsContext, webSessionsContext: webSessionsContext))
        },
        openSessions: {
            pushControllerImpl?(recentSessionsController(context: context, activeSessionsContext: activeSessionsContext, webSessionsContext: webSessionsContext, websitesOnly: false))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: context.sharedContext.accountManager),
        hasTwoStep.get(),
        activeSessionsContext.state |> map { state -> Int? in
            return state.sessions.isEmpty ? nil : state.sessions.count
        } |> distinctUntilChanged
    )
    |> map { presentationData, settings, hasTwoStep, sessionsCount -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(BananaSecurityStrings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: bananaSecurityEntries(settings: settings, hasTwoStep: hasTwoStep, sessionsCount: sessionsCount), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
