"""Compile the production session state machine in isolation from the iOS app."""
import pathlib
import subprocess
import tempfile
import json

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramUIPreferences/Sources/ChatArchiveSettings.swift').read_text()
session = source[source.index('public enum ArchiveFolderPresentation'):source.index('public func updateChatArchiveSettings')]
with tempfile.TemporaryDirectory(prefix='archive-session-') as directory:
    package = pathlib.Path(directory)
    tests = package / 'Tests/ArchiveSessionTests'
    tests.mkdir(parents=True)
    dependency = json.dumps(str(root / 'submodules/SSignalKit'))
    (package / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ArchiveSessionTests", platforms: [.macOS(.v10_15)], dependencies: [.package(path: PATH)], targets: [.testTarget(name: "ArchiveSessionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")])])
'''.replace('PATH', dependency))
    (tests / 'Session.swift').write_text('''import Foundation
import SwiftSignalKit
public enum EnginePeer {
    public struct Id: Hashable {
        let value: Int64
        public init(_ value: Int64) { self.value = value }
        public func toInt64() -> Int64 { value }
    }
}
''' + session)
    (tests / 'SessionTests.swift').write_text((root / 'Tests/ArchiveLock/SessionTests.swift').read_text())
    subprocess.run(['swift', 'test', '--package-path', directory], check=True)
