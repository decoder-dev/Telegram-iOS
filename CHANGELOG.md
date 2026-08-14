# Changelog

Все notable-изменения этого форка. Формат loosely [Keep a Changelog](https://keepachangelog.com/).
Тег релиза = `v{app}-{tagSuffix}` (например `v12.9.2-3845`); CI кладёт секцию тега в GitHub Release notes.
Теги `*-pre` публикуются как GitHub **pre-release** (не Latest).

## [v12.9.2-3848-pre] — 2026-08-14

Pre-release: photo editor stability + fix отправки документов с устройства. Sideload smoke, не Latest.

### Fixed
- **Files picker:** Attach → File → документ с «На iPhone» / Files больше не пропадает молча — `startAccessingSecurityScopedResource() == false` не считается отказом (sandbox URL после `.import`); picker в режиме `.import`; алерт если файл так и не собрался.
- *(includes v12.9.2-3847-pre)* photo editor / camera crashes, async texture load, draft decode, cutout bounds.

## [v12.9.2-3847-pre] — 2026-08-14

Pre-release: стабильность редактора фото / камеры. Для sideload-проверки на устройстве, не Latest.

### Fixed
- **Photo editor:** краш при открытии картинки с `UIImage.scale != 1` (скриншоты и часть фото из галереи) — буфер `loadTexture` считался в points, текстура Metal в пикселях.
- **Camera:** `takePhoto` больше не зовёт `capturePhoto` если photo output не в running-сессии (иначе `NSInvalidArgumentException`).
- **Send / cover / sticker:** композиция 1080p ушла с main thread (watchdog на «просто закрылось»).
- **Drafts:** битый story draft больше не `fatalError`, а decode error (текст, геостикер, неизвестный tool key).
- **Cutout:** Core ML на iOS 16 не на caller thread; lookup маски с bounds-check.

### Changed
- Загрузка full-res текстуры и гистограмма прозрачности — с очереди `UniversalTextureSource` (первый кадр превью может мигнуть пустым).
- Send still-photo читает кэш кадра после GPU, а не делает readback на main. Видеоэкспорт кэш не трогает.
- JPEG коллажа пишется в фоне; playback подключается, когда файлы уже на диске.
- Снимок с камеры перед `createCGImage` режется до 2560 по длинной стороне (не полный 12 Мп буфер).

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
