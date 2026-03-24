# TripTrack -- Техническое решение v1.0

> **Версия:** 1.0
> **К PRD:** v1.0
> **Статус:** MVP -- в разработке
> **Обновлено:** Март 2026

---

## 1. Архитектура

### 1.1. Обзор

Offline-first нативное iOS-приложение. GPS-трекинг автопутешествий с геймификацией. Все данные на устройстве (CoreData). Нет серверной части, нет внешних зависимостей -- 100% нативные фреймворки Apple.

```
+-----------------------------------------------------+
|                  Presentation Layer                   |
|  SwiftUI Views | ViewModels (@Published) | Tab Bar   |
+-----------------------------------------------------+
                          |
                          v
+-----------------------------------------------------+
|                   Service Layer                       |
|  TripManager | LocationManager | GamificationManager |
|  SmoothTrackManager | TerritoryManager | BadgeManager|
+-----------------------------------------------------+
                          |
                          v
+-----------------------------------------------------+
|                  Persistence Layer                    |
|  CoreData (PersistenceController) | Photos (Documents)|
|  UserDefaults (SettingsManager)                       |
+-----------------------------------------------------+
```

### 1.2. Паттерн: MVVM + Service Layer

**Presentation Layer:**
- **SwiftUI Views** -- декларативный UI, организован по фичам в `Views/`
- **ViewModels** -- `@ObservableObject` с `@Published`, `@MainActor` class
- **Навигация** -- Tab Bar (3 таба) + modal sheets

**Service Layer:**
- **Singletons** с `static let shared`
- Бизнес-логика, CRUD, геокодинг, GPS-фильтрация, бейджи
- Вызываются из ViewModels

**Persistence Layer:**
- **CoreData** -- 8 entities, cascade relationships
- **Documents** -- фотографии поездок
- **UserDefaults** -- настройки пользователя

**Data Flow:** Views -> ViewModels (@Published) -> Services -> CoreData

---

## 2. Стек технологий

| Слой | Технология | Зачем |
|------|-----------|-------|
| UI | SwiftUI (iOS 17+) | Декларативный UI, @Observable, NavigationStack |
| Карты | MapKit | Нативные карты Apple, MKMapView representable |
| Хранение | CoreData | Structured persistence, relationships, async saves |
| Локация | CoreLocation | GPS-трекинг, background updates |
| Фото | PhotosUI (PHPicker) | Выбор фото без UIImagePickerController |
| Язык | Swift 5.9 | async/await, Sendable, macros |
| Сборка | XcodeGen (project.yml) | Генерация .xcodeproj из YAML |
| Signing | Local.xcconfig | Bundle ID + Team (gitignored) |
| Min target | iOS 17.0 | iPhone only |

**Без внешних зависимостей.** Ни SPM, ни CocoaPods. Все на нативных фреймворках.

---

## 3. Структура проекта

