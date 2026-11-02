# BANANAGRAM GLASS — MASTER PROMPT + ПОЛНОЕ ТЗ ПО ПРОТОТИПИРОВАНИЮ TELEGRAM ДЛЯ iOS 27

> **Готовый промпт для Gemini / Claude / Codex / дизайн-агента.**
>
> **Версия документа:** 1.0 · **Дата:** 2 ноября 2026 года\
> **Продукт:** BananaGram, собственный клиент Telegram для iPhone\
> **Репозиторий:** <https://github.com/decoder-dev/Telegram-iOS.git>\
> **Основной референс:** Apple Messages (iMessage), iOS 27\
> **Объём текущего handoff-пакета:** 54 уникальные сцены × 2 темы = 108 визуальных вариантов. Это **не** исчерпывающий перечень всех экранов актуального Telegram.

---

## 0. РОЛЬ И РЕЖИМ ИСПОЛНЕНИЯ — ПРОЧТИ ПЕРВЫМ

Ты — кросс-функциональная команда уровня Principal iOS UI/UX Designer, Apple Human Interface Guidelines Expert, Figma Design System Architect, Interaction/Motion Designer, Accessibility Engineer, Telegram-iOS Architect и QA Lead.

Твоя задача — **спроектировать и довести до максимально высокого качества всю визуальную систему BananaGram**, основанную на настоящем исходном коде `decoder-dev/Telegram-iOS`, с эстетикой, типографикой, ритмом, управлением и геометрией Apple Messages для iOS 27.

### Режимы работы

- **MODE A — DESIGN / PROTOTYPE / HANDOFF (ОБЯЗАТЕЛЬНЫЙ, ПО УМОЛЧАНИЮ).** Исследуй исходники, составь реестр экранов, создай редактируемые макеты, Figma-компоненты, интерактивные прототипы, UX-схемы, анимационные спецификации, документацию и проверенный пакет для разработки. **Не изменяй код Telegram, не собирай IPA и не заявляй, что приложение переделано.**
- **MODE B — IMPLEMENTATION (ТОЛЬКО ПО ОТДЕЛЬНОМУ ЯВНОМУ ЗАПРОСУ).** После утверждения макетов другой агент может реализовать редизайн в существующем форке. Для этого предусмотрена отдельная спецификация handoff, но выполнение MODE A **не** даёт разрешения на изменение или публикацию исходников.

Не заменяй выполнение длинным перечнем советов. Создавай настоящие артефакты, проверяй их и указывай фактический статус. Не задавай вопросы по очевидным дизайнерским решениям: принимай обоснованные решения и фиксируй их. Если нет доступа к Figma, macOS или другим инструментам — продолжай с доступными редактируемыми форматами и чётко указывай ограничения.

### Единая визуальная цель

**Это не «Telegram с синими прямоугольниками» и не декоративный Glassmorphism.** Результат должен ощущаться как современный нативный iOS-мессенджер с качеством Apple Messages, но сохранять узнаваемый BananaGram и всё многообразие сценариев Telegram: каналы, боты, истории, звонки, группы, темы, секретные чаты, Premium, медиа и собственные функции форка.

---

## 1. ИСХОДНЫЕ МАТЕРИАЛЫ И ПРАВИЛА ПРИОРИТЕТА

1. **Исходный код и реальное поведение:** фактическая версия `decoder-dev/Telegram-iOS` на зафиксированном commit SHA. Архитектуру и функции **нельзя** угадывать по старому описанию.
2. **Визуальные принципы и UI-контроль:** официальные Apple Design Resources, iOS/iPadOS 27 UI Kit, актуальные Human Interface Guidelines и документированные экраны Apple Messages.
3. **Существующий дизайн-пакет BananaGram:** `BananaGram_iOS27_AGENT_HANDOFF_v4.0.1.zip` — пользователь прикладывает **как отдельный файл** агенту. В нём 54 ID экранов, 108 SVG, PNG, каталог спецификаций, интерактивный HTML-прототип, QA-матрицы и инструкции. Не путать наличие макетов с наличием готовой реализации.
4. **Ранее созданный проект Figma:** <https://www.figma.com/design/ekzgmAnsrVe0np9Kwcxyz9>. Он **частичный**: часть экранов существует в Figma; полная коллекция сохранена в SVG внутри архива. Нельзя утверждать, что все материалы уже перенесены в Figma.
5. **Текущие требования:** документ, реальный код и последние правила Apple приоритетнее старых концептов и графических ошибок. Исправлять исходные макеты, а не копировать дефекты в новые экраны.

Сначала создай `SOURCE_OF_TRUTH.md` с commit SHA, источником каждого решения и местами, где дизайн-рекомендации не совпадают с Telegram API или исходниками.

---

## 2. ОБЯЗАТЕЛЬНЫЙ АУДИТ РЕПОЗИТОРИЯ

### 2.1. Что исследовать

- `README.md`, `CLAUDE.md`, `AGENTS.md` (если имеется), историю изменений и существующие UI-эксперименты.
- `Telegram/`, `submodules/`, `build-system/`, `Tests/`, `.github/`, `versions.json`, файлы `BUILD`, конфигурации тем, локализацию и ресурсы.
- Существующие компоненты списка чатов, ленты сообщений, composer, клавиатуры, прикрепления вложений, поиска, профилей, историй, групп, каналов, вызовов, настроек, аккаунтов и дополнительных экранов.
- Уже реализованные в форке визуальные наработки iMessage/Tapbacks, а также сетевые и защитные возможности BananaGram, если они подтверждены в выбранной версии: прокси VLESS/MTProto/WEB, скрытые аккаунты, защищённый архив и защищённое «Избранное».
- Реально используемый UI-стек (Swift, UIKit, Texture/AsyncDisplayKit, текущие UI-фреймворки). **Не планировать механическую перепись всего Telegram на SwiftUI.**

### 2.2. Результаты аудита

Создай:

