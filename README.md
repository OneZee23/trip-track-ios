# TripTrack — автодневник поездок для iOS

> Google Photos для дорог. Записывает маршруты, помнит за тебя.

**Platform:** iOS (iPhone)
**Status:** v0.1.0 | **Started:** Jan 2026

---

## TL;DR

Нажал "Запись" -- поехал -- нажал "Стоп". Приложение автоматически назовет поездку по геокодингу, сохранит маршрут, скорость, высоту. Через месяц откроешь ленту -- а там все твои дороги. Scratch-карта покажет, где уже был.

Без регистрации. Без облака. Без подписки. Русский и English.

---

## Идея

Ценность не в момент записи. Ценность -- когда через полгода открываешь и видишь: вот эта поездка на дачу в мае, вот ночной бросок в Питер, вот горнолыжка в феврале.

**Ниша пуста.** Google Timeline фактически мертв. Polarsteps -- для отпусков и путешествий за границу. MileIQ -- бухгалтерия пробега для бизнеса. Для человека с машиной, который просто ездит по жизни -- на дачу, к родителям, на горнолыжку -- ничего нет.

TripTrack заполняет эту нишу: минимальный effort при записи, максимальная ценность при просмотре.

---

## Как работает

```
1. Открыл приложение -- карта с текущей позицией
2. Нажал оранжевую кнопку -- запись пошла
3. Едешь -- видишь скорость, высоту, дистанцию, маршрут на карте
4. Нажал "Стоп" -- поездка сохранена
5. Приложение само назовет её: "Москва -- Тула" (геокодинг)
6. Экран итогов: карта маршрута, статистика, можно добавить фото
7. Поездка появилась в ленте с группировкой по месяцам
```

---

## Фичи

### Запись маршрута
- GPS-трекинг с фильтром Калмана (сглаживание через `SmoothTrackManager`)
- Фоновая запись (background location)
- Реалтайм-показатели: скорость, высота, дистанция, время
- Сворачиваемая панель метрик (compact/expanded HUD)
- Спидометр с визуальной шкалой
- Индикатор качества GPS-сигнала
- Компас и отслеживание направления
- Автоматический zoom по скорости движения
- Плавная анимация "головы" маршрута с glow-эффектом
- Пауза/возобновление записи
- Автоматическая тема карты по времени суток (sunrise/sunset calculator)
- Экран итогов после остановки: карта маршрута, статистика, XP, бейджи

### Лента поездок
- Группировка по месяцам с collapsible-секциями
- Contribution calendar (GitHub-style heatmap по км за день)
- Быстрая статистика: общий пробег, количество поездок, время
- Фильтрация по региону, поиск по названию
- Фильтр по дате через calendar picker
- Пагинация (20 поездок на страницу)
- Swipe-удаление с undo-таймером и toast
- Skeleton-загрузка карточек
- Empty state с предложением начать запись

### Детали поездки
- Интерактивная карта с маршрутом (parallax-stretch при скролле)
- Маршрут раскрашен по скорости (градиент)
- Статистика: дистанция, время, средняя/макс. скорость, набор высоты
- Фотографии поездки с полноэкранным просмотром
- Редактирование названия (inline edit)
- Автоматический геокодинг с retry при ошибке
- Share-карточка для соцсетей (маршрут + статистика)
- Добавление заметок

### Карта территорий
- Scratch-карта (fog of war) на основе geohash
- Fullscreen-режим карты
- Статистика: количество посещенных тайлов
- Список посещенных городов и регионов
- Все маршруты на одной карте (polyline overlay)

### Геймификация
- 30+ бейджей в 4 категориях: дистанция, исследование, особые, серии
- Скрытые бейджи (hidden badges)
- Повторяемые бейджи (repeatable)
- XP-система: 1 XP за км, бонусы за длинные поездки, новые регионы, первую поездку дня
- Уровни водителя (1-30) с рангами: Новичок, Водитель, Путешественник, Исследователь, Навигатор, Дальнобойщик, Легенда
- Celebration-экран с конфетти при получении бейджа
- Профиль с аватаром, уровнем, стриком

### Коллекция дорог
- Автоматическое обнаружение часто проезжаемых дорог
- Уровни освоения дороги
- Фильтрация по редкости

### Настройки
- Тема: системная / светлая / темная
- Язык: русский / английский -- переключается на лету
- Dev mode: виртуальный джойстик для тестирования без GPS
- Версия и номер сборки

### Онбординг
- 3 страницы: приветствие, описание записи, запрос геолокации
- Swipe между страницами, кнопка "Поехали!" на финальной

---

## Стек

```
Framework:   SwiftUI
Language:    Swift 5.9
Maps:        MapKit (MKMapView representable)
Storage:     CoreData (8 entities)
Location:    CoreLocation (background modes)
Charts:      Swift Charts
Min iOS:     17.0+
Build:       xcodegen + Xcode
Backend:     None (local-only)
Deps:        Zero (100% native)
```

---

## Структура

