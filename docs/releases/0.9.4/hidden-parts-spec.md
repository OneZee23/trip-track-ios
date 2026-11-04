# Hidden parts of a trip and filming mode (0.9.4): implementation spec

Approved by the owner on 4 Nov 2026. This file is the source of truth for iOS, Android and the backend.
The reference semantics are `hidden_parts_reference.py`; `hidden-parts-vectors.json` holds the shared test vectors,
and every platform tests its resolution against them. Mockups and the reasoning behind each decision:
the owner's design pages of 4 Nov (rendered from `TripTrack-Reviews/2026-11-04-hidden-parts`, outside the repo).

Why: a camper couple who film their trips will not publish them because the route ends at their overnight spot, and they
will film the app and the revealed Atlas in their videos.

## 1. Decisions (owner, 4 Nov 2026)

1. Hidden parts never leave the phone, like the home zone: not in a publication, not in the Cloud Sync copy.
2. On one's own map hidden runs are a dotted ink line with lock pins where they meet the visible route.
3. A per-trip switch «Цифры для других»: «Вся поездка» (default) or «Без скрытого».
4. Photos taken on hidden parts stay on the phone only.
5. Viewers are never told that something is hidden.
6. Hiding the start and the end of every trip is off by default, but every user is asked explicitly, once.
7. Filming mode («Режим съёмки») ships in 0.9.4: by hand, and on its own while the screen is being recorded.

## 2. Model

`TripHiddenParts`, per trip, synced:

- `startMetres: Int?`: `nil` follows the global default; `0` hides nothing; `> 0` is the trip's own value.
- `endMetres: Int?`: the same for the end.
- `sections: [HiddenSection]`: `{ id: UUID, from: Date, to: Date }`, inclusive time ranges set by hand.
- `numbersVisibleOnly: Bool`: default `false` («Вся поездка»).

Local storage: one JSON text column on the trip.

- iOS: a new Core Data model version (v25) adding optional `TripEntity.hiddenPartsJSON: String`. Run
  `xcodegen generate` twice after adding the version (CLAUDE.md, «Ловушки»). Older versions stay untouched.
- Android: a Room column `hiddenPartsJson TEXT` with a migration and a migration test.
- `nil` means no hidden sections and both edges follow the global default.

Global settings (device-local, not synced):

- `privacy.edgeMetres: Int?`: `nil` = never answered, `0` = «Не скрывать», or 200 / 500 / 1000.
- `filming.manual: Bool` (default `false`), `filming.auto: Bool` (default `true`).

Effective edges of a trip: `startMetres ?? globalEdge ?? 0`, the same for the end.

## 3. Resolution (pure functions on both platforms; must reproduce the vectors)

Input: the trip's track points in order (after post-processing, gap fills included), its recording breaks, the
effective start and end metres, the sections, and the active home zone if any.

- `d_i` is the odometer prefix. Production uses the platform's `TripDistanceGate` prefix, which counts nothing across a
  recording break; the vectors use haversine on clean tracks, where both agree.
- A point is hidden if `d_i < start`, or `total − d_i < end`, or `from ≤ t_i ≤ to` for any section, or it is strictly
  inside the home zone (the existing `PrivacyZone` rule).
- Visible runs are maximal runs of visible points, split at recording breaks. A run with fewer than 2 points, or a run
  shorter than 100 m with hidden points on both sides, becomes hidden; repeat until nothing changes.
- `hiddenRanges`: for every maximal run of hidden points `[a..b]` (breaks ignored), `[t_a, t_b]`, inclusive.
- The preview is built from the visible runs only, each run simplified on its own. `previewBreaks` lists the indices
  in the uploaded preview where the runs after the first begin.
- A photo is hidden if its `capturedAt` falls inside a hidden range. Without `capturedAt` it is hidden if its EXIF
  coordinate is strictly inside the home zone or within 150 m of a hidden point. Otherwise it is visible.
