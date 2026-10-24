# Профиль как дорожный журнал

Обложка и журнал собраны по согласованному build brief от 23 октября 2026.
Сервер, API DTO и схема Core Data не менялись.

- `ProfileHeroCard` и `ProfileCoverPager`: фото в синхронизированном порядке,
  счётчик, просмотрщик с выбором обложки, удалением и добавлением. Без фото —
  прежний герой и своя строка добавления. Страницы просмотрщика заморожены
  атомарно внутри presentation item.
- Машина — прежний `VehicleStage`, выровненный низом на границе обложки.
  Под ним паспортная строка, человек, bio и числа. Платный фон сохранён.
- У заполненного «Я» вход стал одной строкой. Далее прежний disclosure,
  подсказки путешествий, черновики, поиск, календарь и журнал.
- Закрепления — первые карточки журнала. Отдельных «Фото» и «Витрины» нет.
  Неизвестные этому телефону закрепления по-прежнему можно снять строкой
  `profile_showcase_unpin_elsewhere`.
- Главы по месяцу старта: исходные расстояния, число поездок и уникальные
  регионы. Закрепления входят в итог месяца, но не повторяются в главе.
- Только `HistoryFolding` скрывает строки: путешествия и повторяющиеся
  поездки. Повторы определяются geohash-6 концов превью в любую сторону,
  отдельно за месяц, минимум три подходящие поездки на пару ячеек. Фото,
  отметки, описание, закрепление, путешествие, черновик и незавершённая
  запись исключают поездку. Все повторы месяца — одна раскрываемая строка,
  семь поездок и «Ещё N»; каждая открывает обычный экран поездки.
- Подготовка глав, повторов, сумм, исторических уровней и словарей чужих
  карточек выполняется вне главного актёра, с защитой от устаревшего ответа.
  Поиск раскрывает совпадения; календарь и сетка сохраняют исходные поездки.
- В чужом профиле подписчики находятся в герое, follow — рядом с именем,
  разделы — одной строкой. Гараж появляется только при нескольких машинах.
  Закрепления не повторяют имя автора. У обычных публичных карточек сохранены
  прежние реакции, комментарии, жалоба и действие «Поделиться».
- При прокрутке обложки часы получают сплошную подложку; у чужого профиля
  возвращается обычная фиксированная навигация с кнопкой «Назад».
- Новые слова переведены на все 13 языков. Расстояния — через `Measure`,
  существительные с числами — через CLDR helpers.

## Проверка

- Полный `-only-testing:TripTrackTests`: **3066 / 0 / 1**
  (всего / ошибок / пропущено), 3065 прошли. Все 12 новых тестов журнала,
  `PreparedProfileHistoryTests` и `LocalizationTests` зелёные.
  Единственный пропуск — существующий `TripDetailMapScopeTests`, которому
  нужен отдельный API URL override; окружение задачи не менялось.
- `ProfileCardShotTests`: **5 / 0 / 0**. Светлая и тёмная обложка,
  просмотрщик и его счётчик, выбор обложки, вариант без фото, закрепления,
  семь строк повторов, «Ещё N» и открытие поездки.
- `GarageProfileShotTests`: **4 / 0 / 0**. Все существующие проверки
  DRIVE2, чужой машины, сохранения доработок, покрытия, тегов и площадки.
- Дополнительный прогон своего просмотрщика и повторов: **2 / 0 / 0**,
  включая настоящий переход из «Добавить фото» в нативный Photos picker.
- Дополнительные чужой профиль и журнал: **2 / 0 / 0**, с финальной
  подложкой часов, навигацией при прокрутке и десятью новыми поездками сида.
- Финальный прогон раскрытия и точного кадрирования журнала: **1 / 0 / 0**.
- Первый диагностический unit-прогон дал два срабатывания в одном
  существующем Metal budget test. После очистки контейнера два полных
  прогона подряд прошли без ошибок; сам тест и его бюджеты не менялись.
- Первый UI-прогон нашёл пустые страницы при открытии просмотрщика и
  неверное ожидание фиксированного числа повторов в тесте. Исправлены
  presentation item и проверка согласованности показанного количества.
  Один промежуточный прогон остановлен для выравнивания SUV с обложкой.
