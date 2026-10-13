# TripTrack — road trip diary for iPhone

**TripTrack — Road Journal** is a free iPhone app that keeps a diary of your car
trips. It records each drive with GPS — in the background, from the Lock Screen,
or automatically when your car's Bluetooth stereo connects — and keeps the route,
speed, distance, photos, notes and stops. The **Atlas** is a fog of war map: the
world starts under fog and clears along the roads you have actually driven.

- Free: recording, trip history, photos, statistics, the Atlas, places, journeys
  and a garage of vehicles with their own odometer, fuel or electric use and costs.
- Optional **TripTrack PRO** subscription: profile and car card styles, avatar
  frames, route colours and manually added trips. Not offered on the Russian
  App Store storefront.
- No account needed to record. Sign in with Apple adds cloud sync, public
  profiles and a web viewer for your synced trips at
  [trip-track.app](https://trip-track.app).
- iPhone, iOS 17 or later. 13 languages. No Android version yet.

[App Store](https://apps.apple.com/us/app/triptrack-road-journal/id6760650361) ·
[Website](https://trip-track.app) · [Changelog](CHANGELOG.md)

---

# TripTrack — автодневник поездок для iPhone

TripTrack сохраняет поездки, маршруты, фотографии и статистику. Начните запись,
поставьте отметку в интересном месте, а позже найдите поездку в истории или
посмотрите пройденные дороги в личном атласе.

[Сайт и веб-кабинет](https://trip-track.app) · [История изменений](CHANGELOG.md)

## Статус

В App Store — **0.8.6 (75)**, выпущена 8 октября 2026. **0.8.9 (78)** отправлена
на проверку Apple 11 октября и заменила заявку 0.8.8, включая все её изменения;
выпуск ручной. Состав и проверки —
[документ кандидата](docs/releases/0.8.9/candidate-78.md).

## Возможности

- **Запись поездок.** Ручной запуск, фоновая запись, пауза и продолжение,
  скорость, время, расстояние и качество GPS. Автотрекинг может сохранять
  черновики, которые нужно подтвердить перед добавлением в историю и атлас.
- **История и детали.** Поиск, календарь, фильтры, маршрут с цветом по скорости,
  полноэкранная карта и воспроизведение поездки. Название, заметки, фотографии
  и отметки помогают вспомнить, что было по дороге.
- **Атлас и места.** Открытые дороги и регионы с датой первого въезда; виды
  «Туман», «Ночь» и «Клетки», постер атласа, сохранённые места и история посещений.
- **Гараж.** Несколько машин, одометр, расход и расчёт стоимости поездок.
  Поддерживаются топливные, электрические и гибридные автомобили.
- **Профиль.** Уровни, достижения, коллекция дорог и оформление.
- **Обмен поездками.** Подписки, реакции, публичные профили и карточки для
  отправки друзьям. Поездки приватны по умолчанию; публикацию выбирает владелец.
- **Вход через Apple и облачная синхронизация.** История и данные аккаунта
  синхронизируются между устройствами. Веб-кабинет на
  [trip-track.app](https://trip-track.app) позволяет смотреть синхронизированные
  поездки на карте с компьютера. Сервер и сайт находятся в отдельных проектах.
- **Приватная зона.** Дом отмечается локально. Координаты внутри выбранной зоны
  удаляются из отправляемых маршрутов, превью, фотографий и отметок;
  исходная запись остаётся на устройстве.
- **Live Activity.** Статус записи на экране блокировки и в Dynamic Island.
  Полноценное приложение для CarPlay пока не включено в релиз.

Основная запись, история, атлас и синхронизация бесплатны. В **0.8.4** добавлена
необязательная подписка **PRO**: дополнительное оформление и ручное добавление
поездок с построением маршрута по дорогам. Такие поездки учитываются в пробеге
и атласе, но не дают XP и достижений. Сохранённое платное оформление возвращается
после возобновления подписки. Разовые чаевые ничего не разблокируют.

Приложение поддерживает **13 языков**: русский, English, Deutsch, Español,
Français, Italiano, Polski, Türkçe, Bahasa Indonesia, Українська, Português,
Қазақша и Filipino. Есть системная, светлая и тёмная темы, метрические и
имперские единицы.

**Платформа:** iPhone, iOS 17 и новее. Android-версии пока нет.

## Технологии

| Область | Реализация |
|---|---|
| Интерфейс | SwiftUI, UIKit для карт и переходов |
| Карты и атлас | MapKit, Metal |
| Запись | Core Location, Core Motion |
| Локальные данные | Core Data, схема v23 в 0.8.9 (78) |
| Аккаунт и синхронизация | Sign in with Apple, HTTP API, локальная очередь изменений |
| Подписка и чаевые | StoreKit 2 |
| Виджеты записи | ActivityKit, WidgetKit, App Intents |
| Диагностика | Sentry — внешняя зависимость через Swift Package Manager |
| Сборка | Swift 5.9, Xcode, XcodeGen |

## Локальная разработка

Нужны macOS, Xcode с установленным iOS SDK и XcodeGen. Для кандидата 0.8.4
использовался SDK iOS 26.5; минимальная версия системы приложения — iOS 17.

1. Установите XcodeGen, например через Homebrew: `brew install xcodegen`.
2. Скопируйте `Local.xcconfig.example` в `Local.xcconfig` и задайте свои
   `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER` и адреса API. Файл с локальными
   настройками исключён из Git; не перезаписывайте его, если он уже настроен.
3. Выполните `xcodegen generate` и откройте `TripTrack.xcodeproj`.
4. Выберите схему `TripTrack`, конфигурацию Debug и доступный симулятор или iPhone.

`project.yml` — источник конфигурации проекта. Изменения настроек вносите туда,
а затем повторно генерируйте проект. Для входа через Apple и синхронизации нужны
настроенные идентификаторы Apple и доступный сервер. В Debug адрес API отделён
от Release; пустой `SENTRY_DSN` отключает отправку диагностики.

Перед работой прочитайте [CLAUDE.md](CLAUDE.md): там правила проекта, команды
проверок и ограничения работы с пользовательскими данными. Unit-тесты находятся
в `TripTrackTests`, UI-сценарии — в `TripTrackUITests`. Результаты конкретной
релизной сборки фиксируются в документации кандидата, а не выводятся из номера
версии в проекте.

## Структура репозитория

```text
TripTrack/               iPhone-приложение: модели, запись, интерфейс, синхронизация
TripTrackShared/         общие модели и действия приложения и расширения
TripTrackLiveActivity/   Live Activity и Dynamic Island
TripTrackTests/          unit-тесты
TripTrackUITests/        UI-сценарии и проверки карт
Tools/                  инструменты разработки и подготовки ресурсов
docs/                   архитектура, тексты стора и документы релизов
project.yml             конфигурация XcodeGen
```

- [Кандидат 0.8.4 (73)](docs/releases/0.8.4/candidate-73.md) — состав,
  выполненные проверки и известные ограничения.
- [Чек-лист релиза](docs/releases/0.8.4/checklist.md) — подготовка и выпуск.
- [Навигация по документации](docs/README.md) — расположение материалов.
- [CHANGELOG](CHANGELOG.md) — история изменений; старые разделы описывают
  соответствующие версии, а не текущее состояние приложения.

## Лицензия

[MIT](LICENSE), © 2026 OneZee.
