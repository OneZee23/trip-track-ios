# iOS implementation report

## Implemented

- Added the v25 Core Data model and `TripHiddenParts`, `PrivacySettings`, and
  `HiddenPartsResolver`. The vector test now checks visible-run distance,
  visible start/end timestamps, preview point count, hidden ranges and photo
  visibility.
- Kept the local full trip during pull and conflict handling when its effective
  mask hides points. The decision uses the trip settings, global edge default
  and home zone, so older server responses cannot replace local data with a
  masked copy.
- Implemented visible-run public distance and date values when
  `numbersVisibleOnly` is enabled. Movement and altitude aggregates use the
  visible route. Added mapper coverage.
- Added `HiddenPhotoSync` visibility decisions and queue reconciliation: hidden
  photos are not uploaded, remote copies are deleted, and newly visible local
  photos are queued for upload. Pulls check the local mask and privacy status
  before removing omitted photos, so hidden photos keep their rows and files.
- Persisted masked preview break indices in the optional v25 `previewBreaksJSON`
  attribute and restore them when rebuilding a trip from Core Data.
- Kept maximum altitude empty when visible-only numbers are enabled and the
  mask hides every measured point.
- Added home-zone resync for public trips and cloud-synced private trips, and
  retained the R2 metadata-sanitization failure behavior (failed stripping
  retries instead of uploading original bytes).
- Added preview-break support to social trip DTOs, social cards, public profile
  map snapshots, trip detail maps and the reusable fullscreen route map. Cards
  can show «Маршрут скрыт автором» when a newer server supplies a positive
  distance but no public route.
- Made `MapSnapshotPreview` cache keys depend on route coordinates and breaks.
  Own-trip posters use the public route, visible-only metrics and visible
  photos; poster paths split at breaks.
- Added the filming-mode state model and screen-capture observer, plus manual
  and automatic controls in Privacy Settings. The own trip detail masks hidden
  route sections and hidden photos while filming mode is active. Atlas builds
  from a separate masked public-preview layer and filters its photo pins with
  the same privacy resolution.
- Added the current privacy and filming strings to all 13 language tables.
  Localization tests enforce matching keys and number/unit discipline.
- Added the «Скрытые участки и режим съёмки (0.9.4)» rules to `CLAUDE.md`.

## Files

- Models and persistence: `TripHiddenParts.swift`, `PrivacySettings.swift`,
  `Trip.swift`, `TripSyncPayload.swift`, `TripRepository.swift`, v25 model.
- Privacy and sync: `HiddenPhotoSync.swift`, `HomePrivacyResync.swift`,
  `FilmingModeManager.swift`, photo sync status and R2 sanitization.
- Public routes and posters: social trip/profile DTOs and views,
  `RouteMapView.swift`, `FullscreenMapSheet.swift`, `MapSnapshotPreview.swift`,
  `StoryShareData` and poster rendering.
- Localization: `AppStrings.swift`, `Translations+HiddenPrivacy.swift`,
  `LocalizationTests.swift`.
- New UI: `HiddenPartsEditorView.swift`, `HiddenEdgesQuestionSheet.swift`,
  `PrivacySettingsView.swift`, the publish-sheet route preview and the own-map
  route overlays.
- Tests: `HiddenPartsPullPersistenceTests`, `HiddenPartsVectorTests`,
  `TripSyncPayloadMapperTests`, `HiddenPhotoSyncTests`,
  `RecordingBreaksPersistenceTests`, `PublicJourneyDTOTests`,
  `MapSnapshotContentCacheTests`, `HiddenPartsPosterTests`,
  `FilmingModeStateTests`, `HiddenPartsEditorModelTests`,
  `FilmingModeFiltersTests`, `HiddenPartsEditorShotTests`,
  `HiddenPartsSurfaceShotTests`.
  `FilmingModeShotTests` captures Atlas and Places with the mode off and on.

## Verification

- The bridge ran `xcodegen generate` twice and `build-for-testing`; the build
  passed.
- `FilmingModeFiltersTests`, `FilmingModeStateTests`,
  `HiddenPartsEditorModelTests`, `HiddenPartsCopyTests`, `LocalizationTests`
  and `AtlasPresentationTests` passed.
- `HiddenPartsSurfaceShotTests` passed the question, onboarding, privacy,
  publish and own-map captures in light and dark.
- `FilmingModeShotTests` passed Atlas and Places captures with filming mode
  off and on. The inspected images hide the home marker, home-area places and
  the photo pin in a hidden run when filming mode is on.
- `LocalizationTests` passed its 13-language key and number/unit checks.
  UI-test API traffic points to localhost.
- The bridge build passed. The requested unit suite passed:
  `HiddenPartsPullPersistenceTests`, `HomePrivacyTrimTests`,
  `PrivacyZoneDisciplineTests`, `RecordingBreaksPersistenceTests`,
  `HiddenPartsVectorTests`, `HiddenPhotoSyncTests`,
  `TripSyncPayloadMapperTests`, and Core Data migrations v9, v10, v12, v13,
  v14, v22, v23 and v24.
- Capture images and `manifest.json` are in `.codex-work/shots/`.

No app version was changed. Git was not used.
