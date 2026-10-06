# App Store Review Notes — TripTrack

Paste the relevant section into App Store Connect → **App Review Information** → **Notes** when submitting the build. Use the current-submission section; the older sections stay as a record of what was said for earlier builds.

---

## v0.8.4 (73) — recording and map fixes (current submission)

**Released October 6, 2026 at 08:27:37 UTC (11:27:37 MSK).**
After the owner's instruction, the approved version was manually released.
App Store Connect readback confirmed **Ready for Distribution**, selected
build **0.8.4 (73)**. This is a full release, not a phased release; availability
is configured for 175 countries and regions, and existing ratings were kept
(`KEEP`). The previous public version was 0.8.1. At 08:29 UTC, public Apple
Lookup still returned 0.8.1 for US and DE; the RU request failed with URLError.
Availability of 0.8.4 across public storefronts is not yet confirmed.
Today's Live Activity and history-counter fixes
are not included in build 73; no new build or test run was performed for release.

Earlier on October 6, build 73 was confirmed as Pending Developer Release.

**Prepared October 5, 2026.** Build 73 combines the changes in
[candidate 72](0.8.4/candidate-72.md) with the map-dash rendering correction.
The Release archive passed verification and uploaded at 18:57 MSK.
**Submitted October 5, 2026 at 19:07 MSK: Waiting for Review**, submission
`9f604caf-1bd0-49a0-ac26-1e5f1d5eb2ab`. Build 73 replaced build 70;
manual release was selected, with no public release at submission time.
The six previously approved PRO/tip items do not require resubmission;
the new submission contains the app version only. Exact Notes and selected
build were read back after submission. The build 70 history below remains unchanged.
See [candidate 73](0.8.4/candidate-73.md) for the test scope and remaining
device checks. Preparing this packet does not mark those checks as passed.

### Short version — paste into App Store Connect

```
TripTrack 0.8.4 (73) includes PRO and recording/map improvements. Recording,
the atlas, places, journeys, photos and statistics stay free. No previously
free feature became paid. PRO and tips were approved with build 70.

ANSWERING 5.1.1(iv), BUILD 69
Each pre-permission screen has one neutral Continue button leading to the
iOS permission request, with no Not now, skip or swipe bypass. Users can
deny access in the system dialog and continue onboarding; denial is
respected without repeated prompts. Requests run sequentially: location,
background location when available, Motion & Fitness, then notifications.
TripTrack does not request microphone access or record audio. Car-stereo
detection observes audio-route changes only. Test on a fresh installation,
including denying access in the system dialogs.

RECORDING AND MAPS
GPS continuity checks reject implausible jumps before saving points, and
the filter resets after a long signal gap. Manual pause boundaries are
retained for distance calculations and sync. This cannot reconstruct a
verified route where GPS measurements are missing or unreliable.
Trip details have a stable initial layout and reuse the map on full-screen
expansion. Gray dashed sections retain a consistent width while zooming.
Existing trips are not automatically rewritten.

PRO adds eight profile backgrounds, six avatar frames, eight vehicle-card
backgrounds and route-line styles, plus manually adding past trips along
roads, with up to three stops. Manual trips count toward distance, the
Atlas and the vehicle odometer, but award no experience, levels, badges or
finds. Cards are labelled "Added by hand". The PRO mark can be hidden in
Privacy settings.

SUBSCRIPTIONS
Germany base prices: EUR 24.99/year or EUR 5.99/month. The paywall shows
localized StoreKit prices. Only the yearly plan offers a 7-day free trial,
and only when Apple reports eligibility; monthly has no trial. Both plans
provide the same access in one subscription group. Family Sharing is off.
Price, duration, trial renewal terms, Restore Purchases, Terms of Use and
Privacy Policy are on the paywall.

HOW TO FIND AND TEST
1. Me/Profile -> TripTrack PRO opens the paywall. Cosmetic galleries offer
   previews and a PRO purchase button.
2. A successful sandbox purchase unlocks PRO. Restore Purchases with the
   SAME purchasing Apple ID restores an active subscription without another
   charge. An account without a subscription does not receive PRO.
3. Profile -> active PRO row opens Apple's Manage Subscription sheet.
   Cancellation preserves access until the current period ends.
4. Manual trip: tap + beside History on Me/Profile, or the add-trip action
   for the selected day in its history calendar.
5. Tips: Me/Profile -> gear (Settings) -> author's card at the bottom ->
   support row. Three repeatable Consumable tips have Germany base prices
   EUR 0.99 / 2.99 / 9.99. They unlock nothing and never grant PRO.

StoreKit 2 entitlements determine access, including offline, and refresh
on foreground return. Verified signed transactions are sent separately
to our server for public cosmetics. When PRO expires, free defaults are
displayed and saved paid choices return with a renewed subscription.

On the RUS storefront, purchase entry points are hidden. An already owned
subscription continues to work regardless of storefront. No special app
account is required to test; Sign in with Apple is available when needed.

ANSWERING THE 2.5.4 REJECTION OF 0.8.2 (65)
The unused bluetooth-central background mode was removed. The only remaining
background mode is location, needed to record drives in the background.
Car-stereo detection uses AVAudioSession audio-route changes, not BLE
background scans. Core Bluetooth is used only in the foreground device
selection sheet; its state-restoration identifier and willRestoreState
handler were also removed.
```

This block is 3,875 characters and retains the responses to 5.1.1(iv) and
2.5.4. The product approvals belong to build 70's completed submission;
they are not an approval of the changes in build 73.

---

## v0.8.4 (70) — PRO and permission-flow correction (previous submission)

**Live check, October 5, 2026:** Review Completed. Build 70, the PRO group,
both subscriptions and all three tips are Approved. The app version is
Pending Developer Release; manual release has not been triggered. The two
messages in this submission are the October 2 rejection and our reply below,
not a new rejection.

**This is the first TripTrack build that sells anything.** Everything that
existed before stays free; the subscription adds four cosmetic unlocks and one
feature, and there is a separate tip that unlocks nothing at all.

Build 70 was uploaded on October 2, 2026 at 17:00 MSK after 17 unit tests
and 3 UI tests passed. These notes were saved and the reply below was sent
with three permission-screen screenshots at 17:14 MSK. Resubmission was
confirmed at 17:15 MSK: all seven items are Waiting for Review, with manual
release after approval. Submission ID: `f0807f5f-e336-4c08-9293-6ff4c1b9c4ff`.

### Short version — paste into App Store Connect

```
TripTrack 0.8.4 (70) introduces PRO. Recording, the map atlas, places, journeys,
photos and statistics stay free. No previously free feature became paid.

ANSWERING 5.1.1(iv), BUILD 69
Each pre-permission screen now has one neutral Continue button leading to
the iOS permission request, with no Not now, skip or swipe bypass. Users
can deny access in the system dialog and continue onboarding; denial is
respected without repeated prompts. Requests run sequentially: location,
background location when available, Motion & Fitness, then notifications.
TripTrack does not request microphone access or record audio. Car-stereo
detection observes audio-route changes only. To check this flow, start a
fresh installation and continue through onboarding, including denying access.

PRO adds eight profile backgrounds, six avatar frames, eight vehicle-card
backgrounds and route-line styles, plus manually adding a past trip along
real roads. Manual trips support start/end address search or map selection
and up to three stops. They count toward distance, the Atlas and the vehicle
odometer, but award no experience, levels, badges or finds. Their cards are
labelled "Added by hand". The optional PRO profile mark can be hidden in
Privacy settings.

SUBSCRIPTIONS. Germany base prices: EUR 24.99/year or EUR 5.99/month; the
paywall displays localized StoreKit prices. Only the yearly plan has a
7-day free trial, shown only when Apple reports eligibility. Both plans
offer the same access and belong to one subscription group. Family Sharing
is disabled. The paywall states price, duration and trial renewal terms,
with Restore Purchases, Terms of Use and Privacy Policy links.

HOW TO FIND AND TEST
1. Me/Profile tab -> TripTrack PRO opens the paywall. Cosmetic galleries
   offer previews and a PRO purchase button. The yearly plan is initially selected; an ineligible account is
   not promised a free trial.
2. After a successful sandbox purchase, PRO unlocks. On a clean installation
   or second device with the SAME purchasing Apple ID, Restore Purchases
   restores access without another charge. An account without a subscription
   does not receive PRO.
3. Profile -> active PRO row opens Apple's Manage Subscription sheet.
   Cancellation preserves access until the paid period ends.
4. Manual trip: tap + beside History on the Me tab, or an empty day in its
   history calendar.
5. Tips: Me/Profile -> gear (Settings) -> scroll to the author's card at the
   bottom -> the support row. Three repeatable Consumable tips have Germany
   base prices EUR 0.99 / 2.99 / 9.99. They unlock nothing and never grant PRO;
   the screen explains this before purchase.

StoreKit 2 entitlements determine access on the device, including offline.
They are refreshed when the app returns to the foreground. Verified signed
transactions are sent separately to our server for public profile cosmetics.
When PRO ends, saved cosmetic choices remain; display falls back to free
defaults and restores those choices if the user subscribes again.

On the RUS storefront, purchase entry points are hidden. An already owned
subscription continues to work regardless of storefront. No special app
account is required to test; Sign in with Apple is available when needed.

ANSWERING THE 2.5.4 REJECTION OF 0.8.2 (65)
The review correctly identified an unused bluetooth-central background mode.
It has been removed. The only remaining background mode is location, needed
to keep recording drives while the app is in the background. Car-stereo
detection uses AVAudioSession audio-route changes, not BLE background scans.
Core Bluetooth is used only in the foreground device-selection sheet; its
state-restoration identifier and willRestoreState handler were also removed.
```

This single paste block includes the responses to both rejections and
must remain within App Store Connect's 4,000-character limit. Preparing these
notes does not mark device acceptance or App Review as completed.

### Reply to the 5.1.1(iv) rejection of 0.8.4 (69) — sent for build 70

