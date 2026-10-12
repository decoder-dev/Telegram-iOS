# Donutgram adaptations, 13 October 2026

Sources: [Donutgram PR74](https://github.com/kittenello/Donutgram/pull/74),
[PR75](https://github.com/kittenello/Donutgram/pull/75),
[PR79](https://github.com/kittenello/Donutgram/pull/79),
[PR86](https://github.com/kittenello/Donutgram/pull/86).
Donor snapshot d6fbd5105e; retained source attribution to kittenello and catboysense.
These are contextual adaptations, not a rewrite of donor commit authorship.
AltStore and its publication branch are excluded at the user's request.

## Added

- Retained deleted cloud messages join in-chat search, including attachment filenames,
  sender, reaction, topic, dates and media filters. Local results do not enter the
  server pagination state. Duplicate ids are merged; older local results appear as
  their remote search window loads. Migrated groups remain supported.
- Retained media join the profile's sparse media list, replacing matching placeholders
  without duplicating ids. Server holes continue to use cloud message anchors.
- A persistent unused local tag indexes future deletions. Old locally retained messages
  gain that index from the account-scoped snapshot store when search/media opens.
  Hard-deleted messages are not resurrected, and missing attachments are not invented.
- Ghost-mode screenshot service messages are suppressed, including mixed batches while
  keeping result positions. Stories queued before the ghost toggle are checked before RPC.
- Ghost scheduling covers multi-peer forwarding and other enqueue consumers. Existing
  user dates/repeat periods and quick replies are preserved; secret chats send immediately.
  Existing UI media-dependent delays remain intact.
- Automatic offline is requested after edits, reactions, polls, bot actions, quick replies,
  games and sending a scheduled message now. Read-on-interact windows are respected.
- Joining another user's live story asks for confirmation while story reads are hidden.
  Consent is scoped to the current peer/story and resets on item changes.
- Statistics are an opt-in in Extras privacy, off by default: analytics events,
  reading/listening metrics, service log upload and call debug logs. Queued analytics
  are discarded unsent while off. Local diagnostic logs remain available.
- Remove pings is independent from Hide mention notifications: live mention badges and
  counts disappear, while push routing respects ordinary chat/topic mute/sound settings.
  The durable setting is projected to the Notification Service. Stored mention tags stay
  untouched so switching it off restores their presentation.
- Extras appearance includes a banana app badge and optional BananaGram label. The
  existing Window badge location/device/orientation/app-focus rules are preserved.
  The image updates immediately with the setting and theme; no ActivityKit or background
  live activity is introduced.

## Existing behavior retained

Local folder colors/tags already use per-account overrides without sending those
overrides to Telegram. Voice/round-video stop-after-playback, no-link-preview sending
and current-chat hashtag routing already have working consumers and remain unchanged.
The search bar in our root/forum header is not hidden by a preference, so the missing
placeholder mechanism fixed in PR86 does not apply. The new lower search button uses
that existing visible-header search path. Explicit Mark Read / Read All remain intentional
server reads, separate from automatic content receipt suppression.

## Validation and limits

`Tests/Upstream13/donut_oct13.py` is in both CI workflows. It executes extracted
production search/filter/merge functions and every combination of scheduling policy,
checks persistence/notification/consent wiring and parses changed Swift files.
Windows has no Swift/Xcode: skipped Swift fixtures require macOS CI, and application
plus five extension libraries require the complete build. Source assertions do not
prove iPhone visuals, actual network behavior, signature trust or runtime calls.
Deleted messages must have been retained locally before deletion. Snapshot export
without its original Postbox messages does not fabricate searchable cloud messages.
