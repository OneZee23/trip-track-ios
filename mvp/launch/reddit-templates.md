# Reddit Post Templates

**Цель:** распределённый launch через 3 разных subreddit'а после HN. Цепляем разные аудитории, разные углы.
**Send window:** W3 days 22-24 июня (после HN-launch Sunday 21 июня)
**Pre-req:** account aged ≥4 weeks, ≥30 helpful comments в target subs

---

## Cadence rule

**Не делай все 3 поста в один день.** Reddit flags cross-promotion агрессивно. Распределение:

| День | Sub | Title-angle |
|---|---|---|
| Mon 22 июня | r/SideProject | "I built X" — launch story |
| Tue 23 июня | r/iOSProgramming | "[Showcase]" — technical, для devs |
| Wed 24 июня | r/privacy | "Open-source X that doesn't phone home" — privacy-tech-audit angle |

После каждого поста — **не пости 24ч в других subs**, даже комменты избегай в spammy объёме.

---

## 1. r/SideProject (Mon 22 June)

**Members:** ~250k. **Self-promo:** explicitly friendly. **Format pref:** image/video + caption.

### Title
```
I built an open-source "Google Photos for road trips" — 18 months solo, would love feedback
```

### Body

```
Hey r/SideProject,

I just launched TripTrack — an iOS app that automatically records your car trips (route, speed, photos, stops) so you can look back later and see what your year on the road actually looked like.

The wedge: Polarsteps is built for the once-a-year gap year. TripTrack is for the trips you take every weekend without thinking — the drive to the cabin, the route to your parents, the favorite Sunday ride. They add up to something, and now you can see it.

Stack:
- SwiftUI + CoreData (versioned migrations, sync-ready)
- Native MapKit, Kalman-filtered GPS, geohash territory tracking
- NestJS backend (also open source), JWT auth via Sign in with Apple
- Built 100% native, zero external dependencies in the app

Privacy story: trips stay on your iPhone by default. Optional cloud sync per trip if you want a second device. Full source on GitHub, including backend — you can self-host or just verify.

I'm a solo dev, this is a side project on top of a full-time backend job. Just launched on Show HN yesterday — got some great feedback and bug reports that I'm working through.

Current stats:
- ~5 daily users (mostly friends so far)
- 0 revenue (it's free, paid cloud tier may come later for server costs)
- Open source from day one

Looking for honest feedback — what would make you actually use this vs Polarsteps / Arc / nothing? What would make you NOT use it?

App Store: <link>
Code: <github link>
Backend: <github link>
30s demo: <gif link>

(Mods, if this is the wrong place, just nuke it — happy to repost to /r/iOSProgramming if more appropriate.)
```

### Anticipated questions

- "Why iOS-only?" → "Solo dev, started SwiftUI. Android if there's pull. Comment here if you'd install it on Android — I'm collecting signal."
- "Business model?" → "App is free forever. Optional cloud sync may be paid later to cover server bills (~€XX/month VPS). Backend is open source so you can self-host."
- "How is this different from Polarsteps?" → 1 sentence: weekly drives not gap-year + edit-every-point + privacy-first + OSS.

### What NOT to do on r/SideProject

- ❌ Не используй "growth hack" / "MRR" / "ARR" jargon — это flag-словарь
- ❌ Не благодари каждого upvote'ера в комментах — выглядит как payment
- ❌ Не редактируй пост через 1ч ("Edit: thanks for the love!") — выглядит cringe

---

## 2. r/iOSProgramming (Tue 23 June)

**Members:** ~140k. **Self-promo:** showcase posts allowed if technical content present. **Format pref:** technical detail wins.

### Title
```
[Showcase] TripTrack — open-source SwiftUI + CoreData road trip diary, happy to answer architecture questions
```

### Body

```
Hi r/iOSProgramming,

Sharing my side project — TripTrack — an iOS app that auto-records your car trips, sleek SwiftUI/CoreData under the hood. Open source. Looking for code review and architecture feedback more than installs.

The interesting engineering bits:

**Background GPS + Kalman filter**
`CLLocationManager` in background mode with motion-detected start/stop. Kalman filter in ~150 LoC, no external deps — smooths jagged urban tracks into something you can show on a map without embarrassment. Filter lives in `KalmanLocationFilter.swift`.

**Versioned CoreData with sync-ready schema**
v1 → v2 migration with sync fields (`userId`, `serverCreatedAt`, `conflictVersion`, `remoteURL`, `uploadStatus`). Lessons learned: do NOT introduce sync fields in v1, you'll regret it. Migration tested with synthetic data covering edge cases.

**Repository pattern for CoreData**
`TripRepository` protocol with `CoreDataTripRepository` as the default. Lets me unit-test trip business logic without spinning up a stack, and swap to a sync-only repo for testing the upload path. Worth the extra layer.

**Sync queue with deduplication**
`@MainActor` queue with priority ordering, exponential backoff retry, soft-delete tombstones for delete propagation. The hard part wasn't writing it — it was reasoning about the state transitions. Has a `SyncTransport` protocol so the backend client can be swapped.

**Geohash fog-of-war**
`geohash` encoding per trackpoint, batched into `VisitedGeohashEntity`. Renders as overlays on MapKit. Fast enough on iPhone 12 to handle 10k+ visited cells without frame drops.

**Binary polyline encoding**
Custom encoding for routes (variable-length signed delta encoding similar to Google's polyline algorithm but tighter). ~5x reduction vs JSON for typical trips.

The wedge against existing apps: Polarsteps is for gap years and is cloud-only. TripTrack is for the trips you take every weekend, fully local-first, optional cloud sync, open source including the backend (NestJS).

Code: <github link>
App Store: <link>
30s demo: <gif link>

Genuinely curious about architecture critique. The CoreData repository abstraction has been the biggest "was this worth it?" question — opinions welcome.
```

