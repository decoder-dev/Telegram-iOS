import Foundation
import SwiftSignalKit

/// Extras ▸ Profile ▸ hide the decorations drawn next to a name: emoji statuses and the Premium star
/// (`hidesPremiumStatus`), and verification checkmarks and verification icons (`hidesVerification`).
///
/// Display only. Peer data, and every trust decision that reads `isVerified`, keep the real values;
/// display sites ask here before drawing. The account's own status is never hidden. Projected from
/// `ForkExtrasSettings` by `SharedAccountContext`.
public enum BananaIdentityBadges {
    private struct State: Equatable {
        var hidesPremiumStatuses = false
        var hidesVerification = false
    }

    private static let state = Atomic<State>(value: State())

    public static func update(hidesPremiumStatuses: Bool, hidesVerification: Bool) {
        let _ = state.swap(State(hidesPremiumStatuses: hidesPremiumStatuses, hidesVerification: hidesVerification))
    }

    public static func hidesPremiumStatus(peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
        return peerId != accountPeerId && state.with { $0.hidesPremiumStatuses }
    }

    public static var hidesVerification: Bool {
        return state.with { $0.hidesVerification }
    }
}
