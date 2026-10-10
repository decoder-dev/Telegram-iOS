import Foundation
import UIKit
import Display
import Postbox
import TelegramUIPreferences
import TelegramCore

public func makeDefaultPresentationTheme(reference: PresentationBuiltinThemeReference, extendingThemeReference: PresentationThemeReference? = nil, serviceBackgroundColor: UIColor?, preview: Bool = false) -> PresentationTheme {
    let theme: PresentationTheme
    switch reference {
        case .dayClassic:
            theme = makeDefaultDayPresentationTheme(extendingThemeReference: extendingThemeReference, serviceBackgroundColor: serviceBackgroundColor, day: false, preview: preview)
        case .day:
            theme = makeDefaultDayPresentationTheme(extendingThemeReference: extendingThemeReference, serviceBackgroundColor: serviceBackgroundColor, day: true, preview: preview)
        case .night:
            theme = makeDefaultDarkPresentationTheme(extendingThemeReference: extendingThemeReference, preview: preview)
        case .nightAccent:
            theme = makeDefaultDarkTintedPresentationTheme(extendingThemeReference: extendingThemeReference, preview: preview)
        case .bananaGramCream:
            theme = makeBananaGramTheme(dark: false)
        case .bananaGramGraphite:
            theme = makeBananaGramTheme(dark: true)
    }
    return theme
}

