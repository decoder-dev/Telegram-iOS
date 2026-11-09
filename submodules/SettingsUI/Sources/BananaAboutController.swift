import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import TextFormat
import UndoUI

/// Extras › About BananaGram: the version, the update check against the fork's GitHub Releases (Regram), the settings
/// backup (Regram, Nekogram, exteraGram) and the in-app side of the "reset on next launch" switches in iOS Settings.
private enum BananaAboutStrings {
    private static var ru: Bool {
        return ForkPresentationLanguage.prefersRussianStrings
    }

    static var title: String { ru ? "О BananaGram" : "About BananaGram" }
    static var updatesHeader: String { ru ? "ОБНОВЛЕНИЯ" : "UPDATES" }
    static var checkForUpdates: String { ru ? "Проверить обновления" : "Check for Updates" }
    static var checking: String { ru ? "Проверка…" : "Checking…" }
    static var upToDate: String { ru ? "Установлена последняя версия" : "BananaGram Is Up to Date" }
    static var checkFailed: String { ru ? "Не удалось связаться с GitHub" : "Couldn't Reach GitHub" }
    static func available(_ release: BananaRelease) -> String {
        return ru ? "Доступна версия \(release.version) (\(release.build))" : "Version \(release.version) (\(release.build)) Available"
    }
    static var includePrereleases: String { ru ? "Включая предварительные" : "Include Pre-releases" }
    static var checkAutomatically: String { ru ? "Проверять автоматически" : "Check Automatically" }
    static var updatesFooter: String {
        ru ? "Сведения берутся из GitHub Releases. Автоматическая проверка — не чаще раза в день при запуске. Установить обновление нужно самостоятельно."
           : "Updates come from GitHub Releases. The automatic check runs at most once a day when the app opens. You install updates yourself."
    }
    static func releaseHeader(_ release: BananaRelease) -> String {
        if release.isPrerelease {
            return ru ? "ПРЕДВАРИТЕЛЬНАЯ ВЕРСИЯ \(release.version) (\(release.build))" : "PRE-RELEASE \(release.version) (\(release.build))"
        } else {
            return ru ? "ВЕРСИЯ \(release.version) (\(release.build))" : "VERSION \(release.version) (\(release.build))"
        }
    }
    static var openRelease: String { ru ? "Открыть страницу выпуска" : "Open Release Page" }
    static var releaseFooter: String {
        ru ? "Нажмите на SHA-256, чтобы скопировать, и сравните с суммой скачанного .ipa."
           : "Tap the SHA-256 to copy it, then compare it with the downloaded .ipa's checksum."
    }
    static var noChecksum: String { ru ? "У этого выпуска нет файла SHA256SUMS.txt." : "This release has no SHA256SUMS.txt file." }
    static var backupHeader: String { ru ? "РЕЗЕРВНАЯ КОПИЯ НАСТРОЕК" : "SETTINGS BACKUP" }
    static var exportSettings: String { ru ? "Экспортировать настройки" : "Export Settings" }
    static var importSettings: String { ru ? "Импортировать настройки" : "Import Settings" }
    static var backupFooter: String {
        ru ? "Сохраняет настройки BananaGram в файл JSON. Ключи API и данные, привязанные к этому устройству, в файл не попадают."
           : "Saves BananaGram's settings to a JSON file. API keys and anything tied to this device are left out."
    }
    static var exportFailed: String { ru ? "Не удалось создать файл настроек." : "Couldn't create the settings file." }
    static var notASettingsFile: String { ru ? "Это не файл настроек BananaGram." : "This isn't a BananaGram settings file." }
    static var nothingToChange: String { ru ? "В файле те же настройки, что и сейчас." : "The file has the same settings you have now." }
    static func changeCount(_ count: Int) -> String {
        if ru {
            return "Изменится настроек: \(count). Импортировать?"
        } else {
            return count == 1 ? "1 setting will change. Import it?" : "\(count) settings will change. Import them?"
        }
    }
    static var importAction: String { ru ? "Импортировать" : "Import" }
    static var imported: String { ru ? "Настройки импортированы." : "Settings imported." }
    static var resetHeader: String { ru ? "ДАННЫЕ НА УСТРОЙСТВЕ" : "LOCAL DATA" }
    static var resetCache: String { ru ? "Сбросить кэш при запуске" : "Reset Cache on Next Launch" }
    static var resetDatabase: String { ru ? "Сбросить базу сообщений при запуске" : "Reset Message Database on Next Launch" }
    static var resetFooter: String {
        ru ? "Выполняется при следующем запуске: закройте BananaGram в переключателе приложений. База сообщений загрузится из Telegram, вход сохранится, секретные чаты пропадут. Эти же переключатели есть в Настройках iOS."
           : "Done the next time BananaGram opens: close it in the app switcher. Messages load again from Telegram and you stay signed in, but secret chats are lost. The same switches are in iOS Settings."
    }
    static var resetDatabaseConfirmation: String {
        ru ? "При следующем запуске чаты загрузятся заново из Telegram. Секретные чаты и неотправленные сообщения будут потеряны."
           : "Next time the app opens, chats load again from Telegram. Secret chats and unsent messages will be lost."
    }
    static var resetDatabaseAction: String { ru ? "Сбросить" : "Reset" }
}

