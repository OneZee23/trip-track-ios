# TripTrack — Technical Solution (Release v0.1.0)

## Document Status
- Product: TripTrack (iOS)
- Release target: `v0.1.0`
- Status: Release-ready architecture baseline
- Last updated: 2026-03-24

---

## 1) Architecture Summary
TripTrack follows MVVM + Service Layer with offline-first persistence.

Data flow:
Views -> ViewModels -> Services -> CoreData/Documents

Main layers:
- Presentation: SwiftUI views and feature modules
- Application: ViewModels with UI state and orchestration
- Domain/Services: tracking, trips, gamification, territories, settings
- Persistence: CoreData entities + photo files in Documents

---

## 2) Platform & Constraints
- iOS 17+, iPhone only
- Swift 5.9
- SwiftUI + MapKit + CoreData
- No third-party dependencies
- Background location mode enabled for active trip recording

---

## 3) Core Components
- `MapViewModel`: recording lifecycle, map state, in-trip HUD data
- `FeedViewModel`: trip listing, grouping, filtering, pagination
- `TripManager`: trip CRUD, batch point saves, geocoding integration
- `LocationManager` + providers:
  - `RealGPSProvider` (CoreLocation)
  - `SimulatedLocationProvider` (dev/testing mode)
- `SmoothTrackManager`: filtering/smoothing for route quality
- `GamificationManager` + `BadgeManager`: XP, levels, badges logic
- `TerritoryManager` + geohash utilities: exploration/fog map progress

---

## 4) Persistence Model
Primary storage:
- CoreData (`TripEntity` as aggregate root)
- Related entities for track points, photos, vehicles, settings, visited regions, roads

Supplementary storage:
- Trip photos in app Documents directory
- User preference/settings values in local storage via settings manager

Key persistence choices:
- Async/non-blocking save paths for frequent GPS updates
- Batch write strategy for location points
- Cleanup of junk trips (very short distance and duration)

---

## 5) Tracking & Map Pipeline
Trip pipeline:
1. User starts recording
2. Location updates stream from active provider
3. Points are validated/smoothed
4. Batched persistence writes are performed
5. Route and HUD update in real time
6. User stops recording and receives trip summary

Map-related capabilities in `v0.1.0`:
- Route rendering during and after recording
- Speed-aware visualizations in trip detail
- Exploration map with fog-of-war behavior

---

## 6) Reliability & Performance Considerations
- Batch saves reduce IO overhead during long trips
- Service separation keeps business logic out of views
- Local-only data model avoids network dependency failures
- Reusable map and card UI components reduce maintenance cost

---

## 7) Security & Privacy
- No account/login required
- No third-party analytics SDK
- No backend data sync in this release
- Trip/location/photo data remains on-device

---

## 8) Release Links
- Repository: https://github.com/OneZee23/trip-track-ios
- Issues / Support: https://github.com/OneZee23/trip-track-ios/issues
- Privacy policy: https://onezee23.github.io/trip-track-ios/docs/privacy-policy.html
