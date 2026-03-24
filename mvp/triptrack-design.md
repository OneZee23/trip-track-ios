# TripTrack -- Design System v1.0

> **Версия:** 1.0
> **К PRD:** v1.0
> **Статус:** MVP -- в разработке
> **Обновлено:** Март 2026

---

## 1. Визуальный язык

### Философия

Минимализм + premium native iOS. Приложение должно ощущаться как нативная часть iOS, а не как кросс-платформенный продукт. Каждый пиксель имеет цель. Информация важнее декораций.

### Принципы

1. **iOS 26+ native** -- Liquid Glass design: frosted glass surfaces, translucency, depth layers
2. **Clean, minimal** -- SF Pro как основной шрифт, чистые линии, много воздуха
3. **Pixel-art accent** -- ТОЛЬКО для логотипа "ROAD TRIP TRACKER", бейджа уровня водителя "LVL N" и pixel car на idle screen. Шрифт Press Start 2P используется исключительно для этих элементов
4. **Dark Mode First** -- оптимизация для ночного вождения, dark theme как primary
5. **Large & Readable** -- крупная типографика, monospacedDigit для цифр, high contrast для солнечного света

### Референсы

- **Apple Maps** -- чистота интерфейса, нативные карты
- **Strava** -- UX активного трекинга
- **Duolingo** -- геймификация, celebration-анимации
- **Flighty** -- минимализм + информативность
- **Things** -- polish и внимание к деталям

---

## 2. Цветовая палитра

### Dark Theme (primary)

| Token | Значение | Применение |
|-------|----------|------------|
| Background | `#000000` | Фон экранов |
| Card Surface | `#1C1C1E` | Карточки, bottom sheets |
| Card Alt / Input BG | `#2C2C2E` | Альтернативный фон, поля ввода |
| Border | `rgba(255,255,255,0.08)` | Границы карточек |
| Text Primary | `#FFFFFF` | Заголовки, основной текст |
| Text Secondary | `rgba(255,255,255,0.6)` | Подписи, вспомогательный текст |
| Text Tertiary | `rgba(255,255,255,0.3)` | Hint-тексты, disabled |
| Accent (Strava Orange) | `#FC4C02` | Основной акцент, кнопки, polyline |
| Accent BG | `rgba(252,76,2,0.1)` | Фон акцентных элементов |
| Success Green | `#34C759` | Старт, расстояние, positive |
| Danger Red | `#FF3B30` | Stop, delete, negative |
| Info Blue | `#007AFF` | Высота, informational |
| Teal | System Teal | Вспомогательный |
| Purple | System Purple | Вспомогательный |
| Yellow | System Yellow | Топливо, warnings |
| Glass Surface | `rgba(44,44,46,0.72)` + `blur(40px)` + `saturate(180%)` | Frosted glass overlays |
| Glass Border | `rgba(255,255,255,0.18)` | Границы glass-элементов |
| Glass Shadow | `0 8px 32px rgba(0,0,0,0.4)` | Тень glass-элементов |

### Light Theme

| Token | Значение | Применение |
|-------|----------|------------|
| Background | `#F2F2F7` | Фон экранов |
| Card Surface | `#FFFFFF` | Карточки |
| Card Alt | `#F5F5F7` | Альтернативный фон |
| Border | `rgba(0,0,0,0.06)` | Границы карточек |
| Text Primary | `#000000` | Основной текст |
| Text Secondary | `rgba(0,0,0,0.55)` | Вспомогательный текст |
| Text Tertiary | `rgba(0,0,0,0.25)` | Hint-тексты |
| Accent | `#FC4C02` | Тот же orange |
| Glass Surface | `rgba(255,255,255,0.72)` | Frosted glass |
| Glass Border | `rgba(255,255,255,0.8)` | Границы glass |

---

## 3. Типографика

| Элемент | Шрифт | Размер | Вес |
|---------|-------|--------|-----|
| Pixel logo "ROAD TRIP" | Press Start 2P | 10px | -- |
| Pixel level badge "LVL N" | Press Start 2P | 9px | -- |
| Заголовок экрана | System (SF Pro) | 20px | 800 (Heavy) |
| Заголовок карточки / название поездки | System | 18px | 800 |
| Stat value (large) | System | 20-22px | 800 |
| Спидометр (запись) | System monospacedDigit | 44px | 900 (Black) |
| Stat label | System | 11px | 400 (Regular) |
| Body text | System | 14px | 400 |
| Chip / button | System | 13px | 600 (Semibold) |
| Calendar day number | System | 12px | 600 |
| Micro label | System | 10px | 600 |

### Правила

- Все числовые значения используют `monospacedDigit()` для стабильной ширины
- Заголовок логотипа: "ROAD TRIP" (10px, orange, Press Start 2P) + "tracker" (11px, tertiary, uppercase, letter-spacing 2px, System)
- Dynamic Type respected для accessibility

---

