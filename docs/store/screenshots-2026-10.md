# App Store screenshot series — October 2026

Updated 7 October 2026. Languages: Russian and English (U.S.). Approved visual
direction: A, light travel journal. Exports: 1320 × 2868, 8-bit RGB PNG, sRGB, no alpha.

The intended series has 8 cards per language. **4 cards per language are ready;
4 still need native captures.** Export count 8 means 4 RU + 4 EN, not the full series.

| Position | Feature | Russian headline | English headline | Status |
|---|---|---|---|---|
|01|Recorded route|Поездка прошла. Маршрут остался.|The drive ends. The route stays.|Previous export retained|
|02|Atlas and road fog|Ваши дороги. Ваш атлас.|Your roads. Your atlas.|Native capture pending|
|03|Companions|Одна поездка. Общие истории.|One trip. Shared stories.|Native capture pending|
|04|Photos and notes|Вспомните, как это было.|Remember how it felt.|Previous export retained|
|05|Trip statistics|Вся поездка. В деталях.|Every drive. Every detail.|Previous export retained|
|06|Garage|Каждая машина. Своя история.|Every car. Its own story.|Native capture pending|
|07|Public trips and feed|Делитесь поездками.|Share your journeys.|Native capture pending|
|08|Levels and achievements|Больше поездок. Выше уровень.|More journeys. New milestones.|New export, not uploaded|

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

## Checks and remaining work

- All 16 planned headlines fit the established typography without font reduction.
- Browser preview checked at 390 and 1440 px in both languages; no page overflow,
  all 8 images load, 4 visible cards per language, gallery also works without scripts.
- New artwork inspected at store-thumbnail size and in a grayscale/blur view.
- All 8 exported PNGs have the required dimensions, RGB/sRGB and no alpha.
- Six previous exports remain byte-identical. No conversion experiment performed.

Native capture remains for populated Atlas, companions, garage and feed in
both languages. Existing loading/empty captures are unsuitable. The owner
requested no builds/tests/simulator work during the two-hour call window;
none of these are required for the completed artwork work.

Private screenshots, HTML compositions, SVG copies, crop provenance, archives
and browser evidence remain outside the public repository in the local review
package `2026-10-07-app-store`. No screenshots or app metadata were uploaded or
changed in App Store Connect during this round. Read the actual ASC state before
any later upload; this document makes no claim about the current review state.

Apple reference:
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