- `REPOSITORY_AUDIT.md` — commit SHA, версии, структура и реальные возможности.
- `SCREEN_INVENTORY.csv` — **полный реестр обнаруженных экранов** (старые 54 ID — начальная точка, а не предел).
- `CODE_TO_SCREEN_MAP.csv` — `screen_id | пользовательская функция | реальный файл | контроллер/узел | состояние | источник | проверено`.
- `DESIGN_GAPS.md` — фактически существующие экраны, которых нет в исходном v4.
- `FEATURE_SAFETY_MAP.md` — что нельзя менять или скрывать из-за требований Telegram/безопасности.

Ни один `path`, класс, метод, версия Xcode или API-метод не должен быть помечен `VERIFIED`, пока не найден в реальном checkout. Файлы из старых спецификаций — только **подсказки для поиска**.

**Если `AGENTS.md` отсутствует:** честно фиксируй отсутствие, не имитируй его содержание. Не угадывай `versions.json`; проверяй при каждом новом checkout.

---

## 3. ВИЗУАЛЬНАЯ СИСТЕМА APPLE MESSAGES / iOS 27

### 3.1. Нерушимые правила

1. **Форма важнее цвета.** Воссоздай характерный ритм, группировку, объём, форму пузырьков, поведение шапки и поля ввода Apple Messages, а не просто окрась исходящие сообщения в синий.
2. **Liquid Glass — для навигации и управляющего слоя.** Применяй системные материалы на таб-барах, toolbars, кнопках и transient-controls; **не** делай стеклянными сами сообщения, карточки публикаций и обычный контент.
3. **Настройки — native grouped lists.** Используй принципы системных секций, заголовков, переключателей, отступов, разделителей, вторичных значений и chevrons. Никаких гигантских декоративных карточек для простых настроек.
4. **Типографика — SF Pro**, системные типографические роли, Dynamic Type и правильная иерархия. Не заменять основной UI на Inter/Roboto ради удобства генератора.
5. **SF Symbols — штатные системные пиктограммы.** У иконок должны быть корректные оптические размеры и доступные метки. Не использовать случайные Unicode-символы как финальные аналоги иконок.
6. **Дизайн-файл должен быть редактируемым:** настоящие текстовые слои, геометрия, компоненты, варианты и Auto Layout. Снимок целого экрана не считается редактируемым макетом.
7. **Без смешения сервисов.** Нельзя обозначать Telegram-сообщения как iMessage/SMS/RCS, Telegram-звонки — как FaceTime, а облачный чат — как end-to-end encrypted без основания.
8. Сохраняй знакомые пользователям Telegram сценарии, даже если в iMessage они отсутствуют.

### 3.2. Глубокая проработка бесед

Обязательно рассмотреть:

- Шапка: системный back-button, avatar, имя, состояние, доступные действия; компактность при прокрутке; групповые аватары и channel-specific элементы.
- Входящие/исходящие bubble: скругления в зависимости от позиции в серии, хвостик для окончания серии, правильное выравнивание, группировка по автору и времени, работа с длинным текстом.
- Контент bubble: упоминания, URL, inline-кнопки ботов, code/pre, spoiler, цитаты, пересылка, ответ, редактирование, альбомы, подписи, опросы, платежи, комментарии, service messages.
- Время и статусы: размещение деликатно и строго в рамках семантики Telegram. Скользящее раскрытие timestamps допустимо как UX-референс, но должно работать корректно.
- Появление новых сообщений, быстрая отправка, retry, pinned messages, jump to bottom, unread divider, запланированная отправка, черновики, медиа и поиск.
- Отдельная compact composer c `+` слева, адаптивным полем ввода и контекстными действиями; корректный layout при клавиатуре, диктовке, voice/video recording, emoji/stickers/GIF.
- Context menu: preview слоя сообщения + реакции + реальные действия Telegram; отдельные отрицательные и destructive states; проверка на длинные подписи и Dynamic Type.

### 3.3. Настройки — особый приоритет

Перепроектируй **системно**, а не украшай:

- Главные настройки: профиль, аккаунт, уведомления, конфиденциальность, устройства, данные и память, оформление, язык, Premium, поддержка.
- Вложенные native lists: Switch, Slider, Picker, Disclosures, destructive rows, contextual footers, permissions guidance.
- BananaGram Extras: сообщения, медиа, оформление, сеть и прокси, дополнительные инструменты, безопасность, архив, скрытые аккаунты, защищённое Избранное.
- Различай обычный архив Telegram и **дополнительный защищённый архив BananaGram** — функции не взаимозаменяемы.
- Каждая настройка: текущий state, default, сохранение/отмена, валидация, ошибки, disabled-state, доступность, влияние на приватность и UI.

### 3.4. Темы, материалы и компоненты

- Light / Dark / System, адаптивные цвета, повышенная контрастность и Reduce Transparency.
- SF Pro type scale: Large Title, Title, Headline, Body, Subheadline, Footnote, Caption.
- Семантические цветовые роли: `background`, `groupedBackground`, `surface`, `textPrimary`, `textSecondary`, `separator`, `accent`, `incomingBubble`, `outgoingBubble`, `warning`, `destructive`, `success`, `disabled`.
- Spacing: основная система 4/8/12/16/20/24/32 pt как **дизайн-ориентир**, не вместо актуальных измерений Apple UI Kit.
- Компоненты: navigation, tab bar, chat row, bubble, bubble tail, grouped message, composer, attachment sheet, reaction strip, avatar, media tile, profile header, call controls, story progress, setting row, search, badge, banner, alert, sheet, secure lock, proxy status.
- Размеры, радиусы, hit targets и safe areas брать из проверенного iOS 27 UI Kit, а не выдумывать «пиксель-перфект» числа.
- Отдельная спецификация движения: открытие чата, отправка сообщения, Tapback, reply, opening context menu, accordion, sheet, keyboard, story transition, media zoom, звонки, unlock vault. Для каждого — начальное/конечное состояния, длительность, easing, interruptibility, Reduce Motion.

---

## 4. ПОЛНОЕ ПОКРЫТИЕ ПРОДУКТА

### 4.1. Обязательные группы интерфейсов

