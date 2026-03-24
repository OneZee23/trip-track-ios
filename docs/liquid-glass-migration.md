# Миграция на Liquid Glass (iOS 26)

## Статус: запланировано, не начато

## Что это
Apple представила Liquid Glass на WWDC 2025 — новый материал для интерфейсов, заменяющий `.ultraThinMaterial`. Динамический стеклянный эффект с размытием, отражениями и реакцией на тач.

## Требования
- Xcode 26+
- Минимальный таргет: iOS 26
- SwiftUI — `.glassEffect()`, `GlassEffectContainer`, `.buttonStyle(.glass)`

## Что нужно мигрировать

### Кастомные компоненты
- **CustomTabBar** — заменить `.ultraThinMaterial` фон на `GlassEffectContainer` + `.glassEffect()`
- **CompactTrackingHUD** — `.glassBackground()` → `.glassEffect(in: .rect(cornerRadius: 20))`
- **IdleHUDView** — аналогично
- **Кнопки зума на карте** — `.glassEffect()` вместо кастомного фона
- **RecordingBanner** — glass effect
- **GPSIndicatorView** — glass pill

### Карточки
- **FeedTripCardView** — `.surfaceCard()` → `.glassEffect(in: .rect(cornerRadius: 16))`
- **DetailStatCard** — аналогично
- **StatsView stat cards** — аналогично
- **RegionsView progress card** — аналогично

### Кнопки
- Все `.glassPill()` → `.glassEffect()` или `.buttonStyle(.glass)`
- Filter bar pills
- Period picker в StatsView

### Интерактивность
- `.glassEffect(.regular.interactive())` на кнопках для тактильной реакции
- `GlassEffectContainer` для группировки связанных элементов (HUD кнопки, filter pills)
- `.glassEffectID()` + `GlassEffectTransition` для морфинга при переключении состояний (idle → recording)

## Порядок миграции
1. Поднять минимальный таргет до iOS 26
2. Заменить `GlassBackground` ViewModifier на `.glassEffect()`
3. Заменить `SurfaceCard` ViewModifier на `.glassEffect(in: .rect(cornerRadius:))`
4. Заменить `GlassPill` ViewModifier на `.glassEffect()` с capsule shape
5. Обернуть группы элементов в `GlassEffectContainer`
6. Добавить `.interactive()` на интерактивные элементы
7. Добавить морфинг-анимации через `glassEffectID`
8. Удалить старые кастомные модификаторы из AppTheme.swift

## Документация
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- Landmarks sample app: Building an app with Liquid Glass
