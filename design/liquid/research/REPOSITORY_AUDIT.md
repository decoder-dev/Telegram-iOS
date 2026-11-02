# Аудит исходной точки

Форк: `decoder-dev/Telegram-iOS`. Исходный SHA: `6f8d479c19ec5448722f440662f3a57550fae78d`.

`versions.json`: приложение 13.1.2, Xcode 26.6, deploy Xcode 26.2, macOS 26, Bazel 9.2.0. Эти значения не являются инвентарём установленных инструментов. Хост — Linux; `xcodebuild` и `xcrun` отсутствуют.

Checkout содержит UIKit, Texture/AsyncDisplayKit, ComponentFlow, TelegramEngine и Postbox. `Telegram/` содержит приложение и extensions; UI находится преимущественно в `submodules/`. Обёртка сборки — `build-system/Make/Make.py`. README и правила репозитория прочитаны в части сборки, внешнего вида и структуры.

Все вложенные Git submodules на момент аудита не инициализированы (`git submodule status` показывает `-`). Код в обычных каталогах `submodules/` доступен, но это не полный рекурсивный checkout для сборки. Инициализация и нативная baseline-сборка остаются отдельным gate перед реализацией.

## Подтверждённые точки кода

- Список чатов: `ChatListControllerImpl`, `submodules/ChatListUI/Sources/ChatListController.swift`.
- Чат: `ChatControllerImpl`, `submodules/TelegramUI/Sources/ChatController.swift` и расширения в `Sources/Chat/`.
- Профиль и собственные настройки: `PeerInfoScreenImpl`, `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift`.
- Extras: `forkExtrasController`, `ForkExtrasControllerFocus`; параметры сохраняются через `ForkExtrasSettings`.
- Архив: `archiveSettingsController`, `ArchiveLockHelpers.swift`, `ArchivePasswordKeychain.swift`.
- Скрытые аккаунты: `HiddenAccountsSession.swift`; в комментариях и состоянии явно различаются владелец, раскрытие и разблокировка на текущий foreground.
- Прокси: `proxySettingsController`, `proxyServerSettingsController`; VLESS содержит отдельный runtime `TelegramVLESS`. WEB carrier описан в `CLAUDE.md`.

Подробные ссылки со строками создаёт `tools/audit.py` из зафиксированного commit. `DECLARATION_FOUND` означает только проверенную декларацию. Runtime, доступность, навигация и безопасность ещё не проверены.

## Проверки

108 пар SVG/PNG проверены на XML, наличие и размеры. Результат — `qa/import-audit.json`. Проверка не оценивает внешний вид. В исходной карте найдено пять целей меньше 44 pt; это дефекты прототипа, а не доказанные дефекты приложения.

Нативная сборка и iOS smoke: BLOCKED. Причины: Linux, отсутствие Xcode/Simulator, неполные Git submodules. Снимки и видео приложения не получены. Доказательств полного функционального или security-аудита пока нет.
