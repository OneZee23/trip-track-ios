# GPS Tracking Improvement: Kalman Filter + Post-Trip Reconstruction

**Date:** 2026-04-02
**Status:** Draft

## Context

В условиях активного GPS-глушения текущий трекинг даёт "срезанные" повороты и дыры в маршруте. Приложение полностью GPS-only: нет Kalman-фильтра, нет dead reckoning. Когда GPS пропадает — точки не записываются, при возвращении сигнала — прямая линия к новой позиции.

Типичный сценарий: пользователь включает запись, переключается на навигатор, приложение в **background**.

**Цель:** максимально точный трек маршрута как в реальном времени, так и в сохранённом виде. Без зависимости от интернета.

## Текущее состояние

- GPS-only трекинг: `RealGPSProvider` → `LocationUpdate` → `MapViewModel` → `TripManager` + `SmoothTrackManager`
- Фильтры: accuracy ≤ 100m (RealGPSProvider), accuracy ≤ 30m + distance ≥ 5m + speed ≤ 300 km/h + drift detection (TripManager)
- Визуальное сглаживание: Catmull-Rom в `PathSmoother` (только для отображения, `[CLLocationCoordinate2D]`)
- Speed decay timer в MapViewModel: каждые 0.5 сек, если нет GPS > 2 сек → затухание скорости
- Два хранилища трека: `TrackPointEntity` (полные точки) + `previewPolyline` (бинарный, ~20 точек после RDP для карточек ленты)
- `TrackPoint` хранит `course`, `speed`, `horizontalAccuracy`, `timestamp`
- `LocationProviding` протокол: `RealGPSProvider` + `SimulatedLocationProvider`

**Ключевые файлы:**
- `TripTrack/Services/RealGPSProvider.swift` — CLLocationManager delegate, валидация, background recovery
- `TripTrack/Services/LocationProvider.swift` — `LocationUpdate` struct, `LocationProviding` protocol
- `TripTrack/Services/TripManager.swift` — handleNewLocation, batch saves, фильтры, `generatePreviewPolyline`
- `TripTrack/Services/SmoothTrackManager.swift` — live display, анимация головы трека
- `TripTrack/Services/PathSmoother.swift` — Catmull-Rom сплайны
- `TripTrack/ViewModels/MapViewModel.swift` — recording bindings, speed EMA, speed decay timer (0.5s)
- `TripTrack/Models/TrackPoint.swift` — модель точки

## Ключевое ограничение

Приложение 90% времени записи в background (пользователь в навигаторе). CoreMotion не доставляет данные в background. Поэтому **CoreMotion вынесен из scope v1** — основное улучшение целиком на GPS-only Kalman filter + post-trip reconstruction. CoreMotion можно добавить позже как enhancement для foreground.

## Архитектура решения

### Новые компоненты

#### 1. `KalmanLocationFilter`

Чистая математика, без системных зависимостей. Две функции: сглаживание GPS-точек + предсказание позиции при gaps.

**State vector в локальных координатах ENU (East, North):**
- `[east, north, velocityEast, velocityNorth]`
- Работа в метрах, не в lat/lon (избегаем нелинейности координат)
- Конвертация lat/lon ↔ ENU при входе/выходе
- Origin ENU = первая GPS-точка записи

**Матрицы:**
- **Process noise (Q):** калибровка под автомобильное движение (~1-3 m/s² ускорение)
- **Measurement noise (R):** динамически из `horizontalAccuracy` каждой GPS-точки
- **State transition (F):** constant-velocity модель, dt из реального времени между update'ами

**Prediction при GPS gap:**
- Предсказание по последним velocity + heading из state vector
- Uncertainty растёт с каждым predict-шагом
- Timeout: **10 секунд** (без IMU drift слишком большой дальше)
- После timeout → возвращает nil, точка замирает

