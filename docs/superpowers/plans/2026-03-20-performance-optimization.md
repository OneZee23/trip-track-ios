# Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate input lag, feed scroll jank, and unnecessary background work across TripTrack.

**Architecture:** 8 surgical fixes to existing files. No new files, no architecture changes. Each fix is independent and can be committed separately.

**Tech Stack:** SwiftUI, Combine, MapKit, CoreData, XCTest

**Spec:** `docs/superpowers/specs/2026-03-20-performance-optimization-design.md`

---

### Task 1: Add Equatable to Trip and TripSection

**Files:**
- Modify: `TripTrack/Models/Trip.swift` (add extension at bottom)
- Modify: `TripTrack/ViewModels/FeedViewModel.swift:4-8` (add Equatable to TripSection)
- Test: `TripTrackTests/TripTrackTests.swift`

- [ ] **Step 1: Write tests for Trip Equatable**

Add to `TripTrackTests/TripTrackTests.swift`:

```swift
func testTripEquatable_sameTrip() {
    let id = UUID()
    let date = Date()
    let trip1 = Trip(id: id, startDate: date, distance: 1000, title: "Test")
    let trip2 = Trip(id: id, startDate: date, distance: 1000, title: "Test")
    XCTAssertEqual(trip1, trip2)
}

func testTripEquatable_differentTitle() {
    let id = UUID()
    let date = Date()
    let trip1 = Trip(id: id, startDate: date, title: "A")
    let trip2 = Trip(id: id, startDate: date, title: "B")
    XCTAssertNotEqual(trip1, trip2)
}

func testTripEquatable_ignoresTrackPoints() {
    let id = UUID()
    let date = Date()
    let point = TrackPoint(latitude: 55.0, longitude: 37.0)
    let trip1 = Trip(id: id, startDate: date)
    let trip2 = Trip(id: id, startDate: date, trackPoints: [point])
    XCTAssertEqual(trip1, trip2, "Equatable should ignore trackPoints for performance")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:TripTrackTests/TripTrackTests/testTripEquatable_sameTrip 2>&1 | tail -5`

Expected: FAIL — Trip does not conform to Equatable

- [ ] **Step 3: Add Equatable to Trip**

Add at bottom of `TripTrack/Models/Trip.swift`:

```swift
// Manual Equatable: excludes trackPoints (large array kills SwiftUI diffing)
// and rarely-changing fields (tripDescription, isPrivate, vehicleId, fuelUsed,
// elevation, maxSpeed, averageSpeed) that don't affect feed card rendering.
// Includes previewPolyline because async backfill updates it.
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
```

- [ ] **Step 4: Add Equatable to TripSection**

In `TripTrack/ViewModels/FeedViewModel.swift`, change the TripSection struct:

```swift
struct TripSection: Identifiable, Equatable {
    let id: String
    let title: String
    let trips: [Trip]
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`

Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add TripTrack/Models/Trip.swift TripTrack/ViewModels/FeedViewModel.swift TripTrackTests/TripTrackTests.swift
git commit -m "perf: add Equatable to Trip and TripSection for SwiftUI diffing"
```

---

### Task 2: ContentView — conditional tab rendering

**Files:**
- Modify: `TripTrack/Views/ContentView.swift:14-31`

- [ ] **Step 1: Replace opacity swap with switch**

In `TripTrack/Views/ContentView.swift`, replace **only** the three tab views with opacity/allowsHitTesting (lines 16-30). Keep all outer modifiers unchanged (`.ignoresSafeArea`, `.environmentObject(mapVM)`, badge overlay, notification receivers, `.onAppear` — lines 36-60).

**Note:** FeedView will now be destroyed/recreated on tab switches. This is fine — its `.onAppear` guard (`if visibleCards.isEmpty`) re-triggers `loadTrips()`. CoreData fetch is fast (<10ms for typical trip counts).

Replace lines 16-30 with:

```swift
switch selectedTab {
case 0:
    FeedView(tripManager: mapVM.tripManager, selectedTab: $selectedTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
case 1:
    TrackingView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, mapVM.isDarkMap ? .dark : systemScheme)
case 2:
    RegionsView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
default:
    EmptyView()
}
```

The outer `ZStack(alignment: .bottom)`, `CustomTabBar`, and all modifiers after line 35 remain unchanged.

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TripTrack/Views/ContentView.swift
git commit -m "perf: conditional tab rendering instead of opacity swap

Only the active tab's view tree exists. MapViewModel persists as
@StateObject in ContentView — recording state survives tab switches."
```