- `PublicProfileFindsShotTests` и `TabBarNavigationTests` не менялись и
  не запускались: их известные исходные падения оставлены вне задачи.

Артефакты: `build/units-verified.xcresult`, `build/ui-verified.xcresult`,
`build/ui-flow.xcresult`, `build/ui-captures.xcresult`, `build/ui-shots.xcresult`.

Сохранённые PNG: `profile-own-first-light.png`, `profile-own-first-dark.png`,
`profile-own-without-photos.png`, `profile-journal-folded.png`,
`profile-journal-expanded.png`, `profile-foreign-first.png`,
`profile-foreign-pinned.png` — в согласованном каталоге `me-review/build/`.
Симулятор: `CD72CE0D-9D57-4426-A225-CEC9E024ACE8`, iOS 18.6;
один `xcodebuild`, `-jobs 4`, выключение после каждого прогона.

## Границы сравнения с HTML

- В демо четыре своих и пять чужих цветных JPEG. Пейзаж из HTML был
  иллюстрацией макета; он не добавлен в пользовательскую библиотеку.
- Суммы и число повторов берутся из настоящей демо-библиотеки, а не из
  чисел макета. Тестовые десять поездок объединяются и с подходящими
  исходными поездками месяца.
- Плитки MapKit на симуляторе недоступны: остаётся существующий fallback
  карты с настоящей линией маршрута. Статическая карта из HTML не копируется.
- Сохранены настоящая текстура выбранного PRO-фона, пиксельный LVL и
  существующий таб-бар. Вход PRO по-прежнему зависит от storefront.
- Итоги главы идут второй строкой по build brief, хотя HTML показывает их
  рядом с месяцем.
- У публичного DTO нет отметок: такие поездки никогда не считаются
  повторяющимися, как требует правило неизвестных полей. Итоги чужих глав
  охватывают загруженные публичные страницы и обновляются при пагинации.

## Изменённые файлы

- `CLAUDE.md`
- `TripTrack/Localization/AppStrings+ProfileJournal.swift`
- `TripTrack/Localization/Translations/Translations+DE.swift`
- `TripTrack/Localization/Translations/Translations+ES.swift`
- `TripTrack/Localization/Translations/Translations+FIL.swift`
- `TripTrack/Localization/Translations/Translations+FR.swift`
- `TripTrack/Localization/Translations/Translations+ID.swift`
- `TripTrack/Localization/Translations/Translations+IT.swift`
- `TripTrack/Localization/Translations/Translations+KK.swift`
- `TripTrack/Localization/Translations/Translations+PL.swift`
- `TripTrack/Localization/Translations/Translations+PT.swift`
- `TripTrack/Localization/Translations/Translations+TR.swift`
- `TripTrack/Localization/Translations/Translations+UK.swift`
- `TripTrack/Models/HistoryFolding.swift`
- `TripTrack/Models/PreparedProfileHistory.swift`
- `TripTrack/Models/ProfileHistoryMonth.swift`
- `TripTrack/Models/ProfileRoutineTrips.swift`
- `TripTrack/Services/DebugProfileCardSeed.swift`
- `TripTrack/Views/Profile/ProfileCoverPager.swift`
- `TripTrack/Views/Profile/ProfileCoverScrollProbe.swift`
- `TripTrack/Views/Profile/ProfileGarageHeader.swift`
- `TripTrack/Views/Profile/ProfileHeroCard.swift`
- `TripTrack/Views/Profile/ProfileHistoryMonthHeader.swift`
- `TripTrack/Views/Profile/ProfilePhotoThumbnail.swift`
- `TripTrack/Views/Profile/ProfilePhotosCard.swift`
- `TripTrack/Views/Profile/ProfileRoutineTripsView.swift`
- `TripTrack/Views/Profile/ProfileTripCardView.swift`
- `TripTrack/Views/Profile/ProfileView.swift`
- `TripTrack/Views/Social/PublicProfileView.swift`
- `TripTrack/Views/Trips/PhotoFullScreenView.swift`
- `TripTrackTests/ProfileMonthlyJournalTests.swift`
- `TripTrackUITests/ProfileCardShotTests.swift`
- `docs/releases/0.9.1/profile-journal.md`
