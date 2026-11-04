# iOS implementation report

## Implemented

- Added the v25 Core Data model and `TripHiddenParts`, `PrivacySettings`, and
  `HiddenPartsResolver`. The vector test now checks visible-run distance,
  visible start/end timestamps, preview point count, hidden ranges and photo
  visibility.
- Kept the full local route during pull and conflict handling. `TripSyncPayload`
  masks route, preview, photo and checkpoint data at the upload boundary.
- Implemented visible-run public distance and date values when
  `numbersVisibleOnly` is enabled. Movement and altitude aggregates use the
  visible route. Added mapper coverage.
- Added `HiddenPhotoSync` visibility decisions and queue reconciliation: hidden
  photos are not uploaded, remote copies are deleted, and newly visible local
  photos are queued for upload.
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
  route sections and hidden photos while filming mode is active.
- Added the current privacy and filming strings to all 13 language tables.
  Localization tests enforce matching keys and number/unit discipline.
- Added the «Скрытые участки и режим съёмки (0.9.4)» rules to `CLAUDE.md`.

## Files

- Models and persistence: `TripHiddenParts.swift`, `PrivacySettings.swift`,
  `Trip.swift`, `TripSyncPayload.swift`, `TripRepository.swift`.
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
- Tests: `HiddenPartsVectorTests`, `TripSyncPayloadMapperTests`,
  `HiddenPhotoSyncTests`, `PublicJourneyDTOTests`,
  `MapSnapshotContentCacheTests`, `HiddenPartsPosterTests`,
  `FilmingModeStateTests`, `HiddenPartsEditorModelTests`,
  `HiddenPartsEditorShotTests`, `HiddenPartsSurfaceShotTests`.

## Verification

- The bridge ran `xcodegen generate` twice and `build-for-testing`; the latest
  build passed.
- Passed bridge test runs: `HiddenPartsVectorTests`,
  `TripSyncPayloadMapperTests`, `HiddenPhotoSyncTests`,
  `PublicJourneyDTOTests`, `FeedPreviewCachePerfTests`,
  `MapSnapshotContentCacheTests`, `FilmingModeStateTests`,
  `PrivacyFlowE2ETests`, `HiddenPartsPosterTests`, and `LocalizationTests`.
- The combined regression request for all nine classes also passed:
  `HiddenPartsVectorTests`, `TripSyncPayloadMapperTests`,
  `HiddenPhotoSyncTests`, `PublicJourneyDTOTests`,
  `MapSnapshotContentCacheTests`, `FilmingModeStateTests`,
  `PrivacyFlowE2ETests`, `HiddenPartsPosterTests`, and `LocalizationTests`.
- The first localization run caught the fixed-radius labels in the existing
  number/unit guard. The three preset keys now document why their units are
  fixed; the localization rerun passed.
- Build/test requests and results are in `.codex-work`; tests ran through the
  supplied simulator bridge.

## This run

- Added the staged «Скрыть от других» editor and its trip menu, edit sheet,
  publish sheet and own-trip-card entry points. Middle sections snap to route
  points, merge on overlap and can be resized on the trip bar. The number
  switch previews visible distance and duration.
- Added Style A to own trip and journey maps and own trip thumbnails. Public
  previews and journeys split at `previewBreaks`; replay fades at remote
  recording breaks; missing public routes show «Маршрут скрыт автором».
- Added the public publish-map preview, hidden-summary row, home/place/previous
  trip quick-hide hints, one-time privacy question, onboarding art and the
  complete local privacy section with the home entry.
- Added the hidden-edges screen copy to all 13 languages, DEBUG seed/open flags,
  editor/question model tests, and light/dark UI screenshot tests.

## Verification and limits

- The final bridge `build` passed. `HiddenPartsEditorModelTests` and
  `LocalizationTests` passed, including key parity, translation reachability
  and number/unit checks.
- The editor screenshot class passed once and exported fresh/dark, sections and
  numbers captures. I inspected them against the approved mockups, shortened
  the map and moved the screen to a full-screen surface. The first captures
  exposed an empty debug seed; the seed now loads full trip details, and the
  scroll content has extra room above the home indicator.
- UI screenshot recaptures and the question/onboarding/settings/publish/map
  shot class returned `unknown request` from the bridge after those final
  changes. The latest code builds, but its UI captures still need a bridge run
  and visual review.
- App-wide filming filters for Atlas, Places, location dots, galleries and
  other own surfaces remain in the next run, as scoped by the request.

No version/build number or git state was changed. The UI fixtures use local
data only. The bridge did not launch the final recapture requests.