## 4. Spacing и Radii

| Параметр | Значение |
|----------|----------|
| Screen horizontal padding | 16px |
| Card padding | 16px |
| Gap between cards | 8-10px |
| Card radius | 16px |
| Button radius (large) | 14px |
| Chip/pill radius | 20px |
| Input radius | 12px |
| Tab bar radius | 28px |
| Tab bar bottom offset | 16px |
| Content bottom padding | 100px (clear tab bar) |
| Safe area top | 56px |

---

## 5. Компоненты

### 5.1. Card Modifiers

Три переиспользуемых SwiftUI ViewModifier:

**`.surfaceCard()`**
- Background: card surface color
- Corner radius: 16px
- Subtle shadow
- Применение: trip cards, stats cards, profile cards, settings sections

**`.glassBackground()`**
- Background: glass surface color + blur(40px) + saturate(180%)
- Border: glass border color
- Shadow: glass shadow
- Corner radius: 16px
- Применение: tracking HUD, map overlays, floating panels

**`.glassPill()`**
- Компактная версия glassBackground
- Меньший padding, pill shape
- Применение: GPS indicator, recording banner, HUD chips

### 5.2. Tab Bar (Liquid Glass, floating)

- Фиксирован 16px от нижнего края
- Centered, max-width 360px
- Frosted glass background + specular shine gradient overlay
- 3 таба:
  1. **Feed** (flag icon) -- default on launch
  2. **Record** (car.fill) -- CENTER tab, elevated orange circle (48px), raised -6px. При записи -- red pulsing dot. На tracking tab -- red STOP button
  3. **Regions** (map icon)

### 5.3. Trip Card (FeedTripCardView)

- Top row: vehicle emoji (36px circle) + vehicle name (14px/700) + date + region (12px, tertiary) + photo count badge
- Title: 18px/800, full width, editable
- Route preview: CardMapPreview (80px tall, simplified polyline, orange route)
- Stats grid (3 columns): Distance (km), Duration, Avg Speed (km/h)
- Badge medals row: до 4 small badge icons (22px) + "+N" overflow
- Tap -> TripDetailView
- Swipe to delete

### 5.4. Contribution Calendar

**Collapsed state (default):**
- Текущая неделя -- одна строка из 7 day cells
- Day labels: Пн Вт Ср Чт Пт Сб Вс
- Стрелка expand внизу

**Expanded state:**
- Полная месячная сетка (7 x 4-6 строк)
- Название месяца + год вверху
- Swipe left/right для навигации между месяцами

**Day cell (~40px square):**
- Номер дня по центру
- Background color = intensity gradient по километражу:
  - Нет поездок: gray (cardAlt)
  - Мало km (bottom 33%): accent 15% opacity
  - Средне (middle 33%): accent 40% opacity
  - Много (top 33%): accent 80-100% opacity
- Intensity relative к максимуму пользователя
- Today: subtle border ring
- Selected day: accent color border (2px)

### 5.5. Badge Cell

- 56x56 colored circle с SF Symbol icon
- Title below (11px)
- **Unlocked:** full color icon
- **Locked visible:** grayed icon + lock overlay
- **Hidden locked:** "?" icon + lock, title = "???"
- **Repeatable counter:** "x{N}" pill (badge color), bottom-right на unlocked

### 5.6. Badge Celebration Overlay

- Fullscreen dark backdrop (0.8 opacity)
- Confetti particles (Canvas + TimelineView, ~40 particles, 3 sec)
- Large badge icon (130px) с glow pulse animation
- "Achievement Unlocked!" subtitle (accent, uppercase, tracked)
- Badge name (28pt bold, white)
- Badge description
- "Continue" button (badge color)
- Sequential presentation для нескольких бейджей (page dots)
- Success haptic

### 5.7. Tracking HUD (Compact)

- Glass background (`.glassBackground()`)
- Large speed display (44pt, monospacedDigit, animated contentTransition)
- "km/h" label below
- 3 metrics row с vertical dividers:
  - Altitude (mountain icon, blue) -- meters
  - Duration (timer icon, orange) -- MM:SS or H:MM:SS
  - Distance (location icon, green) -- km
- Pause/Resume button

### 5.8. Idle HUD

- Pulsing concentric circles с pixel car icon (animated rings)
- "Ready to ride" / "Tap to start" text
- Cached total km + trip count
- Large orange "Start trip" button

### 5.9. Driver Level Card

- Rank icon (52px colored circle) -- 7 рангов с unique icons и colors
- "LVL N" в Press Start 2P pixel font
- XP progress bar (current/needed, или "MAX" на 30)
- Expandable info: правила XP

### 5.10. Filter Bottom Sheet

- Drag handle at top
- Title "Filters" (18px/800)
- Date range picker
- Region chips
- Vehicle filter
- Distance inputs: "Km from" / "Km to"
- Sort options
- Bottom buttons: "Reset" + "Apply"

