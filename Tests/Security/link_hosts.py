"""Compile the production link-host helpers and check case and trailing-dot normalization.

Foundation keeps both (`HTTPS://T.ME.` has scheme `HTTPS` and host `T.ME.`). The in-app opener
used to compare that raw host to `t.me`, so the link left the app.
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

CHECKS = r'''
precondition(normalizedLinkHost("T.ME.") == "t.me")
precondition(normalizedLinkHost("Telegram.DOG") == "telegram.dog")
precondition(normalizedLinkHost("t.me..") == "t.me.")
precondition(isExactTelegramMeHost("T.ME"))
precondition(isExactTelegramMeHost("t.me."))
precondition(isExactTelegramMeHost("Telegram.me"))
precondition(!isExactTelegramMeHost("durov.t.me"))
precondition(!isExactTelegramMeHost("t.me.evil.org"))
precondition(!isExactTelegramMeHost("nottelegram.me"))
precondition(isTelegramLinkUrl("HTTPS://T.ME/durov"))
precondition(isTelegramLinkUrl("https://t.me./durov"))
precondition(isTelegramLinkUrl("https://Telegram.DOG/joinchat/AbC"))
precondition(isTelegramLinkUrl("https://durov.t.me/start"))
precondition(isTelegramLinkUrl("TG://resolve?domain=durov"))
precondition(!isTelegramLinkUrl("https://t.me.evil.org/durov"))
precondition(!isTelegramLinkUrl("https://nottelegram.me/durov"))
precondition(!isTelegramLinkUrl("https://evil.org"))
precondition(isTelegramDeepLinkScheme("TG"))
precondition(!isTelegramDeepLinkScheme("https"))
precondition(!isTelegramDeepLinkScheme(nil))
precondition(isWebUrlScheme("HTTPS"))
precondition(!isWebUrlScheme("TG"))
precondition(!isWebUrlScheme(nil))
print("Link host case, trailing dot, subdomain and scheme checks passed")
'''


def main():
    with tempfile.TemporaryDirectory(prefix="telegram-link-hosts-") as directory:
        path = pathlib.Path(directory)
        # One module: the production `import UrlEscaping` is the module boundary, not a second copy of the code.
        whitelist = (ROOT / "submodules/UrlWhitelist/Sources/UrlWhitelist.swift").read_text(encoding="utf-8")
        whitelist = whitelist.replace("import Foundation\n", "import Foundation\nimport CoreFoundation\n", 1)
        whitelist = whitelist.replace("import UrlEscaping\n", "", 1)
        (path / "UrlWhitelist.swift").write_text(whitelist, encoding="utf-8")
        (path / "main.swift").write_text(CHECKS, encoding="utf-8")
        sources = [
            ROOT / "submodules/UrlEscaping/Sources/Punycode.swift",
            ROOT / "submodules/UrlEscaping/Sources/UrlEscaping.swift",
            path / "UrlWhitelist.swift",
            path / "main.swift",
        ]
        subprocess.run(
            ["swiftc", "-warnings-as-errors", "-o", str(path / "checks")] + [str(source) for source in sources],
            check=True,
            timeout=180,
        )
        subprocess.run([str(path / "checks")], check=True, timeout=30)


if __name__ == "__main__":
    main()
