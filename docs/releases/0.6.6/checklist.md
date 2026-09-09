# 0.6.6 «Путешествие» — что нажать

Каркас, заполняется по ходу версии. Порядок тот же, что в 0.6.5: **бэкенд раньше
сабмита**, тексты стора во все 12 локалей, рейтинг 13+ уже стоит.

| Что | Где | Состояние |
|---|---|---|
| iOS `release/0.6.6` | github.com/OneZee23/trip-track-ios | от `master` 4d77115 (0.6.5) |
| Бэкенд | gitlab.com/triptrack1/triptrack-backend | модуль `journeys`, миграция `1788600000000-AddJourneys` |
| Версия | `project.yml` | 0.6.6, билд **58** |
| Схема CoreData | `TripTrack.xcdatamodeld` | **v12** — `JourneyEntity`; после добавления версии `xcodegen generate` ДВАЖДЫ |
| Спека | `docs/superpowers/specs/2026-09-08-journeys-design.md` | решения приняты 8 сен |
| План | `docs/superpowers/plans/2026-09-09-journeys-066.md` | — |
| Макеты | Figma `8AlZTuVAZueffBsXs0QBuz`, страница `2848:1307` | A и C — канон |

## 1. Бэкенд — сначала он
- [ ] Миграция `AddJourneys` идемпотентна (`IF NOT EXISTS`), пуш в `master`, CI выкатит
- [ ] Проверка: `POST /journeys/upsert` и секция `journeys` в `/sync/pull`

## 2. iOS
- [ ] Миграция v11 → v12 проверена тестом на v11-сторе
- [ ] Путешествие с телефона доехало до второго устройства
- [ ] `LocalDataWipe` и удаление аккаунта стирают `JourneyEntity` (связи нет — явно)

## 3. Сабмит
- [ ] `xcodegen generate` дважды, `.xccurrentversion` = v12
- [ ] What's New ×12 в `app-store.md`, заметки ревьюеру в `../app-review-notes.md`
- [ ] Скриншоты: экран путешествия — лучший кадр релиза

## 4. После аппрува
- [ ] Тег `v0.6.6`
- [ ] Пост в канал `tg-post.md`
