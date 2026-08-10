# Plan: Objective-C → Swift (cluster migration)

Status: living plan. Strategy detail and “never migrate” rationale live in
[`docs/SWIFT_MIGRATION.md`](../SWIFT_MIGRATION.md). This file is the **execution
plan**: phases, necks, DoD, and sequencing.

## North star

Shrink fork-owned Objective-C in `LegacyComponents` (and the ObjC that only
exists to feed it) by **replacing feature clusters at the module neck**, moving
Swift call sites over, then deleting the ObjC subtree.

**Not** a line-by-line translation. **Not** a performance/thermal project.
**Not** rewriting vendored C (ffmpeg, crypto, SQLite, WebRTC).

## Current inventory (2026-08-10)

| Language | Approx. LOC (`submodules`+`Telegram`+`third-party`) |
|---|---|
| Swift | ~305k |
| C | ~511k |
| ObjC `.m` | ~215k |
| ObjC++ `.mm` | ~39k |
| C++ | ~102k |

Fork-relevant ObjC surface:

| Component | Notes |
|---|---|
| `LegacyComponents` | ~145k LOC, **359** `.m` files — primary target |
| `MtProtoKit` | protocol/transport — low priority, shared with upstream |
| `SSignalKit` | dies for free once LegacyComponents no longer needs it |
| `AsyncDisplayKit` / `ffmpeg` / `TgVoipWebrtc` | vendored — do not migrate |

External Swift `import LegacyComponents`: **~148** files. Heavy consumers:
`TelegramUI`, `SettingsUI`, `TelegramCallsUI`, `MediaPickerUI`,
`LegacyMediaPickerUI`, `DrawingUI`, `ChatTitleActivityNode`.

Already done (do not redo):

- Dead-code sweeps (`matrix`, unreferenced LC classes, dead `FLAnimatedImage`)
- `TGEmbedPIPButton` → Swift
- Parallel Swift **Camera** / **MediaEditor** modules exist; Legacy paths still
  wired from attachment menu / stories / some pickers
- Strategy doc corrected against Bazel reality (`objc_library` cannot host Swift)

## Rules that apply to every phase

1. **Unit of work = cluster**, not file. Confirm the neck (external call sites)
   before writing code. If the neck is wider than expected, stop and shrink scope.
2. **No `.swift` inside `LegacyComponents`.** New code is a sibling
   `swift_library` under `submodules/TelegramUI/Components/…` (or a dedicated
   module). Bazel's `LegacyComponents` `objc_library` silently ignores Swift
   and cycles if a Swift target depends back on LC types still used by ObjC.
3. **Coexist → flip call sites → delete.** Both implementations live until
   step 3 is green on a full `Telegram/Telegram` CI build (~35–40 min).
4. **One CI-clean commit that deletes** the ObjC subtree is the only commit that
   counts as “migrated.” Partial in-place ports are forbidden.
5. **Author as `decoder-dev`.** No Cursor/Claude attribution.
6. **Device smoke-test** the affected screen before starting the next cluster.
7. **Do not** touch ffmpeg / crypto / SQLite / tgcalls / SIMD “for Swift.”

## Phase 0 — Hygiene (ongoing, cheap)

**Goal:** Delete unreachable ObjC with zero product change.

| Item | Action | Done when |
|---|---|---|
| Unreferenced LC classes | Grep PublicHeaders + Sources for zero external *and* zero internal refs; `git rm` | Full app builds; LOC dropped |
| Orphan headers in umbrella | Prune `LegacyComponents.h` exports for deleted symbols | Compile clean under `-Werror` |
| Doc drift | Keep this plan + `SWIFT_MIGRATION.md` inventory in sync after each delete wave | Docs match `find`/`wc` |

