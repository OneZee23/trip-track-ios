# Performance Optimization — Surgical Fixes

## Problem

Input fields (TextFields) lag/freeze across the app. Root cause: all 3 tabs stay alive via opacity swap in ContentView, so MapViewModel's frequent @Published updates (location, timers, overlays) trigger full UI tree redraws including inactive tabs. Secondary issues compound the problem.

## Fixes (ordered by impact)

### Fix 1: ContentView — lazy tab rendering

**File:** `ContentView.swift`

Replace opacity swap with conditional rendering. Only the active tab's view tree exists at any time.

```swift
// Before
FeedView(...).opacity(selectedTab == 0 ? 1 : 0).allowsHitTesting(selectedTab == 0)
TrackingView().opacity(selectedTab == 1 ? 1 : 0).allowsHitTesting(selectedTab == 1)
RegionsView().opacity(selectedTab == 2 ? 1 : 0).allowsHitTesting(selectedTab == 2)

// After
switch selectedTab {
case 0: FeedView(...)
case 1: TrackingView()
case 2: RegionsView()
default: EmptyView()
}
```

MapViewModel stays as `@StateObject` in ContentView — it survives tab switches. Recording state, location subscriptions, timers all persist. Only the view layer is destroyed/recreated.

**Impact:** Eliminates all cross-tab @Published cascading. TextField lag gone.

**Trade-off:** MKMapView recreates on tab switch (~0.1s). Acceptable because MapViewRepresentable reads current overlays from MapViewModel on creation.

### Fix 2: Equatable conformance for Trip and TripSection

**Files:** `Trip.swift`, `FeedViewModel.swift`

Add `Equatable` to `Trip` and `TripSection`. This lets SwiftUI skip re-rendering unchanged items in ForEach. Manual conformance excludes `trackPoints` (large array that kills diffing), but includes `previewPolyline` since Fix 6 backfills it async.

```swift
extension Trip: Equatable {
    static func == (lhs: Trip, rhs: Trip) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.distance == rhs.distance &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.region == rhs.region &&
        lhs.photos.count == rhs.photos.count &&
        lhs.previewPolyline == rhs.previewPolyline
    }
}

extension TripSection: Equatable {
    static func == (lhs: TripSection, rhs: TripSection) -> Bool {
        lhs.id == rhs.id && lhs.trips == rhs.trips
    }
}
```

**Impact:** Feed scroll performance — SwiftUI diffs only changed trips instead of redrawing all.

### Fix 3: FeedView — detailVM as lazy property

**File:** `FeedView.swift`

`detailVM` is a computed property that creates a new `TripsViewModel` on every body evaluation.

```swift
// Before
private var detailVM: TripsViewModel {
    TripsViewModel(tripManager: feedVM.tripManager)
}

// After — inline at the single call site in .navigationDestination
.navigationDestination(isPresented: ...) {
    if let id = selectedTripId {
        TripDetailView(tripId: id, viewModel: TripsViewModel(tripManager: feedVM.tripManager))
    }
}
```

The `navigationDestination` content is only evaluated when `isPresented` is true, so the VM is created only when navigating. Remove the `detailVM` computed property entirely.

**Impact:** Eliminates unnecessary allocations per render.

### Fix 4: FeedView — remove visibleCards loop from calendar bindings

**File:** `FeedView.swift`

Calendar date setters iterate all trips to populate `visibleCards`. This is unnecessary — pagination already handles visibility via `onAppear`.

```swift
// Before
set: { newDate in
    feedVM.setDateRange(from: newDate, to: feedVM.filters.dateTo)
    for trip in feedVM.trips { visibleCards.insert(trip.id) }  // ← remove
}

// After
set: { newDate in
    feedVM.setDateRange(from: newDate, to: feedVM.filters.dateTo)
}
```

Same for `dateTo` setter and `.refreshable`.

**Impact:** Eliminates O(n) work on every filter change.

### Fix 5: TrackingView — cache safe area values

**File:** `TrackingView.swift`

`safeAreaTop` and `tabBarHeight` are computed properties that traverse `UIApplication.shared.connectedScenes` on every body evaluation.

```swift
// Before — computed property, runs every render
private var safeAreaTop: CGFloat {
    UIApplication.shared.connectedScenes...
}

// After — cached once
@State private var safeAreaTop: CGFloat = 59
@State private var tabBarHeight: CGFloat = 88

// in .onAppear:
if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
   let window = scene.windows.first {
    safeAreaTop = window.safeAreaInsets.top
    tabBarHeight = 54 + window.safeAreaInsets.bottom
}
```

**Impact:** Eliminates UIKit scene traversal per frame during recording.

### Fix 6: MapViewModel init — async backfill

**File:** `MapViewModel.swift`

`backfillPreviewPolylines()` runs synchronously in init, blocking first render.

