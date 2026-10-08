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
with tempfile.TemporaryDirectory(prefix='appearance-policy-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixture + functions + tests + navigation, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
