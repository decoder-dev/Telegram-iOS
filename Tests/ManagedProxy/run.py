import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
original = (root / 'submodules/TelegramCore/Sources/Network/ProxyServersStatuses.swift').read_text()
for module in ['MtProtoKit', 'WebProxyTransport', 'TelegramVLESS']:
    original = original.replace('import ' + module + '\n', '')
with tempfile.TemporaryDirectory(prefix='telegram-managed-proxy-') as tmp:
    package = pathlib.Path(tmp)
    sources = package / 'Sources/Checks'
    sources.mkdir(parents=True)
    (sources / 'ProxyServersStatuses.swift').write_text(original)
    for name in ['Fixtures.swift', 'main.swift']:
        (sources / name).write_text((root / 'Tests/ManagedProxy' / name).read_text())
    dependency = json.dumps(str(root / 'submodules/SSignalKit'))
    (package / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "ManagedProxyChecks", platforms: [.macOS(.v10_15)],
dependencies: [.package(path: ''' + dependency + ''')],
targets: [.executableTarget(name: "Checks", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")])])
''')
    subprocess.run(['swift', 'run', '--package-path', tmp, 'Checks'], check=True)