```swift
final class KalmanLocationFilter {
    /// Сглаженная GPS-точка. Вызывается для каждого LocationUpdate от GPS
    func processGPSUpdate(_ location: CLLocation) -> CLLocation

    /// Предсказанная позиция (nil если timeout или нет данных)
    func predictedLocation() -> CLLocation?

    /// Сброс (при старте новой записи)
    func reset()

    /// Секунд с последнего GPS update
    var timeSinceLastGPS: TimeInterval { get }

    /// Идёт ли prediction (GPS gap, не превышен timeout)
    var isPredicting: Bool { get }
}
```

Без `@MainActor`, без side effects, без системных зависимостей. Легко тестируется.

#### 2. `PostTripTrackProcessor`

Пост-обработка трека после завершения поездки. Запускается один раз, результат сохраняется в CoreData.

**Алгоритм:**
1. Загрузить все TrackPoints поездки из CoreData (только `isInterpolated = false`)
2. Найти gaps: участки где `Δt между соседними точками > 3 секунд`
3. Для каждого gap:
   - Если расстояние между границами > 5 км — пропускаем (кривая бессмысленна без map-matching)
   - Catmull-Rom интерполяция координат (4 control points: 1 до gap, 2 граничные, 1 после gap)
   - Линейная интерполяция speed, course, altitude между границами
   - Равномерные timestamps (1 точка каждые ~2 сек)
   - `isInterpolated = true`
4. Сохранить интерполированные TrackPointEntity в CoreData
5. Перегенерировать `previewPolyline` (через существующий `TripManager.generatePreviewPolyline`)
6. Пересчитать статистику (distance, avgSpeed, maxSpeed)
7. Пометить `isTrackProcessed = true`

```swift
final class PostTripTrackProcessor {
    func processTrip(_ tripId: UUID) async
}
```

### Модификации существующих компонентов

#### `RealGPSProvider` — БЕЗ ИЗМЕНЕНИЙ
Остаётся чистым CLLocationManager delegate. `LocationProviding` протокол и `SimulatedLocationProvider` — без изменений.

#### `MapViewModel`
- Новое свойство: `private let kalmanFilter = KalmanLocationFilter()`
- В location sink (где приходит LocationUpdate):
  - Конвертировать в CLLocation → `kalmanFilter.processGPSUpdate()` → использовать сглаженную позицию
  - Отправить сглаженную точку в `TripManager` (save) и `SmoothTrackManager` (display)
- Расширить **существующий speed decay timer** (0.5 сек):
  - Текущее поведение (decay speed после 2 сек) — оставить
  - Добавить: если `kalmanFilter.isPredicting`, вызвать `kalmanFilter.predictedLocation()` → отправить в `SmoothTrackManager` (только display, НЕ в TripManager)
- При `startRecording()`: `kalmanFilter.reset()`
- При `stopRecording()`: запустить `PostTripTrackProcessor().processTrip(tripId)`

#### `TripManager`
- **Без изменений в handleNewLocation** — получает уже сглаженные GPS-точки из Kalman (predicted-точки не доходят — MapViewModel их не отправляет в TripManager)

#### CoreData Schema
- `TrackPointEntity`: добавить `isInterpolated: Bool` (default: false)
- `TripEntity`: добавить `isTrackProcessed: Bool` (default: false)

#### `TrackPoint` (модель)
- Добавить `isInterpolated: Bool = false`

#### App Launch
- В `TripManager` или `PersistenceController`: при запуске приложения — найти поездки с `isTrackProcessed = false` и `endDate != nil` (завершённые, но необработанные) → запустить `PostTripTrackProcessor` для каждой

### Поток данных

