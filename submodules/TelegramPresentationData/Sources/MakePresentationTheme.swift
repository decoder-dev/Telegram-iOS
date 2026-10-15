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
        case .bananaGramHalloween:
            theme = makeBananaGramTheme(dark: true, halloween: true)
        case .messagesDay:
            theme = makeDefaultDayPresentationTheme(extendingThemeReference: extendingThemeReference, serviceBackgroundColor: serviceBackgroundColor, day: true, preview: preview)
        case .messagesNight:
            theme = makeDefaultDarkPresentationTheme(extendingThemeReference: extendingThemeReference, preview: preview)
    }
    return theme
}

/// Fork appearances (Cream, Graphite, Halloween and Messages), built on the stock Day / Night themes so every screen the stock themes cover stays
/// covered. Cream is a warm paper surface with a dark-gold accent; Graphite is a warm charcoal surface with a banana-yellow
/// accent. Accent foregrounds are chosen for contrast (white on dark gold, near-black on yellow), and the chat screen
/// (bubbles, input bar, scroll-down button, wallpaper) uses the same palette as the lists so the app reads as one theme.
private func makeBananaGramTheme(dark: Bool, halloween: Bool = false, messages: Bool = false) -> PresentationTheme {
    let background = UIColor(rgb: messages && dark ? 0x000000 : messages ? 0xF2F2F7 : halloween ? 0x14111D : dark ? 0x1D1C1A : 0xF6F0E3)
    let surface = UIColor(rgb: messages && dark ? 0x111111 : messages ? 0xFFFFFF : halloween ? 0x1E1929 : dark ? 0x272522 : 0xFFFAF2)
    let raisedSurface = UIColor(rgb: messages && dark ? 0x262629 : messages ? 0xE9E9EB : halloween ? 0x2A2338 : dark ? 0x312F2B : 0xFFFDF8)
    let foreground = UIColor(rgb: messages && dark ? 0xF5F5F7 : messages ? 0x1C1C1E : halloween ? 0xF8F0E8 : dark ? 0xEFEBE0 : 0x3A3430)
    let secondary = UIColor(rgb: messages && dark ? 0xB2B2B8 : messages ? 0x5C5C62 : halloween ? 0xC0B2CB : dark ? 0xB5B0A4 : 0x6A655D)
    let accent = UIColor(rgb: messages && dark ? 0x69B5FF : messages ? 0x0064CF : halloween ? 0xFFB45E : dark ? 0xEBD58F : 0x8A5F1E)
    // Text and glyphs drawn on an accent fill: white on dark gold, near-black on banana yellow.
    let onAccent = UIColor(rgb: messages && dark ? 0x101010 : messages ? 0xFFFFFF : halloween ? 0x24150D : dark ? 0x1B1A16 : 0xFFFFFF)
    let actionFill = messages ? UIColor(rgb: 0x0064CF) : accent
    let actionForeground = messages ? UIColor.white : onAccent
    let separator = UIColor(rgb: messages && dark ? 0x333336 : messages ? 0xDCDCE0 : halloween ? 0x3A3049 : dark ? 0x3A3733 : 0xE6DDCC)
    let title = messages ? (dark ? "Messages Dark" : "Messages Light") : halloween ? "BananaGram Halloween" : dark ? "BananaGram Graphite" : "BananaGram Cream"
    
    // Outgoing bubbles: soft banana cream with dark-gold details by day, deep olive gold with white text by night.
    let outgoingBubbleColors: [UInt32] = messages ? [0x0064CF, 0x0064CF] : halloween ? [0x543326, 0x432A25] : dark ? [0x5E5236, 0x4A4029] : [0xFCF2DC, 0xF8EBCB]
    let outgoingAccent: UIColor? = messages ? UIColor.white : dark ? nil : UIColor(rgb: 0x85591A)
    // Branded pattern wallpaper. Negative intensity draws the colours through the pattern on a dark base.
    let wallpaper: TelegramWallpaper = messages ? .color(dark ? 0x000000 : 0xFFFFFF) : defaultBuiltinWallpaper(
        data: halloween ? .halloween : .default,
        colors: halloween ? [0x21182E, 0x181420, 0x34213A, 0x17131F] : dark ? [0x5E5232, 0x34312B, 0x75653A, 0x2A2824] : [0xFAF1DC, 0xF4E7C9, 0xFCF6E8, 0xF0E2C2],
        intensity: halloween ? -22 : dark ? -42 : 32
    )
    
    let base = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    let theme = customizePresentationTheme(base, editing: false, title: title, accentColor: accent, outgoingAccentColor: outgoingAccent, backgroundColors: [], bubbleColors: outgoingBubbleColors, animateBubbleColors: false, wallpaper: wallpaper)
    
    // Pressed rows, the faint chevrons and disabled text, and the field boxes: the stock Day / Night values are neutral greys
    // that sit coldly on the warm surfaces, so they are replaced rather than inherited.
    let highlighted = UIColor(rgb: messages && dark ? 0x303033 : messages ? 0xE9E9EB : halloween ? 0x352B44 : dark ? 0x36332E : 0xF1E8D6)
    let disclosure = UIColor(rgb: messages && dark ? 0x94949B : messages ? 0x8A8A91 : halloween ? 0x9784A6 : dark ? 0x77726A : 0xBDB5A5)
    let disabled = UIColor(rgb: messages && dark ? 0x94949B : messages ? 0x929299 : halloween ? 0x9784A6 : dark ? 0x77726A : 0xA39C8E)
    let selectedRow = surface.mixedWith(accent, alpha: dark ? 0.16 : 0.12)
    let fieldFill = dark ? raisedSurface : UIColor(rgb: 0xFFFFFF)
    // Keep ordinary controls in the brand palette; destructive/success colours remain semantic.
    let switchColors = theme.list.itemSwitchColors.withUpdated(frameColor: separator, handleColor: messages ? .white : onAccent, contentColor: messages ? actionFill : accent)
    let disclosureActions = theme.list.itemDisclosureActions.withUpdated(
        neutral1: PresentationThemeFillForeground(fillColor: accent, foregroundColor: onAccent),
        accent: PresentationThemeFillForeground(fillColor: accent, foregroundColor: onAccent)
    )
    // Both archive gradients are light in Cream, so a dark glyph stays legible across the whole fill.
    let archiveForeground = UIColor(rgb: messages && dark ? 0x101010 : messages ? 0x101010 : halloween ? 0x24150D : dark ? 0x1B1A16 : 0x292D32)
    let list = theme.list.withUpdated(blocksBackgroundColor: background, modalBlocksBackgroundColor: background, plainBackgroundColor: surface, modalPlainBackgroundColor: surface, itemPrimaryTextColor: foreground, itemSecondaryTextColor: secondary, itemDisabledTextColor: disabled, itemAccentColor: accent, itemPlaceholderTextColor: secondary.withAlphaComponent(0.8), itemBlocksBackgroundColor: surface, itemModalBlocksBackgroundColor: surface, itemHighlightedBackgroundColor: highlighted, itemBlocksSeparatorColor: separator, itemPlainSeparatorColor: separator, disclosureArrowColor: disclosure, sectionHeaderTextColor: secondary, freeTextColor: secondary, itemSwitchColors: switchColors, itemDisclosureActions: disclosureActions, itemCheckColors: theme.list.itemCheckColors.withUpdated(fillColor: messages ? actionFill : accent, foregroundColor: messages ? .white : onAccent), controlSecondaryColor: disclosure, freeInputField: theme.list.freeInputField.withUpdated(backgroundColor: fieldFill, strokeColor: separator, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary), freePlainInputField: theme.list.freePlainInputField.withUpdated(backgroundColor: fieldFill, strokeColor: separator, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary), itemInputField: theme.list.itemInputField.withUpdated(backgroundColor: surface, strokeColor: surface, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary))
    let searchBar = UIColor(rgb: messages && dark ? 0x242426 : messages ? 0xF2F2F7 : halloween ? 0x292136 : dark ? 0x302E2A : 0xF0E9DB)
    let root = theme.rootController.withUpdated(
        tabBar: theme.rootController.tabBar.withUpdated(backgroundColor: surface, separatorColor: separator, iconColor: secondary, selectedIconColor: accent, textColor: secondary, selectedTextColor: accent, badgeBackgroundColor: accent, badgeStrokeColor: accent, badgeTextColor: onAccent),
        navigationBar: theme.rootController.navigationBar.withUpdated(buttonColor: accent, disabledButtonColor: disabled, primaryTextColor: foreground, secondaryTextColor: secondary, controlColor: secondary, accentTextColor: accent, blurredBackgroundColor: surface.withAlphaComponent(0.95), opaqueBackgroundColor: surface, separatorColor: separator, badgeBackgroundColor: accent, badgeStrokeColor: accent, badgeTextColor: onAccent, segmentedBackgroundColor: searchBar, segmentedForegroundColor: raisedSurface, segmentedTextColor: foreground, segmentedDividerColor: separator),
        navigationSearchBar: theme.rootController.navigationSearchBar.withUpdated(backgroundColor: surface, accentColor: accent, inputFillColor: messages ? searchBar : background, inputTextColor: foreground, inputPlaceholderTextColor: secondary, inputIconColor: secondary, separatorColor: separator)
    )
    // Pinned rows are only a breath apart from ordinary ones: a visible two-tone list reads as a mistake, not a hierarchy.
    let pinnedRow = UIColor(rgb: messages && dark ? 0x151517 : messages ? 0xFAFAFC : halloween ? 0x221C2D : dark ? 0x2B2926 : 0xFBF6EA)
    let inactiveBadgeBackground = UIColor(rgb: messages && dark ? 0x505056 : messages ? 0x68686E : halloween ? 0x584664 : dark ? 0x5A564E : 0x756F62)
    let chats = theme.chatList.withUpdated(backgroundColor: surface, itemSeparatorColor: separator, itemBackgroundColor: surface, pinnedItemBackgroundColor: pinnedRow, itemHighlightedBackgroundColor: highlighted, pinnedItemHighlightedBackgroundColor: highlighted, itemSelectedBackgroundColor: selectedRow, titleColor: foreground, dateTextColor: secondary, authorNameColor: foreground, messageTextColor: secondary, messageHighlightedTextColor: foreground, checkmarkColor: accent, muteIconColor: secondary, unreadBadgeActiveBackgroundColor: accent, unreadBadgeActiveTextColor: onAccent, unreadBadgeInactiveBackgroundColor: inactiveBadgeBackground, unreadBadgeInactiveTextColor: dark ? foreground : onAccent, reactionBadgeActiveBackgroundColor: accent, pinnedBadgeColor: disclosure, pinnedSearchBarColor: searchBar, regularSearchBarColor: searchBar, sectionHeaderFillColor: background, sectionHeaderTextColor: secondary, verifiedIconFillColor: accent, verifiedIconForegroundColor: onAccent, pinnedArchiveAvatarColor: PresentationThemeArchiveAvatarColors(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: messages && dark ? 0x91CAFF : messages ? 0x91CAFF : halloween ? 0xFFC070 : dark ? 0xF4D66F : 0xE9B949), bottomColor: UIColor(rgb: messages && dark ? 0x66B4FA : messages ? 0x66B4FA : halloween ? 0xF59A48 : dark ? 0xD9B34A : 0xC08A1E)), foregroundColor: archiveForeground), unpinnedArchiveAvatarColor: PresentationThemeArchiveAvatarColors(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: messages && dark ? 0x505056 : messages ? 0xC7C7CC : halloween ? 0x584664 : dark ? 0x5A564E : 0xC9C3B5), bottomColor: UIColor(rgb: messages && dark ? 0x404046 : messages ? 0xB5B5BC : halloween ? 0x43354F : dark ? 0x4A4740 : 0xB3AC9C)), foregroundColor: dark ? foreground : archiveForeground), storyUnseenColors: PresentationThemeGradientColors(topColor: UIColor(rgb: messages && dark ? 0x69B5FF : messages ? 0x0064CF : halloween ? 0xFFB45E : dark ? 0xF9E08A : 0xEDBE50), bottomColor: UIColor(rgb: messages && dark ? 0x4C9CEB : messages ? 0x0064CF : halloween ? 0xBD89D5 : dark ? 0xE0B84A : 0xC48A18)), storySeenColors: PresentationThemeGradientColors(topColor: UIColor(rgb: messages && dark ? 0x444448 : messages ? 0xCECED3 : halloween ? 0x51415F : dark ? 0x4F4B44 : 0xCFC9BA), bottomColor: UIColor(rgb: messages && dark ? 0x444448 : messages ? 0xCECED3 : halloween ? 0x51415F : dark ? 0x4F4B44 : 0xCFC9BA)))
    
    // Chat screen: incoming bubbles on the raised surface, the input bar on the list surface, the send button in the accent.
    let incoming = theme.chat.message.incoming
    let incomingBubble = incoming.bubble.withUpdated(
        withWallpaper: incoming.bubble.withWallpaper.withUpdated(fill: [raisedSurface], highlightedFill: raisedSurface.withMultipliedBrightnessBy(dark ? 1.15 : 0.95), stroke: messages ? .clear : dark ? UIColor(white: 1.0, alpha: 0.06) : separator.withAlphaComponent(0.6), reactionInactiveBackground: messages ? raisedSurface : nil, reactionInactiveForeground: messages ? foreground : nil, reactionActiveBackground: accent, reactionActiveForeground: onAccent),
        withoutWallpaper: incoming.bubble.withoutWallpaper.withUpdated(fill: [raisedSurface], highlightedFill: raisedSurface.withMultipliedBrightnessBy(dark ? 1.15 : 0.95), stroke: messages ? UIColor.clear : nil, reactionInactiveBackground: messages ? raisedSurface : nil, reactionInactiveForeground: messages ? foreground : nil, reactionActiveBackground: accent, reactionActiveForeground: onAccent)
    )
    let inputPanel = theme.chat.inputPanel.withUpdated(
        panelBackgroundColor: surface.withAlphaComponent(0.94),
        panelBackgroundColorNoWallpaper: surface,
        panelSeparatorColor: separator,
        panelControlAccentColor: accent,
        panelControlColor: foreground,
        inputBackgroundColor: messages ? searchBar : dark ? raisedSurface : UIColor(rgb: 0xFFFFFF),
        inputStrokeColor: separator,
        inputPlaceholderColor: secondary,
        inputTextColor: foreground,
        inputControlColor: secondary,
        actionControlFillColor: actionFill,
        actionControlForegroundColor: actionForeground,
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
    let outgoing = theme.chat.message.outgoing
    let freeform = theme.chat.message.freeform
    let chat = theme.chat.withUpdated(
        message: theme.chat.message.withUpdated(
            incoming: incoming.withUpdated(bubble: incomingBubble, primaryTextColor: foreground, secondaryTextColor: secondary, linkTextColor: accent, linkHighlightColor: accent.withAlphaComponent(0.3)),
            outgoing: outgoing.withUpdated(
                bubble: outgoing.bubble.withUpdated(
                    withWallpaper: outgoing.bubble.withWallpaper.withUpdated(reactionInactiveBackground: messages ? raisedSurface : nil, reactionInactiveForeground: messages ? foreground : nil, reactionActiveBackground: accent, reactionActiveForeground: onAccent),
                    withoutWallpaper: outgoing.bubble.withoutWallpaper.withUpdated(reactionInactiveBackground: messages ? raisedSurface : nil, reactionInactiveForeground: messages ? foreground : nil, reactionActiveBackground: accent, reactionActiveForeground: onAccent)
                ),
                primaryTextColor: messages ? .white : nil,
                secondaryTextColor: messages ? UIColor.white.withAlphaComponent(0.92) : nil,
                linkTextColor: messages ? .white : nil,
                accentTextColor: messages ? .white : nil,
                accentControlColor: messages ? .white : nil,
                fileTitleColor: messages ? .white : nil,
                fileDescriptionColor: messages ? UIColor.white.withAlphaComponent(0.92) : nil,
                fileDurationColor: messages ? UIColor.white.withAlphaComponent(0.92) : nil
            ),
            freeform: freeform.withUpdated(
                withWallpaper: freeform.withWallpaper.withUpdated(reactionInactiveBackground: messages ? raisedSurface : nil, reactionInactiveForeground: messages ? foreground : nil, reactionActiveBackground: accent, reactionActiveForeground: onAccent),
                withoutWallpaper: freeform.withoutWallpaper.withUpdated(reactionInactiveBackground: messages ? raisedSurface : nil, reactionInactiveForeground: messages ? foreground : nil, reactionActiveBackground: accent, reactionActiveForeground: onAccent)
            ),
            infoLinkTextColor: accent,
            outgoingCheckColor: messages ? UIColor.white.withAlphaComponent(0.92) : nil,
            selectionControlColors: theme.chat.message.selectionControlColors.withUpdated(fillColor: accent, foregroundColor: onAccent)
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
    let passcode = theme.passcode.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: messages && dark ? 0x242426 : messages ? 0x325F95 : halloween ? 0x392448 : dark ? 0x57524A : 0xA7761C), bottomColor: UIColor(rgb: messages && dark ? 0x000000 : messages ? 0x163C69 : halloween ? 0x1A1425 : dark ? 0x2A2824 : 0x7A5200)))
    
    let chart = theme.chart.withUpdated(
        labelsColor: secondary,
        helperLinesColor: separator,
        strongLinesColor: secondary.withAlphaComponent(0.45),
        barStrongLinesColor: secondary.withAlphaComponent(0.45),
        detailsTextColor: foreground,
        detailsArrowColor: secondary,
        detailsViewColor: raisedSurface,
        rangeViewFrameColor: separator,
        rangeViewMarkerColor: secondary
    )
    let intro = theme.intro.withUpdated(startButtonColor: accent, dotColor: accent)
    return PresentationTheme(name: .custom(title), index: PresentationThemeReference.builtin(messages ? (dark ? .messagesNight : .messagesDay) : halloween ? .bananaGramHalloween : dark ? .bananaGramGraphite : .bananaGramCream).index, referenceTheme: theme.referenceTheme, overallDarkAppearance: dark, intro: intro, passcode: passcode, rootController: root, list: list, chatList: chats, chat: chat, actionSheet: actionSheet, contextMenu: contextMenu, inAppNotification: inAppNotification, chart: chart)
}

