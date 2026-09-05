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

## CoreData Schema (versioned, v9 — 0.6.4)

`TripEntity` is central, with cascade relationships to `TrackPointEntity` and `TripPhotoEntity`. Also: `VehicleEntity`, `VehiclePhotoEntity` (0.6.4), `UserSettingsEntity`, `VisitedGeohashEntity`, `GeocodeCacheEntity`, `RoadEntity`. Schema at `TripTrack/Persistence/TripTrack.xcdatamodeld/` (v1 = baseline, v9 = current).

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
