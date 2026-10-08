# App Store Connect — 0.8.6

Пакет для **0.8.6 (75)** от 7 октября 2026. Единственное изменение поведения
приложения относительно 0.8.5 (74) — исправление маски жеста слайдера
запуска записи: `.none` → `.subviews` в готовом состоянии
`SlideToStartView`. Репорт получен с iPhone 15 Pro Max на iOS 17.6.1;
наличие репорта не является подтверждением проверки исправления на этой ОС.
Архив загружен, метаданные и 16 карточек сохранены. 7 октября в 15:39 МСК
подтверждена отправка 0.8.6 (75) на App Review. После одобрения Apple
версия выпущена вручную **8 октября 2026**: в **08:44:37 МСК** подтверждены
`READY_FOR_SALE` / `READY_FOR_DISTRIBUTION` и сборка 75 (`VALID`).
Все 16 карточек одобрены и включены в выпущенную версию. В 08:45 МСК
российская публичная витрина ещё возвращала 0.8.5 и прежние три карточки;
распространение обновления по витринам пока не подтверждено.
Проверки и ограничения — в [документе кандидата](candidate-75.md).

Предыдущая **0.8.5 (74) выпущена 7 октября (подтверждено в 15:06 МСК)**
с прежними тремя карточками в RU/EN. Новый полный комплект относится к 0.8.6.

Обновлены What's New, Review Notes и iPhone-скриншоты RU/EN: по восемь
утверждённых карточек в каждой локали. Остальные локали скриншотов и iPad
не заменялись. Описание приложения, ключевые слова, цены, продукты PRO
и чаевые, ссылки и сведения о приватности сохранены. Карточки показывают
существующие возможности, а не новые функции этого исправления.

В App Store Connect остаются прежние **12 локалей**. Слот **Finnish (`fi`)
содержит Filipino, как в [0.8.5](../0.8.5/app-store.md); его не переименовываем.
Казахской локали ASC нет.

Порядок карточек и требования к файлам:
[screenshots-2026-10.md](../../store/screenshots-2026-10.md).
Точные PNG находятся вне репозитория:
`~/Desktop/TripTrack-Reviews/2026-10-07-app-store/exports/{ru,en}/triptrack-{lang}-01..08.png`.
Загрузка и порядок карточек подтверждены чтением App Store Connect.

## What's New по локалям

### English (U.S.)

```text
Fixed an issue that could prevent the recording slider from responding.
```

### Russian

```text
Исправлена ошибка, из-за которой бегунок запуска записи мог не реагировать на свайп.
```

### German

```text
Ein Fehler wurde behoben, durch den der Schieberegler zum Starten einer Aufzeichnung nicht reagieren konnte.
```

### Spanish (Spain)

```text
Se ha corregido un problema que podía impedir que el control deslizante para iniciar la grabación respondiera.
```

### French

```text
Correction d’un problème qui pouvait empêcher le curseur de démarrage de l’enregistrement de réagir.
```

### Italian

```text
Risolto un problema che poteva impedire al cursore per avviare la registrazione di rispondere.
```

### Polish

```text
Naprawiono błąd, przez który suwak rozpoczynający nagrywanie mógł nie reagować.
```

### Indonesian

```text
Memperbaiki masalah yang dapat membuat penggeser untuk memulai perekaman tidak merespons.
```

### Turkish

```text
Kaydı başlatma kaydırıcısının yanıt vermemesine neden olabilen bir sorun giderildi.
```

### Finnish — слот Filipino

```text
Inayos ang isang problema na maaaring maging sanhi ng hindi pagtugon ng slider para simulan ang pagrekord.
```

### Ukrainian

```text
Виправлено помилку, через яку повзунок запуску запису міг не реагувати на свайп.
```

### Portuguese (Brazil)

```text
Corrigimos um problema que podia impedir que o controle deslizante para iniciar a gravação respondesse.
```

## Review Notes — English

Текст для поля App Review Information → Notes. Перед сохранением сверить
выбранную версию 0.8.6 и сборку 75 в App Store Connect. В тексте нет
утверждения о пройденной проверке на iOS 17.6.1.

```text
TripTrack 0.8.6 (75) fixes an issue that could prevent the recording slider from responding. The issue was reported on an iPhone 15 Pro Max running iOS 17.6.1.

The only app behavior change from 0.8.5 (74) is in SlideToStartView: when ready to record, the parent gesture uses GestureMask.subviews instead of .none. This disables the parent's blocked-state gesture while keeping the slider's child drag gesture enabled. The GPS waiting state, slide threshold, recording start handler and VoiceOver activation are unchanged.

HOW TO CHECK
1. Complete onboarding. For the GPS recording check, allow location access in the iOS dialog. No app account is required: local recording works while signed out, with Cloud Sync off. Sign in with Apple is optional for sync; no demo credentials are needed.
2. Open the central recording tab (steering-wheel icon). With a GPS fix, drag the orange slider handle from left to right. The handle should follow the finger and a completed slide should open the recording controls. A short drag should return the handle without starting.
3. If there is no GPS fix, the slider intentionally waits. Tap it to show the explanation, then choose "Start anyway" to begin while waiting for GPS. This is the existing fallback; it does not bypass denied location permission. If location permission is denied, the slider opens Settings.
4. Guest browsing is also available: open a public trip in Feed to inspect its route, replay and photos without recording a drive.

The App Store screenshot set is updated to eight iPhone images in Russian and eight in English (U.S.). These show existing features; they do not introduce additional app functionality.

Recording remains free. PRO subscriptions, tips, prices, data handling, permission requests and background modes are unchanged. No new in-app purchase products are submitted. The existing permission flow respects denial in the iOS dialogs; the only background mode remains location. TripTrack does not request microphone access or record audio.
```
