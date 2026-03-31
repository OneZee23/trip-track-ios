# Backup Export/Import Design

## Context

Users are concerned about losing trip data if they lose their phone or switch devices. Currently all data lives only on-device in CoreData + Documents directory with no backup mechanism. The goal is to let users export all their data to a file and import it back — without any server costs or external dependencies.

## Decisions

- **Transport:** File + Share Sheet (no iCloud, no server)
- **Encryption:** None (user controls where file goes)
- **Scope:** Full backup (trips, tracks, photos, vehicles, settings, territory)
- **Conflict resolution:** Merge by UUID (newer `lastModifiedAt` wins)
- **UI placement:** Settings screen, "Data" section
- **Format:** ZIP archive with `.triptrack` extension
- **Dependencies:** None — minimal ZIP implementation using Foundation

## File Format

`.triptrack` is a ZIP archive (store-only, no compression — photos are already JPEG):

```
TripTrack_2026-03-31.triptrack (ZIP)
├── manifest.json
├── trips.json
├── vehicles.json
├── settings.json
├── territory.json
└── photos/
    ├── {tripId}/{photoId}.jpg
    └── ...
```

### manifest.json

```json
{
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "exportDate": "2026-03-31T15:30:00Z",
  "deviceName": "iPhone 15",
  "stats": {
    "tripCount": 15,
    "trackPointCount": 12450,
    "photoCount": 42,
    "vehicleCount": 2
  }
}
```

### trips.json

Array of trip objects, each containing nested track points and photo metadata:

```json
[
  {
    "id": "uuid",
    "startDate": "iso8601",
    "endDate": "iso8601",
    "title": "Gelendjik -> Krasnodar",
    "tripDescription": "...",
    "region": "Krasnodar Krai",
    "distance": 192900.0,
    "maxSpeed": 37.5,
    "averageSpeed": 18.9,
    "elevation": 1891.0,
    "fuelUsed": 12.9,
    "isPrivate": false,
    "vehicleId": "uuid",
    "xpEarned": 150,
    "badgesJSON": "[\"speed_demon\",\"explorer\"]",
    "previewPolyline": "base64-encoded-binary",
    "lastModifiedAt": "iso8601",
    "trackPoints": [
      {
        "id": "uuid",
        "latitude": 44.5615,
        "longitude": 38.0769,
        "altitude": 25.0,
        "speed": 18.5,
        "course": 45.0,
        "horizontalAccuracy": 5.0,
        "timestamp": "iso8601"
      }
    ],
    "photos": [
      {
        "id": "uuid",
        "filename": "{tripId}/{photoId}.jpg",
        "caption": "Mountain view",
        "timestamp": "iso8601",
        "sortOrder": 0
      }
    ]
  }
]
```

### vehicles.json

```json
[
  {
    "id": "uuid",
    "name": "Telega",
    "avatarEmoji": "car_pixel_1",
    "odometerKm": 45000.0,
    "level": 5,
    "vehicleLevel": 5,
    "cityConsumption": 10.5,
    "highwayConsumption": 7.2,
    "fuelPrice": 65.0,
    "stickersJSON": "[\"sticker1\"]",
    "createdAt": "iso8601",
    "lastModifiedAt": "iso8601"
  }
]
```

### settings.json

```json
{
  "id": "uuid",
  "avatarEmoji": "driver_1",
  "themeMode": "dark",
  "language": "ru",
  "distanceUnit": "km",
  "volumeUnit": "liters",
  "fuelConsumption": 8.5,
  "fuelPrice": 65.0,
  "fuelCurrency": "RUB",
  "profileXP": 1500,
  "profileLevel": 7,
  "currentStreak": 3,
  "bestStreak": 10,
  "selectedVehicleId": "uuid",
  "lastTripDate": "iso8601",
  "lastModifiedAt": "iso8601"
}
```

### territory.json

```json
{
  "visitedGeohashes": [
    {
      "hash6": "ucfv0j",
      "firstVisited": "iso8601",
      "lastVisited": "iso8601",
      "visitCount": 5
    }
  ],
  "roads": [
    {
      "id": "uuid",
      "name": "M4 Don",
      "startGeohash": "ucfv0j",
      "endGeohash": "ucfv1k",
      "geohashSequence": "ucfv0j,ucfv0k,...",
      "distanceKm": 192.9,
      "level": 2,
      "rarity": "rare",
      "timesDriven": 3,
      "firstDriven": "iso8601",
      "lastDriven": "iso8601"
    }
  ]
}
```

### What is NOT exported

- `GeocodeCacheEntity` — cache, auto-regenerates from geocoding
- Thumbnail images (`.thumbnails/`) — auto-regenerated from full photos
- `syncStatus` fields — reset to `.pendingUpload` on import

## Export Flow

1. User taps "Export Data" in Settings
2. Show ProgressView with cancel option
3. `BackupService.export()` on background thread:
   a. Fetch all entities from CoreData via `viewContext.perform {}`
   b. Encode to Codable structs → JSON Data
   c. Create temp directory in `tmp/`
   d. Write JSON files
   e. Copy photos from `Documents/TripPhotos/`
   f. Package into ZIP using `ZIPArchive.create()`
   g. Name: `TripTrack_{yyyy-MM-dd}.triptrack`
4. Present Share Sheet with the `.triptrack` file
5. Clean up temp directory after Share Sheet dismisses

### Error handling

- CoreData fetch failure → show alert, abort
- Disk space check before export (estimate: sum of photo sizes + ~1MB for JSON)
- Individual photo missing → skip, log warning, continue export

