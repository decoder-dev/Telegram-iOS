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

/// Preview of a branded theme from Settings ▸ Extras. It previews the built-in reference itself
/// (the same palette and pattern wallpaper Appearance offers), so applying it works offline and
/// stays in sync with later palette changes instead of freezing an encoded copy.
func bananaGramThemePreviewController(context: AccountContext, dark: Bool) -> ViewController? {
    let reference: PresentationThemeReference = .builtin(dark ? .bananaGramGraphite : .bananaGramCream)
    guard let theme = makePresentationTheme(mediaBox: context.sharedContext.accountManager.mediaBox, themeReference: reference) else {
        return nil
    }
    let controller = ThemePreviewController(context: context, previewTheme: theme, source: .settings(reference, nil, false))
    controller.customApply = {
        let autoNightModeTriggered = context.sharedContext.currentPresentationData.with { $0 }.autoNightModeTriggered
        let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return bananaGramAppliedThemeSettings(settings, reference: reference, autoNightModeTriggered: autoNightModeTriggered)
        }).start()
    }
    return controller
}
