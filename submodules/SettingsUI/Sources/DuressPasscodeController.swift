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
import LocalizedPeerData
import PasscodeUI
import PasscodeCore

/// BananaGram → Protection → Duress Passcode (after Vartagram's secret passcodes and b7tg): a second passcode that opens
/// the app as usual after hiding or removing what the owner chose.
enum DuressPasscodeStrings {
    private static var ru: Bool {
        return ForkPresentationLanguage.prefersRussianStrings
    }

    static var title: String { ru ? "Код-пароль под принуждением" : "Duress Passcode" }
    static var on: String { ru ? "Вкл." : "On" }
    static var off: String { ru ? "Выкл." : "Off" }
    static var setPasscode: String { ru ? "Задать код-пароль" : "Set Duress Passcode" }
    static var changePasscode: String { ru ? "Сменить код-пароль" : "Change Duress Passcode" }
    static var removePasscode: String { ru ? "Выключить код-пароль" : "Turn Off Duress Passcode" }
    static var passcodeFooter: String {
        ru ? "Если ввести его на экране блокировки, приложение откроется как обычно, но сначала сделает то, что выбрано ниже. Настоящий код-пароль работает как прежде."
           : "Entered on the lock screen, it opens the app as usual but first does what you choose below. Your real passcode keeps working as before."
    }
    static var needsPasscodeFooter: String {
        ru ? "Сначала включите код-пароль в разделе «Конфиденциальность». Код под принуждением вводят на его экране блокировки."
           : "Turn on Passcode Lock in Privacy and Security first. The duress passcode is entered on its lock screen."
    }
    static var kindChangedFooter: String {
        ru ? "Код-пароль стал другого типа, и код под принуждением теперь не ввести. Задайте его заново."
           : "Your passcode is now a different kind of code, so the duress passcode can't be entered. Set it again."
    }
    static var actionHeader: String { ru ? "ПРИ ВВОДЕ" : "WHEN ENTERED" }
    static var hideSecrets: String { ru ? "Спрятать скрытые аккаунты" : "Hide Hidden Accounts" }
    static var logOut: String { ru ? "Выйти из аккаунтов" : "Log Out of Accounts" }
    static var eraseAll: String { ru ? "Стереть все данные" : "Erase All Data" }
    static var hideSecretsFooter: String {
        ru ? "Скрытые аккаунты и защищённый архив закроются, а 10 нажатий на «Настройки» ничего не покажут до входа с настоящим код-паролем."
           : "Hidden accounts and the locked Archive close, and tapping Settings 10 times shows nothing until you unlock with your real passcode."
    }
    static var logOutFooter: String {
        ru ? "Отмеченные ниже аккаунты выйдут на этом устройстве, скрытые аккаунты закроются. Чаты останутся в облаке, для входа понадобится номер телефона."
           : "The accounts checked below are logged out on this device, and hidden accounts close. Chats stay in the cloud; signing back in needs the phone number."
    }
    static var eraseAllFooter: String {
        ru ? "С устройства удалятся все аккаунты вместе с чатами, медиа и кэшем. Чаты останутся в облаке. Сеансы будут видны на других устройствах, пока вы их не завершите."
           : "Every account is removed from this device with its chats, media and caches. Chats stay in the cloud. Sessions stay listed on your other devices until you end them."
    }
    static var accountsHeader: String { ru ? "ВЫЙТИ ИЗ" : "LOG OUT OF" }
    static var accountsFooter: String {
        ru ? "Скрытый аккаунт виден здесь, только пока он открыт."
           : "A hidden account is listed here only while it is open."
    }
    static var logOutConfirmTitle: String { ru ? "Выход из аккаунтов" : "Log Out of Accounts?" }
    static var logOutConfirmText: String {
        ru ? "При вводе кода под принуждением отмеченные аккаунты выйдут на этом устройстве без предупреждения. Чтобы войти снова, понадобятся их номера телефонов."
           : "When the duress passcode is entered, the accounts you check will be logged out on this device without any warning. Signing back in will need their phone numbers."
    }
    static var eraseConfirmTitle: String { ru ? "Стирание всех данных" : "Erase All Data?" }
    static var eraseConfirmText: String {
        ru ? "При вводе кода под принуждением с устройства без предупреждения удалятся все аккаунты, их чаты, медиа и кэш. Сообщения останутся в облаке, но для входа понадобится номер телефона каждого аккаунта и облачный пароль, если он есть."
           : "When the duress passcode is entered, every account on this device is removed without any warning, with its chats, media and caches. Messages stay in the cloud, but signing back in will need each account's phone number and its cloud password, if it has one."
    }
    static var confirmAction: String { ru ? "Включить" : "Turn On" }
    static var sameKind: String {
        ru ? "Код под принуждением должен быть того же типа, что и ваш код-пароль."
           : "The duress passcode must be the same kind of code as your passcode."
    }
    static var sameAsPasscode: String {
        ru ? "Этот код совпадает с вашим код-паролем. Выберите другой."
           : "This is your passcode. Choose a different one."
    }
    static var sameAsArchivePassword: String {
        ru ? "Этот код уже используется как пароль архива. Выберите другой."
           : "This code is already an Archive password. Choose a different one."
    }
    static func tryAgain(seconds: Int) -> String {
        return ru ? "Слишком много попыток. Повторите через \(seconds) с." : "Too many attempts. Try again in \(seconds) s."
    }
}

