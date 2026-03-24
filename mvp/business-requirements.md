# TripTrack — Business Requirements (Release v0.1.0)

## Document Status
- Product: TripTrack (iOS)
- Release target: `v0.1.0`
- Status: Ready for first public release
- Owner: OneZee
- Last updated: 2026-03-24

---

## 1) Product Vision
TripTrack is a personal road diary for iPhone: users record car trips in one tap and return later to relive routes, stats, photos, and travel history.

Core value:
- Minimal effort during recording
- High emotional value when reviewing past trips
- Privacy-first, local-only storage

---

## 2) Problem Statement
Drivers lack a simple app that automatically captures everyday road history.

Existing alternatives are not a fit:
- Navigation apps are not personal journals
- Fitness trackers are optimized for running/cycling
- Travel journals are often manual and trip-centric

TripTrack addresses this with automatic route logging + narrative trip history.

---

## 3) Target Audience
- Primary: iPhone drivers who travel regularly (city, weekend, intercity)
- Secondary: road-trip creators who want visual trip stories

User jobs:
- Record trips without manual overhead
- Recall where/when/how they drove
- Track progress and exploration motivation

---

## 4) Scope for v0.1.0
Must-have outcomes in this release:
- GPS trip recording (foreground/background while recording)
- Live trip HUD (speed, distance, duration, altitude)
- Trip feed with monthly grouping and filters
- Trip details with route map, stats, notes, and photos
- Regions exploration (fog/scratch map)
- Gamification (badges, XP, levels)
- Localized UI (RU/EN) and themes (system/light/dark)
- Fully offline local persistence (CoreData + on-device photos)

Out of scope for this release:
- Cloud sync / backend
- Social network features
- Android version
- Subscription/monetization flows

---

## 5) Release Goals (v0.1.0)
Product goals:
- Publish a stable MVP to App Store
- Validate value with real usage and retention
- Ensure privacy-first positioning is clear in product copy

Quality goals:
- Reliable trip lifecycle (start/pause/resume/stop)
- Acceptable battery usage during active recording
- Crash-free core flow for onboarding, recording, feed, and trip detail

---

## 6) Functional Requirements (High-Level)
- FR-01 Recording lifecycle: start, pause/resume, stop, save summary
- FR-02 Route quality: smoothing/filtering and route rendering consistency
- FR-03 Feed usability: list, sections, search/filter, empty/loading states
- FR-04 Detail completeness: map, metrics, notes, photos
- FR-05 Motivation loops: badges/XP/levels and region progress visibility
- FR-06 Settings/localization: theme + language switching
- FR-07 Privacy by design: no account, no external analytics, local storage

---

## 7) Non-Functional Requirements
- Platform: iOS 17+ (iPhone)
- Stack: SwiftUI + MapKit + CoreData, no third-party dependencies
- Privacy: user data stays on device
- Performance: smooth map/HUD updates during active tracking

---

## 8) Release Links
- Repository: https://github.com/OneZee23/trip-track-ios
- Issues / Support: https://github.com/OneZee23/trip-track-ios/issues
- Privacy policy: https://onezee23.github.io/trip-track-ios/docs/privacy-policy.html
