# Live Activity: Finished Screen Redesign

## Context

The current `FinishedLockScreenView` uses a centered vertical layout with a solid background — functional but visually plain compared to competitors. Yandex Navigator's finished Live Activity (shown on lock screen after trip completion) has a much more polished look: warm gradient background, horizontal icon-text-icon layout, and a glass-style CTA button. The goal is to match that visual quality while keeping TripTrack's own data and branding.

**Scope:** Only `FinishedLockScreenView` — the recording screen (`LiveLockScreenView`) stays as-is.

## Design

### Layout: Horizontal icon-text-icon (matching Yandex)

```
┌──────────────────────────────────────────────┐
│  ┌──────┐                        ┌────────┐  │
│  │pixel │  Маршрут сохранен      │AppIcon │  │
│  │ car  │  VW Polo • 3.9 км •…   │        │  │
│  └──────┘                        └────────┘  │
│                                              │
│  ┌──────────────────────────────────────────┐│
│  │        Открыть автодневник               ││
│  └──────────────────────────────────────────┘│
└──────────────────────────────────────────────┘
```

### Elements

| Element | Current | New |
|---------|---------|-----|
| **Background** | Solid `lightBg`/`darkBg` via `activityBackgroundTint` | Warm orange gradient (`linear-gradient` from amber to orange), same for light/dark mode |
| **Left icon** | Centered checkmark in orange-tinted square | Vehicle avatar (44×44) in semi-transparent white rounded rect. If `vehicleAvatar` starts with `pixel_car_` → `Image(vehicleAvatar)`, otherwise render as emoji `Text(vehicleAvatar)` |
| **Title** | "Маршрут сохранен" / "Route saved" — centered, 17pt | Same text — left-aligned, 18pt, extra-bold (.black weight) |
| **Subtitle** | "VW Polo • 3.9 км • 14:41" — centered, 13pt | Same format — left-aligned, 14pt, medium weight, muted |
| **Right icon** | None (TripTrack text label top-right) | AppIcon image (40×40) in dark rounded rect |
| **CTA button** | Orange filled, white text, chevron right | Glass effect: white 30% opacity background, muted text, no chevron |
| **"TripTrack" label** | Top-right, 9pt | Removed — AppIcon serves as branding |

### Background Gradient

The gradient should match Yandex Navigator's warm feel. In SwiftUI for widgets:
- Use `activityBackgroundTint` with a solid orange fallback
- Layer a `LinearGradient` on top for the warm effect
- Colors: from `Color(red: 1.0, green: 0.78, blue: 0.47)` to `Color(red: 1.0, green: 0.63, blue: 0.31)`
- Same gradient for both light and dark mode (the warm background is the design, not theme-dependent)

### AppIcon in Widget Extension

The AppIcon image (`AppIcon.png`) currently lives only in the main app's asset catalog. It needs to be added to the widget extension's asset catalog (`TripTrackLiveActivity/Assets.xcassets/`) as a new imageset (e.g., `app_icon.imageset`) so `FinishedLockScreenView` can reference it with `Image("app_icon")`.

### Text Colors on Gradient Background

Since the background is always a warm orange gradient (regardless of light/dark mode), text colors are fixed:
- Title: `rgba(0, 0, 0, 0.8)` — near-black for contrast on orange
- Subtitle: `rgba(0, 0, 0, 0.5)` — muted on orange
- Button text: `rgba(0, 0, 0, 0.6)` — medium on glass

### Glass Button

SwiftUI implementation:
- Background: `Color.white.opacity(0.3)` with `RoundedRectangle(cornerRadius: 14)`
- Text: 15pt semibold, `Color.black.opacity(0.6)`
- No chevron icon (unlike current design)
- Full width, centered text
- Height: ~44pt (padding 12pt vertical)

### Dynamic Island (Finished State)

The Dynamic Island compact/expanded views for the finished state should also be updated for consistency:
- **Compact leading:** AppIcon small (instead of checkmark)
- **Compact trailing:** distance + unit (unchanged)
- **Expanded:** same horizontal layout as lock screen if space allows, or simplified
- **Minimal:** AppIcon tiny (instead of checkmark.circle.fill)

## Files to Modify

1. **`TripTrackLiveActivity/TripTrackLiveActivity.swift`** — redesign `FinishedLockScreenView`, update Dynamic Island finished state
2. **`TripTrackLiveActivity/Assets.xcassets/`** — add `app_icon.imageset` with the AppIcon PNG

## Verification

1. Build the widget extension: `xcodebuild build -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'`
2. Run on simulator, complete a trip, verify the finished Live Activity shows the new design
3. Check both light and dark system appearance — gradient should look the same
4. Verify Dynamic Island finished state shows AppIcon
5. Verify the "Open trip diary" deep link still works when tapping the Live Activity
6. Verify the Live Activity auto-dismisses after 5 minutes (existing behavior, should not break)
