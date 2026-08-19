# Changelog

Все notable-изменения этого форка. Формат loosely [Keep a Changelog](https://keepachangelog.com/).
Тег релиза = `v{app}-{tagSuffix}` (например `v12.9.2-3845`); CI кладёт секцию тега в GitHub Release notes.
Теги `*-pre` публикуются как GitHub **pre-release** (не Latest).

## [Unreleased]

### Changed
- **Весь интерфейс** на том же HIG-языке, что и чаты: iOS blue `#3478F6` (таб, бейджи, send, action sheet, чекбоксы), grouped-карточки Settings/Extra (скругление 20 pt, холст чёрный / `#F2F2F7` днём), контакты и звонки — аватар 52 pt и карточки как список чатов.

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
