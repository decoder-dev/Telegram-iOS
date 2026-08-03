# Sideloading a CI-built Telegram IPA

GitHub Actions builds a **fake-signed** `release_arm64` IPA using
`build-system/fake-codesigning`. That signature is only for Bazel packaging —
it will **not** launch on a real iPhone by itself. You must re-sign with your
Apple ID (Sideloadly / AltStore / SideStore).

Official upstream release IPAs are also **not** meant to be functional after
re-sign ([#1120](https://github.com/TelegramMessenger/Telegram-iOS/issues/1120),
[#1136](https://github.com/TelegramMessenger/Telegram-iOS/issues/1136)).
Build from this repo’s Actions artifact instead.

## What CI produces

| Setting | Value |
|--------|--------|
| Configuration | `release_arm64` |
| Codesigning | `build-system/fake-codesigning` |
| Bundle ID (build-time) | `ph.telegra.Telegraph` |
| Team ID (build-time) | `C67CF9S4VU` |
| Extensions | disabled (`--disableExtensions`) |
| Siri / iCloud | off |

Optional repo secrets (API only — do **not** override bundle/team unless you
also supply real Apple profiles):

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

## Install with Sideloadly (recommended)

1. Uninstall App Store Telegram if you keep the default bundle ID, **or** use
   Sideloadly → Advanced Options → **Change Bundle ID** to something unique
   (recommended so both can coexist).
2. Open the Release IPA in Sideloadly, sign with your Apple ID, install.
3. On the iPhone: Settings → General → VPN & Device Management → trust your
   developer certificate.
4. Free Apple IDs expire ~7 days; refresh via Sideloadly / AltStore.

If the app opens to a **black screen**, the usual causes are: wrong/re-signed
official release IPA, conflicting App Store install with the same bundle ID,
or missing trust for the signing certificate. Rebuild from this workflow and
re-sign with a changed bundle ID.

## AltStore / SideStore

Same IPA works. Prefer builds with extensions disabled (this CI already does).
If an installer complains about PlugIns, strip `Payload/*.app/PlugIns` before
signing — not needed for this workflow’s artifact.

## What CI cannot do without your Apple certs

- Produce a universally installable IPA
- Keep push / iCloud / Siri / Associated Domains working under a personal free ID
- Sign for arbitrary users’ devices — final signing is always local
