# C / Objective-C → Swift: what is worth migrating, and what is not

Written in answer to "can the C parts of the client be rewritten in Swift?"
Short answer: some of it, none of it urgently, and the largest pieces should
never be.

## Inventory

Line counts across `submodules/`, `Telegram/`, `third-party/` (excluding
`bazel-*` symlinks):

| Language | Lines |
|---|---|
| Swift | 304,288 |
| C | 551,101 |
| Objective-C (`.m`) | 219,662 |
| C++ (`.cpp`) | 101,906 |
| Objective-C++ (`.mm`) | 39,530 |
| Headers (`.h`) | 280,335 |

Where the non-Swift lines actually live:

| Component | Lines | Nature |
|---|---|---|
| `third-party/` | 690,599 | vendored libraries |
| `submodules/ffmpeg/` | 598,692 | vendored codec stack |
| `submodules/LegacyComponents/` | 142,897 | app code, 379 `.m` files |
| `submodules/MtProtoKit/` | 28,914 | protocol + transport, 92 `.m` files |
| `submodules/AsyncDisplayKit/` | 18,451 | vendored Texture fork |
| `submodules/TgVoipWebrtc/` | 4,118 | thin wrapper over tgcalls (C++) |
| `submodules/SSignalKit/` | 2,868 | ObjC signal primitives |

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

## Worth migrating, in this order

The case for each of these is maintainability, not speed. None of them will
make the app faster; Swift and ObjC compile to comparable machine code for this
kind of work. The wins are memory safety, nullability, and being able to reason
about ownership.

### 1. Small self-contained `LegacyComponents` leaf classes

`LegacyComponents` is 379 files, so "migrate LegacyComponents" is not a task —
but individual leaf views and controllers with few dependents are. Good
candidates are files with no C interop, no manual `CFRetain`/`CFRelease`
balancing, and a small header surface.

This is also where the real bugs have been: the audit found a
`CFRetain` with a conditionally-skipped `CFRelease` in
`PGCameraCaptureSession.m`, and a KVO observer removed only on one of two
teardown paths in `TGPhotoEditorController.m` — a crash, not a leak. Both are
bug classes Swift makes structurally impossible. That is the actual argument
for migrating this code, and it is a good one.

**Do not** start with the largest files. `TGCameraController.m` (3,261 lines)
and `TGPhotoEditorController.m` (3,077) are the ones most in need, and the ones
where a rewrite is most likely to introduce a regression nobody catches.

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

## How to sequence this, if it is done at all

1. Pick one leaf file with no C interop and fewer than ~400 lines.
2. Migrate it whole, in one commit, with its callers updated in the same commit.
3. Build the full app target — this repository has no per-module build, so a
   partially-migrated module is not verifiable in isolation.
4. Exercise the affected screen on a device before moving on.

Explicitly **not** the plan: converting many files at once, converting a whole
module in one change, or deleting a vendored library to replace it with Swift.
Each of those produces a diff nobody can review and a regression nobody can
bisect.

## Honest summary

The client can be moved further toward Swift, and the parts worth moving are
the fork's own aging Objective-C UI code, where two real bugs have already been
found that Swift would have prevented. The parts people usually mean when they
ask this question — the C — are the parts that should stay C.

None of this is a performance project. See `PERFORMANCE_AUDIT.md` for that; in
particular, nothing here should be undertaken in the hope that it reduces
device heat, because no measurement supports that expectation.