```
Thank you for identifying the pre-permission flow issue in build 69.

Build 70 removes the "Not now" and skip actions from the pre-permission
screens and prevents swiping past them. Each screen has one neutral
"Continue" button that proceeds to the corresponding iOS permission request.
Users remain free to deny access in the system dialog and continue onboarding.
The app respects that decision and does not repeatedly prompt after denial.

Location, background location when available, Motion & Fitness, and
notification requests are handled sequentially, without overlapping prompts.

Regarding Audio: TripTrack does not request microphone access or record
audio. Car-stereo detection observes AVAudioSession audio-route changes;
the separate Motion & Fitness permission is used for automatic trip detection.

Please review version 0.8.4 (70). On a fresh installation, proceed through
onboarding with Continue; each unresolved permission is requested by iOS.
Choosing not to allow access in the system dialog still allows onboarding
to continue. The PRO subscription and tip purchase flows are unchanged.
```

### How to test the subscription in sandbox

1. Use TestFlight or a sandbox installation of `com.onezee.TripTrack` on
   the test device. A Debug Run using `Config/TripTrack.storekit` tests the
   local catalog, not the products configured in App Store Connect. Configure
   the tester account for a storefront where the app exposes purchases.
2. In the app: **Я (Profile) → the PRO row** opens the paywall. Cosmetic
   galleries offer previews; their PRO purchase button opens that paywall.
3. The yearly plan is selected by default. If the sandbox account is eligible
   it offers seven days free, followed by the localized yearly price
   (EUR 24.99 on the German storefront). Otherwise the trial line is absent.
4. Tap the purchase button and confirm in the system sheet. Test renewals
   use an accelerated schedule that depends on the test environment and
   sandbox account settings. The paywall closes and the cosmetics
   and the hand-entered-trip entry point unlock immediately.
5. **Restore:** delete and reinstall, or use a second device, then open the
   paywall and tap "Restore Purchases" — PRO returns with no new charge. If
   the Apple ID has no subscription, the app says so instead of failing
   silently.
6. **Cancel:** Profile → the active-subscription row → "Manage Subscription"
   opens Apple's own sheet. Cancelling there does not revoke access until the
   paid period ends.
7. **Tips:** Profile → Settings (gear) → author's card at the bottom →
   support row. Buy any tier and confirm that nothing
   unlocks — that is the intended behaviour.

### Where to find the hand-entered trip

Three entry points, all of them behind PRO: the **+** in the header of
"History" on the Я tab, a tap on an **empty day** in the profile's history
calendar, and the second button on the first-trip welcome card. On the RUS
storefront none of the three is shown at all.

### Answering the 2.5.4 rejection of 0.8.2

Version 0.8.2 (65) was rejected on 30 September 2026 under guideline 2.5.4:
the app declared `bluetooth-central` in `UIBackgroundModes` while no Bluetooth
Low Energy functionality could be found.

**The finding was correct and the capability has been removed.** A car stereo
is a classic-Bluetooth audio sink (A2DP/HFP); BLE scanning never sees one. The
app detects the car through the audio route
(`AVAudioSession.routeChangeNotification`), which needs no background mode.
The only remaining background mode is `location`, which is the app's core
function: a drive keeps recording while the phone is in a pocket and the app
is in the background.

Core Bluetooth is still used, but only in the foreground: the "choose your car
stereo" sheet lists nearby BLE devices. The state-restoration identifier and
the `willRestoreState` handler were removed along with the background mode.

### What is NOT in this build

- **No new permissions, no new privacy-manifest entries, no server
  migrations.** The subscription collects nothing new; the purchase receipt
  travels the same path introduced in 0.8.0.

---

## v0.8.3 — electric cars and hybrids (previous submission)

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.8.3 started with a letter from a user in Germany: the app showed
fuel consumption in litres, and he drives a plug-in hybrid.

NO IN-APP PURCHASES IN THIS BUILD. There is no subscription, no tip jar and
no paywall anywhere in the app, and nothing is submitted under In-App
Purchase for this version. The app is free and complete as shipped.

ENGINE TYPE FOR A CAR. A car now has a powertrain: petrol or diesel,
electric, or both at once. An electric car is measured in kilowatt-hours and
a price per kWh instead of litres; a plug-in hybrid is measured in both. The
question is asked in plain language ("What does your car run on?") rather
than with three technical terms.

AN HONEST BREAKDOWN PER TRIP. Each trip shows how far it went on the battery,
how far on fuel, and what that cost. The electric range is spent per calendar
day: the first kilometres of each day come off the night's charge. Only the
MODE of a trip is stored — everything else is computed at display time, so
correcting the consumption or the range recalculates the whole history at
once, with no migration and no stale numbers. The user can override the mode
on any trip: Auto, Electric, Fuel.

A CHECKPOINT INSIDE THE PRIVATE HOME ZONE NO LONGER CARRIES ITS COORDINATES.
In 0.8.2 the track, the route preview and photo EXIF were already trimmed
inside the user's private zone; a checkpoint placed there still travelled as
an exact point. It now travels without latitude and longitude — the name, the
time and the distance from the start are kept. This release sends strictly
LESS data to our server than the previous one.

RECORDING STARTS UNDER A BAD SKY. The idle accuracy gate was stricter than
the recording gate, which blocked the start slider in an underground car
park, in a courtyard or between tower blocks. The two gates are now the same.
Distance keeps its own, stricter gate and does not change by a metre.

FIXED. Edits to a car (consumption, fuel price, currency, name, visibility)
could be rolled back by an incoming sync from a second device.

HOW TO TEST
1. Open the "Me" tab, then the garage card, then any car, then edit it.
   The "Engine" row asks what the car runs on and offers three answers with
   an explanation under each.
2. Choose "Electricity and fuel" — fields for kWh per 100 km, the price per
   kWh and the battery range appear next to the existing fuel fields.
3. Open any trip of that car: the tiles show electricity, fuel and cost, and
   a row underneath lets you switch the trip between Auto, Electric and Fuel.
4. Record a trip in the Simulator with Features > Location > Freeway Drive
   (not City Run: anything that never exceeds 15 km/h is discarded as a
   walking misfire).

SIGN-IN. Authentication is Sign in with Apple only, and no special account is
needed: the reviewer's own Apple ID works. Everything above works fully
signed out and with Cloud Sync off, which is the default.

No new permissions are requested. Location usage is unchanged from 0.7.0.
```

### Если спросят про «Beta» на двух экранах

Ответ тот же, что и в 0.8.1 и 0.8.2 — секция ниже, она не устарела.

---

## v0.8.2 — отдельной секции нет

Заметки для ревьюера при сабмите 0.8.2 не обновлялись: версия ушла на ревью с
текстом 0.8.1. Записано, чтобы это не выглядело потерянным файлом. Ничего в
0.8.2 не требовало объяснений сверх того, что уже сказано ниже (значок «Бета»
на двух вкладках, отсутствие покупок).

---

## v0.8.1 — a track without gaps, drafts, a new look

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.8.1 is a quality release about recording honestly: a weak GPS
signal no longer drops part of a route, and automatic tracking no longer
decides on the user's behalf.

NO IN-APP PURCHASES IN THIS BUILD. There is no subscription, no tip jar and
no paywall anywhere in the app, and nothing is submitted under In-App
Purchase for this version. The app is free and complete as shipped.

A TRACK WITHOUT GAPS. An evening city, a tunnel or an underground car park
used to produce no fixes at all, and the route broke into separate pieces.
The recording gate now accepts a rougher fix (200 m instead of 65 m) so the
shape of the road is still drawn, while distance keeps its old 65 m gate and
does not change by a metre. A gap that still remains is closed on the phone:
first with a straight line, then, when the app is in the foreground and
online, replaced by a real road route from MapKit and drawn as a grey dashed
line — explicitly a best guess, not a driven path.

DRAFTS IN "REMINDERS" MODE. Automatic tracking in this mode now saves the
trip as a DRAFT and asks "Is this yours?" — on the trip, in the summary, in
the "Me" tab, and in a local notification if the question went unanswered. An
unconfirmed draft is excluded from the Atlas, from statistics and from sync:
it never leaves the phone until the user says it is theirs.

A NEW LOOK, MARKED BETA. The Atlas and Places tabs are redrawn (light paper
map, period filters, places as pins, search and sorting). Both carry a visible
"Beta" chip that opens a short card explaining that these screens are still
being reworked. This is deliberate and not a placeholder left in by mistake.

FIXED. Opening another user's trip from the feed could freeze the app in an
infinite layout loop; profile level could reset to 1 during sync.

HOW TO TEST
1. Record a trip. In the Simulator use Features > Location > Freeway Drive
   (not City Run: anything that never exceeds 15 km/h is discarded as a
   walking misfire).
2. Open the "Feed" tab and tap any trip by another user, go back, and open it
   again — the app stays responsive.
3. Open your own trip, open the journey or place linked from it, then come
   back — the map is still there.
4. Open the fourth tab, "Atlas", tap the "Beta" chip — a card explains that
   the screen is still being reworked. The same chip is on "Places".
5. On the Atlas, tap a region in the sheet — the camera moves to that region.

SIGN-IN. Authentication is Sign in with Apple only, and no special account is
needed: the reviewer's own Apple ID works. Everything above works fully
signed out and with Cloud Sync off, which is the default.

No new permissions are requested. Location usage is unchanged from 0.7.0.
```

### Если спросят про «Beta» на двух экранах

```
The Atlas and Places tabs were redesigned in this release and will be
redesigned once more. Rather than hold the release — which also carries a
freeze fix and a data-loss fix — we ship the current design and label it. The
chip is a normal control: tapping it opens a short card saying the screen is
still being worked on and offering a way to write to us. Nothing behind the
chip is unfinished or non-functional; both tabs work fully.
```

### Если спросят про достроенный участок трека

```
When GPS produces no usable fix for a stretch (a tunnel, an underground car
park), the recorded track has a gap. The app closes it on the device: first
with a straight line, then, if the app is in the foreground and online, it
asks MapKit for a driving route between the two known points and uses that
instead. The filled stretch is drawn as a grey dashed line and carries no
speed, so it is visibly distinct from a recorded one. It never counts towards
distance: only fixes accurate to 65 m or better do. No external service other
than Apple's own MapKit directions is contacted, and nothing about the user
is sent — only the two coordinates bounding the gap.
```

---

## v0.8.0 — the Atlas on Metal, place suggestions, export (previous submission)

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.8.0 is a quality release: the Atlas is redrawn from scratch, the
Places tab starts being useful on the first trip, and a user can take their
own trip out of the app as a file.

NO IN-APP PURCHASES IN THIS BUILD. There is no subscription, no tip jar and
no paywall anywhere in the app, and nothing is submitted under In-App
Purchase for this version. The app is free and complete as shipped.

