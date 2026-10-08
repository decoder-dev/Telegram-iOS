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
print("Theme persistence: 30 combinations; bubble slider: all radii and invalid values; localized Saved Messages: passed")
"""
with tempfile.TemporaryDirectory(prefix='appearance-policy-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixture + functions + tests, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
