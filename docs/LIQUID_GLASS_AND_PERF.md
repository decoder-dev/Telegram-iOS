# Liquid Glass (iOS 26) + “не жрать” — fork notes

Advisory notes for what to adopt from system Liquid Glass, and what still
moves the needle on CPU / battery / heat. Not a measurement report — see
[`PERFORMANCE_AUDIT.md`](PERFORMANCE_AUDIT.md) for structural fixes already
landed and for the “nothing claimed without a trace” rule.

## Liquid Glass — already in the tree

Upstream Telegram-iOS already ships a large glass surface area. The fork should
**reuse** it, not invent a parallel look:

| Surface | Status |
|---|---|
| `GlassBackgroundComponent` / `GlassBackgroundView` (+ `UIGlassEffect` path) | present |
| Chat navigation bar / composer chrome | `.glass` |
| Tab bar, attachment sheets, media picker, polls, location, contacts | `.glass` |
| Fork Extras switches / actions | `systemStyle: .glass` on ItemList rows |

So “add Liquid Glass” does **not** mean wrapping every screen in a new blur
layer. It means finishing the few fork-owned surfaces that still look like
legacy solid chrome next to an otherwise glass app.

## What is worth adding (priority order)

Fit Telegram’s language: soft material, clear hierarchy, no purple-AI glow,
no glass-per-row.

1. **Fork-owned ItemList controllers’ chrome** — Saved Messages History,
   Regex Filters, MessageSaving import/export result sheets. Rows already
   pass `systemStyle: .glass`; make sure the hosting `ItemListController` /
   nav bar uses the same glass presentation as Settings, so the screen does
   not flash between solid and glass when pushed from Extras.
2. **Fork diagnostic chips** — Show DC / registration date / profile-id style
   rows and any floating diagnostic badges: small glass capsules (same
   `GlassBackgroundView` path as media-picker selection chips), not opaque
   colored pills.
3. **Ghost / confirm overlays** — “Confirm before call”, story-open alert,
   Instant Passcode lock affordance: glass action sheets / toast capsules
   consistent with upstream confirmations, instead of custom solid dialogs
   if any remain.
4. **Unread / jump controls on fork compact chat list** — if compact mode
   introduces custom floating controls, give them glass; do not invent a
   second floating style.
5. **Touch feedback** — prefer the existing `TouchEffect` / glass highlight
   path over extra particle / glow layers.

## What not to add

- Glass **message bubbles** or glass **per chat-list row** — expensive blur
  at scroll rate; fights heat goals.
- A fork-wide “Liquid Glass theme” toggle that reimplements system materials
  with custom CIFilters — upstream already owns the real path.
- Decorative glass on static settings footers / long prose sections.
- Purple / indigo gradient “glass” accents that read as generic AI UI.

## Optimization — what already stopped waste

Structural fork work (see `PERFORMANCE_AUDIT.md`): MessageSaving no longer
copies files under Postbox locks, no longer re-encodes the whole JSON store
per save, no longer O(n)-scans on context-menu open, no longer mkdir’s on
every attachment access, and no longer JSON-encodes on the main thread when
backgrounding. Fake-TLS SNI byte layout restored. Grid camera keeps a photo
output so capture does not crash.

Telemetry exists (`ForkPerformanceTelemetry`) but **only observes** — it does
not yet shed work when hot.

## Optimization — next levers that actually matter

Ordered by expected impact vs invasiveness. Prefer the top of the list.

### 1. Shed optional fork work when thermally stressed / Low Power Mode

`ForkPerformanceTelemetry.isThermallyStressed` is already synchronous. Wire it
(and `ProcessInfo.processInfo.isLowPowerModeEnabled`) into:

- **proactive Save Media** — skip opportunistic attachment copies when
  `.serious`/`.critical` or LPM; keep on-delete / on-edit saves.
- **MessageSaving export** — refuse or warn + run only on a utility queue
  with a lower QoS when stressed.
- **Heavy fork retries** — lengthen backoff when stressed instead of hammering.

This is the highest-value *fork-owned* thermal lever: it removes optional I/O
the user did not explicitly request right now.

### 2. Calls are the real heater — do not expect MTProxy to help

Messages travel MTProto TCP; calls are a separate WebRTC ICE/RTP path.
**MTProto proxy cannot tunnel VoIP RTP.** Practical client options already in
tree:

- Settings → Proxy → **Use for Calls** (SOCKS5 only; `.mtp` is ignored in
  `OngoingCallContext`).
- Privacy → Calls → **Peer-to-Peer: Never** (forces relay; often cooler /
  more predictable on bad networks).
- Experimental `enableVoipTcp` → `PresentationCallManager` `allowTCP` —
  expose as an Extras toggle (“Force TCP relay for calls”) for networks that
  murder UDP. Not a free win: TCP relay can add latency; it is an escape
  hatch, not a default.

Capture is hard-locked at high resolution / 30 fps in the WebRTC capturer.
When `isThermallyStressed`, prefer: warn on starting video, or drop capturer
target resolution/fps — do **not** rewrite tgcalls/WebRTC for a cosmetic
Swift migration.

### 3. Signposts on suspected paths (measurement, not a fix)

Add `OSSignposter` intervals around MessageSaving persist, chat history
layout apply, and call video capturer start/stop. Near-free without
Instruments attached; turns the next heat report into a readable trace.

### 4. Indexed MessageSaving store (later)

Even coalesced, a full JSON rewrite of up to 5000 records every 5s is still
O(n). Move to SQLite / Postbox only after MetricKit / signposts show persist
still matters. Do not do this “because JSON is slow” without evidence.

### 5. Leave alone on purpose

- ffmpeg / codecs / SQLite / WebRTC / Metal decode shims — stay C/C++.
- File-by-file ObjC→Swift inside `LegacyComponents` — does not cool the
  device; see `SWIFT_MIGRATION.md`.
- Global-queue → serial-queue sweep across 28 sites — deferred until a
  trace points at one.

## User-facing “make it cooler today” checklist

No code required:

1. Turn off **Proactive Save Media** if Save Deleted/Edits is enough.
2. Use **SOCKS5 + Use for Calls** when a proxy is needed for VoIP; do not
   expect MTProxy to carry calls.
3. Set Calls **P2P → Never** on hostile networks.
4. Prefer audio over video when the phone is already warm / on Low Power Mode.
5. Keep Auto-Play of heavy animations modest (system LPM already throttles
   some multi-animation renderers in-tree).

## Implementation sequencing (when coding, not just advising)

1. Ship AyuForward first-attempt fix (separate PR).
2. Thermal/LPM gate on proactive Save Media + export QoS.
3. Extras toggle for `enableVoipTcp` + short help text pointing at SOCKS5 /
   P2P Never.
4. Glass chrome pass on remaining fork ItemList / chip surfaces.
5. Signposts; only then consider capturer downscale-on-heat or indexed store.
