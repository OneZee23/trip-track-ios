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
- **Services** — singletons with business logic: `TripManager` (CRUD via TripRepository, geocoding, batch saves), `LocationManager` (dual-mode GPS/simulated), `GamificationManager` (badges, XP, levels), `SmoothTrackManager` (Kalman filter), `SyncQueue` (pending sync operations)
- **Persistence** — `PersistenceController.shared` (CoreData), `TripRepository` protocol (CRUD abstraction), photos in Documents directory
- **Views** — SwiftUI, organized by feature in subdirectories under `Views/`

**Data flow**: Views → ViewModels (@Published) → Services → TripRepository → CoreData

**Location tracking** uses Provider pattern: `LocationProvider` protocol → `RealGPSProvider` (CoreLocation) + `SimulatedLocationProvider` (dev joystick). LocationManager switches between them.

## CoreData Schema (8 entities, versioned)

`TripEntity` is central, with cascade relationships to `TrackPointEntity` and `TripPhotoEntity`. Also: `VehicleEntity`, `UserSettingsEntity`, `VisitedGeohashEntity`, `GeocodeCacheEntity`, `RoadEntity`. Schema at `TripTrack/Persistence/TripTrack.xcdatamodeld/` (v1 = baseline, v2 = current with sync fields).

**Sync-readiness fields (v2):** `userId`, `serverCreatedAt`, `conflictVersion` on TripEntity; `remoteURL`, `uploadStatus` on TripPhotoEntity; `userId` on VehicleEntity. All models (`Trip`, `TrackPoint`, `TripPhoto`, `Vehicle`) are `Codable` for JSON API serialization.

## Key Patterns

- **Batch saves**: location points batched (10 points or 15s interval) via TripManager
- **Async CoreData**: `PersistenceController.saveAsync()` for non-blocking writes from location callbacks
- **Binary polylines**: `Trip.encodePolyline/decodePolyline` for compact route storage
- **Geohashing**: `GeohashEncoder` + `VisitedGeohashEntity` for territory tracking
- **Junk trip filtering**: auto-delete trips <500m AND <2min
- **Repository pattern**: `TripRepository` protocol abstracts CoreData CRUD; `TripManager` delegates to `CoreDataTripRepository`
- **Sync queue**: `SyncQueue` (@MainActor) with deduplication, priority ordering, exponential backoff retry, `SyncTransport` protocol for future API client
- **Soft delete**: `SyncStatus.pendingDelete` hides trips from UI; physical delete after server confirms
- **User identity**: `SettingsManager.localUserId` (UUID) stamped on all entities, prepared for Sign in with Apple
- **UI modifiers**: `.surfaceCard()`, `.glassBackground()`, `.glassPill()` for consistent card styling

## Localization & Theming

- **Languages**: thirteen — `en, ru, de, es, fr, it, pl, id, tr, fil, uk, kk, pt` — via `LanguageManager.Language` + the `AppStrings` enum (all UI strings)
- **Themes**: dark/light/system via `ThemeManager`, colors in `AppTheme`
- Add new strings to `AppStrings.swift`, never hardcode UI text

### Adding a string

Write it as a function that takes the language and calls `tr`:

```swift
static func myThing(_ lang: LanguageManager.Language) -> String {
    tr(lang, "myThing", ru: "Моя штука", en: "My thing")
}
```

Russian and English live inline, next to the doc comment that explains the
copy. The other eleven come from `Localization/Translations/Translations+XX.swift`,
keyed by the same function name. A key with no row falls back to **English**, so
an untranslated string shows English rather than `myThing` — which is why
`LocalizationTests` exists: nothing else notices a key that drifted.

Rules that are easy to get wrong:
- **Never** `lang == .ru ? "…" : "…"` inline in a view. That is invisible to the
  tables and stays English on a German phone; 0.6.1 spent a day pulling 205 of
  them back out.
