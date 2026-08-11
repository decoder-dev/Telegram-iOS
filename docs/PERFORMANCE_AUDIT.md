# Performance & thermal audit

Scope: the fork-specific code added on top of upstream Telegram-iOS, plus a
survey of the app-wide patterns that plausibly contribute to sustained CPU
load. Written in response to a report of the device running hot.

## Measurement status — read this first

**Nothing in this document is backed by an Instruments trace, a MetricKit
payload, or a reproducible on-device benchmark.** No macOS host, no Xcode, no
simulator, and no physical device were available while this work was done —
only a Linux checkout and the CI release build.

Every entry below is therefore labelled:

- **structural** — the change removes work that provably happened (file I/O
  under a database lock, an O(n) scan per call). The reasoning is checkable by
  reading the code; the size of the win is not known.
- **not measured** — a hypothesis about a cost. Not acted on beyond flagging.

No claim of "the device runs cooler" is made anywhere, because none was
measured. The instrumentation section at the end is what would turn these into
numbers.

## What was ruled out first

Before changing anything, the obvious explanations were checked and eliminated:

| Hypothesis | Verdict | Evidence |
|---|---|---|
| Users are running a debug build | No | CI builds `release_arm64` with `-c opt` |
| Debug-only flags left on in release | No | `common_debug_args` in the Bazel config sets thread count only |
| Disk logging left enabled | No | Gated behind a user setting; `is_internal_build: false` |
| A fork feature polls on a timer | No | The fork adds no repeating timer; the saving retry chain is bounded (7 attempts, exponential backoff to 16s, then stops) |

So the heat is not a build-configuration mistake. The remaining candidates are
real work being done at the wrong time or too often.

## Findings and changes

### 1. Full JSON re-encode of the record store on every saved message — **structural, fixed**

`MessageSavingStore` persisted by encoding its entire in-memory array (capped
at 5000 records) to JSON and writing it atomically — **once per saved record**,
**while holding the lock** that main-thread readers use.

A single deletion sweep in a busy channel produces hundreds of records back to
back, so this was hundreds of full re-serializations of the whole store in a
burst, each one blocking every reader behind it.

Changed to:
- coalesce writes on a 5s timer, with an immediate flush on `didEnterBackground`
  so nothing is lost when the app is suspended;
- snapshot under the lock, encode **outside** it, so the expensive part no
  longer blocks `hasDeleted` / `hasEdits` on the main thread;
- order concurrent persists with a generation counter, so the coalescing could
  not introduce a lost-update bug of its own.

Work removed: O(records × saves) encodes became O(records) per 5s window.

### 2. Linear scan of the whole store per context-menu open — **structural, fixed**

`hasDeleted` and `hasEdits` are called while building a message context menu,
on the main thread. Both scanned up to 5000 records linearly, per call, per
menu.

Replaced with reference-counted dictionaries maintained alongside the array
(`DeletedIndexKey` / `EditIndexKey`), making both an O(1) lookup. The
topic-scoped `hasDeleted` variant still filters, but that path is only reached
in forum chats.

Not a thermal fix on its own — it is main-thread latency — but it is on the
interaction path, which is where a stall is felt.

### 3. File copies executed inside Postbox transactions — **structural, fixed**

The largest single item. Copying a saved attachment into the durable folder ran
synchronously on the caller's thread, and three of the four callers run inside
a Postbox transaction:

- `_internal_deleteMessages`
- `snapshotMessages` / `snapshotMessage`, from `replayFinalState`
- `preserveMediaIfNeeded`, from `markMessageContentAsConsumedInteractively`

A transaction holds the database lock for its whole body. Copying a 40 MB video
there blocked history loads, draft writes, and unread-count updates for the
duration of the I/O — and a bulk delete multiplied that per message. Contended
locks mean spinning and repeated wakeups, which is a plausible heat
contributor, not just a latency one.

`scheduleCopy` now resolves source and destination on the caller's thread (path
arithmetic plus one directory listing — no byte movement) and dispatches the
copy to a utility queue. The destination is deterministic, so the record is
still stored with its final path immediately.

`preserveMediaIfNeeded` lost its synchronous first attempt entirely; the retry
chain starts at delay 0 so the first attempt still happens immediately, just
not on the caller's thread.

### 4. Repeating timers not invalidated on teardown — **structural, fixed earlier**

