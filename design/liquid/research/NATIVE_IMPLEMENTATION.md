# Нативная реализация Liquid

Владелец отдельно разрешил перейти от макетов к изменению самого приложения в ветке `liquid`. Незавершённая работа над групповым HTML-прототипом сохранена в Git stash с именем `liquid: group prototype checkpoint before native UI work`.

## Первый этап

`LiquidPresentationTheme.swift` задаёт палитру через существующие роли `PresentationTheme`. Она применяется к стандартным Day/Classic White и Night/Classic Black до последующей пользовательской настройки. Изменены списки, grouped settings, навигация, поиск, обычные сообщения, реакции, опросы, файловые подписи и composer. Отдельные светлая и тёмная пары accent/foreground сохраняют контраст текста на кнопках и бейджах.

Cream, Graphite и Halloween строятся напрямую из прежних stock-фабрик, затем получают собственное оформление. Это исключает случайное наследование Liquid-палитры брендовыми темами. Сериализация и сохранённые настройки не мигрируются.

В пути `makePresentationTheme` отключена повторная генерация stock-цветов только для стандартных Classic/Day/Night без явно выбранного accent или цветов пузырьков. Этот путь важен при выборе обоев с сохранением стандартных цветов: при полностью пустых параметрах кастомизатор и раньше возвращал тему сразу. Явные пользовательские цвета продолжают обрабатываться прежним путём. Swift-регрессия проверяет 56 комбинаций темы и настроек.

После штатного кастомизатора палитра по умолчанию применяется повторно без изменения выбранных обоев: кастомизатор также меняет foreground реакций и опросов. Для полного пути фабрики добавлен нативный XCTest target `//submodules/TelegramPresentationData:LiquidThemeTests`. Восемь тестов проверяют фактические объекты темы, foreground реакций с выбранными обоями, пользовательские цвета/обои, брендовые палитры, роли навигации, поверхности дополнительных панелей и контраст всех результатов викторины. Runner закреплён на той же паре iPhone 17 / iOS 26.5, что существующий TextFormatTests; доступность runtime дополнительно выводится в CI. До фактического запуска эти тесты имеют статус NOT RUN.

Общий адаптер `NavigationBarTheme` теперь сохраняет отдельные роли кнопок, заголовка, disabled controls и бейджей. `NavigationBarComponent` рисует бейдж своим fill, а не цветом кнопок. Меню шапки чата использует navigation button color и при создании, и после обновления темы.

`higChatBubbleCorners` сохраняет диапазон радиуса 4–30, вычисление вспомогательного радиуса и настройку слияния. Хвостики восстановлены через уже существующий рендерер. Код не переписывает маски пузырьков.

В корневом списке задан заголовок BananaGram; локализованные названия архива, папок и вкладок сохраняются. Существующие обработчики отправки, редактор, запись, аккаунты и защита не заменяются.

## Проверки и ограничения

Фактические команды, коды завершения и логи находятся в `qa/native/validation.json`. Выполнены Python-регрессии Branding и glass bubbles, включая новые расчёты контраста по цветам нативной Swift-палитры. Это проверки исходников и числовых ограничений, а не запуск UIKit.

Swift-проверка геометрии заблокирована отсутствием `swift`. Попытка Make.py не дошла до компиляции: на Linux проверка SHA-256 загруженного Bazel не совпала с pin. Проверка подписи не отключалась. Xcode и iOS Simulator на этом хосте отсутствуют.

Нативные скриншоты, видео, VoiceOver, реальная клавиатура и итоговая компиляция — NOT RUN. Изменение не считается визуально принятым до сборки и просмотра приложения. Следующий gate — сборка ветки на macOS, затем проверка Classic White/Black, branded themes, custom accents/wallpaper, reply/edit, rich text, voice/video и защищённых состояний.

## Нативная QA-сборка

Подготовка Xcode и Metal вынесена в общий composite action для device build и Simulator QA. QA выбирает Xcode 27 по умолчанию; Xcode 26 остаётся отдельным вариантом с отдельным кэшем. Device workflow сохраняет Simulator runtimes: после архивации он теперь запускает XCTest, поэтому прежнее удаление всех runtimes несовместимо с этим этапом.

Simulator QA устанавливает приложение, извлечённое из свежего `bazel-bin/Telegram/Telegram.ipa`, и сохраняет SHA исходников, версию Xcode и инвентарь Simulator вместе с кадрами. Поиск случайного `.app` в archive-root больше не используется. Локально прошли 43 из 44 проверок BuildTools и 29 из 30 Branding; по одной проверке в каждом наборе пропущено существующими условиями.

Ожидание перед просмотром first-launch видео: один экземпляр welcome-интерфейса, читаемый текст, отсутствие обрезания и вспышек другого фона при запуске, согласованные light/dark поверхности. Это только авторизация/первый запуск. Чаты, composer, меню, клавиатура и защищённые состояния остаются отдельными непроверенными сценариями до их записи в настоящем приложении.

Палитра Liquid дополнена поверхностями emoji/sticker/GIF-панели, поиском стикеров, бот-клавиатурой, полями action sheet и контекстными меню. Их текст, фон и foreground бейджей используют общие роли. Для правильного ответа викторины и success-label выделена контрастная зелёная роль; неправильный ответ использует destructive. Проверены численные сочетания меток с обычной, положительной и отрицательной заливкой. Локальные Branding: 31 pass / 1 skip, glass bubbles: 14 pass. Это не визуальная приёмка этих панелей.

## Раскладка общих списков

По указанию владельца дальнейшие CI-dispatch и публикация отложены до завершения реализации экранов. Уже запущенные задания не отменялись. Новые изменения пока фиксируются локально, чтобы push не запускал автоматический client workflow.

`PresentationLayoutMetrics` задаёт общие отступы и размеры строк. В списке чатов загрузка и раскладка аватара используют один расчёт диаметра; основной заголовок приведён к 17 pt при стандартном масштабе, дата — к 13 pt, счётчик — к 13 pt. Между аватаром и текстом задано 12 pt; обычная строка получает по 14 pt вертикального пространства. Компактный режим, темы, архив, группы, custom rows, редактирование и свайпы продолжают работать через прежние ветви. Статический plus композера заменён на SF Symbol; анимированные состояния записи не менялись.

