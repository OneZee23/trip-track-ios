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
- Tests: `HiddenPartsVectorTests`, `TripSyncPayloadMapperTests`,
  `HiddenPhotoSyncTests`, `PublicJourneyDTOTests`,
  `MapSnapshotContentCacheTests`, `HiddenPartsPosterTests`,
  `FilmingModeStateTests`.

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

## Remaining work and deviations

The implementation is incomplete against the spec. The following release work
remains:

- The hidden-parts editor and its entry points, route-bar handles, two-tap
  section creation, staged apply/cancel, number switch, visible-only preview,
  title hint and «already seen» note.
- Own-map Style A dotted hidden runs and lock pins on the hero, fullscreen map,
  journeys and cards. Recording breaks are preserved on the own trip detail;
  hidden-run rendering is not yet wired there.
- Other people's route splitting in journeys and profile fog, replay fades at
  breaks, visible-edge start/finish markers, and the full no-route fallback.
- Publish-sheet public preview and overnight/home hint.
- The one-time question sheet, onboarding page and placeholder
  `HiddenEdgesIllustration` asset. Settings currently has edge and filming
  controls, but not the complete spec layout or home entry.
- App-wide filming filters for Atlas and its revealed public-preview layer,
  home and place markers, places list rows, map location dots, cards, journeys,
  replay and galleries. Only own trip detail route/photo masking is wired.
- The spec's complete string catalog and screenshot tests for the editor,
  publish sheet, question and settings.
- Integration tests for actual photo queue writes, a one-time question shown
  once, and full visibility guards. The photo tests currently cover sync
  decisions; the filming tests cover the state machine.

No version/build number or git state was changed. No staging deployment was
performed; the server branch and staging check are outside this iOS work.