private final class DuressPasscodeArguments {
    let setPasscode: () -> Void
    let removePasscode: () -> Void
    let selectAction: (DuressPasscodeAction) -> Void
    let toggleAccount: (Int64) -> Void

    init(setPasscode: @escaping () -> Void, removePasscode: @escaping () -> Void, selectAction: @escaping (DuressPasscodeAction) -> Void, toggleAccount: @escaping (Int64) -> Void) {
        self.setPasscode = setPasscode
        self.removePasscode = removePasscode
        self.selectAction = selectAction
        self.toggleAccount = toggleAccount
    }
}

private enum DuressPasscodeSection: Int32 {
    case passcode
    case action
    case accounts
}

private enum DuressPasscodeEntry: ItemListNodeEntry {
    case setPasscode(title: String, enabled: Bool)
    case removePasscode
    case passcodeFooter(String)
    case actionHeader
    case action(DuressPasscodeAction, title: String, selected: Bool)
    case actionFooter(String)
    case accountsHeader
    case account(index: Int, id: Int64, title: String, checked: Bool)
    case accountsFooter

    var section: ItemListSectionId {
        switch self {
        case .setPasscode, .removePasscode, .passcodeFooter:
            return DuressPasscodeSection.passcode.rawValue
        case .actionHeader, .action, .actionFooter:
            return DuressPasscodeSection.action.rawValue
        case .accountsHeader, .account, .accountsFooter:
            return DuressPasscodeSection.accounts.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .setPasscode:
            return 0
        case .removePasscode:
            return 1
        case .passcodeFooter:
            return 2
        case .actionHeader:
            return 10
        case let .action(action, _, _):
            return 11 + action.rawValue
        case .actionFooter:
            return 20
        case .accountsHeader:
            return 30
        case let .account(index, _, _, _):
            return 31 + Int32(index)
        case .accountsFooter:
            return 1000
        }
    }

    static func <(lhs: DuressPasscodeEntry, rhs: DuressPasscodeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DuressPasscodeArguments
        switch self {
        case let .setPasscode(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.setPasscode()
            })
        case .removePasscode:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: DuressPasscodeStrings.removePasscode, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.removePasscode()
            })
        case let .passcodeFooter(text), let .actionFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .actionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DuressPasscodeStrings.actionHeader, sectionId: self.section)
        case let .action(action, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectAction(action)
            })
        case .accountsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: DuressPasscodeStrings.accountsHeader, sectionId: self.section)
        case let .account(_, id, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.toggleAccount(id)
            })
        case .accountsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(DuressPasscodeStrings.accountsFooter), sectionId: self.section)
        }
    }
}

