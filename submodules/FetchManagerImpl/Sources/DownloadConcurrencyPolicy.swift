import Foundation

struct DownloadCandidate<Id: Hashable> {
    let id: Id
    let datacenterId: Int
    let size: Int64?
    let userInitiated: Bool
}

/// Admission only: changing this policy never discards a transfer's downloaded ranges.
enum DownloadConcurrencyPolicy {
    private enum QueueKey: Hashable {
        case prefetch
        case user(datacenterId: Int, large: Bool)

        init<Id: Hashable>(_ candidate: DownloadCandidate<Id>) {
            if candidate.userInitiated {
                // Unknown sizes use the smaller concurrency budget until their size is known.
                self = .user(datacenterId: candidate.datacenterId, large: candidate.size.map { $0 > 20 * 1024 * 1024 } ?? true)
            } else {
                self = .prefetch
            }
        }

        var limit: Int {
            switch self {
            case .prefetch: return 1
            case .user(_, let large): return large ? 2 : 5
            }
        }
    }

    /// `candidates` is already in priority order and contains only unpaused, still-referenced entries.
    static func additionalIds<Id: Hashable>(candidates: [DownloadCandidate<Id>], active: [DownloadCandidate<Id>]) -> [Id] {
        var counts: [QueueKey: Int] = [:]
        var activeIds = Set<Id>()
        for candidate in active where activeIds.insert(candidate.id).inserted {
            counts[QueueKey(candidate), default: 0] += 1
        }
        var selected: [Id] = []
        var seen = activeIds
        for candidate in candidates where seen.insert(candidate.id).inserted {
            let key = QueueKey(candidate)
            if counts[key, default: 0] < key.limit {
                counts[key, default: 0] += 1
                selected.append(candidate.id)
            }
        }
        return selected
    }
}