/// BananaGram's two branded themes, built on the stock Day / Night themes so every screen the stock themes cover stays
/// covered. Cream is a warm paper surface with a dark-gold accent; Graphite is a warm charcoal surface with a banana-yellow
/// accent. Accent foregrounds are chosen for contrast (white on dark gold, near-black on yellow), and the chat screen
/// (bubbles, input bar, scroll-down button, wallpaper) uses the same palette as the lists so the app reads as one theme.
private func makeBananaGramTheme(dark: Bool) -> PresentationTheme {
    let background = UIColor(rgb: dark ? 0x1A1916 : 0xF6F3EB)
    let surface = UIColor(rgb: dark ? 0x252320 : 0xFFFCF5)
    let raisedSurface = UIColor(rgb: dark ? 0x2E2C28 : 0xFFFEFA)
    let foreground = UIColor(rgb: dark ? 0xF3F0E7 : 0x292D32)
    let secondary = UIColor(rgb: dark ? 0xBAB5A9 : 0x65686E)
    let accent = UIColor(rgb: dark ? 0xF4D66F : 0x805600)
    // Text and glyphs drawn on an accent fill: white on dark gold, near-black on banana yellow.
    let onAccent = UIColor(rgb: dark ? 0x1B1A16 : 0xFFFFFF)
    let separator = UIColor(rgb: dark ? 0x3B3833 : 0xDDD8CD)
    let title = dark ? "BananaGram Graphite" : "BananaGram Cream"
    
    // Outgoing bubbles: soft banana cream with dark-gold details by day, deep olive gold with white text by night.
    let outgoingBubbleColors: [UInt32] = dark ? [0x5B4B22, 0x4A3D1D] : [0xF8EAC0, 0xF3DD9E]
    let outgoingAccent: UIColor? = dark ? nil : UIColor(rgb: 0x7A5200)
    // Branded pattern wallpaper. Negative intensity draws the colours through the pattern on a dark base.
    let wallpaper = defaultBuiltinWallpaper(
        data: .default,
        colors: dark ? [0x6B5A2A, 0x34312B, 0x8A7232, 0x2A2824] : [0xF7EBC9, 0xEFDDB1, 0xFAF2DC, 0xEBD8A7],
        intensity: dark ? -45 : 40
    )
    
    let base = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    let theme = customizePresentationTheme(base, editing: false, title: title, accentColor: accent, outgoingAccentColor: outgoingAccent, backgroundColors: [], bubbleColors: outgoingBubbleColors, animateBubbleColors: false, wallpaper: wallpaper)
    
    // Pressed rows, the faint chevrons and disabled text, and the field boxes: the stock Day / Night values are neutral greys
    // that sit coldly on the warm surfaces, so they are replaced rather than inherited.
    let highlighted = UIColor(rgb: dark ? 0x35322D : 0xF1ECDD)
    let disclosure = UIColor(rgb: dark ? 0x77726A : 0xB9B3A6)
    let disabled = UIColor(rgb: dark ? 0x77726A : 0xA39E91)
    let selectedRow = surface.mixedWith(accent, alpha: dark ? 0.16 : 0.12)
    let fieldFill = dark ? raisedSurface : UIColor(rgb: 0xFFFFFF)
    let list = theme.list.withUpdated(blocksBackgroundColor: background, modalBlocksBackgroundColor: background, plainBackgroundColor: surface, modalPlainBackgroundColor: surface, itemPrimaryTextColor: foreground, itemSecondaryTextColor: secondary, itemDisabledTextColor: disabled, itemAccentColor: accent, itemPlaceholderTextColor: secondary.withAlphaComponent(0.8), itemBlocksBackgroundColor: surface, itemModalBlocksBackgroundColor: surface, itemHighlightedBackgroundColor: highlighted, itemBlocksSeparatorColor: separator, itemPlainSeparatorColor: separator, disclosureArrowColor: disclosure, sectionHeaderTextColor: secondary, freeTextColor: secondary, itemDisclosureActions: theme.list.itemDisclosureActions.withUpdated(neutral1: PresentationThemeFillForeground(fillColor: accent, foregroundColor: onAccent)), itemCheckColors: theme.list.itemCheckColors.withUpdated(fillColor: accent, foregroundColor: onAccent), controlSecondaryColor: disclosure, freeInputField: theme.list.freeInputField.withUpdated(backgroundColor: fieldFill, strokeColor: separator, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary), freePlainInputField: theme.list.freePlainInputField.withUpdated(backgroundColor: fieldFill, strokeColor: separator, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary), itemInputField: theme.list.itemInputField.withUpdated(backgroundColor: surface, strokeColor: surface, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary))
    let searchBar = UIColor(rgb: dark ? 0x2E2C28 : 0xEFEADF)
    let root = theme.rootController.withUpdated(
        tabBar: theme.rootController.tabBar.withUpdated(backgroundColor: surface, separatorColor: separator, iconColor: secondary, selectedIconColor: accent, textColor: secondary, selectedTextColor: accent, badgeBackgroundColor: accent, badgeStrokeColor: accent, badgeTextColor: onAccent),
        navigationBar: theme.rootController.navigationBar.withUpdated(buttonColor: accent, disabledButtonColor: disabled, primaryTextColor: foreground, secondaryTextColor: secondary, controlColor: secondary, accentTextColor: accent, blurredBackgroundColor: surface.withAlphaComponent(0.95), opaqueBackgroundColor: surface, separatorColor: separator, badgeBackgroundColor: accent, badgeStrokeColor: accent, badgeTextColor: onAccent, segmentedBackgroundColor: searchBar, segmentedForegroundColor: raisedSurface, segmentedTextColor: foreground, segmentedDividerColor: separator),
        navigationSearchBar: theme.rootController.navigationSearchBar.withUpdated(backgroundColor: surface, accentColor: accent, inputFillColor: background, inputTextColor: foreground, inputPlaceholderTextColor: secondary, inputIconColor: secondary, separatorColor: separator)
    )
    let pinnedRow = UIColor(rgb: dark ? 0x2C2A26 : 0xF3EEDF)
    let chats = theme.chatList.withUpdated(backgroundColor: surface, itemSeparatorColor: separator, itemBackgroundColor: surface, pinnedItemBackgroundColor: pinnedRow, itemHighlightedBackgroundColor: highlighted, pinnedItemHighlightedBackgroundColor: highlighted, itemSelectedBackgroundColor: selectedRow, titleColor: foreground, dateTextColor: secondary, authorNameColor: foreground, messageTextColor: secondary, messageHighlightedTextColor: foreground, checkmarkColor: accent, muteIconColor: secondary, unreadBadgeActiveBackgroundColor: accent, unreadBadgeActiveTextColor: onAccent, unreadBadgeInactiveBackgroundColor: UIColor(rgb: dark ? 0x5A564E : 0x8B8678), reactionBadgeActiveBackgroundColor: accent, pinnedBadgeColor: disclosure, pinnedSearchBarColor: searchBar, regularSearchBarColor: searchBar, sectionHeaderFillColor: background, sectionHeaderTextColor: secondary, pinnedArchiveAvatarColor: PresentationThemeArchiveAvatarColors(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0xF4D66F : 0xE9B949), bottomColor: UIColor(rgb: dark ? 0xD9B34A : 0xC08A1E)), foregroundColor: onAccent), unpinnedArchiveAvatarColor: PresentationThemeArchiveAvatarColors(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x5A564E : 0xC9C3B5), bottomColor: UIColor(rgb: dark ? 0x4A4740 : 0xB3AC9C)), foregroundColor: UIColor(rgb: dark ? 0xF3F0E7 : 0xFFFFFF)), storyUnseenColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0xF9E08A : 0xEDBE50), bottomColor: UIColor(rgb: dark ? 0xE0B84A : 0xC48A18)), storySeenColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x4F4B44 : 0xCFC9BA), bottomColor: UIColor(rgb: dark ? 0x4F4B44 : 0xCFC9BA)))
    
    // Chat screen: incoming bubbles on the raised surface, the input bar on the list surface, the send button in the accent.
    let incoming = theme.chat.message.incoming
    let incomingBubble = incoming.bubble.withUpdated(
        withWallpaper: incoming.bubble.withWallpaper.withUpdated(fill: [raisedSurface], highlightedFill: raisedSurface.withMultipliedBrightnessBy(dark ? 1.15 : 0.95)),
        withoutWallpaper: incoming.bubble.withoutWallpaper.withUpdated(fill: [raisedSurface], highlightedFill: raisedSurface.withMultipliedBrightnessBy(dark ? 1.15 : 0.95))
    )
    let inputPanel = theme.chat.inputPanel.withUpdated(
        panelBackgroundColor: surface.withAlphaComponent(0.94),
        panelBackgroundColorNoWallpaper: surface,
        panelSeparatorColor: separator,
        panelControlAccentColor: accent,
        panelControlColor: foreground,
        inputBackgroundColor: dark ? raisedSurface : UIColor(rgb: 0xFFFFFF),
        inputStrokeColor: separator,
        inputPlaceholderColor: secondary,
        inputTextColor: foreground,
        inputControlColor: secondary,
        actionControlFillColor: accent,
        actionControlForegroundColor: onAccent,
        primaryTextColor: foreground,
        secondaryTextColor: secondary
    )
    // The sticker / emoji / GIF panel and the bot keyboard sit under the input bar, so they take the same surface.
    let mediaPanel = theme.chat.inputMediaPanel.withUpdated(
        panelSeparatorColor: separator,
        panelIconColor: secondary,
        panelHighlightedIconBackgroundColor: accent.withAlphaComponent(0.2),
        panelHighlightedIconColor: accent,
        stickersBackgroundColor: surface,
        stickersSectionTextColor: secondary,
        stickersSearchBackgroundColor: searchBar,
        stickersSearchPlaceholderColor: secondary,
        stickersSearchPrimaryColor: foreground,
        stickersSearchControlColor: secondary,
        gifsBackgroundColor: surface,
        backgroundColor: surface
    )
    let buttonPanel = theme.chat.inputButtonPanel.withUpdated(
        panelSeparatorColor: separator,
        panelBackgroundColor: surface.withAlphaComponent(0.94),
        buttonFillColor: dark ? raisedSurface : UIColor(rgb: 0xFFFFFF),
        buttonStrokeColor: separator,
        buttonHighlightedFillColor: highlighted,
        buttonTextColor: foreground
    )
    let chat = theme.chat.withUpdated(
        message: theme.chat.message.withUpdated(
            incoming: incoming.withUpdated(bubble: incomingBubble, primaryTextColor: foreground, secondaryTextColor: secondary, linkTextColor: accent, linkHighlightColor: accent.withAlphaComponent(0.3)),
            infoLinkTextColor: accent
        ),
        inputPanel: inputPanel,
        inputMediaPanel: mediaPanel,
        inputButtonPanel: buttonPanel,
        historyNavigation: theme.chat.historyNavigation.withUpdated(fillColor: surface, strokeColor: separator, foregroundColor: secondary, badgeBackgroundColor: accent, badgeTextColor: onAccent)
    )
    
    // The same palette for the sheets, menus, banners and the passcode screen that appear over every other screen.
    let actionSheet = theme.actionSheet.withUpdated(opaqueItemBackgroundColor: surface, itemBackgroundColor: surface, opaqueItemHighlightedBackgroundColor: highlighted, itemHighlightedBackgroundColor: highlighted.withAlphaComponent(0.8), opaqueItemSeparatorColor: separator, standardActionTextColor: accent, disabledActionTextColor: disabled, primaryTextColor: foreground, secondaryTextColor: secondary, controlAccentColor: accent, inputBackgroundColor: searchBar, inputHollowBackgroundColor: searchBar, inputBorderColor: separator, inputPlaceholderColor: secondary, inputTextColor: foreground, inputClearButtonColor: secondary, checkContentColor: onAccent)
    let contextMenu = theme.contextMenu.withUpdated(backgroundColor: surface, itemSeparatorColor: separator, sectionSeparatorColor: background, itemBackgroundColor: surface, itemHighlightedBackgroundColor: highlighted, primaryColor: foreground, secondaryColor: secondary, badgeFillColor: accent, badgeForegroundColor: onAccent)
    let inAppNotification = theme.inAppNotification.withUpdated(
        fillColor: raisedSurface,
        primaryTextColor: foreground,
        expandedNotification: theme.inAppNotification.expandedNotification.withUpdated(
            navigationBar: theme.inAppNotification.expandedNotification.navigationBar.withUpdated(backgroundColor: surface, primaryTextColor: foreground, controlColor: accent, separatorColor: separator)
        )
    )
    // The passcode screen is a full-bleed gradient with white keys: gold for Cream, charcoal for Graphite.
    let passcode = theme.passcode.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x57524A : 0xA7761C), bottomColor: UIColor(rgb: dark ? 0x2A2824 : 0x7A5200)))
    
    let intro = theme.intro.withUpdated(startButtonColor: accent, dotColor: accent)
    return PresentationTheme(name: .custom(title), index: PresentationThemeReference.builtin(dark ? .bananaGramGraphite : .bananaGramCream).index, referenceTheme: theme.referenceTheme, overallDarkAppearance: dark, intro: intro, passcode: passcode, rootController: root, list: list, chatList: chats, chat: chat, actionSheet: actionSheet, contextMenu: contextMenu, inAppNotification: inAppNotification, chart: theme.chart)
}