THE ATLAS. The fourth tab shows the world under fog, with only the roads the
user has actually driven open in it. In this release the fog is rendered on
the GPU, rebuilt every frame from the opened path, so pinching, zooming and
panning stay smooth at any scale — the previous version redrew a bitmap and
showed seams and reload flashes. Everything drawn there comes from trips
recorded on this phone; nothing is downloaded or uploaded to draw it.

PLACES. The fifth tab now suggests spots the user seems to visit, inferred
from where their own trips start and end. A suggestion is a name from the
reverse-geocoding cache and a pin — no coordinate is shown as a number — and
tapping "Save" turns it into a place. Nothing is created automatically, and
suggestions are computed on the phone from data it already holds.

EXPORT. A user's own trip can be exported as GPX or CSV from its "..." menu
and shared through the standard share sheet. Someone else's trip has no such
option.

STABILITY. The first launch after updating no longer freezes while the app
reconciles places and territory: that work moved off the main thread.

HOW TO TEST
1. Open the fourth tab, "Atlas". On a fresh install it is solid fog, and that
   is correct: nothing has been driven yet.
2. Record a trip. In the Simulator use Features > Location > Freeway Drive
   (not City Run: anything that never exceeds 15 km/h is discarded as a
   walking misfire). Pinch and pan the Atlas afterwards — the fog follows the
   map without stutter, and the driven corridor is open in it.
3. Open any recorded trip, tap the expand button on its map, then close it —
   the map returns to its place in the same frame it left.
4. On a recorded trip, "..." > "Export GPX" — the standard share sheet opens
   with a .gpx file.

SIGN-IN. Authentication is Sign in with Apple only, and no special account is
needed: the reviewer's own Apple ID works. The Atlas, Places and export all
work fully signed out and with Cloud Sync off, which is the default.

No new permissions are requested. Location usage is unchanged from 0.7.0.
```

### Если спросят, почему в коде есть подписка, а товаров нет

```
The subscription code ships in the binary but is disabled by a single
build-time switch, and no purchase UI can be reached from any screen: there
is no paywall, no locked row and no tip jar in this version. We finished the
feature and decided to hold monetisation for a later release rather than cut
the code out and re-add it. Nothing in the app mentions a price, a
subscription or a purchase, and no In-App Purchase products are submitted
with this build.
```

---

## v0.8.x — Plus: subscription, cosmetics, manual trips (SUPERSEDED — see v0.8.4 above)

**Этот блок УСТАРЕЛ и вставлять его нельзя.** Он писался, когда монетизацию
отложили, и врёт в трёх местах: подписка называется PRO, а не «Плюс»; цены
стали 24,99 € в год и 5,99 € в месяц (здесь стоят прежние 29,99 и 6,99);
чаевые заведены как Consumable. Актуальный текст — секция v0.8.4 выше.
Оставлен как запись того, что предполагалось сказать.

**Этот блок в App Store Connect для 0.8.0 НЕ вставляется.** «Плюс» спрятан
выключателем `PlusAvailability.isEnabled = false`, товаров в сабмите нет.
Текст оставлен готовым к той версии, где монетизацию включат.

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.8.0 adds a subscription, "Plus": four cosmetic unlocks and one
feature, plus a separate one-time tip that unlocks nothing.

WHAT PLUS UNLOCKS. Eight premium profile backgrounds, an avatar frame with a
small badge next to the user's name (toggleable in Privacy settings), a
background for the vehicle's card in the garage, and a colour for the
user's own route line on the maps — all four purely cosmetic and visible to
other people only while the subscription is active. The one feature: adding
a trip the user did not record, point to point by real roads (an address
search or a map tap for start/end, up to three stops in between, MKDirections
builds the route). A manual trip still counts toward the user's distance,
regions, the Atlas and the assigned vehicle's odometer — it is a real road —
but it earns no experience, no level, no badges and no finds, and its card
carries a "written by hand" label. It cannot be edited after creation; only
deleted and re-entered.

PRICING. A yearly subscription at 29.99 EUR with a 7-day free trial (the
default in the paywall), or monthly at 6.99 EUR with no trial. Both are
clearly priced and timed on the paywall before purchase, and "Restore
Purchases" is one tap away on the same screen and in the user's profile.
Canceling an active subscription is Apple's own "Manage Subscription" sheet,
reached from the profile.

TIP JAR. Three one-time, non-consumable-adjacent purchases (small / medium /
large) with no unlock attached to them at all — the screen says exactly that
before payment, to satisfy 3.1.1: this is a tip, not a disguised feature
gate.

SOURCE OF TRUTH. Whether a purchase is active on THIS device is decided by
StoreKit 2 (Transaction.currentEntitlements + Transaction.updates), so Plus
keeps working offline and on a second phone signed into the same Apple ID.
After a verified purchase the app separately sends the signed transaction to
our server, which is the source of truth only for what OTHER people can see
(the cosmetics on a public profile or garage) — never for gating the
purchasing device itself.

REGION. On the RUS storefront the paywall, its entry points and every
premium-looking row are hidden outright rather than shown locked — there is
no way to reach a purchase screen from that storefront. A Plus subscription
already owned (bought before a storefront change, or via family/App Store
gift) keeps working regardless of storefront.

HOW TO TEST THE SUBSCRIPTION IN SANDBOX
1. On the test device: Settings > App Store > Sandbox Account > sign in with
   a Sandbox Tester Apple ID created in App Store Connect > Users and Access
   > Sandbox Testers. Do this BEFORE opening the paywall — signing in from
   the in-app purchase sheet works too, but the dedicated Settings screen is
   more reliable.
2. In the app: Profile > "Plus" row, or any locked cosmetic (Profile
   appearance, a vehicle's card background, the route-line colour setting) >
   opens the paywall. Tap the yearly plan (selected by default, "7 days
   free, then EUR 29.99/year") or the monthly one, then the purchase button.
   Sandbox subscriptions renew every few minutes instead of every year/month
   — this is Apple's own sandbox behaviour, not a bug.
3. Confirm the purchase in the system sheet with the sandbox account's
   password. The paywall closes and the cosmetics/manual-trip entry point
   unlock immediately.
4. RESTORE: from a second sandbox device, or after deleting and reinstalling
   the app, open the paywall and tap "Restore Purchases" — Plus is back
   without a new charge.
5. CANCEL / GRACE: Profile > active-subscription row > "Manage Subscription"
   opens Apple's own sheet; cancelling there does not revoke access
   immediately (the subscription remains active until the paid period ends,
   matching Apple's own behaviour) — this is expected, not a bug to report.

TIP JAR. Profile > "Support the app" > any of the three amounts > confirm in
the sandbox purchase sheet. Nothing else changes on screen except a one-time
"Thank you" toast — that is the entire feature.

MANUAL TRIPS. Profile > "Mine" > "+" in the header (or "..." on the feed
header > "Add a trip"), only reachable with an active Plus subscription (or
a purchase already restored). Pick a start and an end by search or by
tapping the map, optionally up to three stops, a vehicle, a date and a
duration, then "Create". The new trip appears in the list with a pencil icon
and no speed chart on its card.

No new permissions are requested beyond what 0.7.0 already had.
```

### Если спросят про приватность и данные

Это ответ на ОТДЕЛЬНЫЙ вопрос ревьюера, не продолжение вставки выше — вместе
два блока уходят за 4000 знаков лимита Notes.

```
This release adds one new data type: Purchase History. When a purchase is
verified by StoreKit on the device, the app sends the signed transaction to
our server, which stores the subscription's product id, status, expiry date
and trial flag against the user's account — this is what lets Plus
cosmetics show correctly on the user's PUBLIC profile and garage to other
people, and nothing else. It is linked to the user's identity and used only
for App Functionality; it is never used for tracking, advertising or
analytics, and it is not shared with any third party. The App Privacy
answers for this submission add "Purchase History" accordingly; every other
answer is unchanged from 0.7.0.

The tip jar is a StoreKit consumable purchase with no server round trip at
all — no receipt, no product id and no amount is sent to us; it does not
appear anywhere in the Purchase History disclosure above.

A manual trip's route, stops and title are user-entered content, handled
exactly like a recorded trip's title and notes (existing "Other User
Content" answer) — nothing new there. Its GPS-shaped points are
synthesized from Apple's own MapKit directions, not measured, and only ever
leave the device if the user has both signed in and turned Cloud Sync on
(both off by default), same as any other trip.
```

### Длинная версия — для нас

Схема CoreData v19: `TripEntity.source` (`recorded`/`manual`),
`VehicleEntity.cardStyle`, `UserSettingsEntity.avatarFrame`/`showPlusBadge` —
все четыре аддитивные. На бэкенде — `plus_subscription` (по строке на
`original_transaction_id`, без внешних ключей — подписка переезжает между
аккаунтами), `plus_event` (аудит, хранит SHA-256 payload, не сам payload) и
денормализация `account.plus_until`, которую читает каждый публичный ответ
(лента, профиль, гараж, комментарии) без обращения к платёжной таблице.

`avatarFrame`/`showPlusBadge` едут ТОЛЬКО через `POST /auth/profile-update`
(не через `/settings/upsert`) — см. CLAUDE.md «Плюс (0.8.0)». Косметика
гасится по СПИСКУ (`plus-view.ts`), а не выключением поля целиком: человек,
купивший бесплатный фон три года назад, не теряет его из-за того, что
подписка кончилась.

Демо-аккаунт по-прежнему не нужен и не заводится: вход — Sign in with Apple
собственным Apple ID ревьюера, для песочницы покупок — отдельный Sandbox
Tester (см. «How to test» выше, это НЕ учётная запись входа в приложение).
§«Demo account (if reviewer asks)» внизу файла — запасной план на случай
отказа ревью, а не текущая практика.

---

## v0.7.0 — the Atlas: real fog and finds (previous submission)

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.7.0 turns the Map tab into an "Atlas": the world starts covered by
opaque fog, and only the roads the user has actually driven are open in it.

THE FOG. Everything drawn on the Atlas comes from trips recorded on this phone.
On first launch the app rebuilds the opened layer from the existing library in
the background; nothing is downloaded or uploaded to draw it. The same fog is drawn on a trip's own screen (the world as it looked on
that date) and on the recording screen (a hole that grows around the car).

