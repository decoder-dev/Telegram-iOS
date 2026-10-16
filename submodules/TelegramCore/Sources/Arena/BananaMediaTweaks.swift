import Foundation
import SwiftSignalKit

/// Media, sticker and playback preferences ported from Donutgram (accelerateUpload, infiniteRecentStickers,
/// onlyAddedStickers, autoPause, doubleTapSeekSeconds, staticRoundVideoZoom, stickerShape). A runtime projection of
/// `ForkExtrasSettings`, set by `SharedAccountContext`; every default keeps Telegram's own behaviour.
public enum BananaMediaTweaks {
    public struct State: Equatable {
        /// Upload a file over 8 parallel parts instead of 3. Secret-chat (encrypted) uploads keep 3.
        public var accelerateUpload: Bool = false
        /// Do not trim the recent stickers list to Telegram's 20.
        public var infiniteRecentStickers: Bool = false
        /// The sticker keyboard shows no trending packs and no group sticker pack, only installed ones.
        public var onlyAddedStickers: Bool = false
        /// Pause playing videos, voice messages and round videos when the app leaves the foreground.
        public var autoPauseMediaInBackground: Bool = false
        /// The step of a double-tap seek in the video player; 0 turns double-tap seeking off.
        public var doubleTapSeekSeconds: Int32 = 15
        /// A pinch zoom in the round video camera stays where the fingers left it.
        public var staticRoundVideoZoom: Bool = false
        /// 0: stock, 1: rounded, 2: more rounded.
        public var stickerShape: Int32 = 0

        public init(accelerateUpload: Bool = false, infiniteRecentStickers: Bool = false, onlyAddedStickers: Bool = false, autoPauseMediaInBackground: Bool = false, doubleTapSeekSeconds: Int32 = 15, staticRoundVideoZoom: Bool = false, stickerShape: Int32 = 0) {
            self.accelerateUpload = accelerateUpload
            self.infiniteRecentStickers = infiniteRecentStickers
            self.onlyAddedStickers = onlyAddedStickers
            self.autoPauseMediaInBackground = autoPauseMediaInBackground
            self.doubleTapSeekSeconds = doubleTapSeekSeconds
            self.staticRoundVideoZoom = staticRoundVideoZoom
            self.stickerShape = stickerShape
        }
    }

    private static let state = Atomic<State>(value: State())

    public static var current: State {
        return state.with { $0 }
    }

    public static func update(_ next: State) {
        let _ = state.swap(next)
    }

    public static var accelerateUpload: Bool {
        return state.with { $0.accelerateUpload }
    }

    /// The `removeTailIfCountExceeds` value for the recent stickers list.
    public static var recentStickersLimit: Int? {
        return state.with { $0.infiniteRecentStickers } ? nil : 20
    }

    public static var onlyAddedStickers: Bool {
        return state.with { $0.onlyAddedStickers }
    }

    public static var autoPauseMediaInBackground: Bool {
        return state.with { $0.autoPauseMediaInBackground }
    }

    public static var doubleTapSeekSeconds: Int32 {
        return state.with { $0.doubleTapSeekSeconds }
    }

    public static var staticRoundVideoZoom: Bool {
        return state.with { $0.staticRoundVideoZoom }
    }

    public static var stickerShape: Int32 {
        return state.with { $0.stickerShape }
    }

    /// The corner radius drawn on a sticker in chat for the chosen shape.
    public static var stickerCornerRadius: Double {
        switch self.stickerShape {
        case 1: return 12.0
        case 2: return 22.0
        default: return 0.0
        }
    }
}