public func customizePresentationTheme(_ theme: PresentationTheme, editing: Bool, title: String? = nil, accentColor: UIColor?, outgoingAccentColor: UIColor?, backgroundColors: [UInt32], bubbleColors: [UInt32], animateBubbleColors: Bool?, wallpaper: TelegramWallpaper? = nil, baseColor: PresentationThemeBaseColor? = nil) -> PresentationTheme {
    if accentColor == nil && bubbleColors.isEmpty && backgroundColors.isEmpty && wallpaper == nil {
        return theme
    }
    switch theme.referenceTheme {
        case .day, .dayClassic, .bananaGramCream:
            return customizeDefaultDayTheme(theme: theme, editing: editing, title: title, accentColor: accentColor, outgoingAccentColor: outgoingAccentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors ?? false, wallpaper: wallpaper, serviceBackgroundColor: nil)
        case .night, .bananaGramGraphite:
            return customizeDefaultDarkPresentationTheme(theme: theme, editing: editing, title: title, accentColor: accentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors ?? false, wallpaper: wallpaper, baseColor: baseColor)
        case .nightAccent:
            return customizeDefaultDarkTintedPresentationTheme(theme: theme, editing: editing, title: title, accentColor: accentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors ?? false, wallpaper: wallpaper, baseColor: baseColor)
    }
}

