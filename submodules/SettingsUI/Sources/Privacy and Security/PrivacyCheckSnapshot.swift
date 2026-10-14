import Foundation
import CryptoKit
import TelegramCore

// Persist only fingerprints of rule sets, scoped to the local account record.
// No names, phone numbers, session details or raw exception peer IDs are stored.
struct PrivacyCheckSnapshot: Codable {
    let version: Int
    let fields: [String: String]
}

enum PrivacyCheckComparison: Equatable {
    case firstCheck
    case unchanged
    case changed([PrivacyCheckSubject])
    case unavailable
}

private func privacyCheckRuleFingerprint(_ rule: SelectivePrivacySettings) -> String {
    let value: String
    switch rule {
    case let .enableEveryone(disableFor):
        value = "everyone|" + disableFor.keys.map { $0.toInt64() }.sorted().map(String.init).joined(separator: ",")
    case let .enableContacts(enableFor, disableFor, premium, bots):
        let allowed = enableFor.keys.map { $0.toInt64() }.sorted().map(String.init).joined(separator: ",")
        let denied = disableFor.keys.map { $0.toInt64() }.sorted().map(String.init).joined(separator: ",")
        value = ["contacts", allowed, denied, String(premium), String(bots)].joined(separator: "|")
    case let .disableEveryone(enableFor, closeFriends, premium, bots):
        let allowed = enableFor.keys.map { $0.toInt64() }.sorted().map(String.init).joined(separator: ",")
        value = ["selected", allowed, String(closeFriends), String(premium), String(bots)].joined(separator: "|")
    }
    return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

func privacyCheckSnapshotFields(settings: AccountPrivacySettings?, twoStepEnabled: Bool?) -> [String: String] {
    var fields: [String: String] = [:]
    if let settings {
        let rules: [(PrivacyCheckSubject, SelectivePrivacySettings)] = [
            (.phoneNumber, settings.phoneNumber), (.forwards, settings.forwards),
            (.voiceCalls, settings.voiceCalls), (.callP2P, settings.voiceCallsP2P),
            (.presence, settings.presence), (.profilePhoto, settings.profilePhoto),
            (.bio, settings.bio), (.birthday, settings.birthday)
        ]
        for (subject, rule) in rules {
            fields[String(subject.rawValue)] = privacyCheckRuleFingerprint(rule)
        }
        fields[String(PrivacyCheckSubject.phoneDiscovery.rawValue)] = settings.phoneDiscoveryEnabled ? "1" : "0"
    }
    if let twoStepEnabled {
        fields[String(PrivacyCheckSubject.twoStepVerification.rawValue)] = twoStepEnabled ? "1" : "0"
    }
    return fields
}

func privacyCheckCompareAndStore(accountId: Int64, fields: [String: String], defaults: UserDefaults = .standard) -> PrivacyCheckComparison {
    guard !fields.isEmpty else { return .unavailable }
    let key = "PrivacyCheckSnapshot.v1.\(accountId)"
    let previous = defaults.data(forKey: key).flatMap { data -> PrivacyCheckSnapshot? in
        guard data.count <= 16384 else { return nil }
        return try? JSONDecoder().decode(PrivacyCheckSnapshot.self, from: data)
    }
    let baseline = previous?.version == 1 ? previous : nil
    let changed = PrivacyCheckSubject.allCases.filter { subject in
        let field = String(subject.rawValue)
        guard let old = baseline?.fields[field], let current = fields[field] else { return false }
        return old != current
    }
    // A failed sub-check must not erase the last successful baseline for it.
    var merged = baseline?.fields ?? [:]
    for (key, value) in fields { merged[key] = value }
    if let data = try? JSONEncoder().encode(PrivacyCheckSnapshot(version: 1, fields: merged)) {
        defaults.set(data, forKey: key)
    }
    guard let baseline, fields.keys.contains(where: { baseline.fields[$0] != nil }) else { return .firstCheck }
    return changed.isEmpty ? .unchanged : .changed(changed)
}
