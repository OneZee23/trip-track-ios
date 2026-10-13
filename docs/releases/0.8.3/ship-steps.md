# 0.8.3 — что делает владелец, по шагам

Состояние на 29 сентября 2026, сверено командами, а не по памяти:

- iOS: ветка `release/0.8.3`, версия **0.8.3 (66)**, рабочее дерево чистое.
  Ветки `release/0.8.3` на `origin` **НЕТ вовсе** — первый пуш будет с `-u`.
- Долг: `origin/release/0.8.2` стоит на `4a008ec6`, локально ветка ушла на
  **44 коммита** вперёд (голова `e10be60f`); тега `v0.8.2` нет ни локально, ни
  на сервере. `release/0.8.2` целиком входит в `release/0.8.3` — проверено
  `git merge-base --is-ancestor`.
- Бэкенд: `master`, **2 незапушенных коммита** (`fad3069`, `b7c9f05`).
  `.gitlab-ci.yml` собирает и деплоит **автоматически на пуш в master** —
  отдельной команды деплоя нет.

---

## ШАГ 1. Бэкенд — ПЕРВЫМ, до всего остального

Пока миграций нет на проде, приложение 0.8.3 отобьёт апсерт поездки у всех, у
кого включена приватная зона (координата отметки уезжает `null`, а колонка
пока `NOT NULL`).

```bash
cd ~/OneZeeProjects/trip-track-backend
git push origin master
```

Пуш в `master` запускает пайплайн `build → deploy`: собирается образ,
уезжает в реестр, дроплет делает `docker compose pull && up -d` и ждёт
healthcheck. Смотреть прогон в GitLab, вкладка CI/CD → Pipelines.

**Проверка после зелёного пайплайна:**

```bash
ssh <пользователь>@<адрес прод-дроплета>
cd /opt/trip-track-backend
docker compose ps                      # trip-track-backend должен быть healthy
docker compose logs --tail=120 | grep -iE "migration|error"
grep -E '^DB_SYNC|^DB_MIGRATE' .env    # чем именно поедет схема
```

Схема доезжает одним из двух путей, и оба рабочие:

- `DB_SYNC=true` — TypeORM приводит схему к сущностям на старте. По нашим
  заметкам на проде стоит именно это.
- `DB_MIGRATE=true` — прогоняются миграции `AddVehiclePowertrain` и
  `RelaxCheckpointCoordinates`.

**Если оба `false`** — схема не поедет, и это надо сказать мне: тогда
включаем `DB_MIGRATE=true`, `docker compose up -d`, и дальше как обычно.

Контейнер поднялся healthy — значит старт не упал, то есть схема применилась.
Упавшая миграция роняет процесс, и healthcheck этого не пропустит.

---

## ШАГ 2. Репозиторий iOS

### 2а. Долг 0.8.2 — сборка уже на ревью, а истории в репозитории нет

```bash
cd ~/OneZeeProjects/trip-track
git push origin release/0.8.2
git tag v0.8.2 e10be60f
git push origin v0.8.2
```

### 2б. Ветка 0.8.3

Ветки на сервере ещё нет, поэтому `-u`:

```bash
git push -u origin release/0.8.3
```

**Тег `v0.8.3` ставим ПОСЛЕ того, как архив уехал в App Store Connect** (шаг
3): если при сборке что-то всплывёт и появится ещё коммит, тег окажется не на
том, что уехало в стор.

---

## ШАГ 3. Сборка и выгрузка

Проект уже сгенерирован, версия в нём **0.8.3 (66)** — `xcodegen` запускать не
надо.

1. Открыть `TripTrack.xcodeproj`.
2. Схема **TripTrack**, устройство — **Any iOS Device (arm64)**.
3. **Product → Archive**.
4. В Organizer: **Distribute App → App Store Connect → Upload**.
5. Дождаться письма «App Store Connect has finished processing» (5–20 минут).

Сверка версии, если захочется убедиться до выгрузки:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  -c "Print :CFBundleVersion" \
  ~/Library/Developer/Xcode/DerivedData/TripTrack-*/Build/Products/Release-iphoneos/TripTrack.app/Info.plist
```

Ожидается `0.8.3` и `66`.

### После выгрузки — тег

```bash
cd ~/OneZeeProjects/trip-track
git tag v0.8.3 release/0.8.3
git push origin v0.8.3
```

---

## ШАГ 4. Карточка в App Store Connect

Всё готовое лежит в `docs/releases/0.8.3/`.

1. My Apps → TripTrack → **+ Version or Platform** → `0.8.3`.
2. **«What's New»** — из `app-store.md`, во **ВСЕ ДВЕНАДЦАТЬ** локалей.
   Сабмит 0.6.2 отклонили ровно за одну пропущенную.
   В слот **Finnish** кладётся ФИЛИППИНСКИЙ текст — так было в 0.6.3–0.8.2, не
   переименовывать.
3. **Build** — выбрать 66.
4. **App Review Information → Notes** — секция «v0.8.3 … (current submission)»
   из `docs/releases/app-review-notes.md`, целиком из блока с тройными
   кавычками.
5. Скриншоты, ключевые слова, описание — **не трогать**, не менялись.
6. In-App Purchase к этой версии **не прикреплять**: монетизация выключена
   флагом, товаров в сборке нет.
7. **Add for Review → Submit**.

---

## ШАГ 5. Канал

Текст и промпт картинки — `docs/releases/0.8.3/tg-post.md`. Публиковать после
того, как Apple одобрит и версия выйдет, — как делали раньше.

---

## ШАГ 6. Параллельно — то, что блокирует 0.8.4

Начинать НЕ дожидаясь ревью 0.8.3: проверка банковских и налоговых данных
идёт днями.

**App Store Connect → Business → Paid Apps.** Нужен статус **Active**:
соглашение принято, банковские реквизиты заведены, налоговая форма заполнена.
Пока не «Active», товары создать физически нельзя.

Дальше — `docs/releases/0.8.4/app-store-connect-setup.md`: группа `pro`, два
тарифа (19,99 € / 2,99 €, неделя бесплатно только у годового), три чаевых.
Идентификаторы копировать буква в букву — `productID` в ASC не
переименовывается никогда.
