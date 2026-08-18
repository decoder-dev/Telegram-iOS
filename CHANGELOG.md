# Changelog

Все notable-изменения этого форка. Формат loosely [Keep a Changelog](https://keepachangelog.com/).
Тег релиза = `v{app}-{tagSuffix}` (например `v12.9.2-3845`); CI кладёт секцию тега в GitHub Release notes.
Теги `*-pre` публикуются как GitHub **pre-release** (не Latest).

## [v12.9.2-3850-pre] — 2026-08-18

Pre-release: Auto MTProxy + фикс отправки файлов/музыки с устройства. Sideload smoke, не Latest.

### Added
- **Авто MTProxy:** opt-in подтягивание публичного списка MTProxy, пробы RTT и переключение на самый быстрый живой сервер. Тогл в Extras и в Настройки → Данные и память → Прокси. Свои вручную добавленные прокси не затираются; выключение снимает только авто-список. Это чужие ноды: чаты они не читают, IP видят.

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
