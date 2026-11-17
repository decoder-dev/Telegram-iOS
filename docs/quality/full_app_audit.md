# Full app audit — working log

The state of the stabilization audit, kept so a later session can continue without re-auditing what is done.
Statuses: **fixed** (changed, source checks pass), **verified** (seen working in a build or on a device),
**presumed fixed** (changed, not built), **not verified** (could not be checked here).

## Baseline

- Iteration 1: branch `audit/stabilization` (merged into `main` as bd2c65d392) from `main` at `550246240b87070550df4e0d339d72f37b943441` (13.1.2, `versions.json`:
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
- 550246240b (Ghostgram: kept self-destructing media, content restrictions): `Client regression tests` **failed**
  (run 44000212608, step `python3 -m unittest discover -s Tests/Branding`): the Keep Self-Destructing Media footer
  (row 2431) was 250 characters, over the 170 that `test_extras_density.test_footers_stay_a_few_lines` allows.
  Fixed on this branch (both new footers shortened); `Tests/Branding` passes locally. That build itself (IPA) has not
  run yet. Lesson: a check that fails in the local baseline is not automatically environmental; compare with CI.

## Subsystem map

| | Subsystem | Main locations | Status |
|---|---|---|---|
| A | Auth, accounts, passcode, lock | `submodules/AuthorizationUI`, `AppLock`, `PasscodeUI`, `TelegramUIPreferences/HiddenAccountsSession`, `DuressPasscode`, `ArchivePasswordKeychain` | passcode, duress, keychain, hidden accounts in extensions reviewed; 3 fixed, 3 open (iteration 2) |
| B | Chats and messages | `TelegramCore/TelegramEngine/Messages`, `ChatListUI`, `TelegramUI/Sources/Chat*`, Ghost Mode, MessageSaving | Ghost Mode, Message Saving, outgoing text rules reviewed; 4 fixed, 1 open |
| C | Media and files | `GalleryUI`, `MediaPlayer`, `TelegramUI/Components/Chat/*Media*`, Camera | fork media code reviewed (iteration 2); 1 fixed, 4 open; upstream decoders not reviewed |
| D | Networking | `MtProtoKit`, `TelegramCore/Network`, `TelegramVLESS`, `MTWebSocketTransport`, managed proxy, web proxy | fork transports reviewed; 2 fixed; upstream TLS risk noted |
| E | Calls | `TelegramCallsUI`, `TgVoipWebrtc` (submodule not checked out) | CallKit/PushKit and fork call code reviewed; 1 fixed, 2 open; tgcalls not reviewed |
| F | UI/UX | all screens; needs a simulator — not possible here | blocked (no simulator) |
| G | Fork features | `ForkExtrasSettings`, `SettingsUI/Fork*`, `Banana*`, Ghost Mode, filters, local pins, menus | settings serialization, leaks, Ghostgram ports reviewed; 4 fixed |
| H | Security and storage | Postbox, Keychain, settings import/export, update check, deep links, translators | reviewed; 2 fixed, API key storage open |

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

## Iteration 2 (on `main`, from bd2c65d392)

Policy for this iteration: work directly on `main`, no branches or PRs. Same environment limits as iteration 1: no Swift,
Xcode, Bazel or simulator here, so every Swift change below is **presumed fixed** until CI builds it.

**Build:** `Build sideload IPA` run 44099954225 on 8bcac0393e (Xcode 27, compile only, `create_release=false`) built
the IPA with all iteration 2 changes, and its regression job passed. None of the changes was run on a device or
simulator, so they stay *fixed (builds)*, not *verified*.
`Client regression tests` run 44099873571 on 8bcac0393e (with `audit_iteration2`) passed.

### Method

Four read-only reviews in parallel: the Ghostgram ports (8df16d1c41, 550246240b), fork media code, calls + auth/hidden
accounts, and the "suspected" list of iteration 1. Every finding was re-read in the source before a change. The fixes
are pinned by `Tests/Upstream13/audit_iteration2.py` (in `client-regression`): 9 tests, 8 failures + 1 error on the
unfixed tree, all pass on the fixed one. All 36 `Tests/*` directories give the same result before and after the
changes on this machine (`python -m unittest discover` per directory, compared line by line).

### Fixed (source checks pass, builds in CI; not run on a device)

| Pri | Area | Defect | Fix | Files |
|---|---|---|---|---|
| P0 | E | VoIP push: `completion()` ran synchronously at the end of the push handler, while the call was reported to CallKit only after the account was resolved asynchronously (up to 2 s on a cold start). PushKit requires the report before the completion handler; iOS kills the app and eventually stops VoIP pushes. | `completion` runs once, from `finishPush`, right after either report; every early exit uses it; after 5 s without a report a generic call is reported and ended first. The resolve-before-report privacy design is kept. | `TelegramUI/Sources/AppDelegate.swift` |
| P1 | A/H | Siri contact search and the widget's chat picker listed every signed-in account, hidden ones included (names, top chats). | Both account lists drop accounts `HiddenAccountsSettings` hides. | `Telegram/SiriIntents/IntentHandler.swift` |
| P1 | H | Settings import showed only "N settings will change": a crafted file could turn off Security switches, the passcode lock, link confirmations, screenshot protection, streamer mode and Ghost Mode. | Protective keys are counted separately; when any change, the alert names them and its default action keeps them; "Import Everything" is a separate destructive action. | `SettingsUI/Sources/BananaSettingsBackup.swift`, `BananaAboutController.swift` |
| P1 | B/C | Message Saving: the copy of a deleted message's media was only scheduled on a background queue, and the caller deleted the original in the same transaction (secret chat cleared, channel range deleted), so the copy usually failed and the record pointed at nothing. | APFS clone made synchronously (one metadata call), byte copy only as fallback; copies get a fresh modification date so the 14-day unreferenced sweep does not remove them early. | `TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift` |
| P2 | B | Outgoing text rules: a batch with text took an extra postbox hop that a sticker/voice batch did not, so a sticker sent right after a text could be inserted and sent first. | While a rule is on, every batch takes the same hop. | `TelegramCore/Sources/PendingMessages/ForkOutgoingTextRules.swift` |
| P2 | B | Anti-Caps counted uncased letters (CJK, Arabic, Hindi...), so `这是NASA的API文档` was sent as `这是nasa的api文档`. | Only cased letters count, and they must be at least 80% of the letters. | same |
| P2 | G | `BananaMediaTweaks` read-modify-write from a chat history node (AccountManager queue) raced the full write from `SharedAccountContext` (main): Upload Acceleration, Auto-Pause etc. could revert. | `setStickerShape` changes only that field inside `Atomic.modify`. | `TelegramCore/Sources/Arena/BananaMediaTweaks.swift`, `TelegramUI/Sources/ChatHistoryListNode.swift` |
| P1 | A | Duress "Log Out" of an owner account removed it from the hidden-accounts map, so the accounts it hid appeared in the account list right after the duress passcode. | Rule chosen by the owner of the project: the accounts a chosen owner hides are logged out with it; the settings footer and confirmation say so. (b2c4c3605e; built by `Build sideload IPA` 44196231121 and passed `Client regression tests` 44196218338 on c07d64395a; not run on a device.) | `TelegramUIPreferences/Sources/DuressPasscode.swift`, `SettingsUI/Sources/DuressPasscodeController.swift` |
| P3 | G | Document-picker delegates were singletons holding the `AccountContext`; when UIKit dropped the presentation no callback came and the account stayed alive until the next import. | One delegate per picker, retained by the picker (associated object). | `SettingsUI/Sources/ForkExtrasController.swift`, `BananaAboutController.swift` |

### Reviewed, no defect

- Ghostgram ports: renderer formats (44.1 kHz stereo Int16 in `MediaPlayerAudioRenderer`, 48 kHz in ChunkMediaPlayerV2
  checked from the sample buffer), voice changer buffer sizes and delay clamps, C object lifetimes, text-rule UTF-16
  ranges and entity shifting, registration-date table (315 entries, sorted, bands consistent), kept-media hooks.
- Media: shared static settings are `Atomic`; TikTok/Shorts download cleanup; Saved Attachments retry bounds; gallery
  double-tap seek; camera zoom guards.
- Calls/auth: `HiddenAccountsSession` locking, `switchToAccount` gating, ringing for hidden or archive-locked accounts,
  push redaction, duress verification order, CallKit start watchdog, VLESS fail-closed for calls.
- Iteration 1 suspicion "Message Saving defaults until sharedData arrives": **not a bug** (settings and account records
  are emitted FIFO from the same AccountManager queue; accounts are created after the settings handler ran).

### Open (confirmed, not changed in this iteration)

- **P2, A/E**: calls of a hidden account donate `INStartCallIntent` (Siri suggestions) and land in Phone Recents;
  `clearHiddenAccountTraces` removes only send-message donations.
- **P2, A**: `HiddenAccountsSession.revealBlocked` (set by the duress code) is memory-only; a relaunch inside the
  auto-lock window re-enables the Settings x10 reveal gesture (opening still needs the password).
- **P2, A**: an already configured widget reads a hidden account's chats directly (`WidgetKitWidget/TodayViewController.swift`);
  that target does not link `TelegramUIPreferences`, so the filter needs a small dependency change.
- **P2, B**: an open chat is not marked read when Ghost "Don't Read" is turned off until a newer message is visible or
  the chat is reopened (`ChatHistoryListNode` read pipeline ignores the setting).
- **P2, C**: saved secret/view-once media and records outlive their chat and account (only Duress Erase All and the
  manual clear remove them); old unscoped attachment names can match another account's message.
- **P3, C**: saved copies with extensions outside the probe list (`MOV`, `heif`, `apk`) are never found again;
  sticker-to-video export cancelled during `finishWriting`; banned-GIF fallback sends a GIF that the chat rejects.
- **P3, E**: Extras > No Call Rating Prompt changes nothing: `CallControllerNodeV2` never shows the automatic rating
  sheet, so the switch is inert (harmless).
- **P3, D**: WebSocket probe slot ownership (iteration 1) confirmed; self-recovering.
- **P3, voice**: the equalizer's Int16 path hard-clips at large boosts; a resumed voice recording uses the voice changer
  settings of the moment it resumes.
- **P2, H**: translator API keys in the unencrypted AccountManager database (scope: `ForkExtrasSettings` fields,
  `ForkExtrasController` writer, `ForkTranslationBackends` readers).

### Not covered yet

F (UI: needs a simulator), upstream Postbox/MTProto internals, tgcalls, media decoders, auth flows (QR login, 2FA)
beyond the fork's changes.
