# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# First-time setup
cp Local.xcconfig.example Local.xcconfig  # set PRODUCT_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM
brew install xcodegen
xcodegen generate
open TripTrack.xcodeproj
# Xcode → select device → Cmd+R

# Regenerate after adding/removing files
xcodegen generate

# Build from CLI
xcodebuild build -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'
```

Build config lives in `project.yml` (xcodegen). Local signing in `Local.xcconfig` (gitignored).

## Architecture

**MVVM + Service Layer**, fully native (no external dependencies).

- **Models** — data structures: `Trip`, `TrackPoint`, `Vehicle`, `Badge`, `TripPhoto`
- **ViewModels** — `@ObservableObject` with `@Published`: `MapViewModel` (recording, map state), `FeedViewModel` (trip list, filtering, pagination)
- **Services** — singletons with business logic: `TripManager` (CRUD via TripRepository, geocoding, batch saves), `LocationManager` (dual-mode GPS/simulated), `GamificationManager` (badges, XP, levels), `SmoothTrackManager` (Kalman filter), `SyncQueue` (pending sync operations)
- **Persistence** — `PersistenceController.shared` (CoreData), `TripRepository` protocol (CRUD abstraction), photos in Documents directory
- **Views** — SwiftUI, organized by feature in subdirectories under `Views/`

**Data flow**: Views → ViewModels (@Published) → Services → TripRepository → CoreData

**Location tracking** uses Provider pattern: `LocationProvider` protocol → `RealGPSProvider` (CoreLocation) + `SimulatedLocationProvider` (dev joystick). LocationManager switches between them.

### Отметки на маршруте и фото на карте (0.6.5)

«Сколько времени и километров до этой точки» — вопрос из машины, и отвечать на
него можно стало только с плотным треком: на пятиметровых точках ответ был бы с
погрешностью в полквартала.

- **Считает `TripRouteLocator`, и только он.** Три входа — палец по карте,
  кнопка на ходу, время съёмки фотографии — дают одну и ту же `Fix`. Километры
  внутри набираются тем же пятиметровым шагом, что и одометр
  (`distancePrefix`), иначе «до моря 143 км» разошлось бы с «всего 210 км».
- **`passes(near:)` возвращает СПИСОК, а не один ответ.** Дорога «туда и
  обратно» рисуется по одним улицам, палец попадает в оба проезда, и геометрия
  их не различает — различает время. Выбирать за человека нельзя.
- **Живая отметка берёт километры из `entity.distance`**, а не пересчитывает по
  точкам: он уже посчитан правильным шагом и по определению сходится с итогом.
- **`placeId` у отметки всегда `nil`** — задел под «место», которое узнаётся на
  каждой поездке. Заполнять его в 0.6.5 нечем и не нужно.
- **Фото на карте: сначала координата из кадра, потом время съёмки и трек,
  потом ничего** (`TripPhotoPlacement`). Третий случай — решение, а не
  недоделка: у снимков до 0.6.5 есть только время ПОПАДАНИЯ в базу, которое
  отличается от съёмки на дни. Ставить по нему — увезти кадр за сотню
  километров от места съёмки.
- **Синк отметок — внутри поездки** (`TripSyncPayload.checkpoints`), список
  целиком заменяет прежний на сервере. Ключ отсутствует — старый сервер/клиент,
  локальное не трогать. У фото в проводе `capturedAt`/`exifLatitude`/
  `exifLongitude` — опциональны в обе стороны; локальные значения точнее
  серверных и не перезаписываются.
- **Связь снимков с отметками ВЫВОДИТСЯ, а не хранится** (`TripCheckpointPhotos`):
  по времени съёмки в окне ±15 мин, иначе по координате кадра в 300 м; каждый
  снимок — одной отметке. Рукой хранятся только `photoIds` (прикреплённые, в
  порядке прикрепления, JSON в `photoIdsJSON`) и `photoId` (обложка); они
  забирают снимки раньше автоматики. Порядок на полке: обложка → прикреплённые →
  по времени. Предела по числу нет — везде обложка и «+N». Старые поездки
  получают связь бесплатно.
- **Маркер на карте**: кружок на герое (`.compact`), карточка с подписью на
  полном экране (`.labelled`). Подпись и миниатюру готовит экран — карта про
  `TripCheckpoint` не знает. Нажатие на маркер карта только сообщает
  (`onCheckpointTap`), карточку внизу рисует `FullscreenMapSheet`; та же
  карточка показывается, пока реплей стоит на отметке (`engine.holdingIndex`).
- **Правка отметки = правка поездки.** Репозиторий взводит `pendingUpload`
  (`markCheckpointsChanged`), `TripManager` ставит поездку в очередь синка.
  Без этого отметка живёт до первого pull: сервер вернёт список без неё и
  «заменит целиком». Держит `CheckpointSyncFlagTests`.
- **Имя по умолчанию не хранится.** В базе у отметки `name == nil`, «Отметка 2»
  собирается при показе по номеру во времени (`TripMoments`) — иначе номер в
  базе разошёлся бы с порядком и с языком телефона, а геокодер не отличил бы
  «Отметка 2» от имени, данного рукой.
- **Лента «Моменты»** (`TripMomentsTimeline`) собирается из `TripMoments.build`:
  отметки по времени + стопки свободных снимков (то же окно 15 мин, что у
  связи снимок↔отметка). Экран считает `PlacedPhoto` через `placement(ofPhoto:)`,
  лента про трек не знает. Показывается у КАЖДОЙ своей поездки, и пустой тоже
  (старт → финиш): решение владельца, не забытый `if`.
- Метаданные снимка забираются в `TripPhotoPicker` из `PHAsset` и больше нигде:
  после выхода из пикера остаётся файл в Documents, из которого ни времени, ни
  места уже не достать.

### Путешествие (0.6.6)

«Краснодар → Владикавказ → Тбилиси и обратно» — в базе четыре записи, в жизни
одна история. `Journey` — окно дат поверх своих поездок, не контейнер и не
второй трек.

- **Членство — по окну дат, а не по списку.** Поездка попадает в путешествие,
  если её `startDate` внутри `[startDate, endDate]` минус `excludedTripIds`. У
  `Trip` нет `journeyId`, у `Journey` нет `tripIds` — синхронизировать два
  списка друг с другом не с чем, а поездка, которая доедет с другого телефона
  позже, попадёт в путешествие сама.
- **`JourneyEntity` без связей** — как `VehiclePhotoEntity`. Каскад от
  `TripEntity` её не заберёт: удаление аккаунта и `LocalDataWipe` называют её
  явно.
- **Окна не пересекаются.** Проверяется и при создании, и при правке дат —
  поэтому правка одного имени НЕ имеет права сдвинуть границы, если человек
  не трогал сами даты (см. фикс в `JourneyEditSheet`: сравнение по дню, а не
  безусловная перезапись).
- **Итоги — только из `JourneyAggregate`, на лету.** Километры, дни, время в
  пути, регионы нигде не хранятся дважды. Считаешь что-то по плечам путешествия
  своим циклом — значит уже дублируешь `JourneyAggregate.build`, и однажды эти
  два счёта разойдутся, как одометр до `TripDistanceGate`.
- **Отметки остаются в своих поездках.** «От старта» у отметки — от старта её
  плеча. Сквозной нумерации через всё путешествие нет и не будет: она ничего
  не отвечает человеку, который открыл путешествие через полгода.
- **`HistoryFolding` — единственное место, где плечо путешествия прячется из
  списка.** В «Статистике» и в социальной ленте поездки живут как жили;
  схлопывание в одну карточку — только в «Мои», и только там.
- **Местная поездка = оба конца в 30 км от ночёвки.** Так она сворачивается в
  строку «Тбилиси · 5 поездок по городу» на экране путешествия; в плитке
  «поездок» считаются плечи дороги, местные — нет.
- **Подсказка — только «ночь не дома».** Расстояние без ночёвки вне обычной
  среды даёт ложные путешествия из дальних коммьютов (это ошибка Apple Trips,
  повторять её не надо). Дом выводится из истории и спрашивается «Это твой
  дом?» ровно один раз — второй раз он либо уже известен, либо человек его не
  подтвердил, и спрашивать заново — не эмпатия, а надоедливость. И сама
  подсказка НИЧЕГО не создаёт: она открывает тот же лист объединения с уже
  отмеченными поездками. Путешествие в этой версии заводит только человек —
  черновик, появившийся сам, пришлось бы разбирать, а это плата вниманием.
- **Синк — как у машины: личные данные, без Cloud Sync не уезжают с телефона.**
  `applyRemoteJourney` не перезаписывает `pendingUpload` — та же защита, что у
  `applyRemoteVehicle`: локальная правка, ещё не улетевшая на сервер, не
  теряется от входящего pull.
- **`allowsPlayback: false` на карте путешествия.** Склейка плеч — не маршрут:
  между городами в ней пустота, и реплей провёл бы машинку по ней напрямик.
  Реплей живёт у поездки, не у путешествия.

### Ловушки, на которые уходит по часу

- **После добавления версии модели `xcodegen generate` надо запустить ДВАЖДЫ.**
  Первый прогон переписывает `.xccurrentversion` на прежнюю версию (в проекте
  ещё нет новой), второй уважает файл. Проверять после генерации: без этого
  собирается СТАРАЯ схема, а ошибка выглядит как «сущность не найдена».
- **`TripDetailView.body` уперся в предел вывода типов SwiftUI.** Цепочка
  модификаторов перевалила за три десятка, и компилятор начал падать по
  таймауту в случайном месте, а не там, где добавили строку. Тело разрезано на
  `tripDetailStage` + `tripDetailBody`; крупные выражения вынесены в методы.
  Добавляешь модификатор — режь дальше, а не гоняйся за сообщением.

## CoreData Schema (versioned, v12 — 0.6.6)

`TripEntity` is central, with cascade relationships to `TrackPointEntity` and `TripPhotoEntity`. Also: `TripCheckpointEntity` (0.6.5), `JourneyEntity` (0.6.6, no relationships — see below), `VehicleEntity`, `VehiclePhotoEntity` (0.6.4), `UserSettingsEntity`, `VisitedGeohashEntity`, `GeocodeCacheEntity`, `RoadEntity`. Schema at `TripTrack/Persistence/TripTrack.xcdatamodeld/` (v1 = baseline, v12 = current; v10 существовала только в dev-сборках 0.6.5 и добавила отметки, v11 — прикреплённые снимки `photoIdsJSON`, v12 — `JourneyEntity`).

**Внимание:** `VehiclePhotoEntity` связи с машиной НЕ имеет — `vehicleId` это
обычный атрибут. Значит каскад её не заберёт: удаление машины и стирание
аккаунта обязаны называть её явно (см. `LocalDataWipe` и `deleteVehicle`).

**Sync-readiness fields (v2):** `userId`, `serverCreatedAt`, `conflictVersion` on TripEntity; `remoteURL`, `uploadStatus` on TripPhotoEntity; `userId` on VehicleEntity. All models (`Trip`, `TrackPoint`, `TripPhoto`, `Vehicle`) are `Codable` for JSON API serialization.

## Key Patterns

- **Batch saves**: location points batched (10 points or 15s interval) via TripManager
- **Async CoreData**: `PersistenceController.saveAsync()` for non-blocking writes from location callbacks
- **Binary polylines**: `Trip.encodePolyline/decodePolyline` for compact route storage
- **Geohashing**: `GeohashEncoder` + `VisitedGeohashEntity` for territory tracking
- **Junk trip filtering**: auto-delete trips <500m AND <2min
- **Repository pattern**: `TripRepository` protocol abstracts CoreData CRUD; `TripManager` delegates to `CoreDataTripRepository`
- **Sync queue**: `SyncQueue` (@MainActor) with deduplication, priority ordering, exponential backoff retry, `SyncTransport` protocol for future API client
- **Soft delete**: `SyncStatus.pendingDelete` hides trips from UI; physical delete after server confirms
- **User identity**: `SettingsManager.localUserId` (UUID) stamped on all entities, prepared for Sign in with Apple
- **UI modifiers**: `.surfaceCard()`, `.glassBackground()`, `.glassPill()` for consistent card styling

### Поездку на паузе не завершает никто (0.6.5)

Пауза — самое сильное «я остановился нарочно», какое человек может дать: датчик
знает только про зажигание, а пауза знает про намерение. Ни один режим и ни одно
стечение датчиков не имеет права закрыть такую запись.

Правило было записано в комментариях и соблюдалось в ДВУХ дверях из четырёх:
`updateMovementForInactivity` и `recoverStaleTripIfNeeded` паузу проверяли,
`handleDeviceDisconnected` и сам `autoStopTrip` — нет. Через третью дверь оно и
вышло: остановка у магазина рвала поездку надвое.

- Решение по отключению магнитолы живёт в `AutoTripPolicy.onBluetoothDisconnect`
  — чистой функцией, чтобы правило проверялось тестом, а не поездкой. Пишешь
  новый путь к завершению — веди его туда же.
- `autoStopTrip(trigger:)` — последний рубеж. `.automatic` на паузе не работает,
  `.userAction` работает всегда: «Завершить» из уведомления жмёт человек, и
  отказать ему значило бы поменять одну поломку на другую.
- `togglePause` зовёт `AutoTripService.handleManualPause()`, иначе таймер,
  заведённый ДО паузы, продолжит тикать.
- **`.remind` не завершает поездку сам.** Режим называется «напоминания»:
  спросили — ждём ответа. И текст уведомления не обещает автозавершения, когда
  его не будет (`notifTripStopBody(minutes: nil)`).

Держит это `AutoStopOnPauseTests`. Половина тестов там — про то, что режим
«полная автоматика» не изменился.

### Форма трека и километры — разные вопросы (0.6.5)

Точки пишутся часто, чтобы во дворе был виден каждый манёвр. Километры при этом
считаются по-старому. Два счёта, два якоря в `TripManager`:

- `lastLocation` — форма. Двигается часто: секунда ИЛИ поворот на 12°, при
  смещении от метра и не чаще трёх раз в секунду. Прежнее пятиметровое правило
  осталось первой строкой проверки, поэтому новое строго ШИРЕ старого: потерять
  точку запись не может, только добавить.
- `lastDistanceLocation` — километры. Двигается пятью метрами, с прежней защитой
  от дрейфа и `TripDistanceGate.isPlausibleSegment`.

**Порог «машина едет» спрашивает СЫРУЮ скорость GPS, а не оценку фильтра.**
Оценка Калмана на стоянке гуляет от шума позиции до полуметра в секунду, и порог
по ней пришлось бы поднять до 1 м/с — то есть отрезать парковку задним ходом на
3 км/ч. Доплер у стоящей машины честно ноль. Когда GPS скорости не знает,
правило не срабатывает и остаётся прежнее пятиметровое.

**Расстояние считает `TripDistanceGate.totalDistance`, и только оно.** Четыре
места набирали километры своим циклом «каждая точка минус предыдущая»: запись,
`updateEntityStats`, `PostTripTrackProcessor.recalculateStats` и
`Trip.movementSplit`. Причём две последние ПЕРЕЗАПИСЫВАЮТ то, что набрала запись.
Пока точки лежали в пяти метрах, четыре копии давали одно и то же; на плотных
точках они расходятся, и побеждает та, что отработала последней. Пишешь новый
подсчёт пути — зови общую функцию, иначе одометр поедет не там, где его сторожат.

Проверяется это `TrackFidelityTests`, где половина тестов — про то, что цифры НЕ
изменились. Меняешь пороги — гоняй их: они держат оба края (стоящая машина
молчит, парковка на 3 км/ч пишется).

**Не возвращай `distanceFilter` в режим записи.** С iOS 16.4 приложение, которое
просит и `startUpdatingLocation`, и `startMonitoringSignificantLocationChanges`
(мы просим оба), система вправе усыпить в фоне, если фильтр задан.

**Упрощение — только при отрисовке, никогда в хранилище.** `RouteMapView` рисует
с порогом ~2 м; стояло 0.0001 градуса, то есть 7–11 м, и карта срезала ровно те
углы, ради которых точки и записывались.

### На какую машину пишется поездка (0.6.4)

Один вопрос — один ответ, и он живёт в `SettingsManager`:

- `vehicles` — **весь** гараж, включая архивные и проданные. Не фильтровать
  НИКОГДА: через него четыре экрана достают машину СТАРОЙ поездки, и фильтр
  там стирает историю («Транспорт удалён» у живой машины).
- `recordableVehicles` — на что можно писать сейчас (не в архиве, не продана).
  Сюда же придёт лимит бесплатного тарифа в 0.6.5 — одной строкой.
- `activeRecordableVehicleId` — на что уйдёт СЛЕДУЮЩАЯ поездка. Это читают
  гараж, паспорт и чип на экране записи, чтобы не расходиться в показаниях.
  `nil` значит «Без транспорта» — законный выбор человека, не поломка.
- `recordableVehicleId(_:)` — последний рубеж перед штампом. Спрашивает
  ХРАНИЛИЩЕ, а не список в памяти: снимок обновляется только когда его кто-то
  перечитает, и однажды кто-то этого не сделает (так синк уже проносил архивную
  машину мимо проверки).

Правило, которое всё это держит: **архивная или проданная машина не принимает
новых поездок нигде** — ни на экране записи, ни через автозапись по магнитоле,
ни через «Команды». Уже записанные поездки остаются при своих машинах: архив
про будущее, а не про переписывание истории. Автоматически в архив не уезжает
никто и никогда.

## Localization & Theming

- **Languages**: thirteen — `en, ru, de, es, fr, it, pl, id, tr, fil, uk, kk, pt` — via `LanguageManager.Language` + the `AppStrings` enum (all UI strings)
- **Themes**: dark/light/system via `ThemeManager`, colors in `AppTheme`
- Add new strings to `AppStrings.swift`, never hardcode UI text

### Adding a string

Write it as a function that takes the language and calls `tr`:

```swift
static func myThing(_ lang: LanguageManager.Language) -> String {
    tr(lang, "myThing", ru: "Моя штука", en: "My thing")
}
```

Russian and English live inline, next to the doc comment that explains the
copy. The other eleven come from `Localization/Translations/Translations+XX.swift`,
keyed by the same function name. A key with no row falls back to **English**, so
an untranslated string shows English rather than `myThing` — which is why
`LocalizationTests` exists: nothing else notices a key that drifted.

Rules that are easy to get wrong:
- **Never** `lang == .ru ? "…" : "…"` inline in a view. That is invisible to the
  tables and stays English on a German phone; 0.6.1 spent a day pulling 205 of
  them back out.
- Counted nouns go through `AppStrings.plural` / `nounTrips` / `nounDays` … —
  CLDR rules, not `if .ru`. Russian and Ukrainian share the three-form rule;
  Polish has its own and parts with them at 21; French, Filipino and Portuguese
  count 0 as singular; Indonesian has no plural at all.
- **Never** call `uppercased()` / `lowercased()` on copy without a language.
  Turkish writes `İ` for capital «i» and `ı` for lowercase «I», so the bare
  call corrupts every section header. Use `String.uppercased(_ lang:)`, or
  SwiftUI's `.textCase(.uppercase)` — the environment locale is set from the
  chosen language in `TripTrackApp`.
- Dates and numbers take their locale from `lang.locale`, never from a literal
  `"ru_RU"`. For formatters use `LocalizedDateFormatter.patterns/templates`,
  which build one per language.
- Permission prompts live in `TripTrack/Resources/<lang>.lproj/InfoPlist.strings`
  and follow the DEVICE language, not the in-app one. A new language needs a new
  `.lproj` **and** an entry in `knownRegions` in `project.yml`.
- The Live Activity and the widget cannot see `AppStrings` (it reaches into
  half the app). Their words are in `TripTrackShared/LiveActivityStrings.swift`,
  keyed by the raw language code.

## Tech Constraints

- iOS 17+, Swift 5.9, iPhone only
- SwiftUI only (no UIKit views except MapKit representable)
- MapKit (no third-party maps)
- No external dependencies — 100% native frameworks
- Background location enabled via Info.plist UIBackgroundModes

## Swift & SwiftUI Rules

### State Management
- Use `@StateObject` for owned objects created in the view, `@ObservedObject` for passed-in objects, `@EnvironmentObject` for shared app-wide state
- Never create `@StateObject` in a child view for an object owned by a parent — pass it as `@ObservedObject`
- Keep `@State` for local view-only state (toggles, sheet flags, text fields)
- All UI-mutating code must run on `@MainActor`. Services called from ViewModels should dispatch to main when updating `@Published` properties

### Views
- Extract subviews into computed properties or separate structs when body exceeds ~40 lines
- Use `ViewBuilder` functions for conditional UI blocks, not complex ternaries in body
- Prefer `.task {}` over `.onAppear` for async work — it auto-cancels
- Always add `.animation(.default, value:)` with explicit value, never `.animation(.default)` (deprecated)
- Use `LazyVStack` / `LazyHStack` inside `ScrollView` for lists with >20 items

### Нажатие обязано отвечать

Три правила из доклада Apple «Designing Fluid Interfaces» (WWDC 2018),
переписанные под наш случай. Все три мы уже нарушили — каждое поймал человек
на устройстве, не тест и не сборка.

- **Отклик в момент КАСАНИЯ, а не в момент результата.** У всего, что
  нажимается, должен быть видимый отклик под пальцем: `PressableCardStyle` для
  обычного тапа, `HoldableCardStyle` там, где действие открывает долгий тап.
  Голый `.buttonStyle(.plain)` на карточке — нажатие, которого не видно.
  История: карточка гаража с целым меню за долгим тапом выглядела мёртвой,
  потому что удержание ничем не отличалось от промаха.

- **Если нажатие что-то открывает — это видно. Если не открывает — не
  притворяемся.** Шеврон, отклик или и то и другое. Из четырёх строк в карточке
  рекордов открывается ровно одна, и шеврон стоит ровно у неё: неровно
  настолько, насколько неровна правда. Обратная ошибка тоже наша — фотографии
  машины, где обычный тап не делал НИЧЕГО, а единственное действие пряталось за
  жестом, о котором сообщала подпись внизу экрана.

- **Анимацию можно прервать.** Всегда `.animation(_:value:)` с явным значением
  (см. правило выше) и пружина, а не цепочка из `withAnimation` + `sleep`,
  которую нельзя отменить на середине. Человек, передумавший в середине жеста,
  не должен ждать, пока приложение доиграет.

Родня этих правил — раздел «Dialogs» ниже: там та же мысль про то, что экран не
должен обещать одно, а делать другое.

### Performance
- Mark ViewModels as `@MainActor` class
- Use `nonisolated` for heavy computation methods that don't touch UI
- `Task.detached` для тяжёлого счёта (кодирование, фильтрация больших массивов) —
  ПОКА мы на Swift 5.9. В 6.2 правильный инструмент `@concurrent`, а
  `Task.detached` становится «почти никогда»: он не наследует ни изоляцию, ни
  приоритет, ни task-local. При переходе на 6.2 эти 23 места пересмотреть
- For CoreData fetches in background: use `viewContext.perform {}` or `newBackgroundContext()`
- Avoid re-creating objects in `body` — pull constants and formatters to static/lazy properties

### Swift Style
- Prefer `guard let` for early exits over nested `if let`
- Use `[weak self]` in closures that capture self in non-@MainActor contexts
- Prefer `async/await` over Combine chains for new code. Keep existing Combine as-is
- Ошибки: восстановимая — `throws`, ошибка программиста — `precondition`.
  Правило про `Result` здесь стояло годами и НЕ соответствовало коду:
  сервисов, возвращающих `Result`, — ноль, бросающих — сорок два.
  Тип ошибки — enum со связанными значениями (`APIError`), контекст в нём же
- Enums with associated values over multiple optional properties when states are mutually exclusive

### File Organization
- After adding/removing .swift files, run `xcodegen generate` to update the Xcode project
- One type per file. Extensions in the same file are fine, separate extension files only for protocol conformances
- New views go in the appropriate `Views/` subdirectory by feature
- New services are singletons with `static let shared`

### Dialogs — always ours, never the system's

**No system modal ever ships in this app.** No `.alert`, no `.confirmationDialog`,
no `.actionSheet`, no `Menu` used as an action list. They drop UIKit chrome —
system greys, system type, a plate with its own corner radius — into the middle
of a screen built from our warm cards, and they read as borrowed from another
app. Two of them have already shipped broken: a `confirmationDialog` inside a
custom navigator adapted into a floating plate that lost its own Cancel button,
and a `Menu` on a circular nav control left a rounded-square plate behind on
dismissal (see `NavCircleIcon`'s doc comment).

Use the house components instead:
- **Confirmations** — `AppConfirmDialog` / the `.appConfirm(...)` modifier: a
  scrim that swallows taps, the question in our type, and the answers stacked
  with the safe one nearest the thumb.
- **Action lists** («…» menus) — `ActionPopoverList`.
- **Pickers** — `SettingsOptionPicker` in a `.contentSizedSheet`.
- **Transient feedback** — `ToastView`, not an alert.

Rules for any confirmation you build or touch:
- The scrim must be `.accessibilityHidden(true)` and the card a modal, or
  VoiceOver's rotor walks straight past it onto the page behind.
- `AppConfirmDialog` dismisses ITSELF before running each handler, so a handler
  must NOT clear `isPresented` / the item, and must not read its subject back
  out of state after dismissal — take it as the closure argument instead.
  (A hand-rolled overlay does not do this for you: forgetting to dismiss is what
  made «Закрепить» look like a dead button. That is the reason to use the
  component rather than to copy it.)
- A dialog on a TAB-ROOT screen must also `.hideAppTabBar()` while it is up, or
  the custom tab bar paints over the scrim and stays tappable — the user can
  switch tabs with a destructive confirmation pending.
- Attach the dialog at the SCREEN root, never inside a `ScrollView`. An overlay
  is sized to the view it modifies, so a dialog hung on a section gets a scrim
  the size of that section, scrolls with the content, and can be clipped
  off-screen entirely.
- The destructive action is `AppTheme.red`, the ordinary one `AppTheme.accent`,
  and Cancel is always present and always last.
- All copy through `AppStrings`, both languages.

### What NOT to Do
- Don't use `AnyView` — it kills SwiftUI diffing performance
- Don't use `@ObservedObject` for objects the view creates — use `@StateObject`
- Don't force-unwrap optionals except for IBOutlets (which we don't use) and test assertions
- Don't use `DispatchQueue.main.async` in new code — use `@MainActor` or `MainActor.run {}`
- Don't add `import UIKit` in SwiftUI views unless absolutely necessary for a specific API
- Don't nest NavigationStack inside NavigationStack
