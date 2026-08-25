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
   for this session, this returns an `MTWebSocketConnectionInterface`; MtProtoKit calls `connectToHost:`
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
   loss of path viability), the interface logs it and dials the next candidate. If all candidates in the
   list fail, the attempt is reported as failed to `MTTcpConnection`, which redials through MtProtoKit's
   existing `MTTcpConnectionBehaviour` backoff — no second retry/backoff loop was invented.
7. Every "all candidates failed" outcome is also recorded in a per-`MTContext`
   `WebSocketFallbackPolicy`. After 3 consecutive such outcomes, and only if the user's "Fallback to
   Direct Connection" setting is on, the factory closure starts returning `nil`, which makes
   `MTTcpConnection` fall through to its default `MTGcdAsyncSocketTcpConnectionInterface` (ordinary TCP)
   for the rest of the session. A later successful WS connection resets the counter.

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
  bounded — exactly two candidates per DC/media combination, never an unbounded loop).
- **Across reconnect attempts**: MtProtoKit's existing `MTTcpConnectionBehaviour` owns retry/backoff
  timing (unchanged). `WebSocketFallbackPolicy` only tracks *whether* WS should still be attempted; after
  3 consecutive fully-failed attempts, and only when "Fallback to Direct Connection" is enabled, the
  factory closure hands control back to MtProtoKit's default TCP transport for the rest of the session by
  returning `nil`. If the setting is off, the app keeps retrying WebSocket endpoints only, since for a
  user whose whole point is bypassing TCP-level blocking, silently falling back to the blocked transport
  would defeat the feature and make failures hard to diagnose.

Direct TCP, SOCKS5, and MTProto-proxy transport are untouched: they're `MTTcpConnection`'s existing
default path, unconditionally available whenever `context.makeTcpConnectionInterface` isn't set (feature
off) or returns `nil` (feature on but exhausted).

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
  [WS] all endpoints failed 3 times in a row, falling back to direct transport for this session
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

**Known limitation**: the new UI strings are hardcoded English literals, not routed through the
project's generated `PresentationStrings` localization pipeline — that pipeline is a large generated
surface and wiring in new keys for every supported language was out of scope for this pass. Follow-up:
add proper `Localizable.strings` keys and regenerate `PresentationStrings` once the feature is ready to
ship broadly.

## Testing

`submodules/MTWebSocketTransport/` has its own `ios_unit_test` target (`MTWebSocketTransportTests`),
mirroring the project's existing `//submodules/TextFormat:TextFormatTests` pattern. This fork doesn't use
Telegram's private git-based codesigning repository, so use `--xcodeManagedCodesigning` instead of
`--gitCodesigningRepository`/`TELEGRAM_CODESIGNING_GIT_PASSWORD`:

```
python3 build-system/Make/Make.py --overrideXcodeVersion --cacheDir ~/telegram-bazel-cache \
 test --configurationPath build-system/appstore-configuration.json \
 --xcodeManagedCodesigning \
 --target //submodules/MTWebSocketTransport:MTWebSocketTransportTests
```

Verified passing (real Bazel `ios_unit_test`, iOS 26.0 simulator, iPhone 17): **33/33 tests, 0 failures**.
The `ios_test_runner` in `submodules/MTWebSocketTransport/BUILD` pins `os_version = "26.0"` to match the
simulator runtime actually installed in this dev environment — bump it if a newer runtime is the local
default elsewhere. The same logic was also independently smoke-tested via a throwaway standalone SwiftPM
package (bypassing Bazel entirely) with identical results, before the Bazel toolchain was available.

Coverage: small/126+-byte/65536+-byte frames (7/16/64-bit length encoding), masking round-trip,
unmasked-frame decoding, ping/pong, close (with/without code+reason), single- and multi-step
fragmentation reassembly, partial input split across feeds (including a byte-at-a-time worst case),
multiple complete frames delivered in one buffer, malformed input (non-zero RSV bits, unknown opcode,
oversized length) rejection, DC→hostname ordering for DCs 1–5 and the 203→2 fold, production/test path
selection, and the endpoint-selector/fallback-policy state machine (primary→secondary, exhaustion,
reset-on-success, threshold-triggered fallback signal). None of it depends on a live Telegram server or
device — it's all pure logic over synthetic byte buffers, so it can't be flaky.

No test exercises a live `kwsN.web.telegram.org` connection; that would require network access and would
be flaky/environment-dependent in CI, which the task explicitly asked to avoid. The networking glue in
`MTWebSocketConnectionInterface.swift` is therefore verified by code review and (pending environment
availability — see "Known limitations") a real device/simulator run, not by automated tests.

## Known limitations

- **Not yet verified against a live Telegram DC.** See the accompanying implementation report for the
  current build/test verification status in this environment.
- **This fork's `submodules/rlottie/rlottie` and `submodules/TgVoipWebrtc/tgcalls` submodule remotes are
  unreachable** (`git@github.com:Fgeeha/rlottie.git` 404s; `tgcalls` was never initialized), which
  transitively blocks a full `//Telegram:Telegram` app build and even `//submodules/SettingsUI:SettingsUI`
  in isolation (Lottie-consuming UI components sit on the path to almost everything). This is a pre-existing
  gap in this fork's submodule configuration, unrelated to the WebSocket transport work — `ProxyListSettingsController.swift`
  could only be verified by manual review against this file's own existing patterns, not by compiling it.
- **`submodules/MtProtoKit/Sources/MTNetworkAvailability.m` fails to compile on newer SDKs** (Xcode 26.6
  here) because it calls several `SCNetworkReachability*` APIs deprecated in macOS 14.4, and the build
  treats warnings as errors. This is pre-existing in unmodified upstream MtProtoKit — nothing this feature
  touches — and was left as-is rather than patched, since it's out of scope for a WebSocket-transport
  change. It blocks a fully clean `MtProtoKit`/`TelegramCore` Bazel build on this toolchain; it does not
  indicate any problem with the code in this document.
- **Sec-WebSocket-Accept is not cryptographically checked** (see "TLS / security decisions" — deliberate,
  not a gap in the security model, but worth knowing if a stricter WS-conformance check is ever desired).
- **Cloudflare Worker / Cloudflare-proxy fallback is not implemented.** `WebSocketEndpointCandidate` is
  structured so a future candidate type could be added without another MtProtoKit-level change, but no
  such candidate exists yet.
- **UI strings are hardcoded English**, not localized (see "Settings").
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
