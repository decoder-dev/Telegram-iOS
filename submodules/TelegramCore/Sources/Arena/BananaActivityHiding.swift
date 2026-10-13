import Foundation
import SwiftSignalKit

/// Extras ▸ Ghost mode ▸ hide one kind of outgoing activity ("typing…", "recording voice…", "sending a file…")
/// while the others still go out. Independent of the all-or-nothing Don't Send Typing switch, which still wins.
public enum BananaActivityHiding {
    private struct State: Equatable {
        var text = false
        var voice = false
        var files = false
    }

    private static let state = Atomic<State>(value: State())

    public static func update(text: Bool, voice: Bool, files: Bool) {
        let _ = state.swap(State(text: text, voice: voice, files: files))
    }

    public static func hides(_ activity: PeerInputActivity) -> Bool {
        let current = state.with { $0 }
        switch activity {
        case .typingText:
            return current.text
        case .recordingVoice, .recordingInstantVideo:
            return current.voice
        case .uploadingFile, .uploadingPhoto, .uploadingVideo, .uploadingInstantVideo:
            return current.files
        default:
            return false
        }
    }
}
