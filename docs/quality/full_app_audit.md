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

None of the P2 or P3 items above is open any more: the P2 ones were fixed in iteration 3, the P3 ones in
iteration 4.

### Not covered yet

F (UI: needs a simulator), upstream Postbox/MTProto internals, tgcalls, media decoders, auth flows (QR login, 2FA)
beyond the fork's changes.

## Iteration 3 (on `main`, from ae2066dc8a): the open P2 items

Same environment and policy as iteration 2. Pinned by `Tests/Upstream13/audit_iteration3.py` (in `client-regression`):
7 tests, 4 failures + 3 errors on the unfixed tree, all pass on the fixed one. Four existing tests asserted the old
source text of the changed code (`donut_deleted_messages`, `duress_and_local_pins`, `translate_before_sending`); their
assertions were moved to the new code with the same intent. All 36 `Tests/*` directories give the same result as on
ae2066dc8a on this machine.

### Fixed (source checks pass, builds in CI; not run on a device)

| Pri | Area | Defect | Fix | Files |
|---|---|---|---|---|
| P2 | A/E | A hidden account's outgoing calls were donated to Siri (`INStartCallIntent`) and every CallKit call went into Phone Recents; hiding an account removed only its message donations. | No donation while the account is hidden; call donations are grouped per account (`startCallIntentGroupIdentifier`) and deleted by `clearHiddenAccountTraces`. While any account is hidden (stored settings, so also on a VoIP cold start) the provider runs with `includesCallsInRecents = false`. Call donations made before this change carry no group and cannot be deleted. Trade-off: Recents also stay empty for visible accounts while one is hidden; CallKit has no per-call switch. | `TelegramCallsUI/Sources/CallKitIntegration.swift`, `TelegramIntents/Sources/TelegramIntents.swift`, `ChatListUI/Sources/ArchiveLockHelpers.swift`, `TelegramUI/Sources/SharedAccountContext.swift` |
| P2 | A | The duress reveal block was memory-only: a relaunch inside the auto-lock window re-enabled Settings x10. | The flag is stored in the duress passcode's Keychain record, set by `blockReveal`, cleared by `allowReveal`, checked by `isRevealBlocked`. | `TelegramUIPreferences/Sources/DuressPasscode.swift`, `HiddenAccountsSession.swift`, `TelegramUI/Sources/TelegramRootController.swift` |
| P2 | A | A widget configured before its account was hidden kept showing that account's chats. | The widget reads `HiddenAccountsSettings` and drops hidden accounts' items; the widget library links `TelegramUIPreferences`. | `Telegram/WidgetKitWidget/TodayViewController.swift`, `Telegram/BUILD` |
| P2 | B | Turning Don't Read off restored the server read state of chats read only here, the open one too, which stayed unread until a newer message showed. | After the restore transaction completes, `ghostLocalReadsRestoredNotification` makes an open chat read what it shows again (ordered after the restore, which would otherwise undo it). | `TelegramCore/Sources/State/ManagedSynchronizePeerReadStates.swift`, `ManagedLocalInputActivities.swift`, `TelegramUI/Sources/ChatHistoryListNode.swift` |
| P2 | C | A signed-out account's saved deleted messages, edits and media copies (secret/view-once included) stayed on the device in plaintext. Legacy unscoped attachment names could match another account's message. | `MessageSavingStore.eraseAccount` runs when an account record goes (main app only, not while the same user is signed in under another record). Legacy names are only matched for channels. Saved copies of a deleted chat are kept: keeping them is the feature. | `TelegramUIPreferences/Sources/MessageSavingStore.swift`, `TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift`, `SharedAccountContext.swift` |
| P2 | H | DeepL and Yandex API keys were stored in the unencrypted settings database. | `ForkTranslationAPIKeys` keeps them in the Keychain (after first unlock, this device only); keys from an older build are moved there and cleared from the database on launch. | `TelegramUIPreferences/Sources/ForkTranslationAPIKeys.swift` (new), `TranslateUI/Sources/ForkTranslationBackends.swift`, `SettingsUI/Sources/ForkExtrasController.swift`, `SharedAccountContext.swift` |

Not verified on a device: CallKit Recents behaviour, the widget refresh, and the Keychain migration need a real phone.

The first CI run of iteration 3 (3e27984783) failed in `Tests/ClientAdditions/menu_layout.py`, which compiles the Extras
entries in a harness that had no `ForkTranslationAPIKeys`; `Tests/ArchiveLock/run.py` compiles `HiddenAccountsSession`
alone and needed the duress reveal block too. Both harnesses got stubs (4ccfad7804). The IPA was not built in that run.

## Iteration 4 (on `main`, from 3e27984783): the P3 items

Three read-only reviews located and confirmed each item; every patch was re-read in the source before it was applied.
Pinned by `Tests/Upstream13/audit_iteration4.py` (in `client-regression`): 7 tests, 5 failures + 2 errors on the unfixed
tree, all pass on the fixed one. All 36 `Tests/*` directories give the same result as on 3e27984783 on this machine.
CI ran once, for iterations 3 and 4 together, on 6c72687452: `Client regression tests` 44254276483 and
`Build sideload IPA` 44254277702 (Xcode 27, compile only) both passed.

### Fixed (source checks pass, builds in CI; not run on a device)

| Pri | Area | Defect | Fix | Files |
|---|---|---|---|---|
| P3 | C | A saved copy kept the source's extension (`MOV`, `heif`, `apk`...), which the lookup never probed: the copy was never found again. | Extensions are lower-cased, unknown ones saved as `bin`, the probe list is longer, upper-case copies of older builds are probed too. | `TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift` |
| P3 | B | Sticker-to-video: a cancel or the timeout during `finishWriting` called `cancelWriting()` on a finishing writer and removed its file. | A `finishing` flag set before `finishWriting`; the cancel handler then leaves cleanup to the completion. | `TelegramUI/Sources/ChatController+ForkStickerMedia.swift` |
| P3 | B | Banned-GIF conversion of an inline result without content waited out the 60 s timeout. | An `EmptyMediaResource` gives up at once. A GIF that cannot be converted is still sent and shows as failed (dropping it silently was rejected: the user would lose the message without a word). | `TelegramCore/Sources/PendingMessages/ForkBannedGifVideo.swift` |
| P3 | E | No Call Rating Prompt promised to hide a sheet that Telegram no longer shows (`CallControllerNodeV2` never calls `presentCallRating`). | The setting and its guard stay (they work again if upstream re-wires the sheet); the footer now says what the switch does. | `SettingsUI/Sources/ForkExtrasController.swift` |
| P3 | D | WebSocket fallback probe slot was a shared flag: any older connection closing or failing freed the current probe's slot or doubled its backoff. | A token per probe; only the connection holding it aborts the probe or charges its failure. | `TelegramCore/Sources/Network/MTWebSocketConnectionInterface.swift`, `Network.swift` |
| P3 | voice | The Int16 equalizer path (all live playback) hard-clipped boosted peaks. | Soft-limited like the Float and offline paths (unchanged below 0.8 of full scale). | `ForkVoiceDSP/Sources/ForkVoiceDSP.c` |
| P3 | voice | A recording continued from a draft took the voice changer settings of that moment. | The settings the recording began with are kept in its resume data; older drafts fall back to the current settings. | `TelegramUI/Sources/ForkVoiceChanger.swift`, `ManagedAudioRecorder.swift` |

Not verified on a device: playback with a large equalizer boost, a voice draft continued after a settings change, and
the WebSocket fallback on a network that blocks it.