**2026-08-10 wave:** deleted `PGPhotoCustomFilterPass`, `TGBotInfo`,
`TGModernMediaListItemContentView`, `TGStickerAssociation` (+ umbrella
exports). `UIScrollView+TGHacks` was deleted in the same wave and restored:
`TGMediaPickerController` calls its `stopScrollingAnimation`, which a
name-based scan cannot see because the call site names neither the file nor a
class. Categories must be checked selector by selector.

**2026-08-10 second wave** — root-based reachability rather than per-symbol
grep, which is what finally exposed the ActionStage island (a cycle no
per-file scan can break):

- `ActionStage` / `ASActor` / `SGraphNode` / `SGraphObjectNode` — the old
  actor/graph scheduler. Nothing calls `ActionStageInstance()`; the four types
  reference only each other. `ASWatcher` and `ASHandle` survive: they are used
  as a plain delegate pair by `TGMenuView`, `TGMediaAssetsController` and
  others, independently of the scheduler.
- `ocr` / `genann` / `fast-edge` — the neural-net MRZ recogniser behind the
  now-Swift `TGPassportOCR`. Its weights file (`ocr_nn.bin`) is not in the
  resource bundle at all, so the path could not have run even before Phase 1.
- `TGBotComandInfo` — reachable only through `TGBotInfo`, deleted above.
- `TGImageLuminanceMap` — survived only as a stale `@class` in `UIImage+TG.h`.
- `TGModernMediaListItem` / `TGModernMediaListSelectableItem` — protocols
  left over from `TGModernMediaListItemContentView`; `TGMediaPickerGalleryModel`
  imported the headers without naming the protocols.

`LegacyComponents` is now 345 `.m` + 25 `.mm` files and 265 public headers.

**Exit:** Continuous; run a pass before each numbered phase.

## Phase 2 — Camera (finish the parallel migration) — IN PROGRESS

**2026-08-10:** Media picker default asset mode now uses the Swift
`CameraSimplePreviewView` path instead of `TGAttachmentCameraView`; the dead
legacy preview branch in `MediaPickerUI` was removed. Chat's default media
picker preview tile now opens `context.sharedContext.makeCameraScreen` and maps
basic modern photo/video/asset results back into the existing
`enqueueMediaMessages` legacy-signal pipeline. Direct chat camera opens,
edit-media attachment menu camera, story reply camera, and Passport attach
camera still use `presentedLegacyCamera` / `TGCameraController` until their
schedule/timer/caption/QR/document-intent gaps are closed.

## Phase 1 — Passport (pilot cluster) — DONE 2026-08-10

**Why first:** Smallest real neck. External Swift uses of the Passport ObjC
cluster are essentially the SecureId attachment/scan entry points in
`PassportUI` (attach menu, scan controller, OCR, MRZ parsing, and iCloud import).

| Step | Work |
|---|---|
| 1.1 | Inventory call sites in `PassportUI` + any other importers |
| 1.2 | Swift replacement module (scan UI + attach menu + OCR bridge). Prefer Vision/`VNRecognizeTextRequest` / DataScanner where quality matches; keep MRZ parsing logic in Swift |
| 1.3 | Flip the SecureId attachment/scan entry points to the new API; leave old LC symbols unused |
| 1.4 | Delete the Passport ObjC cluster under `LegacyComponents` once symbol search is clean |
| 1.5 | Device: Passport attach / scan / MRZ on a real account flow |

**DoD:** No deleted Passport ObjC symbols outside the deleted tree; PassportUI has no `Legacy*`
files; CI green; SSignalKit usage in Passport path gone.

**2026-08-10 status:** Phase 1 Passport ObjC symbols were migrated out of
`PassportUI`: Swift now owns the attach menu shim, iCloud image import, MRZ
parser, Vision OCR/barcode bridge, and scan controller/camera preview. The
LegacyComponents Passport sources and public headers were deleted. Full iOS
CI/build and device smoke testing were unavailable on the Linux Cloud Agent VM.
`PassportUI` still imports `LegacyComponents`/`SSignalKit` for the shared
non-Passport media picker/camera asset pipeline used by the Swift attach menu;
removing those broader dependencies belongs to a later media-picker/camera
phase, not the Passport symbol deletion.

