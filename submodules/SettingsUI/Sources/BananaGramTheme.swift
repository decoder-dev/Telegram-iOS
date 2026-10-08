import SwiftSignalKit
import Postbox
import AccountContext
import Foundation
import UIKit
import Display
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData

func makeBananaGramTheme(dark: Bool) -> PresentationTheme {
    let background = UIColor(rgb: dark ? 0x181B20 : 0xF6F3EB)
    let surface = UIColor(rgb: dark ? 0x23272E : 0xFFFCF5)
    let foreground = UIColor(rgb: dark ? 0xF3F0E7 : 0x292D32)
    let secondary = UIColor(rgb: dark ? 0xB8BDC5 : 0x656970)
    let accent = UIColor(rgb: dark ? 0xF4D66F : 0x805600)
    let separator = UIColor(rgb: dark ? 0x363C45 : 0xDDD8CD)
    let title = dark ? "BananaGram Graphite" : "BananaGram Cream"
    let base = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    // Build the preset directly, preserving its explicit bubble palette.
    let theme = customizePresentationTheme(base, editing: false, title: title, accentColor: accent, outgoingAccentColor: nil, backgroundColors: [dark ? 0x181B20 : 0xF6F3EB], bubbleColors: [dark ? 0x49412B : 0xF6E5B5], animateBubbleColors: false)
    let list = theme.list.withUpdated(blocksBackgroundColor: background, modalBlocksBackgroundColor: background, plainBackgroundColor: surface, modalPlainBackgroundColor: surface, itemPrimaryTextColor: foreground, itemSecondaryTextColor: secondary, itemAccentColor: accent, itemBlocksBackgroundColor: surface, itemModalBlocksBackgroundColor: surface, itemBlocksSeparatorColor: separator, itemPlainSeparatorColor: separator, sectionHeaderTextColor: secondary, freeTextColor: secondary)
    let root = theme.rootController.withUpdated(
        tabBar: theme.rootController.tabBar.withUpdated(backgroundColor: surface, separatorColor: separator, selectedIconColor: accent, selectedTextColor: accent),
        navigationBar: theme.rootController.navigationBar.withUpdated(buttonColor: accent, primaryTextColor: foreground, secondaryTextColor: secondary, accentTextColor: accent, blurredBackgroundColor: surface.withAlphaComponent(0.95), opaqueBackgroundColor: surface, separatorColor: separator),
        navigationSearchBar: theme.rootController.navigationSearchBar.withUpdated(backgroundColor: surface, accentColor: accent, inputFillColor: background, inputTextColor: foreground, inputPlaceholderTextColor: secondary, inputIconColor: secondary, separatorColor: separator)
    )
    let chats = theme.chatList.withUpdated(backgroundColor: surface, itemSeparatorColor: separator, itemBackgroundColor: surface, pinnedItemBackgroundColor: background, titleColor: foreground, dateTextColor: secondary, authorNameColor: foreground, messageTextColor: secondary, messageHighlightedTextColor: foreground, sectionHeaderFillColor: background, sectionHeaderTextColor: secondary)
    return PresentationTheme(name: .custom(title), index: theme.index, referenceTheme: theme.referenceTheme, overallDarkAppearance: dark, intro: theme.intro, passcode: theme.passcode, rootController: root, list: list, chatList: chats, chat: theme.chat, actionSheet: theme.actionSheet.withUpdated(opaqueItemBackgroundColor: surface, itemBackgroundColor: surface, opaqueItemSeparatorColor: separator, standardActionTextColor: accent, primaryTextColor: foreground, secondaryTextColor: secondary), contextMenu: theme.contextMenu.withUpdated(backgroundColor: surface, itemSeparatorColor: separator, sectionSeparatorColor: background, itemBackgroundColor: surface, primaryColor: foreground, secondaryColor: secondary), inAppNotification: theme.inAppNotification, chart: theme.chart)
}

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

func bananaGramThemePreviewController(context: AccountContext, dark: Bool) -> ViewController? {
    let theme = makeBananaGramTheme(dark: dark)
    guard let encoded = encodePresentationTheme(theme), let data = encoded.data(using: .utf8) else { return nil }
    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
    context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
    let reference = PresentationThemeReference.local(PresentationLocalTheme(title: theme.name.string, resource: resource, resolvedWallpaper: nil))
    let controller = ThemePreviewController(context: context, previewTheme: theme, source: .settings(reference, nil, false))
    // Bundled presets are local themes: applying one must also work offline.
    controller.customApply = {
        let autoNightModeTriggered = context.sharedContext.currentPresentationData.with { $0 }.autoNightModeTriggered
        let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
            return bananaGramAppliedThemeSettings(settings, reference: reference, autoNightModeTriggered: autoNightModeTriggered)
        }).start()
    }
    return controller
}
