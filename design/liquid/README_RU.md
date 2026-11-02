# BananaGram Liquid

Рабочая ветка: `liquid`. Этап: дизайн и прототипирование (MODE A).

Исходники приложения не менялись. Текущий пакет не является готовым редизайном, нативной сборкой или утверждённым дизайном.

Начните с [источников решений](research/SOURCE_OF_TRUTH.md), [аудита checkout](research/REPOSITORY_AUDIT.md) и [расхождений](research/DESIGN_GAPS.md).
Карта 54 исходных сцен: [SCREEN_INVENTORY.csv](research/SCREEN_INVENTORY.csv). Привязки к объявлениям в коде: [CODE_TO_SCREEN_MAP.csv](research/CODE_TO_SCREEN_MAP.csv).

`reference/` и `specs/imported/` содержат исходные материалы пользователя. Нормализованы переводы строк и синтаксис Markdown-переносов; визуальные макеты сохранены без изменений. Это концепты для проверки, а не результаты визуальной приёмки. Старые отчёты PASS из архива сюда не переносились.

Для проверки целостности импортированных материалов выполните из корня репозитория:

```sh
python3 design/liquid/tools/audit.py
```

Нативные проверки требуют macOS, Xcode и Simulator. На текущем Linux-хосте их выполнение заблокировано. Источник версий — `versions.json`, а не целевая версия iOS.

## Открыть прототип

Откройте `prototype/index.html` обычным браузером. Зависимости загружаются с диска, Интернет не нужен. Переписка, список, настройки и вспомогательные DOM-сцены хранят демонстрационное состояние в памяти вкладки. Остальные страницы имеют заметную отметку IMPORTED; их маршруты вынесены под изображение, чтобы не выдавать статический концепт за работающий экран.

Опорная система описана в [COMPONENTS.md](foundations/COMPONENTS.md). Редактируемые экспорты и PNG 3× — в `mockups/light/` и `mockups/dark/`. SVG содержит векторы и текст; это экспорт web-композиции, а не Figma Auto Layout или утверждённая нативная геометрия.

Для проверок создайте отдельное Python-окружение, установите `playwright` и браузер Chromium. Проверено с Playwright 1.64.1:

```sh
python -m playwright install chromium --only-shell
python design/liquid/tools/check_prototype.py
python design/liquid/tools/check_foundations.py
python design/liquid/tools/export_screens.py
```

Результаты находятся в `qa/`. Проверки загрузки, поведения DOM, контраста и кадры различаются по статусу. PASS браузерной проверки не означает нативную приёмку.