FINDS. When a trip ENDS, the app reads the recorded track and reports what the
route passed: authored "secrets", "riddles" derived from open map data (a
lighthouse, a mountain pass, a ferry, a dam, a border post), and
milestones of the user's own geography (a first region, an easternmost point,
high in the mountains, below sea level, three regions in one day, a border, a
pass at night). Each one puts a seal on the Atlas and opens as a card.

DRIVING SAFETY — please read this part. Nothing about finds is computed or
shown while the user is driving. During recording there is no banner, no sound,
no vibration and no "a secret is near you" prompt of any kind: the whole feature
runs after the trip has ended, on the finished track. This is not a side effect
of the design, it is a rule the code is tested against — an automated test fails
the build if any of the discovery code is referenced from the recording path, or
if that code gains access to the location manager, the notification centre or
audio playback. Nothing is awarded for speed, and no text in the app asks the
user to drive faster, to reach a point, or to stop at the roadside. An unsolved
riddle is never shown as a point to drive to: it appears as a 5-30 km circle
with one line of text, at most three at a time, on a screen that is read after
the drive. There is no manual "I am here" entry and no tap-on-the-map entry — a
find counts only from a recorded track.

THE JOURNAL. Pulling the Atlas sheet up shows how much the user has opened,
their regions, all their seals and nearby riddles. Finds also appear in the user's public profile under the achievements,
behind the same visibility switch, and "Share the Atlas" produces an image of
the user's own map.

HOW TO TEST
1. Open the fourth tab, "Atlas". On a fresh install it is solid fog, and that is
   correct: nothing has been driven yet.
2. Record a trip. In the Simulator use Features > Location > Freeway Drive (not
   City Run: anything that never exceeds 15 km/h is discarded as a walking
   misfire). While recording, watch the map — a hole opens around the car, and
   nothing else happens: no prompts, no sounds.
3. End the trip. On the summary screen an "Opened" block appears between the
   stats and the awards ("42 km of new road ..."), and the fog burns off that
   trip's map along the route just driven. If the drive passed nothing of
   interest there is no block at all, which is also correct.
4. Open the Atlas again: the corridor of that drive is now open, with seals on
   it if anything was found. Pull the sheet up for the journal; tap a seal for
   its card.
5. Sharing: with the sheet collapsed, tap Share. The app renders a picture of
   the map and offers it together with one line of text.

SIGN-IN. Authentication is Sign in with Apple only, and no special account is
needed: the reviewer's own Apple ID works. The Atlas and finds work fully signed
out and with Cloud Sync off (the default) — only the story text of an authored
secret and the "found by N people" counter come from our server.

MODERATION. Authored secrets are written by us, not by users: this feature has
no user-generated content. Riddles come from open map data and name only public
objects, never private property or homes.

No new permissions are requested. Location usage is unchanged from 0.6.8.
```

### Если спросят про приватность и данные

Это ответ на ОТДЕЛЬНЫЙ вопрос ревьюера, не продолжение вставки выше — вместе
два блока уходят за 4000 знаков лимита Notes.

```
This release adds no new data type, no new SDK and no new permission. The App
Privacy answers are unchanged from 0.6.8.

The opened layer — the fog — is computed on the phone from the user's own
recorded trips and stays on the phone. It is not uploaded, it is not part of any
sync payload, and it does not travel to the user's second phone.

The catalogue of authored secrets is downloaded from our server and carries
nothing personal: per secret, 32-bit truncations of SHA-256(salt + cell
geohash) plus a symbol. No coordinates, no names, no user data, and the request
itself carries no location. The catalogue is public by design; the matching
happens entirely on the phone, against a track the phone already holds. Offline,
the app falls back to the cached catalogue; the copy shipped in the bundle is
empty in this release.

A find leaves the phone only when the user has signed in AND turned Cloud Sync
on — both off by default. Then the id of the find and the trip that produced it
are sent, so the server can return the story text, confirm the find against the
track it already stores, and report how many people have found it. "Erase my
data from the server" issues an explicit call that deletes these records, and
deleting the account deletes them as well.

Riddles are derived from public OpenStreetMap data (© OpenStreetMap
contributors, ODbL) and ship inside the app as a dataset of public objects —
the extraction script is published with the app's source (Tools/build_secrets.py)
and the attribution is shown in the app, on the riddle card and in Settings, with
a link to openstreetmap.org/copyright. Evaluating a riddle involves no network
request at all. Milestones are computed from the user's own trips and never
leave the phone except as the user's own find, under the same Cloud Sync
condition.
```

### Длинная версия — для нас

Схема CoreData v18: `RevealedCellEntity` (слой открытого, v16), `DiscoveryEntity`
(находки, v17) и история раскрытия у находки (`finders`, `firstFinderName`,
`firstFinderAt`, `rarity`, v18). Слой открытого в синк-пейлоад не попадает
вовсе; находки едут секцией `discoveries` в `/sync/pull` и строкой
`(.discovery, …)` в очереди синка — и только при `cloudSyncEnabled && isSignedIn`.

На бэкенде — `GET /secrets/catalog` (только усечённые хеши и символы),
`POST /secrets/reveal` (текст после совпадения; координата секрета уходит
клиенту ровно в одном случае — по своей ПОДТВЕРЖДЁННОЙ находке),
`POST /secrets/forget-all` для кнопки «стереть мои данные с сервера» и поле
`finds` в публичном профиле.

Правило «ничего на ходу» держит сторож `NoLiveSecretPromptsTests`: он падает,
если код находок упомянут вне своей папки и разрешённых дверей, или если внутри
папки появился `LocationManager`, `CLLocationManager`, `UNUserNotificationCenter`
или `AVAudioPlayer`. Про это стоит сказать ревьюеру прямо — §2.4 спеки написана
ровно для того, чтобы функция не читалась как «игра за рулём».

Демо-аккаунт по-прежнему не нужен и не заводится: вход — Sign in with Apple
собственным Apple ID ревьюера. §«Demo account (if reviewer asks)» внизу файла —
запасной план на случай отказа ревью, а не текущая практика.

---

## v0.6.8 — places, public journeys, segments (previous submission)

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.6.8 adds three things: places the app recognises, journeys that can
be published, and legs between two checkpoints of one trip.

PLACES. When the user marks a spot during a trip, that spot becomes a "place".
Any later trip whose recorded track passes within about 100 m of it counts as a
pass, so the place can say "Here 4 times" and "usually 2:14 from the start".
Places are computed ENTIRELY ON DEVICE: there is no place table on our server,
no place field in any sync payload, and places do not travel to the user's other
phone. Deleting a place forgets its history; the checkpoints it was built from
stay in their trips.

PUBLIC JOURNEYS. 0.6.6 added journeys — a window of dates over the user's own
recorded trips. They were private, with no public page at all. In 0.6.8 the
owner can publish one, and publishing names what it opens: the sheet lists, one
by one, every private trip inside the journey, so the user sees exactly what
becomes visible. A published journey gets its own screen for other people, a
card in the owner's public profile, and a link trip-track.app/j/<code>; a trip
that belongs to it shows "Part of ..." on its feed card. "Hide journey" reverses
it — the journey disappears from other people's feeds and profiles, while the
trips inside keep whatever privacy they have (hiding one wrapper must not
silently hide six trips). Signing out with "hide public content", and deleting
the account, remove journeys the same way they already removed trips.

Related fix in this build: a /s/ link to a trip the user has since made private,
or hidden when signing out, now returns 404. Previously such a link kept
working; the check is now server-side.

LEGS. Two checkpoints of one recorded trip make a named leg with its own time
and distance. Nothing extra is recorded for it — the numbers are the difference
between two checkpoints the app already had. Legs belong to the trip, sync with
it, and are shown only on the user's own trip.

HOW TO TEST
1. Places: open any recorded trip, tap the map to open it full screen, tap a
   point on the route and choose "Add checkpoint". The Places tab (fourth in the
   bottom bar) now holds that place. Record or simulate a second drive past the
   same spot (Simulator: Features > Location > Freeway Drive — use Freeway
   Drive, not City Run: anything that never exceeds 15 km/h is discarded as a
   walking misfire), and the place shows "Here 2 times" with the usual time.
2. Legs: on a trip with two or more checkpoints, tap a checkpoint in the
   "Moments" list, choose "Leg to..." and pick the second checkpoint. The leg
   appears as a bracket under the earlier of the two, with its name, time and
   distance; tap it to rename or delete it.
3. Public journeys: sign in with Apple, turn Cloud Sync on, combine two trips
   into a journey ("..." on a trip > "Combine into a journey"), then "..." on
   the journey > "Publish journey". The sheet lists the private trips that will
   open with it. After publishing, "..." > "Share" gives the
   trip-track.app/j/<code> link, which opens the journey in the app if it is
   installed and as a web page otherwise.

SIGN-IN. Authentication is Sign in with Apple only, and no special account is
needed: the reviewer's own Apple ID works. Everything except publishing can be
tested without signing in at all; Cloud Sync is off by default.

MODERATION. A published journey is user content with the same controls as a
published trip (0.6.3-0.6.5): the owner can hide it at any moment, signing out
can hide everything public, deleting the account erases it from the server, and
the existing report and block flow covers the author. A hidden, deleted or
blocked journey is indistinguishable from one that never existed — the link
returns 404.

No new permissions are requested. Location usage is unchanged from 0.6.7.
```

### Если спросят про приватность и данные

Это ответ на ОТДЕЛЬНЫЙ вопрос ревьюера, не продолжение вставки выше — вместе
два блока уходят за 4000 знаков лимита Notes.

```
Nothing new is collected in this version, and one thing is deliberately not
collected at all.

Places never leave the device. A place is derived on the phone from the user's
own checkpoints and their own recorded tracks: it has no table on our server, no
field in any sync payload, and it does not reach the user's second phone. Two
phones that hold the same checkpoint arrive at the same place identity by
computing it from the coordinates, not by exchanging it.

Legs travel inside the trip they belong to, exactly like the checkpoints added
in 0.6.5, and only when the user has turned Cloud Sync on (off by default). The
server stores a pair of checkpoint ids and a name; the time and distance of a
leg are not stored anywhere — the app computes them from two checkpoints.

A journey becomes visible to other people only through an explicit "Publish"
action that lists, by name, every private trip inside it that will open with it.
Until then a journey is as private as the trips it groups. Hiding it, signing
out with "hide public content", and deleting the account all remove it from the
server's answers.

The home location used to suggest grouping trips into a journey is still
inferred on device from the user's own trip history and never leaves the phone —
unchanged from 0.6.6.

The App Privacy answers are unchanged from 0.6.7; this release adds no new data
type, no new SDK and no new permission.
```

