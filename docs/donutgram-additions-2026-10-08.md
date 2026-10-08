# BananaGram additions and Donutgram branch review

Sources reviewed at Donutgram master `b4fc6aca7b0240f132c99b8eb0ff05eae3a7a85d`.
Existing source attribution and commit history are preserved. These are adaptations,
not a claim that the upstream implementations originated in BananaGram.

## Implemented adaptations

- Gallery video as a round video message, based on
  [05bbb5bfed](https://github.com/kittenello/Donutgram/commit/05bbb5bfed).
  A single gallery video is eligible; files, paid media, multi-selection and peers
  that disallow video messages are excluded. Existing crop/rotation/edit values are
  retained, with a centered square crop and a maximum 60-second selected segment.
  A confirmation reports the conversion before sending; cancelling leaves edits intact.
  Upload/conversion uses the existing cancellable media resource pipeline.
- Separate music pause settings for video recording (including round messages),
  voice recording and voice playback. Audio mixing is adapted from
  [be04eae76b](https://github.com/kittenello/Donutgram/commit/be04eae76b).
  Settings live in the existing MediaInputSettings storage. Old video-recording
  preferences are preserved; voice actions keep their previous pause defaults.
  Active voice/video calls have priority over a new mixing player or recorder.
- Optional channel forward counts, adapted from
  [765424b28b](https://github.com/kittenello/Donutgram/commit/765424b28b).
  Counts come from server message attributes. Missing attributes are populated by
  the existing view-count response, without adding a polling loop. Turning the
  option on/off refreshes an open chat through the existing settings fingerprint.
- Links to actionable BananaGram settings rows. Inspired by
  [DGSettingLinks](https://github.com/kittenello/Donutgram/blob/b4fc6aca7b0240f132c99b8eb0ff05eae3a7a85d/Donutgram/DGSettingsUI/Sources/DGSettingLinks.swift),
  implemented against our existing ItemList screens. Long-press a row to copy
  `tg://settings/bananagram/<page>/<stable-row-id>`. Opening it scrolls to and
  highlights the row; it never changes the setting. Controls keep their gestures.
  Audio options also have settings-search paths under `data/pause-music*`.

## Duplicate avoidance

Ghost local reads, ghost read/view guards, avatar/reaction glow controls, live tab
configuration, native camera zoom factors and shadow-ban translations already exist
in BananaGram and were not imported again. Audio settings extend the existing
storage and screen rather than introducing a parallel settings system. Links reuse
the existing URL dispatcher; counters reuse the existing server update stream.

## Other branches reviewed

- `feat/chat-media-visibility` at `7a2a6c7233fda8a27a4baa5d1f3c06c12ed60981`
  is four commits ahead of master. Useful follow-ups: independently stop advancing
  to the next voice/round message, and retain pinned messages alongside a managing
  bot panel. Other toggles hide paid reactions, birthdays, via-bot labels, bot
  automation and outgoing link previews. Some overlap our existing display and
  autoplay settings; these need a mapping before adding more switches.
- `feat/deleted-media-search-local-folder-colors` at
  `ac0f91948e48bf0196acb5be388ba1e2f050a6cc` is three commits ahead of master.
  Adds preserved-media search, local folder colors/tags and mention notification
  routing. Search depends on DonutgramSpyStorage, unlike our MessageSavingStore.
  Folder colors change core filter synchronization; this branch is not merged
  wholesale while the reported missing ordinary chats remain unexplained.

## Validation boundaries

Tests/ClientAdditions runs real extracted Swift for settings migration and all
eight audio-policy combinations, malformed/valid links, square crop and trim
edge cases. Structural checks cover send restrictions, metadata, live refresh and
duplicate row IDs. Both release and client-regression workflows run these tests.
Full iOS compilation is required before release. Bluetooth routes, microphone
capture, video orientation/rendered thumbnails, VoiceOver and actual device
appearance still require an iPhone run; CI does not prove these scenarios.
The report of missing ordinary chats in build 4139 remains unresolved.
