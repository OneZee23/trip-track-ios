# Auto Trip Detection v2 — CMMotion + Always Location

## Context

v0.3.0 introduced Bluetooth-based auto-trip detection (audio route + BLE scan). It works when the app is alive and the user unlocks their phone. However, it doesn't work after force-quit or on lock screen — iOS limitation: `AVAudioSession.routeChangeNotification` requires a live process, and no API can detect Classic Bluetooth connections after app termination.

This spec adds CMMotionActivityManager as the primary detection layer that **survives force-quit** using `significantLocationChanges` (requires Always location permission). Bluetooth remains as a vehicle-selection refinement layer.

## Architecture — Three Detection Layers

### Layer 1: Audio Route (instant, app alive)
- **Trigger**: `AVAudioSession.routeChangeNotification` + `UIApplication.didBecomeActiveNotification`
- **When**: App in foreground or suspended in memory
- **Latency**: 0 seconds
- **Survives force-quit**: No

### Layer 2: CMMotion + Significant Location (force-quit safe)
- **Trigger**: `significantLocationChanges` wakes app → `CMMotionActivityManager.queryActivityStarting()` confirms `.automotive`
- **When**: Always, including after force-quit and on lock screen
- **Latency**: 1-3 minutes (need cell tower change ~500m)
- **Survives force-quit**: Yes (only mechanism that does)
- **Requires**: Always location + Motion & Fitness permissions

### Layer 3: BT Vehicle Selection (refinement)
- **When**: Layer 1 or 2 triggers → check audio route for saved BT device → select correct vehicle
- **Fallback**: If no BT configured, use default/selected vehicle

## Detection Flow

```
┌─ App alive in memory ─────────────────────────┐
│ AVAudioSession route change                    │
│ → BT device matches saved? → select vehicle    │
│ → mode=auto: start recording                   │
│ → mode=remind: send notification               │
└────────────────────────────────────────────────┘

┌─ App terminated / force-quit ──────────────────┐
│ iOS wakes app via significantLocationChanges    │
│ → CMMotionActivityManager.query(last 5 min)    │
│ → .automotive detected with .high confidence?   │
│   → YES: check audio route for BT device       │
│          → start recording + notification       │
│   → NO: go back to sleep                       │
└────────────────────────────────────────────────┘

┌─ User unlocks phone ──────────────────────────┐
│ didBecomeActive fires                          │
│ → check audio route for saved BT device        │
│ → if found + not recording → trigger           │
└────────────────────────────────────────────────┘
```

## New: MotionDetector Service

```swift
final class MotionDetector {
    private let motionManager = CMMotionActivityManager()
    var onAutomotiveDetected: (() -> Void)?
    var onAutomotiveEnded: (() -> Void)?

    // Foreground: real-time activity updates
    func startLiveUpdates()
    func stopLiveUpdates()

    // Background: query historical activity (works after any wake)
    func queryRecentAutomotive(completion: @escaping (Bool) -> Void)
    // Queries last 5 minutes for .automotive with .high confidence
}
```

## AutoTripService Changes

### Background Launch Handling

In `TripTrackApp.init()` or via `UIApplicationDelegate`:
- Check if launched by location event
- Call `AutoTripService.shared.handleBackgroundLaunch()`
- Which calls `motionDetector.queryRecentAutomotive()` → if yes → trigger auto-start

### Significant Location Delegate

`AutoTripService` starts `significantLocationChanges` when auto-record is enabled + Always permission granted. On each location update:
1. Query CMMotion for recent automotive activity
2. If automotive → check audio route → start recording
3. If not automotive → ignore, go back to sleep

### Auto-stop Logic

- CMMotion `.automotiveEnded` (foreground) → start timer
- BT disconnected → start timer
- Both signals combined for higher confidence
- Timer duration: user-configured (1-10 min, default 3)

## Permissions

### Always Location
- **When to ask**: When user enables auto-record toggle in VehicleDetailView
- **Pre-permission screen**: Custom explanation before system dialog
  - "To detect when you start driving, TripTrack needs background location access"
  - "No location data is stored — it's only used to wake the app when you start moving"
  - "This enables automatic trip recording even when the app is closed"
- **If denied**: Auto-record works only when app is alive (Layer 1 only)
- **Info.plist key**: `NSLocationAlwaysAndWhenInUseUsageDescription`

### Motion & Fitness
- **When to ask**: Same time as Always location
- **Info.plist key**: `NSMotionUsageDescription`
- **If denied**: Fall back to location-only detection (less accurate, more false positives)

## Route Recovery

When auto-start triggers via Layer 2 (1-3 min delay), the first part of the trip is missing. Mitigation:
- On auto-start, `CLLocationManager` provides `location` property with last known position
- The significant location change callback includes recent `CLLocation` objects
- Use these to reconstruct approximate start point
- Mark recovered portion in trip data (dashed line on map vs solid for GPS-recorded)

## Files to Create/Modify

### New:
- `TripTrack/Services/MotionDetector.swift` — CMMotionActivityManager wrapper

### Modify:
- `TripTrack/Services/AutoTripService.swift` — add MotionDetector, significantLocationChanges, background launch
- `TripTrack/Views/Profile/VehicleDetailView.swift` — pre-permission explanation for Always location
- `TripTrack/App/TripTrackApp.swift` — handle location-based background launch
- `TripTrack/Info.plist` — add NSMotionUsageDescription
- `project.yml` — update Always location description text

### Onboarding (separate follow-up):
- New onboarding page explaining Always location benefit

## Verification

1. **Foreground test**: App open → connect BT → instant notification
2. **Unlock test**: App backgrounded → connect BT → unlock phone → notification
3. **Force-quit test**: Force quit app → drive (or walk 500m+) → app wakes → check CMMotion → auto-start
4. **Lock screen test**: Same as force-quit but with phone locked
5. **False positive test**: Ride as passenger in someone else's car → should NOT auto-start (no BT match)
6. **Auto-stop test**: Stop driving → BT disconnects → timer → trip ends
7. **Permission denied test**: Always location denied → still works via Layer 1 (foreground only)