Disclosure и switch rows используют перенос заголовка при размере текста от 23 pt. Обычные текстовые значения disclosure при этом располагаются под заголовком и могут переноситься. Цветовые значения, изображения, счётчики и бейджи сохраняют свой вариант раскладки; additional detail label не подменяется. Высота считается по реальным text layouts, ширина текстовых ограничений не становится отрицательной.

Для этого добавлен `//submodules/ItemListUI:SettingsRowLayoutTests`: три UIKit-теста проверяют обычную строку, большой русский текст с отдельным значением на ширинах 320/393/768 в light/dark и обоих стилях, а также положение бейджа. Подготовлены, но ещё не запускались. Доступные Python-контракты VoiceOver (20), UISizing (6) и glass bubbles (14) прошли; они не заменяют нативный прогон.

Корневые настройки используют отдельные `PeerInfoScreen` rows. Для них также добавлены многострочные состояния: обычные текстовые значения располагаются ниже заголовка при крупном размере, а бейджи и изображения сохраняют прежнюю раскладку. Переключатели и действия берут размер из `listsFontSize`. В switch row правая граница текста теперь учитывает переданный `safeInsets.right`, как сам переключатель. Подписи и биография профиля масштабируются вместе с настройками текста; верхняя левая и правая подписи получают раздельную ширину и общую высоту. Callback-и, ограничения доступа, content model и обработка ссылок не менялись. Нативная проверка этих состояний отложена до общего прогона.

Служебные иконки настроек (уведомления, приватность, устройства, папки, сеть, файлы и другие стандартные действия) используют SF Symbols в прежнем цветном tile размером 30 pt. Символ вписывается в 22×22 pt; при отсутствии символа сохраняется bundled asset. Для них убран декоративный bitmap backdrop; тема и cache/tint API сохранены. Специальные значки продуктов и платежей не подменялись.

Роли welcome-кнопки, верхней панели раскрытого in-app уведомления и статистики включены в общую палитру. Неактивная точка welcome-пагинации отличается от accent активной точки, в том числе в брендовых темах. Уведомления здесь относятся только к отображению внутри клиента: APNs, токены, серверы и обработчики доставки не менялись. Branding после этих изменений: 31 pass / 1 skip.

Общие presentation data теперь наблюдают системную смену категории текста и Reduce Motion. System font обновляет существующие `PresentationFontSize` только при включённом `useSystemFont`; ручные размеры и сериализация сохранены. Итоговый reduceMotion объединяет настройку клиента и системную настройку. Добавлен нативный тест сигнала размера текста с фактическим `UIFont` для категории, доставкой уведомления и проверкой прекращения событий после dispose. Он подготовлен к общему прогону, ещё не запускался.

## Крупный заголовок списка

Корневой список получил отдельный UILabel в стиле large title с системным размером и семантическим header для accessibility. В архиве, выборе контактов, previews и режиме редактирования сохраняется компактная шапка. Изначально корневой список показывает заголовок и поиск. Сначала сворачивается заголовок, затем поиск; остановки предусмотрены в начале, между этими стадиями и в полностью свёрнутом состоянии. Пределы прокрутки передаются текущим, соседним и отложенно созданным страницам папок. Полный предел главной страницы отделён от промежуточного предела при переходе в форум.

Текст компактного заголовка плавно появляется при сворачивании, а соединение/обновление остаётся видимым и в развёрнутой шапке. Замок, proxy button, emoji status и доступ к историям не заменяются. При раскрытии историй крупный текст уступает им место. Область крупного текста пропускает касания в список для прокрутки. Изменённый fade не подменяет opacity замка или кнопок.

До записи ожидается: на первом кадре крупный BananaGram над поиском; при первом участке drag заголовок уходит вверх и затухает, а поиск следует за ним; во втором участке сворачивается поиск. Соседние строки не скачут, не появляются две непрозрачные надписи одновременно, замок и кнопки не исчезают. Проверить reverse drag, release на каждой границе, folder swipe, inline forum push/pop/cancel, поиск/отмену, архив, скрытый поиск, истории, landscape/RTL, крупный текст, light/dark и Reduce Motion. Это ожидаемое поведение, нативная видеоприёмка ещё не выполнена.

На Linux добавлен отдельный Swift 6.4.2 в пользовательский каталог инструментов; архив проверен подписью официального Swift 6.x Release Signing Key. Теперь локально выполнены production geometry (96 граничных состояний + четыре решения snapping), 56 комбинаций настроек тем и сохранённая геометрия пузырьков. В Branding больше нет пропуска из-за отсутствия Swift: 32 pass. UISizing: 6 pass; VoiceOver contracts: 20 pass. Синтаксический разбор Swift 6.4.2 прошёл для всех 28 изменённых Swift-файлов. Он не разрешает UIKit-модули и не считается iOS typecheck/build.

## Пустые состояния и действия

Пустые списки чатов/папок/тем получают полный presentation snapshot: масштабируются заголовок, описание и action. Описание включено в расчёт общей высоты. Кнопка измеряется по многострочному тексту; при недостатке высоты иллюстрация скрывается, а весь контент доступен вертикальной прокруткой. Отдельный архивный information view и его callback сохранены. Touch conversion берётся из фактических bounds вложенного view, а nested scroll не перехватывает status-bar scroll-to-top.

Общий EmptyStateIndicator для состояний медиа/историй также масштабирует текст и кнопки, прокручивается при overflow и убирает отсутствующие title/animation views при переиспользовании. Reduce Motion переключает декоративный sticker на неподвижный кадр. Основная и дополнительная кнопки сохраняют действия и получают доступные текстовые подписи.

ButtonComponent получил необязательный accessibilityLabel на настоящей внутренней UIButton. Состояние enabled/progress теперь одинаково проверяется при tap и long press; явный allowActionWhenDisabled сохранён. Добавлен нативный тест смены подписи и всех четырёх сочетаний enabled/allowWhenDisabled/progress. Он подготовлен, не запускался.

Для видео-проверки ожидается: длинный текст не обрезается, описание не наезжает на CTA, действие остаётся достижимым в landscape/большом тексте, loading скрывает content/actions и озвучивается отдельно, после loading возвращаются прежние действия. Проверить папку без права редактировать, пустые темы, архивный action, повторное использование empty view, Reduce Motion и прокрутку из области текста. Нативная приёмка ещё не выполнена.

