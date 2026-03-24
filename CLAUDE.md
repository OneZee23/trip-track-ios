# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# First-time setup
cp Local.xcconfig.example Local.xcconfig  # set PRODUCT_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM
brew install xcodegen
xcodegen generate
open TripTrack.xcodeproj
# Xcode → select device → Cmd+R

# Regenerate after adding/removing files
xcodegen generate

# Build from CLI
xcodebuild build -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme TripTrack -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16'
```

Build config lives in `project.yml` (xcodegen). Local signing in `Local.xcconfig` (gitignored).

## Architecture

**MVVM + Service Layer**, fully native (no external dependencies).

- **Models** — data structures: `Trip`, `TrackPoint`, `Vehicle`, `Badge`, `TripPhoto`
- **ViewModels** — `@ObservableObject` with `@Published`: `MapViewModel` (recording, map state), `FeedViewModel` (trip list, filtering, pagination)
- **Services** — singletons with business logic: `TripManager` (CRUD, geocoding, batch saves), `LocationManager` (dual-mode GPS/simulated), `GamificationManager` (badges, XP, levels), `SmoothTrackManager` (Kalman filter)
- **Persistence** — `PersistenceController.shared` (CoreData), photos in Documents directory
- **Views** — SwiftUI, organized by feature in subdirectories under `Views/`

**Data flow**: Views → ViewModels (@Published) → Services → CoreData

**Location tracking** uses Provider pattern: `LocationProvider` protocol → `RealGPSProvider` (CoreLocation) + `SimulatedLocationProvider` (dev joystick). LocationManager switches between them.

## CoreData Schema (8 entities)

`TripEntity` is central, with cascade relationships to `TrackPointEntity` and `TripPhotoEntity`. Also: `VehicleEntity`, `UserSettingsEntity`, `VisitedGeohashEntity`, `RoadEntity`. Schema at `TripTrack/Persistence/TripTrack.xcdatamodeld/`.

## Key Patterns

- **Batch saves**: location points batched (10 points or 15s interval) via TripManager
- **Async CoreData**: `PersistenceController.saveAsync()` for non-blocking writes from location callbacks
- **Binary polylines**: `Trip.encodePolyline/decodePolyline` for compact route storage
- **Geohashing**: `GeohashEncoder` + `VisitedGeohashEntity` for territory tracking
- **Junk trip filtering**: auto-delete trips <500m AND <2min
- **UI modifiers**: `.surfaceCard()`, `.glassBackground()`, `.glassPill()` for consistent card styling

## Localization & Theming

- **Languages**: RU/EN via `LanguageManager` + `AppStrings` enum (all UI strings)
- **Themes**: dark/light/system via `ThemeManager`, colors in `AppTheme`
- Add new strings to `AppStrings.swift`, never hardcode UI text

## Tech Constraints

- iOS 17+, Swift 5.9, iPhone only
- SwiftUI only (no UIKit views except MapKit representable)
- MapKit (no third-party maps)
- No external dependencies — 100% native frameworks
- Background location enabled via Info.plist UIBackgroundModes

## Swift & SwiftUI Rules

### State Management
- Use `@StateObject` for owned objects created in the view, `@ObservedObject` for passed-in objects, `@EnvironmentObject` for shared app-wide state
- Never create `@StateObject` in a child view for an object owned by a parent — pass it as `@ObservedObject`
- Keep `@State` for local view-only state (toggles, sheet flags, text fields)
- All UI-mutating code must run on `@MainActor`. Services called from ViewModels should dispatch to main when updating `@Published` properties

### Views
- Extract subviews into computed properties or separate structs when body exceeds ~40 lines
- Use `ViewBuilder` functions for conditional UI blocks, not complex ternaries in body
- Prefer `.task {}` over `.onAppear` for async work — it auto-cancels
- Always add `.animation(.default, value:)` with explicit value, never `.animation(.default)` (deprecated)
- Use `LazyVStack` / `LazyHStack` inside `ScrollView` for lists with >20 items

### Performance
- Mark ViewModels as `@MainActor` class
- Use `nonisolated` for heavy computation methods that don't touch UI
- Prefer `task.detached` for CPU-heavy work (encoding, filtering large arrays)
- For CoreData fetches in background: use `viewContext.perform {}` or `newBackgroundContext()`
- Avoid re-creating objects in `body` — pull constants and formatters to static/lazy properties

### Swift Style
- Prefer `guard let` for early exits over nested `if let`
- Use `[weak self]` in closures that capture self in non-@MainActor contexts
- Prefer `async/await` over Combine chains for new code. Keep existing Combine as-is
- Use `Result` type for error handling in service methods, not throwing + catch at every call site
- Enums with associated values over multiple optional properties when states are mutually exclusive

### File Organization
- After adding/removing .swift files, run `xcodegen generate` to update the Xcode project
- One type per file. Extensions in the same file are fine, separate extension files only for protocol conformances
- New views go in the appropriate `Views/` subdirectory by feature
- New services are singletons with `static let shared`

### What NOT to Do
- Don't use `AnyView` — it kills SwiftUI diffing performance
- Don't use `@ObservedObject` for objects the view creates — use `@StateObject`
- Don't force-unwrap optionals except for IBOutlets (which we don't use) and test assertions
- Don't use `DispatchQueue.main.async` in new code — use `@MainActor` or `MainActor.run {}`
- Don't add `import UIKit` in SwiftUI views unless absolutely necessary for a specific API
- Don't nest NavigationStack inside NavigationStack
