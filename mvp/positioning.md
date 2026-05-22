# TripTrack — Positioning Doc

**Дата фиксации:** 1 июня 2026 (W1 артефакт)
**Источник стратегии:** [30-day marketing challenge spec](../docs/superpowers/specs/2026-05-19-30day-marketing-challenge-design.md)

---

## Mission (one-liner)

Личный дневник твоих дорог. Записывает автоматически, остаётся с тобой — а не с облаком.

> EN: *Your personal road diary. Recorded automatically, kept with you — not in the cloud.*

> DE: *Dein persönliches Reisetagebuch fürs Auto. Automatisch aufgezeichnet, bei dir gespeichert — nicht in der Cloud.*

---

## ICP (Ideal Customer Profile)

### Кто это (гипотеза, валидируется W1 interviews)

**Не road-trip-энтузиаст. Не van-lifer.** TripTrack — для людей которые **ездят повторяющиеся маршруты и хотят увидеть паттерн** в собственной рутине.

**Профиль:**
- 28-45 лет
- Машина — ежедневный инструмент, не хобби
- Ездит на работу, на дачу, к родителям, в любимые места выходного дня
- Не хочет вести дневник вручную — но хочет иметь возможность **посмотреть назад**
- Privacy-aware: НЕ хочет чтобы Google знал куда он ездил
- Технически грамотен на уровне "ставлю себе iOS-приложения и читаю privacy policy"

### Evidence (Drive2 comments, май 2026)

**Anti-ICP — DedMoped810 (Honda N-One):**
Когда увидел статью про автодневник, ответ — не "о, прикольно", а **список 5 камер на маршруте**. Это профиль человека который **знает свой маршрут наизусть** — TripTrack для него = **инструмент документирования того что он уже знает**. Совпадает с ICP.

**Anti-anti-ICP — HoodooCH (VW Taos):**
> "Вы расписали обычную поездку как будто на луну ))"

Это car-enthusiast, для которого "обычная поездка" = noise который трекать незачем. Это **не наш ICP**, и Drive2 как канал такого человека вытаскивает — поэтому Drive2 = research, не acquisition.

**ICP-цитата (мы сами):**
> "эти поездки стали частыми в одно и то же место, поэтому стало интересно, а как оно вообще, сколько у меня ресурсов отнимает и каких"

Это **core insight**. TripTrack показывает **скрытую структуру** того что ты делаешь не задумываясь.

### Не-ICP (кого мы НЕ обслуживаем)

- Туристы-путешественники с маршрутом из 10 стран → Polarsteps лучше
- Road-trip планировщики ("куда поехать") → Roadtrippers / Google Maps
- Bookkeeping для бизнеса (километраж для налогов) → Drivvo / Fuelio
- Hardcore privacy-нерды с self-hosting → Dawarich лучше
- Дальнобойщики / коммерческий транспорт → не наш use case

---

## Wedge (главное позиционное копьё)

> **Polarsteps is for your gap year. TripTrack is for every weekend.**

> DE: **Polarsteps für dein Sabbatical. TripTrack für jedes Wochenende.**

Polarsteps оптимизирован под отпуск раз в год с перелётами через 5 стран. **TripTrack оптимизирован под жизнь** — еженедельные поездки на дачу, дорога на работу, выезд к родителям, поездки в любимый ресторан.

---

## Differentiators (по убыванию приоритета)

| # | Differentiator | Vs competitor |
|---|---|---|
| 1 | **Auto-detect старта и стопа** через BT car-connect + motion | Polarsteps, Roadtrippers — manual start |
| 2 | **Edit any point on the route** — править глюки, чистить лишние точки | Polarsteps — "mystery flights and teleportations" нерешённая годами жалоба |
| 3 | **Private by default + optional sync** | Polarsteps cloud-only. Geory в DE имеет похожее, но без OSS |
| 4 | **Open source** (включая бэкенд) | Polarsteps, Roadtrippers, Calimoto — proprietary. Dawarich — geek-only |
| 5 | **Geohash territory tracking (fog-of-war)** | Никто из direct competitors не делает |
| 6 | **Smooth route playback** (анимированное переигрывание поездки) | Только TripTrack из direct competitors |

---

## Taglines

### Главные (универсальные)

| Lang | Tagline | Контекст использования |
|---|---|---|
| EN | Your personal road diary | Web hero, social, generic |
| EN | Recorded automatically. Kept with you. | App Store promo text, Twitter bio |
| DE | Dein Reisetagebuch fürs Auto | Web hero, App Store DE |
| DE | Automatisch aufgezeichnet. Bei dir gespeichert. | App Store promo text, Wohnmobilforum |
| RU | Личный дневник твоих дорог | Drive2, Habr, TG-канал |

### Channel-specific

| Канал | Tagline |
|---|---|
| HN / r/iOSProgramming | Open-source iOS road trip diary — auto-records, edit every point, optional cloud |
| r/privacy | Trip tracker that doesn't phone home — private by default, full code + threat model inside |
| ProductHunt (месяц 2) | Open-source road trip diary for iPhone — privacy-first, no account needed |
| Wohnmobilforum.de | App die meine Touren automatisch aufzeichnet — datenschutzfreundlich, Feedback erwünscht |
| German blogger pitch | Datenschutzfreundliches Roadtrip-Tagebuch für iPhone — Pro-Version kostenlos für Review |
| Twitter build-in-public | Building a privacy-first road trip diary on the side — month X |