```
TripTrack/
|-- App/
|   +-- TripTrackApp.swift                 # Entry point, @main
|
|-- Models/
|   |-- Trip.swift                         # Trip domain model + polyline encode/decode
|   |-- TrackPoint.swift                   # GPS point model
|   |-- Vehicle.swift                      # Vehicle model
|   |-- Badge.swift                        # Badge model
|   |-- BadgeDefinitions.swift             # 37+ badge definitions
|   |-- GamificationModels.swift           # XP, levels, ranks
|   |-- TripPhoto.swift                    # Photo model
|   |-- TripFilters.swift                  # Filter models
|   +-- UserSettings.swift                 # User settings model
|
|-- ViewModels/
|   |-- MapViewModel.swift                 # Recording, map state, trip lifecycle
|   |-- FeedViewModel.swift                # Trip list, filtering, pagination, sections
|   +-- TripsViewModel.swift               # Trip CRUD operations
|
|-- Services/
|   |-- TripManager.swift                  # CRUD, geocoding, batch saves, photos
|   |-- LocationManager.swift              # Dual-mode GPS (real/simulated)
|   |-- LocationProvider.swift             # Protocol for location providers
|   |-- RealGPSProvider.swift              # CoreLocation implementation
|   |-- SimulatedLocationProvider.swift    # Dev joystick for testing
|   |-- SmoothTrackManager.swift           # Kalman filter for GPS smoothing
|   |-- PathSmoother.swift                 # Catmull-Rom polyline smoothing
|   |-- GamificationManager.swift          # XP, levels, ranks calculation
|   |-- BadgeManager.swift                 # Badge evaluation logic
|   |-- TerritoryManager.swift             # Fog of War, visited geohashes
|   |-- GeohashEncoder.swift               # Geohash-6 encoding
|   |-- RoadCollectionManager.swift        # Road discovery/mastery
|   |-- PhotoStorageService.swift          # Photo save/load to Documents
|   |-- SunCalculator.swift                # Sunset/sunrise for map theme
|   |-- NetworkMonitor.swift               # Connectivity monitoring
|   +-- SettingsManager.swift              # UserDefaults wrapper
|
|-- Persistence/
|   |-- PersistenceController.swift        # CoreData stack, async saves
|   +-- TripTrack.xcdatamodeld/            # CoreData schema
|
|-- Views/
|   |-- ContentView.swift                  # Root view + Tab Bar
|   |-- Navigation/
|   |   +-- CustomTabBar.swift             # Liquid Glass floating tab bar
|   |-- Feed/
|   |   |-- FeedView.swift                 # Main feed screen
|   |   |-- FeedTripCardView.swift         # Trip card component
|   |   |-- ContributionCalendarView.swift # Week/month calendar
|   |   |-- FilterSheetView.swift          # Filter bottom sheet
|   |   |-- StatsView.swift                # Quick stats bar
|   |   |-- FeedEmptyStateView.swift       # Empty state
|   |   |-- SkeletonTripCard.swift         # Loading skeleton
|   |   +-- SwipeActionCard.swift          # Swipe to delete
|   |-- Tracking/
|   |   |-- TrackingView.swift             # Recording screen
|   |   |-- CompactTrackingHUD.swift       # Live stats HUD
|   |   |-- SpeedometerView.swift          # Speed display (44pt)
|   |   |-- IdleHUDView.swift              # Idle state with pulsing rings
|   |   |-- GPSIndicatorView.swift         # Accuracy indicator
|   |   |-- TrackingHUD.swift              # HUD container
|   |   +-- TripCompleteSummaryView.swift  # Post-trip summary
|   |-- Map/
|   |   |-- MapViewRepresentable.swift     # MKMapView UIViewRepresentable
|   |   +-- GlowingHeadOverlay.swift       # Glowing route head
|   |-- Regions/
|   |   |-- RegionsView.swift              # Regions tab main screen
|   |   |-- ScratchMapView.swift           # Fog of War map
|   |   |-- FogOverlay.swift               # MKOverlay for fog
|   |   |-- FogOverlayRenderer.swift       # Custom MKOverlayRenderer
|   |   |-- FogMaskGenerator.swift         # Fog mask computation
|   |   +-- FullscreenFogMapView.swift     # Fullscreen fog map
|   |-- Profile/
|   |   |-- ProfileView.swift              # Profile sheet
|   |   |-- DriverLevelView.swift          # XP + rank display
|   |   +-- VehicleCardView.swift          # Vehicle info card
|   |-- Garage/
|   |   +-- GarageView.swift               # Vehicle management
|   |-- Badges/
|   |   |-- BadgesView.swift               # Badge grid
|   |   |-- BadgeDetailOverlay.swift       # Badge detail popup
|   |   |-- BadgeCelebrationView.swift     # Fullscreen celebration
|   |   |-- ConfettiView.swift             # Confetti particles (Canvas)
|   |   +-- TripBadgesRow.swift            # Badges row in trip detail
|   |-- Trips/
|   |   |-- TripDetailView.swift           # Trip detail screen
|   |   |-- TripsListView.swift            # Legacy trips list
|   |   |-- TripCardView.swift             # Legacy trip card
|   |   |-- PhotoFullScreenView.swift      # Fullscreen photo gallery
|   |   |-- TripShareCardView.swift        # Share card generation
|   |   +-- TripsTabView.swift             # Trips tab
|   |-- Roads/
|   |   +-- RoadCollectionView.swift       # Road collection screen
|   |-- Onboarding/
|   |   +-- OnboardingView.swift           # 3-page onboarding
|   |-- Settings/
|   |   +-- SettingsView.swift             # Settings sheet
|   |-- Theme/
|   |   |-- AppTheme.swift                 # Color palette, modifiers
|   |   +-- ThemeManager.swift             # Theme switching logic
|   +-- Components/
|       |-- CardMapPreview.swift           # Simplified route preview
|       |-- LightRoutePreview.swift        # Lightweight route line
|       |-- RouteMapView.swift             # Interactive route map
|       |-- RoutePreviewView.swift         # Route preview wrapper
|       |-- StatView.swift                 # Reusable stat display
|       |-- LocationTrackingButton.swift   # Map location button
|       |-- PositionMarker.swift           # Current position marker
|       |-- RecordingBanner.swift          # Recording indicator banner
|       |-- PhotoPickerView.swift          # Photo picker
|       |-- NotesEditorView.swift          # Trip notes editor
|       |-- ToastView.swift                # Toast notifications
|       |-- AsyncThumbnailView.swift       # Async image loading
|       +-- DevMenuView.swift              # Debug menu (dev only)
|
|-- Localization/
|   |-- AppStrings.swift                   # All UI strings (RU/EN enum)
|   +-- LanguageManager.swift              # Language switching
|
|-- Resources/
|   +-- Assets.xcassets/                   # Images, colors, app icon
|
|-- Info.plist                             # Background modes, location usage
|-- TripTrack.entitlements                 # App entitlements
+-- PrivacyInfo.xcprivacy                  # Privacy manifest
```