```swift
// Before
init() {
    ...
    tripManager.backfillPreviewPolylines()  // blocks
    refreshTripStats()
    Task { ... }
}

// After
init() {
    ...
    refreshTripStats()
    Task { @MainActor [tripManager, gamificationManager, territoryManager] in
        tripManager.backfillPreviewPolylines()  // moved here
        tripManager.migrateRegionsIfNeeded()
        ...
    }
}
```

**Impact:** Faster app launch. Feed cards show preview polylines after async backfill completes.

### Fix 7: SmoothTrackManager — skip updateSmoothPoints when not animating

**File:** `SmoothTrackManager.swift`

`animationTick()` calls `updateSmoothPoints()` at 30-60 FPS. When animation is complete (progress >= 1.0), the tick still fires but does no-op work. The bigger issue: `updateSmoothPoints` publishes `smoothDisplayPoints` and `headSegmentPoints` on every tick, even when values haven't changed.

```swift
// In animationTick — only update + publish when position actually changed
@objc private func animationTick() {
    guard let target = targetPosition,
          let startPos = animationStartPosition,
          let startTime = animationStartTime else { return }

    let elapsed = -startTime.timeIntervalSinceNow
    let progress = min(elapsed / animationDuration, 1.0)
    let easedProgress = easeOutQuad(progress)

    let newLat = startPos.latitude + (target.latitude - startPos.latitude) * easedProgress
    let newLon = startPos.longitude + (target.longitude - startPos.longitude) * easedProgress

    // Skip if position barely changed (< 0.1m movement)
    if let current = animatedHeadPosition,
       abs(current.latitude - newLat) < 0.000001,
       abs(current.longitude - newLon) < 0.000001 {
        if progress >= 1.0 { animationStartTime = nil }
        return
    }

    animatedHeadPosition = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    updateSmoothPoints()

    if progress >= 1.0 { animationStartTime = nil }
}
```

**Impact:** Reduces @Published updates from 60/sec to only when head position visibly moves.

### Fix 8: Sun theme timer — only during recording

**File:** `MapViewModel.swift`

5-minute timer runs always, even on Feed/Garage tabs. Move to recording lifecycle.

```swift
// Before — setupSunBasedTheme() in init(), timer runs forever

// After — start timer in startRecording(), stop in stopRecording()
// Initial check still happens once on first location
private func setupSunBasedTheme() {
    locationManager.$currentLocation
        .compactMap { $0 }
        .first()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] update in
            self?.updateThemeForSun(coordinate: update.coordinate)
        }
        .store(in: &cancellables)
    // No timer here
}

private func startRecording() {
    ...
    sunCheckTimer = Timer.publish(every: 300, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] ... }
}

private func stopRecording() {
    ...
    sunCheckTimer?.cancel()
    sunCheckTimer = nil
}
```

**Impact:** Eliminates unnecessary timer when not recording.

## Files Changed

| File | Change |
|------|--------|
| `ContentView.swift` | Conditional tabs instead of opacity |
| `Trip.swift` | Add Equatable |
| `FeedViewModel.swift` | Add Equatable to TripSection |
| `FeedView.swift` | Fix detailVM, remove visibleCards loops |
| `TrackingView.swift` | Cache safe area in @State |
| `MapViewModel.swift` | Async backfill, sun timer lifecycle |
| `SmoothTrackManager.swift` | Skip redundant position updates |

## Risk Assessment

- **Fix 1 (tabs):** Medium risk. Map recreates on switch. Mitigated by MapViewModel persistence. TrackingView.onDisappear now fires on tab switch (previously never happened) — guarded by `!isRecording` check so recording is safe. Edge case: TripCompleteSummaryView sheet may need to survive tab switch — `lastCompletedTrip` lives on MapViewModel so sheet re-presents on return.
- **Fix 2 (Equatable):** Low risk. Additive change, no behavior change.
- **Fix 3 (detailVM):** Low risk. Single call site.
- **Fix 4 (visibleCards):** Low risk. Removing dead code path.
- **Fix 5 (safeArea):** Low risk. Values don't change during app lifecycle.
- **Fix 6 (backfill):** Low risk. Feed loads trips independently; polylines backfill in background.
- **Fix 7 (smoothTrack):** Low risk. Only skips sub-pixel updates.
- **Fix 8 (sun timer):** Low risk. Initial check still happens. During recording, timer active.

## Testing Plan

1. Launch app → verify no freeze on first render (Fix 6)
2. Open Garage → type in fuel inputs → verify zero lag (Fix 1)
3. Start recording → verify track renders smoothly (Fix 7)
4. Switch tabs during recording → verify recording continues (Fix 1)
5. Return to map tab → verify overlays present (Fix 1)
6. Scroll feed with 50+ trips → verify smooth scroll (Fix 2)
7. Filter by date → verify no jank (Fix 4)
8. Record at night → verify dark map theme applies (Fix 8)
9. Stop recording → summary sheet appears → switch to Feed tab → switch back → verify sheet reappears (Fix 1)
10. Cold launch → scroll feed immediately → verify cards render (fallback to full coords before backfill) (Fix 6)
11. Record → pause → resume → verify dark theme persists (Fix 8)
