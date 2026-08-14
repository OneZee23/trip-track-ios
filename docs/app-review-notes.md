# App Store Review Notes — TripTrack

Paste the relevant section into App Store Connect → **App Review Information** → **Notes** when submitting the build. Use the current-submission section; the older sections stay as a record of what was said for earlier builds.

---

## v0.6.0 — redesign + companions (current submission)

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
