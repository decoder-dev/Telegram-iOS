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

## Why E-Sign / free certs used to black-screen

Telegram stores its database under an **App Group** (`group.<bundleId>`).
Free Apple IDs and many E-Sign certificates **do not grant App Groups**, so
`containerURL(...)` returns `nil` and stock Telegram stops at **Error 2**
(often looks like a blank/black screen).

This fork falls back to the app’s Documents directory when the App Group is
missing, so the **main app can boot after E-Sign**. Share extension / NSE /
widgets still need a real App Group (paid developer) if you enable them later.

## Install with E-Sign

1. Download `Telegram-*-sideload.ipa` from Releases (not an App Store IPA).
2. In E-Sign: import the IPA → set a **new Bundle ID** (e.g. `com.you.telegram`)
   so it doesn’t clash with App Store Telegram.
3. Prefer removing / skipping entitlements your cert can’t carry (Push, Associated
   Domains, Apple Pay, etc.). App Groups are optional with this fork’s fallback.
4. Sign → install → trust the certificate on the device.
5. Delete any previous install with the same Bundle ID before retrying.

## Install with Sideloadly (also fine)

1. Uninstall App Store Telegram if you keep the default bundle ID, **or** use
   Sideloadly → Advanced Options → **Change Bundle ID** to something unique
   (recommended so both can coexist).
2. Open the Release IPA in Sideloadly, sign with your Apple ID, install.
3. On the iPhone: Settings → General → VPN & Device Management → trust your
   developer certificate.
4. Free Apple IDs expire ~7 days; refresh via Sideloadly / AltStore.

## AltStore / SideStore

Same IPA works. Prefer builds with extensions disabled (this CI already does).
If an installer complains about PlugIns, strip `Payload/*.app/PlugIns` before
signing — not needed for this workflow’s artifact.

## Fork extras

Settings → Privacy and Security → **Extras / Дополнительно** toggles fork-only
features (stored in AccountManager + App Group UserDefaults for NSE):

| Feature | Effect |
|--------|--------|
| Ghost Mode | Skips marking chats/messages as read while browsing |
| Instant Passcode Lock | Locks as soon as the app backgrounds (passcode must be set) |
| Hide Mention Notifications | Drops APS category `"m"` in Notification Service |
| Hide Pinned Notifications | Drops payloads that look like pinned-message alerts |
| Formatting Panel | Bold / Italic / Monospace / Link toolbar above the keyboard |
| Keychain Session Backup | Mirrors `AccountBackupData` into the device Keychain for same-bundle E-Sign reinstalls |

## What CI cannot do without your Apple certs

- Produce a universally installable IPA
- Keep push / iCloud / Siri / Associated Domains working under a personal free ID
- Sign for arbitrary users’ devices — final signing is always local

## Toolchain note (Xcode / iOS)

CI targets **Xcode 27 / iOS 27 SDK** via the GitHub `xcode-27` runner image (`versions.json` → `"xcode": "27.0"`). The preview image omits Metal by default; the workflow downloads `MetalToolchain` (as the runner user) and verifies `xcrun metal -v` before the Bazel build. Make.py always uses `--overrideXcodeVersion` so beta Xcode version strings are accepted.

**Minimum iOS: 15.0** — Xcode 27’s libc++ rejects deployment targets below iOS 15 (`The selected platform is no longer supported by libc++`). The app `minimum_os_version` in `Telegram/BUILD` was raised from 13.0 accordingly.

Swift modules keep `-warnings-as-errors`, but CI passes `-Wwarning ImplicitStrongCapture` and `-Wwarning DeprecatedDeclaration` (SE-0443) so the Xcode 27 diagnostic noise does not block the sideload IPA. Migrating call sites is follow-up work.
