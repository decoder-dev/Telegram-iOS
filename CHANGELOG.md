# Changelog

Все notable-изменения этого форка. Формат loosely [Keep a Changelog](https://keepachangelog.com/).
Тег релиза = `v{app}-{tagSuffix}` (например `v12.9.2-3845`); CI кладёт секцию тега в GitHub Release notes.
Теги `*-pre` публикуются как GitHub **pre-release** (не Latest).

## [Unreleased]

### Security
- **Passcode at rest:** the app-lock passcode is now stored as a PBKDF2-HMAC-SHA256 digest (100k iterations, random 16-byte salt — the same scheme as the Archive password) instead of plaintext in postbox metadata. Legacy plaintext values still unlock and are transparently upgraded to the hashed form on the first successful entry; verification of hashed values is constant-time. The unused `lockId` property, which embedded the raw passcode, was removed. New passcodes are never stored in plaintext.
- **WEB proxy audit fixes (docs/network-audit.md):** backup-IP DoH discovery no longer arms while a WEB secret is active (F-3 — it only leaked "uses Telegram" to the DoH resolver and was never dialed through the tunnel; SOCKS5 is deliberately not gated). The WEB-proxy settings screen now discloses that calls depend on relay support (F-1a).
- **WEB proxy calls bridge (F-1b, client half):** the carrier parses WELCOME capability flags (bit 0 = arbitrary stream targets) and the sidecar then runs a loopback-only SOCKS5 listener — RFC 1929 auth with per-start random credentials, since iOS loopback is not app-isolated — mapping each SOCKS CONNECT to one carrier stream. Calls resolve a WEB proxy to this bridge at call-creation time (`PresentationCallManager.resolvedCallProxyServer()`), or stay direct when the relay lacks the capability, which is every current relay: the feature is inert until a relay implements `docs/webproxy-socks-bridge.md` (which now also carries the operator rollout guide).

### Fixed
- **UI consistency audit (docs/ui-audit.md):** the WEB calls note now reflects the bridge ("calls go through only if the relay supports call tunneling"); "Use for calls" is visible and controllable with a WEB proxy active (was silently applied with its stored default); uk/be app languages no longer get mixed RU/EN fork strings (table lookups follow the same rule as the ternary strings); the WEB catalog sheet got a title; the saved-messages feature is spelled from one string source; the "Auto" proxy summary value comes from one place; "WEB" is findable in settings search; dead `usePasteboardInfo`/`catalogPick` and a verbatim-duplicated status branch removed.

### Changed
- Removed the dead vendored OpenSSL 1.1.1d tarball (`submodules/openssl`) — not referenced by any build target (TDLib builds against BoringSSL); the 1.1.1 series has been EOL since September 2023.
- `Tests/AllTests` now aggregates the three existing unit-test suites instead of a dangling `TgCallsTests` label, so the default `Make.py test` build no longer fails.

## [v12.9.2-4013]

### Fixed
- **Archive lock:** Face ID resign no longer skips a real Home-background relock; suppress only applies while still foreground. Dual willRelock/didBecomeActive callbacks collapsed to session handlers refreshed on every bind (no stale account after switch). Dismiss waits for full archived peer-id set instead of first applying empty (App Switcher leak). Biometric suppress counter always cleared on auth completion.

## [v12.9.2-3950-pre]

### Changed
- **Adversarial hardening:** Archive password uses PBKDF2-HMAC-SHA256 (100k iterations, random 16-byte salt; old SHA-256 hashes still unlock and upgrade); VoIP `useForCalls` defaults on for new installs (existing stored prefs unchanged); passcode setup is 6-digit or alphanumeric only (no 4-digit).

### Fixed
- **Archive lock:** opening Archive no longer pops itself after Face ID/Touch ID — become-active privacy restore only dismisses when the session is still locked, and biometric unlock suppresses background relock so resign-active from the system prompt cannot clear reveal mid-unlock.
- **Archive lock:** App Switcher cover, leave-chat relock, Spotlight/share/mentions/widgets/search name leaks, Peer Info central gate.
- **Adversarial privacy:** Instant Passcode covers/locks on resign-active (Control Center / App Switcher); keyboard hidden under cover; instant cover remove; Archive dismiss sync before uncover; App Lock NSE redacts title+body; secret screenshots default off; Ghost Don't Read gates mentions/live-location/notification-reply/channel-view-increment; master Ghost includes Don't Read Stories; Read on Interact default off; MessageSaving/session Keychain backup/bypass-download default off; session backup wipe on disable.
- **Streamer Mode:** hide own phone number and username in profiles and the Settings header; widgets show locked/empty content while App Lock is active.
- **WEB proxy cold start:** hold MtProto and skip explicit backup-IP discovery while the sidecar has no loopback yet, so the first resume cannot dial Telegram DCs on the real IP.

## [v12.9.2-3949-pre]

### Fixed
- **Forward first-try:** hydrate sources via `getMessagesLoadIfNecessary` before picker (Chat + PeerInfo); pass Message objects from context menu instead of re-fetching ids; AyuForward covers 1:1 CachedUserData copy-protection; rebuild `MessageReference` from Postbox peer when snapshot lacks accessHash; use `apiInputPeer(_:sourceMessageId:)` for forward source; skip empty AyuForward instead of falling through to rejected vanilla forward; reupload webpage image/file embeds.

### Changed
- **AyuGram Android parity (Extras):** Ghost Mode master switch (4 flags incl. Go Offline); Read on Interact default ON + reacts; Schedule ↔ Read on Interact exclusive; full Ghost Schedule requires go-offline; Don't Read suppresses voice/video `readMessageContents`; Bypass unlocks save of protected chat media (not only stories); Local Premium unlocks chat-list View Anonymously; Hide Ads is a real toggle; View Deleted localized.

## [v12.9.2-3948-pre]

### Fixed
- **CI compile:** FakeTLS fragment delay uses `dispatch_after` on `tcpQueue.nativeQueue` — `MTQueue` has no `dispatchAfter:block:`.

## [v12.9.2-3947-pre]

### Fixed
- **CI compile:** `WebProxyCatalogEntry` is `Decodable` only (CodingKeys `secret` alias broke Encodable synthesis); add missing `shouldSkipCarrierRebuildDueToRecentActivity` helper.

## [v12.9.2-3946-pre]

### Added
- **FakeTLS TCP fragmentation:** ClientHello split into 5-byte TLS record header + body (30 ms delay) — DPI boxes waiting for a complete record no longer see SNI/ECH in the first segment.
- **MTProxy mirrors:** jsDelivr + gitmirror CDN fallbacks before GitHub; DoH TXT resolver (Google/Cloudflare/Mozilla) for proxy lists; hardcoded seed placeholder.
- **WS front / CF Worker support:** `WebSocketFrontTemplate`, `WebSocketEndpointPlanConfig`, `WebSocketEndpointPlanner.candidates(config:)` — planner now accepts operator-provided CF Worker front hostnames; HTTP `Host` header and TLS SNI use the front's own domain while cert validation stays on.
- **WEB proxy catalog:** `WebProxyCatalog` with bootstrap + HTTPS directory fetch; "Choose WEB Proxy" sheet with catalog entries + "Enter manually…" fallback.
- **WEB proxy background keepalive:** session PING sent from a `UIBackgroundTask` on entering background; active carrier with recent activity skips full rebuild on foreground resume.

## [v12.9.2-3945-pre] — 2026-09-03

Pre-release: WEB hang/path recovery + Messages chrome nits.

### Fixed
- **WEB proxy:** WS receive no longer swallows background cancels (dead loopback hang); multiplex open waits for first send/frame + 20s timeout; WELCOME watchdog / empty-204 fail; path change reconnects live carrier in place; skip Control Center flicker (&lt;5s background); superseded reconnect no longer double-restarts.
- **WebSocket:** abort stuck `isProbing` on intentional disconnect/deinit so fallback can recover.
- **Login network:** path reconnect + WS settings re-apply on unauthorized accounts.
- **UI:** long-press Send preview uses tailless bubbles; glass caption field 40pt + centred text; proxy-unavailable tooltip anchors to trailing shield; bot Menu button is circular; Day accent swatches show `#007AFF` bubble colour.

## [v12.9.2-3944-pre] — 2026-09-03

Pre-release: intermittent WEB connect recovery + proxy chrome visual fixes.

### Fixed
- **WEB proxy:** cooldown retry no longer no-ops inside the 180s `startingConfiguration` window (carrier deaths / failed bootstraps recover without a path flap); clear bootstrap pause when leaving WEB; `shouldKeepConnection` respects WEB pause; listener `.failed` during start completes the manager; sequential restart notifies `.stopped`.
- **WebSocket:** disable TCP fast open on TLS WS connects (intermittent middlebox handshake failures).
- **UI:** chat list and in-chat titles show «Connecting to proxy…» when a proxy is active; Auto MTProxy shows the nav shield; proxy-unavailable tooltip presents again; proxy list `addProxy` sort fixed; attachment caption send button is 40×40 (not oval) in glass mode.

## [v12.9.2-3943-pre] — 2026-09-03

Pre-release: fix path-reconnect compile on release_arm64 CI.

### Fixed
- **Network:** `ManagedNetworkPathReconnect` — use `String(describing:)` for `NWPath.Status` and `NWInterface.InterfaceType` (no `rawValue` on CI SDK).

## [v12.9.2-3942-pre] — 2026-09-02

Pre-release: network audit cleanup, FakeTLS Chrome ClientHello, WEB proxy foreground resume.

### Fixed
- **WEB proxy resume:** typed sidecar events; MtProto rebuild only on `.carrierResumedInPlace`; carrier rebuild on any real background; single lifecycle hook in AppDelegate.
- **WEB proxy:** in-place reconnect failure no longer double-fires `onFailure` + manager restart (was invalidating `startGeneration` and delaying recovery by backoff); pause MtProto whenever sidecar is down, including stale loopback in environment.
- **WEB proxy:** tear down `NWPathMonitor` when the user disables WEB proxy (no leaked monitor after explicit off).
- **Network:** `rebuildTransport()` respects WEB bootstrap pause — path/VPN handoff no longer resumes MtProto into direct DC while sidecar is bootstrapping.
- **Network:** rebuild transport on OS path changes (Wi‑Fi/cellular/VPN handoff); WEB bootstrap pause; IPv6 connect cap 2.5s; WebSocket send failures tear down the connection like NW TCP.
- **Network:** fix `ManagedNetworkPathReconnect` compile on release_arm64 (`NWInterface.InterfaceType` has no `rawValue`).
- **Proxy rotation:** only switch when the active proxy has connection issues; 12s probe timeout (was 30s).

### Changed
- **FakeTLS (TSPU bypass):** Chrome ClientHello (TDLib non-Darwin layout: fixed ciphers, h2 ALPN, ECH, permuted extensions, ML-KEM key share); removed dead Safari DSL (~420 lines).
- **WebSocket transport:** always enabled for every account (fork invariant); dead settings UI and stale docs removed from Proxy screen.

## [v12.9.2-3939-pre] — 2026-09-02

Pre-release: proxy reachability UI, network perf fixes (WEB loopback, IPv6 fast-fail, WS write buffer).

### Fixed
- **Proxy settings:** SOCKS5 and WEB proxies now get real reachability pings (WEB waits for sidecar bootstrap); auto-rotate counts only manual MTProxy/SOCKS5 servers, is hidden when Auto MTProxy is on, and the two toggles are mutually exclusive; WEB preview connect succeeds via loopback; chat list shows «Connecting to proxy…» while a proxy link is active; chat unread scroll no longer flips to default on a second initial emission.
- **WebSocket:** buffer outbound writes until the HTTP upgrade handshake completes instead of dropping them (MTTcpConnection sends data as soon as `connectToHost` returns).
- **WEB proxy:** stop publishing `lastGoodEndpoint` after the sidecar listener has stopped — stale loopback ports caused hundreds of `127.0.0.1:638xx Connection refused` hits; coalesce bootstraps through backoff and skip superseding an in-flight start on path return.
- **Network:** cap NWConnection connect timeout at 2.5s for IPv6 endpoints (blocked v6 no longer burns 12s per attempt); default proxy rotation wait 5s instead of 10s for new installs.

## [v12.9.2-3938-pre] — 2026-09-02

Pre-release: censorship network stack (proxy rotation, FakeTLS DC fallback, WebSocket hardening).

### Added
- **Proxy rotation:** Android-style ping-based auto-switch — configurable wait (5/10/15/30/60 s), RTT probe via `MTProxyConnectivity`, switch to fastest live server; timeout picker in Settings → Proxy.

### Fixed
- **FakeTLS:** HMAC mismatch on `ee` MTProxy triggers DNS TXT backup → `configSimple` DC fallback (Mozilla DNS after Google); mirrors Android tgnet.
- **WebSocket:** fallback to direct transport uses `NetworkFrameworkTcpConnectionInterface`, not GCDAsyncSocket.
- **WebSocket:** handle NWConnection `.cancelled`; debounce viability loss (2s post-`.ready`); persistent fallback coordinator on `Network`.
- **Proxy rotation:** 30s probe watchdog; reschedule wait-and-probe while still connecting when no faster proxy is found.

## [v12.9.2-3937-pre] — 2026-09-02

Pre-release: upstream TelegramMessenger audit (rich-text / MTProxy / tgcalls).

### Added
- **Docs (audit):** compared `TelegramMessenger/Telegram-iOS` master (Jul 2026 rich-text batch) — all `feat(richtext*)` / `feat(composer*)` / related fixes already present on `dec/zalupa-mess` under fork SHAs; no blind merge of official network code (our NWConnection/reachability fixes are ahead of upstream).

### Fixed
- **WebProxy:** reject malformed `WINDOW` frames unless payload is exactly 4 bytes (MTProxy Aug 2026 empty-packet hardening analogue).

### Notes (no code change this release)
- **MTProxy** (`TelegramMessenger/MTProxy`, Aug 2026): padding/window-clamp fixes apply to the C proxy daemon, not our Swift WEB sidecar; existing guards already cover empty `DATA` frames and stream window credit.
- **tgcalls:** repo pin `e3069322` (2026-06-15); upstream tip `78d07f3e46` (2026-08-20) — intentionally not bumped this pass.
- **Cocoon / Passport / MiniApps:** out of scope.

## [v12.9.2-3936-pre] — 2026-09-02

Pre-release: chat list watchdog layout coalesce + NWConnection silent stall fixes.

### Fixed
- **Chat list:** coalesce header `requestLayout` after the first pass — connection-status title flaps no longer run a spring layout on every `combineLatest` emission (watchdog stack through `GlassBackgroundComponent`).
- **Network:** NWConnection reports disconnect on write/read with no connection instead of silently dropping frames; identity guard on send/receive completions so superseded connections cannot corrupt the successor's read stream.

## [v12.9.2-3935-pre] — 2026-09-02

Pre-release: NWConnection restart race + reachability backoff follow-up.

### Fixed
- **Network:** NWConnection restart uses silent discard (no spurious disconnect); stale `.cancelled` from superseded connections ignored via identity guard — fixes intermittent connect hang.
- **MtProtoKit:** `clearBackoff` always runs on reachability "available" and invalidates pending timer; reconnect only tears down live TCP on offline→online edge; request connection when reachable but disconnected.

## [v12.9.2-3934-pre] — 2026-09-02

Pre-release: foreground resume reconnect storm fix.

### Fixed
- **Network:** stop tearing down live TCP on spurious reachability "available" callbacks during foreground resume — only reconnect after a real offline→online transition.
- **Network:** debounce NWConnection viability loss (2s) on established sockets so brief resume flicker does not restart every transport.
- **Web proxy:** run sidecar resume rebuild only from `applicationDidBecomeActive`, not `willEnterForeground`, to avoid racing foreground network wake-up.

## [v12.9.2-3933-pre] — 2026-09-01

Pre-release: NWConnection always-on, connect hang fix, reconnect storm throttle.

### Fixed
- **Network:** NWConnection is always enabled — debug toggle removed; stored opt-out migrates to on at account load and on every settings write; fix intermittent connect hang (ignore pre-ready viability loss, handle `.cancelled`, restart stale connections).
- **Network:** NWConnection logs name the endpoint and pre-connect failures (`NWError`) so retry storms can be distinguished (relay vs loopback vs DC).
- **MtProtoKit:** one-second floor between TCP reconnect attempts when a peer refuses instantly — stops 4k+ connects/25s watchdog kills while WEB proxy has no carrier.

## [v12.9.2-3932-pre] — 2026-09-01

Pre-release: NWConnection default TCP, connect/thread watchdog fixes, chat list hang.

### Fixed
- **Network:** NWConnection is the default TCP transport — in-flight connects cancel on timeout instead of blocking threads in `connect(2)`; fix deinit leak, failed-write teardown, in-flight logging.
- **MtProtoKit:** `TCP_CONNECTIONTIMEOUT` bounds blocking GCDAsyncSocket connects; stale-FD read after timeout; async socket teardown in `dealloc` off shared queues.
- **Chat list:** skip header `requestLayout` when `combineLatest` emits but title/buttons unchanged — fixes main-thread watchdog hang on unstable network.
- **FetchV2:** gate per-part chunk trace so large downloads do not evict crash breadcrumbs from the log.

## [v12.9.2-3931-pre] — 2026-09-01

Pre-release: launch stack-overflow fix, FFMpeg thread leak fix, crash symbolication CI.

### Added
- **CI:** optional dSYM upload on Build sideload IPA (`generate_dsym`); Symbolicate crash addresses workflow (`atos` on runner).
- **Breadcrumbs:** launch sub-stages inside `rootControllerReady` (`overlayControllersAttached`, `notificationsRegistered`, `authContextObserved`, `logoutObserved`).

### Fixed
- **ListView:** drain transaction queue in a loop instead of recursive `endTransaction` — fixes launch SIGSEGV stack overflow when many list transactions queue at startup.
- **MediaPlayer:** cancel FFMpeg frame source on thread termination so blocked `readPacketCallback` semaphores unwind and worker threads are reclaimed.

### Changed
- **Telemetry:** bundle-images log includes build number and load address per image UUID for crash offset mapping.

## [v12.9.2-3930-pre] — 2026-09-01

Pre-release: VoiceOver accessibility wave + WEB proxy uplink/reconnect fixes.

### Added
- **VoiceOver:** accessibility labels/traits across Display (alerts, action sheets, lists), chat messages, peer info panes, share sheet, contact list, chat list search, input context panels; contract tests (`AccessibilityUITests`, `VoiceOverContracts`) and release gate (`docs/VOICEOVER_RELEASE_GATE.md`, `ACCESSIBILITY_CHANGELOG.md`).

### Fixed
- **Browser:** KVO observer leak, readability text trim, hit-test, crash risks.
- **WEB proxy:** resend uplink batches that never left on reconnect; skip bootstrap when offline; release replaced transport on every reconnect outcome (not only success).
- **Context menu:** keep reaction bar off the message it belongs to.

### Changed
- **Instrumentation:** FetchManager logs finished vs abandoned; heartbeat uses malloc heap + Postbox row counts; network log records interface type and tunnel/proxy state.

## [v12.9.2-3929-pre] — 2026-08-31

Pre-release: read-state retry backoff + log noise reduction (+ 3928 WEB proxy/crash fixes).

### Fixed
- **Read states:** per-peer exponential backoff (1s→60s) when server rejects sync — stops 191-retry spin at 4/s; peer held out of `update()` while waiting.
- **Logging:** `PendingMessageManager` / Postbox unsent-view / `beginSendingMessages` log only when non-empty; master/resigned transitions include peer id.

## [v12.9.2-3928-pre] — 2026-08-31

Pre-release: WEB proxy network resilience + carrier negotiation + crash breadcrumbs.

### Fixed
- **WEB proxy:** transient downlink URLSession errors (-1001/-1004/-1005/-1009) retry with backoff instead of killing the carrier; session POST advertises `X-Carrier-Modes` so relay can pick websocket/lanes; resume-reconnect ignores stale failure from detached carrier.
- **Crash breadcrumbs:** SIGSEGV handler runs on `sigaltstack` and records `backtrace` frames (stack overflow no longer faults again before writing).

## [v12.9.2-3927-pre] — 2026-08-30

Pre-release: WEB proxy resume reconnect fix + FetchV2 log identifier.

### Fixed
- **WEB proxy:** detach the old carrier before in-place resume reconnect — stale `onFailure` from the suspended carrier no longer aborts the replacement and forces a loopback port move.
- **FetchV2:** log lines use the resource id (not the 90-char `inputDocumentFileLocation(…)` type name) so concurrent fetches are distinguishable and logs shrink ~11 MB.

## [v12.9.2-3926-pre] — 2026-08-29

Pre-release: WEB proxy resume/retry hardening.

### Fixed
- **WEB proxy:** keep fail-closed proxy settings on retry/restart holes; rebuild carrier on foreground resume without moving the loopback port (`reconnectTransport`); enforce WebSocket lane connect cap and stop charging a carrier that cannot accept frames.

## [v12.9.2-3925-pre] — 2026-08-29

Pre-release: CryZFix WEB proxy carriers + foreground lifecycle + unread diagnostics.

### Fixed
- **WEB proxy:** add `https-lanes`, `websocket`, and `websocket-lanes` carrier modes (per-lane `/up`/`/down`, multiplex `wss`, per-stream lane sockets with connect cap); fix `/up`/`/down` race; `transportEpoch` guards stale URLSession/WebSocket callbacks; stream ID wrap at `0xffffff`; `lastGoodEndpoint` keeps loopback alive during restart (no `127.0.0.1:1` connect storms); foreground-only lifecycle — `sequentialRestart` on return from background with 3s debounce.
- **Proxy settings:** while sidecar is booting or resuming, keep the previous loopback endpoint instead of falling through to `:1`.

### Added
- **Chat unread:** `[ChatUnreadPosition]` logging across history loading, list transition, and layout realign; 1s suppress window so composer inset changes do not steal the initial unread anchor.

## [v12.9.2-3924-pre] — 2026-08-29

Pre-release: crash diagnostics + log redaction.

### Fixed
- **Logging:** channel/group titles in the state machine log honour `redactSensitiveData` (14 sites; peer id unchanged).
- **Crash diagnostics:** uncaught `NSException` handler logs name, reason and call stack, syncs the log queue, chains to the previous handler; breadcrumb file records exception text; heartbeat adds malloc block count alongside bytes.

## [v12.9.2-3923-pre] — 2026-08-27

Pre-release: autoremove batching, memory/perf diagnostics, network + prefetch fixes.

### Fixed
- **Autoremove:** drain up to 256 due messages per transaction instead of one commit per expiry; Postbox batch scan `entries(tag:upToTimestamp:limit:)`.
- **Message saving:** `[MessageSaving]` file logging; proactive preserve fetch capped at 32 MB (waits for organic download above that).
- **Memory:** respond to memory warnings (eviction path); throttle MediaManager DB writes; camera recovery after interruptions; split resident vs allocated in telemetry.
- **Network:** stop service-layer rebuild on self-invented master flaps; steady master flag on connections.
- **WEB proxy:** cooldown resumes on its own timer instead of waiting for settings re-apply.
- **Prefetch:** skip media already on disk; preload manager logs only when view updates carry entries.

### Added
- **Instrumentation:** MediaBox fetch pipeline + linear path-touch logging; preload manager census; bundle image UUIDs at launch (symbolication); live chat-screen open/close counter.

## [v12.9.2-3922-pre] — 2026-08-26

Pre-release: extended log retention + streaming export.

### Added
- **Logging:** file logging raises retention to 400 MB full / 40 MB critical (`setMaxFiles` + immediate prune on disable); minute `[Heartbeat]` when logging is on.
- **Log export:** `ForkLogExport` hard-links logs → zip on disk, packages off main thread with HUD, single archive for mail/send; `moveResourceData(id:fromTempPath:)` engine forwarder.

## [v12.9.2-3921-pre] — 2026-08-26

Pre-release: crash/hang diagnostics + fork instrumentation for device logs.

### Added
- **Perf telemetry:** MetricKit crash/hang diagnostics log a greppable one-line summary plus full JSON payload (stacks), not just counts.
- **Instrumentation:** memory warnings + main-thread stall watchdog; runtime launch breadcrumbs (chat opened/background); `[Chat]` / `[Composer]` / `[Tapbacks]` markers; `WebProxyLog` / `WebSocketTransportLog` sinks wired in `initializeAccountManagement`; WEB proxy bootstrap/outcome/carrier mode; WS endpoint walk + framing rejections; TCP factory choice logged.

## [v12.9.2-3920-pre] — 2026-08-26

Pre-release: WebSocket recoverable fallback + WEB proxy handshake-only compatibility.

### Fixed
- **WebSocket transport:** after falling back to direct TCP, periodically probe WS again (2 min → 30 min ceiling) instead of staying on direct for the whole process life; a probe that carries MTProto traffic lifts the fallback.
- **WEB proxy:** stop gating session creation on `X-Carrier-Mode == "https"` — compatibility is decided by the `WELCOME` handshake (mode-label park from the intermediate commit was dropped with it).

## [v12.9.2-3919-pre] — 2026-08-26

Pre-release: Day composer tint readable on white wallpaper.

### Fixed
- **Day composer:** input field / attach / mic tint is `#F2F2F7` @ 0.9 (systemGray6) instead of white @ 0.8, so glass no longer disappears into the plain-white wallpaper; placeholder alpha 0.4 → 0.45 for ~3.3:1 contrast.

## [v12.9.2-3918-pre] — 2026-08-26

Pre-release: Tapbacks sheet dock fix + composer capsule min-height clamp.

### Fixed
- **Reactions (Tapbacks):** emoji sheet docks to the screen bottom (with home-indicator gutter) instead of floating above a stale chat `inputHeight`; rubber-band drag is clamped at the safe-area edge.
- **Composer:** single-line height clamp floored at `textFieldMinHeight` so the capsule stays aligned with 40pt controls and an empty field no longer draws the overflow hairline.

## [v12.9.2-3917-pre] — 2026-08-25

Pre-release: bubble/status width fixes, sticker peek sharpness, WebSocket MTProto transport.

### Added
- **WebSocket transport:** optional MTProto over `kwsN.web.telegram.org/apiws` (toggle in proxy settings; off while any proxy server including WEB is active). Framing module + MtProtoKit seam; live rebuild on toggle without relaunch.

### Fixed
- **Channel posts:** long author signatures no longer push the status/bubble past `maximumNodeWidth` — date is re-measured after badges (20pt floor).
- **Bubble header:** avatar/rank/trailing gutter reserved before measuring the author name so the header cannot exceed bubble max width.
- **Sticker peek:** Lottie rasterised at 512pt instead of below the drawn size.
- **Account limit UI:** logout / delete / peer-info gates read shared constants.
- **WEB proxy:** resolve uplink URL before committing a batch; drop unused `receiveBuffer`.
- **WebSocket transport:** freeze endpoints after establish; fallback counts payload success; coalesce near-simultaneous failures; generation-stamped NW callbacks; disconnect in deinit; hot-path buffer/mask fixes.

## [v12.9.2-3916-pre] — 2026-08-25

Pre-release: WEB proxy carrier CPU/radio and reconnect backoff (includes cancelled 3915 badge fixes).

### Fixed
- **WEB proxy:** empty downlink polls paced (0.5–5s backoff); uplink buffers use a read cursor; WINDOW credit coalesced; NWConnection callbacks stay on the sidecar queue; bootstrap no longer blocks the serial queue on semaphores.
- **WEB proxy:** a carrier that dies after becoming ready now shares bootstrap cooldown, so BYE/drop no longer loops unthrottled reconnects.
- **Day theme / white wallpaper:** transcription and date badge chips use an opaque light grey (#E4E4E6) instead of an invisible white-on-white fill (from 3915, IPA was cancelled).
- **Round video:** share and transcription buttons keep a 10pt minimum gap; lift only when the share button still clears the video circle (from 3915, IPA was cancelled).

## [v12.9.2-3915-pre] — 2026-08-25

Pre-release: white-wallpaper badge chip visibility + round video share spacing.

### Fixed
- **Day theme / white wallpaper:** transcription and date badge chips use an opaque light grey (#E4E4E6) instead of an invisible white-on-white fill.
- **Round video:** share and transcription buttons keep a 10pt minimum gap; lift only when the share button still clears the video circle.

## [v12.9.2-3914-pre] — 2026-08-25

Pre-release: round video badge layout + unified message badges / Day contrast.

### Fixed
- **Round video:** share and transcription badges no longer overlap; status moves to the row above transcribe when Saved Messages full-date layout does not fit beside it.
- **Round video:** date/status width derived from the display circle, not expanded playback size.
- **Messages:** share button uses the same blurred pill fill as date, duration and transcription badges.
- **Day theme:** incoming badge and secondary text contrast raised toward WCAG AA (waveform tint left at stock #cacaca).

## [v12.9.2-3913-pre] — 2026-08-25

Pre-release: Tapbacks drag perf + voice transcription status inset.

### Fixed
- **Reactions (Tapbacks):** grabber drag no longer runs a full context-menu layout every frame — only this node's layout; below-keyboard overlay updates short-circuit when unchanged.
- **Voice messages:** expanded transcription time/checkmarks no longer sit inside the bubble's 18pt corner (right inset restored when the padded width won).

## [v12.9.2-3912-pre] — 2026-08-24

Pre-release: Tapbacks sheet keyboard docking (chat dismiss + in-sheet search).

### Fixed
- **Reactions (Tapbacks):** opening the emoji sheet dismisses the chat keyboard so the grid is no longer drawn behind translucent keys (iMessage behavior).
- **Reactions (Tapbacks):** searching inside the sheet docks the sheet above the search keyboard instead of covering the emoji grid.
- **Reactions (Tapbacks):** layout and emoji-content refresh use the same bottom gutter, so a content refresh no longer flashes an empty strip above the search keyboard.

## [v12.9.2-3911-pre] — 2026-08-24

Pre-release: Tapbacks emoji sheet grabber drag polish.

### Fixed
- **Reactions (Tapbacks):** flick down from the expanded stop lands on the resting stop instead of dismissing; short screens with no headroom get rubber-band + dismiss only.
- **Reactions (Tapbacks):** cancelled system gestures return to the starting stop; stale pan offsets are cleared.
- **Reactions (Tapbacks):** grabbing the header during a settle/open animation no longer snaps the sheet — drag seeds from the current presentation position.

## [v12.9.2-3910-pre] — 2026-08-24

Pre-release: composer text centring + draggable Tapbacks emoji sheet.

### Fixed
- **Composer:** placeholder and typed text are vertically centred in the 36pt input capsule (insets derived from capsule height, not stock 31pt constants).
- **Reactions (Tapbacks):** the bottom emoji sheet grabber is draggable — two stops (resting and near full-screen), flick settle, pull-down dismiss; pan ignores touches below the header so the grid still scrolls.
- **Reactions (Tapbacks):** pulling down slides the sheet off-screen 1:1 instead of shrinking it under the finger.

## [v12.9.2-3909-pre] — 2026-08-24

Pre-release: archive lock only with password, Extras in Settings, recent-emoji toggle, WEB proxy protocol gaps.

### Changed
- **Archive:** the folder is hidden only when an archive password is configured; unprotected accounts always see Archive in the chat list.
- **Settings:** Extras (Дополнительно) moved from Privacy and Security to the main Settings list (above Developer Mode); Extras uses the Effect icon.
- **Reactions:** new **Recent Emoji in Reactions** toggle in Customization (default on); off limits pickers to the standard reaction set.
- **WEB proxy:** flow control (`WINDOW` credit), batched uplink, `WELCOME`/`BYE`/`PONG` handling, rejection of `ee` secrets and IP-literal hostnames.

### Fixed
- **Archive lock:** password binding keyed on account record id (survives relogin); protection signal reads Keychain or Postbox mirror; relock uses `isLockActive`; Settings×10 haptic skipped when no password is set.

## [v12.9.2-3908-pre] — 2026-08-24

Pre-release: build fix for Tapbacks panel + media-picker camera stop thrash.

### Fixed
- **Reactions (Tapbacks):** compile failure — `displayTail` now reads `hideReactionPanelTail` through `getController()` (the restored `controller` binding was out of scope).
- **Media picker:** scrolling no longer calls `stopCapture` on every frame when the camera cell is off-screen; `stopCapture` also skips `AVCaptureSession.stopRunning()` when the session is already stopped.

## [v12.9.2-3907-pre] — 2026-08-24

Pre-release: Tapbacks idealism + WEB proxy multi-account / Russian labels.

### Changed
- **Reactions (Tapbacks):** the bottom emoji picker is now an iMessage-style sheet — frosted backdrop with rounded top corners, grabber + close button, a flat grid (no warped edge rows, no Telegram pack chrome) and a home-indicator gutter the grid does not scroll into. Closing returns to the pill instead of leaving a dead Telegram control.
- **Reactions (Tapbacks):** the panel now uses the fork's Messages tokens instead of Telegram chrome colours — sheet surface `#FFFFFF` / `#1C1C1E` (was the context-menu tint `#F9F9F9` / `#252525`), smile button `#FFFFFF` / `#2C2C2E` with a `#8E8E93` glyph (was a full-contrast black/white glyph on an ad-hoc grey), and theme-driven grabber / close-button colours.
- **WEB proxy:** fork-private labels go through `ForkWebProxyStrings` (Russian via `prefersRussianStrings`) instead of `en.lproj`-only localization keys.

### Fixed
- **Reactions (Tapbacks):** the reaction pill can be swiped left/right again — its scroll content was sized to the visible slots only, so reactions past the 7th were unreachable. The row is also vertically centred in the capsule and laid out with the Tapbacks spacing it is measured with.
- **Reactions (Tapbacks):** the glass pill rendered as a dark capsule on the Day theme — the capsule was drawn with a hardcoded dark appearance while its container tracked the theme.
- **Reactions (Tapbacks):** an emoji-content refresh while the docked sheet was open brought back the Telegram pack panel — an empty 42pt band that also clipped the grid's first row — and could re-impose the pill's 7-column capsule metrics on the full-width grid.
- **Reactions (Tapbacks):** smile button geometry and states — the pressed highlight was invisible on the Day theme, the border was a half-pixel hairline, and the button was inset 4pt from the pill's trailing edge instead of the row's 8pt.
- **Reactions (Tapbacks):** sheet header alignment — grabber at the standard 5pt offset, close button optically centred with a 16pt gutter and a full 44pt hit target (was a 30pt target nudged 3pt below centre).
- **Reactions (Tapbacks):** legacy reaction bars stay 46pt (send / share-tag / sticker peek no longer grow a 10pt dead band). Tapbacks is chat-context-menu only, so story and video-chat glass panels keep their original layout. Smile sits in the reserved gap above the bubble; pill fade completes before hide; `hideReactionPanelTail` applies only to chat.
- **WEB proxy:** sidecar readiness is broadcast to every loaded account Network (was a single overwritten callback), so enabling WEB proxy no longer leaves other multi-account sessions stuck on the fail-closed loopback.
- **WEB proxy:** a start already in flight for the same server is reused instead of superseded. Each account resolves the same shared proxy settings, so with several accounts every extra `configure` tore down a sidecar midway through its HTTPS bootstrap and restarted the wait for all of them.
- **WEB proxy:** disabling the proxy no longer mutates the sidecar/endpoint state under the wrong lock, which could race a concurrent readiness callback.
- **WEB proxy:** failed sidecar bootstrap backs off instead of spinning; Account does not reapply empty default proxy settings before shared data arrives.

## [v12.9.2-3906-pre] — 2026-08-24

Pre-release: Tapbacks long-press + bottom emoji picker bugfixes (iMessage-like).

### Fixed
- **Reactions (Tapbacks):** long-press shows a compact pill + context menu (not the legacy in-place emoji blob); smile opens a bottom-docked emoji picker like iMessage instead of the center circle overlay.
- **Reactions (Tapbacks):** the bottom-docked emoji picker was not receiving taps at all — hit-testing stopped at the pill container, so no emoji could be picked; tapping outside the picker now dismisses instead of being swallowed.
- **Reactions (Tapbacks):** the smile button no longer floats over empty space while the picker is open, the anchored message no longer jumps by the smile's height when the picker opens, and the picker slides back down (not up) when it closes.
- **Reactions (Tapbacks):** collapse restores context-menu position lock / smile panel state so the menu does not stay faded or pinned after closing the picker.

## [v12.9.2-3905-pre] — 2026-08-22

Pre-release: iMessage-style Tapbacks reaction panel on message long-press.

### Changed
- **Reactions (long-press):** glass capsule pill without Telegram bubble-tail; expand control moved under the trailing edge as a separate smile button (`Chat/Context Menu/Smile`).
- **Tapbacks sizing:** ~52pt pill, 32pt emoji, 4pt spacing, max 7 visible reactions, secondary 30pt smile with 6pt gap; stretch-to-expand pan disabled in glass mode.

## [v12.9.2-3904-pre] — 2026-08-22

Pre-release: high-detail Телеграм icon family + custom **Patriot** alternate icon.

### Added
- **PatriotPlaneIcon:** 21st alternate app icon — cartoon soldier in tactical armor launching a paper plane; Russian flag backdrop; sleeve chevron (tricolor + **РФ**); localized label «Патриот» / Patriot in Appearance.

### Changed
- **App icons:** procedural generator upgrade — multi-stop gradient disc, metallic ring, layered plane (shadow/fold/wing/crease), supersampling; all **20** standard alternates + default assets regenerated.

## [v12.9.2-3903-pre] — 2026-08-22

Pre-release: WEB proxy hardening (async sidecar, fail-closed, no catalog); proxy UI polish; crash fixes.

### Added
- **WEB proxy:** async sidecar bootstrap (no 45s UI/network thread block); automatic network re-apply when sidecar becomes ready or fails at runtime.

### Changed
- **WEB proxy:** removed catalog/lists — masking sites are added manually (Add Proxy menu or `tg://webproxy` link).
- **WEB proxy:** localized labels via `SocksProxySetup.ProxyWeb` / `MaskingSite`; WEB list rows hide `:443`; preview sheet skips ping row for WEB.
- **Proxy list:** single “Add Proxy” action (SOCKS5 / MTProxy / WEB in action sheet).

### Fixed
- **WEB proxy:** fail-closed when sidecar fails on first enable; `stop()`/`start()` race; exhaustive `.webProxy` URL switches.
- **Calls list:** conference declined calls show missed icon.
- **Bag:** mutation-during-enumeration crash in `Bag.enumerateItems` (NSBag/SBag/MTBag/DeviceProximityBag).
- **Settings:** Proxy row always visible even with no servers configured.

## [v12.9.2-3902-pre] — 2026-08-22

Pre-release: WEB proxy (tproxy-server) with masking-site picker; calls list icons; crash fixes.

### Added
- **WEB proxy:** tproxy-server HTTPS carrier + loopback sidecar; `tg://webproxy?server=…&secret=…` links; masking-site catalog; separate Add SOCKS5 / MTProxy / WEB actions in proxy settings.

### Changed
- **Proxy auto-fetch:** stays **MTProxy-only**; WEB and SOCKS are manual; auto-rotate skips WEB and auto-pulled servers.

### Fixed
- **MTContext:** mutation-during-enumeration crash in listener broadcasts.
- **Calls:** UB/heap overflow in video-clone sink (nil `cloneRenderer`) and odd-length call-tone buffer.
- **Calls list:** incoming and missed rows now show directional type icons (mirrored outgoing PDFs; missed tinted destructive red).
- **WEB proxy:** release build + fail-closed sidecar configure on startup failure.

## [v12.9.2-3901] — 2026-08-21

Release: 3900 + AppDelegate `icons` `let` (same unused-var under `-c opt`).

## [v12.9.2-3900] — 2026-08-21

Release: same as 3899 + SettingsUI build fix (`appIcons` `let`).

## [v12.9.2-3899] — 2026-08-21

Release: **Телеграм** — premium icons, photo-send stability, crash fixes.

### Changed
- **Display name:** home screen → **Телеграм**.
- **App icons:** full custom premium gallery (**20** icons) — Blue/Classic/Filled/Black/White/New1–2 plus Premium Gold, Turbo, Black, Night, Rose, Emerald, Sunset, Ice, Carbon, Royal, Aurora. All unlocked in Appearance.

### Fixed
- **Photo send jetsam/OOM:** encode no longer loads `PHImageManagerMaximumSize`; Max≤1920; thermal shed to 1280; workers 3→2; `proactiveSaveMedia` off by default (+ migration).
- **Camera photo strip:** `Invalid batch updates` crash — reload when model/view counts diverge.
- **HLS player:** optional chaining on remaining `hlsPlayer_instances` JS call sites (seek/load/rate/level).
- **Modal present:** `presentWithContext:` ignores nil generator (avatar menu after dealloc).

## [v12.9.2-3898-pre] — 2026-08-21

Pre-release: full premium Телеграм icon gallery (20 icons).

### Changed
- **App icons:** every alternate icon restyled as premium (gradient disc + metal ring); primary Icon Composer adds a light ring.
- **Premium gallery:** +8 variants — Night, Rose, Emerald, Sunset, Ice, Carbon, Royal, Aurora (11 Premium* total).
- **Appearance:** all 20 icons listed with `isPremium`; no longer hidden when server Premium is disabled.

## [v12.9.2-3897-pre] — 2026-08-21

Pre-release: Russian **Телеграм** rebrand + full custom icon set (incl. Premium).

### Changed
- **Display name:** home screen / share → `Телеграм` (BUILD, xcconfigs, ar/ko overrides).
- **App icons:** all alternate + default + Icon Composer assets replaced with a custom paper-plane family (Blue / Classic / Filled / Black / White / New1–2).
- **Premium icons:** custom Gold, Turbo (pink→violet + gold plane), Premium Black (gold plane + ring); unlocked in Appearance for everyone (WhiteFilled no longer internal-only).

## [v12.9.2-3896-pre] — 2026-08-21

Pre-release: fix photo-send jetsam / heat.

### Fixed
- **Photo send OOM:** outgoing library encode no longer requests `PHImageManagerMaximumSize` (full-sensor RGBA, often 40–100+ MB) before downscale — asks Photos for the encode target size instead; worker pool 3→2; Max quality capped at 1920; thermal/LPM sheds to 1280.
- **Heat (Message Saving):** `proactiveSaveMedia` defaults off; one-shot migration turns it off for existing installs that inherited the old default-on.
- **Crash hardening:** remove force-unwrap on Lanczos filter and `image.cgImage` in outgoing media thumbnail prep.

## [v12.9.2-3895-pre] — 2026-08-21

Pre-release: brutal ZalupaGram icon.

### Changed
- **App icon:** heavier slab **Z**, near-black disc, blood-red cut slash (Icon Composer Mark + Slash layers; PNG sets refreshed).

## [v12.9.2-3894-pre] — 2026-08-21

Pre-release: rebrand to **ZalupaGram** + new app icon.

### Changed
- **Display name:** home-screen / share extension name is `ZalupaGram` (`CFBundleDisplayName` / `CFBundleName`, App Store + Fork xcconfigs, ar/ko InfoPlist overrides).
- **App icon:** paper-plane mark replaced with a bold white **Z** monogram on a magenta→violet circle (`Telegram.icon` Mark.svg + BlueIcon / DefaultAppIcon PNG sets).

## [v12.9.2-3893-pre] — 2026-08-21

Pre-release: HLS seek crash fix; Save Archive for critical logs.

### Fixed
- **HLS player:** seek-after-teardown JS exception (`playerNotifySeekedOnNextStatusUpdate` on destroyed instance) — optional chaining on the deferred `onSeeked` callback.

### Added
- **Debug → Send Critical Logs:** «Save Archive (Zip)» / «Сохранить архив (Zip)» — zip + system share sheet.

## [v12.9.2-3892-pre] — 2026-08-21

Pre-release: Russian Developer Mode / Debug menus; fix Message Saving localisation build break.

### Fixed
- **Build:** `MessageSavingHistoryController` localisation after `ForkPresentationLanguage` (was referencing missing `translations`).
- **Debug / Developer Mode:** all menu titles and action sheets follow app language (RU/EN) via `DebugLocalizedString`.

## [v12.9.2-3891-pre] — 2026-08-21

Pre-release: performance/folder/Ghost Mode follow-ups; commit history authored as decoder-dev (Claude trailers stripped).

### Fixed
- **Chat open:** drop the 250ms blocked-peers debounce on revision 0 so first history paint is not delayed.
- **Folders:** animated switch path; avoid stacked lists on tab tap; undo leftover pagination/scroll sync from earlier duplication attempts.
- **Regex filters:** long messages no longer silently disable every `<type>` filter.
- **Ghost Mode:** no longer mutes you in voice chats; archive Face ID unlock clears cooldown.
- **i18n:** fork strings follow app language, not device language.
- **Stability:** CDN key length + snapshot-gated state; dual-camera round-video races; playlist lazy vars across queues; launch breadcrumbs for crash diagnosis.

### Added
- **Developer Mode** Settings row and screen.

## [v12.9.2-3890-pre] — 2026-08-20

Pre-release: close remaining idealism regressions (composer morph/assets, themes, lists).

### Fixed
- **Build:** `ChatListNode` filter map type leftover after folders staleness drop; unused `strongSelf` after guard drop (`#no-usage` under release).
- **Composer:** `sendOccupiesActionSlot` matches keepSend/slowmode/search; paid-stars width reserved early; tooltip respects mic `isHidden`; scheduled send uses icon (not filled disc) on blue well; mic↔send morph scale+alpha both `0.18 easeInOut`; slot hit-gating; pointer circles 40pt; send/apply/schedule icons + stretchable disc on 40pt canvas.
- **Night/Day base themes:** outgoing secondary `white@0.8` on default path; Night chrome separators `@0.8`; outgoing media well `.clear`; Night waveform inactive `@0.65`.
- **Calls:** avatar 44 pt; **Contacts:** thread rows keep shared left column.
- **Media bubbles:** rename `.emptyWallpaper` → `.whenNoHeader` (header-only rule unchanged).

## [v12.9.2-3889-pre] — 2026-08-20

Pre-release: composer measure/wrap fix, full-bleed separators, media bubble rule, password fields.

### Fixed
- **Composer:** высота поля считается с тем же right inset, что и layout (текст и рост панели снова вместе); `updateTextHeight` / `updateLayout` — одна формула ширины; business-link не резервирует пустой attach-слот.
- **Folders:** selection pill index bound к `selectionFrames`.
- **Lists:** separators в chat/Calls/Contacts до правого края.
- **Night:** cloud-password / free input fields снова `#1C1C1E` (не чёрное на чёрном); placeholder `#636366`.

### Changed
- **Media bubbles:** рамка вокруг фото не зависит от wallpaper — только если нужен header (reply/author); иначе floating date.

## [v12.9.2-3888-pre] — 2026-08-20

Pre-release: Messages composer + follow-up polish (Calls column, contrast, icons).

### Fixed
- **Composer:** send снаружи капсулы (`maxX + 6`); same-slot mic↔send morph; слот через `mediaActionButtonsSlotFrame`; z-order только при инверсии; `isHidden` mic двусторонний; правый слот резервируется всегда (в т.ч. story reply / `.empty`).
- **Calls:** одна колонка аватаров — общий слот 22pt.
- **Icons:** `Call/Star` в rating HUD; video/slo-mo/timelapse badges через SF Symbols.

### Changed
- **Composer (Messages):** Plus слева вместо скрепки; Telegram long-press / video note / bots / slowmode / paid send сохранены.
- **Outgoing on #007AFF:** secondary `white@0.8`; waveform inactive отдельно; Night hairlines `@0.8`; placeholder Night `#636366`.

## [v12.9.2-3887-pre] — 2026-08-20

Pre-release: idealism — no overlaps, one accent, composer 40pt.

### Fixed
- **Calls:** исходящая иконка и voice-chat индикатор больше не залезают под 52pt аватар (резерв слота в `leftInset`).
- **Contacts:** иконка треда центрируется на `avatarFrame` (убран magic `-43`).
- **Composer:** капсула `2/2` → 40pt вровень с кругами attach/mic; `minimalHeight` из тех же insets.

### Changed
- **Day accent / folder pill:** `#3478F6` → `#007AFF` (один системный синий с bubble).
- **Night:** входящие ссылки/акценты и chat-list checkmarks `#007AFF`; elevated `#313131` → `#2C2C2E`.
- **Night palette cleanup (P0–P3):** surfaces `#000` / `#1C1C1E` / `#2C2C2E`; accent и bubble один `#007AFF`; secondary gray `#8E8E93`; destructive `#FF3B30`. Убраны legacy `#0F0F0F` / `#141414` / `#1C1C1D` / `#1F1F1F` / `#3478F6` / `#EB5545`.

## [v12.9.2-3881-pre] — 2026-08-19

Pre-release: fix chat folder switch duplication (regression).

### Fixed
- Переключение папок (Personal → All Chats и др.): дублирование чатов и «ломанный» экран.
- Регрессия `e2ed9433a3`: соседние preloaded-вкладки снова пагинировали в фоне (`isActiveForFolderPagination` default true).
- Apply-time guard по `locationGeneration` — stale transitions отбрасываются при apply.
- `deactivateFolderPagination()` сбрасывает `.navigation` при уходе с вкладки.
- Tab tap (`animated: false`) больше не форсит spring-slide.

## [v12.9.2-3878-pre] — 2026-08-19

Pre-release: brighter chat list search placeholder.

### Fixed
- «Поиск» в списке чатов (тёмная тема): placeholder и лупа ярче — 62% белого, как в композере.

## [v12.9.2-3877-pre] — 2026-08-19

Pre-release: OLED profile card layout (Contacts-style).

### Changed
- **Профиль (OLED):** кнопки действий (звонок / mute / search / more) вынесены из шапки в первую карточку `#1C1C1E` — 48×48 pt круги `#2C2C2E`.
- Шапка: только avatar + имя + статус на чёрном фоне.
- Info-карточка: подписи полей ярче (`#AEAEB2`, iOS tertiary label).
- Табы + контент (медиа, подарки…) в одной карточке `#1C1C1E` с inset как у Settings.
- id / dc / registered — одна строка footer мелким текстом вместо отдельных rows.

## [v12.9.2-3876-pre] — 2026-08-19

Pre-release: composer accessory row alignment + brighter placeholder.

### Fixed
- Timer / emoji / sticker кнопки в поле ввода: 40×40 pt, выровнены по нижнему ряду вместе с микрофоном и скрепкой (раньше 32 pt и «плавали» при многострочном тексте).
- Placeholder «Сообщение» в тёмной теме ярче (62% белого вместо 48%).

## [v12.9.2-3875-pre] — 2026-08-19

Pre-release: OLED-профиль (iOS Contacts), экран «Кастомизация». Sideload smoke, не Latest.

### Changed
- **Профиль (тёмная тема):** чёрная шапка вместо фиолетового градиента, круглые кнопки действий по центру, карточки `#1C1C1E`, тёмные pill-табы. Star-gift профили и все функции (mute, search, more…) сохранены. Светлая тема — штатный Telegram-профиль.
- **«Кастомизация»** вместо «Оформление»: убраны сетка тем, «Темы чатов», авто-ночной режим и «Ночная тема». Остались превью, обои, персональные цвета, размер текста, углы пузырей, иконка приложения.

### Fixed
- Дублирование чатов при переключении Personal → All Chats (фоновая пагинация неактивных вкладок).
- Иконка исходящего звонка больше не наезжает на аватар в списке звонков.
- Поиск и OLED-фоны: чистый `#000000` вместо серого `#272728`.
- Composer: круглые кнопки выровнены по нижнему краю поля ввода.

## [v12.9.2-3874-pre] — 2026-08-19

Pre-release: OLED UI fixes + folder duplication fix (без профиля/кастомизации). Superseded by `3875-pre`.

### Changed
- **Пункт «Оформление» убран из настроек.** Тема, цвет пузыря и радиус скругления теперь заданы форком, выбирать было нечего. Приложение следует системному светлому/тёмному: светло — Day, темно — Night. Сохранённые настройки на диске не трогаются — переписывается только копия, которую читает пайплайн, так что ничего не теряется. Экран остался доступен из поиска по настройкам, по `tg://settings/theme` и из пункта смены иконки.
- **Исходящий пузырь прибит к iOS-синему `#007AFF`** в Day и Night. Фиолетовые пузыри брались из самой темы Night: акцент `0x3e88f7` (дефолтный) разворачивался в градиент `0x0771ff → 0x9047ff → 0xa256bf`, а мой `#007AFF` лежал в дефолте темы, который читается только когда акцент не сохранён. Цена: половина выбора акцента, отвечающая за цвет пузыря, на этих двух темах теперь неактивна — акцент по-прежнему красит кнопки, ссылки и галочки. Подарочные и чат-темы приходят с `editing: false` и сохраняют цвета отправителя.
- **Кнопки микрофона и отправки снова круглые.** Им отдавалась высота поля ввода (52 pt при ширине 40), а фон рисуется прямоугольником этого размера со скруглением в половину высоты — получались овалы рядом с круглой скрепкой. Теперь 40×40, по нижнему краю поля, как скрепка. У кнопки отправки была та же болезнь с другой стороны: её фон получался вставкой 3 pt по обеим осям в коробку 46×высота, то есть квадрат выходил только при высоте ровно на 6 pt больше ширины. Вертикальная вставка теперь считается, а не задана константой.
- **Иконка приложения — отдельный пункт настроек.** Она жила внутри «Оформления» и уехала вместе с ним; это был побочный эффект, а не задача.
- **Оформление:** в списке тем остались только белая (Day) и чёрная (Night) — как в Messages. Classic (сине-зелёные обои) и Tinted Night (синий) убраны и из авто-ночной темы тоже. Если тема уже выбрана, она остаётся доступной, пока не переключишься; облачные темы не тронуты.
- **Авто-MTProxy под белыми списками:** парсер больше не выбрасывает прокси с IP вместо домена (в RU-списке это было 61 из 100), читает формат `host:port:secret`, а не только ссылки `tg://proxy`, и ставит FakeTLS-прокси (`ee`-секрет, подставляют SNI реального домена) первыми — и в очередь проверки, и в выбор до первого ответа. Пул 40 хранимых, 20 проверяемых, добавлен RU-список Chumbayoumba.
- **Поиск, Контакты, Звонки:** строки с 68 pt до 56 pt — аватар 44 pt вместо 52 pt списка чатов. В Messages эти строки ниже, чем строки чатов; текст остался на 72 pt, то есть в 2 pt от списка чатов.
- **Навбар чата снова стеклянный.** Была «‹ Назад» текстом поверх обоев рядом со стеклянной капсулой заголовка — одна панель в двух стилях. Теперь шеврон в своей капсуле и без подписи, как в Messages; обои по-прежнему идут под панель (в glass-режиме у неё нет своей заливки).

### Fixed
- Автопрокси больше не тасует сервера на шумном канале. Правило «любой кандидат быстрее на 50 мс побеждает» на VPN/мобильном канале попадает в разброс, поэтому пул перестраивался почти каждый круг проверки, а каждая перестановка рвёт и поднимает заново все соединения MTProto — отсюда «с VPN всё грузится долго». Теперь добровольное переключение требует +30% скорости и не чаще раза в минуту; отказавший сервер идёт через `excludedActiveServer` мимо обоих ограничений, так что реальный failover не изменился.
- Табличный индекс вкладок: три места брали `controllers[selectedIndex]` без верхней границы (два — вообще без проверок), а список вкладок пересобирается при запуске, при смене аккаунта и при включении вкладки «Звонки». Добавлен `selectedController`, который возвращает nil вместо падения. Это закрытие ловушки, а не подтверждённый диагноз вылетов — краш-лога нет.
- Failover прокси ушёл с главной очереди и перестал переписывать `forceLocalDNS` на каждый тик статуса соединения.
- Панель ввода больше не красится обоями. Поле, скрепка и круглая кнопка отправки брали `.panel`-стекло (белое 70% поверх блюра), из-за чего на зелёных обоях весь composer уходил в зелень. Теперь непрозрачная заливка от темы: `#E9E9EB` днём, `#1C1C1E` ночью.
- Сборка: `3860-pre` не компилировалась — после обнуления inset ветки скругления карточек стали недостижимы, а в проекте `-Werror`. Мёртвый код убран.
- Сборка: `3861-pre` падала следом на `contentBottomInset was never mutated` — удаление `+= 11.0` в HIG-фиксе оставило `var` без единой мутации. Стало `let`, пустая if/else-заглушка убрана.
- Журнал действий администратора: обои идут под навбар, как в чате, вместо стеклянной капсулы поверх них.
- ProxySettings больше не пишет дубль ключа авто-MTProxy, который никто не читал.

## [v12.9.2-3860-pre] — 2026-08-19

Pre-release: HIG layout fix (убрать белые полосы + вернуть классические обои/пузырь цвета). Sideload smoke, не Latest.

### Fixed
- Список чатов снова на всю ширину — убран 16 pt inset карточек (белые полосы по бокам).
- Чат: legacy nav bar над обоями, composer прижат к низу (без 8/11 pt зазоров).
- День/ночь: цвета пузырей с обоями возвращены к классическим Telegram (зелёные исходящие днём, градиент ночью), не iMessage-blue поверх кастомных тем.
- Галочки отправки снова видны на зелёных пузырях — цвет вернулся к `#19c700` (белый на бледно-зелёном давал контраст ~1.2:1).
- Звонки и Контакты тоже на всю ширину: у них оставался 16 pt inset карточек, убранный в списке чатов.

### Security
- **Авто MTProxy больше не включается сам.** Настройка была opt-out (дефолт `true`, в том числе в fallback декодера), поэтому при обновлении трафик уходил через случайный публичный прокси без ведома пользователя. Теперь по умолчанию выключено; у тех, кто включал вручную, ничего не меняется.
- Авто-обновление списка не перебивает вручную выбранный прокси и не включает обратно выключенный.

## [v12.9.2-3859-pre] — 2026-08-19

Pre-release: авто MTProxy — только RU у kort0881 + dubblebyte. Sideload smoke, не Latest.

### Changed
- **Авто MTProxy:** kort0881 берётся только RU-список (`proxy_ru.txt` вместо `proxy_all.txt`); добавлен [dubblebyte/free-mtproto-proxies](https://github.com/dubblebyte/free-mtproto-proxies). SoliSpirit `all_proxies.txt` без изменений. По-прежнему только доменные MTProxy (IP отбрасываются).

## [v12.9.2-3858-pre] — 2026-08-19

Pre-release: extras без обходов + время на HIG-пузырях. Sideload smoke, не Latest.

### Fixed
- **Архив с паролем:** превью из поиска и вкладка Channels больше не светят закрытые чаты; пуш при таймауте NSE не уходит с именем и текстом; Lock Now / фон закрывают и открытый архивный чат; mute на каждый аккаунт; снятие пароля не прячет папку; Archive/Unarchive в меню снова работают.
- Instant passcode только при реальном уходе в фон (Control Center больше не ломает пикеры).
- Hide Tab Bar: на iPhone Настройки остаются в шапке списка чатов; на iPad тумблер скрыт.
- Список чатов сразу перестраивается при hide-blocked / regex; «печатает» у заблокированных не светится.
- Remember last folder — отдельно на аккаунт.
- HIG: у текста/ссылок/rich-markdown снова время и галочки (tailless пузыри). Превью радиуса в настройках совпадает с чатом. Кнопки в контактах не вылезают из карточки. Заголовки списка чатов не залезают под аватар 52 pt.

## [v12.9.2-3857-pre] — 2026-08-19

Pre-release: весь интерфейс на HIG + фикс раскладки карточек. Sideload smoke, не Latest.

### Changed
- **Весь интерфейс** на том же HIG-языке, что и чаты: iOS blue `#3478F6` (таб, бейджи, send, action sheet, чекбоксы), grouped-карточки Settings/Extra (скругление 20 pt, холст чёрный / `#F2F2F7` днём), контакты и звонки — аватар 52 pt и карточки как список чатов.

### Fixed
- Компактный список чатов: аватар 52 pt больше не обрезается в строке 44 pt.
- Свайп удаления в звонках больше не прыгает на старую геометрию; info/дата/Join/чекбоксы остаются в карточке. Групповые звонки в той же карточке.
- Реакции на исходящих пузырях в day-теме — белые на синем, не leftover-зелёные Telegram.
- Release-сборка: убран неиспользуемый `bubbleStrokeColor` (из‑за него падал IPA `3856-pre`).

## [v12.9.2-3856-pre] — 2026-08-19

Pre-release: iOS Messages HIG look на все чаты. Sideload smoke, не Latest.

### Changed
- **Все чаты:** пузыри без «хвостиков», скругление 20 pt; в тёмной теме входящие `#2C2C2E`, исходящие iOS blue `#3478F6` на чёрном фоне (как Messages). Список чатов — карточка `#1C1C1E` на чёрном, аватар 52 pt, выбранная папка синей пилюлей.
- Extra и список чатов ближе к **Apple HIG** (платформенное поведение, не чужой визуал): grouped Extra с иконками Settings, стекла на disclosure, destructive «Заменить» при импорте БД.
- «Скрыть tab bar» на iPad больше не прячет панель вкладок (на iPadOS tab bar — основная навигация).
- Компактный список чатов не сжимает строки ниже 44 pt. Обычные строки чуть выше.

## [v12.9.2-3855-pre] — 2026-08-18

Pre-release: hardening extras crash paths. Sideload smoke, не Latest.

### Fixed
- iPad: Extra → экспорт/импорт БД сохранённых сообщений и шаринг вложений больше не падают из‑за `UIActivityViewController` / document picker без popover.
- Отправка фото (качество 1920/2560): не крашит на `PHImageResultIsDegradedKey` и `TGScaleImageToPixelSize`.
- Удаление / превью стикера при нулевых bounds больше не ловит `UIGraphicsGetCurrentContext()`.
- Двойной тап «править» не открывает редактор для стикеров, опросов и просроченных сообщений.
- Скрытие «Все чаты»: переключение папки не зависает на `.all`, leftover-папка убирается, пункт «Все чаты» в меню скрыт.

## [v12.9.2-3854-pre] — 2026-08-18

Pre-release: фикс белого экрана при запуске. Sideload smoke, не Latest.

### Fixed
- Запуск больше не зависает на белом экране, если чат-лист не успевает стать ready (скрытие «Все чаты» / смена папки / `switchToFilter` без completion). Через 2.5 с UI всё равно показывается.

## [v12.9.2-3853-pre] — 2026-08-18

Pre-release: Extra по разделам + фичи из Swiftgram. Sideload smoke, не Latest.

### Changed
- **Extra** больше не одна простыня. Хаб с кнопками: **Ниндзя** (сохранение удалённых/правок/медиа, фильтры, AyuForward), **Невидимка** (офлайн, прочтения, stories), **Приватность**, **Интерфейс**, **Чат**, **Сеть**.

### Added
- Скрыть вкладку «Все чаты», запоминать последнюю папку, скрыть tab bar.
- Секунды во времени сообщений, широкие посты, размер стикеров.
- Двойной тап по своему сообщению — править; быстрый перевод в меню.
- «В Избранное» и «Выбрать от автора» в контекстном меню.
- Ускорение загрузок (FetchV2) и качество исходящих фото (1280 / 1920 / 2560).

## [v12.9.2-3852-pre] — 2026-08-18

Pre-release: авто-прокси без показа серверов в списке. Sideload smoke, не Latest.

### Changed
- **Авто MTProxy** по умолчанию включён. Подобранные серверы не попадают в «Сохранённые прокси» и не светятся в настройках — в типе соединения просто «Авто». Свои вручную добавленные прокси по-прежнему видны.

## [v12.9.2-3851-pre] — 2026-08-18

Pre-release: фикс повторного включения Авто MTProxy + быстрее выбор прокси. Sideload smoke, не Latest.

### Fixed
- **Авто MTProxy:** выкл → вкл снова сразу поднимает список и активный сервер. Раньше повторная запись того же дампа отбрасывалась, `automaticServers` оставался пустым до перезапуска приложения.

### Changed
- Списки SoliSpirit и kort0881 применяются по мере прихода (не ждём оба URL). Первый живой сервер берётся сразу, RTT добирает более быстрый.
- В экране прокси в списке только свои серверы и текущий авто; пул авто не раздувает UI.

## [v12.9.2-3850-pre] — 2026-08-18

Pre-release: Auto MTProxy + фикс отправки файлов/музыки с устройства. Sideload smoke, не Latest.

### Added
- **Авто MTProxy:** opt-in подтягивание публичных списков MTProxy (SoliSpirit/mtproto и kort0881/telegram-proxy-collector), пробы RTT и переключение на самый быстрый живой сервер. Тогл в Extras и в Настройки → Данные и память → Прокси. Свои вручную добавленные прокси не затираются; выключение снимает только авто-список. Это чужие ноды: чаты они не читают, IP видят.

### Fixed
- **Files / Music picker:** отправка файлов и музыки с устройства (Files / «На iPhone») больше не пропадает молча. `startAccessingSecurityScopedResource() == false` больше не считается отказом в доступе — на iOS это часто значит, что URL уже в sandbox. Пикер вложений переведён на `.import`; при полном провале enqueue показывается ошибка вместо тишины. Также: не падать на `Int(inf)` у битого аудио, не отбрасывать имена с `%`, не оставлять несбалансированный security-scope (из‑за него следующие отправки тоже ломались).

## [v12.9.2-3846] — 2026-08-12

### Changed
- **Ads:** спонсорские / recommended сообщения отключены навсегда в клиенте (не запрашиваются и не вставляются в историю). Тогл в Extras заблокирован во «вкл».

### Also includes (from v12.9.2-3845, if that build was still in flight)
- AyuForward first-tap fix; thermal/LPM skip for proactive Save Media fetch; Liquid Glass / perf docs; per-release CHANGELOG in GitHub Release notes.

## [v12.9.2-3845] — 2026-08-12

### Fixed
- **AyuForward:** форвард noforwards / удалённых / TTL больше не падает молча с первого раза (media reference через `.message`, как у обычного forward).

### Changed
- **Save Media:** при Low Power Mode или thermal `.serious`/`.critical` не стартует opportunistic proactive download. Save Deleted / Edits и copy из кэша без изменений.

### Docs
- `docs/LIQUID_GLASS_AND_PERF.md` — что брать из Liquid Glass iOS 26 и как дальше резать «жратву».
- `docs/DEEDS.md` — опись недавних PR.
- Обновлён `docs/PERFORMANCE_AUDIT.md`.
- `CHANGELOG.md` + inject into CI release notes.

## [v12.9.2-3844] — 2026-08-11

### Fixed
- Fake-TLS SNI: восстановлены 4 нулевых байта в ClientHello DSL (регрессия «empty SNI»).
- Grid camera: снова `photo: true`, чтобы capture не крашился без `AVCapturePhotoOutput`.
- MessageSaving: mkdir Saved Attachments один раз на процесс; flush JSON при background не на main thread.

### Docs
- `docs/PERFORMANCE_AUDIT.md` — network/perf audit.

## [v12.9.2-3843] — 2026-08-11

### Fixed
- Harden MessageSaving import/export; iOS 13 document picker в ForkExtras import.
- Extras list `stableId` order / MessageSaving import-export bugs.

## Earlier

См. git history / предыдущие GitHub Releases (`v12.9.2-3842` и ниже). Новые релизы обязаны добавлять секцию `## [v…]` **перед** тегом.
