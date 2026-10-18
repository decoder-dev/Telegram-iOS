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

/// Display-only labels belong to each signed-in account, not to its server-side peer flags.
public enum BananaVisualLabel: Int32, CaseIterable {
    case none = 0, scam, fake, support, bot
    public var badgeText: String {
        switch self {
        case .none: return ""
        case .scam: return "SCAM"
        case .fake: return "FAKE"
        case .support: return "SUPPORT"
        case .bot: return "BOT"
        }
    }
}

public enum BananaVisualLabels {
    private static let labels = Atomic<[Int64: Int32]>(value: [:])
    public static func update(_ values: [Int64: Int32]) { let _ = labels.swap(values) }
    public static func label(accountId: Int64) -> BananaVisualLabel {
        return labels.with { BananaVisualLabel(rawValue: $0[accountId] ?? 0) ?? .none }
    }
}
