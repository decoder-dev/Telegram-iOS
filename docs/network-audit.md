# Network stack audit — stock engine hardening & WEB-proxy compatibility

Date: 2026-09-05. Scope: everything that moves bytes between this app and Telegram (and what
bypasses that path), with two goals from the product owner:

1. **Keep the stock engine** (MtProtoKit + TelegramCore's `Network`), fully hardened across all
   scenarios — reconnection, network transitions, background/foreground, downloads.
2. **Full WEB-proxy compatibility** — when a WEB proxy is active, nothing that can reveal the
   user's real IP to Telegram infrastructure should leave the device un-proxied.

Method: static audit of this tree (no macOS/Xcode available — see "Verification checklist").
Every claim below is backed by a file/line reference so it can be re-checked against code.

---

## 1. Architecture (as built)

```
TelegramCore Network.swift ── MTContext (stock: DC addresses, auth, salts, backup discovery)
        │                        │
        │                        ├── MTTcpConnection (obfuscated2 framing, above the transport seam)
        │                        │        ├── MTGcdAsyncSocketTcpConnectionInterface   (default: TCP)
        │                        │        ├── NetworkFrameworkTcpConnectionInterface  (experiment)
        │                        │        └── MTWebSocketConnectionInterface (fork, no-proxy only)
        │                        │                 └── MTWebSocketTransport → kwsN.web.telegram.org
        │                        └── MTTcpConnectionBehaviour (reconnect ladder, fork-hardened)
        │
        ├── MediaBox/FetchManagerImpl → FetchV2 → MultipartFetch → MultiplexedRequestManager
        │        └── media/CDN worker connections (same MTProto path → proxied)
        │
        └── WEB proxy (fork): ProxyServerSettings.connection == .web(secret)
                 └── WebProxyManager.shared (process-wide singleton)
                          └── WebProxySidecar (loopback MTProxy listener)
                                   └── WebProxyHttpCarrier (HTTPS POST lanes, frames, credit flow control)
                                            └── relay host (fixed-destination tunnel → stock MTProxy)
```

Key integration seam: `ProxyServerSettings.mtProxySettings` (`TelegramCore/Settings/ProxySettings.swift`)
returns, for a WEB server, an `MTSocksProxySettings` pointing at the **sidecar loopback endpoint**
with the WEB secret. To MtProtoKit the sidecar is an ordinary MTProxy, so the entire stock
engine — session, salts, temp keys, reconnection, media/CDN workers, download multiplexing —
rides it unchanged. `WebProxyManager` never receives raw MTProto bytes; it relays an opaque
obfuscated stream.

**Relay protocol fact that shapes everything below:** the carrier `OPEN` frame carries an
**empty payload** (`WebProxySidecar.swift:529`). The relay is a *fixed-destination tunnel*: every
stream lands on the relay's own backing MTProxy. There is no per-stream target addressing, so
nothing other than MTProto-over-MTProxy can be tunneled through the current relay protocol.

---

## 2. Scenario matrix — reconnection & lifecycle

All of these are **already implemented** in this tree. This is the "stock engine, fully worked
out" checklist, with the owning mechanism:

| # | Scenario | Mechanism | Where |
|---|----------|-----------|-------|
| 1 | Cold start with WEB active, sidecar not up | MtProto paused *at Network init*; explicit backup-IP discovery skipped; fail-closed (no direct dial) | `Network.swift:752` `markWebProxyBootstrapPausedAtInit`, `Account.swift:212` |
| 2 | WEB enabled at runtime (first enable) | `pauseForWebProxyBootstrap` holds MtProto; previous socks kept (no direct fallback) | `ProxySettings.swift:66-88`, `Network.swift:991` |
| 3 | Sidecar becomes ready | Per-account event handler re-applies settings → resume + loopback socks | `registerWebProxySidecarReapply` (`ProxySettings.swift:145`), `.becameReady` |
| 4 | Carrier dies mid-session | Sidecar tears down → `.stopped` event → reapply; exponential cooldown **with armed retry** (the old "dead until next foreground" bug is fixed) | `WebProxyManager.sequentialRestart`/`scheduleRetryLocked` |
| 5 | Carrier resumed in place after background | `carrierResumedInPlace` event forces `rebuildTransport` so MtProto re-dials the same port | `ProxySettings.swift:96-117` |
| 6 | Backgrounded | Sidecar knows `applicationDidEnterBackground`; a UIBackgroundTask sends one keep-alive PING so the next resume can skip the rebuild | `AppDelegate.swift:2084-2105` |
| 7 | Foreground resume | In-place carrier reconnect after real suspension (dwell ≥ 5 s), skip on Control-Center flickers or recent activity; forced restart past stale bootstrap markers | `WebProxyManager.applicationDidBecomeActive` |
| 8 | Wi-Fi ↔ cellular / VPN up-down (path satisfied throughout) | Sidecar rebuilds carrier in place on interface-set change; MtProto transport rebuilt with 1.5 s debounce | `WebProxyManager.handlePathUpdate`, `ManagedNetworkPathReconnect.swift` |
| 9 | Offline → online | Cooldown earned offline is cleared; forced start without waiting it out | `handlePathUpdate` (`WebProxyManager.swift:463`) |
| 10 | No network path | Bootstrap held (charging the cooldown for an offline failure is avoided) | `scheduleStart` guard (`WebProxyManager.swift:417`) |
| 11 | Loopback refuses instantly (relay dead) | Reconnect-storm guard: minimum 1 s between attempts on top of the 1/4/8 s ladder | `MTTcpConnectionBehaviour.m` (fork comment: 4,176 attempts / 25 s incident) |
| 12 | WS transport: per-attempt failure | Bounded 2-candidate endpoint walk; failure before `didConnect` only | `WebSocketEndpointSelector`, `websocket-transport.md` §6 |
| 13 | WS transport: session-level failure | 3 consecutive no-payload attempts → direct TCP (if fallback enabled); probe ladder 2 min → 30 min; success = MTProto payload carried | `WebSocketFallbackPolicy`, `applyWebSocketTransport` (`Network.swift:492`) |
| 14 | Proxy settings flipped (WS ↔ proxy) | Factory re-applied live + forced transport rebuild (first apply excluded) | `Account.swift:1582-1610` |
| 15 | SOCKS/MTProxy stuck connecting | RTT probe of all rotatable servers, switch to fastest, 30 s cooldown, re-arm loop | `ManagedProxyFailover.swift` (WEB excluded from rotation by design) |
| 16 | Transport scheme failure (FakeTLS mismatch etc.) | Scheme invalidated and rotated; backup address discovery begun | `MTProto.m:771` |
| 17 | DC address staleness | Backup discovery signal with 5–20 s delay on scheme setup; DoH via dns.google / mozilla.cloudflare-dns | `MTContext.m:1400-1426`, `MTBackupAddressSignals.m` |
| 18 | App active/background state | `shouldKeepConnection` driven by service-task-master; Share/NSE extensions set their own | `Account.swift:189`, `ShareExtensionContext.swift:78` |
| 19 | Download flood-wait | Per-resource FloodWait processing with backoff | `FetchV2.swift:890,1112` |
| 20 | Download stall / server redirect | CDN redirect + per-part hash verification + reupload handling | `MultipartFetch.swift` |
| 21 | Parallel download tuning | Fork "Download Speed Boost": `maxPendingParts` 12 vs 6 (rides the same proxied workers) | `FetchV2.swift:466` |

Multi-account correctness (a real class of bugs here): every account `Network` registers its own
sidecar event handler and settings re-apply (`Account.swift:228, 1579`) — the earlier
"one overwritten callback strands secondary accounts on the fail-closed route" bug class is
designed out.

**Assessment:** the reconnection/lifecycle story is genuinely complete for the MTProto path. The
stock engine was kept and hardened rather than replaced, exactly as the product goal asks. The
open items are not reconnect bugs — they are the coverage gaps in §4 and the unverified-build
items in §6.

---

## 3. Download path (works through WEB proxy)

`MediaBox` → `FetchManagerImpl` (scheduling, user pauses) → `FetchV2` (multipart, FloodWait,
speed boost) → `MultipartFetch` (CDN redirect, hashes) → `MultiplexedRequestManager` →
`Network.makeWorker(datacenterId:isCdn:isMedia:)` — i.e. **ordinary MTProto media/CDN
connections**, which dial through the sidecar socks settings like everything else. There is no
separate direct-to-CDN HTTP download path for Telegram-hosted media in this tree. Under WEB:

- Downloads multiplex over the sidecar's stream credit system (4 MiB initial window per stream,
  WINDOW grants back, 8 MiB uplink ceiling with amortized buffer compaction —
  `WebProxySidecar.swift:8-60`). Backpressure is explicit; nothing about the 12-part speed boost
  can overrun it (parts wait for credit, they don't fail).
- Relay batching is 2 MiB per POST with multiple lanes (`WebProxyHttpCarrier.swift:118,146`), so
  parallel parts translate into lane occupancy, not extra handshakes.

Verification item (not a code change): throughput of 12-part downloads through a WEB relay vs
direct, to confirm the boost setting is still a win over the carrier's batching latency (§6).

---

## 4. WEB-proxy compatibility matrix — what is and is NOT covered

| Traffic | Through WEB? | Notes |
|---|---|---|
| MTProto main connections | ✅ | socks = sidecar loopback |
| MTProto media + CDN download workers | ✅ | same path (§3) |
| Uploads (multipart upload) | ✅ | same workers |
| Backup DC-IP discovery **dialing** | ✅ (n/a) | With socks set, DC IPs are never dialed directly |
| Backup DC-IP discovery **DoH queries** | ❌ | `MTHttpRequestOperation` → `NSURLSession sharedSession` → dns.google.com / mozilla.cloudflare-dns.com. Reveals Telegram usage to the DoH resolver; under an active proxy the discovered addresses add nothing. See finding F-3 |
| **Calls (1:1, WebRTC: STUN/TURN/TCP/reflector)** | ❌ | `OngoingCallContext.swift:943-948`: `case .mtp, .web: break` — proxy ignored for calls (stock iOS behavior for MTProxy; WEB inherits it). Real IP is exposed to Telegram call infrastructure during a call. See finding F-1 |
| **Group calls / voice chats** | ❌ | Same tgcalls path, same exposure |
| External web content (link-preview media, `fetchHttpResource`) | ❌ | Direct `NSURLSession` to *external* hosts — by design; an MTProxy tunnel can't carry arbitrary HTTP, and these hosts are not Telegram infrastructure |
| In-app browser / web apps / bots (WKWebView) | ❌ | External sites, out of scope for a Telegram proxy |
| WEB-proxy catalog directory fetch | ❌ | External host, by design |
| Notification Service Extension | ⚠️ | Architecture is correct: `standaloneStateManager` → full `Account` → proxy settings + sidecar event handlers all run in the NSE process (`NotificationService.swift:923`, `Account.swift:228`). **Unverified** under NSE memory/time budgets — see finding F-2 |
| Share extension | ✅ (same design) | Creates its own account contexts; same wiring |
| WatchApp (standalone TDLib) | ❌ | Own networking, no WEB support — document as a limitation |

### F-1 — Calls bypass the WEB proxy (P1, product decision + protocol work)

Root cause is two-layered:

1. Client side: tgcalls in this tree only supports a SOCKS5 proxy for calls
   (`VoipProxyServerWebrtc(host:port:username:password:)`); MTProxy and WEB are skipped.
2. Relay side: even if the client side supported it, the current carrier protocol **cannot
   address an arbitrary target** — `OPEN` has an empty payload; the relay pipes every stream to
   its fixed backing MTProxy (`WebProxySidecar.swift:529`). A SOCKS5 listener on the sidecar has
   nothing to forward *to* without a relay-protocol extension.

Options, in increasing cost:

- **(a) Document + surface in UI (cheap, honest).** In the WEB-proxy settings screen, state that
  calls do not go through the proxy. A user enabling WEB for privacy currently has no indication
  that a 30-second call hands their real IP to Telegram's reflectors.
- **(b) Relay-protocol extension (full fix, needs relay-side work).** Add a target
  (host/port/443-domain) to `OPEN` payloads; relay dials arbitrary targets for streams that ask.
  Then add a SOCKS5 listener to the sidecar (each CONNECT maps to one carrier stream; the credit
  system already multiplexes streams) and hand `VoipProxyServerWebrtc` the loopback SOCKS5
  endpoint when WEB is active. Client-side sketch: `WebProxySidecar` gains a second listener +
  a ~200-line SOCKS5 greeting parser; `OngoingCallContext` gains a `.web` branch that asks
  `WebProxyManager` for the SOCKS endpoint. Server-side: relay change, not in this repo.
- **(c) Interim:** users who need call anonymity today can use a separate SOCKS5 proxy — the
  calls path already honors it — or disable P2P in call settings (reduces exposure to
  counterparties, not to Telegram infrastructure).

Recommended: do (a) now, (b) when/if the relay operator can ship the protocol extension.

### F-2 — NSE + WEB sidecar unverified (P1, verification + possible policy)

The NSE creates a standalone account per notification burst, which — with WEB active — starts a
full HTTPS carrier + sidecar inside the extension process. NSEs get ~24 MB soft memory budgets
and short CPU windows; a `NWListener` + multi-lane `URLSession` carrier is not obviously inside
them. If the extension is killed, push processing degrades to generic notifications.

The **wrong** fallback would be "NSE skips the WEB proxy and connects directly" — that is a real-IP
leak from the push path, strictly worse than degraded notifications. If the sidecar can't fit the
budget, the correct policy is "NSE does no network at all when WEB is active" (redacted/generic
notification content only, which the Archive-lock redaction machinery already knows how to
produce).

Verification steps: device with WEB active; send pushes with app killed; watch Console for
`jetsam`/extension-CPU kills; measure NSE peak memory with and without sidecar. Only then decide
policy. No blind code change.

### F-3 — Backup-IP DoH queries leak "uses Telegram" to Google/Cloudflare (P2)

`_beginBackupAddressDiscoveryWithDelay` arms whenever a DC needs a transport scheme
(`MTContext.m:1400-1426`), including when a proxy is active. The DoH requests are direct
(`MTHttpRequestOperation`, shared session). Under an active proxy the discovered DC addresses are
never dialed directly, so the discovery yields nothing the tunnel needs — only the metadata
exposure.

Candidate fix (small, but touches stock engine behavior — needs device verification): in
`MTContext._beginBackupAddressDiscoveryWithDelay`, return early when
`_apiEnvironment.socksProxySettings != nil`. Risk to check: the WS-transport path (no proxy) must
keep discovery; and a future "proxy dies, user disables it" flow must re-discover (it does — the
next scheme setup re-arms it).

### F-4 — Not-yet-built / not-yet-live-verified items (P0, hygiene)

The fork's own `websocket-transport.md` "Known limitations" section says it plainly: the WS
transport has not been built or verified against a live Telegram DC in this fork. The same is
true transitively for everything layered on the stock engine this audit re-read. The WS suite
exists and is now wired into `Tests/AllTests` (commit db8ecf8d) but has not been executed here.
First device build should walk the checklist in §6.

---

## 5. What deliberately was NOT changed

- The stock reconnect machinery stays stock except where a documented fork incident forced a
  change (1 s minimum attempt interval; path-change rebuild; bootstrap pause). No second retry
  loops, no alternative engines.
- `fetchHttpResource`, WKWebView traffic, and catalog fetches stay direct — they talk to
  non-Telegram hosts and cannot ride an MTProxy tunnel.
- WEB stays excluded from automatic proxy rotation (`ManagedProxyFailover.shouldManageRotation`)
  — silently rotating away from the user's privacy choice would be wrong.

## 6. Verification checklist (needs macOS/Xcode + device)

1. Build + run `Tests/AllTests` (now includes `MTWebSocketTransportTests`).
2. WS transport live check: `kwsN.web.telegram.org/apiws` handshake + payload; fallback ladder
   after forced failures.
3. WEB proxy: cold start (airplane → on), first enable, carrier kill (relay unreachable), path
   change Wi-Fi↔cellular with a live download, 10-minute background → resume, multi-account
   (secondary account must not strand on fail-closed route).
4. NSE: memory/CPU profile with WEB active (F-2).
5. Downloads: 12-part speed boost through relay vs direct (throughput sanity).
6. Calls with WEB active: confirm current direct behavior; verify option (a) copy if added.

## 7. Follow-ups out of network scope but noticed

- `MTBackupAddressSignals` uses a temporary in-memory keychain — fine.
- The DoH hosts are hardcoded to Google/Mozilla; a censorship-resilient build may want the
  relay-relative discovery variant (only meaningful together with F-1(b)'s protocol extension).