private final class BananaAboutArguments {
    let checkForUpdates: () -> Void
    let openRelease: (String) -> Void
    let copySha256: (String) -> Void
    let updateSetting: (WritableKeyPath<ForkExtrasSettings, Bool>, Bool) -> Void
    let exportSettings: () -> Void
    let importSettings: () -> Void
    let updateResetCache: (Bool) -> Void
    let updateResetDatabase: (Bool) -> Void

    init(checkForUpdates: @escaping () -> Void, openRelease: @escaping (String) -> Void, copySha256: @escaping (String) -> Void, updateSetting: @escaping (WritableKeyPath<ForkExtrasSettings, Bool>, Bool) -> Void, exportSettings: @escaping () -> Void, importSettings: @escaping () -> Void, updateResetCache: @escaping (Bool) -> Void, updateResetDatabase: @escaping (Bool) -> Void) {
        self.checkForUpdates = checkForUpdates
        self.openRelease = openRelease
        self.copySha256 = copySha256
        self.updateSetting = updateSetting
        self.exportSettings = exportSettings
        self.importSettings = importSettings
        self.updateResetCache = updateResetCache
        self.updateResetDatabase = updateResetDatabase
    }
}

private enum BananaAboutSection: Int32 {
    case version
    case updates
    case release
    case backup
    case reset
}

private enum BananaAboutEntry: ItemListNodeEntry {
    case version(String)
    case updatesHeader
    case checkForUpdates(isChecking: Bool)
    case updateStatus(String)
    case includePrereleases(Bool)
    case checkAutomatically(Bool)
    case updatesFooter
    case releaseHeader(String)
    case releaseNotes(String)
    case releaseSha256(String?)
    case openRelease(String)
    case releaseFooter
    case backupHeader
    case exportSettings
    case importSettings
    case backupFooter
    case resetHeader
    case resetCache(Bool)
    case resetDatabase(Bool)
    case resetFooter

    var section: ItemListSectionId {
        switch self {
        case .version:
            return BananaAboutSection.version.rawValue
        case .updatesHeader, .checkForUpdates, .updateStatus, .includePrereleases, .checkAutomatically, .updatesFooter:
            return BananaAboutSection.updates.rawValue
        case .releaseHeader, .releaseNotes, .releaseSha256, .openRelease, .releaseFooter:
            return BananaAboutSection.release.rawValue
        case .backupHeader, .exportSettings, .importSettings, .backupFooter:
            return BananaAboutSection.backup.rawValue
        case .resetHeader, .resetCache, .resetDatabase, .resetFooter:
            return BananaAboutSection.reset.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .version: return 2383
        case .updatesHeader: return 2384
        case .checkForUpdates: return 2385
        case .updateStatus: return 2386
        case .includePrereleases: return 2387
        case .checkAutomatically: return 2388
        case .updatesFooter: return 2389
        case .releaseHeader: return 2390
        case .releaseNotes: return 2391
        case .releaseSha256: return 2392
        case .openRelease: return 2393
        case .releaseFooter: return 2394
        case .backupHeader: return 2395
        case .exportSettings: return 2396
        case .importSettings: return 2397
        case .backupFooter: return 2398
        case .resetHeader: return 2399
        case .resetCache: return 2400
        case .resetDatabase: return 2401
        case .resetFooter: return 2402
        }
    }

