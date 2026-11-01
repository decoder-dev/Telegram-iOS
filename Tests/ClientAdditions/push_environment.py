"""Compile the production APNs environment selection against profile values."""
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'submodules/TelegramUI/Sources/PushNotificationEnvironment.swift').read_text()
TELEGRAM_BUILD = (ROOT / 'Telegram/BUILD').read_text()
start = SOURCE.index('enum PushNotificationEnvironment {')
implementation = SOURCE[start:SOURCE.index('\n}', start) + 2]
plist_start = TELEGRAM_BUILD.index('name = "TelegramInfoPlist"')
info_plist = TELEGRAM_BUILD[plist_start:]
assert '<key>TelegramAPNSEnvironment</key>' in info_plist
assert '<string>{telegram_aps_environment}</string>' in info_plist
assert 'telegram_aps_environment = telegram_aps_environment' in info_plist
assert 'PushNotificationEnvironment.tokenEnvironment' in (ROOT / 'submodules/TelegramUI/Sources/AppDelegate.swift').read_text()
assert 'PushNotificationEnvironment.isSandbox' in (ROOT / 'submodules/TelegramUI/Sources/SharedAccountContext.swift').read_text()

checks = r'''
precondition(PushNotificationEnvironment.isSandbox(environment: "development", debugFallback: false))
precondition(!PushNotificationEnvironment.isSandbox(environment: "production", debugFallback: true))
precondition(PushNotificationEnvironment.isSandbox(environment: nil, debugFallback: true))
precondition(!PushNotificationEnvironment.isSandbox(environment: nil, debugFallback: false))
precondition(PushNotificationEnvironment.tokenEnvironment == (PushNotificationEnvironment.isSandbox ? "sandbox" : "production"))
print("APNs environment follows the provisioning profile and only falls back to the build mode when unspecified")
'''

with tempfile.TemporaryDirectory(prefix='push-environment-') as directory:
    source = pathlib.Path(directory) / 'main.swift'
    binary = pathlib.Path(directory) / 'checks'
    source.write_text('import Foundation\n' + implementation + '\n' + checks)
    swiftc = shutil.which('swiftc')
    if swiftc is None:
        print('APNs environment source wiring passed; Swift compiler unavailable for local execution')
        raise SystemExit(0)
    subprocess.run([swiftc, '-warnings-as-errors', str(source), '-o', str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