Полный синтаксический проход Swift 6.4.2: 6133 доступных Swift-файла в Telegram и submodules, ошибок разбора 0. Изменённые после этого файлы повторно разбираются отдельно; текущая группа содержит 32 Swift-файла. Это не компиляция UIKit и не проверка всех функций приложения. Из UI-контрактов локально проходят 20 VoiceOver и 6 UISizing.

## Совместимость пользовательских тем

Фабрики cloud/gift themes и decoder импортированных тем теперь используют исходную stock-палитру как основу. Liquid применяется к встроенным Classic/Day/Night без extending theme; незаданные поля импортированного оформления не получают новые цвета случайно. Стартовая defaultPresentationTheme, напротив, использует ту же Liquid-палитру, что выбранная Classic White, чтобы начальный интерфейс не возвращался к старым цветам. Обои, идентификаторы и сериализация тем сохранены.

Локальная Swift-проверка политики расширена до 112 сочетаний. Branding: 32 pass, изменённые Swift-файлы разобраны без синтаксических ошибок. Четыре новых XCTest проверяют стартовый fallback, основу custom theme, cloud settings и декодирование темы с пропущенными полями; они подготовлены, но не запускались. Ожидание для записи: одинаковые базовые поверхности до и после загрузки Classic White; импорт темы сохраняет её цвета и обои без вспышки Liquid. Проверить повторный выбор темы, preview, загрузку gift/cloud theme, перезапуск и ручной accent. Нативная приёмка остаётся NOT RUN.

## Формы входа и регистрации

Общий solver авторизации вынесен в Foundation-файл. Распределение отступов повторяется до выполнения всех ограничений; нулевой вес не участвует в делении. Это устраняет нечисловые координаты и превышение maxValue после последовательного насыщения отступов. Production solver локально проверен на 96 сочетаниях размеров/масштаба, пяти граничных регрессиях, переносе координат и сохранении размеров элементов.

E-mail, пароль, recovery code, ожидание сброса и регистрация используют общий scroll node формы. Поля, описания и дополнительные действия масштабируются системными UIFont text styles; при overflow форма прокручивается и сохраняет видимость активного поля. Иллюстрации e-mail/password скрываются при недостатке высоты. Фото при регистрации остаётся доступным действием внутри прокрутки. Нижняя кнопка остаётся над клавиатурой и на ширине 320 pt. Скрытые условия регистрации не занимают место; заполненное имя рисуется primary, а не placeholder color.

SolidRoundedButtonNode получил отдельный opt-in updateLayout с fontSize: заголовок может переноситься, высота считается по измеренным title/subtitle/icon и уменьшается обратно при снижении масштаба. Прежние вызовы сохраняют фиксированную высоту. Текст, disabled colors, progress и accessibility label используют прежние роли. Дополнительные recovery/reset действия имеют высоту не меньше 44 pt. Divider e-mail центрируется по тексту, а не по ширине боковой линии. Кнопки Apple/Continue переключают и доступность касаний, и VoiceOver одновременно с видимостью; обработчики повторных действий во время progress защищены. Secure password field, серверные сроки сброса и callback-и авторизации сохранены.

Подготовлен //submodules/AuthorizationUI:AuthorizationFormTests: реальный ASScrollNode/UIScrollView, удержание поля в viewport, исчезновение overflow при увеличении высоты, отписка от смены размера текста и рост/перенос/уменьшение CTA. Три XCTest пока NOT RUN. Swift syntax parse новых файлов проходит, UISizing 6 pass, VoiceOver contracts 20 pass.

До записи ожидается: видимые поля и CTA не перекрываются клавиатурой; большой текст переносится без обрезки; активное поле достижимо после смены категории текста; формы прокручиваются только при необходимости; возврат с recovery сохраняет значения; Apple button и Continue не получают касание одновременно. Проверить русский/английский/RTL, iPhone 320/393 pt и iPad, аппаратную и экранную клавиатуру, autofill, progress/error, отсутствие/наличие Terms, добавление фото, Reduce Motion и завершение защищённого reset timer. Нативная визуальная и функциональная приёмка не выполнялась. Телефон и все варианты code entry ещё требуют отдельного прохода.

## Поиск и пустые результаты

Пустые результаты глобального поиска и рекомендации каналов/приложений получили отдельные UIScrollView surfaces. Заголовки/описания используют listsFontSize, цвет и layout обновляются при смене presentation data; декоративная анимация уступает место тексту при недостатке высоты и остаётся статичной в Reduce Motion. Scroll surface скрывается целиком при наличии результатов, чтобы не перекрывать список. Состояние пустых рекомендаций обновляется при каждой транзакции, а не только при первом ready. Верхний отступ учитывает mini player один раз.

CTA поиска публикаций масштабирует текст и высоту, переносит текст запроса на две строки и озвучивает действие/запрос/цену. Для ButtonComponent добавлен opt-in fitToContentHeight; остальные вызовы сохраняют прежнюю высоту. Непрозрачный foreground сохраняет контраст подписи на accent. Завершённый countdown перестаёт обновлять иерархию дважды в секунду; правила оплаты и подтверждения запроса не менялись. Общий footer поиска переносит заголовок и Search in All, учитывает обе боковые safe insets, даёт действию минимум 44 pt и скрывает его при отсутствии callback после reuse.

В очистке GlobalPeerSearchContext исправлена проверка идентичности: currentContext сравнивается с отменённым queryContext, а не queryContext с самим собой. Старый callback не должен удалять контекст нового запроса с тем же ключом. Это проверка логики исходника; сценарий асинхронной повторной подписки ещё требует нативного прогона.

SolidRoundedButtonNode/View теперь показывают notEnabled для accessibility во время progress, не вызывают действие при активном progress и не включают касания из completion старого progress, пока активен новый. Подготовлены нативные регрессии адаптивной высоты ButtonComponent и семантики progress в SolidRoundedButtonNode; NOT RUN. Локально VoiceOver contracts 20 pass, UISizing 6 pass, Swift syntax parse изменённых файлов проходит.

