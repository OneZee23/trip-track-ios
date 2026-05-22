# TripTrack — Threat Model

**Last updated:** 2026-05-19 (для версии 0.5.5)
**Audience:** privacy-aware users, r/privacy auditors, German DSGVO-conscious users, anyone considering self-hosting

This document describes what data TripTrack collects, where it lives, who can read it, and what you can do about it. It is intentionally honest about the trade-offs — including the limits of what an open-source iOS app can guarantee.

If you find an inaccuracy, please open an issue on the [GitHub repo](https://github.com/<org>/triptrack) or email security@trip-track.app.

---

## Data Flow Overview

```
                  ┌───────────────────────────────────────┐
                  │  iPhone (TripTrack 0.5.5)              │
                  │                                        │
   GPS, motion ──▶│  CoreLocation + MotionDetector         │
                  │  → KalmanLocationFilter                │
                  │  → SmoothTrackManager                  │
                  │  → CoreData (local, encrypted at rest  │
                  │    via iOS file protection)            │
                  │                                        │
                  │  Optional features (opt-in):           │
                  │  ─────────────────────────             │
                  │  Sentry crash reports     ──────────┐  │
                  │  Anonymous usage events    ──────┐  │  │
                  │  Cloud sync (per trip)      ─┐   │  │  │
                  └──────────────────────────────┼───┼──┼──┘
                                                 │   │  │
                                                 ▼   ▼  ▼
                                    ┌────────────────────────┐
                                    │  trip-track.app        │
                                    │  (NestJS backend,      │
                                    │   open source)         │
                                    │                        │
                                    │  - PostgreSQL          │
                                    │  - JWT auth            │
                                    │  - Sign in with Apple  │
                                    │  - Self-hostable       │
                                    └────────────────────────┘
                                              │
                                              │ Cloudflare proxy
                                              │ (TLS, no logs
                                              │  beyond IP+timestamp
                                              │  for DDoS)
                                              ▼
                                          Internet
```

---

## What We Collect

### Always (cannot be disabled if app is installed)

Nothing. If you don't grant any permissions and never sign in, TripTrack has zero data leaving your phone — and no data inside the phone beyond what you intentionally record.

### Default behavior (active recording on)

**On-device only:**
- GPS coordinates (raw + Kalman-smoothed)
- Speed, altitude, heading derived from GPS
- Motion-sensor signals for trip start/stop detection
- Photos you explicitly attach to a trip (stored in `Documents/`)
- Vehicle metadata you enter (model, name, odometer)

**None of this leaves your device** by default. Period.

### Optional features (opt-in, per-user)

#### Crash reporting (Sentry)

- **What:** stack traces of app crashes, plus device model and iOS version
- **What is NOT included:** trip data, locations, photos, account email
- **Where:** sent to Sentry SaaS (sentry.io), retained 30 days
- **Toggle:** Settings → Privacy → Disable crash reporting
- **Why we offer it:** without crash reports, solo-dev side projects accumulate silent crashes for months. Disabling is a 1-tap option.

#### Anonymized usage events (PostHog, opt-in via onboarding)

- **What:** event names like `trip_recorded`, `social_feed_opened`, `playback_used` — and aggregate counters (e.g. trip duration buckets, not raw values)
- **What is NOT included:** user identifiers, location data, content of trips
- **Where:** sent to a PostHog instance, retained 90 days
- **Toggle:** Settings → Privacy → Disable analytics
- **Why we offer it:** without aggregate signal, I cannot tell which features work and which to deprecate. Disabling is a 1-tap option.

#### Cloud sync (Sign in with Apple + opt-in per trip)

If you sign in with Apple and **explicitly toggle a trip to public** or **enable second-device sync**, the following leaves your phone:

- **Account:** Sign-in-with-Apple user identifier (a hash, not your email unless you choose to share)
- **Profile** (optional): display name, avatar emoji, current vehicle metadata
- **Trip data:** route polyline (binary-encoded), timestamps, distance/speed/altitude stats, attached photos
- **Social interactions** (if you use them): reactions, follows, comments
- **Where:** stored on our backend at trip-track.app (PostgreSQL), encrypted at rest
- **How:** TLS in transit, JWT-authenticated, ownership-checked on every read
- **Toggle:**
  - Per-trip: each new trip is `isPrivate=true` by default — you must opt in to publish
  - Account-wide: Settings → Cloud Sync → Sign Out (keeps local data, stops sync)
  - Full deletion: Settings → Account → Delete Account (removes server-side data, keeps local)

---

## What We Don't Collect

Explicitly absent:

- **No advertising identifiers** (no IDFA, no IDFV-tracking)
- **No third-party SDKs** in production paths other than Sentry (crash) and PostHog (analytics) — both opt-out
- **No background location collection** outside active recording — when you stop recording, GPS stops
- **No contact list, calendar, photos library** scanning — only photos you explicitly add to a trip
- **No device fingerprinting** — we don't combine signals to track across reinstalls
- **No data sales** — not now, not ever; this is in the Privacy Policy as a binding commitment
- **No ML training on your data** — your trips are not used to train any model, ours or anyone else's

---

## Who Can Read What

| Data | Access |
|---|---|
| Local CoreData on your iPhone | Only you (iOS file protection while phone is locked) |
| Photos in Documents/ | Only you + iOS Photos.app indexing (sandbox) |
| Sentry crash data | Me (developer) + Sentry employees per their privacy policy |
| PostHog analytics | Me + PostHog employees per their privacy policy |
| Cloud-synced trip data | You + me (server admin) + anyone you've shared a public trip with |
| Cloud profile (if public) | You + anyone with the public profile URL |
| Cloud-synced photos | You + viewers of trips you've made public |

**My admin access to the backend:** as the sole developer with database access, I can technically read any cloud-synced data. I do not look at user data except in three cases: (a) debugging a specific issue you've reported, (b) responding to a legal request, (c) sampling for content-moderation review of reported public trips. **All such access is logged in the database.**

In month 6+ when I move to Germany, the backend will be operated by a German entity under DSGVO. Until then, the backend operates under existing privacy law (currently hosted on infrastructure with EU presence; see Privacy Policy for current jurisdiction).

---

## Self-Hosting

The full backend is open source ([github.com/<org>/triptrack-backend](https://github.com/<org>/triptrack-backend)). You can run your own instance:

1. PostgreSQL + Node.js 20+ + Redis (for session/queue)
2. Configure `BACKEND_URL` in the iOS app build (see `Local.xcconfig.example`)
3. Sign in with Apple requires Apple Developer account + Service ID configuration

When self-hosting, no data ever touches my infrastructure. The iOS app talks only to your server.

This is the strongest privacy guarantee TripTrack can offer — if you don't trust the developer, you can verify the code, build your own client, and run your own backend.

---

## DSGVO / GDPR Compliance

For users in the EU/EEA:

- **Article 6 lawful basis:** consent (cloud sync) + legitimate interest (crash reports)
- **Article 7 consent:** opt-in flows for all non-essential data, with clear toggle in settings
- **Article 15 right to access:** export your full account data as JSON via Settings → Cloud Sync → Export Data
- **Article 17 right to erasure:** Settings → Account → Delete Account fully wipes server-side data within 30 days
- **Article 20 data portability:** the JSON export is machine-readable; you can import into any compatible system (currently TripTrack itself, more later)
- **Article 33 breach notification:** any breach of cloud-synced data is reported via email to affected users within 72 hours
- **Data Protection Officer:** TripTrack is below the threshold requiring a formal DPO. Privacy questions: `privacy@trip-track.app`

Full privacy policy: [docs/privacy-policy.html](privacy-policy.html) (RU: [privacy-policy-ru.html](privacy-policy-ru.html))

---

## Threats This Model Does Not Address

Honest about limits:

### What an iOS app cannot guarantee
- **Compromised device:** if your iPhone is jailbroken or compromised, all local data is at risk regardless of app design
- **iOS-level requests:** if Apple receives a valid subpoena for your iCloud-synced data and your app data is backed up to iCloud (you can disable this in iOS settings), Apple may comply

### What our backend cannot guarantee
- **Server compromise:** if our backend is breached, any cloud-synced data is at risk. Mitigation: per-trip privacy default, encrypted at rest, minimal data uploaded
- **Insider risk:** I have admin access. Mitigation: self-host option, open source verifiability of what the client sends
- **Subpoena / legal request:** we comply with valid legal requests per applicable law. Mitigation: minimize what's stored; if you need full deniability, use local-only mode

### What network analysis can reveal
- **Traffic patterns:** even with TLS, an observer of network traffic can see *when* you're using TripTrack (timestamps of API calls). Trip content is encrypted in transit.
- **App Store analytics:** Apple collects download metrics regardless of app design. Per their privacy policy.

---

## Verification

You don't have to trust this document. You can verify:

1. **Read the source code** — both iOS app and backend are MIT-licensed on GitHub
2. **Run mitmproxy** — capture all network traffic from the app and verify what's actually sent
3. **Audit the network layer** — `APIClient.swift` is the single point of network egress; if it's not in there, it's not happening
4. **Check Settings → Privacy** — every opt-in feature is toggleable in plain English
5. **Use a network firewall** — block our domain entirely and the app continues to work fully on-device

---

## Change Log

| Date | Change |
|---|---|
| 2026-05-19 | Initial publication for 0.5.5 |

When this document changes, the diff is in git history. Material changes (new data collected, new third-party involved) will be announced in-app and via email to cloud-sync users 30 days before taking effect.
