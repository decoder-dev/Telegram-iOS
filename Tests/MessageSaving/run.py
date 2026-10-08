"""Execute production persistence/import/export with temporary filesystem fixtures."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
store = (root / 'submodules/TelegramUIPreferences/Sources/MessageSavingStore.swift').read_text(encoding='utf-8')
for module in ['UIKit', 'TelegramCore', 'SwiftSignalKit']:
    store = store.replace('import ' + module + '\n', '')
# Exclude only platform lifecycle and settings wiring, not storage behavior.
start = store.index('    public static func installBridge()')
end = store.index('    public static func append(', start)
store = store[:start] + store[end:]
start = store.index('    public static func applySettings(')
end = store.index('    /// Total retained snapshots', start)
store = store[:start] + store[end:]
model = (root / 'submodules/TelegramCore/Sources/MessageSaving/MessageSavingBridge.swift').read_text(encoding='utf-8')
model = model[model.index('public enum MessageSavingKind'):model.index('public struct MessageSavingBridgeSettings')]
fixtures = r'''
import Foundation
public final class ValuePromise<T> {
    public init(_ value: T, ignoreRepeated: Bool) {}
    public func set(_ value: T) {}
}
enum MessageSavingBridge {
    static var savedAttachmentsDirectory = URL(fileURLWithPath: "/unused")
}
func requireSuccess(_ result: Result<Int, MessageSavingStore.ImportError>) {
    guard case .success = result else { preconditionFailure("Expected successful import") }
}
func requireFailure(_ result: Result<Int, MessageSavingStore.ImportError>) {
    guard case .failure = result else { preconditionFailure("Expected failed import") }
}
'''
tests = r'''
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let database = root.appendingPathComponent("db")
let media = root.appendingPathComponent("media")
try fm.createDirectory(at: media, withIntermediateDirectories: true)
MessageSavingBridge.savedAttachmentsDirectory = media
MessageSavingStore.resetForTesting(directory: database)
func record(_ id: String, _ path: String?) -> MessageSavingRecord {
    return MessageSavingRecord(id: id, accountPeerId: 1, peerId: 2, messageId: 3, namespace: 0, date: 1,
        authorId: nil, authorName: "Test", text: id, kind: .deleted, savedAt: 1, topicId: 0, mediaPath: path)
}
let originalFile = media.appendingPathComponent("original.bin")
try Data([1,2,3]).write(to: originalFile)
requireSuccess(MessageSavingStore.importJSONData(try JSONEncoder().encode([record("old", originalFile.path)]), replace: true))
let originalData = MessageSavingStore.exportJSONData()!
let bundle = root.appendingPathComponent("backup")
let attachments = bundle.appendingPathComponent("Saved Attachments")
try fm.createDirectory(at: attachments, withIntermediateDirectories: true)
try Data([4,5]).write(to: attachments.appendingPathComponent("good.bin"))
let incoming = [record("new1", "good.bin"), record("new2", "missing.bin")]
try JSONEncoder().encode(incoming).write(to: bundle.appendingPathComponent("records.json"))
// The first copy succeeds, the second fails: neither the database nor old bytes may change.
requireFailure(MessageSavingStore.importBundle(from: bundle, replace: true))
precondition(MessageSavingStore.exportJSONData()! == originalData)
precondition(try Data(contentsOf: originalFile) == Data([1,2,3]))
precondition(try fm.contentsOfDirectory(atPath: media.path) == ["original.bin"])

try Data([6,7]).write(to: attachments.appendingPathComponent("missing.bin"))
// Force database commit failure after ALL copies have succeeded.
let recordsFile = database.appendingPathComponent("records.json")
try fm.removeItem(at: recordsFile)
try fm.createDirectory(at: recordsFile, withIntermediateDirectories: false)
requireFailure(MessageSavingStore.importBundle(from: bundle, replace: true))
precondition(MessageSavingStore.exportJSONData()! == originalData)
precondition(try Data(contentsOf: originalFile) == Data([1,2,3]))
try fm.removeItem(at: recordsFile)
try originalData.write(to: recordsFile)
requireSuccess(MessageSavingStore.importBundle(from: bundle, replace: true))
precondition(MessageSavingStore.recordCount == 2)
precondition(fm.fileExists(atPath: originalFile.path))
let exported = MessageSavingStore.exportBundle()!
defer { try? fm.removeItem(at: exported) }
requireSuccess(MessageSavingStore.importBundle(from: exported, replace: true))
precondition(MessageSavingStore.recordCount == 2)
// Missing bytes must fail export, not yield a success-looking records-only folder.
requireSuccess(MessageSavingStore.importJSONData(try JSONEncoder().encode([record("missing", root.appendingPathComponent("absent").path)]), replace: true))
precondition(MessageSavingStore.exportBundle() == nil)
// Corruption is distinguishable from empty and is not overwritten by flush.
try Data("broken-json".utf8).write(to: recordsFile)
MessageSavingStore.resetForTesting(directory: database)
precondition(MessageSavingStore.historyReadFailed)
MessageSavingStore.flush()
precondition(try Data(contentsOf: recordsFile) == Data("broken-json".utf8))
try originalData.write(to: recordsFile)
MessageSavingStore.retryHistoryRead()
precondition(!MessageSavingStore.historyReadFailed && MessageSavingStore.recordCount == 1)
print("Partial copy, failed commit rollback, backup roundtrip, incomplete export and read retry: passed")
'''
# Swift precondition's autoclosure is nonthrowing; perform throwing reads first.
tests = tests.replace('precondition(try Data(contentsOf: originalFile) == Data([1,2,3]))',
                      'do { let bytes = try Data(contentsOf: originalFile); precondition(bytes == Data([1,2,3])) }')
tests = tests.replace('precondition(try fm.contentsOfDirectory(atPath: media.path) == ["original.bin"])',
                      'do { let files = try fm.contentsOfDirectory(atPath: media.path); precondition(files == ["original.bin"]) }')
tests = tests.replace('precondition(try Data(contentsOf: recordsFile) == Data("broken-json".utf8))',
                      'do { let bytes = try Data(contentsOf: recordsFile); precondition(bytes == Data("broken-json".utf8)) }')
with tempfile.TemporaryDirectory(prefix='message-saving-checks-') as tmp:
    path = pathlib.Path(tmp) / 'main.swift'
    path.write_text(fixtures + model + store + tests, encoding='utf-8')
    subprocess.run(['swift', str(path)], check=True)