---

## 4. Модель данных

### 4.1. CoreData Schema (8 entities)

`TripEntity` -- центральная сущность. Cascade relationships к `TrackPointEntity` и `TripPhotoEntity`.

```
TripEntity (central)
|-- id: UUID
|-- title: String?
|-- startDate: Date
|-- endDate: Date?
|-- totalDistance: Double (meters)
|-- totalDuration: Double (seconds)
|-- averageSpeed: Double (m/s)
|-- maxSpeed: Double (m/s)
|-- maxAltitude: Double (meters)
|-- elevationGain: Double (meters)
|-- startLocationName: String?
|-- endLocationName: String?
|-- encodedPolyline: Data? (binary, compact)
|-- vehicleID: UUID?
|-- badgesJSON: String? (earned badges)
|-- xpEarned: Int32
|-- notes: String?
|-- trackPoints: Set<TrackPointEntity> (cascade delete)
|-- photos: Set<TripPhotoEntity> (cascade delete)

TrackPointEntity
|-- latitude: Double
|-- longitude: Double
|-- altitude: Double
|-- speed: Double
|-- course: Double
|-- horizontalAccuracy: Double
|-- timestamp: Date
|-- trip: TripEntity (inverse)

TripPhotoEntity
|-- id: UUID
|-- filename: String
|-- timestamp: Date
|-- trip: TripEntity (inverse)

VehicleEntity
|-- id: UUID
|-- name: String
|-- emoji: String
|-- totalKm: Double
|-- level: Int16
|-- stickersJSON: String?
|-- isSelected: Bool
|-- createdAt: Date

UserSettingsEntity
|-- id: UUID
|-- totalXP: Int32
|-- driverLevel: Int16
|-- driverRank: String
|-- currentStreak: Int16
|-- longestStreak: Int16
|-- lastTripDate: Date?
|-- avatarEmoji: String

VisitedGeohashEntity
|-- geohash: String (primary, geohash-6)
|-- firstVisitDate: Date
|-- visitCount: Int16

RoadEntity
|-- id: UUID
|-- name: String
|-- totalKm: Double
|-- timeDriven: Int16
|-- rarity: String
|-- masteryLevel: String
```

