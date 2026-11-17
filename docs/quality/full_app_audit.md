# Full app audit — working log

The state of the stabilization audit, kept so a later session can continue without re-auditing what is done.
Statuses: **fixed** (changed, source checks pass), **verified** (seen working in a build or on a device),
**presumed fixed** (changed, not built), **not verified** (could not be checked here).

## Baseline

- Branch `audit/stabilization` from `main` at `550246240b87070550df4e0d339d72f37b943441` (13.1.2, `versions.json`:
  Xcode 26.6, Bazel 9.2.0, macOS 26).
- Audit environment: Windows 11, Git Bash, Python 3.14. **No Swift, Xcode, Bazel or simulator**, submodules not
  checked out. Nothing in this audit was compiled or run on a simulator; every Swift change is at most
  *presumed fixed* until CI (`Build sideload IPA`, `Simulator QA evidence`) builds it.
- The repo's `Tests/**/*.py` are source-text checks. On Windows many fail for environment reasons (no `swiftc` /
  `xcrun`, backslash paths in path comparisons). Every result below is a delta against a baseline run on the
  unmodified tree, never an absolute pass/fail.

## CI state (GitHub Actions, read through the public API)

- 9 Nov runs for tag `v13.1.2-4512-pre` (API schema, client regression, MTProto connection): **cancelled**, not
  failed (superseded by a newer run in the same concurrency group).
- `Client regression tests` failed on `main` at 7e616f75, 35eaa649 and a6f4c6f5 (steps
  `Tests/ClientAdditions/menu_layout.py`, `Tests/ClientAdditions/donor_updates.py`,
  `Tests/Customization/appearance.py`). Cause: the Swift test stubs read `ForkExtrasSettings.swift` only up to a
  marker, and `ForkPowerSavingSnapshot` had moved to another file. Fixed by a7ec1ecf; the run on a7ec1ecf is green.
- Last fully green set on `main`: a59d8ebc (Build sideload IPA, Simulator QA, CodeQL; 10 Nov).
- 550246240b (Ghostgram: kept self-destructing media, content restrictions) has not been built yet: its client
  regression and CodeQL runs were in progress when this audit started.

## Subsystem map

| | Subsystem | Main locations | Status |
|---|---|---|---|
| A | Auth, accounts, passcode, lock | `submodules/AuthorizationUI`, `AppLock`, `PasscodeUI`, `TelegramUIPreferences/HiddenAccountsSession`, `DuressPasscode`, `ArchivePasswordKeychain` | partial: passcode, duress, keychain reviewed; 2 fixed |
| B | Chats and messages | `TelegramCore/TelegramEngine/Messages`, `ChatListUI`, `TelegramUI/Sources/Chat*`, Ghost Mode, MessageSaving | partial: Ghost Mode, Message Saving reviewed; 1 fixed |
| C | Media and files | `GalleryUI`, `MediaPlayer`, `TelegramUI/Components/Chat/*Media*`, Camera | not started |
| D | Networking | `MtProtoKit`, `TelegramCore/Network`, `TelegramVLESS`, `MTWebSocketTransport`, managed proxy, web proxy | fork transports reviewed; 2 fixed; upstream TLS risk noted |
| E | Calls | `TelegramCallsUI`, `TgVoipWebrtc` (submodule not checked out) | not started |
| F | UI/UX | all screens; needs a simulator — not possible here | blocked (no simulator) |
| G | Fork features | `ForkExtrasSettings`, `SettingsUI/Fork*`, `Banana*`, Ghost Mode, filters, local pins, menus | settings serialization and leaks reviewed; 1 fixed |
| H | Security and storage | Postbox, Keychain, settings import/export, update check, deep links, translators | reviewed; 1 fixed, API key storage open |

## Iteration 1

### G — settings serialization (same class as a7ec1ecf)

Checked mechanically (scripts in the audit session, not committed): every stored property of `ForkExtrasSettings`
(226) is decoded and encoded under the same key; init defaults, `defaultSettings` values and decode fallbacks agree.
The differences found are intended migrations: `doubleTapToEdit` is written from `doubleTapAction`,
`showMutualContact` falls back to `showProfileId`, the three ghost switches fall back to the legacy ghost flag.
`ChatArchiveSettings`, `MediaInputSettings` checked the same way: no gaps.
Upstream, not fork: `ExperimentalUISettings.dynamicStreaming` is decoded from `dynamicStreaming_v2` but encoded as
`dynamicStreaming`, so the debug switch does not survive a restart. Debug-only and upstream code; left as it is.

Result: no defect.

### Method of iteration 1

Four read-only reviews ran in parallel, one per area (G/UI leaks and timers, D networking, B+G Ghost Mode / Message
Saving / multiple accounts, H security and storage). Every finding was re-read in the source by the audit session
before anything changed; only confirmed defects were fixed. Fixes are pinned by `Tests/Upstream13/audit_stabilization.py`
(run in `client-regression`): all 7 tests fail on the unfixed tree and pass on the fixed one.

### Fixed (presumed: source checks pass, not built)