public func customizePresentationTheme(_ theme: PresentationTheme, editing: Bool, title: String? = nil, accentColor: UIColor?, outgoingAccentColor: UIColor?, backgroundColors: [UInt32], bubbleColors: [UInt32], animateBubbleColors: Bool?, wallpaper: TelegramWallpaper? = nil, baseColor: PresentationThemeBaseColor? = nil) -> PresentationTheme {
    if accentColor == nil && bubbleColors.isEmpty && backgroundColors.isEmpty && wallpaper == nil {
        return theme
    }
    switch theme.referenceTheme {
        case .day, .dayClassic, .bananaGramCream, .messagesDay:
            return customizeDefaultDayTheme(theme: theme, editing: editing, title: title, accentColor: accentColor, outgoingAccentColor: outgoingAccentColor, backgroundColors: backgroundColors, bubbleColors: bubbleColors, animateBubbleColors: animateBubbleColors ?? false, wallpaper: wallpaper, serviceBackgroundColor: nil)
        case .night, .bananaGramGraphite, .bananaGramHalloween, .messagesNight:
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

/// Shared geometry for Messages screens. Content remains self-sizing at larger text sizes.
public enum MessagesAppearanceMetrics {
    public static let sectionCornerRadius: CGFloat = 16.0
    public static let searchCornerRadius: CGFloat = 12.0
    public static let actionCornerRadius: CGFloat = 14.0
    public static let minimumRowHeight: CGFloat = 50.0

    public static func rowHeight(contentHeight: CGFloat, verticalInset: CGFloat) -> CGFloat {
        return max(minimumRowHeight, contentHeight + verticalInset * 2.0)
    }

    public static func searchRadius(height: CGFloat) -> CGFloat {
        return min(searchCornerRadius, max(0.0, height * 0.5))
    }

    public static func actionRadius(height: CGFloat) -> CGFloat {
        return min(actionCornerRadius, max(0.0, height * 0.5))
    }
}

public extension PresentationTheme {
    var isMessagesTheme: Bool {
        // Retired appearance: keep the compatibility API without enabling its styling.
        return false
    }

    /// Fork appearance identity. These palettes keep their stock Day / Night base for rendering;
    /// their stable index identifies Cream, Graphite, Halloween and the two Messages variants.
    var bananaGramReference: PresentationBuiltinThemeReference? {
        if self.index == PresentationThemeReference.builtin(.bananaGramCream).index {
            return .bananaGramCream
        } else if self.index == PresentationThemeReference.builtin(.bananaGramGraphite).index {
            return .bananaGramGraphite
        } else if self.index == PresentationThemeReference.builtin(.bananaGramHalloween).index {
            return .bananaGramHalloween
        } else if self.index == PresentationThemeReference.builtin(.messagesDay).index {
            return .messagesDay
        } else if self.index == PresentationThemeReference.builtin(.messagesNight).index {
            return .messagesNight
        } else {
            return nil
        }
    }
}
