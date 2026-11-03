import Foundation
import UIKit
import XCTest
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

final class LiquidThemeTests: XCTestCase {
    private static let mediaBox = MediaBox(
        basePath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
        isMainProcess: false
    )

    private func theme(_ reference: PresentationBuiltinThemeReference, accent: UIColor? = nil, bubbles: [UInt32] = [], wallpaper: TelegramWallpaper? = nil) throws -> PresentationTheme {
        return try XCTUnwrap(makePresentationTheme(mediaBox: Self.mediaBox, themeReference: .builtin(reference), accentColor: accent, bubbleColors: bubbles, wallpaper: wallpaper))
    }

    func testLiquidDefaultsKeepTheStockMessageColors() throws {
        for reference: PresentationBuiltinThemeReference in [.dayClassic, .day, .night] {
            let theme = try self.theme(reference)
            let dark = theme.overallDarkAppearance
            XCTAssertEqual(theme.chat.message.incoming.bubble.withoutWallpaper.fill.first?.rgb, dark ? 0x2C2C2E : 0xE9E9EB)
            XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill.first?.rgb, dark ? 0x0865CA : 0x0069DF)
            XCTAssertEqual(theme.chat.message.outgoing.primaryTextColor.rgb, 0xFFFFFF)
        }
    }

    func testReactionAndPollForegroundsRemainOpaqueAfterCustomization() throws {
        for reference: PresentationBuiltinThemeReference in [.dayClassic, .day, .night] {
            let theme = try self.theme(reference, wallpaper: .color(0x17384B))
            let expected: UInt32 = theme.overallDarkAppearance ? 0x081523 : 0xFFFFFF
            for colors in [theme.chat.message.incoming, theme.chat.message.outgoing] {
                XCTAssertEqual(colors.bubble.withWallpaper.reactionActiveForeground.rgb, expected)
                XCTAssertEqual(colors.bubble.withWallpaper.reactionActiveForeground.alpha, 1.0)
                XCTAssertEqual(colors.bubble.withoutWallpaper.reactionActiveForeground.alpha, 1.0)
                XCTAssertEqual(colors.polls.barIconForeground.alpha, 1.0)
            }
        }
    }

    func testExplicitAccentAndMessageColorsArePreserved() throws {
        let theme = try self.theme(.day, accent: UIColor(rgb: 0x137249), bubbles: [0xFCE9AF])
        XCTAssertEqual(theme.list.itemAccentColor.rgb, 0x137249)
        XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill.first?.rgb, 0xFCE9AF)
    }

    func testExplicitWallpaperIsPreservedWithDefaultColors() throws {
        let wallpaper = TelegramWallpaper.color(0x17384B)
        let theme = try self.theme(.dayClassic, wallpaper: wallpaper)
        XCTAssertEqual(theme.chat.defaultWallpaper, wallpaper)
        XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill.first?.rgb, 0x0069DF)
    }

    func testStartupThemeUsesTheSamePaletteAsClassicWhite() throws {
        let theme = try self.theme(.dayClassic)
        XCTAssertEqual(defaultPresentationTheme.list.plainBackgroundColor, theme.list.plainBackgroundColor)
        XCTAssertEqual(defaultPresentationTheme.chat.message.incoming.primaryTextColor, theme.chat.message.incoming.primaryTextColor)
        XCTAssertEqual(defaultPresentationTheme.chat.message.outgoing.bubble.withoutWallpaper.fill, theme.chat.message.outgoing.bubble.withoutWallpaper.fill)
    }

    func testCustomThemeBasesDoNotInheritLiquidColors() {
        let reference = PresentationThemeReference.local(PresentationLocalTheme(title: "Imported", resource: LocalFileMediaResource(fileId: 42), resolvedWallpaper: nil))
        for builtin: PresentationBuiltinThemeReference in [.dayClassic, .day, .night] {
            let stock = builtin == .night
                ? makeDefaultDarkPresentationTheme(extendingThemeReference: reference, preview: false)
                : makeDefaultDayPresentationTheme(extendingThemeReference: reference, serviceBackgroundColor: nil, day: builtin == .day, preview: false)
            let theme = makeDefaultPresentationTheme(reference: builtin, extendingThemeReference: reference, serviceBackgroundColor: nil)
            XCTAssertEqual(theme.list.itemPrimaryTextColor, stock.list.itemPrimaryTextColor)
            XCTAssertEqual(theme.chatList.backgroundColor, stock.chatList.backgroundColor)
            XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill, stock.chat.message.outgoing.bubble.withoutWallpaper.fill)
            XCTAssertEqual(theme.chat.defaultWallpaper, stock.chat.defaultWallpaper)
        }
    }

    func testCloudSettingsPreserveStockFallbacksAndExplicitColors() throws {
        let settings = TelegramThemeSettings(baseTheme: .day, accentColor: 0xFF137249, outgoingAccentColor: nil, messageColors: [0xFCE9AF], animateMessageColors: false, wallpaper: .color(0x17384B))
        let stock = makeDefaultDayPresentationTheme(serviceBackgroundColor: nil, day: true, preview: false)
        let expected = customizePresentationTheme(stock, editing: true, accentColor: UIColor(argb: settings.accentColor), outgoingAccentColor: nil, backgroundColors: [], bubbleColors: settings.messageColors, animateBubbleColors: false, wallpaper: settings.wallpaper)
        let theme = try XCTUnwrap(makePresentationTheme(settings: settings))
        XCTAssertEqual(theme.list.itemPrimaryTextColor, expected.list.itemPrimaryTextColor)
        XCTAssertEqual(theme.chatList.backgroundColor, expected.chatList.backgroundColor)
        XCTAssertEqual(theme.list.itemAccentColor.rgb, 0x137249)
        XCTAssertEqual(theme.chat.message.outgoing.bubble.withoutWallpaper.fill.first?.rgb, 0xFCE9AF)
        XCTAssertEqual(theme.chat.defaultWallpaper, settings.wallpaper)
    }

    func testImportedThemeOmissionsUseStockFallbacks() throws {
        let stock = makeDefaultDayPresentationTheme(serviceBackgroundColor: defaultServiceBackgroundColor, day: true, preview: false)
        let encoded = try XCTUnwrap(encodePresentationTheme(stock))
        let olderTheme = encoded.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("  modalBlocksBg:") }
            .joined(separator: "\n")
        let theme = try XCTUnwrap(makePresentationTheme(data: Data(olderTheme.utf8)))
        XCTAssertEqual(theme.list.modalBlocksBackgroundColor, stock.list.blocksBackgroundColor)
    }

    func testBrandedThemesKeepTheirPalettes() throws {
        let cream = try self.theme(.bananaGramCream)
        let graphite = try self.theme(.bananaGramGraphite)
        let halloween = try self.theme(.bananaGramHalloween)
        XCTAssertEqual(cream.list.itemPrimaryTextColor.rgb, 0x3A3430)
        XCTAssertEqual(graphite.list.itemPrimaryTextColor.rgb, 0xEFEBE0)
        XCTAssertEqual(halloween.list.itemPrimaryTextColor.rgb, 0xF8F0E8)
    }

    func testNavigationPreservesSeparateControlTitleAndBadgeRoles() throws {
        for reference: PresentationBuiltinThemeReference in [.dayClassic, .day, .night, .bananaGramCream, .bananaGramGraphite, .bananaGramHalloween] {
            let theme = try self.theme(reference)
            let colors = theme.rootController.navigationBar
            let navigation = NavigationBarTheme(rootControllerTheme: theme)
            XCTAssertEqual(navigation.buttonColor.rgb, colors.buttonColor.rgb)
            XCTAssertEqual(navigation.disabledButtonColor, colors.disabledButtonColor)
            XCTAssertEqual(navigation.primaryTextColor.rgb, colors.primaryTextColor.rgb)
            XCTAssertEqual(navigation.badgeBackgroundColor.rgb, colors.badgeBackgroundColor.rgb)
            XCTAssertEqual(navigation.badgeTextColor.rgb, colors.badgeTextColor.rgb)
            let hiddenBadge = NavigationBarTheme(rootControllerTheme: theme, hideBadge: true)
            XCTAssertEqual(hiddenBadge.badgeBackgroundColor.alpha, 0.0)
            XCTAssertEqual(hiddenBadge.badgeTextColor.alpha, 0.0)
        }
    }

    func testSecondaryComposerAndMenusShareContentSurfaces() throws {
        let wallpapers: [TelegramWallpaper?] = [nil, .color(0x17384B)]
        for reference: PresentationBuiltinThemeReference in [.dayClassic, .day, .night] {
            for wallpaper in wallpapers {
                let theme = try self.theme(reference, wallpaper: wallpaper)
                let list = theme.list
                let media = theme.chat.inputMediaPanel
                XCTAssertEqual(media.backgroundColor, list.itemBlocksBackgroundColor)
                XCTAssertEqual(media.stickersBackgroundColor, media.gifsBackgroundColor)
                XCTAssertEqual(media.stickersSearchPrimaryColor, list.itemPrimaryTextColor)
                XCTAssertEqual(media.stickersSearchPlaceholderColor, list.itemSecondaryTextColor)
                XCTAssertEqual(theme.chat.inputButtonPanel.buttonTextColor, list.itemPrimaryTextColor)
                XCTAssertEqual(theme.actionSheet.inputTextColor, list.itemPrimaryTextColor)
                XCTAssertEqual(theme.actionSheet.inputPlaceholderColor, list.itemSecondaryTextColor)
                XCTAssertEqual(theme.actionSheet.itemBackgroundColor, list.itemBlocksBackgroundColor)
                XCTAssertEqual(theme.contextMenu.itemBackgroundColor, list.itemBlocksBackgroundColor)
                XCTAssertEqual(theme.contextMenu.primaryColor, list.itemPrimaryTextColor)
                XCTAssertEqual(theme.contextMenu.badgeFillColor, list.itemCheckColors.fillColor)
                XCTAssertEqual(theme.contextMenu.badgeForegroundColor, list.itemCheckColors.foregroundColor)
            }
        }
    }

    func testQuizMarksRemainLegibleForEveryResult() throws {
        let wallpapers: [TelegramWallpaper?] = [nil, .color(0x17384B)]
        for reference: PresentationBuiltinThemeReference in [.dayClassic, .day, .night] {
            for wallpaper in wallpapers {
                let theme = try self.theme(reference, wallpaper: wallpaper)
                for colors in [theme.chat.message.incoming.polls, theme.chat.message.outgoing.polls] {
                    XCTAssertEqual(colors.barIconForeground.alpha, 1.0)
                    for fill in [colors.bar, colors.barPositive, colors.barNegative] {
                        XCTAssertGreaterThanOrEqual(self.contrast(colors.barIconForeground, fill), 4.5)
                    }
                }
            }
        }
    }

    private func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var red: CGFloat = 0.0
            var green: CGFloat = 0.0
            var blue: CGFloat = 0.0
            var alpha: CGFloat = 0.0
            XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            XCTAssertEqual(alpha, 1.0)
            func linear(_ value: CGFloat) -> CGFloat {
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
        }
        let firstValue = luminance(first)
        let secondValue = luminance(second)
        return (max(firstValue, secondValue) + 0.05) / (min(firstValue, secondValue) + 0.05)
    }

}
