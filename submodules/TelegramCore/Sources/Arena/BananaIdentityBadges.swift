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

public enum BananaLocalVerificationBadge: Int32, CaseIterable {
    case none = 0, major, hold, developer

    public var title: String {
        switch self {
        case .none: return ""
        case .major: return "Major"
        case .hold: return "Hold"
        case .developer: return "Developer"
        }
    }

    public var iconFileId: Int64? {
        switch self {
        case .none: return nil
        case .major: return 5909078961467431777
        case .hold: return 5913729775393840687
        case .developer: return 5800995289124838177
        }
    }
}

/// Decorations keyed by account record, including separate records on test or custom servers.
/// Renderers must additionally restrict these to that account's own profile or Settings header.
public enum BananaLocalVerificationBadges {
    private static let values = Atomic<[Int64: Int32]>(value: [:])

    public static func update(_ badges: [Int64: Int32]) {
        let _ = values.swap(badges)
    }

    public static func badge(accountId: Int64) -> BananaLocalVerificationBadge {
        return values.with { BananaLocalVerificationBadge(rawValue: $0[accountId] ?? 0) ?? .none }
    }
}