| Pri | Area | Defect | Fix | Files |
|---|---|---|---|---|
| P0 | A/H | Duress Passcode "Erase All" removed the accounts but left every saved deleted/edited message (plaintext `MessageSaving/records.json`), the Saved Attachments copies and the notification extension's staged pushes on the device: they live outside the account folders. | `MessageSavingStore.eraseEverything()` (memory, file written through also over an unreadable history, attachments, staging), called before the accounts are removed. | `TelegramUIPreferences/Sources/DuressPasscode.swift`, `TelegramUIPreferences/Sources/MessageSavingStore.swift` |
| P2 | G | The launch-time push of *default* settings (`applyGhost: false`) still wrote Keep Banned Chats, Remove Pings, Ghost Schedule and Ghost Silent Send, whose setters persist to UserDefaults. The copy meant to bridge the cold-launch gap was overwritten with defaults, so a send right after launch (reply from a notification) went out unscheduled and with sound. | Those four are written only with the user's settings (`if applyGhost`). | `TelegramUI/Sources/SharedAccountContext.swift` |
| P2 | D | The WEB proxy sidecar's MTProxy listener (`NWListener(using: .tcp, on: 0)`) listened on every interface; any device on the same Wi-Fi could open streams through the user's relay session. MtProto only ever connects to it at 127.0.0.1. | Bound to 127.0.0.1, as the SOCKS5 bridge already was. | `WebProxyTransport/Sources/WebProxySidecar.swift` |
| P3 | D | DoH proxy-list fetch: after the 9 s wait timed out, `body` was read while URLSession's handler could still be writing it (data race on a Swift String), and the task kept running. | Read `body` only after a signalled wait; cancel the task on timeout. | `TelegramCore/Sources/State/ManagedAutomaticMtProxy.swift` |
| P3 | A/H | A release `NSLog` of PBKDF2 timing ran after every wrong passcode only when a duress passcode exists, telling a sysdiagnose reader that one is set. | Kept for debug builds only. | `TelegramUIPreferences/Sources/ArchivePasswordKeychain.swift` |
| P3 | H | `tg://ayu/filters/import` fetched a sender-chosen URL through `URLSession.shared` (cookies, shared cache). | One-shot ephemeral session, invalidated after the task. | `TelegramUI/Sources/OpenUrl.swift` |

### Reviewed, no defect

- G/UI: all `Fork*` / `Banana*` settings screens, ChatController fork extensions, fork subscriptions and
  NotificationCenter observers in upstream files, fork timers (snow, keep-alive, proxy failover, WebSocket, path
  reconnect, VLESS heartbeat): weak captures and invalidation paths present. Limit: lines the fork added to upstream
  files without a fork name were scanned only for the newest 163 of 1,139 fork commits (blobless clone).
- D: WebSocket, WEB proxy and SOCKS5 frame parsers (bounds, length caps, overflow guards), `WebProxyManager` lock
  order, reconnect completions, retry backoffs (all bounded).
- B/G: Ghost exceptions and Read on Interact are per account; consume operations stay queued while hidden; local pins
  are per account Postbox; archive keychain items are per account; the notification extension hides hidden accounts.
- H: settings import exclusions (API keys, duress, badges), Message JSON, translator requests (keys only in headers,
  ephemeral sessions), keychain accessibility (`WhenUnlockedThisDeviceOnly`), `tg://webproxy` parser, URL login-part
  guard, regex filter timeout.

### Known, not changed (decisions or larger work)

- **Upstream, D, risk noted**: `MTProtoRustEngine/RustStreamHost.swift` accepts any TLS certificate
  (`sec_protocol_options_set_verify_block` → `complete(true)`) on the engine's TLS routes. Upstream code; on iOS the
  Rust engine is used only through the Debug switch (CLAUDE.md). MTProto still authenticates and encrypts the payload.
  Turning validation on may break fronted routes, so it needs upstream's intent before any change.
- **P2, H**: DeepL / Yandex API keys are stored in `ForkExtrasSettings` in the unencrypted AccountManager database.
  Moving them to the Keychain needs a migration and UI wiring; next iteration.
- **P2, A**: Duress "Log Out" leaves the chosen accounts' saved deleted messages (needs the account record → peer id
  mapping) and other accounts' archive keychain items. Not promised by that action's description; next iteration.
- **P3, D**: WebSocket fallback probe slot can be released by a connection that did not own it
  (`MTWebSocketConnectionInterface`); self-recovering.
- **Suspected, unverified**: Message Saving runs with defaults (`saveDeleted: false`) until `sharedData` arrives at
  launch, so a deletion processed in that window would not be kept; Ghost local reads vs. the notification
  extension's unread counts; a chat left open while Don't Read is turned off is read only after a scroll or reopen;
  read-modify-write of `BananaMediaTweaks.current` from two threads; DocumentPicker singletons keeping an
  `AccountContext` alive when the picker is dropped without a callback; settings import can turn security switches
  off behind a "N settings will change" confirmation.

### Not covered yet

C (media pipeline), E (calls), F (UI — needs a simulator), A beyond passcode/duress (auth flows, QR login, 2FA),
upstream Postbox and MTProto internals. Next: build this branch in CI (`Build sideload IPA`), then C and E.
