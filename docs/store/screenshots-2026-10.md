# App Store screenshot series — October 2026

Updated 7 October 2026. Languages: Russian and English (U.S.). Approved visual
direction: A, light travel journal. Exports: 1320 × 2868, 8-bit RGB PNG, sRGB, no alpha.

**The full series is exported: 8 Russian + 8 English cards, 16 PNGs.**
The local preview and download archive contain the same verified final images.
The new artwork has not been uploaded to App Store Connect in this round.

| Position | Feature | Russian headline | English headline | Status |
|---|---|---|---|---|
|01|Recorded route|Поездка прошла. Маршрут остался.|The drive ends. The route stays.|Previous export retained|
|02|Atlas and road fog|Ваши дороги. Ваш атлас.|Your roads. Your atlas.|Both languages exported|
|03|Companions|Одна поездка. Общие истории.|One trip. Shared stories.|Both languages exported; real invitation sheet|
|04|Photos and notes|Вспомните, как это было.|Remember how it felt.|Previous export retained|
|05|Trip statistics|Вся поездка. В деталях.|Every drive. Every detail.|Previous export retained|
|06|Garage|Каждая машина. Своя история.|Every car. Its own story.|Both languages exported with plate hidden|
|07|Public trips and feed|Делитесь поездками.|Share your journeys.|Both languages exported|
|08|Levels and achievements|Больше поездок. Выше уровень.|More journeys. New milestones.|Both languages exported; original pixel art|

Atlas follows the first route card so discovery is visible early. Photos and
statistics retain the approved existing artwork; their sequence positions change.

## Achievement artwork

Owner correction 7 October: use the existing pixel-art achievement illustrations.
The new composition uses original SVGs from
`TripTrack/Resources/Assets.xcassets/Badges`, exactly as referenced by `BadgeArt`.
Captions come from `BadgeDefinitions`, in each language. Selected catalogue
examples: highway_wolf, centurion, carpool_karaoke, endurance, early_bird, night_wolf.

This is marketing artwork from genuine product assets, not a recreated app
screen. It does not attribute all six badges to the featured trip. The earlier
composition using symbols cropped from trip details is retired and excluded
from the export package.

## Checks and handoff

- All 16 planned headlines fit the established typography without font reduction.
- Browser preview checked at 390 and 1440 px in both languages; no page overflow,
  all 16 images load, 8 RU / 8 EN visible cards, gallery also works without scripts.
- New artwork inspected at store-thumbnail size and in a grayscale/blur view.
- All 16 exported PNGs have the required dimensions, RGB/sRGB and no alpha.
- Six previous exports remain byte-identical. No conversion experiment performed.

The owner supplied the English Atlas screenshot and navigated the installed app
for direct USB captures of the Russian Atlas, both vehicle profiles, both public
feeds and both companion invitation sheets. No app build, simulator or invitation
was needed. The phone can be disconnected.

Both vehicle exports have the plate fully covered by an opaque mask before PNG
rasterization. Raw sources are private. The preview embeds only final PNGs and the
ZIP contains only those 16 PNGs plus its README; every embedded and archived image
was checked against the export hashes. Six previously approved exports remain
byte-identical.

The companion card shows the real invitation screen, with no fabricated accepted
participants. Its copy promises invitations and photos in one trip. Code confirms
that an accepted companion can view the private trip and add photos to its gallery;
it does not promise simultaneous GPS recording or joint editing.

The updated local preview includes all eight themes, language switching, store-size
view, downloads and text comments. Capture status, source provenance and export
hashes are synchronized. Next: owner review of the completed set, then check actual
App Store Connect state before applying the new screenshots.

Private screenshots, HTML compositions, SVG copies, crop provenance, archives
and browser evidence remain outside the public repository in the local review
package `2026-10-07-app-store`. No screenshots or app metadata were uploaded or
changed in App Store Connect during this round. Read the actual ASC state before
any later upload; this document makes no claim about the current review state.

Apple reference:
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