Ожидание перед записью: при открытой клавиатуре пустой текст не уходит под navigation bar; длинное описание и действие доступны прокруткой; при появлении результатов scroll overlay перестаёт перехватывать касания; смена theme/text size обновляет пустое состояние сразу. Проверить recommendations empty/nonempty/empty, быстрые одинаковые запросы и отмену, локальный/глобальный scope, Search in All reuse, filters, downloads, mini player, paid/free/premium search, истечение countdown, RTL/боковые insets и Reduce Motion. Нативной видеоприёмки ещё не было.

## Телефон, вложенный фокус и ввод Unicode

Экран телефона использует scroll form для заголовка, описания, выбора страны/номера и синхронизации контактов. Заголовок/описание/CTA и подпись switch обновляются с системным текстом, подпись switch переносится и озвучивает своё назначение. Passkey link и его обработчик сохранены; сложное attributed description кэшируется по UIFont и состоянию passkey. Форматирование номера, маска, prefix selection и текущий фиксированный размер phone fields не менялись. Следовательно, полный Dynamic Type самого phone input ещё не заявляется.

Вложенное активное поле переводится в координаты scroll content через convert: прежний frame относился к непосредственному родителю. Нативный тест добавлен для этого случая. Reduce Motion переизмеряет формы через системное уведомление; welcome→phone переход не двигает и не масштабирует snapshots при Reduce Motion, декоративная phone/mail/password анимация остаётся неподвижной. В обычном режиме сохраняется прежний переход и typing illustration; иллюстрация скрывается при нехватке высоты.

В word/phrase entry исправлена ошибка NSRange: UIKit передаёт UTF-16, а код использовал диапазон как индексы Characters. Это давало неправильную замену и потенциальный выход за пределы строки при emoji/составных символах. Регрессия до исправления падает на «🇷🇺 тест»; после исправления production delegate проходит девять Unicode/range случаев и пять проверок состояний, не заменяя реальную валидацию слова/фразы.

Embedded progress адаптивной CTA обновляет положение при смене ширины/высоты/цвета и сохраняет диаметр не больше 28 pt. Подготовлен UIKit-тест изменения размера текста во время progress. Новые и изменённые Swift-файлы проходят parse; нативные тесты по-прежнему NOT RUN.

До записи ожидается: country/number/contacts доступны с клавиатурой на 320 pt; фокус вложенного поля остаётся видимым после resize; passkey ссылка работает; подтверждение номера открывается и возвращается к тому же полю/выделению; normal и Reduce Motion welcome-переходы не оставляют snapshots. Проверить завершение intro animation, появление/скрытие клавиатуры, новую/добавляемую учётную запись, country picker, неполный номер и progress/error. Полная раскладка всех code-entry вариантов и phone confirmation ещё ожидает отдельного прохода.

Широкий Linux-прогон на commit 186b357a3e: 43/54 Python-наборов release regression завершились с exit 0. 11 остановились на отсутствующих Apple модулях/API либо несовместимой numeric bridging UserDefaults в Linux (Int вместо Int64). Два assertion failures локализованы к этой bridging-разнице; соответствующие production files не менялись в liquid. Проверки не отключались и не считаются прошедшими. Нужен macOS-прогон.

## Варианты подтверждения кода

Code entry использует scroll form для SMS, другого сеанса, звонка, missed-call, e-mail, Fragment, Firebase, слова и фразы. Заголовок, основное описание, опции и reset text масштабируются; нижние Continue/Fragment/Apple controls резервируют место по фактическим frames. После смены способа подтверждения заново выбираются видимые controls, Fragment title/animation/theme не остаются на Continue, а divider Apple восстанавливается явно. Таймеры, правила предыдущего/следующего способа, masked email/spoiler и серверные сроки не менялись.

Контекстное меню вставки переводит frame кода из scroll content в координаты исходного controller. Hint/error/paste остаются в координатах своего content. Существующие слоты numeric code сохраняют размеры и compact policy; дополнительные подписи hint/paste ещё сохраняют прежний размер 13 pt. Пустое место под вспомогательным текстом не заменяется отключением действия. Next/reset actions имеют минимум 44 pt и переносятся. Декоративная missed-call illustration получает собственный frame, скрывается при нехватке высоты; анимация выбирается при смене content/Reduce Motion, не перезапускается на каждом timer tick. Numeric glyph movement и success scale подавлены в системном Reduce Motion.

Найдена и устранена повторная отправка кода при paste/autofill: updateCode вызывал codeChanged, который уже отправлял полный код, затем отправлял его второй раз. Отправка теперь проходит через один обработчик; busy request блокирует повторную вставку/submit. Проверка production методов воспроизводит двойной submit до исправления и проходит после него для семи способов доставки с incomplete/full/busy состояниями. Действия смены варианта, Apple и reset также проверяют progress перед callback.

Локально проходят все Customization fixtures, UISizing 6 и Swift parse затронутых файлов. Нативная приёмка вариантов входа остаётся NOT RUN. До записи ожидается: переключение Fragment→word→SMS и Apple→обычный код не оставляет старых кнопок; CTA не перекрывает поле при клавиатуре; следующий вариант и reset доступны прокруткой; popup Paste привязан к видимому коду после scroll; один paste вызывает один запрос. Проверить таймер, неверный/верный код, предыдущий способ, pending email reset, auto-fill, Unicode phrase, VoiceOver, RTL и изменение текста во время ввода. Карточка подтверждения телефона и Dynamic Type numeric/phone slots требуют дальнейшей проверки.

## Общие поля настроек

ItemListSingleLineInputItem переносит обычную подпись над вводом при крупном listsFontSize; username/emoji prefixes сохраняют inline-положение. В обычном режиме подпись оставляет место для редактируемого текста. Дополнительный suffix измеряется отдельно и больше не рисуется поверх поля. Высота учитывает подпись, suffix и минимальный target; clear control получает 44 pt и относится к строке ввода, а не к верхней подписи. Шрифт уже введённого текста обновляется вместе с typingAttributes.

Clear visibility теперь зависит от фактического текста UITextField, а не предыдущего immutable item snapshot. Исправлено обратное isAccessibilityElement; очистка видима для VoiceOver, когда доступна, и не изменяет disabled/пустое поле. Clear callback привязан к исходному item при reentrant обновлении. Return/edit callbacks не запускаются у disabled field. Поле получает осмысленную accessibility label; secure entry и модель валидации не заменялись.

