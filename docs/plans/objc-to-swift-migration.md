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
| `LegacyComponents` | ~145k LOC, **322** `.m` files — primary target |
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

**2026-08-10 third wave** — same root-based reachability, tightened so that a
mention which only ever appears on an `#import`/`#include` line, in an
`@class`/`@protocol` forward declaration, or inside a comment does **not**
count as a use. Stale imports are what kept the two islands below alive:

- The legacy **message model**: `TGAudioMediaAttachment`,
  `TGBotContextResultAttachment`, `TGContactMediaAttachment`,
  `TGGameMediaAttachment`, `TGInvoiceMediaAttachment` (+ its only consumer of
  `TGWebDocument`), `TGLocalMessageMetaMediaAttachment`,
  `TGUnsupportedMediaAttachment`, `TGViaUserAttachment`. These are reachable
  only through `TGMessage`'s dynamic parser registry, and nothing anywhere
  calls `+registerMediaAttachmentParser:`, so no code path can construct them;
  their type constants never leave their own files either. Same story for
  `TGBotReplyMarkupRow` / `TGBotReplyMarkupButton` (`TGBotReplyMarkup.rows` is
  an untyped `NSArray`) and for `TGStickerPack`, which had no references at all.
- The **conversation / instant-page island**: `TGWebPageMediaAttachment` →
  `TGInstantPage` → `TGConversation` → `TGChannelAdminRights`,
  `TGChannelBannedRights`, `TGDatabaseMessageDraft`. Each link is the sole user
  of the next, and the head is reachable only from a stale `#import` in
  `TGMessage.h` plus a forward declaration in
  `TGAuthorSignatureMediaAttachment.h`.
- `TGLabel` (only a forward declaration in `TGViewController.h`),
  `LegacyHTTPRequestOperation` (an unused protocol imported by
  `LegacyComponentsGlobals.h`), and the mutually-referencing
  `TGOverlayFormsheetController` / `TGOverlayFormsheetWindow` pair, whose only
  outside mention is commented-out code in `TGMediaAvatarMenuMixin`.

Checked and deliberately **kept**: `UIControl+HitTestEdgeInsets` (a
property-only category — 17 Swift call sites set `hitTestEdgeInsets`, and a
selector scan that ignores `@property` will wrongly call it dead),
`NSObject+TGLock` (the `TG_SYNCHRONIZED_*` macros are used by `ASHandle` and
`TGFont` even though the two methods are not), `FloatConversion.h` (C++
templates, invisible to an ObjC-shaped symbol scan), and the
`AVURLAsset`/`UIImage`/`TGMediaAsset` `TGMediaEditableItem` categories, which
supply protocol conformances consumed through `id<TGMediaEditableItem>` and so
can never be proven dead statically.

After the message-model + conversation deletes (and the Phase 3 recon that
removed implementation-less `TGPhotoPaint*Entity` headers), `LegacyComponents`
stood at 324 `.m` + 25 `.mm` files and 242 public headers.

**2026-08-10 fourth wave** (`ede84449dc`) — leftovers the third-wave scan still
left standing:

- `TGMessageHole` / `TGMessageGroup` — only unused properties on `TGMessage`
  (copied in `-copy`, never constructed / encoded / read; not PSCoding).
- `POPDecayAnimation` (+ internal header) — never instantiated. Live POP users
  are spring/basic. Removed the class and the decay-only autoreverse branches
  in `POPAnimator`; left the unreachable `kPOPAnimationDecay` enum value.
- Dead `TGStringUtils` surface — zero call sites outside the defining file
  (HTML unescape + escape tables, actor-URL escape, base64, emoji/mute/currency/
  timer/call/device/user-count formatters, `phoneMatchHash` /
  `legacy_murMurHashBytes32`, `TGIsKorean` / `TGIsLocaleArabic`, unused
  `NSString (Telegraph)` category). Kept: URL escape, localized numbers, md5,
  `stringComponentsForMessageTimerSeconds`, `stringForFileSize:precision:`,
  `integerValueFormat`, `legacy_murMurHash32`, `TGIsRTL` / `TGIsArabic`,
  `NSData` hex helpers. Watch / CallsEmoji / TelegramStringFormatting keep
  their own same-named helpers.

