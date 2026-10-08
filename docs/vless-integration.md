# VLESS proxy integration (iOS port)

Reference implementation studied: [telegramvless](https://github.com/gustafsonhelga1980-bit/telegramvless) (Telegram Desktop, branch `vless-ui`) + [tgcalls fork](https://github.com/gustafsonhelga1980-bit/tgcalls) (branch `vless-media-socks`) + [lib_webview fork](https://github.com/gustafsonhelga1980-bit/lib_webview) (branch `vless-webview-proxy`).

## Desktop architecture (studied)

1. **Runtime**: Xray runs as a *sidecar process* (`xray/xray` next to the executable) with two authenticated loopback inbounds — SOCKS5 (`udp: true`) and HTTP. Credentials and ports are generated per launch.
2. **Proxy state**: enabling VLESS installs the local SOCKS5 as the app's selected proxy (`VlessProxySink`), proxy rotation disabled; disabling stops the sidecar and restores the previous selection. On startup the stored `vless://` URL is re-applied if enabled.
3. **Profile**: `vless://` links are parsed with a strict allowlist (`Core::ParseVlessProfile`, 1837 lines: tcp/ws/grpc/httpupgrade/xhttp transports, none/tls/reality security, vision flow, fingerprints, ALPN, ECH, cert pinning, mldsa65 post-quantum verify). Unsupported parameters are *rejected*, not ignored. The iOS port now covers the modern XHTTP surface too: `type=xhttp` (with `mode` = auto/packet-up/stream-up/stream-one and the double-encoded `extra` JSON with xmux/xPadding settings, merged into `xhttpSettings` by the core), the post-quantum `mlkem768x25519plus.<native|xorpub|random>.<1rtt|0rtt>.<key>` encryption expression (passed through verbatim to the outbound user settings), and the `allowInsecure` flag; the URI cap is 8192 to fit ~1.6 KB post-quantum keys.
4. **Calls**: `IsManagedVlessProxy` = SOCKS5 + `127.0.0.1` + valid ASCII credentials. tgcalls routes all call media through the local bridge (authenticated SOCKS5 UDP ASSOCIATE + reflector/relay transports, P2P/STUN/TCP suppressed). If VLESS is enabled but the route is unavailable, group calls are **prevented** and ongoing calls hang up (`stopMediaAndHangup`) — a kill switch against traffic leaking outside the proxy. Call teardown waits for media threads (`PostCallTeardownBarrier`).
5. **WebView**: embedded webviews route through the local HTTP proxy (lib_webview fork). Not portable to iOS WKWebView 1:1 (no per-process proxy env) — deferred.

## iOS port status

### Shipped

- **tgcalls**: the whole `vless-media-socks` branch is vendored as `submodules/TgVoipWebrtc/patches/vless-media-socks.patch` (applied by CI after submodule checkout; the pin stays on upstream `e3069322`). Contains managed SOCKS5 call transports, anti-SSRF relay validation, glare fix, replay hardening.
- **App wiring (1-1 calls)**: `VoipProxyServerWebrtc.managed` + `OngoingCallContext` marks authenticated loopback SOCKS5 proxies as managed. **Already usable today**: any on-device proxy app exposing an authenticated local SOCKS5 (user/pass set, host `127.0.0.1`) entered in Settings → Data and Storage → Proxy, with "Use for calls", routes call media exclusively through it.
- **TelegramVLESS package** (`submodules/TelegramVLESS`, pure Swift, no deps): strict `vless://` parser (common subset: tcp/ws/grpc/httpupgrade, none/tls/reality, xtls-rprx-vision, fingerprints, ALPN, sni/pbk/sid/spx), Xray config assembly (desktop-shaped: authenticated socks+http loopback inbounds, single vless outbound), `VlessManager` lifecycle, `LibXrayRuntime` adapter behind `#if canImport(LibXray)`.
- **CI**: `Fetch libxray framework` step downloads the pinned release (`XTLS/libxray` v26.9.9, apple-cgo build, sha256 `84a11f09…`, from the GitHub-reported asset digest) into `third-party/libxray/` (gitignored).

### Remaining wiring (next steps)

1. **Bazel**: add an `apple_static_xcframework_import` (or `objc_library`) target for `third-party/libxray/LibXray.xcframework` exposing module `LibXray`; add it as a dep of `//submodules/TelegramVLESS` so `canImport(LibXray)` activates the adapter.
2. **Settings**: store `vlessURL: String?` + enabled flag (e.g. in the shared `ProxySettings` postbox entry, or a separate account preference). UI: a "VLESS" row in `ProxyListSettingsController` with a paste field; enabling installs the sink SOCKS5 as the active proxy + `useForCalls = true`.
3. **Startup**: a process-wide `VlessManager` singleton owned by the app context; on launch, if enabled, `start(url:)` and install the returned sink; observe state failures (`runtimeUnavailable`, `startFailed`) → surface in the proxy UI (like "unavailable" proxy state) and drop the sink.
4. **Kill switch**: while VLESS is enabled, block group call join (and any new 1-1 call) if the route is down; mirror `IsManagedVlessProxy` checks before handing a proxy into tgcalls.
5. **Group calls**: pass `GroupInstanceDescriptor.proxy` through the `GroupCallThreadLocalContext` wrapper (tgcalls support already vendored in the patch).
6. **Teardown parity**: use `PostCallTeardownBarrier` in the wrapper before recycling the call context.
