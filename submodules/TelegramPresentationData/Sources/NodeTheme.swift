import Foundation
import UIKit
import Display
import TelegramUIPreferences
import TelegramCore

/// "Node": the palette of the Telegram UI kit (310 screens) the owner asked for. White list blocks on a flat light grey,
/// a single clear blue accent, light-blue outgoing bubbles, flat wallpaper. Built the same way as the BananaGram themes
/// (on the stock Day / Night themes, then every list, bar, chat and sheet colour replaced) so every screen the stock
/// themes cover is covered. The dark variant is derived from the same hue: the kit itself has no dark screens.
/// Lives in its own file so the BananaGram palette tests keep reading `makeBananaGramTheme` alone.
func makeNodeTheme(dark: Bool) -> PresentationTheme {
    let background = UIColor(rgb: dark ? 0x0E1013 : 0xEBEBEB)
    let surface = UIColor(rgb: dark ? 0x16191D : 0xFFFFFF)
    let raisedSurface = UIColor(rgb: dark ? 0x1E2228 : 0xFFFFFF)
    let foreground = UIColor(rgb: dark ? 0xF1F3F6 : 0x171717)
    let secondary = UIColor(rgb: dark ? 0xA3A9B3 : 0x636367)
    let accent = UIColor(rgb: dark ? 0x4DA8FF : 0x0068CC)
    // Text and glyphs drawn on an accent fill: white on dark gold, near-black on banana yellow.
    let onAccent = UIColor(rgb: dark ? 0x04172B : 0xFFFFFF)
    let separator = UIColor(rgb: dark ? 0x2A2F36 : 0xE0E0E0)
    let title = dark ? "Node Dark" : "Node Light"
    
    // Outgoing bubbles: the kit's light blue with dark text by day, a deep blue with white text by night.
    let outgoingBubbleColors: [UInt32] = dark ? [0x1D5A9E, 0x174C86] : [0xCCE7FF, 0xBFE0FF]
    let outgoingAccent: UIColor? = dark ? nil : UIColor(rgb: 0x0A5CB0)
    // Plain wallpaper, as in the kit: flat light grey by day, near-black by night.
    let wallpaper: TelegramWallpaper = .color(dark ? 0x0E1013 : 0xEBEBEB)
    
    let base = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    let theme = customizePresentationTheme(base, editing: false, title: title, accentColor: accent, outgoingAccentColor: outgoingAccent, backgroundColors: [], bubbleColors: outgoingBubbleColors, animateBubbleColors: false, wallpaper: wallpaper)
    
    // Pressed rows, the faint chevrons and disabled text, and the field boxes: the stock Day / Night values are neutral greys
    // that sit coldly on the warm surfaces, so they are replaced rather than inherited.
    let highlighted = UIColor(rgb: dark ? 0x232830 : 0xF0F0F0)
    let disclosure = UIColor(rgb: dark ? 0x5A616C : 0xBDBDC3)
    let disabled = UIColor(rgb: dark ? 0x6B727D : 0xA0A0A6)
    let selectedRow = surface.mixedWith(accent, alpha: dark ? 0.16 : 0.12)
    let fieldFill = dark ? raisedSurface : UIColor(rgb: 0xFFFFFF)
    // Keep ordinary controls in the brand palette; destructive/success colours remain semantic.
    let switchColors = theme.list.itemSwitchColors.withUpdated(frameColor: separator, handleColor: onAccent, contentColor: accent)
    let disclosureActions = theme.list.itemDisclosureActions.withUpdated(
        neutral1: PresentationThemeFillForeground(fillColor: accent, foregroundColor: onAccent),
        accent: PresentationThemeFillForeground(fillColor: accent, foregroundColor: onAccent)
    )
    // Both archive gradients are light in Cream, so a dark glyph stays legible across the whole fill.
    let archiveForeground = UIColor(rgb: 0x0B2A4A)
    let list = theme.list.withUpdated(blocksBackgroundColor: background, modalBlocksBackgroundColor: background, plainBackgroundColor: surface, modalPlainBackgroundColor: surface, itemPrimaryTextColor: foreground, itemSecondaryTextColor: secondary, itemDisabledTextColor: disabled, itemAccentColor: accent, itemPlaceholderTextColor: secondary.withAlphaComponent(0.8), itemBlocksBackgroundColor: surface, itemModalBlocksBackgroundColor: surface, itemHighlightedBackgroundColor: highlighted, itemBlocksSeparatorColor: separator, itemPlainSeparatorColor: separator, disclosureArrowColor: disclosure, sectionHeaderTextColor: secondary, freeTextColor: secondary, itemSwitchColors: switchColors, itemDisclosureActions: disclosureActions, itemCheckColors: theme.list.itemCheckColors.withUpdated(fillColor: accent, foregroundColor: onAccent), controlSecondaryColor: disclosure, freeInputField: theme.list.freeInputField.withUpdated(backgroundColor: fieldFill, strokeColor: separator, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary), freePlainInputField: theme.list.freePlainInputField.withUpdated(backgroundColor: fieldFill, strokeColor: separator, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary), itemInputField: theme.list.itemInputField.withUpdated(backgroundColor: surface, strokeColor: surface, placeholderColor: secondary, primaryColor: foreground, controlColor: secondary))
    let searchBar = UIColor(rgb: dark ? 0x1F2329 : 0xF5F5F5)
    let root = theme.rootController.withUpdated(
        tabBar: theme.rootController.tabBar.withUpdated(backgroundColor: surface, separatorColor: separator, iconColor: secondary, selectedIconColor: accent, textColor: secondary, selectedTextColor: accent, badgeBackgroundColor: accent, badgeStrokeColor: accent, badgeTextColor: onAccent),
        navigationBar: theme.rootController.navigationBar.withUpdated(buttonColor: accent, disabledButtonColor: disabled, primaryTextColor: foreground, secondaryTextColor: secondary, controlColor: secondary, accentTextColor: accent, blurredBackgroundColor: surface.withAlphaComponent(0.95), opaqueBackgroundColor: surface, separatorColor: separator, badgeBackgroundColor: accent, badgeStrokeColor: accent, badgeTextColor: onAccent, segmentedBackgroundColor: searchBar, segmentedForegroundColor: raisedSurface, segmentedTextColor: foreground, segmentedDividerColor: separator),
        navigationSearchBar: theme.rootController.navigationSearchBar.withUpdated(backgroundColor: surface, accentColor: accent, inputFillColor: background, inputTextColor: foreground, inputPlaceholderTextColor: secondary, inputIconColor: secondary, separatorColor: separator)
    )
    // Pinned rows are only a breath apart from ordinary ones: a visible two-tone list reads as a mistake, not a hierarchy.
    let pinnedRow = UIColor(rgb: dark ? 0x1A1E23 : 0xF8FAFC)
    let inactiveBadgeBackground = UIColor(rgb: dark ? 0x4A515B : 0x6E6E75)
    let chats = theme.chatList.withUpdated(backgroundColor: surface, itemSeparatorColor: separator, itemBackgroundColor: surface, pinnedItemBackgroundColor: pinnedRow, itemHighlightedBackgroundColor: highlighted, pinnedItemHighlightedBackgroundColor: highlighted, itemSelectedBackgroundColor: selectedRow, titleColor: foreground, dateTextColor: secondary, authorNameColor: foreground, messageTextColor: secondary, messageHighlightedTextColor: foreground, checkmarkColor: accent, muteIconColor: secondary, unreadBadgeActiveBackgroundColor: accent, unreadBadgeActiveTextColor: onAccent, unreadBadgeInactiveBackgroundColor: inactiveBadgeBackground, unreadBadgeInactiveTextColor: dark ? foreground : onAccent, reactionBadgeActiveBackgroundColor: accent, pinnedBadgeColor: disclosure, pinnedSearchBarColor: searchBar, regularSearchBarColor: searchBar, sectionHeaderFillColor: background, sectionHeaderTextColor: secondary, pinnedArchiveAvatarColor: PresentationThemeArchiveAvatarColors(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x7CC4FF : 0x6CBBFF), bottomColor: UIColor(rgb: dark ? 0x4DA8FF : 0x39A0FF)), foregroundColor: archiveForeground), unpinnedArchiveAvatarColor: PresentationThemeArchiveAvatarColors(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x4A515B : 0xC9CBD1), bottomColor: UIColor(rgb: dark ? 0x3B424C : 0xB4B7BF)), foregroundColor: dark ? foreground : archiveForeground), storyUnseenColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x7CC4FF : 0x4FB4FF), bottomColor: UIColor(rgb: dark ? 0x2F9BFF : 0x0087FD)), storySeenColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x3B424C : 0xD0D2D8), bottomColor: UIColor(rgb: dark ? 0x3B424C : 0xD0D2D8)))
    
    // Chat screen: incoming bubbles on the raised surface, the input bar on the list surface, the send button in the accent.
    let incoming = theme.chat.message.incoming
    let incomingBubble = incoming.bubble.withUpdated(
        withWallpaper: incoming.bubble.withWallpaper.withUpdated(fill: [raisedSurface], highlightedFill: raisedSurface.withMultipliedBrightnessBy(dark ? 1.15 : 0.95), stroke: dark ? UIColor(white: 1.0, alpha: 0.06) : separator.withAlphaComponent(0.6)),
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
    // The passcode screen is a full-bleed gradient with white keys: blue by day, deep navy by night.
    let passcode = theme.passcode.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: UIColor(rgb: dark ? 0x1E3A5F : 0x2F9BFF), bottomColor: UIColor(rgb: dark ? 0x0B1522 : 0x0067C7)))
    
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
    return PresentationTheme(name: .custom(title), index: PresentationThemeReference.builtin(dark ? .nodeDark : .nodeLight).index, referenceTheme: theme.referenceTheme, overallDarkAppearance: dark, intro: intro, passcode: passcode, rootController: root, list: list, chatList: chats, chat: chat, actionSheet: actionSheet, contextMenu: contextMenu, inAppNotification: inAppNotification, chart: chart)
}