- Public numbers with `numbersVisibleOnly`: distance is the sum over visible runs of `d_last − d_first`;
  `startDate`/`endDate` are the first and last visible point times; driving and stopped time, average and maximum speed,
  elevation gain and maximum altitude are computed over the visible runs with the existing functions. Without the
  switch the uploaded numbers are the whole trip's, as the home zone does today.
- Everything hidden: no track points, `previewPolyline = nil`. With «Без скрытого» the numbers are zero and viewers see
  the title and «Маршрут скрыт автором».

## 4. Upload: the trip sync payload is the only boundary (as for the home zone)

For every upload, public or Cloud Sync; drafts never upload:

- `trackPoints`: visible points only.
- `previewPolyline`: the visible runs; new optional key `previewBreaks: [Int]` (`[]` when there are none).
- Photos: a hidden photo is not uploaded. If it already has a server copy, queue its deletion (the existing photo delete
  path). When it becomes visible again, queue its upload.
- Photo EXIF coordinates and checkpoint coordinates inside a hidden range are `nil` (the 0.8.3 checkpoint rule);
  the checkpoint's name, time and distances still go.
- Numbers and dates as in §3.
- New optional key `hiddenParts` (the settings object above; absent from old clients).
- New optional key `hiddenRanges: [{from, to}]`, ISO-8601 (`[]` = none).
- `recordingBreaks` unchanged.

Re-upload triggers: a trip's hidden parts change; the global edge changes; the home zone changes (existing). Re-upload
every trip that has a server copy, public AND Cloud-synced private (never drafts), in background batches. This also
closes today's hole: private cloud copies stayed untrimmed after a zone change, and companions can see private trips.

## 5. Pull and conflicts: the phone with the full track wins

On a phone that holds the full track of a trip with an effective mask (hidden parts, default edges or the home zone):

- never replace local track points, preview, numbers or dates with the server's; the server holds the masked copy;
- the conflict path (`/trips/detail` with track points) must not replace local points either. Today it does on both
  platforms and wipes the points inside the home zone; fix it;
- `hiddenParts` from the server is applied only when the local trip has no pending edits (the rule of other trip
  fields).

A phone without the full track (a second phone, a reinstall) shows the trip as the server has it, so nothing is
dotted. The editor still shows the settings and says «Скрытые куски есть только на телефоне, где записана поездка».

## 6. Backend (a branch; the owner deploys it before the apps)

- Trip columns, on the entity and in a migration with `ADD COLUMN IF NOT EXISTS` (production runs `DB_SYNC=true`):
  `hidden_parts jsonb null`, `hidden_ranges jsonb null`, `preview_breaks jsonb null`.
- DTO: `hiddenParts?`, `hiddenRanges?` (array of `{from, to}` ISO strings, at most 1000, invalid entries dropped
  silently), `previewBreaks?` (integers, at most 4096). Missing = keep, `[]` = clear (the `recordingBreaks` pattern).
  Never fail the whole upsert on these keys.
- Old-client guard: when the payload has no `hiddenRanges` key and the stored trip has non-empty `hidden_ranges`:
  - drop incoming track points inside any range;
  - keep the stored `preview_polyline` and `preview_breaks`, ignore the incoming preview;
  - null incoming photo EXIF coordinates and checkpoint coordinates whose time falls inside a range;
  - if the stored `hidden_parts.numbersVisibleOnly` is true, keep the stored numbers and dates.
- Defense in depth: whenever the effective `hidden_ranges` is non-empty, points inside it are dropped before insert.
- Owner endpoints (`/sync/pull`, `/trips/detail`) return `hiddenParts`, `hiddenRanges`, `previewBreaks`.
- Non-owner surfaces: the feed-item serializer and `toPublicTrip` add `previewBreaks`. The `/social/trip` replay track
  adds `breaks: [ISO]`: the union of recording breaks and, for each hidden range, the time of the first stored point
  after `range.to`, sorted and unique. The forced first and last replay points are then visible points.
- The `/u/` Atlas routes split at `previewBreaks` (`atlas-geometry`).
- Tests: a new client (stores ranges, drops points inside), an old client (each guarded field), the owner echo,
  `previewBreaks` in feed and public DTOs, replay `breaks`, the migration twice.