- Counted nouns go through `AppStrings.plural` / `nounTrips` / `nounDays` … —
  CLDR rules, not `if .ru`. Russian and Ukrainian share the three-form rule;
  Polish has its own and parts with them at 21; French, Filipino and Portuguese
  count 0 as singular; Indonesian has no plural at all.
- **Never** call `uppercased()` / `lowercased()` on copy without a language.
  Turkish writes `İ` for capital «i» and `ı` for lowercase «I», so the bare
  call corrupts every section header. Use `String.uppercased(_ lang:)`, or
  SwiftUI's `.textCase(.uppercase)` — the environment locale is set from the
  chosen language in `TripTrackApp`.
- Dates and numbers take their locale from `lang.locale`, never from a literal
  `"ru_RU"`. For formatters use `LocalizedDateFormatter.patterns/templates`,
  which build one per language.
- Permission prompts live in `TripTrack/Resources/<lang>.lproj/InfoPlist.strings`
  and follow the DEVICE language, not the in-app one. A new language needs a new
  `.lproj` **and** an entry in `knownRegions` in `project.yml`.
- The Live Activity and the widget cannot see `AppStrings` (it reaches into
  half the app). Their words are in `TripTrackShared/LiveActivityStrings.swift`,
  keyed by the raw language code.

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

### Dialogs — always ours, never the system's

**No system modal ever ships in this app.** No `.alert`, no `.confirmationDialog`,
no `.actionSheet`, no `Menu` used as an action list. They drop UIKit chrome —
system greys, system type, a plate with its own corner radius — into the middle
of a screen built from our warm cards, and they read as borrowed from another
app. Two of them have already shipped broken: a `confirmationDialog` inside a
custom navigator adapted into a floating plate that lost its own Cancel button,
and a `Menu` on a circular nav control left a rounded-square plate behind on
dismissal (see `NavCircleIcon`'s doc comment).

Use the house components instead:
- **Confirmations** — `AppConfirmDialog` / the `.appConfirm(...)` modifier: a
  scrim that swallows taps, the question in our type, and the answers stacked
  with the safe one nearest the thumb.
- **Action lists** («…» menus) — `ActionPopoverList`.
- **Pickers** — `SettingsOptionPicker` in a `.contentSizedSheet`.
- **Transient feedback** — `ToastView`, not an alert.

Rules for any confirmation you build or touch:
- The scrim must be `.accessibilityHidden(true)` and the card a modal, or
  VoiceOver's rotor walks straight past it onto the page behind.
- `AppConfirmDialog` dismisses ITSELF before running each handler, so a handler
  must NOT clear `isPresented` / the item, and must not read its subject back
  out of state after dismissal — take it as the closure argument instead.
  (A hand-rolled overlay does not do this for you: forgetting to dismiss is what
  made «Закрепить» look like a dead button. That is the reason to use the
  component rather than to copy it.)
- A dialog on a TAB-ROOT screen must also `.hideAppTabBar()` while it is up, or
  the custom tab bar paints over the scrim and stays tappable — the user can
  switch tabs with a destructive confirmation pending.
- Attach the dialog at the SCREEN root, never inside a `ScrollView`. An overlay
  is sized to the view it modifies, so a dialog hung on a section gets a scrim
  the size of that section, scrolls with the content, and can be clipped
  off-screen entirely.
- The destructive action is `AppTheme.red`, the ordinary one `AppTheme.accent`,
  and Cancel is always present and always last.
- All copy through `AppStrings`, both languages.

### What NOT to Do
- Don't use `AnyView` — it kills SwiftUI diffing performance
- Don't use `@ObservedObject` for objects the view creates — use `@StateObject`
- Don't force-unwrap optionals except for IBOutlets (which we don't use) and test assertions
- Don't use `DispatchQueue.main.async` in new code — use `@MainActor` or `MainActor.run {}`
- Don't add `import UIKit` in SwiftUI views unless absolutely necessary for a specific API
- Don't nest NavigationStack inside NavigationStack