**Risk:** OCR quality regression on low-light docs — gate delete behind
side-by-side comparison on device photos.

## Phase 2 — Camera (finish the parallel migration)

**Neck today:** `LegacyCamera`, `LegacyAttachmentMenu`,
`ChatControllerOpenAttachmentMenu`, stories send path still reference
`TGCameraController` / `PGCamera` / `TGAttachmentCameraView`.

**2026-08-10 partial flip inventory:**

| Surface | Status |
|---|---|
| `MediaPickerUI/Sources/MediaPickerScreen.swift` | DONE for the grid preview: `TGAttachmentCameraView` dead branch deleted; Swift `CameraSimplePreviewView` is the only preview path. |
| `ChatControllerOpenAttachmentMenu.openCamera` from the default media picker preview tile | PARTIAL: `CameraHolder` now routes through `makeCameraScreen(.sticker)` and converts basic `CameraScreenImpl.Result` photo/video/asset outputs into legacy enqueue signals. Direct `openCamera()` and edit-media attachment-menu camera remain on `presentedLegacyCamera` to preserve schedule/timer/caption/QR behavior. |
| `StoryItemSetContainerViewSendMessage` | LEGACY: still calls `presentedLegacyCamera`; non-legacy preview taps fall back to the legacy camera. Importing `CameraScreenImpl.Result` here would create a `CameraScreen` <-> stories component cycle, so this needs an API-level bridge before a safe flip. |
| `PassportUI/SecureIdAttachmentMenu` | LEGACY: still uses `TGCameraController` for Passport-specific intents (`PassportId`, multiple, selfie/document crop). |
| `LegacyMediaPickerUI/LegacyAttachmentMenu` | LEGACY: still owns the carousel camera, `PGCamera.cameraAvailable()`, and editor-result conversion via `TGCameraController.resultSignals`. |
| `TelegramUI/Components/LegacyCamera/LegacyCamera.swift` | LEGACY SHIM: still has live callers from direct chat camera, edit-media camera, story reply camera, and shortcut share camera. |

No camera ObjC files are deletion-safe yet: `TGCameraController`, `PGCamera`,
`TGAttachmentCameraView`, `TGAttachmentCarouselItemView`, and camera view/control
headers are still referenced by the live surfaces above and by internal
`LegacyComponents` users such as avatar/video-message capture.

| Step | Work |
|---|---|
| 2.1 | Map every remaining Legacy camera entry to the modern `Camera` /
`CameraScreen` API (gaps = missing intents: video-only, attachment slot, volume
button handler) |
| 2.2 | Implement missing intents on the Swift side; do not extend ObjC |
| 2.3 | Flip call sites (one commit per major surface: chat attach, stories, peer
avatar if any) |
| 2.4 | Delete camera ObjC subtree + `LegacyCamera` shim module |

**DoD:** `rg TGCameraController|PGCamera` empty outside history; attach +
stories camera smoke-tested.

## Phase 3 — Photo / video editor

**Neck:** High traffic on `TGPhotoEditor*` slider/tabs/buttons from DrawingUI /
MediaEditor bridges; modern `MediaEditor` already exists.

| Step | Work |
|---|---|
| 3.1 | List every `TGPhotoEditor*` / paint-entity type still imported from Swift |
| 3.2 | Close feature gaps in Swift `MediaEditor` (tabs, done/send/schedule
buttons, crop) |
| 3.3 | Flip DrawingUI / gallery edit entry points |
| 3.4 | Delete editor ObjC behind the neck |

**DoD:** Edit → send / schedule / crop parity; no `TGPhotoEditor*` in Swift.

## Phase 4 — Drawing / paint remnants