```
TripTrack/
├── App/                        -- @main entry point
├── Models/                     -- Trip, TrackPoint, Badge, Vehicle, TripPhoto, GamificationModels
├── Localization/               -- LanguageManager, AppStrings (RU/EN)
├── Services/
│   ├── TripManager.swift       -- CRUD, геокодинг, батчинг, фото
│   ├── LocationManager.swift   -- dual-mode: real GPS + simulated
│   ├── LocationProvider.swift  -- протокол провайдера
│   ├── RealGPSProvider.swift   -- CoreLocation
│   ├── SimulatedLocationProvider.swift -- джойстик для dev mode
│   ├── SmoothTrackManager.swift -- Kalman filter, плавная анимация трека
│   ├── GamificationManager.swift -- XP, уровни, бейджи
│   ├── BadgeManager.swift      -- проверка и выдача бейджей
│   ├── TerritoryManager.swift  -- geohash, scratch-карта
│   ├── RoadCollectionManager.swift -- коллекция дорог
│   ├── GeohashEncoder.swift    -- кодирование geohash
│   ├── SunCalculator.swift     -- sunrise/sunset для авто-темы карты
│   ├── PhotoStorageService.swift -- сохранение фото в Documents
│   ├── SettingsManager.swift   -- профиль, XP, streak
│   ├── PathSmoother.swift      -- сглаживание маршрута
│   └── NetworkMonitor.swift    -- мониторинг сети
├── Persistence/
│   ├── PersistenceController.swift
│   └── TripTrack.xcdatamodeld/ -- CoreData schema (8 entities)
├── ViewModels/
│   ├── MapViewModel.swift      -- запись, карта, бейджи, zoom
│   ├── FeedViewModel.swift     -- лента, фильтры, пагинация
│   └── TripsViewModel.swift    -- список поездок
├── Views/
│   ├── ContentView.swift       -- 3-tab layout
│   ├── Navigation/             -- CustomTabBar (glass)
│   ├── Tracking/               -- карта, HUD, спидометр, idle, summary
│   ├── Feed/                   -- лента, карточки, календарь, фильтры, статистика
│   ├── Trips/                  -- список, детали, фото, share card
│   ├── Regions/                -- scratch map, fog of war
│   ├── Roads/                  -- коллекция дорог
│   ├── Badges/                 -- бейджи, celebration, confetti
│   ├── Profile/                -- профиль, уровень, гараж
│   ├── Garage/                 -- управление машинами
│   ├── Settings/               -- настройки
│   ├── Onboarding/             -- онбординг (3 страницы)
│   ├── Map/                    -- MapViewRepresentable, glow overlay
│   ├── Theme/                  -- AppTheme, ThemeManager
│   └── Components/             -- переиспользуемые компоненты
└── Resources/                  -- Assets
```

---

## Быстрый старт

### Что нужно

- macOS с Xcode 15+
- iOS Simulator или iPhone (iOS 17+)
- Apple Developer account (бесплатный для симулятора)
- Homebrew

### Сборка

```bash
git clone <repo-url>
cd trip-track

cp Local.xcconfig.example Local.xcconfig   # вписать PRODUCT_BUNDLE_IDENTIFIER и DEVELOPMENT_TEAM
brew install xcodegen
xcodegen generate
open TripTrack.xcodeproj
```

В Xcode:
1. Выбрать Team в Signing & Capabilities
2. Выбрать симулятор: **iPhone 16**
3. **Cmd+R**

### CLI-сборка

```bash
xcodebuild build -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Документация

| Документ | Описание |
|----------|----------|
| [Business Requirements](./mvp/business-requirements.md) | Продуктовые требования, сценарии, целевая аудитория |
| [Technical Solution](./mvp/technical-solution.md) | Архитектура, модель данных, технические решения |
| [App Store Metadata](./mvp/appstore-metadata.md) | Текущие metadata, review notes и privacy URLs для релиза |
| [CLAUDE.md](./CLAUDE.md) | Инструкции для Claude Code: архитектура, правила, паттерны |

---

## Roadmap

### v0.1.0 MVP (done -- current)

- [x] GPS-трекинг с фильтром Калмана и фоновой записью
- [x] Реалтайм HUD: скорость, высота, дистанция, время
- [x] Автоматический геокодинг названий поездок
- [x] Лента поездок с группировкой по месяцам
- [x] Contribution calendar (heatmap по дням)
- [x] Детали поездки: карта, скорости, фото, редактирование
- [x] Scratch-карта территорий (fog of war, geohash)
- [x] Геймификация: 30+ бейджей, XP, уровни, ранги
- [x] Коллекция дорог
- [x] Профиль с аватаром и статистикой
- [x] Онбординг (3 страницы)
- [x] Тема (system/light/dark) и язык (RU/EN)
- [x] CoreData persistence с batch saves
- [x] Автоудаление мусорных поездок (<500м AND <2мин)
- [x] Dev mode с виртуальным джойстиком
- [x] Share-карточки для поездок

### Future (ideas)

- [ ] Apple Watch companion (быстрый старт записи)
- [ ] Widgets (последняя поездка, статистика за неделю)
- [ ] Push-уведомления (забытая запись, стрик)
- [ ] Экспорт данных (GPX, CSV)
- [ ] Автостарт записи (motion detection)
- [ ] iCloud sync
- [ ] Мультиязычный геокодинг
- [ ] Fuel tracking

---

## Версионирование

- **0.X** (0.1, 0.2, 0.3) -- стабильные протестированные релизы
- **0.X.Y** (0.1.1, 0.2.1) -- инкрементальные обновления

Подробности в [CHANGELOG.md](./CHANGELOG.md).

---

## Лицензия

MIT