### Длинная версия — для нас

Схема CoreData v15: `PlaceEntity`, `PlacePassEntity`, `TripEntity.placesMatchedAt`
(что уже сверено) и `TripEntity.segmentsJSON`. Ни одна из этих колонок не
попадает в синк-пейлоад, кроме `segments`, который едет внутри поездки рядом с
`checkpoints` и по той же дисциплине ключа: ключа нет — старый клиент, локальное
не трогаем; список пришёл — заменяет прежний целиком.

На бэкенде — публичная страница `/j/<код>` (с проверкой `is_private`, как и у
`/s/` с этой версии), список `GET /users/:id/journeys`, поле `journey` на
карточке ленты и колонка `trip.segments jsonb`. Мест на сервере нет вовсе.

Демо-аккаунт по-прежнему не нужен и не заводится: вход — Sign in with Apple
собственным Apple ID ревьюера, и этого достаточно, включая публикацию.
§«Demo account (if reviewer asks)» внизу файла — запасной план на случай
отказа ревью, а не текущая практика.

---

## v0.6.7 — units and the map car (previous submission)

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.6.7 is a units release plus a redrawn map marker.

UNITS. The app already had a miles/kilometres setting, but it only changed the
labels — the numbers stayed metric. This build makes the choice real across
distance, speed, elevation (feet) and fuel economy. Storage stays metric
everywhere; the unit lives only at the display boundary.

PER-VEHICLE DASHBOARD UNITS. A car's dashboard has its own units, independent
of the person's preference: an imported car with a miles odometer in a metric
country, or the reverse. The vehicle passport now has a "Dashboard units" row
governing exactly three things — the odometer field the user types into, the
odometer display, and fuel figures. Everything else, and every figure that sums
more than one vehicle, stays in the user's chosen unit.

MAP MARKER. Trip replay now draws a top-down car that rotates to the recorded
course, tinted with that vehicle's colour. The previous sprite was a side view
that could only mirror left/right.

CRASH REPORTING. This is the first build that actually sends crash reports.
Earlier releases shipped with an empty Sentry key and sent nothing. The App
Privacy answers have been updated accordingly in this submission — the previous
"Data Not Collected" entry predated the app's account, sync and social
features and was out of date.

No new permissions are requested. Location usage is unchanged from 0.6.6.
```

### Если спросят про приватность и данные

```
The App Privacy answers were rewritten for this submission to match what the
app actually does: account email and name (Sign in with Apple), user and device
identifiers, precise and coarse location for recorded trips, photos, user-written
content, product interaction and diagnostics. All of it is linked to the user's
account; none of it is used for tracking, and the app contains no advertising or
analytics SDK — the only third-party SDK is Sentry, for crash and performance
diagnostics, hosted in the European Union.

Cloud sync is off by default. Trips, photos and settings stay on device until
the user signs in and enables it; a trip the user publishes is the one exception,
and that is an explicit action.

The home location used to suggest grouping trips into a journey is inferred on
device from the user's own trip history and never leaves the phone. Verified by
inspection: the string "home" does not appear in the app's sync models or
networking layer.
```

### Если спросят про единицы и точность

```
Distances are stored in metres and never converted for storage. The unit choice
affects display and input parsing only. Achievement thresholds, experience
points and vehicle levels are computed from metric values regardless of the
chosen unit, so changing units can neither unlock nor lock an achievement.
```

---

## v0.6.6 — journeys

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.6.6 adds "journeys": a way to group the user's own recorded trips
into one story — Krasnodar → Vladikavkaz → Tbilisi and back is four recordings
and one trip in real life. A journey is a window of dates over trips that are
already on the device; nothing is copied, and deleting a journey leaves every
trip untouched.

No new permissions, no new data collection. Journeys are built only from trips
the user recorded themselves, and are private by default: they leave the device
only if the user has turned Cloud Sync on (off by default). There is no public
page for a journey in this version.

Location (5.1.1): unchanged — recording is still started and stopped by the
user (or by the user's own Bluetooth/Shortcuts automation, opt-in). No
background collection was added.

The "home" suggestion: to offer "these drives look like one journey", the app
needs to know where the user sleeps normally, because what makes a journey is a
night away from home. That location is inferred ON DEVICE from the user's own
recorded trips (the ends of evening/night drives), stored locally in app
settings, shown to the user as "Is this your home?", and NEVER sent to our
server or to anyone else. "Yes" closes the question for good; "No" turns the
suggestions off and the app may ask once more after 30 days. No new permission
is requested for this.

User content (1.2): a journey has a user-typed name and an optional cover photo
chosen from the trip's own photos. Both are private; nothing about a journey is
published to other users in this version. Reporting and blocking work as in
0.6.5.

How to test:
1. Have two or more recorded trips that join up. Record two short drives, or
   run the app in the Simulator: start recording, then Features → Location →
   Freeway Drive, let it run a minute or two, stop — and repeat once. Pick
   Freeway Drive, not City Run: anything that never goes above 15 km/h is
   discarded as a walking misfire, so a jogging route (and a phone left on a
   desk) produces no trip at all.
2. Open a trip → "..." in the header → "Combine into a journey". A sheet
   ("Build a journey") lists the neighbouring trips (±7 days) grouped by day.
   The trips that join up — one ends where the next begins, less than 36 hours
   apart — are already ticked; the rest are not. Tick or untick any row, watch
   the total at the bottom, then "Create journey".
3. The same sheet opens by pressing and holding a trip card on the "Mine" tab
   — the card you held is the one the sheet starts from. There is no
   multi-select mode.
4. The journey card replaces its legs in the "Mine" list. Open it: one map with
   all legs, the totals (days, km, drives, time), then the road day by day —
   one card per day, legs and the local-driving stop as rows inside it.
   "..." → "Edit journey" changes the name, the date window (past dates only;
   the count of trips that fall inside is shown live under the pickers) and the
   cover photo (picked from the legs' own photos; it then replaces the map on
   the card and on the screen header). Press and hold a leg row → "Remove from
   journey": the trip leaves the journey and stays in the trip list. "Delete
   journey" removes only the journey — the trips stay in the list.
```

### Длинная версия — для нас

Никаких новых разрешений и никакого нового сбора. Схема CoreData v12 —
`JourneyEntity` (окно дат, исключённые поездки, обложка), миграция lightweight.
Дом — два `Double` в `UserDefaults` приложения (`homeLatitude/homeLongitude`)
плюс флаг «спрашивали»; в синк-пейлоаде его нет вовсе. Проверено перед
сабмитом 0.6.6: `grep -ri home TripTrack/Models/Sync TripTrack/Networking`
пуст, единственные упоминания координат дома — `SettingsManager` (запись и
чтение `UserDefaults`) и `LocalDataWipe` (стирание). Публичной страницы
путешествия в 0.6.6 нет намеренно — она ждёт подъёма сайта.

---

## v0.6.5 — checkpoints and photos on the route (previous submission)

### Короткая версия — вставить в App Store Connect

```
TripTrack 0.6.5 lets a user mark points on a recorded drive ("checkpoints") to
see how long and how far it took to reach them, and places the trip's photos on
the map where they were taken. Nothing new is collected from the device beyond
what the app already uses: location during a recording the user started, and
photos the user explicitly picks from their library.

Location (5.1.1): unchanged — recording is started and stopped by the user
(or by the user's own Bluetooth/Shortcuts automation, opt-in). Track density
during a recording is higher than before; battery use is unchanged (the
distance filter never reduced GPS polling).

Photos (5.1.1): when the user picks a photo, the app reads its capture date
and, if present, its EXIF location to place it on the route. Both stay on the
device unless Cloud Sync is enabled by the user. No photo is read without an
explicit pick.

User content (1.2): checkpoint names are user text, private by default and
visible to others only if the user makes the trip public. Reporting and
blocking work as in 0.6.4.

Test: record a short drive (or use the simulator's City Run), tap the flag on
the Lock Screen Live Activity or on the recording screen; open the trip, tap
the route on the full-screen map — a card shows the time and distance to that
point; confirm to add. Attach a photo to a checkpoint from its sheet.
```

### Длинная версия — для нас

Никаких новых разрешений. Фото читаются через `PHAsset` только для выбранных
снимков (`creationDate`, `location`). Схема CoreData v11, миграция lightweight.

---

## v0.6.4 — vehicle passport

### Короткая версия — вставить в App Store Connect

Ровно то, что нужно ревьюеру: что нового и где жалоба. Длинная версия ниже —
для нас, не для формы.

```
TripTrack 0.6.4 adds a "passport" for each vehicle in the user's garage:
photos, make/model/year, an optional licence plate, and stats derived from
trips already recorded on the device. A user may open another person's garage
if that person made it public.

User-generated content and moderation (1.2):
• Vehicle photos, names, notes and plates are user content and can be public.
• Report a vehicle: the "..." button in the header of its page.
• Report a single photo: the flag button in the full-screen photo viewer.
• Block a user: their profile "..." menu — hides their garage both ways.
• Reports go to the same queue as trips and profiles, actioned within 24h.

Privacy defaults:
• Everything about a vehicle is off or private until the owner turns it on.
• For vehicles that existed before this version, the route map is switched OFF
  on upgrade — a vehicle's map effectively shows where its owner lives.
• Photos leave the device only if the user enables Cloud Sync, which is off by
  default.

No special account is needed. Sign in with Apple is optional; a demo account is
in App Review Information.
```


Self-contained: paste the **English** block below into App Store Connect →
App Review Information → Notes. It replaces the 0.6.3 notes entirely.

### English

TripTrack 0.6.4 — Reviewer Notes

TripTrack is a road-trip diary: it records a drive with GPS and keeps it as a map,
a track and photos. This release gives each vehicle a page of its own and adds
user-controlled visibility for everything on it.

WHAT'S NEW IN 0.6.4
• Vehicle passport — a screen per vehicle: make, model, year, an optional
  registration plate, a level derived from distance driven, three counters
  (trips, regions, days on the road), a map of that vehicle's own trips, its
  records, and its trips as a separate list.
• Vehicle photos — the user picks images from their library; one is pinned as the
  vehicle's main photo. They are uploaded to our storage only when Cloud Sync is
  enabled, which is off by default.
