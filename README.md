# TripTrack — автодневник поездок для iOS

> Google Photos для дорог. Записывает маршруты, помнит за тебя.

**Platform:** iOS (iPhone)
**Status:** v0.6.0 | **Started:** Jan 2026

---

## TL;DR

Нажал "Запись" -- поехал -- нажал "Стоп". Приложение автоматически назовет поездку по геокодингу, сохранит маршрут, скорость, высоту. Через месяц откроешь ленту -- а там все твои дороги. Scratch-карта покажет, где уже был.

Без регистрации. Без подписки. Русский и English. Готовится серверный синк.

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

### Социальное (v0.6)
- **Приватно по умолчанию** — все поездки приватные; пользователь сам решает какие публиковать. One-time миграция переводит все существующие поездки в приватные при апгрейде
- **Лента подписок** — публичные поездки тех на кого подписан + карусель "Предложенные" когда подписок мало. Paged tabs "Лента ↔ Мои" с горизонтальным свайпом
- **Публичные профили** — hero с баннером и градиентным фоном (8 вариантов), имя + ранг + LVL, stats grid (поездки/км/регионы/🔥 стрик), карточка активной машины (уровень + одометр), ряд последних ачивок, followers/following, последние поездки
- **Реакции** — `🔥 🏁 🏎️ 🛣️ 🗺️` через long-press. Top-3 самых популярных реакций с количествами прямо на карточке, полный breakdown в деталях поездки
- **Шеринг** — story-style 9:16 карточка с картой и метриками для Instagram/галереи + share-ссылка через бэкенд
- **Модерация** — block/unblock, репорты на пользователей и поездки, content-filter на названия поездок, список заблокированных
- **Discover** — поиск пользователей по имени + suggested карусель
- **"Посмотреть как видят другие"** — превью своего публичного профиля из настроек

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
Backend:     None yet (sync-ready data layer)
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
│   ├── SettingsManager.swift   -- профиль, XP, streak, userId
│   ├── SyncQueue.swift         -- очередь синк-операций с retry
│   ├── RemotePhotoStorage.swift -- protocol для облачного хранения фото
│   ├── PathSmoother.swift      -- сглаживание маршрута
│   └── NetworkMonitor.swift    -- мониторинг сети
├── Persistence/
│   ├── PersistenceController.swift
│   ├── TripRepository.swift    -- protocol + CoreData repository (CRUD abstraction)
│   └── TripTrack.xcdatamodeld/ -- CoreData schema v2 (8 entities, versioned)
├── ViewModels/
│   ├── MapViewModel.swift      -- запись, карта, бейджи, zoom
│   ├── FeedViewModel.swift     -- лента, фильтры, пагинация
│   └── TripsViewModel.swift    -- список поездок
├── Views/
│   ├── ContentView.swift       -- 3-tab layout
│   ├── Navigation/             -- CustomTabBar (glass), NavBackButton
│   ├── Tracking/               -- карта, HUD, спидометр, idle, summary
│   ├── Feed/                   -- лента, Strava-стиль карточки, календарь, фильтры, статистика
│   ├── Trips/                  -- список, детали, фото, share card, reactions breakdown
│   ├── Social/                 -- PublicProfileView, FollowListView, DiscoverView, ReportSheet, BlockedListView, StoryShareSheet, SuggestedUsersCarousel
│   ├── Regions/                -- scratch map, fog of war
│   ├── Roads/                  -- коллекция дорог
│   ├── Badges/                 -- бейджи, celebration, confetti
│   ├── Profile/                -- профиль, hero card, уровень, гараж, ProfileBackgroundPickerSheet, CloudSyncView, DebugLogsView
│   ├── Garage/                 -- управление машинами
│   ├── Onboarding/             -- онбординг (3 страницы)
│   ├── Map/                    -- MapViewRepresentable, glow overlay
│   ├── Theme/                  -- AppTheme, ThemeManager
│   └── Components/             -- переиспользуемые компоненты (SheetCloseButton, и др.)
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

### v0.1.0 MVP (done)

- [x] GPS-трекинг с фильтром Калмана и фоновой записью
- [x] Реалтайм HUD: скорость, высота, дистанция, время
- [x] Автоматический геокодинг названий поездок
- [x] Лента поездок с группировкой по месяцам
- [x] Детали поездки: карта, скорости, фото, редактирование
- [x] Scratch-карта территорий (fog of war, geohash)
- [x] Геймификация: 30+ бейджей, XP, уровни, ранги
- [x] CoreData persistence с batch saves
- [x] Тема (system/light/dark) и язык (RU/EN)

