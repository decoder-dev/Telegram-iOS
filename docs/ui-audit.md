# UI consistency audit

Status: **static audit + fixes applied** (this commit). Scope: every fork-modified screen, plus
cross-cutting checks over the whole app (localization, search indexing, settings rows, section
integrity). Stock Telegram screens are internally consistent; they were audited at the
cross-cutting level and where they interact with fork features. No build/runtime verification
was possible in this environment — §4 is the device checklist.

## 1. Methodology

- Read every fork-owned string source end-to-end (`ForkPresentationLanguage`,
  `ArchiveLockLocalizedString`, `ForkExtrasLocalizedString`, `DebugLocalizedString`,
  `messageSavingLocalizedString`, `forkExtrasSettingsTitle`/`forkDeveloperModeSettingsTitle`) and
  cross-checked definition ↔ usage (dead keys, duplicated values, divergent language rules).
- Read the fork screens end-to-end: proxy add/edit form, proxy list, WEB catalog sheet, proxy
  preview sheet, Data & Storage proxy row, peer-info settings rows, Extras hub + category
  screens, saved-deleted/edits history screens, Archive lock screens.
- Cross-checked the settings search index (`SettingsSearchableItems`) against the screens it
  routes to.
- Checked stableId/section integrity of every fork item-list enum touched (uniqueness within
  controller, ordering matches append order).
- Checked text styling classes used by fork rows (`ItemListSwitchItem`, `ItemListTextItem`,
  `ItemListCheckboxItem`, `ItemListDisclosureItem`, `ActionSheetButtonItem`,
  `ActionSheetTextItem`) — all go through `presentationData`, no hardcoded colors or fonts
  found in fork UI code.

## 2. Findings — fixed in this commit

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| U-1 | P1 | **Calls disclaimer was stale after the SOCKS5-bridge client landed** (`F-1(b)`): the WEB-mode note said calls never go through the proxy, but with a capability relay they now do — the screen lied in the safer direction (users think they are exposed when they are not), and `docs/network-audit.md` already promised "depends on relay support" wording. | `ForkWebProxyStrings.callsNote` rewritten: calls go through the WEB proxy only if the relay supports call tunneling; otherwise the IP is visible during a call. Comment updated to describe the bridge. |
| U-2 | P1 | **"Use for calls" toggle hidden when a WEB proxy is active** (proxy list + settings search both gated on `.socks5`), yet the stored `useForCalls` value (default **on**) silently governs WEB calls through the bridge — the setting worked but was invisible and uncontrollable. | Toggle + help now shown for SOCKS5 *and* WEB actives (MTProxy stays hidden — tgcalls cannot use it, no bridge for it). WEB help text = `callsNote`; SOCKS5 keeps the stock help. Search index gating extended identically (`hasCallProxyServers`). |
| U-3 | P1 | **Language-rule mismatch for uk/be**: ternary fork strings (WEB proxy, message-saving, Extras/Debug rows in `PresentationData.swift`) serve Russian to ru/uk/be, but the table-based lookups (`ArchiveLockLocalizedString`, `ForkExtrasLocalizedString`) matched only exact `ru`/`en` keys — a Ukrainian-language user got fork screens that mixed Russian (ternary strings) and English (table strings). | Both table `languageCode()` implementations now map ru/uk/be → `ru` before the exact-match/device fallback, matching `ForkPresentationLanguage.prefersRussianStrings`. |
| U-4 | P2 | **WEB catalog sheet had no title** — bare hostnames + "Enter manually…" + Cancel; and `ForkWebProxyStrings.catalogPick` ("From catalog…") was defined but never used anywhere (dead key). | Catalog sheet now leads with `ActionSheetTextItem(catalogTitle)`; dead `catalogPick` key removed. |
| U-5 | P2 | **Three separate sources spelled the saved-messages feature**: context menus (`ForkMessageSavingStrings.viewDeleted`), the history screens (inline `messageSavingLocalizedString` with duplicated en/ru literals), and five never-read accessors + ten table entries in `ForkExtrasLocalizedString` — any edit would drift. | Consolidated into `ForkMessageSavingStrings` (viewDeleted, editHistory, clearDeleted, noDeleted, noEdits); history screens and the Clear button read from it; dead accessors/table entries and the inline helper removed. |
| U-6 | P2 | **"Авто"/"Auto" proxy summary value was an inline ternary duplicated** in the Data & Storage row and the peer-info settings row. | New `ForkProxySettingsStrings.autoFetchValue`; both rows use it. |
| U-7 | P2 | **WEB proxy not findable via settings search**: the Proxy row's synonyms are the stock `SOCKS5\nMTProto` catalogue string; typing "WEB" found nothing. | `ForkWebProxyStrings.proxyType` added to the Proxy and Add-Proxy search items' alternates. |
| U-8 | P3 | **Dead enum case** `usePasteboardInfo` in the proxy add/edit form (declared, rendered, never appended — leftover scaffolding). | Removed (case, section mapping, stableId, render). |
| U-9 | P3 | **Verbatim-duplicated web/non-web status branches** in the proxy list entries function (the `isWebProxy` if/else handled all three statuses identically). | Collapsed to a single switch; behavior unchanged. |