• Public garage — from another user's profile you can open the vehicles they have
  chosen to make visible, and the passport of each.
• "I'm a passenger" — a one-tap state before recording starts, for a taxi, a bus
  or someone else's car. The trip is recorded without a vehicle attached.
• Sold — a vehicle can be marked sold by the user; new trips are never recorded
  onto a sold vehicle. Nothing is marked automatically, and a sold vehicle stays
  visible in the garage (and to other users, if the owner made it public).

USER-GENERATED CONTENT AND MODERATION
0.6.4 adds three new stranger-visible surfaces, all optional and all off or
owner-controlled:
• Free text — the vehicle's name, an optional one-line "about", and make/model
  chosen from a built-in catalogue or typed.
• Photos of the vehicle. They are uploaded to our storage only when Cloud Sync
  is enabled, which is OFF by default; with it off they never leave the device.
• An optional registration plate, hidden by default and shown only if the owner
  turns it on.
Each is covered by the existing report-and-block flow. A vehicle is reported
from the "…" in the header of its page; a single photo is reported from the flag
button in the full-screen viewer, where the photo being reported is on screen
and cannot be mistaken. Blocking a user hides their garage entirely, in both
directions. Reports reach the same queue as the existing ones and are actioned
within 24 hours, per 1.2.

PRIVACY DEFAULTS ON UPGRADE
• Vehicles that existed before this release have their route map switched OFF by
  the upgrade migration. A vehicle's map is effectively "where its owner lives",
  and the axis did not exist before 0.6.4, so no consent to it was ever given.
  Newly created vehicles default to on; the switches live on the vehicle's own
  "Who can see" screen, two taps after it is created.
• Plates are hidden by default; photos are hidden by default for existing vehicles.
• All four axes (vehicle, map, photos, plate) are enforced on the SERVER: hidden
  data is not returned to another user's device at all, rather than being returned
  and hidden by the app.

DATA DELETION
"Delete account" erases the account and its server data, and also erases every
trip, track point, photo, vehicle and vehicle photo held on the device. The
separate "Erase my server data" removes trips, photos and the garage from the
server while leaving the local copy in place.

HOW TO REVIEW
No special account is required; sign-in with Apple is optional and the app is
fully usable signed out. To see the garage: Profile ("Я") → Garage → "+" to add a
vehicle → open it. To see the passenger state: Record tab → the "I'm a passenger"
button next to the vehicle chip. Location permission is requested only when the
user starts a recording.

### Русский (для себя, не для вставки)

То же самое своими словами: паспорт машины, фотографии, чужой гараж, «я
пассажир», проданные машины. Три новых поверхности с пользовательским контентом — имя и
описание машины, фотографии, номер, — все закрываются переключателями, и все
проверяются на сервере. У машин, заведённых до релиза, карта маршрутов выключена
миграцией: согласия на эту ось никто не давал, потому что до 0.6.4 её не было.

---

## v0.6.3 — public profile (previous submission)

Self-contained: paste the **English** block below into App Store Connect →
App Review Information → Notes. It replaces the 0.6.0/0.6.2 notes entirely —
nothing below this section needs to be pasted alongside it.

### English

TripTrack 0.6.3 — Reviewer Notes

TripTrack is a road-trip diary: it records a drive with GPS and keeps it as a map,
a track and photos. This release is about what OTHER people can see, and about
giving every user explicit control over it.

WHAT'S NEW IN 0.6.3
• Opening someone's profile now offers two screens — their full statistics, and a
  map of the trips they chose to make public. Both are the same screens the user
  already has for their own data; only the source of the trips differs.
• "What others see" — four switches (basic counters, full statistics, map,
  achievements). A switch that is off hides that block from everyone else. Basic
  counters, achievements and vehicle visibility are enforced on the server, which
  stops returning the data. Statistics and the map are drawn from the same set of
  the user's already-public trips, so the server stops returning that set when BOTH
  are off; with one of the two still on, the remaining screen is the one hidden by
  the app. Nothing private is involved either way: these are trips the user chose
  to publish, and they are visible in the feed regardless.
• Vehicle visibility is now enforced on the server: a car the owner marked private
  no longer appears on their profile or on feed cards.
• Odometer split in two — the dashboard reading the owner types in, and the distance
  the app recorded itself. The car's level is earned only from the recorded part.