    static func <(lhs: BananaAboutEntry, rhs: BananaAboutEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BananaAboutArguments
        switch self {
        case let .version(version):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "BananaGram", label: version, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .updatesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: BananaAboutStrings.updatesHeader, sectionId: self.section)
        case let .checkForUpdates(isChecking):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: isChecking ? BananaAboutStrings.checking : BananaAboutStrings.checkForUpdates, kind: isChecking ? .disabled : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.checkForUpdates()
            })
        case let .updateStatus(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .includePrereleases(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.includePrereleases, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting(\.updateCheckIncludesPrereleases, value)
            })
        case let .checkAutomatically(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.checkAutomatically, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSetting(\.updateCheckAutomatically, value)
            })
        case .updatesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(BananaAboutStrings.updatesFooter), sectionId: self.section)
        case let .releaseHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .releaseNotes(text):
            return ItemListMultilineTextItem(presentationData: presentationData, text: text, enabledEntityTypes: [], sectionId: self.section, style: .blocks)
        case let .releaseSha256(hash):
            if let hash {
                return ItemListMultilineTextItem(presentationData: presentationData, text: "SHA-256\n\(hash)", enabledEntityTypes: [], font: .monospace, sectionId: self.section, style: .blocks, action: {
                    arguments.copySha256(hash)
                })
            } else {
                return ItemListMultilineTextItem(presentationData: presentationData, text: BananaAboutStrings.noChecksum, enabledEntityTypes: [], sectionId: self.section, style: .blocks)
            }
        case let .openRelease(url):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.openRelease, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openRelease(url)
            })
        case .releaseFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(BananaAboutStrings.releaseFooter), sectionId: self.section)
        case .backupHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: BananaAboutStrings.backupHeader, sectionId: self.section)
        case .exportSettings:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.exportSettings, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportSettings()
            })
        case .importSettings:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.importSettings, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importSettings()
            })
        case .backupFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(BananaAboutStrings.backupFooter), sectionId: self.section)
        case .resetHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: BananaAboutStrings.resetHeader, sectionId: self.section)
        case let .resetCache(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.resetCache, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateResetCache(value)
            })
        case let .resetDatabase(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: BananaAboutStrings.resetDatabase, value: value, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateResetDatabase(value)
            })
        case .resetFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(BananaAboutStrings.resetFooter), sectionId: self.section)
        }
    }
}

private struct BananaAboutState: Equatable {
    var isChecking: Bool = false
    var updateResult: BananaUpdateCheckResult?
    var resetCache: Bool
    var resetDatabase: Bool
}

/// The changelog part of a release body that CI wrote ("### Changelog" up to the next heading), else the whole body.
private func bananaReleaseNotesExcerpt(_ body: String) -> String {
    var notes = body
    if let start = body.range(of: "### Changelog") {
        notes = String(body[start.upperBound...])
        if let end = notes.range(of: "\n### ") {
            notes = String(notes[..<end.lowerBound])
        }
    }
    notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if notes.count > 800 {
        notes = String(notes.prefix(800)) + "…"
    }
    return notes
}

private func bananaAboutEntries(settings: ForkExtrasSettings, state: BananaAboutState) -> [BananaAboutEntry] {
    var entries: [BananaAboutEntry] = []
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    entries.append(.version("\(bananaCurrentVersion) (\(build))"))

    entries.append(.updatesHeader)
    entries.append(.checkForUpdates(isChecking: state.isChecking))
    switch state.updateResult {
    case .upToDate:
        entries.append(.updateStatus(BananaAboutStrings.upToDate))
    case let .available(release):
        entries.append(.updateStatus(BananaAboutStrings.available(release)))
    case .failed:
        entries.append(.updateStatus(BananaAboutStrings.checkFailed))
    case .none:
        break
    }
    entries.append(.includePrereleases(settings.updateCheckIncludesPrereleases))
    entries.append(.checkAutomatically(settings.updateCheckAutomatically))
    entries.append(.updatesFooter)

    if case let .available(release) = state.updateResult {
        entries.append(.releaseHeader(BananaAboutStrings.releaseHeader(release)))
        let notes = bananaReleaseNotesExcerpt(release.notes)
        if !notes.isEmpty {
            entries.append(.releaseNotes(notes))
        }
        entries.append(.releaseSha256(release.ipaSha256))
        entries.append(.openRelease(release.pageUrl))
        if release.ipaSha256 != nil {
            entries.append(.releaseFooter)
        }
    }

    entries.append(.backupHeader)
    entries.append(.exportSettings)
    entries.append(.importSettings)
    entries.append(.backupFooter)

    entries.append(.resetHeader)
    entries.append(.resetCache(state.resetCache))
    entries.append(.resetDatabase(state.resetDatabase))
    entries.append(.resetFooter)
    return entries
}

/// The document picker keeps its delegate weakly, so the delegate is a shared object; the completion (and the
/// context it holds) is let go as soon as the picker is done.
private final class BananaSettingsFilePicker: NSObject, UIDocumentPickerDelegate {
    static let shared = BananaSettingsFilePicker()
    private var completion: ((URL?) -> Void)?

    func present(context: AccountContext, completion: @escaping (URL?) -> Void) {
        self.completion = completion
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        forkExtrasPresentNativeController(picker, context: context)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion?(urls.first)
        self.completion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion?(nil)
        self.completion = nil
    }
}

