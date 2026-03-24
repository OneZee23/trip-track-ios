# TripTrack -- PRD v1.0

> **Версия:** 1.0 MVP
> **Автор:** OneZee
> **Статус:** В разработке
> **Контекст:** Сезон 2 -- Proof of Work Challenge
> **Обновлено:** Март 2026

---

## 1. Executive Summary

**TripTrack** -- нативное iOS-приложение для автоматического трекинга автопутешествий. Персональный дорожный дневник: приложение записывает маршруты через GPS, а потом позволяет пережить поездки заново -- с фотографиями, статистикой, бейджами и картой исследованных территорий.

**Ключевая гипотеза:** Людям не хватает простого инструмента, который автоматически записывает поездки и превращает их в красивый дневник. Google Timeline умер, Polarsteps -- для отпусков, MileIQ -- бухгалтерия. Ниша "Google Photos для дорог" пуста.

**Платформа:** iOS 17+, iPhone, SwiftUI + MapKit + CoreData
**Бюджет:** $0 (solo-разработка) + $99/год Apple Developer Account
**Внешние зависимости:** Нет (100% нативные фреймворки)

### Ключевые преимущества

- **Полностью офлайн** -- все данные на устройстве, работает без интернета
- **Геймификация** -- Fog of War карта, 37+ бейджей, уровни водителя, XP-система
- **Энергоэффективность** -- Kalman-фильтр, батчинг записей, фоновый режим
- **Автоматизация** -- нажал "Старт" и поехал, приложение делает остальное
- **Красивый дневник** -- фото, заметки, статистика, contribution calendar

### Целевой рынок

- **Primary:** Россия (автопутешественники, дачники, регулярные водители)
- **Secondary:** СНГ, глобальный рынок (в будущем)
- **TAM:** ~10-15 млн активных автопутешественников в РФ

---

## 2. Идея и эволюция

### Ядро продукта

"Google Photos для дорог" -- ценность не в записи маршрута, а в моменте, когда через месяцы открываешь приложение и переживаешь поездку заново. Лента поездок с фотографиями, маршрутами и статистикой -- персональная история путешествий.

### Вдохновение

- **Strava** -- UX активного трекинга, HUD с live-данными
- **Duolingo** -- система бейджей, XP, уровней, celebration-анимации
- **Drive2** -- дневник автомобилиста, эмоциональная привязка к машине
- **Apple Calendar** -- contribution calendar, collapsible week/month view
- **NFS Most Wanted** -- Fog of War карта исследованных территорий

### Философия дизайна

Минимализм и стиль. iOS 26+ Liquid Glass design -- frosted glass surfaces, translucency, depth layers. Pixel-art акцент только для логотипа и уровня водителя. Все остальное -- чистый современный UI.

---

## 3. Проблема и бизнес-цели

### 3.1. Проблема

Человек с машиной ездит на дачу, горнолыжку, к родителям, в автопутешествия. Хочет видеть историю поездок, вспоминать маршруты, отслеживать статистику. Существующие решения не подходят:

- **Навигаторы** (Google Maps, Яндекс) -- слишком сложные, не дневник, privacy concerns
- **Фитнес-трекеры** (Strava, Runkeeper) -- заточены под бег/велосипед, не авто
- **Travel-журналы** (Polarsteps, Tripsy) -- для отпусков, ручной ввод
- **GPS-логгеры** (GPX Tracker) -- голые данные, нет UX

**Личная боль:** Google Timeline умер. Нет единого места, где хранятся все поездки с маршрутами, фотографиями и статистикой.

### 3.2. Бизнес-цели

| Цель | Метрика | Приоритет |
|------|---------|-----------|
| Валидация продукта | Ежедневное личное использование 30+ дней | P0 |
| App Store релиз | Публикация v1.0 | P0 |
| Первые пользователи | 1,000 установок | P1 |
| Retention | D7 > 30%, D30 > 15% | P1 |
| Органический рост | 5,000 установок без рекламы (ASO) | P2 |

### 3.3. Гипотеза

> Если дать водителю инструмент, где запись поездки = один тап, а история выглядит как красивый дневник с маршрутами, фото и бейджами -- он будет возвращаться, потому что: (а) запись автоматическая, (б) Fog of War карта мотивирует исследовать, (в) бейджи и XP дают дофамин.

---

## 4. Целевая аудитория

### Персона 1: "Алексей -- Путешественник"

**Демография:**
- Возраст: 28-45 лет
- Пол: 65% мужчины, 35% женщины
- Доход: средний+
- Локация: крупные города РФ
- Устройство: iPhone 12 и новее