## 7. Clients: interface

### The editor «Скрыть от других»

Entry points: the own trip's «…» menu; a row «Скрыто от других» in the trip edit sheet; a row in the publish sheet;
a card «Скрыто от других» on the own trip page when anything is hidden.

A full-screen map of the trip (style A) under a sheet:

- «Скрыть от других» and «Готово». Changes apply only on «Готово»; closing discards them without a question.
- A summary line: «Начало 500 м · конец 1 км · участков в середине нет».
- The trip bar: the whole trip as a horizontal bar in speed colours, hidden ranges hatched, drag handles on middle
  sections, start and end times under it.
- «Начало»: chips Нет · 200 м · 500 м · 1 км · 2 км. When the trip follows the global default the matching chip is
  marked and a caption says «по умолчанию». «Конец»: the same.
- Middle sections listed with their time range and distance, each with a delete button. «+ Скрыть участок в середине»
  switches the map to «Нажмите на маршрут, где начинается участок», then «…где заканчивается»; taps snap to the
  nearest track point (`TripRouteLocator`). The handles on the bar adjust a section afterwards.
- «Цифры для других»: a segmented control «Вся поездка» / «Без скрытого», with the caption «Другие увидят 184 км и
  3 ч 31 мин».
- A card «Останется только на этом телефоне»: the hidden pieces and N photos from them.
- A toggle «Как увидят другие» switches the map to the public version.
- When the title was generated (not typed) and the start or the end is hidden: «Название «Хака → Бардена-Реаль»
  называет место финиша. Изменить название».
- When the trip has a server copy and is public: «Кто уже видел поездку, мог запомнить её целиком.»

### Style A on one's own maps