## Import Flow

1. User taps "Import Data" in Settings
2. `UIDocumentPickerViewController` opens, filtered to `.triptrack` UTType
3. Read and parse `manifest.json` → show preview:
   > "Backup from Mar 31, 2026: 15 trips, 42 photos. Import?"
4. User confirms
5. Show ProgressView
6. `BackupService.import()` on background context:
   a. Unzip to temp directory
   b. Validate `formatVersion` (must be <= current supported version)
   c. Parse JSON files
   d. **Merge logic per entity type:**

### Merge Strategy

| Entity | Key | Conflict Rule |
|--------|-----|--------------|
| TripEntity | `id` (UUID) | If exists: update if backup `lastModifiedAt` is newer. If not exists: create. If exists and local is newer: skip |
| TrackPointEntity | — | Follows parent trip. If trip is created/updated, delete existing points and recreate from backup. If trip is skipped, points are skipped |
| TripPhotoEntity | `id` (UUID) | Follows parent trip. If trip is created/updated: add missing photos (by id). Copy photo file only if not already present on disk |
| VehicleEntity | `id` (UUID) | If exists: update if backup `lastModifiedAt` is newer. If not: create |
| UserSettingsEntity | singleton | Update if backup `lastModifiedAt` is newer |
| VisitedGeohashEntity | `hash6` | If exists: merge — take max `visitCount`, earliest `firstVisited`, latest `lastVisited`. If not: create |
| RoadEntity | `id` (UUID) | If exists: take max `timesDriven`, earliest `firstDriven`, latest `lastDriven`. If not: create |

7. Show result summary:
   > "Added 5 trips, updated 2, skipped 8. Added 15 photos."
8. Clean up temp directory
9. Refresh UI (post notification or update `@Published` properties)

### Error handling

- Invalid/corrupted ZIP → show alert "File is not a valid TripTrack backup"
- Unsupported `formatVersion` → show alert "This backup was created by a newer version. Update TripTrack to import"
- Partial import failure (e.g. one trip fails) → continue with rest, show warning in summary
- Photo file missing in ZIP → create entity without photo file, log warning

## UTType Registration

Register `.triptrack` as a custom document type in `project.yml`:

- UTType identifier: `com.onezee.triptrack.backup`
- Conforms to: `public.data`, `public.zip-archive`
- Extension: `.triptrack`
- MIME type: `application/zip`

This enables:
- Document picker filtering
- Opening `.triptrack` files from Files app / Telegram / AirDrop launches TripTrack

Handle incoming files via `onOpenURL` modifier in the app's root view.

## New Files

| File | Purpose |
|------|---------|
| `TripTrack/Services/BackupService.swift` | Export/import orchestration, JSON encoding/decoding |
| `TripTrack/Services/ZIPArchive.swift` | Minimal ZIP read/write using Foundation (store-only, no compression) |
| `TripTrack/Models/BackupModels.swift` | Codable structs: `BackupManifest`, `BackupTrip`, `BackupTrackPoint`, `BackupPhoto`, `BackupVehicle`, `BackupSettings`, `BackupTerritory` |
| `TripTrack/Views/Settings/DataManagementSection.swift` | "Export Data" / "Import Data" UI in settings |

## Modified Files

| File | Change |
|------|--------|
| `project.yml` | Add UTType for `.triptrack`, add document type |
| Settings view | Add "Data" section with DataManagementSection |
| `AppStrings.swift` | Add localization keys for backup UI (RU/EN) |
| Root view (ContentView/MainTabView) | Add `onOpenURL` handler for `.triptrack` files |

## ZIP Implementation Notes

Minimal ZIP using Foundation only (no external dependencies):

- **Write:** Local File Header + file data (store, no compression) + Central Directory + End of Central Directory
- **Read:** Find End of Central Directory → parse Central Directory → extract files by offset
- Store-only (compression method 0) is fine because:
  - Photos are already JPEG compressed
  - JSON data is typically small (<1MB even for hundreds of trips)
  - Simplifies implementation significantly (~200-300 lines)

## Localization

All new strings go through `AppStrings`:

| Key | RU | EN |
|-----|-----|-----|
| exportData | Экспорт данных | Export Data |
| importData | Импорт данных | Import Data |
| exporting | Экспортируем... | Exporting... |
| importing | Импортируем... | Importing... |
| backupPreview | Бекап от {date}: {trips} поездок, {photos} фото | Backup from {date}: {trips} trips, {photos} photos |
| importConfirm | Импортировать? | Import? |
| importResult | Добавлено {added}, обновлено {updated}, пропущено {skipped} | Added {added}, updated {updated}, skipped {skipped} |
| invalidBackup | Файл не является бекапом TripTrack | File is not a valid TripTrack backup |
| newerVersion | Этот бекап создан новой версией. Обновите TripTrack | This backup requires a newer version. Update TripTrack |
| exportError | Не удалось создать бекап | Failed to create backup |

## Verification

1. **Export test:** Create a trip with track points and photos → export → verify ZIP contains all JSON files and photos → open in another app (Files) to verify Share Sheet works
2. **Import test:** Take exported file → delete app data → import → verify all trips, photos, settings restored
3. **Merge test:** Export → add new trip → import same backup → verify new trip remains, no duplicates
4. **Edge cases:** Import on fresh install (no existing data), import empty backup, import backup with missing photos
5. **UTType test:** Send `.triptrack` file via AirDrop/Telegram → verify app opens and offers import
