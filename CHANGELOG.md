# Changelog

Все notable-изменения этого форка. Формат loosely [Keep a Changelog](https://keepachangelog.com/).
Тег релиза = `v{app}-{tagSuffix}` (например `v12.9.2-3845`); CI кладёт секцию тега в GitHub Release notes.
Теги `*-pre` публикуются как GitHub **pre-release** (не Latest).

## [Unreleased]

## [v12.9.2-3900] — 2026-08-21

Release: same as 3899 + SettingsUI build fix (`appIcons` `let`).

## [v12.9.2-3899] — 2026-08-21

Release: **Телеграм** — premium icons, photo-send stability, crash fixes.

### Changed
- **Display name:** home screen → **Телеграм**.
- **App icons:** full custom premium gallery (**20** icons) — Blue/Classic/Filled/Black/White/New1–2 plus Premium Gold, Turbo, Black, Night, Rose, Emerald, Sunset, Ice, Carbon, Royal, Aurora. All unlocked in Appearance.

### Fixed
- **Photo send jetsam/OOM:** encode no longer loads `PHImageManagerMaximumSize`; Max≤1920; thermal shed to 1280; workers 3→2; `proactiveSaveMedia` off by default (+ migration).
- **Camera photo strip:** `Invalid batch updates` crash — reload when model/view counts diverge.
- **HLS player:** optional chaining on remaining `hlsPlayer_instances` JS call sites (seek/load/rate/level).
- **Modal present:** `presentWithContext:` ignores nil generator (avatar menu after dealloc).

## [v12.9.2-3898-pre] — 2026-08-21

Pre-release: full premium Телеграм icon gallery (20 icons).

### Changed
- **App icons:** every alternate icon restyled as premium (gradient disc + metal ring); primary Icon Composer adds a light ring.
- **Premium gallery:** +8 variants — Night, Rose, Emerald, Sunset, Ice, Carbon, Royal, Aurora (11 Premium* total).
- **Appearance:** all 20 icons listed with `isPremium`; no longer hidden when server Premium is disabled.

## [v12.9.2-3897-pre] — 2026-08-21

Pre-release: Russian **Телеграм** rebrand + full custom icon set (incl. Premium).

### Changed
- **Display name:** home screen / share → `Телеграм` (BUILD, xcconfigs, ar/ko overrides).
- **App icons:** all alternate + default + Icon Composer assets replaced with a custom paper-plane family (Blue / Classic / Filled / Black / White / New1–2).
- **Premium icons:** custom Gold, Turbo (pink→violet + gold plane), Premium Black (gold plane + ring); unlocked in Appearance for everyone (WhiteFilled no longer internal-only).

## [v12.9.2-3896-pre] — 2026-08-21

Pre-release: fix photo-send jetsam / heat.

### Fixed
- **Photo send OOM:** outgoing library encode no longer requests `PHImageManagerMaximumSize` (full-sensor RGBA, often 40–100+ MB) before downscale — asks Photos for the encode target size instead; worker pool 3→2; Max quality capped at 1920; thermal/LPM sheds to 1280.
- **Heat (Message Saving):** `proactiveSaveMedia` defaults off; one-shot migration turns it off for existing installs that inherited the old default-on.
- **Crash hardening:** remove force-unwrap on Lanczos filter and `image.cgImage` in outgoing media thumbnail prep.

## [v12.9.2-3895-pre] — 2026-08-21

Pre-release: brutal ZalupaGram icon.

### Changed
- **App icon:** heavier slab **Z**, near-black disc, blood-red cut slash (Icon Composer Mark + Slash layers; PNG sets refreshed).

## [v12.9.2-3894-pre] — 2026-08-21

Pre-release: rebrand to **ZalupaGram** + new app icon.

### Changed
- **Display name:** home-screen / share extension name is `ZalupaGram` (`CFBundleDisplayName` / `CFBundleName`, App Store + Fork xcconfigs, ar/ko InfoPlist overrides).
- **App icon:** paper-plane mark replaced with a bold white **Z** monogram on a magenta→violet circle (`Telegram.icon` Mark.svg + BlueIcon / DefaultAppIcon PNG sets).

## [v12.9.2-3893-pre] — 2026-08-21

Pre-release: HLS seek crash fix; Save Archive for critical logs.

### Fixed
- **HLS player:** seek-after-teardown JS exception (`playerNotifySeekedOnNextStatusUpdate` on destroyed instance) — optional chaining on the deferred `onSeeked` callback.

### Added
- **Debug → Send Critical Logs:** «Save Archive (Zip)» / «Сохранить архив (Zip)» — zip + system share sheet.

## [v12.9.2-3892-pre] — 2026-08-21

Pre-release: Russian Developer Mode / Debug menus; fix Message Saving localisation build break.

### Fixed
- **Build:** `MessageSavingHistoryController` localisation after `ForkPresentationLanguage` (was referencing missing `translations`).
- **Debug / Developer Mode:** all menu titles and action sheets follow app language (RU/EN) via `DebugLocalizedString`.

## [v12.9.2-3891-pre] — 2026-08-21

Pre-release: performance/folder/Ghost Mode follow-ups; commit history authored as decoder-dev (Claude trailers stripped).

### Fixed
- **Chat open:** drop the 250ms blocked-peers debounce on revision 0 so first history paint is not delayed.
- **Folders:** animated switch path; avoid stacked lists on tab tap; undo leftover pagination/scroll sync from earlier duplication attempts.
- **Regex filters:** long messages no longer silently disable every `<type>` filter.
- **Ghost Mode:** no longer mutes you in voice chats; archive Face ID unlock clears cooldown.
- **i18n:** fork strings follow app language, not device language.
- **Stability:** CDN key length + snapshot-gated state; dual-camera round-video races; playlist lazy vars across queues; launch breadcrumbs for crash diagnosis.

### Added
- **Developer Mode** Settings row and screen.

## [v12.9.2-3890-pre] — 2026-08-20

Pre-release: close remaining idealism regressions (composer morph/assets, themes, lists).

### Fixed
- **Build:** `ChatListNode` filter map type leftover after folders staleness drop; unused `strongSelf` after guard drop (`#no-usage` under release).
- **Composer:** `sendOccupiesActionSlot` matches keepSend/slowmode/search; paid-stars width reserved early; tooltip respects mic `isHidden`; scheduled send uses icon (not filled disc) on blue well; mic↔send morph scale+alpha both `0.18 easeInOut`; slot hit-gating; pointer circles 40pt; send/apply/schedule icons + stretchable disc on 40pt canvas.
- **Night/Day base themes:** outgoing secondary `white@0.8` on default path; Night chrome separators `@0.8`; outgoing media well `.clear`; Night waveform inactive `@0.65`.
- **Calls:** avatar 44 pt; **Contacts:** thread rows keep shared left column.
- **Media bubbles:** rename `.emptyWallpaper` → `.whenNoHeader` (header-only rule unchanged).

## [v12.9.2-3889-pre] — 2026-08-20

Pre-release: composer measure/wrap fix, full-bleed separators, media bubble rule, password fields.

### Fixed
- **Composer:** высота поля считается с тем же right inset, что и layout (текст и рост панели снова вместе); `updateTextHeight` / `updateLayout` — одна формула ширины; business-link не резервирует пустой attach-слот.
- **Folders:** selection pill index bound к `selectionFrames`.
- **Lists:** separators в chat/Calls/Contacts до правого края.
- **Night:** cloud-password / free input fields снова `#1C1C1E` (не чёрное на чёрном); placeholder `#636366`.

### Changed
- **Media bubbles:** рамка вокруг фото не зависит от wallpaper — только если нужен header (reply/author); иначе floating date.

## [v12.9.2-3888-pre] — 2026-08-20

Pre-release: Messages composer + follow-up polish (Calls column, contrast, icons).

### Fixed
- **Composer:** send снаружи капсулы (`maxX + 6`); same-slot mic↔send morph; слот через `mediaActionButtonsSlotFrame`; z-order только при инверсии; `isHidden` mic двусторонний; правый слот резервируется всегда (в т.ч. story reply / `.empty`).
- **Calls:** одна колонка аватаров — общий слот 22pt.
- **Icons:** `Call/Star` в rating HUD; video/slo-mo/timelapse badges через SF Symbols.

### Changed
- **Composer (Messages):** Plus слева вместо скрепки; Telegram long-press / video note / bots / slowmode / paid send сохранены.
- **Outgoing on #007AFF:** secondary `white@0.8`; waveform inactive отдельно; Night hairlines `@0.8`; placeholder Night `#636366`.

## [v12.9.2-3887-pre] — 2026-08-20

Pre-release: idealism — no overlaps, one accent, composer 40pt.

### Fixed
- **Calls:** исходящая иконка и voice-chat индикатор больше не залезают под 52pt аватар (резерв слота в `leftInset`).
- **Contacts:** иконка треда центрируется на `avatarFrame` (убран magic `-43`).
- **Composer:** капсула `2/2` → 40pt вровень с кругами attach/mic; `minimalHeight` из тех же insets.

### Changed
- **Day accent / folder pill:** `#3478F6` → `#007AFF` (один системный синий с bubble).
- **Night:** входящие ссылки/акценты и chat-list checkmarks `#007AFF`; elevated `#313131` → `#2C2C2E`.
- **Night palette cleanup (P0–P3):** surfaces `#000` / `#1C1C1E` / `#2C2C2E`; accent и bubble один `#007AFF`; secondary gray `#8E8E93`; destructive `#FF3B30`. Убраны legacy `#0F0F0F` / `#141414` / `#1C1C1D` / `#1F1F1F` / `#3478F6` / `#EB5545`.

## [v12.9.2-3881-pre] — 2026-08-19

Pre-release: fix chat folder switch duplication (regression).

### Fixed
- Переключение папок (Personal → All Chats и др.): дублирование чатов и «ломанный» экран.
- Регрессия `e2ed9433a3`: соседние preloaded-вкладки снова пагинировали в фоне (`isActiveForFolderPagination` default true).
- Apply-time guard по `locationGeneration` — stale transitions отбрасываются при apply.
- `deactivateFolderPagination()` сбрасывает `.navigation` при уходе с вкладки.
- Tab tap (`animated: false`) больше не форсит spring-slide.

## [v12.9.2-3878-pre] — 2026-08-19

Pre-release: brighter chat list search placeholder.

### Fixed
- «Поиск» в списке чатов (тёмная тема): placeholder и лупа ярче — 62% белого, как в композере.

## [v12.9.2-3877-pre] — 2026-08-19

Pre-release: OLED profile card layout (Contacts-style).

### Changed
- **Профиль (OLED):** кнопки действий (звонок / mute / search / more) вынесены из шапки в первую карточку `#1C1C1E` — 48×48 pt круги `#2C2C2E`.
- Шапка: только avatar + имя + статус на чёрном фоне.
- Info-карточка: подписи полей ярче (`#AEAEB2`, iOS tertiary label).
- Табы + контент (медиа, подарки…) в одной карточке `#1C1C1E` с inset как у Settings.
- id / dc / registered — одна строка footer мелким текстом вместо отдельных rows.

## [v12.9.2-3876-pre] — 2026-08-19

Pre-release: composer accessory row alignment + brighter placeholder.

### Fixed
- Timer / emoji / sticker кнопки в поле ввода: 40×40 pt, выровнены по нижнему ряду вместе с микрофоном и скрепкой (раньше 32 pt и «плавали» при многострочном тексте).
- Placeholder «Сообщение» в тёмной теме ярче (62% белого вместо 48%).

## [v12.9.2-3875-pre] — 2026-08-19

Pre-release: OLED-профиль (iOS Contacts), экран «Кастомизация». Sideload smoke, не Latest.

### Changed
- **Профиль (тёмная тема):** чёрная шапка вместо фиолетового градиента, круглые кнопки действий по центру, карточки `#1C1C1E`, тёмные pill-табы. Star-gift профили и все функции (mute, search, more…) сохранены. Светлая тема — штатный Telegram-профиль.
- **«Кастомизация»** вместо «Оформление»: убраны сетка тем, «Темы чатов», авто-ночной режим и «Ночная тема». Остались превью, обои, персональные цвета, размер текста, углы пузырей, иконка приложения.

### Fixed
- Дублирование чатов при переключении Personal → All Chats (фоновая пагинация неактивных вкладок).
- Иконка исходящего звонка больше не наезжает на аватар в списке звонков.
- Поиск и OLED-фоны: чистый `#000000` вместо серого `#272728`.
- Composer: круглые кнопки выровнены по нижнему краю поля ввода.

## [v12.9.2-3874-pre] — 2026-08-19

Pre-release: OLED UI fixes + folder duplication fix (без профиля/кастомизации). Superseded by `3875-pre`.

### Changed
- **Пункт «Оформление» убран из настроек.** Тема, цвет пузыря и радиус скругления теперь заданы форком, выбирать было нечего. Приложение следует системному светлому/тёмному: светло — Day, темно — Night. Сохранённые настройки на диске не трогаются — переписывается только копия, которую читает пайплайн, так что ничего не теряется. Экран остался доступен из поиска по настройкам, по `tg://settings/theme` и из пункта смены иконки.
- **Исходящий пузырь прибит к iOS-синему `#007AFF`** в Day и Night. Фиолетовые пузыри брались из самой темы Night: акцент `0x3e88f7` (дефолтный) разворачивался в градиент `0x0771ff → 0x9047ff → 0xa256bf`, а мой `#007AFF` лежал в дефолте темы, который читается только когда акцент не сохранён. Цена: половина выбора акцента, отвечающая за цвет пузыря, на этих двух темах теперь неактивна — акцент по-прежнему красит кнопки, ссылки и галочки. Подарочные и чат-темы приходят с `editing: false` и сохраняют цвета отправителя.
- **Кнопки микрофона и отправки снова круглые.** Им отдавалась высота поля ввода (52 pt при ширине 40), а фон рисуется прямоугольником этого размера со скруглением в половину высоты — получались овалы рядом с круглой скрепкой. Теперь 40×40, по нижнему краю поля, как скрепка. У кнопки отправки была та же болезнь с другой стороны: её фон получался вставкой 3 pt по обеим осям в коробку 46×высота, то есть квадрат выходил только при высоте ровно на 6 pt больше ширины. Вертикальная вставка теперь считается, а не задана константой.
- **Иконка приложения — отдельный пункт настроек.** Она жила внутри «Оформления» и уехала вместе с ним; это был побочный эффект, а не задача.
- **Оформление:** в списке тем остались только белая (Day) и чёрная (Night) — как в Messages. Classic (сине-зелёные обои) и Tinted Night (синий) убраны и из авто-ночной темы тоже. Если тема уже выбрана, она остаётся доступной, пока не переключишься; облачные темы не тронуты.
- **Авто-MTProxy под белыми списками:** парсер больше не выбрасывает прокси с IP вместо домена (в RU-списке это было 61 из 100), читает формат `host:port:secret`, а не только ссылки `tg://proxy`, и ставит FakeTLS-прокси (`ee`-секрет, подставляют SNI реального домена) первыми — и в очередь проверки, и в выбор до первого ответа. Пул 40 хранимых, 20 проверяемых, добавлен RU-список Chumbayoumba.
- **Поиск, Контакты, Звонки:** строки с 68 pt до 56 pt — аватар 44 pt вместо 52 pt списка чатов. В Messages эти строки ниже, чем строки чатов; текст остался на 72 pt, то есть в 2 pt от списка чатов.
- **Навбар чата снова стеклянный.** Была «‹ Назад» текстом поверх обоев рядом со стеклянной капсулой заголовка — одна панель в двух стилях. Теперь шеврон в своей капсуле и без подписи, как в Messages; обои по-прежнему идут под панель (в glass-режиме у неё нет своей заливки).

### Fixed
- Автопрокси больше не тасует сервера на шумном канале. Правило «любой кандидат быстрее на 50 мс побеждает» на VPN/мобильном канале попадает в разброс, поэтому пул перестраивался почти каждый круг проверки, а каждая перестановка рвёт и поднимает заново все соединения MTProto — отсюда «с VPN всё грузится долго». Теперь добровольное переключение требует +30% скорости и не чаще раза в минуту; отказавший сервер идёт через `excludedActiveServer` мимо обоих ограничений, так что реальный failover не изменился.
- Табличный индекс вкладок: три места брали `controllers[selectedIndex]` без верхней границы (два — вообще без проверок), а список вкладок пересобирается при запуске, при смене аккаунта и при включении вкладки «Звонки». Добавлен `selectedController`, который возвращает nil вместо падения. Это закрытие ловушки, а не подтверждённый диагноз вылетов — краш-лога нет.
- Failover прокси ушёл с главной очереди и перестал переписывать `forceLocalDNS` на каждый тик статуса соединения.
- Панель ввода больше не красится обоями. Поле, скрепка и круглая кнопка отправки брали `.panel`-стекло (белое 70% поверх блюра), из-за чего на зелёных обоях весь composer уходил в зелень. Теперь непрозрачная заливка от темы: `#E9E9EB` днём, `#1C1C1E` ночью.
- Сборка: `3860-pre` не компилировалась — после обнуления inset ветки скругления карточек стали недостижимы, а в проекте `-Werror`. Мёртвый код убран.
- Сборка: `3861-pre` падала следом на `contentBottomInset was never mutated` — удаление `+= 11.0` в HIG-фиксе оставило `var` без единой мутации. Стало `let`, пустая if/else-заглушка убрана.
- Журнал действий администратора: обои идут под навбар, как в чате, вместо стеклянной капсулы поверх них.
- ProxySettings больше не пишет дубль ключа авто-MTProxy, который никто не читал.

## [v12.9.2-3860-pre] — 2026-08-19

Pre-release: HIG layout fix (убрать белые полосы + вернуть классические обои/пузырь цвета). Sideload smoke, не Latest.

### Fixed
- Список чатов снова на всю ширину — убран 16 pt inset карточек (белые полосы по бокам).
- Чат: legacy nav bar над обоями, composer прижат к низу (без 8/11 pt зазоров).
- День/ночь: цвета пузырей с обоями возвращены к классическим Telegram (зелёные исходящие днём, градиент ночью), не iMessage-blue поверх кастомных тем.
- Галочки отправки снова видны на зелёных пузырях — цвет вернулся к `#19c700` (белый на бледно-зелёном давал контраст ~1.2:1).
- Звонки и Контакты тоже на всю ширину: у них оставался 16 pt inset карточек, убранный в списке чатов.

### Security
- **Авто MTProxy больше не включается сам.** Настройка была opt-out (дефолт `true`, в том числе в fallback декодера), поэтому при обновлении трафик уходил через случайный публичный прокси без ведома пользователя. Теперь по умолчанию выключено; у тех, кто включал вручную, ничего не меняется.
- Авто-обновление списка не перебивает вручную выбранный прокси и не включает обратно выключенный.

## [v12.9.2-3859-pre] — 2026-08-19

Pre-release: авто MTProxy — только RU у kort0881 + dubblebyte. Sideload smoke, не Latest.

### Changed
- **Авто MTProxy:** kort0881 берётся только RU-список (`proxy_ru.txt` вместо `proxy_all.txt`); добавлен [dubblebyte/free-mtproto-proxies](https://github.com/dubblebyte/free-mtproto-proxies). SoliSpirit `all_proxies.txt` без изменений. По-прежнему только доменные MTProxy (IP отбрасываются).

## [v12.9.2-3858-pre] — 2026-08-19

Pre-release: extras без обходов + время на HIG-пузырях. Sideload smoke, не Latest.

### Fixed
- **Архив с паролем:** превью из поиска и вкладка Channels больше не светят закрытые чаты; пуш при таймауте NSE не уходит с именем и текстом; Lock Now / фон закрывают и открытый архивный чат; mute на каждый аккаунт; снятие пароля не прячет папку; Archive/Unarchive в меню снова работают.
- Instant passcode только при реальном уходе в фон (Control Center больше не ломает пикеры).
- Hide Tab Bar: на iPhone Настройки остаются в шапке списка чатов; на iPad тумблер скрыт.
- Список чатов сразу перестраивается при hide-blocked / regex; «печатает» у заблокированных не светится.
- Remember last folder — отдельно на аккаунт.
- HIG: у текста/ссылок/rich-markdown снова время и галочки (tailless пузыри). Превью радиуса в настройках совпадает с чатом. Кнопки в контактах не вылезают из карточки. Заголовки списка чатов не залезают под аватар 52 pt.

## [v12.9.2-3857-pre] — 2026-08-19

Pre-release: весь интерфейс на HIG + фикс раскладки карточек. Sideload smoke, не Latest.

### Changed
- **Весь интерфейс** на том же HIG-языке, что и чаты: iOS blue `#3478F6` (таб, бейджи, send, action sheet, чекбоксы), grouped-карточки Settings/Extra (скругление 20 pt, холст чёрный / `#F2F2F7` днём), контакты и звонки — аватар 52 pt и карточки как список чатов.

### Fixed
- Компактный список чатов: аватар 52 pt больше не обрезается в строке 44 pt.
- Свайп удаления в звонках больше не прыгает на старую геометрию; info/дата/Join/чекбоксы остаются в карточке. Групповые звонки в той же карточке.
- Реакции на исходящих пузырях в day-теме — белые на синем, не leftover-зелёные Telegram.
- Release-сборка: убран неиспользуемый `bubbleStrokeColor` (из‑за него падал IPA `3856-pre`).

## [v12.9.2-3856-pre] — 2026-08-19

Pre-release: iOS Messages HIG look на все чаты. Sideload smoke, не Latest.

### Changed
- **Все чаты:** пузыри без «хвостиков», скругление 20 pt; в тёмной теме входящие `#2C2C2E`, исходящие iOS blue `#3478F6` на чёрном фоне (как Messages). Список чатов — карточка `#1C1C1E` на чёрном, аватар 52 pt, выбранная папка синей пилюлей.
- Extra и список чатов ближе к **Apple HIG** (платформенное поведение, не чужой визуал): grouped Extra с иконками Settings, стекла на disclosure, destructive «Заменить» при импорте БД.
- «Скрыть tab bar» на iPad больше не прячет панель вкладок (на iPadOS tab bar — основная навигация).
- Компактный список чатов не сжимает строки ниже 44 pt. Обычные строки чуть выше.

## [v12.9.2-3855-pre] — 2026-08-18

Pre-release: hardening extras crash paths. Sideload smoke, не Latest.

### Fixed
- iPad: Extra → экспорт/импорт БД сохранённых сообщений и шаринг вложений больше не падают из‑за `UIActivityViewController` / document picker без popover.
- Отправка фото (качество 1920/2560): не крашит на `PHImageResultIsDegradedKey` и `TGScaleImageToPixelSize`.
- Удаление / превью стикера при нулевых bounds больше не ловит `UIGraphicsGetCurrentContext()`.
- Двойной тап «править» не открывает редактор для стикеров, опросов и просроченных сообщений.
- Скрытие «Все чаты»: переключение папки не зависает на `.all`, leftover-папка убирается, пункт «Все чаты» в меню скрыт.

## [v12.9.2-3854-pre] — 2026-08-18

Pre-release: фикс белого экрана при запуске. Sideload smoke, не Latest.

### Fixed
- Запуск больше не зависает на белом экране, если чат-лист не успевает стать ready (скрытие «Все чаты» / смена папки / `switchToFilter` без completion). Через 2.5 с UI всё равно показывается.

## [v12.9.2-3853-pre] — 2026-08-18

Pre-release: Extra по разделам + фичи из Swiftgram. Sideload smoke, не Latest.

### Changed
- **Extra** больше не одна простыня. Хаб с кнопками: **Ниндзя** (сохранение удалённых/правок/медиа, фильтры, AyuForward), **Невидимка** (офлайн, прочтения, stories), **Приватность**, **Интерфейс**, **Чат**, **Сеть**.

### Added
- Скрыть вкладку «Все чаты», запоминать последнюю папку, скрыть tab bar.
- Секунды во времени сообщений, широкие посты, размер стикеров.
- Двойной тап по своему сообщению — править; быстрый перевод в меню.
- «В Избранное» и «Выбрать от автора» в контекстном меню.
- Ускорение загрузок (FetchV2) и качество исходящих фото (1280 / 1920 / 2560).

## [v12.9.2-3852-pre] — 2026-08-18

Pre-release: авто-прокси без показа серверов в списке. Sideload smoke, не Latest.

### Changed
- **Авто MTProxy** по умолчанию включён. Подобранные серверы не попадают в «Сохранённые прокси» и не светятся в настройках — в типе соединения просто «Авто». Свои вручную добавленные прокси по-прежнему видны.

## [v12.9.2-3851-pre] — 2026-08-18

Pre-release: фикс повторного включения Авто MTProxy + быстрее выбор прокси. Sideload smoke, не Latest.

### Fixed
- **Авто MTProxy:** выкл → вкл снова сразу поднимает список и активный сервер. Раньше повторная запись того же дампа отбрасывалась, `automaticServers` оставался пустым до перезапуска приложения.

### Changed
- Списки SoliSpirit и kort0881 применяются по мере прихода (не ждём оба URL). Первый живой сервер берётся сразу, RTT добирает более быстрый.
- В экране прокси в списке только свои серверы и текущий авто; пул авто не раздувает UI.

## [v12.9.2-3850-pre] — 2026-08-18

Pre-release: Auto MTProxy + фикс отправки файлов/музыки с устройства. Sideload smoke, не Latest.

### Added
- **Авто MTProxy:** opt-in подтягивание публичных списков MTProxy (SoliSpirit/mtproto и kort0881/telegram-proxy-collector), пробы RTT и переключение на самый быстрый живой сервер. Тогл в Extras и в Настройки → Данные и память → Прокси. Свои вручную добавленные прокси не затираются; выключение снимает только авто-список. Это чужие ноды: чаты они не читают, IP видят.

### Fixed
- **Files / Music picker:** отправка файлов и музыки с устройства (Files / «На iPhone») больше не пропадает молча. `startAccessingSecurityScopedResource() == false` больше не считается отказом в доступе — на iOS это часто значит, что URL уже в sandbox. Пикер вложений переведён на `.import`; при полном провале enqueue показывается ошибка вместо тишины. Также: не падать на `Int(inf)` у битого аудио, не отбрасывать имена с `%`, не оставлять несбалансированный security-scope (из‑за него следующие отправки тоже ломались).

## [v12.9.2-3846] — 2026-08-12

### Changed
- **Ads:** спонсорские / recommended сообщения отключены навсегда в клиенте (не запрашиваются и не вставляются в историю). Тогл в Extras заблокирован во «вкл».

### Also includes (from v12.9.2-3845, if that build was still in flight)
- AyuForward first-tap fix; thermal/LPM skip for proactive Save Media fetch; Liquid Glass / perf docs; per-release CHANGELOG in GitHub Release notes.

## [v12.9.2-3845] — 2026-08-12

### Fixed
- **AyuForward:** форвард noforwards / удалённых / TTL больше не падает молча с первого раза (media reference через `.message`, как у обычного forward).

### Changed
- **Save Media:** при Low Power Mode или thermal `.serious`/`.critical` не стартует opportunistic proactive download. Save Deleted / Edits и copy из кэша без изменений.

### Docs
- `docs/LIQUID_GLASS_AND_PERF.md` — что брать из Liquid Glass iOS 26 и как дальше резать «жратву».
- `docs/DEEDS.md` — опись недавних PR.
- Обновлён `docs/PERFORMANCE_AUDIT.md`.
- `CHANGELOG.md` + inject into CI release notes.

## [v12.9.2-3844] — 2026-08-11

### Fixed
- Fake-TLS SNI: восстановлены 4 нулевых байта в ClientHello DSL (регрессия «empty SNI»).
- Grid camera: снова `photo: true`, чтобы capture не крашился без `AVCapturePhotoOutput`.
- MessageSaving: mkdir Saved Attachments один раз на процесс; flush JSON при background не на main thread.

### Docs
- `docs/PERFORMANCE_AUDIT.md` — network/perf audit.

## [v12.9.2-3843] — 2026-08-11

### Fixed
- Harden MessageSaving import/export; iOS 13 document picker в ForkExtras import.
- Extras list `stableId` order / MessageSaving import-export bugs.

## Earlier

См. git history / предыдущие GitHub Releases (`v12.9.2-3842` и ниже). Новые релизы обязаны добавлять секцию `## [v…]` **перед** тегом.