**Авторизация:** welcome, телефон, страна, код, 2FA/SRP, passkey/QR, подтверждение нового устройства, восстановление, список аккаунтов, ошибки, переход к приложению.

**Навигация и чаты:** все чаты, папки, unread, pinned, обычный архив, поиск, глобальный и внутридиалоговый поиск, фильтры, свайпы, выбор нескольких чатов, создание диалога, контакты, mentions.

**Сообщения:** private, basic group, supergroup, channel, topic/forum, bot, secret chat, replies, quotes, edits, scheduled, translated messages если доступны, read/unread, reactions, forwarded, photo album, spoiler, poll, voice/video round, link preview, files, saved messages.

**Медиа:** галерея, камера, crop/edit, viewer, video player, files, downloads, stickers, GIF, emoji, emoji status, voice messages, waveform, speed changes, story viewer/editor/privacy.

**Профили:** личный профиль, пользователь, bot, группа, канал, participants, admin actions, privacy, shared media, contacts, invites, reporting, blocking.

**Звонки:** история, incoming/outgoing, ongoing audio/video, group call, screen sharing, speaker/audio route, mute, camera, call errors and network state.

**Дополнительные Telegram-функции:** Premium, gifts, paid reactions, bots, mini apps, permissions, notifications, sessions/devices, storage, personalization, language, username, deep links, moderation, payment flows — **только то, что реально обнаружено в выбранной версии исходников**.

**BananaGram Extras:** существующие настройки чатов, reactions, network/proxy (VLESS/MTProto/WEB только если подтверждены), protected archive, protected Saved Messages, hidden accounts, security warnings and controls. Отсутствующие в checkout функции помечать `NOT_PRESENT`, а не рисовать как существующие.

### 4.2. Исходный v4-каталог — 54 обязательных ID

Ниже приведён начальный список из `SCREEN_MATRIX.csv` handoff-архива. Каждый ID должен иметь **собственный** осмысленный high-fidelity экран и варианты состояния. Похожие композиции допустимы только там, где это оправдано компонентной системой, а не ради экономии работы.

