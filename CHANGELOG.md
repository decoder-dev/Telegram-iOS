# Changelog

Все notable-изменения этого форка. Формат loosely [Keep a Changelog](https://keepachangelog.com/).
Тег релиза = `v{app}-{tagSuffix}` (например `v12.9.2-3845`); CI кладёт секцию тега в GitHub Release notes.

## [Unreleased]

### Changed
- **Ads:** спонсорские / recommended сообщения отключены навсегда в клиенте (не запрашиваются и не вставляются в историю). Тогл в Extras заблокирован во «вкл».

## [v12.9.2-3845] — 2026-08-12

### Fixed
- **AyuForward:** форвард noforwards / удалённых / TTL больше не падает молча с первого раза (media reference через `.message`, как у обычного forward).

### Changed
- **Save Media:** при Low Power Mode или thermal `.serious`/`.critical` не стартует opportunistic proactive download. Save Deleted / Edits и copy из кэша без изменений.

### Docs
- `docs/LIQUID_GLASS_AND_PERF.md` — что брать из Liquid Glass iOS 26 и как дальше резать «жратву».
- `docs/DEEDS.md` — опись недавних PR.
- Обновлён `docs/PERFORMANCE_AUDIT.md`.

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