### Anticipated questions

- "Why not Realm / SwiftData?" → "Started in 2024 when SwiftData was still rough; CoreData with NSPersistentCloudKitContainer was the safe choice. Would I pick SwiftData today? Maybe."
- "Why MapKit not Mapbox?" → "Zero external deps was a design constraint. Also MapKit's iOS 17+ rendering is genuinely good now."
- "Background GPS — what's your battery impact?" → "Real-world measurement: ~3-5% per hour of active recording on iPhone 14 with screen off. Mostly driven by GPS sampling frequency."

### What NOT to do on r/iOSProgramming

- ❌ Не показывай скриншоты без сопровождающего кода или архитектурного описания — sub любит **техническую** showcase, не визуальную
- ❌ Не благодари upvotes
- ❌ Не игнорируй критику стека — если кто-то ругает CoreData, ответь конкретно, не "well it works"

---

## 3. r/privacy (Wed 24 June)

**Members:** ~1.6M. **Self-promo:** strict but tolerates OSS если frame'ишь как "code audit invitation" not "buy our thing". **Format pref:** text + GitHub link prominently.

### Title
```
Open-source iOS road trip tracker that doesn't phone home — code + threat model inside
```

### Body

```
Hey r/privacy,

I built an iOS road trip diary app (TripTrack) and wanted to share with this community specifically because the privacy model is the differentiator and I'd love a code audit.

What we DON'T collect:
- No advertising IDs (no IDFA / no IDFV)
- No third-party analytics SDKs in the user-facing path (Google, Meta, anything else — none)
- No background location collection — only when you're actively driving and the app has explicit "while in use" / "always" permission
- No social-graph harvesting (we don't read your contacts, calendar, photos library beyond what you explicitly add)
- No device fingerprinting

What we DO collect (transparency, all optional):
- Crash reports via Sentry (no PII, can be disabled in settings)
- Anonymized usage events for me to know what features work (no per-trip data, no identifiers — can be disabled in settings)
- If you opt into cloud sync: your Sign in with Apple email/name (encrypted at rest), trip metadata, polyline routes, any photos you explicitly attach to a trip

What you can do:
- Use the app fully offline, never sign in, never sync — fully local, no account ever
- Sign in with Apple's email-relay (no real email exposed to me)
- Per-trip privacy toggle — every trip is `isPrivate=true` by default, sharing is explicit
- Self-host the backend if you want zero trust in my server (full NestJS source on GitHub)
- Delete your account and all server data with one tap (verified working — tested it)

Threat model: <link to docs/threat-model.md>
Code (iOS): <github link>
Code (backend): <github link>
App Store: <link>

Honest invitation: if anyone here wants to audit the network layer, the SIWA flow, or the sync protocol — I'll happily walk through it. I'm a backend dev by day, not a security researcher, so an external set of eyes is valuable.

Currently iOS-only. Free. No subscription. May add a paid cloud tier later to cover server costs — but local + self-host stays free forever.
```

### Anticipated questions

- "Why iOS-only — Android is more privacy-friendly" → "Solo dev, started SwiftUI. Self-host backend works for any client; if there's pull for an Android version (or even a community fork), I'll support it."
- "Sign in with Apple is still tracking" → "True if you use real email. SIWA relay gives me a hash, not your email. Or skip account entirely — full local-only works."
- "What's stopping you from changing the policy later?" → "MIT-licensed source means anyone can fork. If I betray the privacy stance, fork the last good commit and self-host. Practical answer: my own data is in this app, I'd be the first victim of a backslide."

### What NOT to do on r/privacy

- ❌ **Never** claim "100% privacy" or "totally private" — community immediately calls bullshit
- ❌ Не упоминай "AI" вообще — anti-pattern для этой аудитории
- ❌ Не сравнивай напрямую с Google Timeline или Apple ("we're better than Apple at privacy") — выглядит как hype
- ❌ Если кто-то найдёт **реальный** privacy issue в коде — **acknowledge публично и в течение часа** create GitHub issue. Это будет твой best PR в этом sub

---

## Cross-promote between Reddit and HN

После HN launch (если успешный) — в каждом Reddit post можно естественно упомянуть "got featured on Show HN yesterday, lots of feedback to work through":

- В r/SideProject это **strong social proof**
- В r/iOSProgramming это **technical credibility**
- В r/privacy это **community endorsement signal**

Но **не делай главным hook'ом** — пост должен стоять и без HN-успеха. HN-mention максимум 1 фраза в первой трети поста.

Если HN flop'нул — **не упоминай вообще**.

---

## Tracker

| Date | Sub | Title used | Upvotes | Comments | Top-3 sentiment | Notable quotes (→ customer-voice.md) |
|---|---|---|---|---|---|---|
| TBD | r/SideProject | | | | | |
| TBD | r/iOSProgramming | | | | | |
| TBD | r/privacy | | | | | |

---

## What если все 3 flop'нут

- Все 3 поста с <10 upvotes за 6ч → пересматривай **positioning**, не каналы. Может быть messaging не цепляет
- Mods удалили хотя бы 2 из 3 → karma недозрел или формат не тот; не пиши ещё месяц в этих subs
- 1-2 успешных, 1 flop — normal distribution, double-down на работающий angle в месяц 2

После всех 3 — обновить `mvp/retro-june-2026.md` с insights.