Processed paste и username normalization используют Range(NSRange,in:) и UTF-16 caret offsets. Отложенный cursor update не применяется к уже изменившемуся тексту. Новая Foundation fixture исполняет production delegate с небольшими адаптерами text-position/queue: проверяет Unicode paste, составные символы username, normalization, владение queued caret, invalid ranges и disabled/length/validation gates. До исправления регрессия воспроизводится, после — проходит. Это не запуск UIKit.

Добавлены четыре нативных InputRowLayoutTests в существующий SettingsRowLayoutTests target: large labels/suffix, prefix и смена font на переиспользуемом node, clear/disabled states и настоящий UITextField paste/caret. NOT RUN. Все Customization fixtures, 20 VoiceOver contracts, 6 UISizing и parse затронутых Swift-файлов локально проходят.

До записи ожидается: русские подписи не сжимают field до одного символа; suffix не перекрывает значение; при изменении размера текста текст и title масштабируются вместе; username prefix остаётся рядом со slug; очистка доступна VoiceOver и не появляется на disabled/пустом поле. Проверить proxy forms, 2FA/password, редактирование профиля/имени/ссылок, monthly fee suffix, custom emoji prefix, selection/caret, maxLength, formatted paste, смену темы и клавиатуру. Нативной визуальной приёмки ещё не было.

## Локализованные заголовки чатов и звонков

Три animation segment builders (chat title view, chat header component, call status bar) использовали NSRange локализованных аргументов как смещения Characters. При emoji/составных символах строка могла обрезаться или падать. Разбиение теперь использует NSString и UTF-16 length, соответствующие контракту GenerateStrings. Текст, аргументы, segment ids и существующая анимация сохраняются. Неверный порядок квадратных скобок в строке счётчика не образует обратный диапазон удаления.

Новая fixture исполняет реальные блоки трёх builders: до исправления воспроизводится String index out of bounds; после проходят 90 Unicode/order/ending сочетаний и 15 случаев metadata. Это тест строкового построения, не движения UIKit. Branding 32 pass и VoiceOver contracts 20 pass. Для записи ожидается: числовой счётчик и суффикс сохраняют все символы в обычной/пользовательской локализации; изменение числа не создаёт дублированные/пустые сегменты; меню заголовка и переход к звонку работают как раньше. Нативная проверка анимации и call lifecycle пока NOT RUN.

## Ввод в редакторах медиа и стикеров

Тот же UTF-16 контракт применён к числовому/цветовому полю Drawing UI, цветам avatar editor и wallpaper editor, а также title/slug sticker pack. Color validators, uppercase hex, ограничения длины, slug filtering и callback-и сохранены. В sticker slug caret рассчитывается по UTF-16 prefix; queued selection не заменяет более новый текст.

Fixtures расширены исполнением production Drawing delegate (Unicode replacement, invalid boundary, validation callback) и sticker delegate (Unicode title, normalized slug/caret, disabled state, invalid boundary). Они проходят на Linux, как и syntax parse четырёх экранных файлов. Для hex editor проверен общий диапазон ввода и неизменность ветвей валидации; реальный UIKit color selection ещё не запускался. До записи ожидается: ввод/удаление # и hex-цифр обновляют swatch, невалидная вставка не меняет цвет, slider↔hex синхронизированы; sticker title принимает Unicode, slug сохраняет прежнюю фильтрацию/лимит и курсор после вставки. Редакторы всё ещё требуют нативной проверки жестов, клавиатуры и сохранения результата.

## Общая строка поиска

SearchBarNode использует системные magnifyingglass/number/dollarsign/xmark.circle.fill с прежними ресурсами как fallback. У Cancel фактический frame не меньше 44 pt, у clear расширена область касания до 44 pt; editable field резервирует место под неё также во время перехода из placeholder. Clear исключается из accessibility и отключается при скрытии. Keyboard delete для prefix/tokens сохраняет прежний обработчик.

Добавлен SearchBarLayoutTests: реальные hitTest рядом с clear glyph, очистка и её accessibility state для четырёх стилей/трёх ширин, размер Cancel и его callback. Swift parse проходит; UIKit tests NOT RUN на Linux. До записи ожидается: field/clear/Cancel не перехватывают касания друг друга; появление clear не двигает левый край запроса; вход/выход поиска не оставляет двойных иконок. Проверить light/dark, token/prefix deletion, inline navigation, RTL и safe insets. Визуальная приёмка ещё не выполнялась.

## Действия и варианты выбора в настройках

Action rows переносят длинные подписи, выравнивают многострочный текст по назначению действия и учитывают обе safe insets. Checkbox rows переносят title/subtitle, резервируют отдельное место под правую отметку и центрируют текстовую группу по высоте. Обе строки имеют минимум 44 pt. VoiceOver получает subtitle и системный selected trait вместо жёстко заданного английского Selected.

Disabled action больше не выполняется через selected/long press; добавлен отдельный VoiceOver activation с той же проверкой. Disabled checkbox также блокирует VoiceOver, который раньше обходил enabled. Foundation fixture исполняет production selection/activation/long press paths, включая повторное использование: PASS. Добавлены четыре ChoiceRowLayoutTests для actual TextNode layout, safe insets и VoiceOver/reuse; NOT RUN. Swift syntax parse проходит.

До записи ожидается: длинные действия хранения/защиты/уведомлений читаются полностью; отметка не пересекает текст; multiline строки разделены одинаковыми отступами; disabled controls не подсвечиваются и не выполняются. Проверить privacy exceptions, notification tone lists, archive scope, destructive actions и обычные/крупные размеры текста в обеих темах. Нативной приёмки ещё не было.

## История звонков и пустые состояния

Calls empty state перенесён в отдельный ASScrollNode: описание/действие масштабируются с listsFontSize, ограничения в три строки больше нет. При нехватке высоты иллюстрация скрывается, текст и кнопка остаются достижимы прокруткой. Content offset ограничивается после resize. Кнопка целиком является одним accessibility element; скрытый overlay не перехватывает список, скрытый список исключён из VoiceOver. Смена темы/текста/Reduce Motion обновляет экран; illustration playback выбирается только при смене Reduce Motion, still frame вместо loop. Empty-state scope берётся из переданного обновления.

