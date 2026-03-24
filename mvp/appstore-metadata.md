# TripTrack — App Store Metadata v0.1.0

## App Name
**EN:** TripTrack — Drive Journal
**RU:** TripTrack — Дневник поездок

## Subtitle (30 chars max)
**EN:** Auto trip diary with GPS
**RU:** Автодневник с GPS-трекингом

---

## Description (EN)

TripTrack automatically records your car trips — route, speed, altitude, and distance. Just drive. Open the app later to relive every road you've taken.

**Record**
- GPS tracking with Kalman filter for smooth, accurate routes
- Background recording — works with the screen off
- Real-time speed, altitude, and distance on a collapsible HUD
- Compass and heading indicator on the map

**Relive**
- Trip feed organized by month with contribution calendar
- Detailed trip view: speed-colored route on the map, altitude stats, photos
- Auto-generated trip names from geocoding (Moscow → Saint Petersburg)
- Filter trips by region

**Explore**
- Scratch map — see which territories you've covered via geohash fog-of-war
- Total distance, trip count, and duration stats
- Speed graph for every trip

**Customize**
- Dark, light, and system themes
- Russian and English languages
- No account required, no cloud — your data stays on your device

No subscriptions. No ads. No external dependencies. 100% native Swift.

---

## Description (RU)

TripTrack автоматически записывает автопоездки — маршрут, скорость, высоту и дистанцию. Просто езжайте. Откройте приложение потом, чтобы пережить каждую дорогу заново.

**Запись**
- GPS-трекинг с фильтром Калмана для точных маршрутов
- Фоновая запись — работает с выключенным экраном
- Скорость, высота и дистанция в реальном времени на сворачиваемой панели
- Компас и индикатор направления на карте

**Переживайте заново**
- Лента поездок по месяцам с календарём активности
- Детальный просмотр: маршрут на карте с цветом скорости, статистика высоты, фото
- Автоматические названия поездок через геокодинг (Москва → Санкт-Петербург)
- Фильтрация по региону

**Исследуйте**
- Скретч-карта — видите какие территории вы покрыли через geohash-туман войны
- Общая статистика: дистанция, количество поездок, время в пути
- График скорости для каждой поездки

**Настройте под себя**
- Тёмная, светлая и системная темы
- Русский и английский языки
- Без аккаунта, без облака — данные остаются на устройстве

Без подписок. Без рекламы. Без внешних зависимостей. 100% нативный Swift.

---

## Keywords (100 chars max)
**EN:** trip,tracker,gps,drive,road,journal,diary,route,speed,map,car,travel,log,distance,altitude
**RU:** поездка,трекер,gps,маршрут,дневник,скорость,карта,авто,путешествие,дорога,дистанция,высота

---

## Promotional Text (170 chars max)
**EN:** Your personal road diary. Every trip recorded automatically — route, speed, altitude. Just drive and relive the journey later.
**RU:** Ваш личный дневник дорог. Каждая поездка записывается автоматически — маршрут, скорость, высота. Просто езжайте.

---

## What's New (v0.1.0)
**EN:** First release! GPS trip recording with Kalman filter, trip feed with monthly grouping, detailed stats, scratch map, photos, dark/light themes, RU/EN languages.
**RU:** Первый релиз! GPS-запись поездок с фильтром Калмана, лента по месяцам, детальная статистика, скретч-карта, фото, тёмная/светлая темы, RU/EN языки.

---

## Review Notes (for Apple reviewer)

Thank you for reviewing TripTrack!

**What the app does:**
TripTrack is a personal trip diary that records GPS routes while driving. It stores trip data (route, speed, altitude, distance) locally on the device using CoreData. No account or cloud service is required.

**How to test:**
1. Launch the app. You'll see a 3-page onboarding — swipe through it.
2. Grant location permission (required for GPS recording).
3. Tap the record button on the main map screen to start a trip.
4. Walk or drive for a minute to generate some track points.
5. Tap stop to end the trip. You'll see a summary screen.
6. Switch to the Feed tab to see your recorded trip.
7. Tap a trip card to view detailed stats, route on map, and photos.

**Location usage:**
The app uses location services in the foreground and background to record GPS routes during active trip recording. Location data is stored locally and never transmitted to any server.

**No login required.** The app works entirely offline with local data.

---

## App Category
**Primary:** Navigation
**Secondary:** Travel

## Age Rating
4+ (no objectionable content)

## Privacy
- **Data collected:** Location (used for GPS route recording)
- **Data NOT collected:** Name, email, phone, payment, contacts, browsing history, identifiers, diagnostics
- **Data linked to user:** None
- **Data used for tracking:** None
- **Third-party sharing:** None

---

## Copyright
2026 OneZee

## Support URL
https://github.com/OneZee23/trip-track-ios/issues

## Privacy Policy URL
https://onezee23.github.io/trip-track-ios/docs/privacy-policy.html
