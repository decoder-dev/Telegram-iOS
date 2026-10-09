import SwiftSignalKit
import Postbox
import AccountContext
import Foundation
import UIKit
import Display
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData

// The branded themes themselves are built in TelegramPresentationData (`makeBananaGramTheme` in MakePresentationTheme.swift)
// and offered as built-in themes; this file only keeps how choosing one updates the stored theme settings.

func bananaGramAppliedThemeSettings(_ settings: PresentationThemeSettings, reference: PresentationThemeReference, autoNightModeTriggered: Bool) -> PresentationThemeSettings {
    var updated = settings
    if autoNightModeTriggered {
        var automatic = settings.automaticThemeSwitchSetting
        automatic.theme = reference
        updated = settings.withUpdatedAutomaticThemeSwitchSetting(automatic)
    } else {
        updated = settings.withUpdatedTheme(reference)
    }
    var wallpapers = updated.themeSpecificChatWallpapers
    wallpapers[reference.index] = nil
    return updated.withUpdatedThemeSpecificChatWallpapers(wallpapers)
}
