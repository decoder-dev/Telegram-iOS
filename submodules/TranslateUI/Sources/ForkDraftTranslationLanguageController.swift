import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

private final class ForkDraftTranslationLanguageArguments {
    let select: (String) -> Void

    init(select: @escaping (String) -> Void) {
        self.select = select
    }
}

private enum ForkDraftTranslationLanguageEntry: ItemListNodeEntry {
    case language(index: Int32, code: String, title: String, subtitle: String, checked: Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .language(index, _, _, _, _):
            return index
        }
    }

    static func <(lhs: ForkDraftTranslationLanguageEntry, rhs: ForkDraftTranslationLanguageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ForkDraftTranslationLanguageArguments
        switch self {
        case let .language(_, code, title, subtitle, checked):
            return LocalizationListItem(presentationData: presentationData, systemStyle: .glass, id: code, title: title, subtitle: subtitle, checked: checked, activity: false, loading: false, editing: LocalizationListItemEditing(editable: false, editing: false, revealed: false, reorderable: false), sectionId: self.section, alwaysPlain: false, action: {
                arguments.select(code)
            }, setItemWithRevealedOptions: nil, removeItem: nil)
        }
    }
}

/// The languages a draft can be translated into: the chat's current one first, then the popular ones, then the rest
/// in alphabetical order. Each row names the language in the app's language and in its own.
private func forkDraftTranslationLanguageEntries(strings: PresentationStrings, selectedLanguage: String?) -> [ForkDraftTranslationLanguageEntry] {
    let appLocale = Locale(identifier: strings.baseLanguageCode)
    func title(_ code: String) -> String {
        return appLocale.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    var codes: [String] = []
    if let selectedLanguage, supportedTranslationLanguages.contains(selectedLanguage) {
        codes.append(selectedLanguage)
    }
    for code in popularTranslationLanguages where !codes.contains(code) {
        codes.append(code)
    }
    let rest = supportedTranslationLanguages.filter { !codes.contains($0) }.sorted { title($0).localizedCompare(title($1)) == .orderedAscending }
    codes.append(contentsOf: rest)

    return codes.enumerated().map { index, code -> ForkDraftTranslationLanguageEntry in
        let subtitle = Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code
        return .language(index: Int32(index), code: code, title: title(code), subtitle: subtitle, checked: code == selectedLanguage)
    }
}

/// Translate Before Sending: picks the language a chat's draft is translated into.
public func forkDraftTranslationLanguageController(context: AccountContext, selectedLanguage: String?, completion: @escaping (String) -> Void) -> ViewController {
    var dismissImpl: (() -> Void)?
    let arguments = ForkDraftTranslationLanguageArguments(select: { code in
        dismissImpl?()
        completion(code)
    })
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(presentationData.strings.Translate_ChangeLanguage),
            leftNavigationButton: ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                dismissImpl?()
            }),
            rightNavigationButton: nil,
            backNavigationButton: nil
        )
        let entries = forkDraftTranslationLanguageEntries(strings: presentationData.strings, selectedLanguage: selectedLanguage)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    dismissImpl = { [weak controller] in
        controller?.dismiss(animated: true)
    }
    return controller
}
