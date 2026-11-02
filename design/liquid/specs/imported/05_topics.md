# 05_topics — Сообщество · Темы

**Раздел:** `CONVERSATION`\
**Дизайн:** 393 × 852 pt, Light/Dark, SVG editable, PNG 3×\
**Native status:** NOT IMPLEMENTED IN THIS PACKAGE\
**Code location:** not verified; see candidate search patterns below.

## Какие файлы открыть

- `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/05_topics.svg`
- `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/dark/05_topics.svg`
- `01_VISUAL_SOURCE/PNG_3X/light/05_topics.png`
- `01_VISUAL_SOURCE/PNG_3X/dark/05_topics.png`
- `01_VISUAL_SOURCE/METADATA/hotspots/05_topics.json`

## Где искать код (ПРЕДПОЛОЖЕНИЯ до сверки)

- `submodules/TelegramUI/Sources/ChatController*.swift`
- `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`
- `submodules/TelegramUI/Components/Chat/**`

Поиск на самом клоне: `rg -n 'ChatController|SettingsController|PeerInfo|Archive|VLESS|MediaPicker' submodules Telegram`.
Путь/класс/точку входа, оказавшиеся правильными, записать в `reports/REAL_SOURCE_MAP.csv`. Если нет файла — не делать фиктивную заглушку.

## Какое поведение нельзя потерять

Сохраняются отправка, редактирование, пересылка, ответы, сохранённые, статусы, вложения, админские действия, реакция, rich-text, жесты и voice/video.

## Связанные действия из прототипа

- `Назад` → `02_chats`
- `UI / UX` → `17_group_chat`
- `Анимации` → `17_group_chat`
- `Разработка` → `17_group_chat`
- `Референсы` → `17_group_chat`
- `Чаты` → `02_chats`
- `Звонки` → `23_call_history`
- `Контакты` → `36_new_message`
- `Настройки` → `24_settings`

## Демо-действия (не настоящие API)

- Нет специальных demo-only действий.

## Пошаговая реализация

1. Открыть оба макета и сопоставить с реальным существующим экраном в репозитории.
2. Определить data model, анимации, input/output, локализацию, настройки и accessibility hooks.
3. Выделить переиспользуемые элементы; выбрать платформенный native контрол вместо копирования картинки.
4. Реализовать геометрию и цвет для Light/Dark с поддержкой Dynamic Type и Reduce Transparency.
5. Подключить все действия к действующим обработчикам Telegram; проверять отсутствие потери функциональности.
6. Открыть длинное имя/текст, пустые данные, отсутствие сети, ограничения доступа и ошибку.
7. Снять скриншоты до/после на 393×852pt либо аналогичной целевой конфигурации, сравнить с PNG, исправить недочёты.
8. Запустить реальную нативную QA и записать состояние `PASS/FAIL/BLOCKED` с доказательствами.
9. Сохранить маленький git commit и инструкцию отката; перейти к следующему экрану только после gate.

## Критерии приёмки

- Визуальная иерархия, безопасные зоны и типографика соответствуют v3 в обеих темах.
- Все реальные действия на экране функционируют и соответствуют Telegram, а не HTML-схеме.
- Нет выхода текста за границы, отсутствующих символов/иконок, резких скачков или скрытой информации.
- Пользовательские данные, безопасность и функциональность не изменены визуальной правкой.
- Подтверждены результаты тестов и указана точная версия исходного кода.
