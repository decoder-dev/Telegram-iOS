# WebSocket MTProto transport

An optional, off-by-default transport that carries MTProto over a WebSocket connection to Telegram's
own `kwsN.web.telegram.org` front-ends instead of a raw TCP socket, for users on networks that block or
throttle direct TCP/MTProto but allow ordinary HTTPS/WebSocket traffic. It reproduces the wire behavior
of [`Flowseal/tg-ws-proxy`](https://github.com/Flowseal/tg-ws-proxy) natively, without running a Python
process, a localhost MTProto-proxy listener, or any extra handshake/re-encryption layer.

## Relationship to Flowseal/tg-ws-proxy

Studied at commit **`b2a8074c59c52cabde7fe295280b614cc6c01fce`** (2026-08-13, "version bump"), MIT
licensed. tg-ws-proxy is a **local MTProxy server**: an external client connects to it with an MTProxy
secret (`tg://proxy?server=...&secret=...`), it decrypts that connection, generates a **second,
independent** MTProto obfuscation handshake, and re-encrypts the traffic for `kwsN.web.telegram.org`
over a hand-rolled WebSocket client (`proxy/bridge.py`, `proxy/raw_websocket.py`).

That re-encryption step only exists because tg-ws-proxy bridges an *external* MTProxy-secret client to
Telegram-over-WS. Telegram-iOS is not an external client: `MTTcpConnection` (MtProtoKit) already
produces the exact "obfuscated2" handshake format `kwsN.web.telegram.org` expects as its first message.
**Nothing in tg-ws-proxy's crypto/handshake layer needed to be ported.** Only two things were genuinely
new:

1. RFC 6455 WebSocket framing (tg-ws-proxy's `raw_websocket.py`).
2. The DC-number → `kwsN[-1].web.telegram.org` hostname/path table (tg-ws-proxy's `config.py`/`utils.py`).

No source was transliterated; both were reimplemented from reading tg-ws-proxy's logic, in the
architectural style already used by MtProtoKit/TelegramCore. Per tg-ws-proxy's MIT license this doesn't
require attribution beyond this note, but it's recorded here in case tg-ws-proxy's DC table or framing
behavior changes upstream and this fork needs to be compared against a specific commit again.

### Component classification

| tg-ws-proxy component | Disposition | Why |
|---|---|---|
| MTProxy-secret handshake decode, client-facing AES-CTR | **Not needed** | Only exists to terminate an *external* client's MTProxy connection; the app talks to its own transport directly. |
| Fresh "obfuscated2" handshake generator (`_generate_relay_init`) | **Reused, not ported** | `MTTcpConnection` (MtProtoKit) already generates this exact format for the existing TCP transport. |
| Re-encrypt bridge (`CryptoCtx`, `bridge.py`) | **Not needed** | A consequence of the two points above; nothing to re-encrypt when there's only one MTProto stream to begin with. |
| WS HTTP-upgrade handshake | **Ported** (`MTWebSocketConnectionInterface.beginWebSocketHandshake`) | Genuinely new protocol surface. |
| WS binary framing / masking / fragmentation / ping-pong / close | **Ported** (`MTWebSocketTransport` module) | Genuinely new protocol surface; also the part the task asked to keep testable, so it's hand-rolled rather than delegated to `NWProtocolWebSocket`. |
| DC → hostname/path mapping, incl. media ordering swap | **Ported** (`WebSocketDatacenterMapping.swift`) | Genuinely new: Telegram's own client code has no equivalent table. |
| DC 203 special case | **Ported** (folds to DC 2, matching tg-ws-proxy) | Cheap to keep, avoids a subtle mismatch if this DC is ever hit. |
| Test-DC `+10000` offset sniffing / `--force-test-dc` | **Not needed** | tg-ws-proxy needs this because *its* clients (Telethon/TDLib-style) can't otherwise signal test-DC; MtProtoKit already knows `context.isTestingEnvironment` directly. |
| `_WsPool`/`_CfWorkerPool` connection pooling, SNI domain-fronting | **Not needed** | Exists to serve many concurrent local proxy clients from one process; irrelevant to a single-account app with its own small fixed connection count. Domain-fronting (`sni="sprinthost.ru"`) also conflicts with keeping real TLS validation. |
| `_Balancer` / Cloudflare Worker & Cloudflare-proxy fallback | **Not implemented (this pass)** | Explicitly deprioritized by the task; the endpoint-candidate abstraction (`WebSocketEndpointCandidate`) leaves room to add a CF-Worker candidate later without another MtProtoKit-level change. |
| Raw-TCP fallback inside tg-ws-proxy's own balancer | **Reused, not ported** | This is exactly what `MTTcpConnection`'s default `MTGcdAsyncSocketTcpConnectionInterface` already is — see "Fallback policy" below. |
| FakeTLS (`fake_tls.py`) | **Not needed** | Disguises tg-ws-proxy's *inbound* localhost listener; there is no local listener here. |
| Packet-boundary reconstruction after re-encryption (`MsgSplitter`) | **Reused, not ported** | MtProtoKit already frames discrete MTProto packets above the transport interface; this problem doesn't exist at this layer. |
| CERT_NONE / check_hostname=False TLS config | **Deliberately not ported** | See "TLS / security" below. |
| Tray UI, HTTP management API, PyInstaller packaging, desktop config, process lifecycle | **Not needed** | Exist only because tg-ws-proxy is a standalone desktop application. |

## Architecture

```
TelegramCore
     |
     v
MtProtoKit (MTContext / MTTcpConnection)
     |
     +---- MTGcdAsyncSocketTcpConnectionInterface   (default: raw TCP)
     |
     +---- NetworkFrameworkTcpConnectionInterface   (existing opt-in: raw TCP via Network.framework)
     |
     +---- MTWebSocketConnectionInterface           (new: WebSocket)
                 |
                 | TLS (default cert validation) + RFC 6455 framing
                 v
        kwsN.web.telegram.org / kwsN-1.web.telegram.org
                 |
                 v
            Telegram DC
```

### Where this plugs in

MtProtoKit already has a pluggable low-level byte-transport seam, `MTTcpConnectionInterface`
(`submodules/MtProtoKit/PublicHeaders/MtProtoKit/MTContext.h`), and a second implementation of it
already exists (`NetworkFrameworkTcpConnectionInterface.swift`, gated behind the debug-only
`NetworkSettings.useNetworkFramework` flag). All MTProto packet framing, length-prefixing and
obfuscation (plain, intermediate, or MTProxy-secret-obfuscated, including the FakeTLS ClientHello for
domain-fronting secrets) live in `MTTcpConnection.m`, *above* this interface — the interface only ever
sees fully-formed byte blobs via `writeData:` and hands back raw bytes via
`readDataToLength:withTimeout:tag:`. That is the reason a WebSocket transport needs zero MTProto/crypto
changes: it just has to move the same already-correct byte stream over a different transport.

`MTWebSocketConnectionInterface` (`submodules/TelegramCore/Sources/Network/MTWebSocketConnectionInterface.swift`)
implements that interface. It is wired in from `Network.swift` via
`context.makeTcpConnectionInterface`, the same mechanism `NetworkFrameworkTcpConnectionInterface` uses —
no new connection-lifecycle manager, no new transport class, no changes to `MTTransport`/`MTTcpTransport`
(scheme selection, reconnection backoff, actualization pings, background/foreground handling — all of it
is reused unchanged).

### One extension to the existing interface contract

The factory closure `MTContext.makeTcpConnectionInterface` originally only received a delegate and a
queue. `MTTcpConnection` resolves `connectToHost:` to the *literal DC IP* for the normal TCP path, which
is meaningless to a WebSocket front-end whose hostname/IP bear no relation to the DC's direct IP. The
closure was extended (in `MTContext.h` and the one call site in `MTTcpConnection.m`'s `start` method) to
additionally pass `datacenterId`, `isMedia`, and `isTestingEnvironment`, and its return type was widened
from non-optional to optional (`id<MTTcpConnectionInterface> _Nullable`, matching the runtime nil-check
that was already there) so a factory can signal "give up on this alternate transport for this attempt" —
used by the fallback policy below. `MTWebSocketConnectionInterface` uses these three values to compute
its own list of WS hostnames via `WebSocketEndpointPlanner`, and ignores the `inHost`/`port` it's handed.

### New isolated module: `MTWebSocketTransport`

All *pure, protocol-level* logic — RFC 6455 frame encode/decode/reassembly, the DC→hostname/path
mapping, and endpoint/fallback state machines — lives in a standalone Swift module,
`submodules/MTWebSocketTransport/`, with **zero dependency on TelegramCore, MtProtoKit, or Foundation
networking**. This is what makes it unit-testable without a live Telegram server or a running app:

- `WebSocketFrame.swift` — `WebSocketFrameEncoder`/`WebSocketFrameDecoder` (stateless, pure functions
  over `Data`) plus `WebSocketMessageReassembler` (the one stateful piece: buffers partial reads,
  reassembles fragmented messages, surfaces ping/pong/close/protocol-error events).
- `WebSocketDatacenterMapping.swift` — `WebSocketDatacenter.hostnames(datacenterId:isMedia:)`,
  `.path(isTestingEnvironment:)`, and `WebSocketEndpointPlanner.candidates(...)` combining both.
- `WebSocketFallbackPolicy.swift` — `WebSocketEndpointSelector` (walks primary → secondary endpoint for
  one connection attempt) and `WebSocketFallbackPolicy` (counts consecutive "every endpoint failed"
  outcomes across reconnects, signals when to give up on WS for the session).

`MTWebSocketConnectionInterface.swift` (in `TelegramCore/Sources/Network/`, alongside
`NetworkFrameworkTcpConnectionInterface.swift`) is the thin networking glue: it owns an `NWConnection`
per candidate (TCP + TLS), performs the WS HTTP-upgrade handshake, and drives `MTWebSocketTransport`'s
pure logic to turn the WS byte stream into the same `readDataToLength:`-style read-request queue
`NetworkFrameworkTcpConnectionInterface` already implements for raw TCP.

## Connection flow

1. `MTTcpConnection` calls `context.makeTcpConnectionInterface(delegate, queue, datacenterId, isMedia,
   isTestingEnvironment)`. If WebSocket transport is enabled and the fallback coordinator hasn't given up
   at the moment the connection is opened, this returns an `MTWebSocketConnectionInterface`; MtProtoKit calls `connectToHost:`
   on it exactly as it would a TCP interface.
2. The interface computes its candidate list via `WebSocketEndpointPlanner.candidates(datacenterId:
   isMedia: isTestingEnvironment:)` — media connections try `kwsN-1.web.telegram.org` first, then
   `kwsN.web.telegram.org`; non-media connections try the base host first, matching tg-ws-proxy's
   `ws_domains()` ordering.
3. For the current candidate: open an `NWConnection` (TCP + TLS, default certificate/hostname
   validation, SNI derived automatically from the hostname) to `host:443`.
4. On TLS-ready, send a manual HTTP/1.1 `Upgrade: websocket` request (`GET /apiws` or `/apiws_test`,
   `Sec-WebSocket-Key`, `Sec-WebSocket-Version: 13`), then read until a `101` status line + the
   `Upgrade`/`Connection` headers are seen. (See "Security decisions" for why `Sec-WebSocket-Accept`
   itself is not cryptographically verified.)
5. Once upgraded, MtProtoKit's `writeData:` calls become RFC 6455 masked binary frames; inbound WS
   frames are reassembled (handling fragmentation, ping/pong, close) and their payload bytes are handed
   back to MtProtoKit's `readDataToLength:` queue exactly as a continuous byte stream — same semantics
   as the raw-TCP interface, regardless of how WS frame boundaries happen to line up with MTProto packet
   boundaries.
6. If a candidate fails (TCP/TLS error, handshake rejected, framing protocol error, connect timeout,
   loss of path viability) **before the connection has been reported to `MTTcpConnection`**, the
   interface logs it and dials the next candidate. If all candidates in the list fail, the attempt is
   reported as failed to `MTTcpConnection`, which redials through MtProtoKit's existing
   `MTTcpConnectionBehaviour` backoff — no second retry/backoff loop was invented.

   Once `connectionInterfaceDidConnect` has been delivered the endpoint list is frozen and any later
   failure becomes a plain disconnect instead. Swapping the socket underneath a live
   `MTTcpConnection` would be silently fatal: it prepends its 64-byte obfuscation header to the
   *first* packet only and then keeps encrypting with a per-connection AES-CTR stream, so the
   replacement endpoint would be handed mid-stream ciphertext with no init — and `MTTcpConnection`
   would see a second `connectionInterfaceDidConnect` with no disconnect in between. It is one-shot
   by design; MTProto discards it and builds a new one, which dials the endpoint list afresh.
7. Each attempt's outcome is recorded in a per-`MTContext` `WebSocketFallbackPolicy`. After 3
   consecutive failed attempts, and only if the user's "Fallback to Direct Connection" setting is on,
   the factory closure starts returning `nil`, which makes `MTTcpConnection` fall through to its
   default `MTGcdAsyncSocketTcpConnectionInterface` (ordinary TCP).

   That fallback is not the end of it. What makes WebSocket fail is a property of the network the
   device is on, and that changes underneath a running app — the user leaves the network, moves
   between cellular and Wi-Fi, lands in another country. So the coordinator re-opens on its own:
   after 2 minutes it lets **one** connection through while the rest stay on direct transport, and
   doubles the wait to a 30-minute ceiling each time that probe fails. A probe that carries traffic
   lifts the fallback outright. On a network that never recovers this costs about 14 probes over six
   hours; on one that recovers ten minutes in, WebSocket is back within two.

   What counts as success is **the peer delivering MTProto payload**, not a completed WebSocket
   handshake. The gateway accepts the upgrade before it has seen a single byte of the stream it may
   then reject, so counting the handshake would reset the counter on every attempt and the fallback
   would never engage against exactly the failure mode it exists for. A connection torn down at
   `MTTcpConnection`'s own request is neutral — neither success nor failure.

## DC mapping

Reproduces tg-ws-proxy's `proxy/config.py`/`proxy/utils.py` behavior (`WebSocketDatacenter` in
`WebSocketDatacenterMapping.swift`):

- Production path: `/apiws`. Test-DC path: `/apiws_test` (selected from `context.isTestingEnvironment`,
  not sniffed from the DC number the way tg-ws-proxy has to for its non-Telegram-iOS clients).
- Hostnames for DC *N*: `kwsN.web.telegram.org` and `kwsN-1.web.telegram.org`.
- **Media connections** try `kwsN-1` first, then `kwsN`. **Non-media connections** try `kwsN` first, then
  `kwsN-1`. (Matches tg-ws-proxy's `ws_domains()`.)
- DC 203 folds to DC 2's hostnames.
- Covers DCs 1–5 (the mainline production/test set); nothing else is currently special-cased.

## Fallback behavior

Two independent levels, both reusing existing mechanisms rather than inventing new ones:

- **Within one connection attempt**: primary endpoint → secondary endpoint (`WebSocketEndpointSelector`,
  bounded — exactly two candidates per DC/media combination, never an unbounded loop — and only until
  the connection is reported to `MTTcpConnection`, per step 6 above).
- **Across reconnect attempts**: MtProtoKit's existing `MTTcpConnectionBehaviour` owns retry/backoff
  timing (unchanged). `WebSocketFallbackPolicy` only tracks *whether* WS should still be attempted; after
  3 consecutive attempts that never carried MTProto payload, and only when "Fallback to Direct
  Connection" is enabled, the factory closure hands control back to MtProtoKit's default TCP transport
  by returning `nil` — reconsidered periodically, per the probe schedule in step 7. If the setting is
  off, the app keeps retrying WebSocket
  endpoints only, since for a user whose whole point is bypassing TCP-level blocking, silently falling
  back to the blocked transport would defeat the feature and make failures hard to diagnose.

Direct TCP, SOCKS5, and MTProto-proxy transport are untouched: they're `MTTcpConnection`'s existing
default path, available whenever the factory returns `nil` (feature on but exhausted) or the feature is
off. Turning the feature off restores whatever factory the account was using before rather than clearing
it — on an account with the `NetworkSettings.useNetworkFramework` experiment enabled that is
`NetworkFrameworkTcpConnectionInterface`, and otherwise nothing, which is `MTTcpConnection`'s own
default. `setDefaultTcpConnectionInterface` in `Network.swift` is the single place that choice is made;
`applyWebSocketTransport` defers to it on every path that is not "WebSocket transport is on".

## TLS / security decisions

- **Certificate validation is not weakened.** `NWProtocolTLS.Options()` is constructed with Apple's
  default `sec_protocol_options` — full certificate-chain and hostname validation — the same default
  Network.framework uses everywhere else in this codebase (see `NetworkFrameworkTcpConnectionInterface`).
  tg-ws-proxy's `check_hostname = False` / `verify_mode = ssl.CERT_NONE` (applied unconditionally to
  every outbound WS connection, not only its domain-fronting path) was deliberately **not** ported.
- **SNI** is derived automatically by Network.framework from the `NWEndpoint.Host` hostname
  (`kwsN.web.telegram.org` / `kwsN-1.web.telegram.org`) when using `NWConnection` with TLS — no manual
  override needed or performed.
- **`Sec-WebSocket-Accept` is not cryptographically verified** against the `Sec-WebSocket-Key` sent (only
  the `101` status line and `Upgrade`/`Connection` headers are checked). This mirrors tg-ws-proxy's own
  client behavior. It's a deliberate simplification, not an oversight: that header is an RFC 6455
  protocol-conformance echo, not a security boundary. The channel's actual security comes from (a) TLS
  certificate validation, already enforced, and (b) MTProto's own auth-key/obfuscation layer above this
  transport, neither of which derives anything from this value.
- **No `NSAllowsArbitraryLoads`, no ATS changes.** Not needed — `NWConnection` with `NWProtocolTLS` isn't
  subject to ATS's `NSURLSession`-oriented policy the way plain HTTP loads are, and this connection
  always uses TLS.
- **Logging** never includes auth keys, MTProto secrets, session data, or payload contents — only
  DC/media/endpoint/transport/failure-category metadata, e.g.:
  ```
  [WS] DC2 media -> kws2-1.web.telegram.org/apiws
  [WS] handshake OK (kws2-1.web.telegram.org)
  [WS] endpoint kws2-1.web.telegram.org failed (timeout/protocol error)
  [WS] trying secondary endpoint
  [WS] no endpoint carried traffic on 3 attempts in a row, falling back to direct transport; will probe again in 120s
  [WS] probing whether WebSocket works again after 120s on direct transport
  [WS] probe carried traffic, WebSocket transport is back in use
  ```

## Settings

Two new fields on the existing `ProxySettings` model (`SyncCore_ProxySettings.swift`), persisted through
the same Postbox `SharedDataKeys.proxySettings` / `PreferencesEntry` mechanism the SOCKS5/MTProxy server
list already uses — no new persistence machinery:

- `webSocketTransportEnabled: Bool` (default `false`) — the feature is off by default.
- `webSocketFallbackToDirect: Bool` (default `true`) — falls back to direct TCP after repeated failure;
  can be turned off for users who specifically want to keep retrying WebSocket only.

Surfaced in `Settings → Data and Storage → Proxy` (`ProxyListSettingsController.swift`) as a new
"WebSocket Transport" section below the existing "Use for Calls" section: an enable toggle, a
fallback-to-direct toggle (shown only while WS transport is enabled), and an explanatory footer. It is
intentionally independent of the SOCKS5/MTProxy server list above it (`enabled`/`servers`/`activeServer`)
— WS transport changes *how* MtProtoKit opens its socket, not *which* proxy server is used, and DC
hostnames are not exposed to the user.

Both toggles apply to a running account without a relaunch. `Account.swift` subscribes to
`SharedDataKeys.proxySettings`, re-runs `applyWebSocketTransport` against the live `MTContext`, and then
calls `Network.rebuildTransport()`. That last step is required, not cosmetic: `MTTcpConnection` captures
`makeTcpConnectionInterface` when it is constructed, so replacing the factory on the context leaves every
existing connection on the old transport. `rebuildTransport` goes through `MTProto`'s `pause()`/`resume()`
— the only public route to `resetTransport` — and consults the current `shouldKeepConnection` value first,
because `MTProtoStatePaused` is a flag rather than a counter and an unconditional `resume()` would wake a
connection the app had deliberately paused. The subscription's first emission is skipped, since
`initializedNetwork` has already applied those same values and rebuilding there would restart a connection
that is still coming up.

**Known limitation**: the new UI strings are literals rather than keys routed through the project's
generated `PresentationStrings` pipeline. They follow the bilingual RU/EN pattern the fork's other
proxy-screen additions use (`ForkPresentationLanguage.prefersRussianStrings`), so they are not
English-only, but they are not localized beyond those two languages either. Follow-up: add proper
`Localizable.strings` keys and regenerate `PresentationStrings` once the feature ships broadly.

## Testing

`submodules/MTWebSocketTransport/` has its own `ios_unit_test` target (`MTWebSocketTransportTests`),
mirroring the project's existing `//submodules/TextFormat:TextFormatTests` pattern. Run it the way
`CLAUDE.md` documents for a single target:

```
source ~/.zshrc 2>/dev/null; python3 build-system/Make/Make.py --overrideXcodeVersion \
 --cacheDir ~/telegram-bazel-cache \
 test --configurationPath build-system/appstore-configuration.json \
 --gitCodesigningRepository git@gitlab.com:peter-iakovlev/fastlanematch.git \
 --gitCodesigningType development --gitCodesigningUseCurrent \
 --target //submodules/MTWebSocketTransport:MTWebSocketTransportTests
```

**Not yet run in this fork.** The suite passed upstream in the repository it was ported from, but nothing
here has been built or executed — see "Known limitations". The `ios_test_runner` in
`submodules/MTWebSocketTransport/BUILD` pins `os_version = "26.5"` / `iPhone 17` to match
`//submodules/TextFormat:TextFormatTests`, this fork's other `ios_unit_test`; the default runner picks an
invalid device and the test process exits 15.

Coverage: small/126+-byte/65536+-byte frames (7/16/64-bit length encoding), masking round-trip,
unmasked-frame decoding, ping/pong, close (with/without code+reason), single- and multi-step
fragmentation reassembly, partial input split across feeds (including a byte-at-a-time worst case),
multiple complete frames delivered in one buffer, malformed input (non-zero RSV bits, unknown opcode,
oversized length) rejection, DC→hostname ordering for DCs 1–5 and the 203→2 fold, production/test path
selection, and the endpoint-selector/fallback-policy state machine (primary→secondary, exhaustion,
reset-on-success, threshold-triggered fallback signal). None of it depends on a live Telegram server or
device — it's all pure logic over synthetic byte buffers, so it can't be flaky.

No test exercises a live `kwsN.web.telegram.org` connection; that would require network access and would
be flaky and environment-dependent. The networking glue in
`MTWebSocketConnectionInterface.swift` is therefore verified by code review and (pending environment
availability — see "Known limitations") a real device/simulator run, not by automated tests.

## Known limitations

- **Not yet verified against a live Telegram DC**, and not yet built. This document and the code under
  it were ported into this fork in an environment without Bazel, so every claim here rests on review and
  on reasoning against this tree's own sources, not on a compiler or on traffic. Building it and
  confirming that `kwsN.web.telegram.org/apiws` actually accepts this handshake is the outstanding
  verification step.
- **Sec-WebSocket-Accept is not cryptographically checked** (see "TLS / security decisions" — deliberate,
  not a gap in the security model, but worth knowing if a stricter WS-conformance check is ever desired).
- **Cloudflare Worker / Cloudflare-proxy fallback is not implemented.** `WebSocketEndpointCandidate` is
  structured so a future candidate type could be added without another MtProtoKit-level change, but no
  such candidate exists yet.
- **UI strings are RU/EN literals**, not routed through the localization pipeline (see "Settings").
- **DC 203 handling is untested against real traffic** — folded to DC 2 per tg-ws-proxy's own behavior,
  but this fork has no way to exercise it live.
- **Background/foreground transition handling was not independently re-verified for the WS path.** It
  reuses `MTTcpTransport`'s existing (transport-agnostic) reconnection triggers, but the initial research
  pass flagged that `MTTcpTransport`'s own "sleep watchdog" mechanism is currently `#if false`'d out
  upstream — any gap there is pre-existing and applies equally to the TCP transport, not introduced by
  this change.

## Updating this fork when either upstream project changes

- **If `Flowseal/tg-ws-proxy` changes its DC↔hostname table, path names, or framing behavior**: diff the
  new commit against `b2a8074c59c52cabde7fe295280b614cc6c01fce` (the commit this implementation was
  derived from), focusing on `proxy/config.py`, `proxy/utils.py`, and `proxy/raw_websocket.py`. Update
  `WebSocketDatacenterMapping.swift` and/or `WebSocketFrame.swift` accordingly, and add/adjust the
  corresponding test in `submodules/MTWebSocketTransport/Tests/`.
- **If `TelegramMessenger/Telegram-iOS` upstream changes MtProtoKit's transport layer**: the integration
  surface is intentionally small — `MTContext.h`'s `makeTcpConnectionInterface` property (now 5 closure
  params instead of 2, nullable return) and `MTTcpConnection.m`'s `start` method (two new ivars, one call
  site passing them through). If a merge conflicts here, re-apply the same three changes: (1) extend the
  factory closure with `datacenterId`/`isMedia`/`isTestingEnvironment` params and a nullable return type,
  (2) store `_datacenterId`/`_isTestingEnvironment` ivars set from the existing init parameters, (3) pass
  them at the one `_makeTcpConnectionInterface(...)` call site. Everything else this feature touches
  (`MTWebSocketConnectionInterface.swift`, the `MTWebSocketTransport` module, the `Network.swift` branch,
  the `ProxySettings` fields, the Settings UI section) is additive and should merge cleanly on its own.
