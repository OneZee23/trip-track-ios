# App Store Review Notes — TripTrack

Paste the relevant section into App Store Connect → **App Review Information** → **Notes** when submitting the build. Use the current-submission section; the older sections stay as a record of what was said for earlier builds.

---

## v0.6.4 — vehicle passport (current submission)

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
• Archive — a vehicle can be archived by the user; new trips are never recorded
  onto an archived or sold vehicle. Nothing is archived automatically.

USER-GENERATED CONTENT AND MODERATION
0.6.4 adds three new stranger-visible surfaces, all optional and all off or
owner-controlled:
• Free text — the vehicle's name, an optional one-line "about", and make/model
  chosen from a built-in catalogue or typed.
• Photos of the vehicle. They are uploaded to our storage only when Cloud Sync
  is enabled, which is OFF by default; with it off they never leave the device.
• An optional registration plate, hidden by default and shown only if the owner
  turns it on.
Each is covered by the existing report-and-block flow: any vehicle or vehicle
photo can be reported from the same menu as a trip or a profile, and blocking a
user hides their garage entirely, in both directions. Reports reach the same
queue as the existing ones and are actioned within 24 hours, per 1.2.

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
пассажир», архив. Три новых поверхности с пользовательским контентом — имя и
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
• Report — on every public profile, every feed card and every trip. Eight reasons:
  spam, harassment, hate, nudity, violence, illegal, impersonation, other.
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
