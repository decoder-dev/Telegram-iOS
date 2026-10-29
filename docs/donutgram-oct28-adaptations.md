# Donutgram adaptations, 29 October 2026

Reviewed Donutgram master from `b4fc6ac` (6 October) to `c779066` (28 October). Both switches are off by default
and live in Extras.

## Added

- **Approximate last seen** (#120). Extras > Profile. A person whose last seen is hidden shows as
  "last seen today at ~14:22" instead of "last seen recently", from the time of their latest activity this client
  saw. The activity is the existing `TelegramUserPresence.lastActivity`, which the state replay already moves for an
  incoming message (away and greeting messages excluded) and for the read of one of our messages; the donor's separate
  presence field is not copied, so no stored model changes. Only a hidden ("recently") status is replaced, an
  activity older than the moment the switch was turned on, or older than three days, is ignored, and the moment is
  forgotten when the switch goes off. The text refreshes at local midnight and when the activity gets too old
  (`BananaApproximateLastSeen`). An open chat or profile shows the change after it is reopened.
- **Send stickers anonymously** (#121). Extras > Media. A sticker is re-uploaded as a plain document without the
  reference to its set (not in secret chats), so the recipient cannot open the set. The sender keeps the set on the
  device, by the id of the file the server made (500 most recent, per account), to open it from their own chat and to
  offer "View sticker set" (`BananaAnonymousStickers`).

## Already present

Copy photo and copy frame in the gallery, mp4 from Files sent as video (#108); content restriction bypass
(`bypassDownloadRestrictions`); hiding messages of blocked users; service message filter; selecting all messages of an
author; "Go to start of chat" in the avatar menu; disabling the camera swipe in stories; disappeared gifts.

## Not taken

Wallet, QR codes, Pass, the new Share screen and the 15 settings sections (separate subsystems with their own API),
and the search on the saved-deletions page (depends on `DonutgramSpyStorage`; BananaGram uses `MessageSavingStore`).

Neither feature could be run on a device: they are covered by source-text tests (`Tests/Upstream13/donut_oct28.py`)
and the full build. The anonymous upload path (a re-uploaded cloud sticker with its set dropped) needs one send to a
real chat to confirm that the server accepts it as a sticker.