`LegacyComponents` is now **322** `.m` + **24** `.mm` files and **239** public
headers (~144k LOC).

**Known-dead, left to their phase owners** (verified unreachable, but inside a
subtree another phase is actively editing — delete them as part of that phase's
commit rather than as hygiene):

- ~~`TGCameraFlashActiveView`~~ — deleted (Phase 2 hygiene).
- ~~`TGModernGalleryImageItem` / `TGModernGalleryImageItemView`~~ — deleted
  (Phase 5 hygiene). Kept `TGModernGalleryImageItemImageView` /
  `TGModernGalleryImageItemContainerView` (still used by zoomable gallery).

**Exit:** Continuous; run a pass before each numbered phase.

## Phase 2 — Camera (finish the parallel migration) — IN PROGRESS

**2026-08-10:** Media picker default asset mode now uses the Swift
`CameraSimplePreviewView` path instead of `TGAttachmentCameraView`; the dead
legacy preview branch in `MediaPickerUI` was removed. Chat's default media
picker preview tile and the non-`CameraHolder` `openCamera` fallback now open
`context.sharedContext.makeCameraScreen` and map basic modern photo/video/asset
results back into the existing `enqueueMediaMessages` legacy-signal pipeline
via `SharedAccountContext.legacyCameraCapturedMediaSignals(fromCameraScreenResult:)`.
Story reply and edit-media cameras also use `makeCameraScreen`.
`presentedLegacyCamera` was **deleted** (2026-08-10) — it had no remaining
Swift callers after the edit-media / story flips. Remaining necks:
Passport `TGCameraController` intents, `LegacyAttachmentMenu` carousel /
`TGCameraController.resultSignals`, and ``presentedLegacyShortcutCamera` (deleted)`.
Schedule/silent/timer/QR on flipped paths remain a temporary gap (send immediately).

### Shortcut share camera — leave (do not flip yet) — 2026-08-10

`TelegramRootController.openRootCamera` still calls
``presentedLegacyShortcutCamera` (deleted)` → `TGCameraController` → `makeShareController`
(`.fromExternal` enqueue). **Not flipped** to `makeCameraScreen`:
`CameraScreenMode` is only `.story` / `.sticker` / `.avatar`. None of those
modes produce the capture-then-share-sheet product flow. Revisit after a
share/generic `CameraScreenMode` exists.

### Passport attach camera — gap (do not flip yet) — 2026-08-10

`PassportUI/Sources/SecureIdAttachmentMenu.swift` still constructs
`TGCameraController` with `PassportIntent` / `PassportIdIntent` /
`PassportMultipleIntent` (plus selfie `disableResultMirroring`). That path is
**live** from `presentSecureIdAttachmentMenu` → document form / auth flows.

**Why not Option A (flip to Swift now):**

- `SecureIdScanController` is **MRZ OCR only** (Vision frame poll →
  `SecureIdMRZ`). It does not capture / crop / multi-select document photos for
  SecureId attach upload.
- `CameraScreen` / `CameraScreenMode` today is only `.story` / `.sticker` /
  `.avatar`. It has no Passport equivalents for:
  - `onlyCrop` editor mode (all three Passport camera intents)
  - identity-card document frame overlay + fixed 0.704 aspect auto-crop
    (`PassportIdIntent`)
  - multi-capture + selection panel (`PassportMultipleIntent`)
  - attach-menu carousel preview detach/reattach into `TGCameraControllerWindow`
  - result handoff into `secureIdAttachmentResultSignal` (`TGCameraCapturedPhoto`
    / editing + selection contexts → scaled image dicts)