func bananaAboutController(context: AccountContext) -> ViewController {
    let initialState = BananaAboutState(resetCache: ForkLocalDataReset.isCacheResetRequested, resetDatabase: ForkLocalDataReset.isDatabaseResetRequested)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((BananaAboutState) -> BananaAboutState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    let actionsDisposable = DisposableSet()
    let checkDisposable = MetaDisposable()
    actionsDisposable.add(checkDisposable)
    var presentControllerImpl: ((ViewController) -> Void)?

    func presentText(_ text: String) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }

    func confirmImport(_ data: Data) {
        // Checking every value against this build's settings decodes them a few hundred times: off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let values = BananaSettingsBackup.importedValues(from: data)
            let current = context.sharedContext.immediateForkExtrasSettings
            let count = values.map { BananaSettingsBackup.changeCount(from: current, to: BananaSettingsBackup.apply($0, to: current)) } ?? 0
            DispatchQueue.main.async {
                guard let values else {
                    presentText(BananaAboutStrings.notASettingsFile)
                    return
                }
                if count == 0 {
                    presentText(BananaAboutStrings.nothingToChange)
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(textAlertController(context: context, title: BananaAboutStrings.importSettings, text: BananaAboutStrings.changeCount(count), actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .defaultAction, title: BananaAboutStrings.importAction, action: {
                        // Through the same shared-data write the Extras switches use, so every runtime projection follows.
                        actionsDisposable.add((updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                            return BananaSettingsBackup.apply(values, to: current)
                        }
                        |> deliverOnMainQueue).start(completed: {
                            presentText(BananaAboutStrings.imported)
                        }))
                    })
                ]))
            }
        }
    }

    let arguments = BananaAboutArguments(
        checkForUpdates: {
            updateState { state in
                var state = state
                state.isChecking = true
                return state
            }
            checkDisposable.set((bananaCheckForUpdates(includePrereleases: context.sharedContext.immediateForkExtrasSettings.updateCheckIncludesPrereleases)
            |> deliverOnMainQueue).start(next: { result in
                updateState { state in
                    var state = state
                    state.isChecking = false
                    state.updateResult = result
                    return state
                }
            }))
        },
        openRelease: { url in
            context.sharedContext.applicationBindings.openUrl(url)
        },
        copySha256: { hash in
            UIPasteboard.general.string = hash
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: presentationData.strings.Conversation_TextCopied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
        },
        updateSetting: { keyPath, value in
            actionsDisposable.add(updateForkExtrasSettingsInteractively(accountManager: context.sharedContext.accountManager) { current in
                var updated = current
                updated[keyPath: keyPath] = value
                return updated
            }.start())
        },
        exportSettings: {
            guard let data = BananaSettingsBackup.exportData(context.sharedContext.immediateForkExtrasSettings) else {
                presentText(BananaAboutStrings.exportFailed)
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("BananaGram Settings \(formatter.string(from: Date())).json")
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                presentText(BananaAboutStrings.exportFailed)
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                let _ = try? FileManager.default.removeItem(at: url)
            }
            forkExtrasPresentNativeController(activity, context: context)
        },
        importSettings: {
            BananaSettingsFilePicker.shared.present(context: context, completion: { url in
                guard let url, let data = try? Data(contentsOf: url) else {
                    return
                }
                confirmImport(data)
            })
        },
        updateResetCache: { value in
            ForkLocalDataReset.isCacheResetRequested = value
            updateState { state in
                var state = state
                state.resetCache = value
                return state
            }
        },
        updateResetDatabase: { value in
            let apply: (Bool) -> Void = { value in
                ForkLocalDataReset.isDatabaseResetRequested = value
                updateState { state in
                    var state = state
                    state.resetDatabase = value
                    return state
                }
            }
            if !value {
                apply(false)
                return
            }
            // Nothing is asked for until the reset is confirmed; Cancel turns the switch back off.
            updateState { state in
                var state = state
                state.resetDatabase = true
                return state
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentControllerImpl?(textAlertController(context: context, title: BananaAboutStrings.resetDatabase, text: BananaAboutStrings.resetDatabaseConfirmation, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                    apply(false)
                }),
                TextAlertAction(type: .destructiveAction, title: BananaAboutStrings.resetDatabaseAction, action: {
                    apply(true)
                })
            ], dismissOnOutsideTap: false))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        forkExtrasSettings(accountManager: context.sharedContext.accountManager),
        statePromise.get()
    )
    |> map { presentationData, settings, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(BananaAboutStrings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: bananaAboutEntries(settings: settings, state: state), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] presented in
        controller?.present(presented, in: .window(.root))
    }
    return controller
}