В call rows крупный текст размещает дату под статусом, title допускает две строки, status/date переносятся. Текстовая группа центрируется рядом с аватаром. Reveal offset учитывает обе раскладки даты. Info target расширен до 44 pt и исключён из взаимодействия/VoiceOver в editing; accessibility summary включает дату. Group call Join масштабируется и переносится, строка учитывает фактическую высоту кнопки; title и кнопка разнесены с учётом правого inset. Скрытая Join не доступна VoiceOver. Call routing, delete confirmations и archive protection не менялись.

Production empty-state geometry проходит 192 сочетания viewport/text/button sizes на Foundation. UISizing проверяет реальные выражения адаптивного Join: 6 pass; VoiceOver contracts 20 pass. Customization fixtures проходят. Parse четырёх Swift files проходит; UIKit layout, active-call lifecycle и touch routing на iOS NOT RUN.

До записи ожидается: переход All↔Missed не оставляет пустую поверхность поверх результатов; empty text/button доступны в landscape и при крупном тексте; непрокручиваемое содержимое центрируется; иллюстрация не зациклена в Reduce Motion. История с длинными именами/датами не пересекается с Info/Join; swipe delete, editing, conference avatars и возврат из call info сохраняют позиции. Проверить themes, sidebar/неравные safe insets, активный/завершённый group call, 320/393 pt и iPad, RTL и изменение текста во время scroll. Нативной видеоприёмки ещё не было.

## Контакты, limited access и обновление presentation data

Root controllers Calls/Contacts и ContactsControllerNode больше не отбрасывают изменение listsFontSize/Reduce Motion при прежних теме и языке. ContactListNode передаёт такое обновление в обе ветви списка и помечает существующие rows для повторного layout через allUpdated; stable ids и обычный diff сохраняются. При одном изменении font/motion permission node не пересоздаётся. Fixture исполняет production conditions и настоящий MergeLists: неизменные данные не обновляют строки, font/motion обновляют существующие строки, insert/delete сохраняются — PASS.

Limited-access banner масштабирует описание и Manage, учитывает фактическую высоту кнопки и обе safe insets. При крупном тексте кнопка располагается под описанием, обычная раскладка резервирует её ширину отдельно. Target фактически не меньше 44 pt, label доступен VoiceOver. Contact action rows переносят title/subtitle, tall/alpha больше не принуждают высоту 50 pt, если текста больше. Исправлена позиция leading inline icon: подпись начиналась до правого края значка. Subtitle озвучивается вместе с действием.

UISizing 6 pass, Swift parse семи изменённых/добавленных файлов проходит. Подготовлены два ContactRowLayoutTests через настоящий публичный nodeConfiguredForParams: limited-access description/Manage для 320/393/768 pt и обычного/крупного текста, tall action с inline icon. UIKit tests NOT RUN. До записи ожидается: системная смена размера текста обновляет уже открытые Calls/Contacts и поисковую выдачу без reload аккаунта; scroll position и selection не сбрасываются; limited access Manage не перекрывает описание и открывает прежний системный picker. Проверить allowed/limited/denied permissions, search, alphabet index, invite/add, stories inset, active filters, темы, RTL и боковые safe insets. Нативной приёмки ещё не было.

## Общие action sheets и alerts

Disabled ActionSheetButtonItem теперь блокирует callback во всех путях (touch, keyboard performAction, VoiceOver), а disabled hover не подсвечивает строку. TextAlertContentActionNode.pressed использует уже существующий guarded performAction. Измерение длинных sheet labels не ограничивается остатком высоты группы: группа по-прежнему прокручивает элементы, текст сам не обрезается до текущего viewport. ActionSheetTextItem озвучивает отображённый Markdown без formatting markers; text/button имеют одинаковые боковые отступы 16 pt.

Foundation fixture исполняет реальные методы sheet/alert, включая enabled→disabled→enabled: PASS. Добавлены четыре AlertActionStateTests в DisplayTests: touch/keyboard/VoiceOver и reuse, длинные labels при малом viewport, rendered Markdown. UIKit tests NOT RUN; syntax parse проходит. Дополнительно исправлена фильтрация presentation data у root chat list: смена listsFontSize/Reduce Motion вызывает обновление native header/search/empty content и requestLayout. Проверка presentation delivery расширена на этот controller, PASS.

До записи ожидается: disabled действие не выполняется с VoiceOver/клавиатуры/касания; длинные подтверждения удаления/отправки не обрезаны и доступны scroll; Markdown не дублирует разметку при озвучивании; отмена/подтверждение сохраняют прежние callbacks и focus restoration. Проверить destructive/send/archive/permissions sheets, hardware keyboard, iPad и крупные размеры текста. Отдельно остаётся проверка font scaling: в Display sheet/alert UIFontMetrics применяется поверх theme.baseFontSize из presentation data; менять эту политику без проверки live notifications/manual font preferences пока не стали. Нативной приёмки ещё не было.

## Объяснения системных разрешений

PermissionContentNode использует scroll surface с общей вертикальной раскладкой title/subtitle/body/primary action/privacy/footer. Типографика следует listsFontSize; основной CTA использует настоящий MultilineTextComponent и адаптивную высоту ButtonComponent. Secondary action не меньше 44 pt. Footer больше не скрывается в низком окне, иллюстрация уступает место обязательному содержимому. Учитываются обе боковые safe insets, прокрутка появляется только при overflow, offset ограничивается после resize. VoiceOver order задан в том же порядке, что визуальное содержимое. Theme update сохраняет выбранное выравнивание body.

Permission controller исправляет viewport: высота content frame уменьшается на navigationHeight, уже занятое navigation bar пространство не учитывается второй раз в top inset. Reduce Motion отключает перемещение всего permission screen/смены состояния и использует still frame для illustration. В обычном режиме прежние переходы остаются. Изменения font/motion передаются от root controller и уже открытому placeholder контактов. Requests/allow/skip/privacy callbacks и состояние OS permissions не менялись. FilterHitTest сохраняет pass-through на пустой непрокручиваемой поверхности; overflow surface принимает scroll.

