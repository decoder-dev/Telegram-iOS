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

## Follow-up review, 10 October 2026

Reviewed Donutgram master commits from 15 September to 6 October (up to `b4fc6ac`),
`feat/chat-media-visibility` at `f0d0b0682443a7693e6b5e5952bc47f46a9e5736` and
`feat/deleted-media-search-local-folder-colors` at `ac0f91948e48bf0196acb5be388ba1e2f050a6cc`.

### Adapted

- Long-press on any regular inline bot button offers to copy its title and, for
  callback buttons, the callback data (non-UTF-8 payloads as hex). Link buttons keep the
  link menu. Based on [a5e267f](https://github.com/kittenello/Donutgram/commit/a5e267f).
- Profile status refresh: the manager that re-renders "last seen N minutes ago" was
  released immediately and its one-shot timer never fired, so the text went stale while
  the profile was open. It is now kept alive and re-armed after each tick. Based on
  [0d30b60](https://github.com/kittenello/Donutgram/commit/0d30b60).
- Account limit raised to 500 independent of Premium
  ([94239ad](https://github.com/kittenello/Donutgram/commit/94239ad)); the "add account"
  help text states the real limit.
- With "Save Stories & Protected Media" on, protected stories also stop blocking screenshots
  and screen recording ([873da44](https://github.com/kittenello/Donutgram/commit/873da44)).
  Reuses the existing switch; its footer says so.
- Round video: locking a recording resets the slide-to-cancel offset, so "Cancel" no
  longer stays faded out after a quick flick up
  ([8a8fc4b](https://github.com/kittenello/Donutgram/commit/8a8fc4b)).

### Already present, not imported again

Round video snapshot cover and flip-only animation (134d802), zoom dial labels, glide and
touch fixes (8a8fc4b remainder, c1e722d, 0272252, 39f4436, bd020b8), built-in microphone
switch, mention avatars, edited mark hidden in story-forward previews (af392b9), archive
pull gesture (abe83fa), stop-after-voice/round-video playback, hide paid reactions, via-bot
labels, birthdays, bot automation panel and pinned messages with bot panel, shadow ban
for people, bots and channels, Ghost mode read/view guards, save-to-cloud and
select-from-author menu items, bottom folders, avatar and reaction glow.

### Adapted later, 10 October 2026

- Hashtags open the This Chat tab (`f0d0b06`): Interface > Chats switch.
- Banned GIFs as silent looping videos (c7bb578): Interface > Chats switch, off by default.
  Only chats that ban GIFs but allow videos are affected.
- Music as a voice message (a5e267f): context menu on a track in Attach > Music, offered only
  where voice messages are allowed. Encoding is on the phone (Opus, 48 kHz mono).
- Original date on forwarded messages (a5e267f): Interface > Chats switch.
- From AyuGram Desktop: no greeting sticker (switch) and Hide Blocked Messages also hiding
  messages sent through a blocked inline bot.

### Skipped

- Disappeared gifts, deleted-message reply quotes, saving messages from pushes and
  user ID search: depend on DonutgramSpyStorage or on an unverified server behaviour
  (`users.getUsers` with a zero access hash); BananaGram uses MessageSavingStore.
- Presence "last seen" toggle (51834f5) and own last seen: rely on DGSimpleSettings
  (relative online time, ghost last-online store) which BananaGram does not have.
- Online dot lifetime, chat list header centring and status hiding, island styles,
  poll results before voting: Donutgram-specific features or server-dependent.
- Ghost story question timing (0312c36, cf1d120): tied to Donutgram's ghost prompt design;
  BananaGram asks before opening a story instead.
- Folder colours: unchanged policy, core filter synchronization.
