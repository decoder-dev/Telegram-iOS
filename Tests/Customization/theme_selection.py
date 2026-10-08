"""Run the production theme policy, radius mapping and localized title on macOS."""
import pathlib
import subprocess
import tempfile
root = pathlib.Path(__file__).resolve().parents[2]
def function(path, name):
    source = (root / path).read_text(encoding='utf-8')
    start = source.index(name)
    return source[start:source.index('\n}', start) + 2]
source = 'submodules/TelegramPresentationData/Sources/PresentationData.swift'
radius = 'submodules/SettingsUI/Sources/Text Size/TextSizeSelectionItem.swift'
functions = '\n'.join([function(source, 'public func forkNormalizedThemeSettings('),
                        function(source, 'public func forkSavedMessagesMenuTitle('),
                        function(radius, 'func bubbleRadiusSliderValue('),
                        function(radius, 'func bubbleRadiusFromSliderValue(')])
title_functions = ['forkEditHistoryMenuTitle', 'forkUseRecentEmojiInReactionsTitle', 'forkUseRecentEmojiInReactionsInfo', 'forkExtrasSettingsTitle', 'forkDeveloperModeSettingsTitle', 'forkCustomizationSettingsTitle']
functions += '\n' + '\n'.join(function(source, 'public func ' + name + '(') for name in title_functions)
fixture = r"""
import Foundation
public struct PresentationThemeSettings: Equatable {
    var theme: String
    var automaticPolicy: String
    var darkTheme: String
    var wallpaper: String
}
public struct PresentationStrings {
    struct Component { var languageCode: String }
    var primaryComponent: Component
}
"""
tests = r"""
for theme in ["day", "night", "classic", "tinted", "local:BananaGram", "cloud:custom"] {
    for policy in ["disabled", "system", "scheduled", "brightness", "force"] {
        let saved = PresentationThemeSettings(theme: theme, automaticPolicy: policy, darkTheme: "custom-dark", wallpaper: "custom-wallpaper")
        precondition(forkNormalizedThemeSettings(saved) == saved, "User appearance overwritten")
    }
}
for radius in 4...30 {
    precondition(bubbleRadiusFromSliderValue(bubbleRadiusSliderValue(radius)) == radius, "Odd radius lost")
}
precondition(bubbleRadiusSliderValue(Int.min) == 0)
precondition(bubbleRadiusSliderValue(Int.max) == 26)
for value in [CGFloat.nan, .infinity, -.infinity, -100, 100] {
    precondition((4...30).contains(bubbleRadiusFromSliderValue(value)))
}
for code in ["ru", "ru-RU", "RU", "uk", "be"] {
    let strings = PresentationStrings(primaryComponent: .init(languageCode: code))
    precondition(forkSavedMessagesMenuTitle(strings) == "В Избранное")
}
for code in ["en", "en-US", "de", ""] {
    let strings = PresentationStrings(primaryComponent: .init(languageCode: code))
    precondition(forkSavedMessagesMenuTitle(strings) == "Save to Saved Messages")
}
for title in [forkEditHistoryMenuTitle, forkUseRecentEmojiInReactionsTitle, forkUseRecentEmojiInReactionsInfo, forkExtrasSettingsTitle, forkDeveloperModeSettingsTitle, forkCustomizationSettingsTitle] {
    let russian = title(PresentationStrings(primaryComponent: .init(languageCode: "ru")))
    let english = title(PresentationStrings(primaryComponent: .init(languageCode: "en")))
    precondition(russian != english)
    for code in ["ru-RU", "RU", "uk-UA", "be-BY"] {
        precondition(title(PresentationStrings(primaryComponent: .init(languageCode: code))) == russian)
    }
    precondition(title(PresentationStrings(primaryComponent: .init(languageCode: "en-US"))) == english)
}
print("Theme persistence: 30 combinations; bubble slider: all radii and invalid values; localized Saved Messages: passed")
"""
navigation_source = (root / 'submodules/TelegramUI/Sources/TelegramRootController.swift').read_text(encoding='utf-8')
start = navigation_source.index('    public func openContacts()')
method = navigation_source[start:navigation_source.index('\n    }', start) + 6]
navigation = r"""
class Controller {}
class ChatController: Controller {}
class ContactsController: Controller {
    var switchToChatsController: (() -> Void)?
    init(context: Int) {}
}
class TabController: Controller {
    var controllers: [Controller] = [ChatController()]
    var selectedIndex = 0
}
final class Root {
    let context = 0
    var rootTabController: TabController? = TabController()
    var viewControllers: [Controller] = []
    init() { viewControllers = [rootTabController!] }
    func popToRoot(animated: Bool) { viewControllers = Array(viewControllers.prefix(1)) }
    func pushViewController(_ c: Controller, animated: Bool) { viewControllers.append(c) }
    func setViewControllers(_ controllers: [Controller], animated: Bool) { viewControllers = controllers }
    func openChatsController(activateSearch: Bool) { rootTabController?.selectedIndex = 0 }
__OPEN_CONTACTS__
}
let rootNavigation = Root()
rootNavigation.openContacts()
precondition(rootNavigation.viewControllers.count == 2)
let contactsScreen = rootNavigation.viewControllers[1] as! ContactsController
let conversation = ChatController()
rootNavigation.pushViewController(conversation, animated: false)
contactsScreen.switchToChatsController?()
precondition(rootNavigation.viewControllers.count == 2)
precondition(rootNavigation.viewControllers.last === conversation, "Purposeful action must retain the open chat")
precondition(!rootNavigation.viewControllers.contains { $0 === contactsScreen }, "Standalone Contacts left in navigation stack")
contactsScreen.switchToChatsController?()
precondition(rootNavigation.viewControllers.last === conversation)
let visibleContacts = Root()
visibleContacts.rootTabController!.controllers.append(ContactsController(context: 0))
visibleContacts.openContacts()
precondition(visibleContacts.viewControllers.count == 1 && visibleContacts.rootTabController!.selectedIndex == 1)
print("Hidden Contacts: remove intermediate screen, retain conversation, repeat callback and normal tab route passed")
""".replace('__OPEN_CONTACTS__', method)