private func duressPasscodeEntries(settings: ForkExtrasSettings, passcodeKind: PostboxAccessChallengeData.Kind?, duressKind: PostboxAccessChallengeData.Kind?, accounts: [(id: Int64, title: String)]) -> [DuressPasscodeEntry] {
    var entries: [DuressPasscodeEntry] = []
    entries.append(.setPasscode(title: duressKind == nil ? DuressPasscodeStrings.setPasscode : DuressPasscodeStrings.changePasscode, enabled: passcodeKind != nil))
    if duressKind != nil {
        entries.append(.removePasscode)
    }
    if passcodeKind == nil {
        entries.append(.passcodeFooter(DuressPasscodeStrings.needsPasscodeFooter))
    } else if let duressKind, duressKind != passcodeKind {
        entries.append(.passcodeFooter(DuressPasscodeStrings.kindChangedFooter))
    } else {
        entries.append(.passcodeFooter(DuressPasscodeStrings.passcodeFooter))
    }

    let action = DuressPasscodeAction(rawValue: settings.duressPasscodeAction) ?? .hideSecrets
    entries.append(.actionHeader)
    entries.append(.action(.hideSecrets, title: DuressPasscodeStrings.hideSecrets, selected: action == .hideSecrets))
    entries.append(.action(.logOut, title: DuressPasscodeStrings.logOut, selected: action == .logOut))
    entries.append(.action(.eraseAll, title: DuressPasscodeStrings.eraseAll, selected: action == .eraseAll))
    switch action {
    case .hideSecrets:
        entries.append(.actionFooter(DuressPasscodeStrings.hideSecretsFooter))
    case .logOut:
        entries.append(.actionFooter(DuressPasscodeStrings.logOutFooter))
    case .eraseAll:
        entries.append(.actionFooter(DuressPasscodeStrings.eraseAllFooter))
    }

    if action == .logOut {
        entries.append(.accountsHeader)
        for (index, account) in accounts.enumerated() {
            entries.append(.account(index: index, id: account.id, title: account.title, checked: settings.duressLogOutAccountIds.contains(account.id)))
        }
        entries.append(.accountsFooter)
    }
    return entries
}

