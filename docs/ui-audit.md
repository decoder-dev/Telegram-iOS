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

## 4. Device verification checklist (first build)

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
