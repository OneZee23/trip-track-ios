# Twitter / X — Build-in-Public Plan

**Account creation:** W1 day 1 (1 июня 2026)
**Language:** English (target: EN-speaking road-trippers + indie-dev community)
**Cadence:** 2-3 posts/week максимум. Не daily — у тебя нет аудитории и daily posts с 0 followers = шум для самого себя
**Goal по 30 дням:** 30-50 followers (всё с нуля). НЕ "viral", а **discoverable footprint** который leverage'ит HN/Reddit traction

---

## Why bother с Twitter если 500 TG подписчиков уже есть

Твой TG — RU-dev аудитория. **Не road-trippers, не DACH-аудитория, не build-in-public англоязычный community.**

Twitter нужен для:
1. **Anchor для HN/Reddit launches** — в HN first comment ты можешь упомянуть "I tweet build-in-public updates" — это credibility
2. **Discoverability через replies** — отвечая под индексирующими постами #buildinpublic, #indiehackers, #SwiftUI, ты появляешься в feed'ах interested
3. **Long-tail SEO** — Twitter posts появляются в Google
4. **Лицо проекта** — потенциальные users / contributors / interviewers могут проверить что ты реальный человек

**Что Twitter HE даёт за 30 дней:**
- ❌ Сотни installs (audience не выстроена)
- ❌ Viral momentum (1 viral tweet требует existing distribution)
- ❌ Заменит HN/Reddit/blogger outreach

---

## Account setup (W1 day 1)

### Handle
- **First choice:** `@triptrack_app` или `@TripTrackApp`
- **Backup if taken:** `@triptrack_io` / `@triptrackapp` / `@trip_track_app`
- НЕ использовать `@OneZee_` стиль (твой personal handle) — для проекта нужен brand-handle. Personal aккаунт можно вести отдельно

### Profile picture
- TripTrack app icon (clean square, иконка из AppStore)
- Не используй фото лица — это **проект**, не **личный** аккаунт

### Banner
- Clean — скриншот route playback из приложения, **с DE/EN текстом** "Your road diary. Recorded automatically."
- Если нет навыков дизайна — белый/тёмный фон с tagline crisp typography. Лучше минимум чем плохой Canva-шаблон

### Bio (160 chars max)

**Option A (recommended):**
```
Open-source iOS road trip diary. Built for the trips you take every weekend. Private by default. 🛣️
Made by @<your-personal>.
github.com/<org>/triptrack
```