**Психография:**
- Любит автопутешествия (3-5 поездок в год + регулярные дачные)
- Ценит визуальный контент и сторителлинг
- Интересуется статистикой и достижениями
- Предпочитает простые, красивые приложения

**Боли:**
- Забывает детали прошлых поездок
- Нет единого места для истории маршрутов
- Сложные приложения с избыточными функциями
- Расход батареи при GPS-трекинге

**Jobs To Be Done:**
- "Я хочу автоматически записывать все мои поездки"
- "Я хочу видеть карту мест, где я был"
- "Я хочу через полгода вспомнить, как мы ехали на Алтай"
- "Я хочу мотивацию посетить новые регионы"

### Персона 2: "Марина -- Блогер-путешественник"

**Демография:**
- Возраст: 22-35 лет
- Активный блогер в Instagram/TikTok
- Частые поездки (8-12 в год)

**Боли:**
- Нужен красивый контент для соцсетей
- Сложно вспомнить детали маршрута для блога
- Хочется уникального визуального контента (Fog of War, бейджи)

**Anti-персона:** люди, ищущие навигатор, КБЖУ-трекер, бухгалтерию пробега для налогов.

---

## 5. Scope: MVP

### 5.1. Must Have

| # | Фича | Описание |
|---|------|----------|
| M1 | GPS-трекинг | Ручной старт/стоп, фоновая запись, Kalman-фильтр |
| M2 | Tracking HUD | Полноэкранная карта + frosted glass HUD: скорость, высота, время, расстояние |
| M3 | Polyline на карте | Orange route с glow-эффектом, Catmull-Rom сглаживание, green dot на старте |
| M4 | Лента поездок (Feed) | Группировка по месяцам, карточки с превью маршрута, фильтры, пагинация |
| M5 | Contribution Calendar | Неделя/месяц, intensity по километражу, тап на день = фильтр ленты |
| M6 | Детали поездки | Карта маршрута, статистика, фотографии, заметки, редактируемое название |
| M7 | Итоги поездки | Summary sheet после остановки: маршрут, статистика, XP, бейджи |
| M8 | Fog of War карта | Geohash-6 тайлы, fog overlay, visited tiles, города/регионы |
| M9 | Бейджи (37+) | Milestone + repeatable, 4 категории, celebration overlay с конфетти |
| M10 | XP и уровни | 30 уровней водителя, 7 рангов, XP за км + бонусы |
| M11 | Уровни авто | 10 уровней на автомобиль по км |
| M12 | Профиль | Уровень водителя, автомобиль, аватар, статистика |
| M13 | Гараж | Мульти-авто, emoji, одометр, уровни |
| M14 | Настройки | Тема (system/light/dark), язык (RU/EN) |
| M15 | Онбординг | 3 страницы: welcome, recording, location permission |
| M16 | CoreData persistence | Офлайн хранение, async saves, binary polylines |
| M17 | Junk filtering | Автоудаление поездок <500m AND <2min |
| M18 | Фото в поездках | Добавление/удаление фото, fullscreen gallery |

### 5.2. Should Have (v1.1)

| # | Фича |
|---|------|
| S1 | Статистика -- детальный dashboard (графики, рекорды, heatmap) |
| S2 | Road Collection -- система коллекционирования дорог |
| S3 | Калькулятор топлива (расход, стоимость) |
| S4 | Экспорт GPX |
| S5 | Share card (скриншот маршрута для соцсетей) |

### 5.3. Won't Have (MVP)

| # | Фича | Причина |
|---|------|---------|
| W1 | Автостарт (motion detection) | Сложность + ненадежность без тестирования на реальных устройствах |
| W2 | Подписка / монетизация | Сначала валидация продукта |
| W3 | Backend / синхронизация | Офлайн-first, нет сервера |
| W4 | Social features | Вне scope MVP |
| W5 | Apple Watch / CarPlay | Вне scope MVP |
| W6 | Офлайн-карты (OpenStreetMap tiles) | MapKit работает с кешированием |
| W7 | Android | Только iOS |

### 5.4. Реализовано сверх плана (MVP)

| # | Фича | Описание |
|---|------|----------|
| E1 | Sun-based map theme | Авто-переключение темы карты по закату/рассвету |
| E2 | Simulated location provider | Dev joystick для тестирования без реальной езды |
| E3 | Батчинг GPS-точек | 10 точек или 15 сек -- запись пачками для экономии I/O |
| E4 | GPS accuracy indicator | Зеленый/желтый/красный индикатор точности |
| E5 | Recording banner | Floating banner на других табах при активной записи |
| E6 | Стикеры автомобиля | 9 коллекционных стикеров по milestone-ам |