---

## Elevator pitch (30 секунд)

### EN (для HN, Reddit, blogger emails, English-speaking)

> TripTrack is a road trip diary for iOS. It records your drives automatically — route, speed, photos, stops — so you can look back later and see what your year actually looked like on the road. Everything stays on your device by default, with optional cloud sync if you want it. It's open source, built solo over 18 months. The wedge: most trip apps are designed for once-a-year vacations. TripTrack is built for the trips you take every weekend without thinking.

### DE (для Wohnmobilforum, German bloggers, App Store DE description first paragraph)

> TripTrack ist ein Reisetagebuch fürs Auto für iPhone. Es zeichnet deine Fahrten automatisch auf — Strecke, Geschwindigkeit, Fotos, Pausen — damit du später siehst, wie dein Jahr auf der Straße wirklich aussah. Alles bleibt standardmäßig auf deinem Gerät, optionale Cloud-Synchronisation falls gewünscht. Open Source, in 18 Monaten allein entwickelt. Der Unterschied: Die meisten Reise-Apps sind für den einen Jahresurlaub gebaut. TripTrack ist für die Fahrten, die du jedes Wochenende ohne nachzudenken machst.

### RU (для TG-канала, Habr, Drive2 — НЕ для главных каналов, но для контекста)

> TripTrack — это автодневник для iPhone. Записывает поездки автоматически: маршрут, скорость, фото, остановки. Потом открываешь и видишь свой год на колёсах. По умолчанию данные на устройстве, синхронизация — опционально. Open source, делал один 18 месяцев. Фишка: большинство трип-приложений делают для редкого отпуска. TripTrack — для поездок которые ты совершаешь каждые выходные не задумываясь.

---

## 3-абзацный landing copy draft

### EN (для главного лендинга)

**Hero:**

> # Your road diary, automatically.
> TripTrack records every drive you take — route, speed, photos, stops — without you doing anything. Open the app later and see what your year actually looked like on the road.

**Section 2 (privacy):**

> Your trips stay on your iPhone by default. No account required to start. Optional cloud sync if you want your data on a second device — and even then, you control what gets uploaded. Fully open source, including the backend.

**Section 3 (wedge):**

> Most trip apps are built for the gap year. TripTrack is built for the trips you take every weekend without thinking. The drive to the cabin. The route to your parents. The favorite ride on Sunday morning. They add up to something — and now you can see it.

### DE (для DE-лендинга, месяц 2)

**Hero:**

> # Dein Reisetagebuch, automatisch.
> TripTrack zeichnet jede Fahrt auf — Strecke, Geschwindigkeit, Fotos, Pausen — ohne dass du etwas tun musst. Öffne die App später und sieh dir an, wie dein Jahr auf der Straße wirklich aussah.

**Section 2 (privacy):**

> Deine Fahrten bleiben standardmäßig auf deinem iPhone. Kein Konto erforderlich. Optionale Cloud-Synchronisation, falls du deine Daten auf einem zweiten Gerät brauchst — und auch dann entscheidest du, was hochgeladen wird. Vollständig Open Source, inklusive Backend.

**Section 3 (wedge):**

> Die meisten Reise-Apps sind für den einen großen Urlaub gebaut. TripTrack ist für die Fahrten, die du jedes Wochenende ohne nachzudenken machst. Die Fahrt zur Hütte. Der Weg zu deinen Eltern. Die Lieblingsstrecke am Sonntagmorgen. Sie summieren sich zu etwas — und jetzt kannst du es sehen.

---

## Что НЕ говорим в копирайте

Anti-patterns которые роняют conversion в DACH-аудитории:

- ❌ "Best", "#1", "ultimate", "revolutionize" — App Store reviewers и немцы punish это одинаково
- ❌ "AI-powered" — anything AI-suffix devalues serious DACH consumers
- ❌ "Social network for road trips" — социальное у нас opt-in, не основной hook
- ❌ "No subscriptions ever" — пока правда, но не загоняй себя в угол на будущее
- ❌ "100% privacy" — абсолютный claim юристы и privacy-нерды разорвут
- ❌ "Replaces Google Timeline" — direct comparison invites backlash от Google-фанатов
- ✅ "Private by default, optional sync" — конкретно и проверяемо

---

## Decision log

| Дата | Решение | Reasoning |
|---|---|---|
| 2026-05-19 | Wedge: weekend-trips vs gap-year | Из ресёрча Polarsteps positioning + Drive2 evidence про повторяющиеся маршруты |
| 2026-05-19 | Privacy = entry criterion не USP | DACH market — privacy is gating, не selling. USP — auto-detect + edit-any-point |
| 2026-05-19 | Open source — credibility не acquisition | Devs не road-trippers; OSS работает на HN-launch и blogger pitch, не на App Store rank |
| 2026-05-19 | Не делаем Strava-for-roadtrips (B) | Требует видео-контент, ROI хуже |
