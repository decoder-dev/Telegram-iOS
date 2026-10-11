"""Execute both existing passcode encodings and new credential tags."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
source = (ROOT / 'submodules/TelegramCore/Sources/AccountManager/AccountManagerMetadataTable.swift').read_text(encoding='utf-8')
enum = source[source.index('public enum PostboxAccessChallengeData:'):source.index('public struct AuthAccountRecord<')]
fixture = '''import Foundation
public protocol PostboxCoding { init(decoder: PostboxDecoder); func encode(_ encoder: PostboxEncoder) }
public final class PostboxDecoder {
    let values: [String: Any]
    init(_ values: [String: Any]) { self.values = values }
    public func decodeInt32ForKey(_ key: String, orElse: Int32) -> Int32 { values[key] as? Int32 ?? orElse }
    public func decodeOptionalStringForKey(_ key: String) -> String? { values[key] as? String }
    public func decodeStringForKey(_ key: String, orElse: String) -> String { values[key] as? String ?? orElse }
}
public final class PostboxEncoder {
    var values: [String: Any] = [:]
    public func encodeInt32(_ value: Int32, forKey: String) { values[forKey] = value }
    public func encodeString(_ value: String, forKey: String) { values[forKey] = value }
}
''' + enum + '''
let numeric = PostboxAccessChallengeData.numericalPasswordHash(value: "digest", digits: 6)
let alpha = PostboxAccessChallengeData.plaintextPasswordHash(value: "alpha")
let secured = PostboxAccessChallengeData.secured(id: "credential", kind: .digits6)
precondition(PostboxAccessChallengeData(decoder: PostboxDecoder(["r": Int32(3), "t": "digest", "d": Int32(6)])) == numeric)
precondition(PostboxAccessChallengeData(decoder: PostboxDecoder(["r": Int32(4), "t": "alpha"])) == alpha)
precondition(PostboxAccessChallengeData(decoder: PostboxDecoder(["r": Int32(3), "id": "credential", "kind": "digits6"])) == secured)
for value in [numeric, alpha, secured, .none, .numericalPassword(value: "123456"), .plaintextPassword(value: "abc")] {
    let encoded = PostboxEncoder()
    value.encode(encoded)
    precondition(PostboxAccessChallengeData(decoder: PostboxDecoder(encoded.values)) == value)
    if value == secured { precondition(encoded.values["r"] as? Int32 == 5) }
    let json = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(PostboxAccessChallengeData.self, from: json)
    precondition(decoded == value)
}
let unknown = PostboxAccessChallengeData(decoder: PostboxDecoder(["r": Int32(999)]))
precondition(unknown != .none, "Unknown challenge must fail closed")
print("PASS legacy Postbox tags, official credential import, fork credential tag, Codable round trips")
'''
with tempfile.TemporaryDirectory() as temporary:
    path = pathlib.Path(temporary)
    (path / 'main.swift').write_text(fixture, encoding='utf-8')
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'test')], check=True, timeout=60)
    subprocess.run([str(path / 'test')], check=True, timeout=15)