Production geometry проходит 800 сочетаний viewport/text/subtitle/privacy/footer; presentation-delivery fixture расширена на PermissionController, PASS. Swift parse затронутых файлов и 20 VoiceOver contracts проходят. Реальные системные диалоги, callback lifecycle, нативный scroll/hitTest и ButtonComponent rendering NOT RUN. До записи ожидается: все тексты/CTA/footer достижимы на 320 pt и в landscape; иллюстрация не отнимает место у текста; primary→secondary→footer читаются VoiceOver по порядку; смена текста/Reduce Motion не теряет текущий permission step. Проверить contacts allowed/limited/denied, notifications, location/custom permission content, Privacy policy, Skip/Allow, RTL, iPad/safe insets и возврат из Settings. Нативной видеоприёмки ещё не было.

## Локальная контрольная точка a02a9f17a1

Обновлён qa/native/validation.json с исходным SHA каждого прогона. На этой версии: Branding 32, glass bubbles 14, VoiceOver contracts 20 и UISizing 6 pass; все Customization fixtures проходят, включая 192 calls и 800 permissions geometry combinations. 83 изменённых Swift files относительно main проходят syntax parse. Это не проверка UIKit API/types.

40 новых нативных test methods в шести targets подготовлены, но не выполнялись. Более ранний широкий прогон 54 command groups на 186b357a3e сохранён отдельно с исходными логами: 43 pass / 11 failures на Linux. Mac-only API и numeric bridging failures не скрыты. Сборка текущего HEAD, Simulator/video acceptance и полнота всех экранов остаются NOT RUN/IN PROGRESS; main, push, CI и релиз этим проходом не изменялись.

Menu group layout дополнительно резервирует видимую область для каждой группы. Длинная нижняя группа больше не оставляет верхнюю с нулевой высотой; внутри группы custom items не получают отрицательную constrained height. На обычном коротком Cancel свободное место по-прежнему получает основная группа. Production height budget проходит 75 height/count/tall-group сочетаний. Добавлен нативный test двух групп с длинным Cancel (NOT RUN). Для записи дополнительно проверить достижимость обеих групп при AX text sizes и малом viewport, отсутствие вложенного scroll конфликта, а также unchanged обычный короткий sheet. Native test methods подготовлены: 41.

## Медиапикер: доступ к Фото и запрет отправки

MediaPickerPlaceholderNode теперь использует общий EmptyStateIndicatorComponent: длинные тексты/действия, крупный текст, overflow scroll и Reduce Motion следуют тем же правилам, что остальные пустые экраны. Убраны отрицательные top offsets -60/-160 pt и фиксированная ширина CTA 248 pt; viewport учитывает navigation bar и safe insets. Второе действие камеры остаётся отдельной текстовой кнопкой. Photos сохраняет loop, Banned — once: для общего компонента добавлен opt-in animationIsLooping с прежним default для других callers.

Содержимое передаётся при каждом update, поэтому переиспользуемый placeholder обновляет denied↔restricted тексты и действия. Settings/camera/boost callbacks назначаются на каждом соответствующем проходе, а не только при создании node. Restricted placeholder имеет приоритет над intro доступа к Фото; camera handler дополнительно проверяет intro/hasCamera, boost — canBoost. Существующие server-side rights, разрешения OS и отправка медиа не менялись. Изменения font/motion доходят через MediaPickerScreen presentation update.

Foundation fixture проверяет production handlers на повторно используемом node и условие приоритета restriction: PASS. Presentation-delivery fixture расширена на MediaPickerScreen, PASS. Swift parse трёх файлов проходит; реальная фото-библиотека, камера, смена permission state и rendering общего component NOT RUN. До записи ожидается: denied→allowed/restricted и обратно не оставляет старых кнопок; запрет медиа не предлагает камеру; Boost доступен только по canBoost; 320 pt/landscape/крупный текст не обрезают описание; открытие Settings/Camera и возврат сохраняют корректное состояние picker. Проверить story/sticker/avatar subjects, limited access, ban expiry, canBoost update, themes и Reduce Motion. Нативной приёмки ещё не было.

## Геолокация при закрытом доступе

LocationPlaceholderNode использует тот же EmptyStateIndicatorComponent, что медиапикер: масштабируемые title/body/CTA, overflow scroll, безопасные отступы и Reduce Motion. Убраны отрицательные top offsets и расчёт места под несуществующую camera button. Callback Open Settings сохранён; Location loop продолжает работать в обычном режиме.

LocationPickerController принимал presentation updates только при смене темы; теперь также принимает язык, listsFontSize и Reduce Motion. Controller node переизмеряет текущую раскладку и обновляет существующие venue/action rows при font/motion change, сохраняя stable ids и diff. Поиск мест, координаты, live location и отправка не менялись. Production delivery condition проходит fixture; syntax parse трёх файлов проходит. Real permission prompt, карта, venue search/selection, Open Settings→return и нативная отрисовка NOT RUN.

До записи ожидается: denied placeholder не уходит под navigation bar/home indicator; Open Settings доступен с крупным текстом/в landscape; возвращение к разрешённой карте убирает overlay; смена языка обновляет подписи без смены темы; selection/search не теряются при font-only update. Проверить precise/reduced accuracy, live location, manual pin, business location, venues loading/empty/error, темы и RTL. Нативной приёмки ещё не было.

## Локальная контрольная точка 71fe9d593f

После прохода медиапикера/геолокации и group height budget повторно проходят Branding 32, glass bubbles 14, VoiceOver contracts 20, UISizing 6 и все Customization fixtures. Изменённых Swift files относительно main: 90, syntax parse без ошибок. Нативных test methods подготовлено 41; их выполнение и iOS build по-прежнему NOT RUN. Более ранние 54 regression groups не выдаются за прогон текущего HEAD. Полный редизайн и визуальная приёмка всех экранов не завершены. Из сохранённых compiler logs убраны только trailing spaces, raw SHA-256 отмечен в metadata; диагностическое содержимое сохранено.

## Профиль, прокси, vault и story peer rows

Шапка профиля: Message/Add получают высоту не меньше 44 pt, подписи кнопок масштабируются с listsFontSize и переносятся. Caption у круглых действий (message/call/video/…) тоже масштабируется и может занять две строки при крупном тексте. PeerInfo rows (header/comment/contact/encryption key/labeled value/address/info) используют `PresentationLayoutMetrics` и размер системного текста; контактные username/phone при крупном тексте складываются вертикально.