**Option B (более brand'овый):**
```
Your road diary, automatically. Open source. Privacy-first. iPhone.
trip-track.app — built by a solo dev moving toward Germany 🇩🇪
```

**Option C (для приоритета на DACH):**
```
Reisetagebuch fürs Auto. Open Source. Datenschutzfreundlich. iPhone.
Built solo, soon to be DE-based. trip-track.app
```

**Не используй emoji-spam:** 1-2 emoji max, или ноль.

### Pinned tweet — Intro thread (4 tweets)

```
1/4 — I'm building TripTrack, an open-source iOS road trip diary.

It auto-records every drive you take so you can look back and see what your year on the road actually looked like.

Built solo over 18 months on top of a full-time backend job. Available on the App Store. 🛣️

[insert demo GIF, 15-30s, looped]
```

```
2/4 — The wedge:

Most trip apps are built for the gap year. TripTrack is for the trips you take every weekend without thinking. The drive to the cabin. The route to your parents. The favorite Sunday ride.

They add up to something — and now you can see it.
```

```
3/4 — Privacy is the design constraint, not the marketing line.

Trips stay on your iPhone by default. Optional cloud sync per trip. Backend is open source too, so you can self-host.

No ads. No advertising SDKs. No contact-scraping. Optional crash reports & analytics — both 1-tap off. 1-tap account deletion.
```

```
4/4 — Following along here for build-in-public updates.

Roadmap is open. Open source: github.com/<org>/triptrack
App Store: <link>
Threat model: trip-track.app/threat-model

Feedback / DM / replies all welcome.
```

---

## Cadence + content (30 дней)

| Week | Cadence | Тип контента |
|---|---|---|
| W1 | 2 posts | Account intro thread (pinned) + 1 "starting a 30-day marketing challenge" tweet |
| W2 | 2 posts | 1 about a technical decision (e.g. "why open-source the backend"), 1 about user-interviews insight (anonymized) |
| W3 | 3 posts | HN-launch live tweet, 1 follow-up with stats, 1 thanking the people who engaged |
| W4 | 2 posts | Retro tweet with numbers (installs, lessons), 1 forward-looking ("month 2 plan") |

**Total month 1: ~9 tweets** + replies к relevant accounts.

### Sample tweets (skeleton drafts)

**W1 challenge announcement:**
```
Day 1 of a 30-day marketing challenge for TripTrack.

Starting state:
- 3-5 DAU
- $0 revenue
- 0 GitHub stars
- iOS-only, English B1, German A1
- Side project, full-time job

Goal: 100-300 new installs by end of June. Posting everything as it happens.
```

**W2 technical decision tweet:**
```
Decided to open-source the backend (NestJS) alongside the iOS app.

Reasoning: "private by default" is meaningless if you can't verify the code. Self-hosting also gives the most privacy-conscious users a real option.

Trade-off: more code in the open == more code to maintain.

github.com/<org>/triptrack-backend
```

**W2 user-research insight (anonymized):**
```
Talked to 5 TripTrack users this week. The pattern:

They don't see themselves as "road-trip enthusiasts."

They see themselves as people who happen to drive the same routes a lot and got curious about how those drives actually add up.

Reframing the messaging accordingly.
```

**W3 HN launch live:**
```
Just posted Show HN.

If you're an indie iOS dev / road-tripper / privacy nerd — would love your eyes:
news.ycombinator.com/item?id=XXXX

(I'll be replying to every comment for the next 6 hours.)
```

**W4 retro:**
```
30-day marketing challenge: results.

- New installs: XXX (vs goal 100-300)
- HN: XX upvotes
- Reddit: X posts, Y total upvotes
- Bloggers: X reviewed, Y replied
- User interviews: 5

Top lesson: <one sentence>
Biggest surprise: <one sentence>
Month 2 plan: <one sentence + link>
```

---

## Engagement strategy (replies > posts)

С 0 followers, **твой собственный feed никто не видит**. Что видит — это **твои replies** под более крупными аккаунтами в твоей нише.

**Целевые accounts для replies (не follow-spam — реальное engagement):**

Indie-dev / build-in-public:
- @levelsio (Pieter Levels)
- @marckohlbrugge
- @rauchg
- @theo (t3.gg)
- @swiftindie
- @swiftui (SwiftUI community handles)

Road-trip / privacy-tech:
- @arc_timeline (Arc app)
- @polarsteps
- @signalapp (для privacy-context tweets)
- @swiftorg (Swift official)

DACH / German tech:
- @ct_magazin (c't magazine)
- @netzpolitik
- @golem_news

**Rule:** не запостив самого 3+ дня, **не делай replies** — будет выглядеть как promo-bot. Сначала собственный content, потом engagement.

**Quality > volume:** 1 thoughtful reply под крупным tweet > 10 generic "great point!" replies.

---

## DM strategy

С 0 followers, **cold DM = spam**. Не делай.

Acceptable DM situations:
- Кто-то tweet'нул "looking for a road trip diary app" → reply public, then "happy to give you a free Pro code, DM if interested"
- Bloggers с которыми контакт начат по email — DM можно для follow-up если email failed
- Existing followers с specific questions — обязательно отвечать

---

## What NOT to do on Twitter

- ❌ **Не покупай followers** — детектится Twitter, аккаунт shadowban
- ❌ **Не follow-spam-then-unfollow** — old growth-hack, теперь убивает reach
- ❌ **Не пости одно и то же 3 раза за неделю** — even если первый пост не зашёл
- ❌ **Не используй >3 hashtag'а** в одном tweet — выглядит как 2018-era spam
- ❌ **Не RT свои собственные tweets через 30 минут** — visible cringe
- ❌ **Не игнорируй replies к своим tweets** — даже если коммент кажется бесполезным, лайк или короткий ответ build community
- ❌ **Не сравнивай напрямую с Polarsteps в публичных tweets** — могут вызвать community backlash. В replies на конкретный вопрос — OK
- ❌ **Не пиши только про код** — твой ICP не разработчики. Mix tech + product + user-story tweets

---

## Анти-pattern: build-in-public стало parody

Сейчас 2026, "I'm building X with $0 MRR, day 47" tweets — joke-meme.

**Чтобы не выглядеть as parody:**
- Реальные numbers, не fake milestones
- Реальные mistakes, не staged "vulnerable" moments
- Конкретные решения и trade-offs, не общие фразы
- Иногда пости про продукт **без** "and here's my journey" angle

---

## Cross-promote с TG-каналом

У тебя есть **500 RU-dev подписчиков** в TG. Можно дублировать **самые technical** tweets как posts в TG (translated to RU). НО:
- TG aудитория — **devs**, не road-trippers. Не пости там tweet о user-research insights — нерелевантно
- НЕ пости "буду виден тут @ <twitter handle>" больше 2 раз за месяц — выглядит как desperate cross-promo
- TG-канал лучше использовать для **deeper посты** (1000+ слов) которые на Twitter не помещаются — backend architecture, marketing-experiment retro, etc.

---

## Tracker

| Week | Posts published | Followers (end of week) | Notable engagement | Insight |
|---|---|---|---|---|
| W1 | | | | |
| W2 | | | | |
| W3 | | | | |
| W4 | | | | |

После 30 дней решение: **scale up Twitter (3-5 posts/week)** или **deprioritize в пользу другого канала**.

---

## Sanity check к концу месяца

Если к концу июня:
- 0-10 followers и 0 meaningful engagement → Twitter — не твой канал, **прекращай**
- 10-50 followers с 1-2 реальных conversations → продолжай в том же темпе
- 50+ followers с активными convos → scale up в месяц 2
