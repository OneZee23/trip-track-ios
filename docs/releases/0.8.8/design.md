# 0.8.8: Me, profile and PRO

Status: implemented; primary visual and interaction checks passed. Based on 0.8.7 (76).
The 0.8.7 submission is unchanged. No 0.8.8 App Store upload or submission yet.

## Direction

A personal road diary with a clear identity, readable trip totals and a calm
PRO storefront. Keep the existing Inter/Handjet typography, terracotta accent,
SF Symbols, custom achievements and user-selected cosmetics. This is a native
SwiftUI refinement, not a web redesign or a new app navigation model.

Applied references:
- [Impeccable](https://github.com/pbakaus/impeccable): Operate mode, hierarchy,
  real-content overflow, state coverage and bounded visual verification.
- [Taste / Redesign](https://github.com/leonxlnx/taste-skill): preserve the
  established identity; improve spacing, legibility and composition first.
- [Motion Framer](https://github.com/freshtechbro/claudedesignskills/blob/main/.claude/skills/motion-framer/SKILL.md):
  state-driven feedback and reduced motion, implemented with SwiftUI. No web
  animation dependency is added.

## Changes

- Me: the default identity card follows the light/dark theme. A flat statistics
  strip replaces the nested translucent card. Settings, profile, level and
  statistics remain separate targets. At accessibility sizes identity and
  statistics stack vertically. Selected covers and entitlement rules remain.
- Profile editor: compact cover, visible name/handle, three named groups for
  personal details, appearance and driving progress. Existing editor order and
  public preview remain. The avatar grid preserves retired-avatar warnings.
- PRO: larger interactive personal preview, unboxed feature groups, selected
  tariff marked with both a check and tint. The offer remains pinned; content
  scrolls by actual size, without the obsolete fixed-height estimate.
- Copy: removes the promise of a gap-free history (PRO does not recover GPS).
  New labels and the revised promise are supplied in all 13 languages.
- Motion: short feedback on pressing, disclosure and avatar choice; no zoom or
  movement when Reduce Motion is enabled. No decorative loops are introduced.

## Verification

- Debug simulator build-for-testing passed, including the signed simulator build.
- 46 focused unit tests passed: plan modelling, paywall states, copy budgets,
  context-sheet layout and premium background access.
- iOS 18.6 / iPhone 16 Pro Max: all five UI scenarios passed. These cover
  purchase-to-background navigation and persistence, the Later action, light
  and dark profile editing, avatar picker, preview, tariff selection and
  German accessibility text.
- iOS 18.6 / iPhone SE (3rd generation): both profile/plan selection and
  maximum-text scenarios passed. Features scroll while the offer stays pinned.
- iOS 26.5 / iPhone 17 Pro Max: profile → settings → privacy consent flow
  passed. The two StoreKit-dependent scenarios remain **unverified**: the
  simulator service returns `SKInternalErrorDomain Code=3` while saving its
  test configuration, before the purchase starts. Retrying with a fully signed
  simulator build did not resolve it. This is not recorded as a purchase pass.
- All four new localization keys exist exactly once in each of the 11
  translation tables, plus Russian/English source strings.
- Gallery: 12 real app screenshots; no missing images or horizontal overflow
  at browser widths 1440 and 390. Prices are from the local StoreKit catalog,
  not production App Store prices. No live purchase was made.

Evidence is local: `~/Desktop/TripTrack-Reviews/2026-10-09-design-088/`.
`index.html` presents light/dark, compact and accessibility screenshots.
Final UI results: `max-final.xcresult`, `compact-final.xcresult`,
`ios26-profile-settings.xcresult`. The first failed run is retained: purchase
checks inherited the recording tab, and the avatar container overrode child
accessibility identifiers. Explicit initial-tab arguments and a containing
accessibility group fixed those issues; final iOS 18.6 runs passed.

The commercial footer retains its existing fixed typography. The feature list,
profile identity and fields support Dynamic Type; this does not claim a full
accessibility overhaul of the purchase flow.

## Release hygiene

- App, Live Activity and watch metadata: 0.8.8 (77).
- Changelog updated; branch `release/0.8.8`.
- Website RU/EN roadmap lists 0.8.8 as in development, not available.
- No backend change is needed for this UI revision.
- No release archive, TestFlight upload or App Review submission for 0.8.8.
  The StoreKit check on iOS 26 remains a release-verification item.