Список прокси: server rows берут fontSize из presentation data, переносят длинный host/status, считают высоту по тексту и расширяют info target. Action rows и browser exception rows переносят заголовки и держат минимум 44 pt. Expandable switch и text-with-label в ItemListUI следуют тем же правилам.

Passcode Cancel/Delete и mode button используют минимум 44 pt. Story/peer list rows масштабируют title/subtitle и не опускаются ниже interactive size. Branding Liquid contrast: 7 pass. Нативная приёмка и Simulator по-прежнему NOT RUN.

## ItemList, настройки, Premium, storage и poll

Оставшиеся ItemList rows (action/switch/placeholder/section header/multiline и single-line input) берут `PresentationLayoutMetrics` для горизонтальных inset и минимума 44 pt; заголовки секций и подписи переносятся при крупном тексте. AccountOrder и соседние peer rows (`ItemListPeerItem`) при крупном тексте переносят title/status/label и не опускаются ниже interactive size.

Premium option rows и CTA на PremiumIntro масштабируются с `listsFontSize`, а ListAction rows держат минимум 44/52 pt. Storage usage: заголовок, описание, Edit/Done, clear button, peer/file/category labels идут через Dynamic Type; peer rows расширяются по тексту. Compose poll option fields читают `listsFontSize` из presentation data и держат минимум interactive height. Theme font/brightness sliders и Recent Sessions header button тоже на метриках. Нативная приёмка по-прежнему NOT RUN.

## Пустые чаты и поиск в группах

`ChatEmptyNode` (обычный/secret/group/cloud/topic/greeting/premium-required и intro footer) масштабирует title/body от `interfaceState.fontSize.baseDisplaySize` и обновляет текст при смене размера шрифта. Group/discussion search navigation bars держат close/search hit targets на `PresentationLayoutMetrics.minimumInteractiveSize` и боковые inset на `listHorizontalInset`. Attachment file empty и EntityKeyboard empty search тоже на Dynamic Type. Branding Liquid: 7 pass. Simulator/видеоприёмка NOT RUN.

## Privacy, story sheets и appearance chrome

Privacy intro и Recent Session sheet масштабируют тексты/CTA от listsFontSize и держат interactive минимум. Story quality/stealth sheets и StoryActions hit targets на PresentationLayoutMetrics. Theme accent/app icon/theme grid/text size slider и wallpaper gallery top chrome — те же inset/height. MessagePriceItem принимает fontSize и масштабирует price/unlock. Branding Liquid: 7 pass. Simulator NOT RUN.

## Sessions, contacts, sticker search и папки

Recent Sessions/Website rows, ContactsPeerItem, ItemListPeerActionItem, Settings search rows, ChatList filter preset/category/title items и sticker/GIF PaneSearchContainer используют PresentationLayoutMetrics и Dynamic Type. Avatar/row floors clamp к minimumInteractiveSize. Branding Liquid: 7 pass. Simulator NOT RUN.

## Invite links, stats, contacts actions и PeerInfo edit

ItemListAddress, InviteLinks rows, Statistics stars/message/balance, ContactList action/limited permission, BotCheckout tip/price, DatePicker, ChatNewThreadInfo, CommandMenu, ListMessage extracted rects — на PresentationLayoutMetrics. PeerInfo header editing/notes/multiline fields, Group sticker search, Attachment file search, SearchInputPanel и ListMultilineTextField — Dynamic Type. Branding Liquid: 7 pass. Simulator NOT RUN.

## Auth, calls, navigation bar floors

Authorization sequence fields/actions, CallList rows/empty state, ChatList hole search CTA, Permission privacy target, NavigationBar/NavigationButton hit floors, StorageUsage nav buttons и Wallet header hit targets используют `PresentationLayoutMetrics.minimumInteractiveSize`. Branding Liquid: 7 pass. Simulator NOT RUN.

## New contact, gifts, schedule и translation menu

PhoneInputItem принимает listsFontSize; Gift auction/value/bid, ForumCreateTopic, ChatScheduleTime и TranslationLanguages menu масштабируют основные 17 pt labels. Branding Liquid: 7 pass. Simulator NOT RUN.

## Message input, stars, wallpaper color, text processing

MessageInputPanel, NavigationSearch, Stars withdrawal/transactions, WallpaperColorPanel, QuickReplySetup, TextProcessing (+ language selection), EmojiGameStake, Avatar ColorPicker, CreateBot/CommunityEdit, ChatFolderLink preview items и CreateExternalMediaStream масштабируют основные labels от listsFontSize. Branding Liquid: 7 pass. Simulator NOT RUN.

## Share, passkeys, media editor и context menu

ShareWithPeers/Share panels, PeerSelection, Passkeys, BusinessMessage setup, MiniApp list, MediaRecording/MediaEditor/CreateLink, ListTextField, Emoji search bar/header, ContextMenu action fonts (через Controllers arguments), Wallet send/transfer и slowmode placeholder масштабируются от listsFontSize. Branding Liquid: 7 pass. Simulator NOT RUN.

## Share input, prompts, payments, polls bubble и QrStudio

ShareInputField, PromptController, TipEdit, 2FA input, PaymentCard, LegacyDataImportSplash, ChatMessageReport panel, poll bubble labels, ChatScheduleTime node, Toolbar, ActionPanel, Alert input fields, Undo overlay, QrStudio buttons, Gift store/demo/options, JoinAffiliate, LocationMapHeader, AuthConfirmation и related panels масштабируют 17 pt labels. Branding Liquid: 7 pass. Simulator NOT RUN.

## Passport, SearchBar, gallery footer и passcode setup

Passport phone/scan forms, SearchBarNode contentFontSize, AvatarGallery footer, PasscodeSetup labels, JoinLink preview, ItemListSingleLine/Address fonts, InviteLink viewer, external file gallery, Drawing toolbar, ChatImport, Browser address bar, Authorization phone/code fonts, VoiceChat recording/stage, StickerPeek, TextSizeSelection и Tooltip масштабируют 17 pt labels. Branding Liquid: 7 pass. Simulator NOT RUN.
