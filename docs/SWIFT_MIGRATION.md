# C / Objective-C → Swift: what is worth migrating, and what is not

Written in answer to "can the C parts of the client be rewritten in Swift?"
Short answer: some of it, none of it urgently, and the largest pieces should
never be.

**Execution plan (phases, necks, DoD):**
[`docs/plans/objc-to-swift-migration.md`](plans/objc-to-swift-migration.md).

## Inventory

Line counts across `submodules/`, `Telegram/`, `third-party/` (excluding
`bazel-*` symlinks), refreshed 2026-08-10:

| Language | Lines |
|---|---|
| Swift | ~305,000 |
| C | ~511,000 |
| Objective-C (`.m`) | ~215,000 |
| C++ (`.cpp`) | ~102,000 |
| Objective-C++ (`.mm`) | ~39,000 |
| Headers (`.h`) | ~192,000 |

Where the non-Swift lines actually live:

| Component | Lines | Nature |
|---|---|---|
| `third-party/` + `submodules/ffmpeg/` | majority of C | vendored libraries / codecs |
| `submodules/LegacyComponents/` | ~145,000 | app ObjC, ~313 `.m` + 23 `.mm` files — migration target |
| `submodules/MtProtoKit/` | ~29,000 | protocol + transport |
| `submodules/AsyncDisplayKit/` | ~18,000 | vendored Texture fork |
| `submodules/TgVoipWebrtc/` | thin wrapper | over tgcalls (C++) |
| `submodules/SSignalKit/` | ~3,000 | ObjC signal primitives (dies with LC) |

So of ~900k non-Swift lines, roughly **85% is vendored third-party code** that
this repository does not author and should not fork. The genuinely
fork-owned Objective-C is `LegacyComponents` plus `MtProtoKit` — about 172k
lines, and even that is mostly upstream Telegram code, not fork code.

## Never migrate

These are not style questions. Rewriting any of them makes the app worse.

**ffmpeg and the codec stack (598k lines).** Hand-tuned C with per-architecture
assembly and SIMD paths. A Swift reimplementation would be slower by a large
multiple on exactly the workload that already runs hottest — video decode — and
would lose upstream security fixes permanently. This is also the single most
likely origin of sustained device heat, which makes a rewrite the *worst*
available response to a thermal complaint, not the best.

**Cryptography (`MTEncryption.m` and friends).** Correctness here is not
verifiable by reading the resulting Swift. Constant-time properties, buffer
handling, and interoperability with the server's exact wire behaviour are all
load-bearing, and none of them are visible in a diff. Rewriting working crypto
for style reasons is how side channels get introduced.

**SQLite.** It is the most-tested C code in existence. Nothing to gain.

**tgcalls / WebRTC (C++).** A live, upstream-maintained real-time media stack
shared with other Telegram clients. Diverging from it means owning every
future WebRTC change alone.

**SIMD and assembly paths.** Swift's SIMD types are good, but replacing a
tuned kernel blindly — without a benchmark showing the replacement is at least
as fast on device — trades measured performance for readability. Only with a
benchmark, and then one kernel at a time.

**Anything hardware-accelerated** (VideoToolbox, Metal, AVFoundation bridging).
The ObjC there is already a thin shim over a C API; Swift would add bridging
cost and remove nothing.

## The blocker: file-by-file migration does not work here

An earlier revision of this document recommended migrating small
`LegacyComponents` leaf classes one at a time. That advice was written from
general Swift-migration experience and **not** checked against this
repository's build. Checked now, it is wrong on two counts.

**1. A `.swift` file cannot go into `LegacyComponents` at all.**
`submodules/LegacyComponents/BUILD` declares one `objc_library` whose sources
are `glob(["Sources/*.m", "Sources/*.mm", "Sources/*.c", "Sources/*.cpp",
"Sources/*.h"])`. Bazel's `objc_library` compiles no Swift, and the glob does
not match `*.swift` — so a Swift file dropped into `Sources/` is **silently
ignored**, not a build error. Migrating a file in place is not possible.

Adding Swift requires a sibling `swift_library` target, with the remaining
ObjC importing its generated `-Swift.h`. But a migrated class almost always
uses other `LegacyComponents` ObjC types, so that `swift_library` would have to
depend back on `LegacyComponents` — a dependency cycle, which Bazel rejects.
Only a class whose dependencies are a strict subset of `{Foundation, UIKit,
SSignalKit, AppBundle}` escapes the cycle.

**2. The population of migratable leaf files is one, and it is dead code.**
Of the 379 `.m` files, exactly **one** has no dependents inside the module:
`matrix.m` (306 lines). It is vendored Apple sample code for 4×4 matrix
arithmetic, and nothing anywhere references it — the two `#include "matrix.h"`
hits elsewhere in the tree resolve to `RMIntro`'s own separate copy. Every
other file has at least one in-module dependent, so migrating it would break
the ObjC that uses it.

So the correct first action on that file is `git rm`, not a translation.

The bug argument for migrating this code still stands — the audit found a
`CFRetain` with a conditionally-skipped `CFRelease` in
`PGCameraCaptureSession.m`, and a KVO observer removed on only one of two
teardown paths in `TGPhotoEditorController.m`, a crash rather than a leak, and
both are bug classes Swift makes structurally impossible. What does not stand
is the idea that you can get there one file at a time.

## What does work

### The module is an island with a narrow neck

