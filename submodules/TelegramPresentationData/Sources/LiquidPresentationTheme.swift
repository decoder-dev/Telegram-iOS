import Foundation
import UIKit
import Display

private struct LiquidPalette {
    let background: UIColor
    let groupedBackground: UIColor
    let surface: UIColor
    let primaryText: UIColor
    let secondaryText: UIColor
    let separator: UIColor
    let accent: UIColor
    let onAccent: UIColor
    let link: UIColor
    let incoming: UIColor
    let outgoing: UIColor
    let destructive: UIColor

    init(dark: Bool) {
        self.background = UIColor(rgb: dark ? 0x000000 : 0xFFFFFF)
        self.groupedBackground = UIColor(rgb: dark ? 0x1C1C1E : 0xF2F2F7)
        self.surface = UIColor(rgb: dark ? 0x252527 : 0xFFFFFF)
        self.primaryText = UIColor(rgb: dark ? 0xF5F5F7 : 0x171719)
        self.secondaryText = UIColor(rgb: dark ? 0xAEAFB7 : 0x64646C)
        self.separator = UIColor(rgb: dark ? 0x3A3A3C : 0xDEDEE3)
        self.accent = UIColor(rgb: dark ? 0x59A5FF : 0x0069DF)
        self.onAccent = UIColor(rgb: dark ? 0x081523 : 0xFFFFFF)
        self.link = UIColor(rgb: dark ? 0x59A5FF : 0x005CBB)
        self.incoming = UIColor(rgb: dark ? 0x2C2C2E : 0xE9E9EB)
        self.outgoing = UIColor(rgb: dark ? 0x0865CA : 0x0069DF)
        self.destructive = UIColor(rgb: dark ? 0xFF756E : 0xC52B24)
    }
}

private func liquidBubble(_ bubble: PresentationThemeBubbleColor, fill: UIColor, palette: LiquidPalette) -> PresentationThemeBubbleColor {
    func update(_ colors: PresentationThemeBubbleColorComponents) -> PresentationThemeBubbleColorComponents {
        return colors.withUpdated(
            fill: [fill],
            highlightedFill: fill.mixedWith(palette.primaryText, alpha: 0.08),
            stroke: .clear,
            reactionInactiveBackground: palette.groupedBackground,
            reactionInactiveForeground: palette.link,
            reactionActiveBackground: palette.accent,
            reactionActiveForeground: palette.onAccent
        )
    }
    return bubble.withUpdated(withWallpaper: update(bubble.withWallpaper), withoutWallpaper: update(bubble.withoutWallpaper))
}