---

## 6. Экраны

### 6.1. Feed (Main Screen)
Основной экран приложения. Лента поездок с contribution calendar, quick stats, фильтрами. Группировка по месяцам. Sticky header с аватаром, логотипом, settings.

### 6.2. Record (Trip Recording)
Полноэкранная карта с orange polyline. Два состояния: idle (pulsing car + "Start trip") и recording (live HUD с скоростью, высотой, временем, расстоянием). Пользователь НЕ заблокирован на этом экране -- запись продолжается на всех табах.

### 6.3. Regions (Fog of War)
Карта исследованных территорий. Progress card с тайлами, городами, регионами. Fog overlay на Apple Maps. Список городов с progress bars.

### 6.4. Profile (Sheet)
Уровень водителя, XP bar, автомобиль, аватар. Навигация: Garage, Badges, Stats.

### 6.5. Trip Detail (Push navigation)
Интерактивная карта маршрута (45% экрана, speed color-coding). Stats grid, бейджи, фотографии, заметки. Editable title.

### 6.6. Trip Completion Summary (Sheet)
Маршрут на карте, stats grid, XP earned, бейджи, streak info, vehicle progress. Action buttons: Photo, Note, Done.

### 6.7. Badges (Sheet)
Grid бейджей (3 колонки), категории с headers. Counter header "N/Total". Hidden info section.

### 6.8. Badge Celebration (Fullscreen Overlay)
Конфетти, glow, badge showcase. Sequential для нескольких бейджей.

### 6.9. Garage (Sheet)
Список авто с emoji, одометром, уровнем. Add/delete/select.

### 6.10. Stats (Sheet -- v1.1)
Hero section, weekly chart, calendar heatmap, records, fuel calculator.

### 6.11. Settings (Sheet)
Theme picker, language picker, version/build.

### 6.12. Onboarding (First launch)
3 страницы: welcome, recording, location permission + CTA.

---

## 7. Иконография и ассеты

### SF Symbols (используемые)

| Контекст | Symbol |
|----------|--------|
| Feed tab | flag |
| Record tab | car.fill |
| Regions tab | map |
| Settings | gearshape |
| Profile | person.circle |
| Start trip | play.fill |
| Stop trip | stop.fill |
| Pause | pause.fill |
| Resume | play.fill |
| GPS accuracy | antenna.radiowaves.left.and.right |
| Location button | location.fill |
| Altitude | mountain.2.fill |
| Duration | timer |
| Distance | location.fill |
| Speed | speedometer |
| Photo | camera.fill |
| Notes | pencil |
| Delete | trash |
| Add | plus |
| Filter | line.3.horizontal.decrease |
| Close | xmark |
| Back | chevron.left |
| Expand | chevron.down |
| Collapse | chevron.up |
| Badge locked | lock.fill |
| Badge hidden | questionmark |
| Streak | flame.fill |
| XP | sparkles |

### Pixel-art ассеты

- **Logo wordmark:** "ROAD TRIP" в Press Start 2P, 10px, orange (#FC4C02)
- **Subtitle:** "tracker" в System, 11px, tertiary, uppercase, letter-spacing 2px
- **Level badge:** "LVL {N}" в Press Start 2P, 9px
- **Idle car icon:** pixel car для idle screen (анимированные pulsing rings вокруг)

### App Icon

Минималистичная иконка с reference на road/driving тематику. Orange accent.

---

## 8. Motion и Interaction

| Элемент | Анимация |
|---------|----------|
| Card entrance | fadeUp: opacity 0->1, translateY 10->0, 350ms ease, staggered 50ms |
| Bottom sheets | slideUp from bottom, spring 300ms |
| Calendar expand/collapse | Height animation, spring 300ms |
| Calendar month swipe | Horizontal slide, 250ms ease |
| Tab switch | Cross-fade content |
| Recording dot | Gentle pulse (scale 1->1.1->1, 2s loop) |
| Idle HUD | Pulsing concentric rings around pixel car |
| Filter chip appear/remove | Scale + fade, 200ms |
| Region select | scale(1.06) + ring glow, 250ms ease |
| Glass shine | Static gradient overlay (no animation) |
| Badge celebration | Confetti particles (Canvas, 3s) + icon scale spring + glow pulse |
| Badge unlock overlay | Spring response 0.6, dampingFraction 0.7 |
| Speed display | monospacedDigit contentTransition for smooth digit changes |

### Haptic Feedback

| Событие | Тип |
|---------|-----|
| Start/stop/pause recording | Medium impact |
| Tab switch | Light impact |
| Filter apply | Light impact |
| Day cell tap (calendar) | Light impact |
| Region tap on map | Light impact |
| Badge unlock | Success notification |
| Badge tap in grid | Light impact |
| Trip completion | Success notification |
| Junk trip auto-delete | Warning notification |

---

> Design System актуален для MVP v1.0. Обновляется по мере развития продукта.