| ID | Экран | Раздел | Исходный SVG Light (в архиве) |
|---|---|---|---|
| `01_auth_phone` | Авторизация · Номер телефона | Авторизация | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/01_auth_phone.svg` |
| `02_chats` | Сообщения · Все чаты | Список чатов/поиск | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/02_chats.svg` |
| `03_chat` | Личная переписка | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/03_chat.svg` |
| `04_attachments` | Вложения · Панель выбора | Медиа/истории | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/04_attachments.svg` |
| `05_topics` | Сообщество · Темы | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/05_topics.svg` |
| `06_profile` | Профиль контакта | Профили | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/06_profile.svg` |
| `07_call_audio` | Голосовой звонок | Звонки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/07_call_audio.svg` |
| `08_gallery` | Медиа · Галерея | Медиа/истории | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/08_gallery.svg` |
| `09_story` | История · Просмотр | Медиа/истории | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/09_story.svg` |
| `10_appearance` | Оформление | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/10_appearance.svg` |
| `11_proxy_detail` | Сеть · VLESS | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/11_proxy_detail.svg` |
| `12_vault` | Защищённый архив | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/12_vault.svg` |
| `13_auth_code` | Вход · Код подтверждения | Авторизация | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/13_auth_code.svg` |
| `14_search` | Глобальный поиск | Список чатов/поиск | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/14_search.svg` |
| `15_archive` | Архив чатов | Список чатов/поиск | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/15_archive.svg` |
| `16_channel` | Канал · Лента | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/16_channel.svg` |
| `17_group_chat` | Групповой чат | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/17_group_chat.svg` |
| `18_reactions` | Реакции · Контекстное меню | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/18_reactions.svg` |
| `19_stickers` | Стикеры и GIF | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/19_stickers.svg` |
| `20_photo_view` | Просмотр фотографии | Медиа/истории | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/20_photo_view.svg` |
| `21_voice_record` | Запись голосового | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/21_voice_record.svg` |
| `22_shared_media` | Общие медиа | Медиа/истории | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/22_shared_media.svg` |
| `23_call_history` | История звонков | Звонки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/23_call_history.svg` |
| `24_settings` | Настройки | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/24_settings.svg` |
| `25_proxies` | Прокси · Список | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/25_proxies.svg` |
| `26_hidden_accounts` | Скрытые аккаунты | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/26_hidden_accounts.svg` |
| `27_vault_locked` | Архив · Блокировка | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/27_vault_locked.svg` |
| `28_accounts` | Переключение аккаунтов | Авторизация | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/28_accounts.svg` |
| `29_miniapp` | Mini App | Боты/Mini Apps | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/29_miniapp.svg` |
| `30_poll` | Опрос · Результаты | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/30_poll.svg` |
| `31_premium` | Telegram Premium | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/31_premium.svg` |
| `32_storage` | Данные и хранилище | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/32_storage.svg` |
| `33_notifications` | Уведомления | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/33_notifications.svg` |
| `34_video_call` | Видеозвонок | Звонки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/34_video_call.svg` |
| `35_edit_profile` | Редактирование профиля | Профили | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/35_edit_profile.svg` |
| `36_new_message` | Новое сообщение | Список чатов/поиск | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/36_new_message.svg` |
| `37_extras_root` | BananaGram · Дополнительно | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/37_extras_root.svg` |
| `38_extras_messages` | BananaGram · Сообщения | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/38_extras_messages.svg` |
| `39_extras_media` | BananaGram · Медиа | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/39_extras_media.svg` |
| `40_extras_network` | BananaGram · Сеть | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/40_extras_network.svg` |
| `41_extras_security` | BananaGram · Защита | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/41_extras_security.svg` |
| `42_archive_settings` | Пароль архива | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/42_archive_settings.svg` |
| `43_archive_scope` | Что защищать паролем | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/43_archive_scope.svg` |
| `44_proxy_add` | Добавить прокси | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/44_proxy_add.svg` |
| `45_proxy_connection` | Подключение прокси | BananaGram Extras | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/45_proxy_connection.svg` |
| `46_privacy_security` | Конфиденциальность | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/46_privacy_security.svg` |
| `47_sessions` | Устройства | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/47_sessions.svg` |
| `48_chat_style` | Вид сообщений | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/48_chat_style.svg` |
| `49_story_editor` | Редактор истории | Медиа/истории | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/49_story_editor.svg` |
| `50_context_menu` | Действия с сообщением | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/50_context_menu.svg` |
| `51_call_settings` | Настройки звонков | Звонки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/51_call_settings.svg` |
| `52_search_filters` | Фильтры поиска | Список чатов/поиск | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/52_search_filters.svg` |
| `53_saved_protected` | Защищённое Избранное | Чаты/каналы/сообщения | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/53_saved_protected.svg` |
| `54_appearance_preview` | Предпросмотр оформления | Настройки | `01_VISUAL_SOURCE/FIGMA_EDITABLE_SVG/light/54_appearance_preview.svg` |

> Для каждого ID версия Dark лежит в соседней директории `FIGMA_EDITABLE_SVG/dark/`, а PNG — в `PNG_3X/light|dark/`. Обозначения путей относятся к ранее созданному handoff-пакету; агент должен проверить фактическое содержимое приложенного архива.

### 4.3. Углублённые состояния для каждой сцены

Прототипируй соответствующие применимые состояния:

- Normal / Selected / Loading / Skeleton / Empty / Offline / Permission Denied / Error / Retry / Disabled.
- Keyboard visible / hidden; input focus; text overflow; long contact/channel titles; long chat text; multiline composer; heavy media; pending download.
- Unread / Read / Sending / Scheduled / Failed / Edited / Deleted; out-of-order updates; service message; restricted content.
- Locked / Unlocked / Wrong password / Face ID unavailable / app going background / account switched / screen recording risk для защищённых экранов.
- Light / Dark / Increased Contrast / Large Accessibility Text / Reduce Motion / Reduce Transparency.

Каждое состояние может быть вариантом компонента или отдельной сцены — не нужно бездумно дублировать сотни одинаковых статичных картинок.

---

## 5. FIGMA — СТРУКТУРА И ТРЕБОВАНИЯ

### Структура файла

1. Cover & Getting Started
2. Reference Audit / Apple iOS 27
3. Foundations / Colors, Typography, Spacing, Materials
4. Symbols & Components
5. Authentication
6. Chat Lists & Search
7. Conversations & Composer
8. Groups / Channels / Topics / Bots
9. Reactions & Context Menus
10. Media & Stories
11. Profiles & Contacts
12. Calls
13. Settings (native grouped lists)
14. BananaGram Extras / Network / Security
15. Light & Dark QA
16. User Flows & Interactive Prototypes
17. Developer Design Handoff

Сделай master-компоненты и component variants, Auto Layout, Figma Variables, styles, constraints, interactive prototype wires, осмысленные layer names. В светлой и тёмной теме одно и то же состояние должно иметь одинаковые UX-свойства.

**Если Figma ограничивает план:** не заявляй, что full-featured variable modes или неограниченные страницы созданы. Вместо этого используй разрешённые страницы/секции, отдельные варианты темы, локальный набор редактируемых SVG, `tokens.json` и инструкцию импорта. Сохраняй имена ID экрана в файлах.

**Важное:** стандартные компоненты iOS/iPadOS 27 Apple нужно искать через официальный UI Kit в Figma. Не смешивай между собой устаревшие iOS 17/18/26 kits без маркировки версии.

---

## 6. ИНТЕРАКТИВНЫЕ ПРОТОТИПЫ

Нужно создавать реальную навигацию и изменяемые состояния, а не просто связывать два статичных скриншота. Демонстрационные действия разрешены **только в локальном прототипе**, без реального доступа к пользовательскому Telegram.

### Обязательные сценарии E2E

1. **Login:** Welcome → номер → код → 2FA/ошибка → чат-лист.
2. **Chat:** список → личный чат → ввод → локальная демонстрационная отправка → Tapback → ответ → возврат.
3. **Attachments:** чат → `+` → фото/видео/файл → preview → local send.
4. **Search:** чаты → поиск → фильтр → результат → найденное сообщение.
5. **Group:** группа → тема → сообщение → участник → профиль → назад.
6. **Channel:** публикация → реакции → комментарии → media viewer.
7. **Story:** лента историй → просмотр → ответ → редактор → настройки публикации.
8. **Calls:** история → исходящий звонок → mute/speaker → завершение.
9. **Appearance:** настройки → оформление → light/dark/system → preview.
10. **Proxy:** BananaGram Extras → сеть → VLESS/MTProto/WEB → edit → demo connect/disconnect → error.
11. **Secure archive:** открытие → locked → неверный код → доступ → блокировка при background.
12. **Hidden accounts:** добавление/скрытие → переключение → уход приложения в фон → безопасное восстановление.
13. **Premium/Mini Apps:** соответствующая страница → permission sheet → dismiss, если функции подтверждены в форке.

### Проверка интерактивности

- Every click action reaches a valid target.
- Back / dismiss / swipe / state reset work consistently.
- Sheet cannot become stranded behind content.
- Theme changes preserve content and navigation.
- No duplicate interactive regions, inaccessible menu items or tap areas outside frame bounds.
- Demo operations are labelled `SIMULATED` where otherwise misleading.
- Offline HTML prototype should work locally with demo fixtures; use only locally available dependencies or document network requirements.

---

## 7. АНИМАЦИОННАЯ СПЕЦИФИКАЦИЯ

Для каждого motion-компонента создать `MOTION_SPEC.md`:

`animation_id | trigger | source frame | destination frame | duration | easing | animated properties | interrupt | reduce_motion_fallback | QA evidence`.

Обязательные кейсы: push/pop беседы, selection, bubble entry, reaction popover, iMessage-like Tapback, message reply, edit mode, composer growth, keyboard transition, media viewer zoom, story progress, call connect/disconnect, drag-to-dismiss, archive unlock, proxy status. Не применять одинаковый bounce ко всем операциям. Скорости и пружины измерять по реальным iOS-референсам, а не выдумывать как точные системные значения.

---

## 8. TELEGRAM-СПЕЦИФИЧНЫЕ ИНВАРИАНТЫ И БЕЗОПАСНОСТЬ

1. Не менять семантику отправки, чтения, таймеров самоуничтожения, online/typing и updates ради «красивого интерфейса». Telegram API Terms **запрещают вмешательство в базовую функциональность**, включая неправдивые статусы прочтения и ghost mode.
2. Не выдавать облачные чаты за end-to-end encrypted; E2EE характерно для секретных чатов. Не ослаблять их протокол и security guarantees.
3. Не подменять `api_id` и `api_hash` чужими; при реальной реализации нужен собственный зарегистрированный Telegram API ID. Для MODE A реальные ключи вообще не нужны.
4. Не логировать токены, ключи, номера телефонов, пароли прокси, ключи архива и содержимое сообщений в аналитике и тестовых скриншотах.
5. Защищённый архив, скрытые аккаунты и protected Saved Messages не должны утекать в search, quick actions, app switcher, previews, Spotlight, share sheets, notifications, widgets, thumbnails и debug logs — **проверяй реальную текущую политику исходников**, не обещай несуществующую защиту.
6. При описании прокси не вводи пользователя в заблуждение: статус «подключено» должен быть истинным состоянием сети в реализации, а в HTML-прототипе должен быть помечен демонстрационным.
7. Соблюдай правила Telegram API, licensing и Apple App Review. Не называй форк официальным Telegram; не используй официальную эмблему Telegram как собственный бренд BananaGram.
8. Дизайн не должен содержать реальные личные переписки: используй синтетические имена и тестовые медиа; пользовательские данные Telegram нельзя собирать для обучения AI-моделей.

---

## 9. ДИЗАЙН-ТОКЕНЫ И ПРАВИЛА ДЛЯ РАЗРАБОТЧИКА

Подготовь машинно-читаемые:

- `design-tokens.json` — Light, Dark, semantic layers, typography, radii, spacing, stroke, effects, motion.
- `components.json` — component ID, variants/states, roles, iOS analog, behavior, Figma node/frame URL.
- `screen-inventory.csv` — экран, приоритет, Figma node, SVG/PNG, states, flow, approval.
- `interaction-map.csv` — hotspot/action, source/destination, gesture, accessibility, expected result.
- `code-to-screen-map.csv` — предполагаемый Swift-модуль и впоследствии подтверждённая реальная реализация; никакой подмены `UNVERIFIED` на `VERIFIED`.
- `accessibility-matrix.csv` — content labels, order, touch targets, Dynamic Type, VoiceOver, Contrast, Reduce Motion.

Для каждой UI-сцены оформи следующую карточку:

```text
SCREEN_ID:
TITLE:
SOURCE_REPO_COMMIT:
SOURCE_CODE_PATH: (VERIFIED / CANDIDATE / UNKNOWN)
FIGMA_FRAME:
LIGHT_SVG / DARK_SVG:
LIGHT_PNG / DARK_PNG:
PURPOSE:
LAYOUT_HIERARCHY:
COMPONENTS_AND_VARIANTS:
STATES:
USER_ACTIONS:
NAVIGATION:
CONTENT_SEMANTICS:
ACCESSIBILITY:
MOTION:
SECURITY_INVARIANTS:
QA_CHECKS:
UNRESOLVED:
DESIGN_APPROVAL_STATUS:
```

**Для MODE B, только если отдельно разрешена реализация:** сохранять нативную архитектуру Telegram-iOS (Swift/UIKit/Texture/Bazel, если подтверждено checkout), менять visual layer минимальными изолированными PR, проверять, что оригинальные event handlers, состояние и MTProto продолжают работать. В прототипном MODE A ничего этого не писать/не менять.

---

## 10. КОНТРОЛЬ КАЧЕСТВА — НЕ РИСОВАТЬ НА ГЛАЗ

### Визуальная QA

- pixel-scale сравнение с официальными iOS 27 UI Kit и Apple Messages по композиции, шапке, tab bar, bubble, composer, row heights, settings groups;
- отсутствие дешёвых декоративных градиентов, чрезмерного blur и карточек «для красоты»;
- светлая и тёмная темы, правильная контрастность и цветовая роль;
- нет обрезанного текста, лишних placeholder-эмодзи, пересекающихся пузырьков, неверных шрифтов;
- состояния клавиатуры, длинных имён/сообщений, больших шрифтов, Dynamic Island, safe areas, разная ширина iPhone;
- все макеты отличимы по назначению, нет переименованных дублей;
- исходник SVG действительно редактируемый, Figma макет — семантические слои, не скриншот фрейма;
- визуальная приёмка не по количеству файлов, а по качеству каждого ключевого пути.

### Прототипная QA

Проверить основные E2E-пути автоматически где возможно (например, Playwright для HTML), сохранение состояния, навигацию, theme switch, корректность размеров и отсутствие ошибок консоли. Проверить результаты вручную визуально.

### Документирование статуса

Используй `PASS / FAIL / BLOCKED / NOT RUN` и записывай **реальные доказательства** (скриншоты, имена файлов, логи). Отдельно фиксируй `VISUAL_READY`, `PROTOTYPE_READY`, `FIGMA_EDITABLE`, `CODE_NOT_STARTED`, `NATIVE_NOT_TESTED`. Нельзя называть нативные тесты выполненными только из-за успешного запуска HTML-прототипа.

### Критерии приёмки MODE A

- Есть полный аудит выбранного commit SHA.
- Все 54 исходные сцены либо существенно усовершенствованы, либо имеют обоснованный статус и замечания.
- Добавлены найденные в коде отсутствующие сценарии или чёткая `GAP_MATRIX` по ним.
- Базовые беседы и настройки визуально максимально приближены к Apple Messages/iOS 27 при сохранении semantics Telegram.
- Предоставлен редактируемый дизайн и полноценный интерактивный прототип.
- Существуют светлые/тёмные темы, основные states и доступность.
- Документация достаточна для передачи новому разработчику без объяснений на словах.
- Итоговый ZIP реально существует, целостен, содержит все объявленные материалы и `MANIFEST.sha256`.

---

## 11. ПОШАГОВОЕ РУКОВОДСТВО ДЛЯ ДИЗАЙН-АГЕНТА И БУДУЩЕГО РАЗРАБОТЧИКА

Сделай один документ `COMPLETE_STEP_BY_STEP_GUIDE.md` и, если доступны инструменты, PDF/HTML. Обязательные главы:

1. Распаковка архива и обзор каталогов.
2. Где находится `SCREEN_MATRIX`, как открыть макет и связать ID с референсом Apple.
3. Как клонировать форк рекурсивно, зафиксировать SHA и изучить фактический UI, не редактируя код в MODE A.
4. Как открыть/импортировать Figma и SVG; что делать при ограниченном тарифе Figma.
5. Как редактировать theme tokens и master components, не портя остальные экраны.
6. Как открыть HTML-прототип, включить тёмную тему и проверить маршрут.
7. Как добиться точной композиции Apple Messages: checklist для чатов, bubble, composer, навигации и настроек.
8. Как дорабатывать секретные/защищённые интерфейсы безопасно.
9. Как экспортировать PNG/SVG и сверить их с редактируемыми исходниками.
10. Как создавать новые экранные состояния из компонентов.
11. Как оценить accessibility и подготовить UX-матрицу.
12. Как создать developer handoff и не выдумать исходные Swift-файлы.
13. Как повторять QA после каждой правки и фиксировать доказательства.
14. Как сформировать чистый ZIP с проверенным манифестом.
15. Что делать при проблемах Figma, некорректных шрифтах, отсутствующих исходных файлах и невозможности тестировать iPhone.

**Формат каждого шага:** `Кто` → `Что открыть` → `Где найти` → `Каким действием` → `Почему` → `Ожидаемый результат` → `Как проверить` → `Если ошибка` → `Как откатить`.

---

## 12. СТРУКТУРА ИТОГОВОГО ZIP

```text
BananaGram_iOS27_Complete_Prototype_Handoff/
├── 00_START_HERE/
│   ├── README_RU.md
│   ├── PACKAGE_INDEX.md
│   └── SOURCE_OF_TRUTH.md
├── 01_RESEARCH/
│   ├── REPOSITORY_AUDIT.md
│   ├── SCREEN_INVENTORY.csv
│   ├── CODE_TO_SCREEN_MAP.csv
│   ├── DESIGN_GAPS.md
│   └── LINK_CATALOG.md
├── 02_FIGMA/
│   ├── FIGMA_LINK.md
│   ├── FIGMA_IMPORT_GUIDE.md
│   ├── EDITABLE_SVG/light/
│   ├── EDITABLE_SVG/dark/
│   └── COMPONENT_LIBRARY/
├── 03_MOCKUPS/
│   ├── LIGHT_PNG/
│   ├── DARK_PNG/
│   ├── INTERACTION_STATES/
│   ├── ACCESSIBILITY/
│   └── CONTACT_SHEETS/
├── 04_DESIGN_SYSTEM/
│   ├── tokens.json
│   ├── COMPONENTS.md
│   ├── TYPOGRAPHY.md
│   ├── COLORS.md
│   ├── MATERIALS.md
│   └── MOTION_SPEC.md
├── 05_INTERACTIVE_PROTOTYPE/
│   ├── index.html
│   ├── assets/
│   ├── USER_FLOWS.md
│   └── INTERACTION_MAP.csv
├── 06_DIAGRAMS/
│   ├── NAVIGATION_MAP.svg
│   ├── COMPONENT_STATES/
│   └── USER_FLOWS/
├── 07_DESIGN_HANDOFF/
│   ├── SCREEN_SPECS/
│   ├── FEATURE_SAFETY_MAP.md
│   ├── IMPLEMENTATION_READINESS.md
│   ├── CODE_MAPPING_CANDIDATES.md
│   └── DESIGN_DECISIONS.md
├── 08_STEP_BY_STEP/
│   ├── COMPLETE_STEP_BY_STEP_GUIDE.md
│   ├── FIGMA_EDITING_GUIDE.md
│   ├── PROTOTYPE_TEST_GUIDE.md
│   └── TROUBLESHOOTING.md
├── 09_QA/
│   ├── VISUAL_QA.csv
│   ├── PROTOTYPE_QA.csv
│   ├── ACCESSIBILITY_QA.csv
│   ├── SECURITY_REVIEW.md
│   ├── TEST_EVIDENCE/
│   └── FINAL_AUDIT.md
├── 10_PRESENTATION/
│   └── DESIGN_REVIEW.pdf
├── MASTER_PROMPT.md
├── MANIFEST.sha256
└── DELIVERY_REPORT.md
```

**Не добавляй пустые фиктивные файлы.** Если какого-то формата создать невозможно, заполни `KNOWN_LIMITATIONS.md` и предоставь лучшее доступное решение. Существующий v4-архив разрешено переиспользовать как основу; новую версию собирать с понятным changelog, без дублирования старых некорректных прототипов.

---

## 13. ОФИЦИАЛЬНЫЕ ССЫЛКИ И РЕФЕРЕНСЫ — ИСПОЛЬЗОВАТЬ ПРИ РАБОТЕ

Ссылки приведены как **источники для проекта**, а не как подтверждение, что все материалы уже скачаны или импортированы. Перед выполнением проверять доступность и актуальность. Приоритет — первоисточники Apple и Telegram.

### A. Исходники и handoff BananaGram

| Ресурс | Ссылка | Назначение |
|---|---|---|
| Собственный форк | https://github.com/decoder-dev/Telegram-iOS | Source of truth для кодовой архитектуры |
| Прямая Git-ссылка | https://github.com/decoder-dev/Telegram-iOS.git | Для `git clone --recursive` |
| Официальный Telegram-iOS | https://github.com/TelegramMessenger/Telegram-iOS | Upstream, лицензирование, сборка |
| Telegram-iOS README | https://github.com/TelegramMessenger/Telegram-iOS/blob/master/README.md | Официальная инструкция сборки |
| Upstream Xcode/Bazel versions | https://github.com/TelegramMessenger/Telegram-iOS/blob/master/versions.json | Версии *только для соответствующего commit* |
| Build system | https://github.com/TelegramMessenger/Telegram-iOS/tree/master/build-system | Bazel / Xcode генерация |
| Модули UI | https://github.com/TelegramMessenger/Telegram-iOS/tree/master/submodules/TelegramUI | Поиск базовых UI-модулей |
| Telegram UI issue tracker | https://github.com/TelegramMessenger/Telegram-iOS/issues | Проблемы интерфейса и регрессии |
| Telegram UI pull requests | https://github.com/TelegramMessenger/Telegram-iOS/pulls | История и возможные примеры изменений |
| Fork branches | https://github.com/decoder-dev/Telegram-iOS/branches | Найти правильную рабочую ветку |
| Fork commits | https://github.com/decoder-dev/Telegram-iOS/commits/master/ | Зафиксировать исходный SHA |
| Текущий Figma-проект | https://www.figma.com/design/ekzgmAnsrVe0np9Kwcxyz9 | Частичный редактируемый дизайн BananaGram |
| Локальный исходный архив | `BananaGram_iOS27_AGENT_HANDOFF_v4.0.1.zip` | Пользователь **должен приложить архив** к задаче агента |

> Примечание: `CLAUDE.md`, `AGENTS.md`, `CHANGELOG.md` и некоторые BananaGram Extras могут различаться между ветками; искать в checkout, не обещать существование файла по неоткрываемой ссылке.

### B. Apple: официальный дизайн iOS 27 / iMessage

| Ресурс | Ссылка | Назначение |
|---|---|---|
| **Apple Design Resources** | https://developer.apple.com/design/resources/ | Главный официальный каталог ресурсов |
| **iOS & iPadOS 27 UI Kit — Figma** | https://www.figma.com/community/file/1651309003795292092 | Редактируемые системные компоненты Apple |
| Apple: анонс дизайн-китов 27 | https://developer.apple.com/news/?id=e2lxw9l1 | Дата и состав UI Kit |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines/ | Правила Apple |
| HIG: Layout | https://developer.apple.com/design/human-interface-guidelines/layout | Пространство, иерархия, safe areas |
| HIG: Materials | https://developer.apple.com/design/human-interface-guidelines/materials | Разделение content и Liquid Glass |
| Liquid Glass | https://developer.apple.com/documentation/technologyoverviews/liquid-glass | Системные материалы |
| Adopting Liquid Glass | https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass | Как адаптировать существующий интерфейс |
| **Apple Messages iOS 27 (RU)** | https://support.apple.com/ru-ru/guide/iphone/iph82fb73ba3/27/ios/27 | Достоверные скриншоты и пользовательские сценарии |
| Apple Messages iOS 27 (EN) | https://support.apple.com/en-ie/guide/iphone/iph82fb73ba3/27/ios/27 | Дополнительный язык референса |
| SF Symbols | https://developer.apple.com/sf-symbols/ | Официальные системные пиктограммы |
| HIG: SF Symbols | https://developer.apple.com/design/human-interface-guidelines/sf-symbols | Использование системных иконок |
| Fonts / SF Pro | https://developer.apple.com/design/resources/ | Скачать SF Pro для законного использования по условиям Apple |
| Accessibility: Motion | https://support.apple.com/guide/iphone/customize-onscreen-motion-iph0b691d3ed/27/ios/27 | Reduce Motion и системные настройки |
| Apple App Review | https://developer.apple.com/app-store/review/guidelines/ | Правила распространения стороннего клиента |
| Xcode | https://developer.apple.com/xcode/ | Инструменты для будущего этапа реализации |
| SwiftUI | https://developer.apple.com/documentation/swiftui | Системная база для новых компонентов, если применимо |
| UIKit | https://developer.apple.com/documentation/uikit | Основной нативный UIKit-стек |
| AVKit | https://developer.apple.com/documentation/avkit | Нативный просмотр медиа |
| UserNotifications | https://developer.apple.com/documentation/usernotifications | Системные уведомления |

### C. Telegram API, безопасность и лицензирование

| Ресурс | Ссылка | Назначение |
|---|---|---|
| Telegram API home | https://core.telegram.org/ | Каталог API и документации |
| Telegram API для клиентов | https://core.telegram.org/api | MTProto API, full-client методы |
| **Telegram API Terms** | https://core.telegram.org/api/terms | Обязательные ограничения сторонних клиентов |
| **Создание Telegram Application** | https://core.telegram.org/api/obtaining_api_id | Собственный api_id / api_hash |
| My Telegram / API tools | https://my.telegram.org/ | Регистрация клиентского приложения |
| Telegram authorization | https://core.telegram.org/api/auth | Разные способы входа, 2FA и ошибки |
| Telegram updates | https://core.telegram.org/api/updates | Синхронизация, read/updates semantics |
| MTProto security guidelines | https://core.telegram.org/mtproto/security_guidelines | Обязательные требования к криптографии |
| Secret Chats | https://core.telegram.org/api/end-to-end | Безопасность секретных чатов |
| MTProto | https://core.telegram.org/mtproto | Протокол Telegram |
| TDLib (альтернатива, не стек форка) | https://core.telegram.org/tdlib/ | Справочная архитектура клиента, не повод переписывать форк |
| Telegram Apps | https://telegram.org/apps | Официальные и неофициальные клиенты |
| Telegram FAQ | https://telegram.org/faq | Истинная семантика функций |
| Telegram Content Licensing | https://telegram.org/tos/content-licensing | Правила использования контента и запрет AI scraping/training |
| Telegram-iOS license / repo | https://github.com/TelegramMessenger/Telegram-iOS | Проверять точный LICENSE в выбранной версии |

### D. Прототипирование и техническая документация

| Ресурс | Ссылка | Назначение |
|---|---|---|
| Figma | https://www.figma.com/ | Редактируемые макеты, прототипы |
| Figma Community | https://www.figma.com/community | Поиск других референсов и UI-наборов |
| Figma Learn | https://help.figma.com/ | Auto Layout, components, variants, prototypes |
| Figma API | https://www.figma.com/developers/api | Опциональный API/экспорт |
| Mermaid | https://mermaid.js.org/ | User flows, sequence diagrams |
| Playwright | https://playwright.dev/ | Проверки автономного HTML-прототипа |
| WCAG 2.2 | https://www.w3.org/TR/WCAG22/ | Контраст, управление, доступность |
| Git | https://git-scm.com/docs | Version control и фиксация SHA |
| Bazel | https://bazel.build/ | Справка по билду существующего проекта |

### Правила обращения с источниками

- Ссылки могут вести на обновляемые страницы: фиксируй дату проверки и используемую версию.
- При расхождении iOS 27 UI Kit и старого JPEG-концепта **побеждает актуальный официальный Apple UI Kit**.
- При расхождении графического макета и поведения Telegram **сохраняй корректную функциональность Telegram**.
- Не копируй чужую графику в релиз без проверки лицензии. Apple UI Kit предназначен для дизайна под платформы Apple и подчиняется условиям Apple Design Resources.

---

## 14. ПОРЯДОК ИСПОЛНЕНИЯ АГЕНТОМ

### Этап 0 — Подготовка исходных данных

- Получить архив v4 и URL форка.
- Проверить содержимое, ссылки и источник Figma.
- Зафиксировать source commit SHA и перечислить имеющиеся материалы.

### Этап 1 — Аудит и gap analysis

- Сканировать UI-модули форка.
- Сопоставить полный набор экранов с 54 ID.
- Выделить отсутствующие экраны и старые дефекты в дизайне.

### Этап 2 — Apple iOS 27 visual reference audit

- Проверить актуальный iOS 27 UI Kit.
- Измерить ключевые системные компоненты.
- Проанализировать реальные Apple Messages conversation/list/settings patterns.

### Этап 3 — Foundations + Components

- Подготовить семантические токены, typography, layouts и reusable components.
- Закрепить Light/Dark варианты и Accessibility fallbacks.

### Этап 4 — High-fidelity screens

- Сначала качественно довести три образцовых экрана: **Список чатов**, **Личная переписка**, **Настройки**.
- После проверки распространить систему на 51 оставшийся ID и добавленные из кода сцены.
- Никаких переименованных одинаковых картинок.

### Этап 5 — Prototypes + Motion

- Связать пользовательские сценарии.
- Настроить состояния, жесты и переходы.
- Собрать автономный HTML-прототип и/или Figma prototype по доступности инструментов.

### Этап 6 — QA + Iteration

- Просмотреть каждый экран визуально.
- Проверить Dark/Light, large text, keyboard, disabled, safety, routing.
- Исправить проблемы и переснять макеты.

### Этап 7 — Handoff + ZIP

- Подготовить описание каждого экрана, кодовую карту без вымышленных путей, матрицы сценариев и руководство.
- Проверить целостность файлов, SHA-256, кликабельные пути.
- Сформировать `DELIVERY_REPORT.md` с фактическим, не заявленным на словах результатом.

**Не переходить в MODE B без отдельного согласия владельца.**

---

## 15. КАК ДОЛЖЕН ВЫГЛЯДЕТЬ ФИНАЛЬНЫЙ ОТВЕТ АГЕНТА

Короткий отчёт на русском:

1. Исследованный репозиторий, ветка и точный commit SHA.
2. Сколько уникальных экранов найдено, переработано и проверено.
3. Сколько Figma frames/component variants реально создано.
4. Какие прототипные маршруты действительно работают.
5. Где находятся Light/Dark исходники и как их открыть.
6. Ссылки на реально существующий Figma-файл и ZIP (если созданы).
7. Сколько тестов PASS/FAIL/BLOCKED/NOT RUN с подтверждением.
8. Какие ограничения ещё остаются.
9. Что передать следующему агенту-разработчику.
10. Отдельно: **«Исходники Telegram изменены: НЕТ / ДА (со списком файлов)»**. В режиме MODE A должно быть **НЕТ**.

**Главное:** мне нужен результат, который можно показать профессиональному iOS-дизайнеру, открыть и покликать как продукт, импортировать в Figma, проверить и передать разработчику. Не заглушка и не «концепт из трёх экранов», а детальный проверяемый проект интерфейса всего BananaGram, в эстетике iMessage для iOS 27, без потери Telegram-специфичных функций.

---

## 16. ОТДЕЛЬНЫЙ PROMPT ДЛЯ ФАЗЫ РЕАЛИЗАЦИИ (НЕ ЗАПУСКАТЬ СЕЙЧАС)

> Только после утверждения MODE A, с явным разрешением пользователя:
>
> «Возьми утверждённый дизайн-пакет BananaGram Glass iOS 27 и внедри его в существующий форк `decoder-dev/Telegram-iOS` без смены архитектуры Telegram. Сначала получи baseline build, зафиксируй commit SHA, проверь `versions.json` и правила репозитория, затем малыми изолированными изменениями внедряй визуальные компоненты. Сохрани MTProto, Secret Chats, историю сообщений, реакции, звонки, accounts, VLESS/MTProto/WEB, protected archive, hidden accounts и механизмы безопасности. Для каждого экрана дай точный путь исходника, screenshot comparison, build/test evidence и rollback. Не выполняй push, merge, публикацию или подписание релиза без отдельного разрешения».

---

*Конец мастер-промпта. Перед запуском задачи добавь агенту исходный ZIP-архив v4.0.1 и доступ к репозиторию. Настоящий Figma-файл не должен подменяться изображениями. Если доступ к ресурсам отсутствует, честно отмечай ограничения.*
