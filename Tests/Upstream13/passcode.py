"""Execute production legacy migration and real file locking with fault injection."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
source = (ROOT / 'submodules/PasscodeCore/Sources/Passcode.swift').read_text(encoding='utf-8')

def method(marker):
    start = source.index(marker)
    brace = source.index('{', start)
    end, depth = brace + 1, 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

fixture = '''import Foundation
import Darwin
enum PasscodeKind { case digits6 }
typealias PasscodeCredentialReference = String
enum PasscodeError: Error { case unavailable, corrupted, invalidCode, cooldown(Int) }
enum PasscodeSession { static func invalidateAll() {} }
struct Record { var managedPasscode = false; var unprotectedKey: Data? = Data([1]); var revision: UInt64 = 0 }
struct Attempts: Codable { var count = 0; var deadline: Double = 0 }
final class Storage {
    var data: Data?
    var fail = false
    func write(_ data: Data, account: String, biometric: Bool) throws {
        if fail { throw PasscodeError.unavailable }; self.data = data
    }
    func remove(_ account: String) throws {
        if fail { throw PasscodeError.unavailable }; self.data = nil
    }
}
final class Store {
    let mutex = NSRecursiveLock()
    let lockPath: String?
    let storage = Storage()
    var record: Record?
    var failSave = false
    var now = 100.0
    init(_ path: String) { lockPath = path }
    func clock() -> (uptime: Double, unused: Bool) { (now, false) }
    func load() throws -> Record? { record }
    func existingOrCreate() throws -> Record { record ?? Record() }
    func attempts() throws -> Attempts { try storage.data.map { try JSONDecoder().decode(Attempts.self, from: $0) } ?? Attempts() }
    func reference(_ record: Record) -> String { "credential" }
    func wrap(code: String, kind: PasscodeKind, key: Data, record: inout Record) throws { }
    func save(_ record: Record) throws {
        if failSave { throw PasscodeError.unavailable }; self.record = record
    }
''' + '\n'.join(method(marker) for marker in [
    '    private func serialized<T>', '    public func migrateLegacy(',
    '    private func migrateLegacyLocked(', '    public func migrateVerifiedLegacy('
]).replace('public func ', 'func ') + '''
}
let store = Store(CommandLine.arguments[1])
for attempt in 1...6 {
    do { _ = try store.migrateVerifiedLegacy(code: "wrong", kind: .digits6, verifyLegacy: { false }); fatalError("Wrong code accepted") }
    catch PasscodeError.invalidCode { }
    precondition(try store.attempts().count == attempt)
}
var called = false
do { _ = try store.migrateVerifiedLegacy(code: "123456", kind: .digits6, verifyLegacy: { called = true; return true }); fatalError("Cooldown bypassed") }
catch PasscodeError.cooldown(60) { }
precondition(!called && store.record == nil)
store.now += 61
store.failSave = true
do { _ = try store.migrateVerifiedLegacy(code: "123456", kind: .digits6, verifyLegacy: { true }); fatalError("Storage failure accepted") }
catch PasscodeError.unavailable { }
precondition(store.record == nil)
precondition(try store.attempts().count == 6)
store.failSave = false
let reference = try store.migrateVerifiedLegacy(code: "123456", kind: .digits6, verifyLegacy: { true })
precondition(reference == "credential" && store.record?.managedPasscode == true && store.storage.data == nil)
called = false
_ = try store.migrateVerifiedLegacy(code: "wrong", kind: .digits6, verifyLegacy: { called = true; return false })
precondition(!called, "Managed credential must stay authoritative; normal verify follows")
print("PASS real cross-process lock, cooldown, save failure, migration and authority")
'''
# Swift precondition takes a non-throwing autoclosure.
fixture = fixture.replace('precondition(try store.attempts().count == attempt)', 'let count = try store.attempts().count; precondition(count == attempt)').replace('precondition(try store.attempts().count == 6)', 'let count = try store.attempts().count; precondition(count == 6)')
with tempfile.TemporaryDirectory() as temporary:
    path = pathlib.Path(temporary)
    (path / 'main.swift').write_text(fixture, encoding='utf-8')
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'test')], check=True, timeout=60)
    subprocess.run([str(path / 'test'), str(path / 'credential.lock')], check=True, timeout=15)
