# Hacker News Show HN — Launch Post Draft

**Target launch:** Sunday 21 June 2026, 05:00 PDT (= 15:00 Krasnodar / 14:00 UTC)
**Backup launch:** Sunday 28 June 2026, same time
**Link target:** Landing page (не App Store — HN expects writeup, screenshots, repo в одном месте)

---

## Title

```
Show HN: TripTrack – Privacy-first iOS road trip diary, open source
```

**Длина:** 67 chars (HN soft limit ~80).
**Why this title:**
- "Show HN:" — обязательный префикс
- "Privacy-first" — головной differentiator
- "iOS" — фильтр аудитории (избегаем Android-нытья в первом коменте)
- "road trip diary" — что это (не "tracker", не "logger", не "journal" — "diary" эмоциональнее)
- "open source" — major credibility hook, HN loves OSS

**Anti-pattern title (НЕ делать):**
- ❌ `Show HN: TripTrack — The ultimate road trip companion` (маркетинговый тон → instant downvote)
- ❌ `Show HN: I built a road trip app` (нет hook'ов)
- ❌ `Show HN: TripTrack v1.0 🚗` (emoji, version number → флагают)

---

## Body (тело поста на HN)

HN-посты бывают **link-only** (URL → landing) или с **text body**. Для Show HN рекомендуется **link-only**, body отдельно в first comment.

**URL:** `https://trip-track.app` (или текущий лендинг)

---

## First Comment (post immediately after submission)

Размещается в собственном thread как первый комент. Это твой главный pitch.

```
Hey HN — I'm the author.

TripTrack is a SwiftUI/CoreData app I built because Google Timeline died and Polarsteps is for backpackers, not the drive-to-the-cabin crowd. It records your car trips automatically — route, speed, photos, stops. All trips live on your iPhone by default. Optional cloud sync if you want a second device (your data, controlled per-trip).

Built solo over 18 months as a side project. Stack:
- SwiftUI + CoreData (versioned v1→v2 with sync-ready fields)
- MapKit, no third-party maps
- Kalman-filtered GPS via CoreLocation, smoothed background tracking
- Geohash territory tracking ("fog of war" map showing where you've been)
- Binary polyline encoding for compact route storage
- NestJS backend (also open source), Cloudflare proxy, JWT auth via Sign in with Apple

The wedge against existing road-trip apps:
- Polarsteps is for the gap year. TripTrack is for every weekend.
- Edit any point on your track. Polarsteps has unfixable "mystery flights" — TripTrack lets you delete glitches.
- Open source including the backend, so you can verify the privacy story or self-host.

Happy to dig into the GPS-smoothing math, the v1→v2 CoreData migration with sync deduplication, the geohash fog-of-war, or why I think "Google Photos for roads" is the right framing.

App Store: <link>
Code: <github link>
Backend code: <github link>

Currently iOS-only. Android is on the table if there's enough interest — would love to hear if that matters to anyone.
```

**Tone notes:**
- Лёгкий, технарский — не маркетинг
- Конкретика про stack (HN это любит)
- Признание ограничений (iOS-only) — препятствует первой токсичной критике
- Конкретные вещи в которые "happy to dig" — invites comments
- Wedge sentences — короткие, цитируемые

---

## Pre-launch checklist (за неделю до 21 июня)

- [ ] Landing page готов: hero + demo GIF + App Store badge + GitHub link + 30-сек pitch
- [ ] Landing page тестирован: iPhone 4G FCP <2s, hero без скролла, нет email gate
- [ ] GitHub repo: README с screenshots, LICENSE (MIT), CONTRIBUTING.md, описание архитектуры
- [ ] Backend GitHub repo: тоже README с архитектурой и self-host instructions
- [ ] Demo GIF: 30 секунд, ≤3 MB, simulator capture (record→map→detail)
- [ ] App Store listing approved (см. [aso-listing-2026-06.md](../aso-listing-2026-06.md)) с новым title/description
- [ ] Privacy Policy + Terms доступны на лендинге (HN audit-friendly community)
- [ ] Threat model документ для skeptical commenters (`docs/threat-model.md` — что мы НЕ собираем и почему можно верить)
- [ ] User research interviews done (W1) — есть quotes и stories на случай questions про users
- [ ] Stripe / IAP отключены (HN критикует paywalls в Show HN; mention "free, future cloud sync may have paid tier" — OK; pre-existing paywall — NOT OK)

---

## Launch day playbook (Sunday 21 June)

### 04:30 PDT (14:30 Krasnodar) — pre-flight
- [ ] Открой HN news.ycombinator.com, убедись что нет mass-event (Apple WWDC, Google IO etc) который зальёт front page
- [ ] Final read of first comment — нет ли опечаток / cringe
- [ ] Чашка кофе, тихая комната, 6 часов free

### 05:00 PDT (15:00 Krasnodar) — submit
- [ ] Submit post с title + link
- [ ] **Immediately** open thread and post first comment as первый комент (within 60 seconds of submission)
- [ ] Tweet/Twitter announce: short thread with link
- [ ] Notify TG-канал (RU dev audience): пост "запустил Show HN сейчас, ссылка ..."

### 05:00 — 06:30 PDT (15:00–16:30 Krasnodar) — first 1.5h
**КРИТИЧЕСКОЕ окно. Если пост наберёт momentum здесь — попадёт на front page.**

- [ ] **Replying within <60 min to EVERY comment**. Это не optional — HN наблюдает за author engagement
- [ ] **Не спорь** с критикой. Acknowledge → ask follow-up question → if you disagree, do so technically not emotionally
- [ ] **Не благодари** за каждый коммент ("thanks!" looks like reddit). Просто отвечай по сути
- [ ] **Не запрашивай upvotes** ни в треде ни приватно — HN детектит это и hellbans
- [ ] Если попал на front page (≥30 upvotes за 1ч) — оставайся за компом next 4 часа

### 06:30 — 12:00 PDT (16:30–22:00 Krasnodar) — sustain
- [ ] Reply velocity снижается до ~1/час
- [ ] Save quotes из comments в `mvp/user-research/customer-voice.md`
- [ ] Если есть качественный bug-report — fix или create GitHub issue в реальном времени (HN community LOVES this)
- [ ] Если кто-то self-hosting backend пытается — help them в треде, это золотая PR

### 12:00 PDT onwards — late afternoon
- [ ] Replies можно отвечать в течение дня next 2-3 days
- [ ] HN thread остаётся discoverable 48-72 hours

---

## Anticipated questions + answer drafts

Готовь ответы заранее — в стрессе launch'а написать с нуля не получится.

### Q: "Why iOS-only? Android users are 70% of the market."

```
Solo project, started in SwiftUI because that's what I knew best at the time. Android is on the table — looking for signal here whether enough people would actually install it. If you'd use it on Android, just say so in this thread, that's data for me.
```

### Q: "Why open source if you might charge for cloud sync later?"

```
Two reasons. First, OSS is the only honest way to claim "privacy-first" — you can read the code. Second, the app itself stays free forever; if cloud sync goes paid eventually, you can self-host the backend (it's also open source) or stay on-device with no sync at all.
```

### Q: "How is this different from Polarsteps / Roadtrippers / Arc Timeline?"

```
- Polarsteps: built for once-a-year vacations with flights and multi-country trips. TripTrack is for the weekly drives. Also Polarsteps has multi-year unfixed track-correction issues; TripTrack lets you edit any point.
- Roadtrippers: trip planner, not journal. Different job.
- Arc Timeline: closest in philosophy but stalled (~1 update/year), iOS-power-user UX. TripTrack is for normal road-trippers with social/share options if they want them.
- Dawarich: great for self-hosting nerds. TripTrack is for people who want it to just work but with the same privacy guarantees.
```

### Q: "Show me code samples / what's the architecture?"

```
Linked the GitHub above. Highlights:
- TripRepository protocol abstracts CoreData CRUD (testable, swappable for sync-only mode)
- Kalman filter in KalmanLocationFilter.swift, ~150 LoC, no external deps
- SyncQueue is @MainActor with dedup + exponential backoff + soft-delete (tombstones)
- Geohash fog-of-war in GeohashEncoder + VisitedGeohashEntity — fastest way to render territory coverage I found

Happy to walk through any of this if there's interest.
```

### Q: "What does cloud sync do? What gets uploaded?"

```
Per-trip control. You pick which trips publish to your account. Default state: every new trip is `isPrivate=true` on creation. Sync uploads polylines (binary-encoded), trip metadata, and photos you've explicitly attached. Nothing about your device, nothing background, no analytics SDKs. Threat model doc is on the landing page.
```

### Q: "Business model?"

```
Free, MIT-licensed source, no ads, no advertising SDKs. Crash reports (Sentry) and anonymous usage stats (PostHog) are opt-out in settings — full disclosure in the threat model. Cloud sync is currently free while user base is small. If it grows, cloud sync may move to a small annual paid tier to cover server costs (currently ~€XX/month on a single VPS). Local-only and self-host options stay free forever — that's why backend is also open source.
```

### Q: Toxic comment / dismissive comment

```
Don't engage emotionally. Either:
- Find the kernel of truth, acknowledge, move on ("Fair — the [X] flow is rough. Tracking it as issue #N now.")
- If just empty negativity, ignore and let other commenters respond
- Never get into back-and-forth past 2 replies
```

---

## Success criteria for HN launch

| Outcome | Interpretation |
|---|---|
| ≥100 upvotes, front page top half | **Excellent**. 1000-5000 landing hits, 30-150 installs realistic. Месяц 2 leverages this. |
| 30-99 upvotes, lower front page | **Good**. 300-1500 hits, 10-50 installs. Smoke test passed. |
| 10-29 upvotes | **Acceptable**. Got some feedback comments — value is in those, not installs. |
| <10 upvotes, no comments | **Flop**. Try again 28 июня with different title. After 2 flops — переписать positioning или dev.to long-form вместо HN. |

---

## Post-launch (W4 retro inputs)

После closing thread:
- [ ] Все cited quotes из comments → `mvp/user-research/customer-voice.md`
- [ ] Все feature-asks → GitHub issues, labelled `from-hn-launch`
- [ ] Все bug-reports → GitHub issues, prioritise по severity
- [ ] HN reach metrics (upvotes, comments, front-page time) → retro doc
- [ ] Landing page traffic + UTM-attributed installs → retro
- [ ] Lessons learned for ProductHunt launch in месяц 2