An audit of `Timer(repeats: true)` and `CADisplayLink` teardown found several
that were invalidated only reactively (when a state change was observed) and
never on `deinit`. A `CADisplayLink` that outlives its owner keeps firing at
display rate forever — a permanent, ongoing CPU and battery cost, not a memory
leak. Fixed instances are listed in the commit history; the notable one is
`UniversalTextureSource`, whose `invalidate()` tore down its input contexts but
not its own display link.

Current inventory in the tree: 36 repeating-timer constructions, 11
`CADisplayLink` constructions. The ones reachable from the fork's own screens
have been checked; the rest are upstream and were audited opportunistically,
not exhaustively.

### 5. Candidates identified but **not measured** and not acted on

These are hypotheses. Acting on any of them without a trace would be guessing,
and the spec is explicit that a thermal claim needs evidence.

- **JSON as the store format.** Even coalesced, every write re-encodes the whole
  store. An indexed store (SQLite, or Postbox itself) would make a write O(1) in
  the number of records. Worth doing — but the current cost is now once per 5s
  at worst, so this is an optimization, not a fix, and it should be sequenced
  after a measurement confirms it still matters.
- **`DispatchQueue.global()` for texture work.** 28 call sites across submodules
  dispatch to the concurrent global pool. The concurrent pool can over-subscribe
  cores under load; a dedicated serial queue is usually both cooler and more
  predictable. One instance (`CompressedImageRenderer`) was already converted for
  a correctness reason, and the change is behaviour-preserving elsewhere, but
  there is no evidence any of the rest is hot.
- **Video decode, camera pipeline, and rendering.** By far the most likely
  origin of sustained heat in a messaging client, and entirely upstream code.
  Untouched deliberately — see `SWIFT_MIGRATION.md` for why guessing here is
  worse than doing nothing.

## Instrumentation: what to add to turn this into numbers

The app currently has **two** `OSSignposter` instances in the whole tree
(`DustEffectLayer`, `StorageUsageScreen`) and **no** MetricKit subscriber and
**no** `thermalState` observer. That is the actual blocker: there is no way to
answer "what is hot" from inside the app, so every diagnosis has to be made
from the outside with Instruments attached.

**Added** (`submodules/TelegramUI/Sources/ForkPerformanceTelemetry.swift`,
installed from `AppDelegate` right after the shared logger exists):

1. **`ProcessInfo.thermalState` observer.** Logs the state at launch and every
   transition. Cheapest possible signal, and it answers "when does it get hot"
   with no tooling at all — the user reads it out of the app log.
   `ForkPerformanceTelemetry.isThermallyStressed` exposes the same state
   synchronously so a future throttling decision does not have to hop a queue
   on a layout path.
2. **MetricKit subscriber** (`MXMetricManager`). Logs a greppable one-line
   summary of the scalar metrics — cumulative CPU time, logical disk writes,
   background-exit counts including watchdog and CPU-limit kills — plus the
   full payload JSON, which carries the launch-time and hang-time histograms.
   At most one payload per day, so the volume is negligible. This is the only
   signal here that comes back from real users rather than from a developer's
   desk.

Both are observation only. Nothing throttles or changes behaviour, because
choosing what work to shed requires first knowing what it costs.

**Still to do:**

3. **Signposts on the suspected paths** — media decode, chat history layout,
   the saving store's persist. Near-free when no tool is attached, and they
   make an Instruments trace readable instead of a wall of symbol names.
   Requires a device and Instruments to be worth anything, so it is sequenced
   behind 1–2, which do not.
4. **Thermal-aware throttling**, only after 1–3 say where. Reducing work when
   `thermalState >= .serious` (lower decode target, pause non-visible
   animations) is a real lever; the state is already available for it.

## Network audit addendum (2026-08-11)