```
[GPS update — background + foreground]

CLLocationManager → RealGPSProvider → LocationUpdate (без изменений)
                                            ↓
                                       MapViewModel
                                            ↓
                                   KalmanLocationFilter.processGPSUpdate()
                                            ↓
                                      Smoothed CLLocation
                                            ↓
                              ┌─────────────┴─────────────┐
                              ↓                           ↓
                      TripManager.save()       SmoothTrackManager.addPoint()
                      (CoreData batch)          (live display)

[GPS gap — speed decay timer (каждые 0.5 сек)]

MapViewModel timer tick
    → kalmanFilter.isPredicting?
        → YES: kalmanFilter.predictedLocation()
                    → SmoothTrackManager.addPoint() (ТОЛЬКО display)
        → NO (timeout): ничего, точка замирает
    → elapsed > 2s?
        → speed *= 0.4 (существующий decay)

[После записи]

MapViewModel.stopRecording()
    → PostTripTrackProcessor.processTrip(tripId)
        → Load TrackPoints (isInterpolated = false)
        → Find gaps (Δt > 3s, distance < 5km)
        → Catmull-Rom interpolation → new TrackPointEntity (isInterpolated = true)
        → Regenerate previewPolyline
        → Recalculate stats
        → Mark isTrackProcessed = true

[При запуске приложения]

AppLaunch → find trips where isTrackProcessed = false AND endDate != nil
         → PostTripTrackProcessor.processTrip() для каждой
```

## Энергопотребление

| Состояние | GPS | Kalman | Доп. расход |
|-----------|-----|--------|-------------|
| Просмотр ленты | Off | Off | 0% |
| Idle (не пишем) | Low-power 100m | Off | 0% |
| Запись (bg + fg) | Best accuracy | Smoothing + predict | ~0% (только CPU math) |
| Post-trip обработка | Off | Off | ~1 сек CPU |

## Граничные случаи

1. **GPS пропал сразу после старта** — нет velocity/heading в state vector. `predictedLocation()` → nil, замираем
2. **Остановка на светофоре + GPS gap** — velocity ~0, prediction держит точку на месте
3. **Тоннель (длинный gap)** — prediction timeout 10 сек → замираем. PostTripTrackProcessor восстановит
4. **GPS "прыжок" после gap** — Kalman с высоким uncertainty мягко переходит к новой позиции
5. **Gap > 5 км** — PostTripTrackProcessor пропускает (нет смысла без map-matching)
6. **App killed до post-processing** — обработается при следующем запуске (isTrackProcessed check)
7. **Повторный processTrip** — проверяет isTrackProcessed, пропускает если уже обработан
8. **SimulatedLocationProvider** — Kalman работает так же (получает те же LocationUpdate)

## Тестирование

1. **Unit-тесты KalmanLocationFilter:**
   - Серия GPS-точек с шумом → σ выхода < σ входа
   - GPS gap 5 сек → prediction генерирует точки по вектору движения
   - GPS gap 15 сек → prediction timeout, возвращает nil
   - "Прыжок" после gap → плавный переход
   - ENU roundtrip: lat/lon → ENU → lat/lon, ошибка < 0.01m

2. **Unit-тесты PostTripTrackProcessor:**
   - Трек с gap 5 сек → интерполированные точки с timestamps, isInterpolated = true
   - Трек с gap 2 мин → кривая между границами
   - Gap > 5 км → не интерполируется
   - Трек без gaps → ничего не добавляется
   - Повторный вызов → no-op
   - previewPolyline перегенерирован
   - Статистика пересчитана

3. **Ручное тестирование:**
   - SimulatedLocationProvider: режим с искусственными GPS gaps
   - Сравнить live-трек и post-processed трек визуально
   - Реальная поездка → сравнить с текущим поведением

## Что НЕ входит в scope

- CoreMotion / IMU sensor fusion — enhancement для v2 (foreground-only, marginal benefit)
- Map-matching (привязка к дорогам) — отдельная фича
- Серверная обработка треков
- UI-изменения (индикатор потери GPS)
- Изменение формата экспорта/бэкапа

## Будущие улучшения (не в этом scope)

- **CoreMotion fusion:** подключить гироскоп для коррекции heading при prediction в foreground. Продлит prediction с 10 до ~30 сек
- **Map-matching:** привязка к дорогам (офлайн OSM или онлайн Apple Maps) для точного восстановления длинных gaps
- **GPS signal quality indicator:** UI-индикатор когда GPS нестабилен
