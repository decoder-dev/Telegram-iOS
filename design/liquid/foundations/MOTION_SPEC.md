# Движение — открытые измерения

В текущем прототипе переходы между сценами мгновенные. Пружины, длительность клавиатуры и метрики iOS не измерены. Здесь нет заявлений о покадровой приёмке нативной анимации.

Перед реализацией нужны записи референса и приложения для следующих переходов:

- chat push/pop: направление, сцепление header/list, возможность прервать back gesture;
- bubble entry: положение относительно composer и предыдущей серии, поведение при быстрой отправке;
- context/reaction sheet: открытие, dismiss, повторный tap, возврат focus;
- reply/edit: рост banner и синхронное смещение списка;
- composer/keyboard: изменение высоты, диктовка, смена emoji, voice/video recording;
- media zoom, story, call connect/reconnect, archive unlock и proxy status.

Для каждого перехода фиксируются trigger, начальное/конечное состояния, длительность по timestamps, easing, прерывание и Reduce Motion fallback. Значения не копируются из декоративных web-анимаций.

Прототипный Reduce Motion выключает CSS animation/transition. Это пригодный fallback для HTML, но нативное системное предпочтение пока NOT RUN. Окончательная проверка — запись Simulator, `tools/animation_sheet.py` и просмотр кадров по правилам корневого AGENTS.md.