# Execute the same local preset reducer used by the Apply callback. Deliberately
# provide no network/account upload API: presets must work with only local state.
preset_function = function('submodules/SettingsUI/Sources/BananaGramTheme.swift', 'func bananaGramAppliedThemeSettings(')
preset_tests = r"""
import Foundation
struct PresentationThemeReference: Equatable { var index: Int64 }
struct AutomaticSetting: Equatable { var theme: PresentationThemeReference; var policy: String }
struct PresentationThemeSettings: Equatable {
    var theme: PresentationThemeReference
    var automaticThemeSwitchSetting: AutomaticSetting
    var themeSpecificChatWallpapers: [Int64: String]
    var unrelated: String
    func withUpdatedTheme(_ theme: PresentationThemeReference) -> Self { var s = self; s.theme = theme; return s }
    func withUpdatedAutomaticThemeSwitchSetting(_ value: AutomaticSetting) -> Self { var s = self; s.automaticThemeSwitchSetting = value; return s }
    func withUpdatedThemeSpecificChatWallpapers(_ value: [Int64: String]) -> Self { var s = self; s.themeSpecificChatWallpapers = value; return s }
}
__PRESET_FUNCTION__
for policy in ["disabled", "system", "scheduled", "brightness"] {
    for activeNight in [false, true] {
        for preset in [Int64(100), Int64(101)] {
            let original = PresentationThemeSettings(theme: .init(index: 1), automaticThemeSwitchSetting: .init(theme: .init(index: 2), policy: policy), themeSpecificChatWallpapers: [1: "day", 2: "night", preset: "old"], unrelated: "font/radius/motion")
            let reference = PresentationThemeReference(index: preset)
            let result = bananaGramAppliedThemeSettings(original, reference: reference, autoNightModeTriggered: activeNight)
            precondition(result.theme.index == (activeNight ? 1 : preset))
            precondition(result.automaticThemeSwitchSetting.theme.index == (activeNight ? preset : 2))
            precondition(result.automaticThemeSwitchSetting.policy == policy)
            precondition(result.themeSpecificChatWallpapers == [1: "day", 2: "night"])
            precondition(result.unrelated == original.unrelated)
            precondition(bananaGramAppliedThemeSettings(result, reference: reference, autoNightModeTriggered: activeNight) == result)
        }
    }
}
print("Local preset application: active day/night slots, wallpaper isolation, policy preservation and repeat Apply passed")
""".replace('__PRESET_FUNCTION__', preset_function)
controller_source = (root / 'submodules/ChatListUI/Sources/ChatListController.swift').read_text(encoding='utf-8')
start = controller_source.index('                        for i in (0 ..< index')
end = controller_source.index('\n                    }', start)
loop = controller_source[start:end]
folder_tests = r"""
import Foundation
struct Tab { var id: Int }
func fallback(old: [Int], remaining: [Int], selected: Int) -> Int? {
    let tabContainerData = (old.map { Tab(id: $0) }, false)
    let resolvedItems = remaining.map { Tab(id: $0) }
    guard let index = old.firstIndex(of: selected) else { return nil }
    var selectedEntryId = selected
    var found = false
__FOLDER_LOOP__
    return found ? selectedEntryId : nil
}
precondition(fallback(old: [1, 2], remaining: [2], selected: 1) == nil)
precondition(fallback(old: [0, 1, 2], remaining: [0, 1], selected: 2) == 1)
precondition(fallback(old: [0, 1, 2], remaining: [0], selected: 2) == 0)
precondition(fallback(old: [0], remaining: [], selected: 0) == nil)
print("Removed folder fallback: first tab, immediate predecessor, multiple removals passed")
""".replace('__FOLDER_LOOP__', loop)

with tempfile.TemporaryDirectory(prefix='appearance-policy-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixture + functions + tests + navigation, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
    for name, code in [('preset', preset_tests), ('folder', folder_tests)]:
        path = pathlib.Path(tmp) / (name + '.swift')
        path.write_text(code, encoding='utf-8')
        subprocess.run(['swift', str(path)], check=True)
