# Slide to Start: защита от случайного запуска записи

**Date:** 2026-04-02
**Status:** Draft

## Context

Apple reject'нул приложение из-за long-press кнопки старта (0.4 сек) — ревьюер тапнул, ничего не произошло, получили reject. Убрали long-press, вернули обычный tap — одобрили. Но обычный tap легко нажать случайно в кармане.

**Решение:** slide to start — горизонтальный слайдер, стандартный паттерн (как slide to unlock). Визуально очевиден, невозможно случайно активировать, Apple точно не зареджектит.

## Что делаем

Заменяем кнопку "Start Trip" в `IdleHUDView` на `SlideToStartView`.

## Компонент: `SlideToStartView`

**Новый файл:** `TripTrack/Views/Tracking/SlideToStartView.swift`

**Визуал:**
- Горизонтальный трек, размер текущей кнопки (~full width по padding родителя, 56pt высота)
- Фон: glass material с тёмным overlay (как текущая кнопка)
- Rounded corners 16pt (как текущая кнопка)
- Ползунок слева: круг 48pt с иконкой `play.fill`, оранжевый accent (`AppTheme.accent`)
- Текст по центру трека: "Slide to start" / "Сдвиньте для старта", полупрозрачный (`secondary`)
- По мере drag: текст fade out (opacity = 1 - progress)

**Взаимодействие:**
- `DragGesture` на ползунке
- Ползунок следует за пальцем по горизонтали (clamped 0...maxOffset)
- Threshold: 85% ширины = подтверждение
- Дотянул до threshold: heavy haptic → вызов `onStartTrip()`
- Отпустил раньше: spring animation назад к 0

**Интерфейс:**
```swift
struct SlideToStartView: View {
    let onStartTrip: () -> Void
}
```

## Модификации

### `IdleHUDView`
- Заменить `Button { onStartTrip() }` (строки 52-73) на `SlideToStartView(onStartTrip: onStartTrip)`
- Убрать `UIImpactFeedbackGenerator` из старой кнопки — haptic теперь внутри SlideToStartView

### `AppStrings`
- Добавить `slideToStart`: EN = "Slide to start", RU = "Сдвиньте для старта"

### Не трогаем
- `CustomTabBar` — там кнопка переключает вкладку, не стартует запись
- `TrackingView` — stop кнопка остаётся tap
- `MapViewModel` — логика `toggleRecording()` без изменений

## Ключевые файлы
- `TripTrack/Views/Tracking/IdleHUDView.swift` — замена кнопки
- `TripTrack/Localization/AppStrings.swift` — новая строка
- `TripTrack/Views/Theme/AppTheme.swift` — цвета (используем существующие)

## Тестирование
- Ручное: slide до конца → запись стартует
- Ручное: slide до середины, отпустить → пружинит назад, запись НЕ стартует
- Ручное: tap на слайдер → ничего не происходит
- Ручное: телефон в кармане → случайная активация невозможна