### v0.2.0 Fog of War 2.0 (done)

- [x] Мягкие радиальные градиенты вместо острых прямоугольников
- [x] Анимация рассеивания тумана при записи
- [x] Экран детальной информации о машине

### v0.3.0 Auto-Trip (done)

- [x] Автозапись поездок по Bluetooth
- [x] Детекция вождения через CMMotion
- [x] Трёхслойная детекция (Audio + CMMotion + Significant Location)
- [x] Уведомления с action buttons

### v0.4.0 Pre-Server Readiness (done)

- [x] CoreData Model Versioning (v1 → v2)
- [x] Codable на моделях (Trip, TrackPoint, TripPhoto, Vehicle)
- [x] TripRepository — CRUD абстракция за protocol
- [x] User Identity (локальный userId)
- [x] Photo Sync Readiness (upload status, remote URL)
- [x] SyncQueue (очередь операций с retry)
- [x] Тесты: Codable round-trip, SyncQueue

### v0.4.1 Sign in with Apple (done)

- [x] Авторизация через Apple ID в профиле
- [x] KeychainHelper для безопасного хранения credentials
- [x] Два состояния профиля: Guest / Signed In

### v0.4.2 Live Activity + Watch (done)

- [x] Fix: remind-режим не спамит уведомлениями
- [x] Fix: Live Activity при автостарте из бэкграунда
- [x] Fix: восстановление записи после перезапуска приложения
- [x] Live Activity на Apple Watch Smart Stack (iOS 18+)
- [x] Уведомление при автозавершении поездки
- [x] Кнопка "Остановить" в уведомлении об автостарте

### v0.4.3 -- v0.4.4 Auto-trip fixes (done)

- [x] Motion-ended больше не триггерит auto-stop (только GPS скорость + BT)
- [x] Split notification text (BT disconnect vs 20-min inactivity)
- [x] Junk filter расширен (maxSpeed<15 AND duration>180 → delete)
- [x] Feed auto-reload после авто-записи в фоне

### v0.5.0 Server Sync (done -- current)

- [x] Свой бэкенд (NestJS + PostgreSQL + JWT + Cloudflare R2)
- [x] Серверная верификация Apple identity token через JWKS
- [x] Client API layer (URLSession + JSON-RPC envelope + single-flight refresh)
- [x] Синхронизация trips / vehicles / settings / photos между устройствами
- [x] R2 photo storage (thumbnails cellular, originals Wi-Fi only)
- [x] Sync triggers: foreground, network restored, Wi-Fi connected, 5-мин таймер
- [x] Conflict resolution (optimistic concurrency + silent last-write-wins)
- [x] First sync после Sign in (все локальные данные уезжают)
- [x] Guest mode сохранён (sync opt-in)

### v0.6.0 — Social (shipped)

- [x] Strava-style карточки в ленте (`SocialFeedCardView`)
- [x] Публичные профили с hero, stats grid, активной машиной, ачивками, followers/following
- [x] Follow / unfollow, объединённая лента подписок + suggested users
- [x] Car-themed реакции `🔥 🏁 🏎️ 🛣️ 🗺️` через long-press, per-emoji pills, reaction breakdown
- [x] Шеринг поездки по ссылке через бэкенд + story-style share 9:16
- [x] Градиентные фоны профиля (8 вариантов)
- [x] Block / unblock, репорты (user + trip), content-filter на названия
- [x] Discover — поиск пользователей и suggested карусель
- [x] Unified back button, единый presentation chain для share sheet

### Future (ideas)

- [ ] Apple Watch companion app (старт/пауза/стоп с часов)
- [ ] Widgets (последняя поездка, статистика)
- [ ] Экспорт данных (GPX, CSV)
- [ ] Комментарии к поездкам
- [ ] Notifications — новые подписчики, реакции на поездки

---

## Версионирование

- **0.X** (0.1, 0.2, 0.3) -- стабильные протестированные релизы
- **0.X.Y** (0.1.1, 0.2.1) -- инкрементальные обновления

Подробности в [CHANGELOG.md](./CHANGELOG.md).

---

## Лицензия

MIT