Hidden runs: round ink dots (the text colour at 55 %, dash pattern 0.1 / 7.2 pt, about the route's width) over a white
casing. Lock pins where a visible run meets a hidden one: a 21 pt white disc with an ink lock glyph (Android draws its
own glyph vector, never an SF Symbol outline). Distinct from the grey dashed road-gap fill. Applies to the own trip's
hero and full-screen maps, the own journey map and own cards; never to other people's trips.

### Other people's trips

Lines split at `previewBreaks` (cards, the profile map and its fog, journeys) and at the replay `breaks` (the trip
map). The replay crosses a break by fading out and in, never by sliding along a straight line. Start and finish markers
sit on the first and last points, which are visible ones. Old servers and old apps degrade to a straight chord.

### Publish sheet

Adds a map «Так её увидят в ленте и в профиле» (the public version) and a row «Скрыто: …» that opens the editor.
When neither edge is hidden and the trip starts or ends within 300 m of the home, of a place, or of where the previous
trip ended (an overnight stop), a hint «Скрыть конец? Здесь вы ночевали» with a one-tap «Скрыть 500 м».

### The question, once

A sheet, and the same as an onboarding page for new installs right after the background-location page. A pixel
illustration in the style of the other onboarding pictures; «Скрывать начало и конец поездок?»; «Дом и место ночёвки
не попадут ни в ленту, ни в облачную копию. Сами вы увидите поездку целиком.»; options «Не скрывать», «200 м · двор,
парковка», «500 м · квартал, стоянка», «1 км · надёжнее для кемпинга». Nothing is preselected and «Сохранить» stays
disabled until a choice is made. Footnote «Поменять можно в Настройках → Конфиденциальность».

Shown once after the update, when the app is idle (not while recording, not over another sheet). Dismissed by a swipe,
it is asked again at the first publication. If the choice would hide the whole route of short published trips, the
sheet says how many before saving.

### Settings → Конфиденциальность

Section «Места, которые не видны другим»: «Дом» (the existing screen) and «Начало и конец поездок» (a picker with the
same options). Section «Режим съёмки»: a toggle «Режим съёмки» («Скрытое не видно и на ваших экранах») and a toggle
«Включать при записи экрана» («Сам включится и выключится»; on Android before 15 it is disabled with «На этой версии
Android запись экрана не определить»). A footnote says what the mode hides and that the recording screen keeps the
location dot.

### Filming mode

Active = `manual || (auto && the screen is being recorded)`. iOS: `UIScreen.main.isCaptured` and
`capturedDidChangeNotification` (mirroring counts too). Android 15+: `WindowManager.addScreenRecordingCallback` with
the `DETECT_SCREEN_RECORDING` permission; earlier versions are manual only. When the recording stops, a mode that turned
itself on turns itself off; a manual one stays on.

While active, one's own screens show:

- trips without hidden runs (maps, cards, replay, posters);
- the Atlas from a separate revealed layer built from the public previews, and the Atlas numbers from that layer;
- no home marker and no home-zone circle;
- no places whose point lies inside a hidden run of any trip or inside the home zone (map pins and list rows);
- no «where am I» dot on the Atlas, trip maps and Places; the recording screen keeps it;
- no photos from hidden parts in galleries or on maps.

There is no on-screen indicator, it would end up in the video. The second revealed layer is built once in the
background, with the hint «Готовим режим съёмки» on the Atlas, and is maintained alongside the main layer after that.

## 8. Existing holes fixed in this release (both platforms unless noted)

1. The conflict path wipes local points inside the home zone (§5).
2. The trip poster ignores the home zone; posters draw the public version.
3. Previews draw chords across holes; fixed by `previewBreaks`.
4. Private cloud copies stay untrimmed after a zone change; fixed by the re-upload in §4.
5. iOS: the photo upload falls back to the original bytes (GPS EXIF included) when re-encoding fails. Never upload the
   original bytes; retry later.
6. The replay slides across recording pauses: maps and replay split at recording breaks (own trips) and at `breaks`
   (other people's).

## 9. Strings

All new strings in the 13 languages: iOS `AppStrings` with ru/en inline and `Translations+XX`; Android regenerates its
resources from the iOS strings (`tools/strings`). Russian copy as quoted here; short, no exclamation marks.

## 10. Tests

- The vectors on each platform; on the backend where the guard depends on them.
- The upload discipline: everything leaves through the mask (extend `PrivacyZoneDisciplineTests` and its Android twin).
- Pull and conflict guards; photo rules; the numbers switch; `previewBreaks` rendering; replay breaks; the question
  shown once; the filming-mode state machine.
- Screenshot tests: the editor, the publish sheet, the question, the settings section, light and dark.

## 11. Not in this release

A custom edge distance; one switch that hides a trip's whole map; owner pages on the website; journey posters.

## 12. String keys (shared by both platforms)

iOS adds these as `AppStrings` functions (ru and en inline, the other eleven in `Translations+XX`); Android gets them
from `tools/strings`, and until then may add the same keys by hand. `{…}` are placeholders filled after `tr()`.
Android-only copy uses the `android_` prefix.

| key | ru | en |
|---|---|---|
| hiddenEditorTitle | Скрыть от других | Hide from others |
| hiddenFromOthers | Скрыто от других | Hidden from others |
| hiddenStartLabel | Начало | Start |
| hiddenEndLabel | Конец | End |
| hiddenNone | Нет | None |
| hiddenByDefault | по умолчанию | default |
| hiddenNothing | Ничего не скрыто | Nothing is hidden |
| hiddenSummaryStart | начало {value} | start {value} |
| hiddenSummaryEnd | конец {value} | end {value} |
| hiddenSummaryMiddle | в середине: {count} | in the middle: {count} |
| hiddenAddSection | Скрыть участок в середине | Hide a section in the middle |
| hiddenPickStart | Нажмите на маршрут, где начинается участок | Tap the route where the section begins |
| hiddenPickEnd | Теперь там, где он заканчивается | Now where it ends |
| hiddenNumbersTitle | Цифры для других | Numbers for others |
| hiddenNumbersWhole | Вся поездка | Whole trip |
| hiddenNumbersVisible | Без скрытого | Without hidden parts |
| hiddenNumbersCaption | Другие увидят {distance} и {duration} | Others will see {distance} and {duration} |
| hiddenStaysTitle | Останется только на этом телефоне | Stays on this phone only |
| hiddenStaysBody | Скрытые куски маршрута и фото с них не уйдут ни в ленту, ни в облачную копию. | Hidden pieces of the route and photos from them go neither to the feed nor to the cloud copy. |
| hiddenPreviewToggle | Как увидят другие | As others will see it |
| hiddenTitleNamesStart | Название «{title}» называет место старта. | The title “{title}” names where the trip starts. |
| hiddenTitleNamesFinish | Название «{title}» называет место финиша. | The title “{title}” names where the trip ends. |
| hiddenRename | Изменить название | Rename |
| hiddenAlreadySeen | Кто уже видел поездку, мог запомнить её целиком. | Anyone who has already seen the trip may remember it whole. |
| hiddenOnlyOnRecordingPhone | Скрытые куски есть только на телефоне, где записана поездка. | Hidden pieces exist only on the phone that recorded the trip. |
| hiddenPill | Другим не видно {distance} | Hidden from others: {distance} |
| routeHiddenByAuthor | Маршрут скрыт автором | The route is hidden by its author |
| publishPreviewCaption | Так её увидят в ленте и в профиле | This is how it will look in the feed and on your profile |
| publishHiddenRow | Скрыто: {summary} | Hidden: {summary} |
| publishHintOvernight | Скрыть конец? Здесь вы ночевали | Hide the end? You stayed overnight here |
| publishHintHome | Скрыть начало? Здесь ваш дом | Hide the start? Your home is here |
| publishHintAction | Скрыть {value} | Hide {value} |
| edgeQuestionTitle | Скрывать начало и конец поездок? | Hide the start and end of trips? |
| edgeQuestionBody | Дом и место ночёвки не попадут ни в ленту, ни в облачную копию. Сами вы увидите поездку целиком. | Your home and where you sleep won't reach the feed or the cloud copy. You will still see the whole trip. |
| edgeOptionNone | Не скрывать | Don't hide |
| edgeOption200Note | двор, парковка | yard, parking |
| edgeOption500Note | квартал, стоянка | block, campsite |
| edgeOption1000Note | надёжнее для кемпинга | safer for camping |
| edgeQuestionFootnote | Поменять можно в Настройках → Конфиденциальность | You can change this in Settings → Privacy |
| edgeQuestionWholeTrips | Целиком скроется маршрут у {count} {trips} | The whole route of {count} {trips} will be hidden |
| privacyPlacesSection | Места, которые не видны другим | Places others don't see |
| privacyEdgesRow | Начало и конец поездок | Start and end of trips |
| privacyEdgesFootnote | Скрывается у всех поездок, кроме тех, где вы задали своё. Ни в ленту, ни в облако не уходит. | Hidden on every trip except those where you set your own. Goes neither to the feed nor to the cloud. |
| filmingSection | Режим съёмки | Filming mode |
| filmingToggleSubtitle | Скрытое не видно и на ваших экранах | Hidden parts disappear from your own screens too |
| filmingAutoToggle | Включать при записи экрана | Turn on while the screen is recorded |
| filmingAutoSubtitle | Сам включится и выключится | Turns itself on and off |
| filmingFootnote | В режиме съёмки «Атлас», карты поездок и «Места» показывают ваши поездки без скрытых кусков, без дома и без синей точки, где вы сейчас. Экран записи поездки точку оставляет. | In filming mode the Atlas, trip maps and Places show your trips without hidden pieces, without your home and without the blue dot of where you are. The recording screen keeps the dot. |
| filmingPreparing | Готовим режим съёмки | Preparing filming mode |
| android_filming_auto_unavailable | На этой версии Android запись экрана не определить | This Android version can't detect screen recording |

Existing strings to reuse: `done`, `save`, `cancel`, `delete`, `photosCount`, `nounTrips`, the distance and duration
formatters (`Measure`), the home screen strings.