public func makePresentationTheme(settings: TelegramThemeSettings, title: String? = nil, serviceBackgroundColor: UIColor? = nil) -> PresentationTheme? {
    let defaultTheme = makeDefaultPresentationTheme(reference: PresentationBuiltinThemeReference(baseTheme: settings.baseTheme), extendingThemeReference: nil, serviceBackgroundColor: serviceBackgroundColor, preview: false)
    return customizePresentationTheme(defaultTheme, editing: true, title: title, accentColor: UIColor(argb: settings.accentColor), outgoingAccentColor: settings.outgoingAccentColor.flatMap { UIColor(argb: $0) }, backgroundColors: [], bubbleColors: settings.messageColors, animateBubbleColors: settings.animateMessageColors, wallpaper: settings.wallpaper)
}

public func makePresentationTheme(cloudTheme: TelegramTheme, dark: Bool = false) -> PresentationTheme? {
    let settings: TelegramThemeSettings?
    if let exactSettings = cloudTheme.settings?.first(where: { dark ? ($0.baseTheme == .night || $0.baseTheme == .tinted) : ($0.baseTheme == .classic || $0.baseTheme == .day) }) {
        settings = exactSettings
    } else if let firstSettings = cloudTheme.settings?.first {
        settings = firstSettings
    } else {
        settings = nil
    }
    guard let settings else {
        return nil
    }
    let defaultTheme = makeDefaultPresentationTheme(reference: PresentationBuiltinThemeReference(baseTheme: settings.baseTheme), extendingThemeReference: .cloud(PresentationCloudTheme(theme: cloudTheme, resolvedWallpaper: nil, creatorAccountId: nil)), serviceBackgroundColor: nil, preview: false)
    return customizePresentationTheme(defaultTheme, editing: true, accentColor: UIColor(argb: settings.accentColor), outgoingAccentColor: settings.outgoingAccentColor.flatMap { UIColor(argb: $0) }, backgroundColors: [], bubbleColors: settings.messageColors, animateBubbleColors: settings.animateMessageColors, wallpaper: settings.wallpaper)
}

