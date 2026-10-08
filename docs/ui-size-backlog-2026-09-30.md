# Отложенные замечания по размерам UI — 30 сентября 2026

База: `6f7c9e2580ce12a9df03e35e9b252c465385d468`.

Сохранено по просьбе пользователя. Исправления не выполнялись. Статическое сканирование 5712 файлов: 189 кандидатов, не 189 доказанных ошибок. Полный реестр: `../../outputs/ui-size-audit/candidates.json` относительно репозитория. Проверка на устройстве не выполнена.

Рекомендация для области нажатия: 44×44 pt. Размер изображения не равен области нажатия.

## SIZE-01: Paste login code

`submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift:852`

Button height 24pt, no hitTestSlop in component; repeated at line 867.

Статус: подтверждено расчётами исходников; нужно исправить и проверить попадание касания с учётом родителя.

## SIZE-02: Limited contacts permission action

`submodules/ContactListUI/Sources/LimitedPermissionItem.swift:228`

Button height 28pt, no hitTestSlop in component.

Статус: подтверждено расчётами исходников; нужно исправить и проверить попадание касания с учётом родителя.

## SIZE-03: Join group call

`submodules/CallListUI/Sources/CallListGroupCallItem.swift:340`

Button height 28pt + 6pt top + 6pt bottom = 40pt target height before ancestor clipping.

Статус: подтверждено расчётами исходников; нужно исправить и проверить попадание касания с учётом родителя.

## SIZE-04: Playback speed

`submodules/TelegramUI/Sources/OverlayAudioPlayerControlsNode.swift:879`

Frame 24x44pt; slop left/right 4pt and top/bottom 8pt gives 32x60pt before ancestor clipping.

Статус: подтверждено расчётами исходников; нужно исправить и проверить попадание касания с учётом родителя.

## SIZE-05: Cancel voice recording

`submodules/TelegramUI/Components/Chat/ChatTextInputAudioRecordingCancelIndicator/Sources/ChatTextInputAudioRecordingCancelIndicator.swift:129`

17pt title measured to content; custom hitTest extends only 5pt per edge, leaving ordinary single-line text target below 44pt high.

Статус: подтверждено расчётами исходников; нужно исправить и проверить попадание касания с учётом родителя.

## SIZE-06: Section header action

`submodules/ItemListUI/Sources/Items/ItemListSectionHeaderItem.swift:273`

Target equals measured header text + 4pt hit slop per edge; default header font 13pt gives less than 44pt height. Row height also follows text + 13pt.

Статус: подтверждено расчётами исходников; нужно исправить и проверить попадание касания с учётом родителя.

## Осталось проверить

Другие кандидаты, перекрытия областей нажатия, русский/английский и RTL, максимальный шрифт, горизонтальная ориентация, iPad Split View, клавиатура и safe area. Исходный файл docs/audit-2026-09-27.md не изменялся.


## Исправления в работе

30 сентября: внесены исправления описанных пунктов. Для размеров локально прошли 6 проверок. Для хранилища добавлены Swift-тесты отказа копирования/записи, round-trip и повторного чтения; для архива — повторный запрос. Полная macOS/iOS проверка и визуальная проверка на устройстве ещё не завершены. Старое описание выше сохраняется как исходное состояние аудита.

Проверка исправлений: Client regression tests 36689222097 успешно прошли на macOS для 3a1d560498. Полная iOS-сборка 36689222256 ещё выполняется; проверки на устройстве не проводились.