• "I was a passenger" — a trip can be marked as a transfer (taxi, bus, someone
  else's car). The distance stays in the person's statistics but is not added to
  any car's mileage.
• Live Activity shows distance in the compact Dynamic Island.
• A back control is now always present on the recording screen, so a recording in
  progress no longer traps the user there. Recording continues in the background.
• New accent colour.

NO NEW PERMISSIONS. No change to what is collected or stored. Nothing is published
that the user had not already published — the public map draws only trips the owner
marked public, which the app has supported since 0.5. All four switches default to
ON, which preserves exactly what a profile showed in 0.6.2; the app also shows a
one-time card explaining this and links straight to the switches.

Private trips are never drawn on a public map. A private profile stays visible only
to its followers. A closed or blocked profile returns the same indistinguishable
response as a non-existent one, so the app cannot be used to confirm that an
account exists.

ACCOUNT DELETION (Guideline 5.1.1(v))
Me → Account & sync → Delete account. Two taps from the tab bar, no email, no
support ticket. It deletes the server account and everything on it (trips, photos in
object storage, reactions, comments, follows) AND erases the trips and photos stored
on the device. The row states this ("Permanently, everywhere") and the confirmation
names every category before the destructive button. A separate, less destructive
option — "Clear my server data" — wipes the server copy while keeping the account.

LOCATION
Background location ("Always") keeps a recording alive while the screen is off —
that is the product. Location is collected ONLY during a recording the user started.

SIGN IN
Sign in with Apple only, and entirely optional: recording, history, photos,
vehicles, map and statistics all work signed out and offline. Signing in adds cloud
sync and the social layer. A demo account is provided in App Review Information →
User Account.

UGC MODERATION (Guideline 1.2)
• Report — on every public profile, every feed card, every trip, every vehicle
  and every vehicle photo. Eight reasons: spam, harassment, hate, nudity,
  violence, illegal, impersonation, other.
• Block — from any public profile's "…" menu; hides content in both directions.
• Comments can be deleted by their author and by the trip owner.
• Terms of Service state a zero-tolerance policy and a 24-hour moderation SLA.
• Automated denylist filter on user-entered trip titles.

PRIVACY
• No tracking, no ads, no third-party analytics, no cross-app identifiers.
• Photos are stripped of EXIF/GPS metadata on the device before any upload.
• Profiles are public only if the user turns them on (Me → Privacy).
• Privacy Policy and Terms: https://trip-track.app

LANGUAGES
Thirteen: English, Russian, German, Spanish, French, Italian, Polish, Indonesian,
Turkish, Filipino, Ukrainian, Kazakh, Portuguese. The in-app language is chosen in
settings and is independent of the device language; system permission prompts follow
the device language.

HOW TO TEST WITHOUT DRIVING
1. Onboarding → "While using the app" is enough to see every screen.
2. The Feed opens with public trips from real accounts — open one for the trip
   detail, replay, photos and discussion.
3. Open the author of any feed card → their profile has "Statistics" and "Map" cards
   under the counters. That is the new part of this release.
4. Me (last tab) → Privacy → "What others see" → turn a switch off, then reopen your
   own profile through "How others see you": the block is gone there too, because
   that preview obeys the same switches a stranger does.
5. Me → Account & sync for sign-out, "Clear my server data" and Delete account.
6. Recording screen: Record tab → start → the back control in the top row returns to
   the app while the recording keeps running.

CONTACT
privacy@trip-track.app

### Русский (для себя, в ASC не вставлять)

TripTrack 0.6.3 — заметки для ревьюера

При открытии чужого профиля теперь доступны два экрана: полная статистика человека
и карта его публичных маршрутов. Это те же экраны, что пользователь видит для своих
данных; отличается только источник поездок.

Управление приватностью расширено, а не сокращено. «Приватность» → «Кто что видит»:
четыре тумблера — базовые счётчики, расширенная статистика, карта, достижения. Все
включены по умолчанию, что в точности сохраняет то, как профиль выглядел в 0.6.2.
Выключенный блок скрывается от всех, и сервер перестаёт отдавать эти данные вовсе, а
не полагается на то, что их спрячет приложение. Видимость машины теперь тоже
соблюдается на сервере.

Приватные поездки на публичную карту не попадают никогда. Закрытый и заблокированный
профиль отвечают тем же, чем несуществующий, — по ответу нельзя подтвердить, что
аккаунт есть.

Новых разрешений нет, состав собираемых данных не изменился.

---

## v0.6.2 — vehicles and illustrations (previous submission)

A cosmetic release on top of 0.6.1, plus a sign-in stability fix. No new
permissions, no change to what data is collected, stored or transmitted, no
change to accounts or deletion. The 0.6.0 notes further down still describe
the app accurately. Paste **this** section, then the English 0.6.0 section
under it.

### English

```
TripTrack 0.6.2 — Reviewer Notes

WHAT CHANGED
This release is about how the app looks. The garage previously offered one car
silhouette in eight colours; it now offers ten — saloon, hatchback, crossover,
pickup, van, convertible, sports car, motorcycle, scooter and bicycle — in nine
colours, with the shape and the colour picked on separate axes. The motorcycle,
moped and bicycle vehicle types already existed and were all drawn as a car.

Alongside that, the empty states, error states and onboarding pages now use
illustrations drawn for this app instead of system symbols, and lists show a
placeholder outline while loading instead of a spinner.

All artwork is original, drawn for TripTrack. None of the vehicle silhouettes
depicts a real make or model.

Two bug fixes. A vehicle's mileage is now derived from its trips rather than
accumulated once, so reassigning or deleting a trip updates the number. And a
network drop during a background token refresh no longer signs the user out:
the app retries the refresh on its own, and if the session has genuinely
expired it keeps everything on the device — trips, settings, display name —
and shows a "please sign in again" card instead of wiping state. This changes
no permissions and no data handling; it only makes an existing sign-in more
resilient.

HOW TO SEE IT
Me (last tab) → Garage → any vehicle, or «Add vehicle». The type picker is the
top row, the colour picker below it. Changing the type of an existing vehicle
between «Car» and «Motorcycle» switches the available silhouettes.

NO NEW PERMISSIONS
The permission set is unchanged from 0.6.0: location (including background),
motion, Bluetooth and Photos, each requested at the point of use and each
optional.

STILL TRUE FROM 0.6.0
• Account deletion is in the app: Me → Account & sync → Delete account. It
  removes the server account and everything on it, and erases the trips and
  photos on the device.
• The app works fully offline and without an account; signing in with Apple is
  optional and only enables cloud sync and the social side.
• Trips are private until the user publishes them. Public trips carry reactions
  and comments, with report and block available from the card, the profile and
  the trip.
• The Groups tab is still a preview of clubs that do not exist yet, with a
  waitlist and no user content.
```

### Русский

```
TripTrack 0.6.2 — заметки для ревьюера

ЧТО ИЗМЕНИЛОСЬ
Релиз про внешний вид. Раньше в гараже был один силуэт машины в восьми цветах,
теперь их десять — седан, хэтчбек, кроссовер, пикап, фургон, кабриолет,
спорткар, мотоцикл, скутер и велосипед — в девяти цветах, причём тип и цвет
выбираются отдельно. Типы «мотоцикл», «мопед» и «велосипед» в приложении уже
были и все три рисовались легковой машиной.

Вместе с этим пустые состояния, экраны ошибок и онбординг получили рисованные
иллюстрации вместо системных значков, а списки при загрузке показывают контур
списка вместо крутящегося индикатора.

Вся графика оригинальная, нарисована для TripTrack. Ни один силуэт не
изображает реальную марку или модель.

Два баг-фикса. Пробег машины теперь выводится из её поездок, а не
накапливается один раз, поэтому перенос или удаление поездки обновляет число.
И обрыв сети во время фонового обновления токена больше не разлогинивает:
приложение само повторяет обновление, а если сессия действительно истекла —
сохраняет всё на устройстве (поездки, настройки, имя) и показывает карточку
«войдите снова» вместо стирания состояния. Разрешения и обращение с данными
не меняются — существующий вход просто стал устойчивее.

ГДЕ ПОСМОТРЕТЬ
«Я» (последняя вкладка) → Гараж → любая машина или «Добавить». Верхний ряд —
выбор типа, под ним — выбор цвета. Смена типа с «Машина» на «Мотоцикл» меняет
доступные силуэты.

НОВЫХ РАЗРЕШЕНИЙ НЕТ
Набор разрешений не изменился с 0.6.0: геопозиция (в том числе фоновая),
движение, Bluetooth и Фото — каждое запрашивается в момент использования и
каждое необязательное.

ОСТАЁТСЯ ВЕРНЫМ С 0.6.0
• Удаление аккаунта есть в приложении: «Я» → «Аккаунт и синхронизация» →
  «Удалить аккаунт». Оно стирает серверный аккаунт со всем содержимым и
  удаляет поездки и фотографии на устройстве.
• Приложение полностью работает офлайн и без аккаунта; вход через Apple —
  необязательный и включает только облачную синхронизацию и социальную часть.
• Поездки приватны, пока пользователь не опубликует их. У публичных есть
  реакции и комментарии, жалоба и блокировка доступны с карточки, из профиля
  и из поездки.
• Вкладка «Группы» — по-прежнему превью несуществующих клубов с листом
  ожидания и без пользовательского контента.
```

---

## v0.6.1 — twelve more languages (previous submission)

A localization-only release on top of 0.6.0, plus two small interface fixes.
Nothing about behaviour, data handling, permissions or account deletion changed
— the 0.6.0 notes below still describe the app accurately. Paste **this**
section, then the English 0.6.0 section under it.

### English

```
TripTrack 0.6.1 — Reviewer Notes

WHAT CHANGED
0.6.1 takes the app from two interface languages to thirteen: English, Russian,
German, Spanish, French, Italian, Polish, Turkish, Indonesian, Ukrainian,
Brazilian Portuguese, Kazakh and Filipino. That is essentially the whole
release — no new features, no new permissions, no change to what data is
collected or where it goes.

Two interface fixes ride along: the «Public profile» switch on the Privacy
screen no longer disappears when the server cannot be reached (it stays,
disabled, and says why), and the «Send logs» button now sits above the log
instead of below several hundred entries.

HOW TO SEE IT
Me (last tab) → the gear in the header → Language. Thirteen options, each named
in its own language and script. The interface switches immediately; no restart,
no re-login.

On a fresh install the app picks a language from the phone's preferred-language
list, so a Turkish device opens in Turkish without touching the setting.

The system permission prompts (location, motion, Bluetooth, Photos) are
localized through InfoPlist.strings and follow the DEVICE language, not the
in-app one — to see a Turkish prompt, the device itself has to be set to
Turkish.

STILL TRUE FROM 0.6.0
• Account deletion is in the app: Me → Account & sync → Delete account. It
  removes the server account and everything on it, and erases the trips and
  photos on the device.
• The app works fully offline and without an account; signing in with Apple is
  optional and only enables cloud sync and the social side.
• Trips are private until the user publishes them. Public trips carry reactions
  and comments, with report and block available from the card, the profile and
  the trip.
• The Groups tab is still a preview of clubs that do not exist yet, with a
  waitlist and no user content.
```

### Русский

```
TripTrack 0.6.1 — заметки для ревьюера

ЧТО ИЗМЕНИЛОСЬ
0.6.1 переводит приложение с двух языков интерфейса на тринадцать: английский,
русский, немецкий, испанский, французский, итальянский, польский, турецкий,
индонезийский, украинский, португальский (Бразилия), казахский и филиппинский.
Это практически весь релиз: никаких новых функций, никаких новых разрешений,
никаких изменений в том, какие данные собираются и куда уходят.

Заодно два интерфейсных фикса: переключатель «Публичный профиль» на экране
«Приватность» больше не исчезает при недоступном сервере, а кнопка «Отправить
логи» переехала на верх экрана журнала.

КАК ПОСМОТРЕТЬ
«Я» (последняя вкладка) → шестерёнка в шапке → «Язык». Тринадцать вариантов,
каждый назван на своём языке и в своём алфавите. Интерфейс переключается сразу.

При первой установке приложение выбирает язык по списку предпочтений телефона.

Системные запросы разрешений переведены через InfoPlist.strings и следуют языку
УСТРОЙСТВА, а не выбранному в приложении.

ОСТАЁТСЯ В СИЛЕ С 0.6.0
• Удаление аккаунта внутри приложения: «Я» → «Аккаунт и синхронизация» →
  «Удалить аккаунт». Стирает и серверный аккаунт, и данные на устройстве.
• Приложение полностью работает офлайн и без аккаунта.
• Поездки приватны, пока пользователь их не опубликует; у публичных есть жалоба
  и блокировка.
• Вкладка «Группы» — превью несуществующих клубов со списком ожидания.
```

---

## v0.6.0 — redesign + companions (previous submission)

### English

```
TripTrack 0.6.0 — Reviewer Notes

This is the largest update since 0.5.6: the whole interface was redrawn, and trips
became something people can share with whoever was in the car.

WHAT'S NEW IN 0.6.0
• Five tabs: Feed, Map, Record, Groups, Me
• Companions — invite the people who rode with you to a trip; they can add their own
  photos to it. Invitations arrive in Notifications and can be declined or left later.
• Discussions — comments with replies on public trips, plus reactions and a
  "who reacted" list
• Trip replay, story-format share posters, a rewritten photo viewer
• Profile: "how others see you" preview, followers/following, achievements, levels
• Shared profile links (https://trip-track.app/u/<id>) now open a real profile page
• Groups tab: a PREVIEW of clubs that do not exist yet. Every screen says "SOON";
  the only live part is a waitlist ("Notify me"), which stores nothing but an
  install id and an optional club key. No user content, no chat.
• Delete Account (Guideline 5.1.1(v)) — see below
• Privacy screen collecting the three visibility switches in one place

ACCOUNT DELETION (Guideline 5.1.1(v))
Me → Account & sync → Delete account. Two taps from the tab bar, no email, no support
ticket. It deletes the server account and everything on it (trips, photos in object
storage, reactions, comments, follows) AND erases the trips and photos stored on the
device — the row states this ("Permanently, everywhere") and the confirmation names
every category before the destructive button.

LOCATION
Background location ("Always") keeps a recording alive while the screen is off — that
is the product. Location is collected ONLY during a recording the user started.

SIGN IN
Sign in with Apple only, and entirely optional: recording, history, photos, vehicles,
map and stats all work signed out, offline. Signing in adds cloud sync and the social
layer. A demo account is provided in App Review Information → User Account.

UGC MODERATION (Guideline 1.2)
• Report — on every public profile, every feed card and every trip. Eight reasons.
• Block — from any public profile's "…" menu; hides both directions.
• Comments can be deleted by their author and by the trip owner.
• Terms of Service state a zero-tolerance policy and a 24-hour moderation SLA.
• Automated denylist filter on user-entered trip titles.

PRIVACY
• No tracking, no ads, no third-party analytics, no cross-app identifiers.
• Photos are stripped of EXIF/GPS metadata on the device before any upload.
• Profiles are public only if the user turns them on (Me → Settings → Privacy).
• Privacy Policy and Terms: https://trip-track.app

HOW TO TEST WITHOUT DRIVING
1. Onboarding → allow location "While using" is enough to see every screen.
2. The Feed opens with public trips from real accounts — open one to see the trip
   detail, replay, photos and discussion.
3. Me → "How others see you" for the public profile preview; the "…" there has
   share, report and block.
4. Me → Account & sync for sign-out, "Clear my server data" and Delete account.
5. Groups → "See what's coming" for the clubs preview.

CONTACT
privacy@trip-track.app
```

### Russian

```
TripTrack 0.6.0 — Заметки для ревьюера

Самое крупное обновление с 0.5.6: интерфейс перерисован целиком, а поездку теперь
можно разделить с теми, кто ехал рядом.

ЧТО НОВОГО В 0.6.0
• Пять вкладок: Лента, Карта, Запись, Группы, Я
• Попутчики — приглашение тех, кто ехал с вами; они могут добавить свои фото в
  поездку. Приглашения приходят в уведомления, их можно отклонить или выйти позже.
• Обсуждения — комментарии с ответами к публичным поездкам, реакции и список
  «кто отреагировал»
• Реплей маршрута, постеры для историй, переписанный просмотрщик фото
• Профиль: превью «как видят другие», подписчики/подписки, достижения, уровни
• Ссылка на профиль (https://trip-track.app/u/<id>) открывает настоящую страницу
• Вкладка «Группы» — ПРЕВЬЮ клубов, которых ещё нет. На каждом экране написано
  «СКОРО»; живая часть одна — вайтлист («Уведомить меня»), который хранит только
  идентификатор установки и, опционально, ключ клуба. Никакого контента и чатов.
• Удаление аккаунта (Guideline 5.1.1(v)) — см. ниже
• Экран «Приватность» с тремя переключателями видимости в одном месте

УДАЛЕНИЕ АККАУНТА (Guideline 5.1.1(v))
Я → Аккаунт и синхронизация → Удалить аккаунт. Два тапа от таб-бара, без писем и
обращений в поддержку. Удаляется серверный аккаунт и всё, что на нём (поездки, фото
в объектном хранилище, реакции, комментарии, подписки), И стираются поездки и фото
на устройстве — так и написано на ряду («Безвозвратно, везде»), а подтверждение
перечисляет всё это до красной кнопки.

ГЕОЛОКАЦИЯ
Фоновая геолокация («Всегда») нужна, чтобы запись продолжалась с выключенным
экраном — это и есть продукт. Геолокация собирается ТОЛЬКО во время записи,
начатой пользователем.

ВХОД
Только Sign in with Apple и полностью опционально: запись, история, фото, машины,
карта и статистика работают без входа и офлайн. Вход добавляет облачную
синхронизацию и социальный слой. Демо-аккаунт указан в App Review Information →
User Account.

МОДЕРАЦИЯ UGC (Guideline 1.2)
• Жалоба — с любого публичного профиля, карточки ленты и поездки. Восемь причин.
• Блокировка — из меню «…» на профиле, скрывает в обе стороны.
• Комментарий может удалить его автор и владелец поездки.
• В Условиях — нулевая терпимость к недопустимому контенту и SLA 24 часа.
• Автофильтр по денилисту на названиях поездок.

ПРИВАТНОСТЬ
• Нет трекинга, рекламы, сторонней аналитики и cross-app идентификаторов.
• EXIF/GPS удаляются из фото на устройстве до любой загрузки.
• Профиль публичен, только если пользователь включил это сам (Я → Настройки →
  Приватность).
• Политика и Условия: https://trip-track.app

КАК ПРОВЕРИТЬ БЕЗ ПОЕЗДКИ
1. Онбординг → разрешения «При использовании» достаточно для всех экранов.
2. В Ленте — публичные поездки реальных аккаунтов: откройте любую и посмотрите
   деталку, реплей, фото и обсуждение.
3. Я → «Как видят другие» — превью публичного профиля; в «…» шеринг, жалоба, блок.
4. Я → Аккаунт и синхронизация — выход, «Удалить мои данные на сервере», удаление
   аккаунта.
5. Группы → «Посмотреть что будет» — превью клубов.

КОНТАКТ
privacy@trip-track.app
```

---

## v0.5.8 — bug-fix update (previous submission)

```
TripTrack 0.5.8 — Reviewer Notes

This is a bug-fix update over 0.5.7. No changes to data collection, account handling, or core flows.

LOCATION: The app uses background location ("Always") to keep recording a trip while the screen is off or the app is backgrounded — core to the product (recording a multi-hour drive). Location is only collected during an active recording.

SIGN IN: Authentication is Sign in with Apple only. No demo account is required — your own Apple ID works. Cloud sync features unlock after signing in.

TESTING WITHOUT DRIVING: The app includes demo trips visible on the feed and map without recording, so the trip detail / photos / map UI can be reviewed without movement. To exercise live recording, move with the device or simulate a location route.

NEW IN 0.5.8 — "Publish trips on the global map" (Profile screen): an OPT-IN toggle, OFF by default. When a user explicitly enables it, only their own trips already marked PUBLIC are shown on a map on our website. Routes are anonymized (start/end points trimmed); private trips are never included; no other users' personal data is exposed. The user can turn it off at any time. This is the user's own content only.

BUG FIXES IN THIS BUILD: map rendering during recording (route line flicker), speedometer reading at a full stop, a launch-screen hang, instant feed loading, full-quality photo upload on any network, and trip-notes discoverability.
```

---

## Historical — first social submission draft

Written before the App Store line existed, when the social work was numbered
«v0.6.0» internally; it actually shipped as **0.5.6**. Kept because the moderation
and privacy wording below is still the source these notes are trimmed from — the
version numbers in it are NOT the current ones.

### English

```
TripTrack v0.6.0 — Reviewer Notes

Thank you for reviewing this major update from v0.4.4 (offline-only) to v0.6.0 (adds optional cloud sync + social features).

WHAT'S NEW vs v0.4.4:
• Sign in with Apple (optional, unlocks cloud sync + social)
• Cloud sync toggle in Profile → Cloud Sync
• Public profiles, follow, emoji reactions (no DMs, no comments)
• Trip sharing via short URL
• Delete Account in Profile → Cloud Sync → Delete Account (Guideline 5.1.1(v))
• Block + Report on every public profile and social feed card (Guideline 1.2)

OFFLINE / GUEST MODE:
The app is fully functional without signing in. All GPS recording, trip history, photos, vehicle profiles, and stats work offline with local CoreData. Sign in with Apple is offered only on the Profile screen and is entirely optional.

UGC MODERATION (Guideline 1.2):
• Terms of Service (URL in App Store Connect) contains a zero-tolerance clause for objectionable content and abusive users.
• Block user — available from any public profile's three-dot menu. Blocked users are removed from feed/search bidirectionally and cannot interact.
• Report content — available from every public profile and every trip card in the friends feed. Reason picker with 8 categories (spam, harassment, hate speech, nudity, violence, illegal, impersonation, other).
• 24-hour moderation SLA stated in Terms.
• Automated text filter on user-submitted trip titles (denylist of slurs and objectionable terms).

PRIVACY:
• App Privacy Labels updated. No tracking, no ads, no third-party analytics, no cross-app identifiers.
• Privacy Policy and Terms available at https://onezee23.github.io/trip-track-ios/
• Precise location collected ONLY during user-initiated trip recording.
• Photos: EXIF and GPS metadata stripped client-side before any upload.
• Cloudflare R2 (EU jurisdiction bucket) for photo storage; disclosed in Privacy Policy.

HOW TO TEST:
1. Launch app — onboarding, decline auto-record for fastest path.
2. Tap record (center tab) to record a trip; stop after a few seconds.
3. Open the trip from Feed — test edit title, share (custom story sheet).
4. Profile (top-left avatar): tap "Sign in with Apple" to test sync.
5. When signed in: segmented "Mine | Friends" appears in Feed. Tap Friends → search/discover → tap any user → Public Profile → three-dot menu to test Block and Report.
6. Cloud Sync screen (Profile → Cloud Sync): toggle, delete account, sign out all live here.

CONTACT:
privacy@trip-track.app
```

---

### Russian

```
TripTrack v0.6.0 — Заметки для ревьюера

Спасибо за ревью. Это крупное обновление с v0.4.4 (полностью офлайн) до v0.6.0 (добавлена опциональная облачная синхронизация и социальные функции).

ЧТО НОВОГО с v0.4.4:
• Sign in with Apple (опционально, открывает cloud sync + social)
• Тоггл облачной синхронизации в Профиль → Синхронизация в облаке
• Публичные профили, подписки, эмодзи-реакции (НЕТ личных сообщений, НЕТ комментариев)
• Шеринг поездки через короткую ссылку
• Удаление аккаунта: Профиль → Синхронизация в облаке → Удалить аккаунт (Guideline 5.1.1(v))
• Block + Report на каждом публичном профиле и карточке социальной ленты (Guideline 1.2)

ОФЛАЙН / ГОСТЕВОЙ РЕЖИМ:
Приложение полностью работает без входа в аккаунт. Все GPS-запись, история поездок, фото, профили авто и статистика работают офлайн через CoreData. Sign in with Apple находится только в Профиле и полностью опционален.

МОДЕРАЦИЯ UGC (Guideline 1.2):
• Условия использования содержат clause о нулевой терпимости к недопустимому контенту.
• Block user — в трёх точках на любом публичном профиле. Заблокированные убираются из ленты/поиска в обе стороны.
• Report content — на каждом публичном профиле и карточке в ленте друзей. Выбор из 8 причин.
• 24-часовой SLA на рассмотрение жалоб указан в Условиях.
• Автоматический текстовый фильтр на заголовках поездок (денилист оскорбительных выражений).

ПРИВАТНОСТЬ:
• App Privacy Labels обновлены. Трекинг отсутствует, нет рекламы, нет сторонней аналитики, нет cross-app идентификаторов.
• Политика конфиденциальности и Условия: https://onezee23.github.io/trip-track-ios/
• Точная геолокация собирается ТОЛЬКО во время записи поездки, начатой пользователем.
• Фото: EXIF + GPS метаданные удаляются на клиенте перед любой загрузкой.
• Cloudflare R2 (EU jurisdiction) для хранения фото; раскрыто в Политике.

КАК ПРОВЕРИТЬ:
1. Запусти приложение — пройди онбординг, пропусти авто-запись для быстрого пути.
2. Тап на центральную кнопку записи → запиши короткую поездку → остановись.
3. Открой поездку в Ленте — проверь редактирование названия, шеринг (custom story sheet).
4. Профиль (верхний левый угол, аватар): тап Sign in with Apple → тест синка.
5. После входа: сегментед "Мои | Друзья" в Ленте. Тап "Друзья" → поиск/discover → тап на юзера → Публичный профиль → три точки → тест Block и Report.
6. Экран Синхронизации (Профиль → Синхронизация в облаке): тоггл, удаление аккаунта, выход.

КОНТАКТ:
privacy@trip-track.app
```

---

## Demo account (if reviewer asks)

Apple reviewers cannot sign in with Apple unless you provide one of:

1. **Test Apple ID** — create a dedicated Apple ID for Apple review (e.g., `triptrack.reviewer@icloud.com`). Sign in on a test device first so the account exists on the backend. Provide username + password in **App Review Information → User Account**.

2. **Guest mode sufficient?** — the app works fully offline without Sign in with Apple. Mention that reviewers can evaluate core functionality without signing in. Most reviewers will accept this for a non-account-gated app.

**Recommended**: provide a demo account. Apple's default behavior is to fail the review with "we could not test sign-in related functionality" if not provided.