---

## 6. Функциональные требования

### FR-01: GPS-трекинг

**User Story:** Как водитель, я хочу записать маршрут поездки, нажав одну кнопку, чтобы потом его просмотреть.

**Acceptance Criteria:**
- Кнопка "Start trip" на экране Recording (idle state)
- Background location updates -- запись продолжается при заблокированном экране и на других табах
- Kalman-фильтр сглаживает GPS-jitter
- Outlier rejection: отбрасывание точек с accuracy >50m и скоростью >300 km/h
- Батчинг: точки сохраняются пачками (10 шт или каждые 15 сек)
- Pause/Resume без потери данных
- Stop -> Trip Completion Summary sheet

### FR-02: Tracking HUD

**User Story:** Как водитель, я хочу видеть скорость, расстояние и время прямо на карте, чтобы не отвлекаться.

**Acceptance Criteria:**
- Полноэкранная MapKit карта с orange polyline
- Compact HUD (frosted glass, bottom sheet):
  - Скорость (44pt, monospacedDigit, animated)
  - Высота (m), длительность (MM:SS), расстояние (km)
- GPS accuracy indicator (top-left corner)
- Map controls (right side): location tracking (3 states), zoom
- Auto-zoom: camera distance адаптируется к скорости

### FR-03: Лента поездок (Feed)

**User Story:** Как пользователь, я хочу видеть историю поездок сразу при открытии приложения.

**Acceptance Criteria:**
- Feed -- главный экран, default tab при запуске
- Группировка по месяцам с collapsible section headers
- Trip Card: vehicle emoji, название, дата, регион, превью маршрута, статистика (km, время, avg speed), бейджи
- Contribution Calendar: collapsed (неделя) / expanded (месяц), intensity по км
- Quick Stats Bar: количество поездок, общий км, общее время
- Filter Bar: регион, дата, расстояние, авто -- через bottom sheet
- LazyVStack с пагинацией
- Swipe to delete (с подтверждением)
- Empty state: иконка + "No trips yet" + "Tap Record to start"

### FR-04: Детали поездки

**User Story:** Как пользователь, я хочу просмотреть подробности конкретной поездки.

**Acceptance Criteria:**
- Интерактивная карта маршрута (45% высоты экрана), speed color-coding (green -> red)
- Редактируемое название поездки
- Stats grid (2 колонки): расстояние, длительность, avg speed, max speed, elevation gain, max altitude
- Секция бейджей (если заработаны)
- Секция фотографий: горизонтальная сетка, добавление/удаление, fullscreen gallery
- Секция заметок: editable text area

### FR-05: Fog of War карта

**User Story:** Как путешественник, я хочу видеть карту исследованных территорий, чтобы мотивироваться ездить в новые места.

**Acceptance Criteria:**
- Geohash-6 tiles (~0.72 km^2)
- Fog overlay: visited tiles cleared, unvisited fogged
- Все recorded polylines отображаются как cleared corridors
- Progress card: visited tiles, города, регионы, percentage
- Список городов с progress bars
- Tap -> fullscreen fog map

### FR-06: Бейджи и геймификация

**User Story:** Как пользователь, я хочу получать достижения за поездки, чтобы было интереснее.

**Acceptance Criteria:**
- 37+ бейджей в 4 категориях: Distance, Exploration, Special, Streaks
- Milestone (one-time) + Repeatable (с счетчиком)
- Hidden бейджи: "?" до открытия
- Grid-экран бейджей (3 колонки, секции по категориям)
- Badge Celebration: fullscreen overlay с конфетти, glow-анимацией, sequential presentation
- XP система: 1 XP/km, +20 первая поездка дня, +50 новый регион, x2 за 200+ km
- 30 уровней водителя, 7 рангов (Novice -> Legend)
- 10 уровней автомобиля по km

### FR-07: Профиль и гараж

**User Story:** Как пользователь, я хочу видеть свой прогресс и управлять автомобилями.

**Acceptance Criteria:**
- Профиль (modal sheet): уровень водителя, XP bar, автомобиль, аватар (emoji selector), навигация к Garage/Badges/Stats
- Гараж: список авто с emoji, одометром, уровнем; add/delete/select vehicle

### FR-08: Онбординг

**User Story:** Как новый пользователь, я хочу быстро понять что делает приложение и дать нужные разрешения.

**Acceptance Criteria:**
- 3 страницы TabView с page dots
- Page 1: Welcome + app intro
- Page 2: Recording feature
- Page 3: Location permission CTA + "Let's Go" button