### 4.2. Relationships

```
TripEntity -->> TrackPointEntity (cascade delete)
TripEntity -->> TripPhotoEntity (cascade delete)
TripEntity --> VehicleEntity (optional, by vehicleID)
```

### 4.3. Binary Polylines

Маршруты хранятся в двух форматах:
- **TrackPointEntity** -- полные GPS-точки с metadata (speed, altitude, accuracy)
- **encodedPolyline** (Data) -- компактное бинарное представление координат для быстрого рендеринга

```swift
// Trip.swift
static func encodePolyline(_ coordinates: [CLLocationCoordinate2D]) -> Data
static func decodePolyline(_ data: Data) -> [CLLocationCoordinate2D]
```

Бинарный формат экономит ~80% места по сравнению с хранением отдельных точек для визуализации.

---

## 5. GPS-трекинг

### 5.1. Provider Pattern

```
LocationProvider (protocol)
|-- startUpdating()
|-- stopUpdating()
|-- onLocationUpdate: (CLLocation) -> Void
    |
    |-- RealGPSProvider         # CoreLocation, production
    +-- SimulatedLocationProvider  # Dev joystick, debug
```

`LocationManager` переключается между провайдерами. В production -- `RealGPSProvider` с background location updates. В debug -- `SimulatedLocationProvider` с виртуальным джойстиком.

### 5.2. CoreLocation Configuration

```swift
desiredAccuracy: kCLLocationAccuracyBest
distanceFilter: 5 meters
activityType: .automotiveNavigation
allowsBackgroundLocationUpdates: true
showsBackgroundLocationIndicator: true
pausesLocationUpdatesAutomatically: false
```

Info.plist: `UIBackgroundModes` -> `location`.

### 5.3. Kalman Filter (SmoothTrackManager)

Упрощенный Kalman-фильтр для сглаживания GPS-траектории:

1. **Accuracy filter** -- отбрасывание точек с `horizontalAccuracy > 50m`
2. **Speed consistency check** -- отбрасывание нереалистичных скачков (>300 km/h)
3. **Kalman smoothing** -- предсказание + коррекция по measurement accuracy
4. **Process noise** -- настраиваемый параметр баланса smoothing/responsiveness

Результат: убирает GPS-дрожание, сглаживает траекторию, улучшает точность на 30-50%.

### 5.4. Batch Saves

Точки записываются не по одной, а пачками:
- **Порог по количеству:** 10 точек
- **Порог по времени:** 15 секунд
- **При остановке:** flush всех оставшихся

Батчинг снижает нагрузку на CoreData I/O и экономит батарею.

### 5.5. Junk Trip Filtering

Автоматическое удаление "мусорных" поездок:
- Расстояние < 500 метров AND длительность < 2 минуты
- Проверяется при завершении поездки
- Warning haptic при удалении

---

## 6. Картография

### 6.1. MapKit

Используется нативный MapKit (MKMapView через `UIViewRepresentable`). Без третьесторонних библиотек карт.

Компоненты:
- **MapViewRepresentable** -- обертка MKMapView для SwiftUI
- **GlowingHeadOverlay** -- анимированная головная точка маршрута
- **FogOverlay + FogOverlayRenderer** -- MKOverlay для Fog of War

### 6.2. Route Rendering