func makeLiquidPresentationTheme(_ theme: PresentationTheme) -> PresentationTheme {
    let dark = theme.overallDarkAppearance
    let palette = LiquidPalette(dark: dark)
    let highlighted = palette.background.mixedWith(palette.primaryText, alpha: 0.08)
    let selected = palette.background.mixedWith(palette.accent, alpha: 0.12)
    let inputField = theme.list.freeInputField.withUpdated(
        backgroundColor: palette.groupedBackground,
        strokeColor: palette.separator,
        placeholderColor: palette.secondaryText,
        primaryColor: palette.primaryText,
        controlColor: palette.secondaryText
    )
    let list = theme.list.withUpdated(
        blocksBackgroundColor: palette.groupedBackground,
        modalBlocksBackgroundColor: palette.groupedBackground,
        plainBackgroundColor: palette.background,
        modalPlainBackgroundColor: palette.background,
        itemPrimaryTextColor: palette.primaryText,
        itemSecondaryTextColor: palette.secondaryText,
        itemAccentColor: palette.accent,
        itemDestructiveColor: palette.destructive,
        itemPlaceholderTextColor: palette.secondaryText,
        itemBlocksBackgroundColor: palette.surface,
        itemModalBlocksBackgroundColor: palette.surface,
        itemHighlightedBackgroundColor: highlighted,
        itemBlocksSeparatorColor: palette.separator,
        itemPlainSeparatorColor: palette.separator,
        sectionHeaderTextColor: palette.secondaryText,
        freeTextColor: palette.secondaryText,
        freeTextErrorColor: palette.destructive,
        itemCheckColors: theme.list.itemCheckColors.withUpdated(fillColor: palette.accent, foregroundColor: palette.onAccent),
        freeInputField: inputField,
        freePlainInputField: inputField,
        itemInputField: inputField
    )
    let root = theme.rootController.withUpdated(
        tabBar: theme.rootController.tabBar.withUpdated(
            backgroundColor: palette.surface,
            separatorColor: palette.separator,
            iconColor: palette.secondaryText,
            selectedIconColor: palette.accent,
            textColor: palette.secondaryText,
            selectedTextColor: palette.accent,
            badgeBackgroundColor: palette.accent,
            badgeStrokeColor: palette.accent,
            badgeTextColor: palette.onAccent
        ),
        navigationBar: theme.rootController.navigationBar.withUpdated(
            buttonColor: palette.accent,
            primaryTextColor: palette.primaryText,
            secondaryTextColor: palette.secondaryText,
            controlColor: palette.secondaryText,
            accentTextColor: palette.accent,
            blurredBackgroundColor: palette.background.withAlphaComponent(0.9),
            opaqueBackgroundColor: palette.background,
            separatorColor: palette.separator,
            badgeBackgroundColor: palette.accent,
            badgeStrokeColor: palette.accent,
            badgeTextColor: palette.onAccent
        ),
        navigationSearchBar: theme.rootController.navigationSearchBar.withUpdated(
            backgroundColor: palette.background,
            accentColor: palette.accent,
            inputFillColor: palette.groupedBackground,
            inputTextColor: palette.primaryText,
            inputPlaceholderTextColor: palette.secondaryText,
            inputIconColor: palette.secondaryText,
            separatorColor: palette.separator
        )
    )
    let chatList = theme.chatList.withUpdated(
        backgroundColor: palette.background,
        itemSeparatorColor: palette.separator,
        itemBackgroundColor: palette.background,
        pinnedItemBackgroundColor: palette.background,
        itemHighlightedBackgroundColor: highlighted,
        pinnedItemHighlightedBackgroundColor: highlighted,
        itemSelectedBackgroundColor: selected,
        titleColor: palette.primaryText,
        dateTextColor: palette.secondaryText,
        authorNameColor: palette.primaryText,
        messageTextColor: palette.secondaryText,
        messageHighlightedTextColor: palette.primaryText,
        checkmarkColor: palette.accent,
        muteIconColor: palette.secondaryText,
        unreadBadgeActiveBackgroundColor: palette.accent,
        unreadBadgeActiveTextColor: palette.onAccent,
        unreadBadgeInactiveBackgroundColor: palette.secondaryText,
        unreadBadgeInactiveTextColor: palette.background,
        pinnedSearchBarColor: palette.groupedBackground,
        regularSearchBarColor: palette.groupedBackground,
        sectionHeaderFillColor: palette.groupedBackground,
        sectionHeaderTextColor: palette.secondaryText
    )
    let incoming = theme.chat.message.incoming
    let outgoing = theme.chat.message.outgoing
    let incomingBubble = liquidBubble(incoming.bubble, fill: palette.incoming, palette: palette)
    let outgoingBubble = liquidBubble(outgoing.bubble, fill: palette.outgoing, palette: palette)
    let chat = theme.chat.withUpdated(
        defaultWallpaper: .color(palette.background.rgb),
        message: theme.chat.message.withUpdated(
            incoming: incoming.withUpdated(
                bubble: incomingBubble,
                primaryTextColor: palette.primaryText,
                secondaryTextColor: palette.secondaryText,
                linkTextColor: palette.link,
                scamColor: palette.destructive,
                accentTextColor: palette.link,
                accentControlColor: palette.link,
                fileTitleColor: palette.primaryText,
                fileDescriptionColor: palette.secondaryText,
                fileDurationColor: palette.secondaryText,
                polls: incoming.polls.withUpdated(radioButton: palette.link, radioProgress: palette.link, bar: palette.link, barIconForeground: palette.onAccent)
            ),
            outgoing: outgoing.withUpdated(
                bubble: outgoingBubble,
                primaryTextColor: .white,
                secondaryTextColor: .white,
                linkTextColor: .white,
                scamColor: .white,
                accentTextColor: .white,
                accentControlColor: .white,
                fileTitleColor: .white,
                fileDescriptionColor: .white,
                fileDurationColor: .white,
                polls: outgoing.polls.withUpdated(radioButton: .white, radioProgress: .white, bar: .white, barIconForeground: palette.outgoing)
            ),
            outgoingCheckColor: .white
        ),
        inputPanel: theme.chat.inputPanel.withUpdated(
            panelBackgroundColor: palette.background.withAlphaComponent(0.9),
            panelBackgroundColorNoWallpaper: palette.background,
            panelSeparatorColor: palette.separator,
            panelControlAccentColor: palette.accent,
            panelControlColor: palette.primaryText,
            inputBackgroundColor: palette.groupedBackground,
            inputStrokeColor: palette.separator,
            inputPlaceholderColor: palette.secondaryText,
            inputTextColor: palette.primaryText,
            inputControlColor: palette.secondaryText,
            actionControlFillColor: palette.accent,
            actionControlForegroundColor: palette.onAccent,
            primaryTextColor: palette.primaryText,
            secondaryTextColor: palette.secondaryText
        ),
        historyNavigation: theme.chat.historyNavigation.withUpdated(fillColor: palette.surface, strokeColor: palette.separator, foregroundColor: palette.secondaryText, badgeBackgroundColor: palette.accent, badgeTextColor: palette.onAccent)
    )
    return PresentationTheme(
        name: theme.name, index: theme.index, referenceTheme: theme.referenceTheme, overallDarkAppearance: dark,
        intro: theme.intro, passcode: theme.passcode, rootController: root, list: list, chatList: chatList, chat: chat,
        actionSheet: theme.actionSheet.withUpdated(standardActionTextColor: palette.accent, destructiveActionTextColor: palette.destructive, primaryTextColor: palette.primaryText, secondaryTextColor: palette.secondaryText),
        contextMenu: theme.contextMenu.withUpdated(primaryColor: palette.primaryText, secondaryColor: palette.secondaryText, destructiveColor: palette.destructive),
        inAppNotification: theme.inAppNotification, chart: theme.chart
    )
}