public func makePresentationTheme(chatTheme: ChatTheme, dark: Bool = false) -> PresentationTheme? {
    guard case let .gift(_, themeSettings) = chatTheme else {
        return nil
    }
    let settings: TelegramThemeSettings?
    if let exactSettings = themeSettings.first(where: { dark ? ($0.baseTheme == .night || $0.baseTheme == .tinted) : ($0.baseTheme == .classic || $0.baseTheme == .day) }) {
        settings = exactSettings
    } else if let firstSettings = themeSettings.first {
        settings = firstSettings
    } else {
        settings = nil
    }
    guard let settings else {
        return nil
    }
    let defaultTheme = makeDefaultPresentationTheme(reference: PresentationBuiltinThemeReference(baseTheme: settings.baseTheme), serviceBackgroundColor: nil, preview: false)
    let theme = customizePresentationTheme(defaultTheme, editing: false, accentColor: UIColor(rgb: settings.accentColor), outgoingAccentColor: settings.outgoingAccentColor.flatMap { UIColor(rgb: $0) }, backgroundColors: [], bubbleColors: settings.messageColors, animateBubbleColors: settings.animateMessageColors, wallpaper: settings.wallpaper)
    if case let .gift(starGiftValue, _) = chatTheme {
        theme.starGift = starGiftValue
    }
    return theme
}

public func makePresentationTheme(cloudTheme: TelegramTheme, baseTheme: TelegramBaseTheme? = nil) -> PresentationTheme? {
    let settings: TelegramThemeSettings?
    if let exactSettings = cloudTheme.settings?.first(where: { $0.baseTheme == baseTheme }) {
        settings = exactSettings
    } else if let firstSettings = cloudTheme.settings?.first {
        settings = firstSettings
    } else {
        settings = nil
    }
    guard let settings = settings else {
        return nil
    }
    let defaultTheme = makeDefaultPresentationTheme(reference: PresentationBuiltinThemeReference(baseTheme: settings.baseTheme), extendingThemeReference: nil, serviceBackgroundColor: nil, preview: false)
    return customizePresentationTheme(defaultTheme, editing: true, accentColor: UIColor(argb: settings.accentColor), outgoingAccentColor: settings.outgoingAccentColor.flatMap { UIColor(argb: $0) }, backgroundColors: [], bubbleColors: settings.messageColors, animateBubbleColors: settings.animateMessageColors, wallpaper: settings.wallpaper)
}