## 3. Findings — by design, no change

- **Rotation-timeout picker marks the selected option with a "✓ " prefix** instead of a stock
  selected-state component. Stock `ActionSheetButtonItem` has no selected state at all; the
  prefix is informative and used consistently in the fork's pickers. Kept.
- **Fork sections without headers** (Extras hub rows, proxy list forks rows): matches the
  grouped-list look the fork uses elsewhere; footers carry the explanation. Kept.
- **Non-RU/EN app languages see English fork strings.** The repo ships only `en.lproj`
  locally; Telegram serves other locales at runtime and a fork key is never in that catalogue.
  English fallback is the deliberate trade-off (`ForkPresentationLanguage` doc comment).
- **Two string mechanisms coexist** (ternary enums in TelegramUIPreferences vs en/ru tables in
  feature modules). The tables need module-local keys and the enum needs nothing — consolidating
  them into one cross-module table would add a dependency edge for little user-visible gain.
  Documented here instead.
- **`SettingsSearch_Synonyms_Proxy_Title`** ("SOCKS5\nMTProto") is a catalogue string the fork
  cannot edit for RU users (server-served); the fork appends its own synonym at the call site
  (U-7) instead.

## 4. Visual bug hunt (second pass)

Focus: rendering/layout defects, not strings. Every fork visual feature was traced to its
layout code: compact chat list / preview, folder-tab font, message-timestamp seconds, sticker
size, wide channel posts, reactions-bar hiding, deleted/edited marks, profile diagnostic rows,
app-icon naming. Verified-clean along the way: `hideReactionsBar` swaps the attribute to an
empty one (no reserved-gap artifacts); sticker scaling (50–150% of 184 pt) fits bubble widths;
timestamp/marks flow through measured text (no fixed widths, no truncation risk); the
`scheduleWhenOnline` placeholder interacts safely with the marks.

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| V-1 | P2 | **Profile diagnostic labels were English-only** — the `registered` row label was a hardcoded string in a screen that is otherwise RU/EN bilingual. (`id`/`dc` stay as-is: universal tokens, AyuGram parity.) | Label localized via `ForkPresentationLanguage` («регистрация»/«registered»). |
| V-2 | P1 | **Layout-affecting Extras toggles did not apply live** — item nodes read `ForkExtrasHotFlags` statics at layout time, and nothing invalidated already-rendered UI: after toggling compact rows/preview, folder-tab font, seconds, sticker size, wide posts, reactions bar or the marks, the screen re-rendered only rows that happened to re-layout — a half-old, half-new mix until restart. (`hideAllChats`/`rememberLastFolder`/`hideTabBar` were the exceptions: they had reactive wiring.) | Chat list: `ChatListContainerNode.refreshForkItemLayouts()` re-emits each tab's list state (a fresh `ChatListPresentationData` instance — `==` compares it by reference), wired to a new controller subscription on the compact flags; `compactFolderNames` joined the existing folders subscription whose `reloadFilters()` ends in a full layout pass for the tab bar. Chats: the fork's own `MessageFilterSettingsFingerprint` in `ChatHistoryListNode` now also carries `showMessageSeconds`, `wideChannelPosts`, `stickerSizePercent`, `hideReactionsBar`, `deletedMessageMark`, `editedMessageMark`, so a toggle re-emits the history and message nodes re-layout with fresh flag reads. |
| V-3 | P2 | **Inverted equality in `ChatListNodeState ==`**: `if areFoundPeerArraysEqual(...) { return false }` — missing `!`. With the usual equal (empty) found-peer arrays every state comparison said "changed", so every `updateState` call (typing ticks, reveal actions, selection) re-emitted and re-laid-out the whole visible list. Correctness was saved by downstream dedup; the cost was constant needless list churn (battery/jank). | `!` restored. |
| V-4 | P3 | **Dead hot-flag copies**: `ForkExtrasHotFlags.saveToCloudMenu` / `.selectFromAuthor` are pushed on every settings change but never read (the features read `immediateForkExtrasSettings` instead). | Documented; left in place — removing them is churn with no user-visible gain. |
| V-5 | P3 | **`dec/zalupa` line carries unaudited visual work** (Телеграм icon family rebrand, PatriotPlane icons, calls-list type icons, proxy-list redesign). Those files are not in this branch's tree. | Not fixable here; audit them when the lines are next merged (see §5). |
| V-6 | P1 | **Profile diagnostic rows changed on tap instead of opening the value window** — the fork's `id`/`dc`/«регистрация» rows had `action: nil` plus a `requestLayout` closure copied from the expandable bio/link rows. A tap therefore ran a full immediate `containerLayoutUpdated` pass (the visibly "shifting" screen the user reported as "the row changes"), and the standard value window (the copy-value context menu) was reachable only via long-press. | Tap now opens the same `genericCopy` context menu as long-press; the meaningless `requestLayout` argument was dropped and `PeerInfoScreenLabeledValueItem.requestLayout` gained a no-op default so non-expanding rows no longer fake one. Rows are now real accessibility buttons (activate = open value menu). |
| V-7 | P2 | **Stale keyboard return key after toggling "Send with return key"** — `ChatTextInputPanelNode` seeded `returnKeyType` only when the input node was created, so a mid-session toggle left a "return" key that actually sends (or a "send" key that inserts a newline) until the chat was closed and reopened. Same class as V-2 (creation-time read of a live setting). | The key type is re-asserted whenever editing begins (`chatInputTextNodeDidBeginEditing`), using the fresh `immediateForkExtrasSettings` snapshot. |

