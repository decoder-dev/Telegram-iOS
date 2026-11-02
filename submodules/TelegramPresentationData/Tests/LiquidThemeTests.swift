import Foundation
import UIKit
import XCTest
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences

final class LiquidThemeTests: XCTestCase {
    private var directory: URL!
    private var mediaBox: MediaBox!

    override func setUpWithError() throws {
        try super.setUpWithError()
        self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        self.mediaBox = MediaBox(basePath: self.directory.path, isMainProcess: false)
    }

    override func tearDownWithError() throws {
        self.mediaBox = nil
        if let directory = self.directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        self.directory = nil
        try super.tearDownWithError()
    }

    private func theme(_ reference: PresentationBuiltinThemeReference, accent: UIColor? = nil, bubbles: [UInt32] = [], wallpaper: TelegramWallpaper? = nil) throws -> PresentationTheme {
        return try XCTUnwrap(makePresentationTheme(mediaBox: self.mediaBox, themeReference: .builtin(reference), accentColor: accent, bubbleColors: bubbles, wallpaper: wallpaper))
    }

    func testDefaultMessageColorsSurviveTheFullThemeFactory() throws {
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
            let theme = try self.theme(reference)
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

    func testBrandedThemesKeepTheirPalettes() throws {
        let cream = try self.theme(.bananaGramCream)
        let graphite = try self.theme(.bananaGramGraphite)
        let halloween = try self.theme(.bananaGramHalloween)
        XCTAssertEqual(cream.list.itemPrimaryTextColor.rgb, 0x3A3430)
        XCTAssertEqual(graphite.list.itemPrimaryTextColor.rgb, 0xEFEBE0)
        XCTAssertEqual(halloween.list.itemPrimaryTextColor.rgb, 0xF8F0E8)
    }
}
