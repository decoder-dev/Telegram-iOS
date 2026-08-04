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
| Bundle ID (build-time) | `ph.teleg.Telegrapf` |
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
| Hide Mention Notifications | Drops mention pushes in Notification Service (`loc-key` / alert heuristics; App Group + standard defaults) |
| Hide Pinned Notifications | Drops pinned-message pushes the same way |
| Keychain Session Backup | Mirrors `AccountBackupData` into the device Keychain for same-bundle E-Sign reinstalls |

Settings → Support footer shows `Telegram VERSION (BUILD)` and `decoder-dev`. Archive tip sheets / auto-archive suggestion alerts are suppressed.

## What CI cannot do without your Apple certs

- Produce a universally installable IPA
- Keep push / iCloud / Siri / Associated Domains working under a personal free ID
- Sign for arbitrary users’ devices — final signing is always local

## Toolchain note (Xcode / iOS)

CI stays on **Xcode 26.2** (`versions.json`, `runs-on: macos-26`). An attempt to ship on the Xcode 27 preview runner produced an installable IPA that **crashed on device**; that toolchain bump is parked until the beta runtime is stable. Make.py uses `--overrideXcodeVersion`.