Not part of the original thermal/CPU pass above, but found while auditing the same fork
commits for regressions: `submodules/MtProtoKit/Sources/MTTcpConnection.m`'s Fake-TLS
ClientHello generator (`executeGenerationCode`) had its `S "\x00\x00\x00\x00"` literal (right
after `G 2`, the SNI extension's lead-in) shrunk to `S "\x00\x00"` by the proxy-fixes commit
that claimed to fix "empty SNI" (issue #1912). This is **checkable without Xcode or a
device**: the byte layout is deterministic given the DSL interpreter's own rules (`[`/`]` push
a 2-byte length placeholder and patch it on pop; `G N` writes `grease[N]` twice, and
`grease[N]`'s low nibble is forced to `0xA`, so it can never be `0x00`). Re-implementing the
interpreter faithfully in a standalone script and feeding its output through a minimal TLS
ClientHello parser shows:

- With 4 zero bytes (upstream shape): `ext[0]` = an empty `0x?A?A`-typed GREASE extension,
  `ext[1]` = `type=0x0000 (server_name)`, correctly containing the domain. Valid SNI.
- With 2 zero bytes (this fork's "fix"): the parser consumes both zero bytes as
  `ext_data_length=0` for the GREASE extension, so `extension_type=0x0000` for server_name is
  never written at all — the domain bytes that follow are misread as a mislabeled
  `extension_type=0x0010` (ALPN) blob. **No `server_name` extension exists in the ClientHello.**

So the 2-byte version doesn't fix "empty SNI" — it removes SNI outright, which is a strictly
worse regression for exactly the scenario ("ee"-secret / domain-fronted MTProxy) the original
fix was supposed to help. Reverted to 4 bytes; see the comment at the call site for the full
byte-accounting.

## Follow-up audit (2026-08-11): three more findings, fixed

1. **Crash risk: grid camera preview reused for capture with no photo output attached.**
   `submodules/MediaPickerUI/Sources/MediaPickerScreen.swift`'s in-grid camera tile was built
   with `photo: false` to shrink the preview-only session, but `cameraTapped()` hands that exact
   `Camera` instance through `CameraHolder` into `CameraScreenImpl`, which reuses it as-is for
   the real capture rather than reconfiguring it. With no `AVCapturePhotoOutput` attached, the
   shutter's `takePhoto()` calls `capturePhoto(with:delegate:)` on an output that was never added
   to the session — an `NSInvalidArgumentException`, not a soft failure. Restored `photo: true`;
   the 720p/no-audio preset from the same migration is unaffected and still cheaper than the
   1080p/full-`.photo`-preset session it replaced.
2. **Per-access `createDirectory` under the Postbox transaction lock.**
   `submodules/TelegramCore/Sources/MessageSaving/MessageSavingAttachments.swift`'s
   `directoryURL` called `FileManager.createDirectory` (a mkdir+stat syscall) on every single
   read, and callers include `MessageSavingBridge.preserveMediaIfNeeded`, which runs on a
   Postbox transaction thread — so a bulk delete of hundreds of messages meant hundreds of
   redundant mkdir calls serialized behind the database lock. Moved the directory creation into
   a `static let` initializer, which Swift runs at most once per process; every later access is
   now a plain property read.
3. **Main-thread JSON encode + atomic write on backgrounding.**
   `submodules/TelegramUIPreferences/Sources/MessageSavingStore.swift`'s `installBridge()`
   registered its `UIApplication.didEnterBackgroundNotification` observer with `queue: nil`,
   which runs the handler synchronously on the main thread, and the handler called `flush()` —
   a full `JSONEncoder().encode` of the entire record list plus an atomic file write — directly
   on it. That's exactly the swipe-to-home hitch this document is auditing for. Left `flush()`
   itself synchronous (call sites like `exportMessageSavingDatabase` rely on the write having
   landed before they read the file back), but the backgrounding observer now hops onto the
   store's own serial queue before calling it, wrapped in a `beginBackgroundTask` so the write
   still gets to finish even if iOS suspends the app before the async hop would otherwise run.

## Priority order

| # | Item | Status |
|---|---|---|
| 1 | File I/O inside Postbox transactions | fixed (structural) |
| 2 | Per-record full-store re-encode | fixed (structural) |
| 3 | O(n) scans on the main thread | fixed (structural) |
| 4 | Persist lost-update race | fixed (correctness) |
| 5 | Un-invalidated timers / display links | fixed where found |
| 6 | `thermalState` observer | added |
| 7 | MetricKit subscriber | added |
| 8 | Fake-TLS SNI byte-count regression | fixed (see network addendum) |
| 9 | Grid camera capture crash (`photo: false` reuse) | fixed |
| 10 | Per-access `createDirectory` under transaction lock | fixed |
| 11 | Main-thread flush on backgrounding | fixed |
| 12 | Signposts on suspected paths | not started |
| 13 | Thermal-aware throttling | blocked on 6, 12 |
| 14 | Indexed store instead of JSON | deferred pending measurement |
| 15 | Global-queue → serial-queue audit | deferred pending measurement |
| 16 | Media pipeline | not touched by design |
