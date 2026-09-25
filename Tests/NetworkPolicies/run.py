import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramCore/Sources/State/AccountViewTracker.swift').read_text()
begin = source.index('private enum UnsupportedMediaRefreshPolicy {')
policy = source[begin:source.index('\n}', begin) + 2]
source = (root / 'submodules/TelegramCore/Sources/Settings/ProxySettings.swift').read_text()
begin = source.index('    public func matchesConnectedProxyAddress(')
method = source[begin:source.index('\n    }', begin) + 6]
fixture = '''import Foundation
struct Route { var ip: String }
public struct ProxyServerSettings { var mtProxySettings: Route? }
extension ProxyServerSettings {
''' + method + '\n}\n'
tests = '''
let now: Int32 = 100_000
precondition(UnsupportedMediaRefreshPolicy.needsUpdate(previous: nil, now: now))
precondition(!UnsupportedMediaRefreshPolicy.needsUpdate(previous: now, now: now + 30))
precondition(!UnsupportedMediaRefreshPolicy.needsUpdate(previous: now, now: now + 35999))
precondition(UnsupportedMediaRefreshPolicy.needsUpdate(previous: now, now: now + 36000))
let failure = UnsupportedMediaRefreshPolicy.failedTimestamp(now: now)
precondition(!UnsupportedMediaRefreshPolicy.needsUpdate(previous: failure, now: now + 29))
precondition(UnsupportedMediaRefreshPolicy.needsUpdate(previous: failure, now: now + 30))
precondition(UnsupportedMediaRefreshPolicy.needsUpdate(previous: now, now: now - 1))
precondition(UnsupportedMediaRefreshPolicy.needsUpdate(previous: Int32.min, now: Int32.max))
let preparing = ProxyServerSettings(mtProxySettings: nil)
precondition(!preparing.matchesConnectedProxyAddress("127.0.0.1"))
let running = ProxyServerSettings(mtProxySettings: Route(ip: "127.0.0.1"))
precondition(running.matchesConnectedProxyAddress("127.0.0.1"))
precondition(!running.matchesConnectedProxyAddress("external-profile.example"))
precondition(!running.matchesConnectedProxyAddress(nil))
print("Unsupported-media retry timing and managed connection route: passed")
'''
with tempfile.TemporaryDirectory(prefix='telegram-network-policies-') as tmp:
    file = pathlib.Path(tmp) / 'main.swift'
    file.write_text(fixture + policy + tests)
    subprocess.run(['swift', str(file)], check=True)