---

### Task 3: FeedView — remove detailVM and visibleCards loops

**Files:**
- Modify: `TripTrack/Views/Feed/FeedView.swift`

- [ ] **Step 1: Inline detailVM at navigationDestination call site**

In `TripTrack/Views/Feed/FeedView.swift`, replace the `.navigationDestination` block (lines 67-74):

```swift
.navigationDestination(isPresented: Binding(
    get: { selectedTripId != nil },
    set: { if !$0 { selectedTripId = nil } }
)) {
    if let id = selectedTripId {
        TripDetailView(tripId: id, viewModel: TripsViewModel(tripManager: feedVM.tripManager))
    }
}
```

- [ ] **Step 2: Delete the detailVM computed property**

Remove lines 396-398:

```swift
private var detailVM: TripsViewModel {
    TripsViewModel(tripManager: feedVM.tripManager)
}
```

- [ ] **Step 3: Remove visibleCards loop from dateFrom binding setter**

Change line 39 from:
```swift
feedVM.setDateRange(from: newDate, to: feedVM.filters.dateTo)
for trip in feedVM.trips { visibleCards.insert(trip.id) }
```
To:
```swift
feedVM.setDateRange(from: newDate, to: feedVM.filters.dateTo)
```

- [ ] **Step 4: Remove visibleCards loop from dateTo binding setter**

Change line 46 from:
```swift
feedVM.setDateRange(from: feedVM.filters.dateFrom, to: newDate)
for trip in feedVM.trips { visibleCards.insert(trip.id) }
```
To:
```swift
feedVM.setDateRange(from: feedVM.filters.dateFrom, to: newDate)
```

- [ ] **Step 5: Remove visibleCards loop from .refreshable**

Change line 114 from:
```swift
.refreshable { feedVM.language = lang.language; feedVM.loadTrips(); for trip in feedVM.trips { visibleCards.insert(trip.id) } }
```
To:
```swift
.refreshable { feedVM.language = lang.language; feedVM.loadTrips() }
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild build -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add TripTrack/Views/Feed/FeedView.swift
git commit -m "perf: remove detailVM reallocation and O(n) visibleCards loops"
```

---

### Task 4: TrackingView — cache safe area values

**Files:**
- Modify: `TripTrack/Views/Tracking/TrackingView.swift`

- [ ] **Step 1: Replace computed properties with @State**

In `TripTrack/Views/Tracking/TrackingView.swift`:

1. Add `@State` properties near the top of the struct (after `@EnvironmentObject`):

```swift
@State private var safeAreaTop: CGFloat = 59
@State private var tabBarHeight: CGFloat = 88
```

2. Delete the two computed properties `safeAreaTop` (lines 179-183) and `tabBarHeight` (lines 185-190).

3. Keep `idleHUDInset` as computed — it just references `tabBarHeight`:
```swift
private var idleHUDInset: CGFloat {
    tabBarHeight + 380
}
```

4. Update `.onAppear` to cache values:

```swift
.onAppear {
    viewModel.requestLocationPermission()
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = scene.windows.first {
        safeAreaTop = window.safeAreaInsets.top
        tabBarHeight = 54 + window.safeAreaInsets.bottom
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TripTrack/Views/Tracking/TrackingView.swift
git commit -m "perf: cache safe area insets in @State instead of per-frame UIKit traversal"
```

---

### Task 5: MapViewModel — async backfill and sun timer lifecycle

**Files:**
- Modify: `TripTrack/ViewModels/MapViewModel.swift`

- [ ] **Step 1: Move backfillPreviewPolylines into async Task**

In `TripTrack/ViewModels/MapViewModel.swift`, change `init()` (lines 64-87):