### FR-09: Настройки

**Acceptance Criteria:**
- Тема: System / Light / Dark
- Язык: Русский / English
- Версия + build number

---

## 7. User Flows

### Запись поездки

```
Feed -> Tap Record tab -> "Start trip" -> [Driving...] -> Stop -> Trip Summary -> Done -> Feed (new trip at top)
```

### Просмотр истории

```
Feed -> Scroll -> Tap trip card -> Trip Detail (map, stats, photos, notes) -> Back
```

### Fog of War

```
Feed -> Tap Regions tab -> Progress card -> Tap fog map -> Fullscreen exploration map
```

### Бейджи

```
[Trip ends] -> Summary -> Done -> Badge Celebration (confetti) -> Continue -> Feed
```

### Drill-down фильтрация

```
Feed -> Tap calendar day -> Feed filters to day -> Tap "Filters" chip -> Bottom sheet -> Apply -> Filtered feed
```

### Навигация

```
Tab Bar (Liquid Glass, floating):
    |-- Feed (flag icon) -- default on launch
    |   |-- Profile (avatar button) -> sheet
    |   |   |-- Garage -> sheet
    |   |   |-- Badges -> sheet
    |   |   |-- Stats -> sheet
    |   |-- Settings (gear button) -> sheet
    |-- Record (car.fill, orange circle, center tab)
    |-- Regions (map icon)
```

---

## 8. Метрики успеха

| Метрика | Цель MVP |
|---------|----------|
| DAU / MAU | > 20% |
| D7 retention | > 30% |
| D30 retention | > 15% |
| Поездок / неделю (active user) | > 3 |
| Время записи (median) | > 15 min |
| Crash-free rate | >= 99.5% |
| App Store rating | > 4.5 |
| GPS accuracy | <20m в 90% случаев |
| Battery drain | <5% в час при трекинге |
| Onboarding completion | > 70% |
| First trip recorded | > 50% в первые 7 дней |

---

## 9. Конкурентный анализ

| Приложение | Тип | Сильные стороны | Слабые стороны | Отличие TripTrack |
|-----------|-----|-----------------|----------------|-------------------|
| Google Maps Timeline | Автотрекинг | Автоматический, всегда включен | Мертв (2024), privacy concerns, нет геймификации | Privacy-first, офлайн, геймификация |
| Strava | Фитнес-трекер | GPS accuracy, social | Для бега/велосипеда, не авто | Заточено под автопутешествия |
| Polarsteps | Travel journal | Красивый дизайн, фото | Ручной ввод, для отпусков | Автоматический GPS, для любых поездок |
| MileIQ | Бухгалтерия пробега | Авто-детекция | Утилитарный, нет дневника | Эмоциональный продукт, не бухгалтерия |
| GPX Tracker | GPS logger | Простой, GPX export | Голые данные, нет UX | Красивый дневник, бейджи, fog map |
| Fog of World | Fog of War map | Уникальная концепция | Только карта, нет трекинга поездок | Полный дневник + fog map |

**Unique Value Proposition:**
TripTrack = Strava UX + Duolingo gamification + Google Photos storytelling, заточенное под автопутешествия.

---

## Appendix A: Roadmap

### v1.0 MVP (текущий)

- [x] MVVM + Service Layer архитектура
- [x] GPS-трекинг с Kalman-фильтром и батчингом
- [x] Tracking HUD (скорость, высота, время, расстояние)
- [x] MapKit с orange polyline и glow-эффектом
- [x] Лента поездок с contribution calendar
- [x] Детали поездки (карта, статистика, фото, заметки)
- [x] Fog of War карта (geohash-6)
- [x] 37+ бейджей с celebration overlay
- [x] XP и уровни водителя/авто
- [x] Профиль и гараж
- [x] Онбординг (3 страницы)
- [x] Локализация RU/EN
- [x] Темы dark/light/system
- [x] Junk trip filtering
- [ ] App Store submission

### v1.1 (planned)

- [ ] Stats dashboard (графики, рекорды, weekly chart, heatmap)
- [ ] Road Collection (5 rarity levels, mastery system)
- [ ] Fuel calculator
- [ ] GPX export
- [ ] Share card для соцсетей

### v1.2 (ideas)

- [ ] Auto-start (motion detection)
- [ ] Apple Watch companion
- [ ] CarPlay integration
- [ ] Widget (streak, total km)

### Future

- [ ] Backend sync (multi-device)
- [ ] Social features (friends, leaderboards)
- [ ] Challenges (visit N regions in a month)

---

> MVP в разработке. Планируемый релиз -- Q2 2026.