Often partially entangled with Phase 3. Treat as a separate delete wave only if
editor migration leaves a paint island (`TGPhotoPaint*`, stickers paint
context in `LegacyMediaPickerUI`).

**DoD:** DrawingUI no longer imports LegacyComponents for paint entities.

## Phase 5 — Media picker / gallery (largest)

**Neck:** `MediaPickerUI` + `LegacyMediaPickerUI` still lean on
`TGMediaPickerGallery*`, `TGModernGallery*`, send action sheets, asset types.

| Step | Work |
|---|---|
| 5.1 | Split “grid/picker UI already Swift” vs “gallery item/model still ObjC” |
| 5.2 | Port gallery item/model/fetch-result types into MediaPickerUI (or a new
`MediaGallery` Swift module) |
| 5.3 | Flip `LegacyMediaPickers` / wallpaper / avatar pickers |
| 5.4 | Delete gallery + picker ObjC; retire `LegacyMediaPickerUI` when empty |

**DoD:** Single Swift picker/gallery path for chat, avatar, wallpaper; module
deleted or reduced to thin deprecated shims scheduled for removal.

**Budget:** Largest phase — expect multiple CI cycles; never land a half-deleted
gallery.

## Phase 6 — Shared utilities & POP

Only after Phases 1–5 remove internal LC consumers:

| Item | Action |
|---|---|
| `TGStringUtils` / `TGDateUtils` | Either already unused → delete, or fold tiny survivors into Swift helpers next to call sites |
| Facebook POP (`POPAnimatableProperty`, …) | Replace with `UIViewPropertyAnimator` / existing Display transitions — **replace, don't translate** |
| `SSignalKit` ObjC | Delete when LC no longer links it; SwiftSignalKit already owns the app |

## Phase 7 — Explicit non-goals (parked)

| Area | Why parked |
|---|---|
| `MtProtoKit` non-crypto | Tractable but outage-class risk; shared upstream |
| `GCDAsyncSocket` | Replace with `NWConnection` only if transport work is funded — not a Swift port |
| `libphonenumber` generated `.m` | Regenerate / swap library |
| ffmpeg / codecs / SIMD | Never |
| Crypto (`MTEncryption` etc.) | Never |
| AsyncDisplayKit / Texture | Vendored; migrate screens off it only as separate UI work |

## Verification checklist (every phase)

- [ ] Neck inventory committed or pasted in PR description (call-site table)
- [ ] Swift module builds as its own Bazel target before call-site flip
- [ ] Full `Telegram/Telegram` CI green after flip
- [ ] Full CI green after ObjC delete
- [ ] Device smoke of the cluster’s primary flows
- [ ] `rg` clean for deleted symbols
- [ ] Inventory numbers in `SWIFT_MIGRATION.md` refreshed if LOC moved >1k

## Suggested sequencing on the calendar

No day/week estimates — cost is **CI runs + device verification depth**:

1. Phase 0 pass → Phase 1 Passport (proves the pipeline)
2. Phase 2 Camera (high user visibility, partial work exists)
3. Phase 3–4 Editor / paint
4. Phase 5 Picker/gallery (only when 2–4 are done — shared types)
5. Phase 6 utilities / POP / SSignalKit funeral
6. Revisit Phase 7 only with an explicit product reason

## First concrete ticket (start here)

**Phase 1.1 — Passport neck freeze**

1. List every symbol under the Passport ObjC cluster and every Swift reference.
2. Write a one-page “replacement API” sketch for attach + scan + OCR in
   `PassportUI` (no LC types in the public Swift surface).
3. Do **not** delete ObjC until 1.3 is on a green IPA tag.

## Related docs

- [`docs/SWIFT_MIGRATION.md`](../SWIFT_MIGRATION.md) — strategy, Bazel blocker, never-migrate list
- [`docs/PERFORMANCE_AUDIT.md`](../PERFORMANCE_AUDIT.md) — heat/CPU; orthogonal to this plan
