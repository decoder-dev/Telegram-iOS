"""Verify wallet-state RPC diagnostics retain codes without retaining sensitive error text."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Wallet/Wallet.swift').read_text()
start = source.index('public enum WalletGetStateError:')
end = source.index('public enum WalletGetUserAddressesError:', start)
fixture = 'import Foundation\n' + source[start:end] + r'''
let cases: [(Int32, String, String)] = [
    (400, "METHOD_INVALID", "unsupported"),
    (400, "METHOD_NOT_AVAILABLE", "unsupported"),
    (400, "API_LAYER_INVALID", "unsupported"),
    (401, "AUTH_KEY_UNREGISTERED", "unauthorized"),
    (420, "FLOOD_WAIT_123", "rateLimited"),
    (500, "INTERNAL", "server"),
    (503, "TIMEOUT", "server"),
    (-1000, "network", "other"),
    (400, "secret recovery phrase token address", "other"),
    (400, "METHOD_INVALID\nsecret", "other")
]
for (code, description, kind) in cases {
    let error = WalletGetStateError(rpcCode: code, rpcDescription: description)
    let nsError = error as NSError
    precondition(nsError.code == Int(code))
    precondition(nsError.domain == "TelegramCore.WalletGetStateError")
    precondition(error.diagnosticKind == kind)
    precondition(nsError.userInfo.isEmpty)
    precondition(!String(reflecting: error).contains(description))
}
precondition((WalletGetStateError.generic as NSError).code == 0)
precondition(WalletGetStateError.generic.diagnosticKind == "generic")
print("Wallet RPC codes, bounded categories and sensitive-text redaction passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / 'main.swift'
    path.write_text(fixture)
    subprocess.run(['swift', str(path)], check=True, timeout=120)
logger = (root / 'submodules/WalletContext/Sources/WalletLogger.swift').read_text()
assert 'error.diagnosticKind' in logger