`LegacyComponents` publishes 296 headers. Only **64** of those names are
referenced anywhere outside the module. The other 232 are internal detail.

That 64-name neck is the real migration unit. You cannot extract a file, but
you can replace a whole feature that enters through a few of those names and
then delete everything behind it in one commit — no cycle, because nothing
crosses the boundary any more.

The externally-used names cluster by feature, and the clusters are very uneven:

| Cluster | External entry points | Notes |
|---|---|---|
| Media picker / gallery | ~15 | largest and most entangled |
| Camera | 5 (`TGCameraController`, `PGCamera`, `TGAttachmentCameraView`, …) | a modern Swift `Camera` / `CameraScreen` already exists in parallel |
| Photo / video editor | ~6 | modern Swift `MediaEditor` exists in parallel |
| Passport | 5, **one call site each** | smallest, most self-contained neck in the module |
| POP animation | 3 | vendored Facebook POP — replace, don't translate |
| Utilities (`TGStringUtils`, `TGDateUtils`) | 92 call sites | high traffic, but heavily used *inside* the module too, so it cannot move until the rest does |

This also explains why the camera and media editor already have modern Swift
counterparts under `submodules/TelegramUI/Components/`: the codebase has been
migrating this way all along — building the replacement alongside, moving call
sites over, deleting the old subtree — rather than translating files.

### Recommended order

1. **Delete dead code.** Ongoing hygiene (see Phase 0 in the execution plan).
   `matrix.m` is already gone. Re-run reachability on the remaining ~313 `.m`
   files and the internal-only headers before each cluster.
2. **Passport.** Five entry points with one call site each — by a wide margin
   the cheapest complete cluster to replace, and a real end-to-end rehearsal of
   the pattern before touching anything load-bearing.
3. **Camera, then photo/video editor.** Both already have Swift counterparts;
   the work is finishing the call-site migration and deleting the ObjC subtree,
   not writing a new implementation.
4. **Media picker / gallery.** Largest neck, most entanglement. Last among UI
   clusters.
5. **Utilities / POP / SSignalKit.** Fall out once nothing else in the module
   remains.

Full phase checklist, DoD, and the first ticket are in
[`docs/plans/objc-to-swift-migration.md`](plans/objc-to-swift-migration.md).

### Cost per step

There is no per-module build in this repository — the only verification is the
full `Telegram/Telegram` target, which takes roughly 38 minutes on CI. Each
migration step therefore costs a CI run, and `-Werror` on the ObjC side plus
`-warnings-as-errors` on the Swift side means a step either lands clean or not
at all. Batch related deletions into one commit; do not push a cluster
migration in ten pieces.

### 2. `SSignalKit` (2,868 lines of ObjC)

A Swift equivalent already exists and is used everywhere: `SwiftSignalKit`. The
ObjC version survives only because `LegacyComponents` consumes it. It
disappears for free as (1) progresses — it is not a separate project.

### 3. `MtProtoKit`'s non-crypto layers

`MTProto.m` (2,850 lines) and the transport files are ordinary state machines
and socket handling. Migratable in principle, and they would benefit from
Swift's optionals. But this is the layer every single feature depends on, an
error here is a connectivity outage rather than a visual glitch, and it is
shared with upstream. Low priority despite being technically tractable.

### 4. `GCDAsyncSocket.m` (7,404 lines) — replace, don't rewrite

Vendored, and largely superseded by `Network.framework`. If this is ever
touched, the move is to adopt `NWConnection` rather than to translate 7,000
lines of socket code into Swift line by line.

## Not worth migrating, but not for performance reasons

`libphonenumber` (`NBMetadataCore.m`, 14,237 lines) is generated metadata, not
hand-written logic. Translating generated code produces generated code in a
different language. Regenerate or replace the library; never port it.

## How to run one cluster migration

1. Confirm the cluster's neck: grep the tree outside `LegacyComponents` for its
   public class names and list every call site. If the neck is wider than you
   expected, stop and pick a smaller cluster.
2. Build the Swift replacement as its own module under
   `submodules/TelegramUI/Components/`, alongside the ObjC one. Do not touch
   `LegacyComponents` yet — both implementations coexist and the app still uses
   the old one.
3. Move the call sites over, one commit, and build.
4. Delete the ObjC subtree once nothing references it. This is the commit that
   actually shrinks the codebase, and it is safe precisely because step 3
   already proved nothing needs it.
5. Exercise the affected screen on a device before starting the next cluster.

Explicitly **not** the plan: translating files in place (structurally
impossible, see above), converting a whole module in one change, or deleting a
vendored library to replace it with Swift. Each produces a diff nobody can
review and a regression nobody can bisect.

## Honest summary

The client can be moved further toward Swift, and the parts worth moving are
the fork's own aging Objective-C UI code, where two real bugs have already been
found that Swift would have prevented. The parts people usually mean when they
ask this question — the C — are the parts that should stay C.

But it cannot be done file by file. The build makes that structurally
impossible, and the one file that qualifies is dead code. The unit of migration
is a feature cluster crossing the module's 64-name boundary, replaced wholesale
and then deleted — which is how the camera and media editor already acquired
their Swift counterparts. Anyone planning this work should budget in clusters
and CI runs, not in files.

None of this is a performance project. See `PERFORMANCE_AUDIT.md` for that; in
particular, nothing here should be undertaken in the hope that it reduces
device heat, because no measurement supports that expectation.