public func makePresentationTheme(mediaBox: MediaBox, themeReference: PresentationThemeReference, baseTheme: TelegramBaseTheme? = nil, extendingThemeReference: PresentationThemeReference? = nil, accentColor: UIColor? = nil, outgoingAccentColor: UIColor? = nil, backgroundColors: [UInt32] = [], bubbleColors: [UInt32] = [], animateBubbleColors: Bool? = nil, wallpaper: TelegramWallpaper? = nil, baseColor: PresentationThemeBaseColor? = nil, serviceBackgroundColor: UIColor? = nil, preview: Bool = false) -> PresentationTheme? {
    var accentColor = accentColor
    if accentColor == .clear {
        accentColor = nil
    }
    let theme: PresentationTheme
    switch themeReference {
        case let .builtin(reference):
            let defaultTheme = makeDefaultPresentationTheme(reference: reference, extendingThemeReference: extendingThemeReference, serviceBackgroundColor: serviceBackgroundColor, preview: preview)
            theme = customizePresentationTheme(defaultTheme, editing: true, accentColor: accentColor, outgoingAccentColor: outgoingAccentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors, wallpaper: wallpaper, baseColor: baseColor)
        case let .local(info):
            if let path = mediaBox.completedResourcePath(info.resource), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead), let loadedTheme = makePresentationTheme(data: data, themeReference: themeReference, resolvedWallpaper: info.resolvedWallpaper) {
                theme = customizePresentationTheme(loadedTheme, editing: false, accentColor: accentColor, outgoingAccentColor: outgoingAccentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors, wallpaper: wallpaper)
            } else {
                return nil
            }
        case let .cloud(info):
            let settings: TelegramThemeSettings?
            if let exactSettings = info.theme.settings?.first(where: { $0.baseTheme == baseTheme }) {
                settings = exactSettings
            } else if let firstSettings = info.theme.settings?.first {
                settings = firstSettings
            } else {
                settings = nil
            }
            if let settings = settings {
                if let loadedTheme = makePresentationTheme(mediaBox: mediaBox, themeReference: .builtin(PresentationBuiltinThemeReference(baseTheme: settings.baseTheme)), extendingThemeReference: themeReference, accentColor: accentColor ?? UIColor(argb: settings.accentColor), outgoingAccentColor: outgoingAccentColor ?? settings.outgoingAccentColor.flatMap { UIColor(argb: $0) }, backgroundColors: [], bubbleColors: bubbleColors.isEmpty ? settings.messageColors : bubbleColors, animateBubbleColors: animateBubbleColors ?? settings.animateMessageColors, wallpaper: wallpaper ?? settings.wallpaper, serviceBackgroundColor: serviceBackgroundColor, preview: preview) {
                    theme = loadedTheme
                } else {
                    return nil
                }
            } else if let file = info.theme.file, let path = mediaBox.completedResourcePath(file.resource), let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedRead), let loadedTheme = makePresentationTheme(data: data, themeReference: themeReference, resolvedWallpaper: info.resolvedWallpaper) {
                theme = customizePresentationTheme(loadedTheme, editing: false, accentColor: accentColor, outgoingAccentColor: outgoingAccentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors, wallpaper: wallpaper)
            } else {
                return nil
            }
    }
    return theme
}

public extension PresentationTheme {
    /// Which BananaGram theme this is, if any. `referenceTheme` can't say: both are built on the stock Day / Night themes and
    /// keep their `referenceTheme`, so code that switches on it sees plain Day or Night and, with the yellow accent, an
    /// unknown custom theme. The theme's index is the only thing that identifies it.
    var bananaGramReference: PresentationBuiltinThemeReference? {
        if self.index == PresentationThemeReference.builtin(.bananaGramCream).index {
            return .bananaGramCream
        } else if self.index == PresentationThemeReference.builtin(.bananaGramGraphite).index {
            return .bananaGramGraphite
        } else {
            return nil
        }
    }
}