- **Orange polyline** с glow-эффектом (основной цвет: #FC4C02)
- **Catmull-Rom** smoothing (PathSmoother) для плавных кривых
- **Speed color-coding** в Trip Detail: gradient green -> red
- **Green dot** на точке старта
- **Animated glowing head** на текущей позиции

### 6.3. Auto-zoom

Camera distance адаптируется к скорости:
- Медленно -> ближе к земле
- Быстро -> дальше, больший обзор

### 6.4. Sun-based Map Theme

`SunCalculator` вычисляет закат/рассвет по координатам пользователя. Карта автоматически переключается между light/dark стилем.

### 6.5. Fog of War (Scratch Map)

Реализация через геохеширование:

1. **GeohashEncoder** -- конвертация координат в geohash-6 строку (~0.72 km^2 на тайл)
2. **VisitedGeohashEntity** -- хранение посещенных тайлов в CoreData
3. **FogMaskGenerator** -- генерация маски тумана
4. **FogOverlay + FogOverlayRenderer** -- MKOverlay рендеринг:
   - Dark theme: `rgba(0,0,0,0.7)` fog
   - Light theme: `rgba(200,200,200,0.6)` fog
   - Мягкие/feathered границы тумана
5. **TerritoryManager** -- подсчет городов, регионов, прогресса

---

## 7. Геймификация

### 7.1. Бейджи (37+)

4 категории:
- **Distance** (13 badges): first_trip, road_regular (10), road_warrior (50), century (100km), thousand, ten_thousand, etc.
- **Exploration** (5 badges): explorer_5/10/25 regions, ambassador (2+ countries), globetrotter (5+)
- **Special** (12 badges): night_rider, mountain_goat, above_clouds, sea_level, early_bird, snow_leopard, etc.
- **Streaks** (3 badges): streak_3/7/30

Типы:
- **Milestone** -- one-time, навсегда
- **Repeatable** -- зарабатывается на каждой квалифицирующей поездке, счетчик инкрементируется

Хранение: `BadgeDefinitions.swift` (определения), `TripEntity.badgesJSON` (заработанные на поездке), `UserDefaults` (глобальный unlock status).

### 7.2. XP и уровни

**XP начисление:**
- 1 XP за каждый km
- +20 XP за первую поездку дня
- +50 XP за новый регион
- x2 мультипликатор за поездки >200 km

**30 уровней водителя, 7 рангов:**

| Ранг | Уровни | Иконка | Цвет |
|------|--------|--------|------|
| Novice | 1-4 | car | gray |
| Driver | 5-9 | steering wheel | bronze |
| Traveler | 10-14 | compass | silver |
| Explorer | 15-19 | map | gold |
| Navigator | 20-24 | helm | platinum |
| Trucker | 25-29 | star | diamond |
| Legend | 30 | flame | orange |

**10 уровней автомобиля** по накопленному пробегу:
New -> Break-in -> Familiar -> Yours -> Partner -> Veteran -> Warhorse -> Legend -> Immortal -> Odometer Infinity

### 7.3. Streaks

Consecutive days with trips. Хранится в `UserSettingsEntity` (currentStreak, longestStreak, lastTripDate).

### 7.4. Vehicle Stickers

9 коллекционных стикеров по milestone-ам (хранятся в `VehicleEntity.stickersJSON`).

---

## 8. Персистентность

### 8.1. CoreData Stack

```swift
PersistenceController.shared
|-- persistentContainer: NSPersistentContainer
|-- viewContext: NSManagedObjectContext (main thread)
|-- newBackgroundContext() -> NSManagedObjectContext
|-- saveAsync() -- non-blocking save from location callbacks
```

**Merge policy:** `NSMergeByPropertyObjectTrumpMergePolicy`
**Auto-merge:** `automaticallyMergesChangesFromParent = true`

### 8.2. Async Saves

`PersistenceController.saveAsync()` для non-blocking записи из location callbacks. GPS-точки батчатся и сохраняются в background context.

### 8.3. Photo Storage

Фотографии сохраняются в Documents directory (не в CoreData). `TripPhotoEntity` хранит только filename. `PhotoStorageService` управляет save/load/delete.

### 8.4. Settings

`SettingsManager` -- обертка над UserDefaults для настроек (тема, язык, onboarding status).

---

## 9. Ключевые паттерны

### 9.1. Provider Pattern (Location)

`LocationProvider` protocol позволяет подменять source GPS-данных:
- Production: `RealGPSProvider` (CoreLocation)
- Debug: `SimulatedLocationProvider` (виртуальный джойстик)

### 9.2. Batch Saves

GPS-точки накапливаются в буфере (10 шт / 15 сек) и сохраняются пачкой через `TripManager`. Снижает I/O и CPU usage.

### 9.3. Junk Trip Filtering

Автоматическое удаление поездок < 500m AND < 2min при завершении. Предотвращает засорение ленты.

### 9.4. Binary Polylines

`Trip.encodePolyline/decodePolyline` -- компактное бинарное хранение маршрутов для быстрого рендеринга без загрузки всех TrackPoint.

### 9.5. Geohashing

`GeohashEncoder` конвертирует координаты в geohash-6 строки. `VisitedGeohashEntity` в CoreData хранит посещенные тайлы. Позволяет эффективно считать territory coverage.

### 9.6. Card Modifiers

Три переиспользуемых стиля карточек:
- `.surfaceCard()` -- стандартная карточка с bg + corner radius + subtle shadow
- `.glassBackground()` -- frosted glass для overlay-ев на карте
- `.glassPill()` -- компактный glass pill для HUD-элементов

### 9.7. Singleton Services

Все сервисы -- singletons с `static let shared`. Инжектируются в ViewModels. Позволяет переиспользовать state между экранами.

---

## 10. Темизация и локализация

### 10.1. Темы

`ThemeManager` -- `@ObservableObject`, `@EnvironmentObject` в корне приложения.
Три режима: system / light / dark.

`AppTheme` -- статический набор цветов, автоматически переключается по `colorScheme`:

| Token | Dark | Light |
|-------|------|-------|
| background | #000000 | #F2F2F7 |
| card surface | #1C1C1E | #FFFFFF |
| card alt | #2C2C2E | #F5F5F7 |
| text primary | #FFFFFF | #000000 |
| text secondary | rgba(255,255,255,0.6) | rgba(0,0,0,0.55) |
| accent (Strava orange) | #FC4C02 | #FC4C02 |
| success green | #34C759 | #34C759 |
| danger red | #FF3B30 | #FF3B30 |
| info blue | #007AFF | #007AFF |
| glass surface | rgba(44,44,46,0.72) | rgba(255,255,255,0.72) |

### 10.2. Локализация

`LanguageManager` -- переключение RU/EN без перезапуска.
`AppStrings` -- enum со всеми UI-строками. Hardcoded текст в UI запрещен.

```swift
enum AppStrings {
    case tripStarted
    case totalDistance
    // ...

    var ru: String { ... }
    var en: String { ... }
    var localized: String { LanguageManager.shared.current == .ru ? ru : en }
}
```

---

## 11. Open Questions

| # | Вопрос | Статус |
|---|--------|--------|
| 1 | Auto-start через motion detection | Отложено -- требует тестирования на реальных устройствах |
| 2 | Backend sync (multi-device) | Отложено -- офлайн-first MVP |
| 3 | Монетизация (freemium/subscription) | Отложено -- сначала валидация продукта |
| 4 | Stats dashboard | Планируется в v1.1 |
| 5 | Road Collection mastery system | Планируется в v1.1 |
| 6 | Apple Watch / CarPlay | Планируется в v1.2+ |
| 7 | Оптимизация battery drain на длинных поездках (>4 часов) | Требует тестирования |
| 8 | Offline tile caching (MapKit) | MapKit кеширует автоматически, но без гарантий |

---

> MVP в разработке. Архитектура стабильна. Все core-модули реализованы.
