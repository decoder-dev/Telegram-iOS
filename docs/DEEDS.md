# Опись деяний (Claude)

Кратко: что сделано в последних PR, что трогали, что **намеренно не ломали**.

## Готово к review / merge

### [#28](https://github.com/decoder-dev/Telegram-iOS/pull/28) — AyuForward «со второго раза»

- **Баг:** первый Forward noforwards/deleted/TTL часто `.Failed`, второй проходил.
- **Почему:** `.standalone` media reference не умеет самочиниться при `FILE_REFERENCE_EXPIRED`.
- **Фикс:** как у обычного forward — `.message(MessageReference(sourceMessage), …)`.
- **Не ломаем:** обычный forward; путь через Saved Attachments; уже закэшированное медиа.

### [#29](https://github.com/decoder-dev/Telegram-iOS/pull/29) — Liquid Glass + план «не жрать»

- Только docs (`LIQUID_GLASS_AND_PERF.md` + pointer в `PERFORMANCE_AUDIT.md`).
- Рантайм не менялся.
- Glass: добивать fork chrome/чипы, **не** пузыри и не каждую строку чата.
- Heat: следующий рычаг — гасить только *proactive* Save Media при thermal/LPM.

### Этот PR — thermal/LPM gate на proactive fetch

- В `MessageSavingBridge.preserveMediaIfNeeded` не стартуем `startFetch`, если Low Power Mode или thermal `.serious`/`.critical`.
- **Сохраняются:** Save Deleted / Save Edits, `saveMedia` copy при удалении, retry `copyIfAvailable` если файл уже в кэше, ручной toggle Proactive Save Media.
- **Меняется только:** оппортунистический сетевой download «на всякий случай», когда телефону и так тяжело.

## Уже в master раньше (напоминание)

Структурный перф MessageSaving, Fake-TLS SNI, grid camera photo output, flush off main — см. `PERFORMANCE_AUDIT.md`.

## Намеренно отложено (чтобы не ломать)

- Extras-toggle `enableVoipTcp` — требует аккуратной вставки в `ForkExtrasEntry.stableId` (раньше ломали порядок списка). Пока флаг живёт в ExperimentalUISettings (default `false`).
- Downscale видеозвонка при heat — только после signposts.
- Glass chrome pass на fork ItemList — отдельным мелким PR, без смены логики.