Until those intents exist on `CameraScreen` (Phase 2 step 2.2), keep the
Legacy path. **Do not delete `TGCameraController` or the Passport intent enum
cases** — they are still reachable. No unreachable `TGCameraControllerPassport*`
branches were found to prune; media-picker
`TGMediaAssetsControllerPassport*Intent` remains live for the same attach menu.

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
| `ChatControllerOpenAttachmentMenu.openCamera` | DONE: both `CameraHolder` and non-holder paths present `makeCameraScreen(.sticker)` and convert results via `legacyCameraCapturedMediaSignals(fromCameraScreenResult:)`. Schedule/silent/timer/QR not yet on CameraScreen completion (send immediately). |
| `ChatControllerOpenAttachmentMenu` edit-media `legacyAttachmentMenu` `openCamera` | DONE: dismisses menu sheet and presents `makeCameraScreen`; drops carousel transition. |
| `StoryItemSetContainerViewSendMessage` | DONE: all preview types use `makeCameraScreen` + AccountContext result bridge. Dropped `LegacyCamera` module dep. |
| `PassportUI/SecureIdAttachmentMenu` | BLOCKED / LEGACY: still uses `TGCameraController` for Passport-specific intents (`PassportId`, multiple, selfie/document crop). Not flippable to `SecureIdScanController` (MRZ-only) or current `CameraScreen` modes — see “Passport attach camera — gap” above. No dead Passport intent branches to delete. |
| `LegacyMediaPickerUI/LegacyAttachmentMenu` | LEGACY: still owns the carousel camera, `PGCamera.cameraAvailable()`, and editor-result conversion via `TGCameraController.resultSignals`. |
| `TelegramRootController` shortcut share | DONE: `openRootCamera` uses `makeCameraScreen` + share sheet via legacy enqueue signals. `LegacyCamera` module deleted. Left intentionally — no share/generic `CameraScreenMode`. |
| `TelegramUI/Components/LegacyCamera/LegacyCamera.swift` | SHIM: only ``presentedLegacyShortcutCamera` (deleted)` remains (`presentedLegacyCamera` deleted). |

No camera ObjC files are deletion-safe yet: `TGCameraController`, `PGCamera`,
`TGAttachmentCameraView`, `TGAttachmentCarouselItemView`, and camera view/control
headers are still referenced by Passport, LegacyAttachmentMenu carousel,
shortcut camera, and internal LC users (avatar / video-message capture).

| Step | Work |
|---|---|
| 2.1 | Map every remaining Legacy camera entry to the modern `Camera` /
`CameraScreen` API (gaps = missing intents: video-only, attachment slot, volume
button handler; **Passport** onlyCrop / PassportId frame+auto-crop /
PassportMultiple / selfie mirror / SecureId result signal) |
| 2.2 | Implement missing intents on the Swift side; do not extend ObjC.
Passport attach stays on `TGCameraController` until these land. |
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

### 3.1 status — Swift call sites flipped 2026-08-10

~22k LOC of `TGPhoto*` ObjC sits behind a neck of exactly **five** symbols.
Everything else in the editor — `TGPhotoEditorController`, the tab controller,
tools/curves/tint/blur/crop/quality/HUD/preview views, `TGPhotoEditorButton`,
`TGPhotoToolCell`, `TGPhotoDrawingController`, `TGPhotoAvatarCropView`,
`TGPhotoAvatarPreviewController`, `TGPhotoCaptionInputMixin` — has **no**
reference outside `LegacyComponents` and dies with the neck, not before it.

**Swift slider surface is LC-free:** `EditorStyleSliderView` (pure-Swift
`UIControl` in `SliderComponent/Sources`) replaced every Swift construction of
`TGPhotoEditorSliderView` — `SliderComponent` itself plus ItemList/settings
call sites in `SettingsUI`, `PeerInfoUI`, `InviteLinksUI`, `PremiumUI`,
`InstantPageUI`, `MessagePriceItem`, and `WallpaperPatternPanelNode`.
`StorageKeepSizeComponent` already used `SliderComponent` (dead comment only).
`TGPhotoEditorSliderView` is **not** deleted — ObjC editor tool views inside
`LegacyComponents` (`TGPhotoEditorGenericToolView`, tint/blur, collection hit
test) still own it.