```swift
init() {
    let manager = LocationManager()
    self.locationManager = manager
    self.tripManager = TripManager(locationManager: manager)

    setupRecordingBindings()
    setupSunBasedTheme()
    refreshTripStats()

    Task { @MainActor [tripManager, gamificationManager, territoryManager] in
        tripManager.backfillPreviewPolylines()
        tripManager.migrateRegionsIfNeeded()

        let allTrips = tripManager.fetchTrips()
        let settingsEntity = gamificationManager.fetchSettingsEntity()
        gamificationManager.backfillIfNeeded(trips: allTrips, settingsEntity: settingsEntity)

        territoryManager.backfillIfNeeded()
    }
}
```

- [ ] **Step 2: Remove timer from setupSunBasedTheme**

Replace `setupSunBasedTheme()` (lines 357-375) with:

```swift
private func setupSunBasedTheme() {
    // Check once when first location arrives
    locationManager.$currentLocation
        .compactMap { $0 }
        .first()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] update in
            self?.updateThemeForSun(coordinate: update.coordinate)
        }
        .store(in: &cancellables)
}
```

- [ ] **Step 3: Start sun timer in startRecording**

In `startRecording()`, add before the haptic feedback line:

```swift
// Sun-based theme check during recording
sunCheckTimer = Timer.publish(every: 300, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        guard let self, let loc = self.locationManager.currentLocation else { return }
        self.updateThemeForSun(coordinate: loc.coordinate)
    }
```

- [ ] **Step 4: Stop sun timer in stopRecording**

In `stopRecording()`, add after `durationTimer = nil`:

```swift
sunCheckTimer?.cancel()
sunCheckTimer = nil
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild build -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add TripTrack/ViewModels/MapViewModel.swift
git commit -m "perf: async backfill polylines, sun timer only during recording"
```

---

### Task 6: SmoothTrackManager — skip sub-pixel updates

**Files:**
- Modify: `TripTrack/Services/SmoothTrackManager.swift:130-154`

- [ ] **Step 1: Update animationTick with position delta check**

Replace `animationTick()` in `TripTrack/Services/SmoothTrackManager.swift` (lines 130-154) with:

```swift
@objc private func animationTick() {
    guard let target = targetPosition,
          let startPos = animationStartPosition,
          let startTime = animationStartTime else {
        return
    }

    let elapsed = -startTime.timeIntervalSinceNow
    let progress = min(elapsed / animationDuration, 1.0)
    let easedProgress = easeOutQuad(progress)

    let newLat = startPos.latitude + (target.latitude - startPos.latitude) * easedProgress
    let newLon = startPos.longitude + (target.longitude - startPos.longitude) * easedProgress

    // Skip publish if position barely changed (< ~0.1m)
    if let current = animatedHeadPosition,
       abs(current.latitude - newLat) < 0.000001,
       abs(current.longitude - newLon) < 0.000001 {
        if progress >= 1.0 { animationStartTime = nil }
        return
    }

    animatedHeadPosition = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    updateSmoothPoints()

    if progress >= 1.0 {
        animationStartTime = nil
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add TripTrack/Services/SmoothTrackManager.swift
git commit -m "perf: skip sub-pixel position updates in track animation"
```

---

### Task 7: Run full test suite

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Expected: All tests PASS (including new Equatable tests from Task 1)

- [ ] **Step 2: Build release config to check for warnings**

Run: `xcodebuild build -scheme TripTrack -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Release 2>&1 | grep -E '(warning:|error:|BUILD)' | tail -20`

Expected: BUILD SUCCEEDED, no new warnings

- [ ] **Step 3: Manual QA checklist**

Run through the testing plan from the spec (`docs/superpowers/specs/2026-03-20-performance-optimization-design.md`, Testing Plan section):

1. Launch app — no freeze on first render
2. Open Garage — type in fuel inputs — zero lag
3. Start recording — track renders smoothly
4. Switch tabs during recording — recording continues
5. Return to map tab — overlays present
6. Scroll feed with 50+ trips — smooth scroll
7. Filter by date — no jank
8. Record at night — dark map theme applies
9. Stop recording — summary sheet — switch tabs — switch back — sheet reappears
10. Cold launch — scroll feed immediately — cards render
11. Record — pause — resume — dark theme persists