public func duressPasscodeController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var popToSelfImpl: (() -> Void)?
    let actionsDisposable = DisposableSet()
    let accountManager = context.sharedContext.accountManager

    // The Keychain is read again after every change made here.
    let duressKind = ValuePromise<PostboxAccessChallengeData.Kind?>(DuressPasscodeKeychain.kind(), ignoreRepeated: true)

    let updateSettings: (@escaping (ForkExtrasSettings) -> ForkExtrasSettings) -> Void = { f in
        actionsDisposable.add(updateForkExtrasSettingsInteractively(accountManager: accountManager, f).start())
    }
    let presentAlert: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.presentGlobalController(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
    }
    let fail: (String) -> Void = { text in
        popToSelfImpl?()
        presentAlert(text)
    }

    // Last step: the real passcode confirms the change (and clears the failed attempt the check below recorded), then
    // the code is compared with every Archive password and saved.
    let confirmAndStore: (String, PostboxAccessChallengeData.Kind) -> Void = { code, kind in
        let controller = settingsPasscodeSessionController(context: context, completion: { result in
            guard case let .success(session) = result else {
                popToSelfImpl?()
                return
            }
            session.invalidate()
            let _ = (context.sharedContext.activeAccountsWithInfo
            |> take(1)
            |> deliverOnMainQueue).start(next: { _, accounts in
                let peerIds = accounts.map { $0.account.peerId }
                DispatchQueue.global(qos: .userInitiated).async {
                    let isArchivePassword = peerIds.contains(where: { ArchivePasswordKeychain.matchesPassword(code, peerId: $0) })
                    let stored = !isArchivePassword && DuressPasscodeKeychain.store(code, kind: kind)
                    DispatchQueue.main.async {
                        duressKind.set(DuressPasscodeKeychain.kind())
                        if isArchivePassword {
                            fail(DuressPasscodeStrings.sameAsArchivePassword)
                        } else if !stored {
                            fail(context.sharedContext.currentPresentationData.with { $0 }.strings.PasscodeSettings_UpdateError)
                        } else {
                            popToSelfImpl?()
                        }
                    }
                }
            })
        })
        if let controller {
            pushControllerImpl?(controller)
        }
    }

    let arguments = DuressPasscodeArguments(
        setPasscode: {
            let _ = (accountManager.accessChallengeData()
            |> take(1)
            |> deliverOnMainQueue).start(next: { view in
                guard let kind = view.data.passcodeKind else {
                    presentAlert(DuressPasscodeStrings.needsPasscodeFooter)
                    return
                }
                let fieldType: PasscodeEntryFieldType
                switch kind {
                case .digits4:
                    fieldType = .digits4
                case .digits6:
                    fieldType = .digits6
                case .alphanumeric:
                    fieldType = .alphanumeric
                }
                let setupController = PasscodeSetupController(context: context, mode: .setup(change: false, fieldType), allowFourDigitPasscode: kind == .digits4)
                setupController.title = DuressPasscodeStrings.title
                var submitted = false
                setupController.complete = { code, numerical in
                    if submitted {
                        return
                    }
                    let enteredKind: PostboxAccessChallengeData.Kind = numerical ? (code.count == 6 ? .digits6 : .digits4) : .alphanumeric
                    guard enteredKind == kind else {
                        fail(DuressPasscodeStrings.sameKind)
                        return
                    }
                    submitted = true
                    // The real passcode is checked the throttled way the lock screen checks it, so this screen can't be
                    // used to guess it faster.
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = Result { try PasscodeCredentialStore.shared.verify(code, scope: .settings) }
                        DispatchQueue.main.async {
                            switch result {
                            case let .success(session):
                                session.invalidate()
                                fail(DuressPasscodeStrings.sameAsPasscode)
                            case let .failure(error):
                                switch error as? PasscodeError {
                                case .invalidCode?:
                                    confirmAndStore(code, kind)
                                case let .cooldown(seconds)?:
                                    fail(DuressPasscodeStrings.tryAgain(seconds: seconds))
                                default:
                                    fail(context.sharedContext.currentPresentationData.with { $0 }.strings.PasscodeSettings_UpdateError)
                                }
                            }
                        }
                    }
                }
                pushControllerImpl?(setupController)
            })
        },
        removePasscode: {
            DuressPasscodeKeychain.clear()
            duressKind.set(DuressPasscodeKeychain.kind())
        },
        selectAction: { action in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            switch action {
            case .hideSecrets:
                updateSettings { current in
                    var updated = current
                    updated.duressPasscodeAction = action.rawValue
                    return updated
                }
            case .logOut, .eraseAll:
                let _ = (forkExtrasSettings(accountManager: accountManager)
                |> take(1)
                |> deliverOnMainQueue).start(next: { settings in
                    if settings.duressPasscodeAction == action.rawValue {
                        return
                    }
                    let isLogOut = action == .logOut
                    let currentAccountId = context.account.id.int64
                    let alert = textAlertController(context: context, title: isLogOut ? DuressPasscodeStrings.logOutConfirmTitle : DuressPasscodeStrings.eraseConfirmTitle, text: isLogOut ? DuressPasscodeStrings.logOutConfirmText : DuressPasscodeStrings.eraseConfirmText, actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: DuressPasscodeStrings.confirmAction, action: {
                            updateSettings { current in
                                var updated = current
                                updated.duressPasscodeAction = action.rawValue
                                // Start with the account this was set up from rather than with nothing checked.
                                if isLogOut && updated.duressLogOutAccountIds.isEmpty {
                                    updated.duressLogOutAccountIds = [currentAccountId]
                                }
                                return updated
                            }
                        })
                    ])
                    context.sharedContext.presentGlobalController(alert, nil)
                })
            }
        },
        toggleAccount: { accountId in
            updateSettings { current in
                var updated = current
                if let index = updated.duressLogOutAccountIds.firstIndex(of: accountId) {
                    updated.duressLogOutAccountIds.remove(at: index)
                } else {
                    updated.duressLogOutAccountIds.append(accountId)
                }
                return updated
            }
        }
    )

    // Hidden accounts stay out of the list unless they are open, as everywhere else.
    let accounts = combineLatest(context.sharedContext.activeAccountsWithInfo, HiddenAccountsSession.shared.stateSignal)
    |> map { accountsWithInfo, hiddenState -> [(id: Int64, title: String)] in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        return accountsWithInfo.accounts.compactMap { info -> (id: Int64, title: String)? in
            let id = info.account.id.int64
            guard hiddenState.listing(accountId: id) == .normal else {
                return nil
            }
            return (id, info.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder))
        }
    }

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: accountManager),
        accountManager.accessChallengeData() |> map { $0.data.passcodeKind } |> distinctUntilChanged,
        duressKind.get(),
        accounts
    )
    |> map { presentationData, settings, passcodeKind, duressKind, accounts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(DuressPasscodeStrings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: duressPasscodeEntries(settings: settings, passcodeKind: passcodeKind, duressKind: duressKind, accounts: accounts), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    popToSelfImpl = { [weak controller] in
        guard let controller, let navigationController = controller.navigationController as? NavigationController else {
            return
        }
        let _ = navigationController.popToViewController(controller, animated: true)
    }
    return controller
}