Also audited clean in this pass (no change needed): the WebProxy manager's lock
discipline on every remaining `queue.sync` path (`sendKeepalivePing`,
`shouldSkipCarrierRebuildDueToRecentActivity` — snapshot-then-sync everywhere);
the SOCKS5 parser's bounds checks before every index (loopback is reachable by
other processes on device); `ForkExtrasHotFlags`/`ForkGhostModeSettings`
atomicity and the hot-flag ↔ settings default parity (`saveToCloudMenu`,
`selectFromAuthor`, `hideAds`, `useRecentEmojiInReactions` all match
`ForkExtrasSettings.defaultSettings`); streamer-mode gates on phone/username
rows in profiles (consistent with `forkHidesOwnIdentity`, hot flag included);
Ghost Read-on-Interact's generation counter (repeated sends extend the window
correctly, no stuck override); `rememberLastFolder`'s drag lifecycle (the
container clears `isSwitchingCurrentItemFilterByDragging` *before* the final
`currentItemFilterUpdated` callback, so swipe-switched folders persist). The
`shouldDivertMessagesToScheduled` stub (always `.single(false)`) is dead but
harmless — ghost scheduling is applied via message attributes; noted here rather
than churned.

Device verification for this pass: toggle each of the V-2 flags while the chat list and an open
chat are visible — every visible row/bubble should restyle in place with no restart; watch that
typing-indicator ticks no longer visibly churn the list (V-3).

## 5. Device verification checklist (first build)

1. Proxy add/edit: WEB mode shows the updated calls note; SOCKS5/MTProxy modes show none;
   paste-from-clipboard row still first when a proxy URL is on the clipboard.
2. WEB catalog sheet shows the "Каталог WEB-прокси"/"WEB Proxy catalog" title and entries.
3. With WEB active: "Use for calls" visible with the bridge help; toggling it off/on keeps
   working after app restart; settings search finds "Use for calls" and "WEB".
4. App language set to Ukrainian with WEB proxy and Extras open: no mixed RU/EN fork strings
   (all fork text RU, as the fork rule dictates).
5. Saved-messages: context menu "Удалённые"/"View Deleted" matches the opened screen's title
   and the Clear button label in both languages.
6. Data & Storage row and the Settings→(peer)→… proxy row show the same value for every proxy
   state (SOCKS5 / MTProxy / WEB / Auto / None).