| Neck symbol | External call sites | Notes |
|---|---|---|
| `TGPhotoEditorSliderView` | **ObjC only** inside `LegacyComponents` (generic/tint/blur tool views + `TGPhotoEditorCollectionView` hit test). No remaining Swift constructors. | Deleting the ObjC slider waits on Phase 3.2–3.4 editor flip. |
| `TGPhotoToolbarViewProtocol` (+ the `TGPhotoEditorTab` / `TGPhotoEditorBackButton` / `TGPhotoEditorDoneButton` enums it declares) | `MediaPickerUI/MediaPickerPhotoToolbarView.swift`, `LegacyMediaPickerUI/LegacyAttachmentMenu.swift`, `LegacyMediaPickerUI/LegacyPaintStickersContext.swift`, `LegacyCamera/LegacyCamera.swift` | Already half-migrated, and it shows the pattern to copy: the toolbar is **Swift** (`MediaPickerPhotoToolbarView`) and is injected into the ObjC editor through `stickersContext.photoToolbarView`. `TGPhotoEditorController` / `TGMediaPickerGalleryInterfaceView` fall back to the ObjC `TGPhotoToolbarView` only when that block is nil. Deleting the ObjC toolbar means proving every caller supplies the block. |
| `TGPhotoPaintStickersContext.h` | 13 Swift files (`DrawingUI` drawing view/entities/interface controller, `AttachmentTextInputPanelNode`, `MediaPickerUI`, `LegacyMessageInputPanel`, stories send path, `ChatControllerOpenAttachmentMenu`, …) | Widest, but it is a **pure protocol header** (`TGPhotoDrawingView`, `TGPhotoDrawingEntitiesView`, `TGPhotoDrawingInterfaceController`, `TGPhotoDrawingAdapter`, `TGCaptionPanelView`, `TGLivePhotoButton`, `TGPhotoPaintEntityRenderer`, …) whose implementations are already Swift. It is the ObjC↔Swift seam, not editor code, and should be the **last** thing removed. |
| `TGPhotoVideoEditor` | `LegacyMediaPickerUI/LegacyAttachmentMenu.swift` (`legacyWallpaperEditor`, `legacyMediaEditor`, gallery controller), `LegacyMediaPickerUI/LegacyAvatarPicker.swift` (`legacyAvatarEditor`) | The actual editor entry point — four class methods. Reached from `ChatController` (edit media + avatar), `ChatControllerEditGif`, `PeerInfoScreenOpenMessage`, `WallpaperGalleryController`, `AuthorizationSequenceSignUpController`. This is where a Swift `MediaEditorScreen` bridge has to land. |
| `TGPhotoEditorUtils`' `TGPhotoEditorCrop` | `WallpaperGridScreen/WallpaperUtils.swift` | One C function; trivially portable, but the file also holds orientation helpers used all over `LegacyComponents`. |

Notes for whoever picks 3.2 up:

- ~~`legacyStoryMediaEditor`~~ — **deleted 2026-08-10** with `StoryMediaEditorResult`.
- ~~`TGPhotoEditorCrop` in WallpaperUtils~~ — **ported 2026-08-10** to local Swift crop.
- Sequencing that falls out of the table: (1) ~~Swift slider
  (`SliderComponent` + ItemList/settings call sites)~~ (done), (2) guarantee
  the Swift toolbar is always injected and drop the ObjC fallback, (3)
  `TGPhotoVideoEditor` → `MediaEditorScreen` bridge, (4) delete the
  `TGPhoto*` subtree (incl. `TGPhotoEditorSliderView.m`), (5) retire
  `TGPhotoPaintStickersContext.h` once DrawingUI no longer needs an ObjC seam.
- **Already deleted (2026-08-10, safe leaves only):** `TGPhotoPaintEntity`,
  `TGPhotoPaintStickerEntity`, `TGPhotoPaintTextEntity` — three headers
  declaring classes with no `@implementation` anywhere in the repo, reachable
  only through stale imports in `TGMediaVideoConverter`, `TGPaintingData` and
  `TGVideoEditAdjustments`. No other `TGPhoto*` file is deletion-safe today.


### 3.2 progress — 2026-08-10

| Landed | Detail |
|---|---|
| Dead Swift editor shim | Removed `legacyStoryMediaEditor` / `StoryMediaEditorResult` |
| Crop neck cleared from Swift | `WallpaperUtils` local `cropWallpaperImage`; drops LegacyComponents import |
| SliderComponent + ItemList off ObjC | `EditorStyleSliderView` replaces every Swift `TGPhotoEditorSliderView` constructor (`SliderComponent`, Settings/PeerInfo/InviteLinks/Premium/InstantPage ItemList embeds, `MessagePriceItem`, `WallpaperPatternPanelNode`). ObjC tool views still use `TGPhotoEditorSliderView` — **do not delete yet** |
| Phase 2 adjacent | Deleted unused `presentedLegacyCamera`; trimmed LegacyCamera deps |

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
