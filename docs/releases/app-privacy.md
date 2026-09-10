# App Privacy для TripTrack — готовая анкета (10 сентября 2026)

**Вердикт:** «Data Not Collected» неверно однозначно и было неверно ещё до Sentry. Отмечать надо **14 типов данных в 7 категориях**, все — **Linked to You**, **Tracking = No** во всех. Анкету можно исправить сегодня, без сборки и без апдейта: Apple прямо разрешает («You may update your answers at any time, and you do not need to submit an app update in order to change your answers» — [app-privacy-details](https://developer.apple.com/app-store/app-privacy-details/)).

---

## 0. Что подтверждено по документации Apple сегодня

Проверено на живых страницах, а не по памяти:

| Что | Состояние на 10.09.2026 |
|---|---|
| Состав анкеты | **Не менялся**: 16 категорий / 32 типа — Contact Info, Health & Fitness, Financial Info, Location, Sensitive Info, Contacts, User Content, Browsing History, Search History, Identifiers, Purchases, Usage Data, Diagnostics, Surroundings, Body, Other Data |
| Цели (purposes) | **Ровно шесть**: Third-Party Advertising, Developer's Advertising or Marketing, Analytics, Product Personalization, App Functionality, Other Purposes. Проверено по машинному индексу Apple (`NSPrivacyCollectedDataTypePurposes`) — **значения «Account Management» НЕ существует** (важно, см. §5) |
| «Collect» | «transmitting data off the device in a way that allows you and/or your third-party partners to access it **for a period longer than what is necessary to service the transmitted request in real time**» |
| «Linked to You» | «Data collected from an app is often linked to the user's identity, unless specific privacy protections are put in place **before collection** to de-identify or anonymize it… **'Personal Information' and 'Personal Data', as defined under relevant privacy laws, are considered linked to the user**» |
| «Tracking» | линковка с **Third-Party Data** ради рекламы/измерения рекламы либо передача **data broker**. У нас ни того, ни другого (грепом: `AppTrackingTransparency`, `AdSupport`, `advertisingIdentifier` — **ноль вхождений**) |
| Данные фреймворков Apple | «If you collect data about your app from Apple frameworks or services, you should indicate what data you collect and how you use it. **You are not responsible for disclosing data collected by Apple.**» |
| Ответственность за SDK | «You need to identify all of the data **you or your third-party partners** collect… 'Third-party partners' refers to analytics tools, advertising networks, **third-party SDKs**…» |
| Только на устройстве | «Data that is processed only on device is not 'collected' and does not need to be disclosed… If you derive anything from that data and send it off device, the resulting data should be considered separately» |

---

## 1. АНКЕТА — кликать сверху вниз

ASC → App → **App Privacy** → Edit → первый вопрос «Do you or your third-party partners collect data from this app?» → **Yes**.
Дальше по сетке категорий. Tracking у **всех** = **No**.

| # | Категория / тип (как в ASC) | Отмечать | Цели (purposes) | Linked | Track | Чем доказано (файл:строка) |
|---|---|---|---|---|---|---|
| 1 | Contact Info → **Name** | ✅ **ДА** | App Functionality | **Yes** | No | `displayName` → `account.display_name`: `AuthService.swift:644-645`, `account.entity.ts:17-18`. Уходит ВСЕГДА после входа, не зависит от Cloud Sync (`AuthService.swift:227`) |
| 2 | Contact Info → **Email Address** | ✅ **ДА** | App Functionality | **Yes** | No | claim `email` внутри Apple identityToken → `account.email`: `AuthService.swift:156-161`, `apple-auth.service.ts:91`, `auth.service.ts:43`, `account.entity.ts:14-15`. Hide-My-Email релей — тоже email |
| 3 | Contact Info → Phone Number | ❌ нет | — | — | — | Нигде не запрашивается и не отправляется |
| 4 | Contact Info → **Physical Address** | ❌ **нет** | — | — | — | Дом — только `UserDefaults` на телефоне, 8 мест использования, ни одного сетевого: `SettingsManager.swift:109-122`. Ни в одном payload-типе `Models/Sync/*` поля дома нет |
| 5 | Contact Info → Other User Contact Info | ❌ нет | — | — | — | — |
| 6 | Health & Fitness → **Fitness** | ❌ **нет** | — | — | — | `CMMotionActivityManager` есть (`MotionDetector.swift:8`), но результат нужен только для автозапуска записи и **устройство не покидает**. Apple: on-device ≠ collect |
| 7 | Health & Fitness → Health | ❌ нет | — | — | — | HealthKit не подключён |
| 8 | Financial Info → **Payment Info** | ❌ **нет** | — | — | — | StoreKit-«чаевые» (`TipJarService.swift`), платёж вне приложения, чек на наш сервер не уходит (грепом по бэкенду: `receipt/storekit/appAccountToken` — ноль). Дословно у Apple: «it is not collected and does not need to be disclosed» |
| 9 | Financial Info → Credit / Other | ❌ нет | — | — | — | — |
| 10 | Location → **Precise Location** | ✅ **ДА** | App Functionality | **Yes** | No | Точки трека: широта/долгота/высота/скорость/курс/время, до 3 точек в секунду — `TrackPointPayload.swift:3-13` → `track_point` (`track-point.entity.ts:18-26`), привязка `trip.account_id` |
| 11 | Location → **Coarse Location** | ✅ **ДА** | App Functionality, **Product Personalization** | **Yes** | No | `trip.region` (город/область из геокодера) — `TripSyncPayload.swift:35-83`, `trip.entity.ts`. Product Personalization — потому что **регионы своих поездок (включая приватные) подбирают «кого показать» в Discover**: `trip-track-backend/src/modules/social/social.service.ts:1646-1670` + `:1601-1614` |
| 12 | Sensitive Info | ❌ нет | — | — | — | Не собираем и не выводим (расу, ориентацию, здоровье и т. п.). См. спорное §4.7 |
| 13 | **Contacts** | ❌ **нет** | — | — | — | `import Contacts` / `CNContactStore` — **ноль вхождений**. Адресную книгу не читаем. Граф подписок создаётся внутри приложения, покрыт Product Interaction (см. спорное §4.5) |
| 14 | User Content → Emails or Text Messages | ❌ нет | — | — | — | Личных сообщений в приложении нет |
| 15 | User Content → **Photos or Videos** | ✅ **ДА** | App Functionality | **Yes** | No | Байты снимков → наш сервер → R2, ключ содержит id аккаунта: `R2PhotoStorage.swift:62-89`, `photos.service.ts:89`; снимки машин — `vehicle-photos.service.ts:67` |
| 16 | User Content → Audio Data | ❌ нет | — | — | — | — |
| 17 | User Content → Gameplay Content | ❌ нет | — | — | — | Уровни/XP — не игровой контент, ушли в Other Usage Data (#25) |
| 18 | User Content → **Customer Support** | ❌ **нет** | — | — | — | Обращений в поддержку в приложении нет; отладочные логи уходят **через share sheet по выбору человека** (`DebugLogsView.swift:209`, `DebugLogExporter.swift:69`) и к нам не попадают. Текст жалоб покрыт #19 |
| 19 | User Content → **Other User Content** | ✅ **ДА** | App Functionality | **Yes** | No | Название и описание поездки (`TripSyncPayload.swift:35-83`), подпись фото (`:3-16`), имя отметки (`:19-33`), имя путешествия (`JourneySyncPayload.swift:3-20`), «о машине» и госномер (`VehicleSyncPayload.swift:3-60`), комментарии (`SocialDTOs.swift:705-709`), текст жалобы до 500 знаков (`SocialDTOs.swift:676-681`) |
| 20 | **Browsing History** | ❌ нет | — | — | — | Веб-контента вне приложения не отслеживаем |
| 21 | **Search History** | ❌ **нет** | — | — | — | Запрос уходит на `/social/search` (`DiscoverView.swift:363-366`), но сервер его **не хранит и не логирует**: `social.controller.ts:123-127` → `social.service.ts:1503-1520` (только SQL-выборка), а access-лог пишет лишь `method/url/status/user_id` без тела (`logger.module.ts:75-90`). По определению Apple «collect» это не сбор |
| 22 | Identifiers → **User ID** | ✅ **ДА** | App Functionality, **Analytics** | **Yes** | No | Apple `sub` → `account.apple_subject` (`auth.service.ts:32`); `accountId` в каждом событии Sentry (`SentryService.swift:132-142`, ставится `AuthService.swift:183`, `:967`); `user_id` в каждой строке прод-лога (`logger.module.ts:61-64`) |
| 23 | Identifiers → **Device ID** | ✅ **ДА** | App Functionality, Analytics | **Yes** | No | `localUserId` → `device.local_user_id` (`AuthService.swift:158`, `device.entity.ts:19-20`); APNs-токен (`PushNotificationManager.swift:96-111`); `device_app_hash` = SHA-1 от IDFV в событиях Sentry (`SentryCrashMonitor_System.m:389-431`); installation-UUID Sentry (`SentryInstallation.m:26-60`) |
| 24 | Purchases → Purchase History | ❌ нет | — | — | — | См. #8 — историю покупок не получаем и не храним |
| 25 | Usage Data → **Product Interaction** | ✅ **ДА** | App Functionality, Analytics, Product Personalization | **Yes** | No | Реакции (`SocialFeedStore.swift:445`), подписки (`SuggestedUsersCarousel.swift:137`), прочтения уведомлений (`/notifications/mark-read`) — хранятся с account_id. **Плюс** сессии Sentry (счётчик запусков): `enableAutoSessionTracking` приходит включённым (`SentryOptions.m:83`) и у нас не выключен |
| 26 | Usage Data → Advertising Data | ❌ нет | — | — | — | Рекламы нет |
| 27 | Usage Data → **Other Usage Data** | ✅ **ДА** | App Functionality | **Yes** | No | Геймификация: уровень, XP, текущая и лучшая серия, дата последней поездки → `account.profile_level/profile_xp/current_streak/best_streak` (`AuthService.swift:648-651`, `account.entity.ts:38-48`, `SettingsSyncPayload.swift:14-18`) |
| 28 | Diagnostics → **Crash Data** | ✅ **ДА** | App Functionality | **Yes** | No | Sentry: `SentrySDK.start` (`SentryService.swift:43`) из `TripTrackApp.swift:47`; краш-хендлер по умолчанию YES (`SentryOptions.m:68`). **Linked = Yes именно из-за** `setAccount(id:)` (`SentryService.swift:132-142`) |
| 29 | Diagnostics → **Performance Data** | ✅ **ДА** | App Functionality, Analytics | **Yes** | No | Транзакции 10 % (`SentryService.swift:53`), App Hang (`SentryOptions.m:124`) и Watchdog Termination (`:85`) — оба включены умолчанием и не выключены; всё с тем же `user.id` |
| 30 | Diagnostics → **Other Diagnostic Data** | ✅ **ДА** | App Functionality | **Yes** | No | Контекст устройства/ОС/culture (модель, память, заряд, локаль, **часовой пояс**) — `SentryClient.m:1015-1046`; сетевые крошки и события 5xx (`SentryService.swift:76-77`, `:107`) |
| 31 | Surroundings → Environment Scanning | ❌ нет | — | — | — | Не visionOS, ARKit нет |
| 32 | Body → Hands / Head | ❌ нет | — | — | — | — |
| 33 | Other Data → **Other Data Types** | ✅ **ДА** | App Functionality | **Yes** | No | Паспорт машины: марка, модель, год, кузов, **госномер** + флаг видимости, пробег, стикеры, расходы, дата продажи — `VehicleSyncPayload.swift:3-60`, `vehicle.entity.ts:19-113`. В поле описания в ASC написать: «Vehicle profile (make, model, year, licence plate, odometer) and app preferences» |

**Итого отмечено: 14 типов. Linked to You — все 14. Used to Track You — ни одного.**

### Если ревьюер спросит — короткие ответы

- **«Почему Precise Location — App Functionality, а не Analytics?»** Трек нужен, чтобы показать маршрут и восстановить его на втором телефоне; ни ранжирования, ни рекламы по нему нет. Единственное исключение — регион (Coarse) в подборе людей в Discover, и он объявлен как Product Personalization.
- **«Почему Crash Data Linked, если Sentry говорит Not Linked?»** Манифест Sentry описывает голый SDK. Мы сами кладём `accountId` в scope (`SentryService.swift:132-142`) — значит у нас связано.
- **«Кто третьи стороны?»** Sentry (диагностика, ЕС-регион `ingest.de.sentry.io`) и Cloudflare R2 (хранение снимков). Рекламных и аналитических SDK нет, ATT не используется.
- **«Есть ли удаление аккаунта в приложении?»** Да, `/auth/delete-account`, стирает Postgres и R2 (`auth.service.ts:331-391`). Требование 5.1.1(v) закрыто — **кроме одной строки, см. §4.4**.

---

## 2. Три условия отправки — их спрашивают, и путать нельзя

Для анкеты условие роли не играет (декларируется всё, что уходит хоть в одном сценарии), но для ревьюера и для политики — играет:

1. **Всегда после входа**, без всяких тумблеров: вход, профиль, пуш-токен (`SyncEnqueuer.swift:12` — гейт только на `isSignedIn`; профиль идёт мимо очереди — `AuthService.swift:227`).
2. **Только при включённой Cloud Sync**: машины, снимки машин, путешествия, настройки и **ВСЕ** поездки, включая приватные (`SyncEnqueuer.swift:44` → «if cloudSyncEnabled { return true }», `:84-88` — «Personal metadata — never leaves device without full sync ON»). По умолчанию Cloud Sync **выключена** (`SettingsManager.swift:33`).
3. **Только при публикации поездки**: поездка с `isPrivate == false` и её снимки уезжают даже при выключенном Cloud Sync (`SyncEnqueuer.swift:60`, `:80-81`). Новые поездки по умолчанию приватны (`TripManager.swift:152`).
4. **Без входа вообще** — ровно один поток: лист ожидания «Клубов» шлёт UUID установки при каждом открытии вкладки (`GroupsWaitlistStore.swift:60-69`, `requiresAuth: false`).

---

## 3. Диагностика уезжает БЕЗ согласия и без тумблера

Sentry стартует до всего остального (`TripTrackApp.swift:47`), от Cloud Sync не зависит, спросить человека негде. Для App Privacy это нормально (декларировали — и хватит), для GDPR — слабое место (§6). Развилка владельца на один коммит:

- **Оставить как есть** → в анкете обязателен **Product Interaction** (счётчик запусков — это Usage Data, а не Diagnostics).
- **`options.enableAutoSessionTracking = false`** → Product Interaction по линии Sentry отпадает, **но остаётся** по линии реакций/подписок (#25), так что галочку всё равно ставить. Потеряется crash-free rate. **Вывод: выключать нет смысла, декларируйте.**

---

## 4. Спорные места и как их трактовать

**4.1. «Точные координаты уходят только при включённой синхронизации — декларировать?»**
**ДА, обязательно.** Apple: «Please disclose all data collected from your app, **unless it meets ALL of the criteria** outlined in the Optional Disclosure section», и там же: «Data types must meet **all** criteria… If a data type collected by your app meets some, but not all, of the above criteria, **it must be disclosed**». Критерии требуют, чтобы сбор происходил «only in infrequent cases that are **not part of your app's primary functionality**» и чтобы человек «**affirmatively chooses to provide the data for collection each time**». Трек — это и есть основная функция приложения, и галочка ставится один раз, а не на каждую поездку. Освобождение не работает. То же и для приватных поездок: при включённом Cloud Sync они уезжают все (`SyncEnqueuer.swift:44`).

**4.2. «Обратное геокодирование через Apple — это сбор данных разработчиком?»**
**НЕТ, в анкете не объявляется.** Apple дословно: «**You are not responsible for disclosing data collected by Apple**». Координаты, уходящие в `CLGeocoder` (`TripManager.swift:537, 834, 868, 935`) и в тайлы MapKit (`MapSnapshotPreview.swift:163-177`), нам недоступны. **НО граница проходит по результату**: название города, которое геокодер вернул, мы сохраняем в `trip.region` и синхронизируем — это уже наши данные, и они объявлены как Coarse Location (#11). Отдельно: **в политике сейчас написана неправда** — «Reverse geocoding … is performed via Apple MapKit **on your device**». `CLGeocoder` — сетевой сервис Apple, координаты уходят с телефона. Формулировку надо чинить (§6).

**4.3. «Мы же срезаем EXIF» — это только про файл.**
В байтах JPEG GPS действительно нет (`R2PhotoStorage.swift:11-26`, плюс оба реальных пути грузят уже пересжатые байты). Но **время съёмки и координата кадра едут рядом обычными полями JSON**: `capturedAt`, `exifLatitude`, `exifLongitude` (`TripSyncPayload.swift:13-15`, `:128-130`) → колонки `trip_photo.captured_at/exif_latitude/exif_longitude` (`trip-photo.entity.ts:23-27`, пишет `trips.service.ts:411-413`). Для анкеты это ничего не меняет (Precise Location уже отмечена), **для политики — прямая неправда, которую надо убрать**.

**4.4. Лист ожидания «Клубов» — единственный поток без согласия и без каскада.**
UUID установки уходит при **каждом** открытии вкладки, даже гостем (`GroupsWaitlistStore.swift:60-69`). Строка `group_waitlist` **намеренно** без FK и каскада (`group-waitlist.entity.ts:32-37`) — то есть переживает «удалить аккаунт безвозвратно». Это (а) обязывает поставить Device ID даже гипотетическому пользователю без аккаунта, (б) **противоречит §9 политики** («Erasure — permanently delete… all associated server-side data») и требованию 5.1.1(v). **Рекомендация:** до сабмита добавить удаление строк `group_waitlist` по `device_id` в `/auth/delete-account`, либо дописать исключение в политику. Первое честнее и дешевле.

**4.5. Contacts и «социальный граф».** Формулировка Apple включает «or social graph», и подписки формально под неё подводятся. **Не отмечать**: категория исторически про импорт адресной книги/графа **с устройства**, а мы адресную книгу не читаем вовсе (`CNContactStore` — ноль вхождений), граф создаётся внутри приложения и уже покрыт Product Interaction. Отметка Contacts, наоборот, ввела бы в заблуждение («приложение читает мои контакты»).

**4.6. `device_app_hash` — IDFV-производная, которую наша чистка не снимает.**
Чистит по именам полей (`SentryService.swift:154-158` + `PIISensitiveKeys.swift:14-33`), а `device_app_hash` в списке нет — доезжает в контексте `app` вместе с `user.id`. Именно поэтому Device ID отмечен. **Одна строка в `PIISensitiveKeys.all` убирает его** — но галочку Device ID это не снимет (её держат `localUserId` и APNs-токен).

**4.7. Sensitive Info / «данные о здоровье» по закону штата Вашингтон.** GPS может случайно показать визит в клинику. Для анкеты Apple это **не** Sensitive Info (там про расу, ориентацию, религию и т. п.) — не отмечать. В политике блок про MHMDA уже есть и он корректный, трогать не надо.

**4.8. IP-адрес на приёмнике Sentry.** `sendDefaultPii = false` выставлен явно (`SentryService.swift:69`), но сохранит приёмник IP или обнулит — решает **настройка организации на sentry.io**, а не код. По GDPR IP — персональные данные. **Проверить в кабинете** (Settings → Security & Privacy → «Prevent Storing of IP Addresses»). На анкету не влияет (уже стоят User ID / Device ID), на политику влияет.

**4.9. `UIDevice.current.name`.** Отправляется при каждом входе (`AuthService.swift:159`) в `device.device_name`. Пугает меньше, чем кажется: entitlement `com.apple.developer.device-information.user-assigned-device-name` в `TripTrack.entitlements` **отсутствует** (проверено), значит с iOS 16 приходит родовое «iPhone», а не «iPhone Вани». Отдельной галочки не требует (Name уже стоит). Всё равно дешевле не слать вовсе, чем объяснять.

---

## 5. `PrivacyInfo.xcprivacy` — файл есть, и в нём три ошибки

Файл лежит в бандле и попадает в цель (`TripTrack/PrivacyInfo.xcprivacy`, `project.pbxproj:479`, `:2199`, проверено по собранному артефакту). Это хорошая новость: риска ITMS-91053 «манифеста нет вообще» нет. Плохая — **манифест сейчас противоречит и коду, и будущей анкете**:

1. **Невалидное значение цели, дважды.** В блоках Email и UserID стоит `NSPrivacyCollectedDataTypePurposeAccountManagement`. По машинному индексу Apple допустимых целей ровно шесть, и такой среди них **нет**. Значение либо молча игнорируется, либо ловится валидацией при загрузке. Убрать.
2. **Не хватает шести типов** после Sentry и социальной части: Crash Data, Performance Data, Product Interaction, Device ID, Other User Content, Coarse Location, Other Usage Data, Other Data Types.
3. **`OtherDiagnosticData` стоит `Linked = false`** — после `setAccount(id:)` это неправда, должно быть `true`.
4. Манифест SDK Sentry (`Sentry.framework/PrivacyInfo.xcprivacy`, все три типа `Linked = FALSE`) описывает голый SDK и **нас не освобождает** — карточку заполняет разработчик.
5. **Защитно добавить `NSPrivacyAccessedAPICategorySystemBootTime` с причиной `35F9.1`.** `CACurrentMediaTime()` в восьми местах (`RouteMapView.swift:547,551`; `FingerWatch.swift:27,79`; `FullscreenMapSheet.swift:1026,1071`; `RoutePlaybackController.swift:148,157`) — это обёртка над `mach_absolute_time`. Формулировка 35F9.1 («measure the amount of time that has elapsed between events that occurred within the app… **may not be sent off-device**») ровно наш случай: тайминг анимаций, наружу не уходит. `FileTimestamp` и `DiskSpace` **не добавлять** — совпадающих API нет (`LogArchive.swift:123` берёт `.size`, `PhotoMetadata.swift:80` — `PHAsset.creationDate`, это Photos, не файловая система). Если ITMS-91053 всё же прилетит с именем категории — добавить точечно.

Готовая замена (`NSPrivacyCollectedDataTypes` целиком, `Tracking` везде `false`, `Linked` везде `true`):

| Тип в манифесте | Purposes |
|---|---|
| `…TypePreciseLocation` | AppFunctionality |
| `…TypeCoarseLocation` | AppFunctionality, ProductPersonalization |
| `…TypeEmailAddress` | AppFunctionality |
| `…TypeName` | AppFunctionality |
| `…TypePhotosorVideos` | AppFunctionality |
| `…TypeOtherUserContent` | AppFunctionality |
| `…TypeUserID` | AppFunctionality, Analytics |
| `…TypeDeviceID` | AppFunctionality, Analytics |
| `…TypeProductInteraction` | AppFunctionality, Analytics, ProductPersonalization |
| `…TypeOtherUsageData` | AppFunctionality |
| `…TypeCrashData` | AppFunctionality |
| `…TypePerformanceData` | AppFunctionality, Analytics |
| `…TypeOtherDiagnosticData` | AppFunctionality |
| `…TypeOtherDataTypes` | AppFunctionality |

(Полные строки: префикс `NSPrivacyCollectedDataType`, цели — префикс `NSPrivacyCollectedDataTypePurpose`. Написание `PhotosorVideos` — со строчной «or» — именно такое у Apple, это не опечатка.)

**Соответствие анкете:** после этой правки манифест и карточка совпадают тип в тип — 14 против 14. Сейчас они расходятся дважды: манифест против карточки (6 против 0) и манифест против кода (нет Crash/Performance).

---

## 6. Политика приватности — что чинить

Действующая: `https://onezee23.github.io/trip-track-ios/privacy-policy.html`, «Last updated: April 20, 2026». Русская версия (`privacy-policy-ru.html`, «Обновлено: 20 апреля 2026») зеркальная — **править надо ОБЕ**. И отдельно: остальные одиннадцать языков получают английскую страницу (`AppConfig.swift:35-39`) — для GDPR это не запрет, но немецкому пользователю политика приходит по-английски; стоит знать.

Документ сам по себе сильный (легальные основания, права, американские штаты), но **семь утверждений в нём сейчас неверны**:

| § политики | Что написано | Что на самом деле | Как переписать |
|---|---|---|---|
| 2.1 Guest mode | «**No data leaves the device**» в гостевом режиме | UUID установки уходит при каждом открытии «Клубов» (`GroupsWaitlistStore.swift:60-69`), поисковый запрос уходит гостем (`DiscoverView.swift:363-366`), **Sentry шлёт краши и сессии до входа** | «В гостевом режиме поездки, треки, фото и настройки не покидают устройство. Исключения: диагностика падений (см. §3.5) и, при открытии вкладки «Клубы», случайный идентификатор установки» |
| 3.2 | Синхронизация — «signed-in mode only, **when cloud sync is on**» | Поездка, сделанная публичной, и её снимки уезжают при **выключенном** Cloud Sync (`SyncEnqueuer.swift:60`, `:80-81`) | Добавить третий случай: «поездка, которую вы опубликовали, и её фотографии уходят на сервер даже при выключенной синхронизации» |
| 3.2 / 10 | «Before upload, **all metadata (EXIF, including GPS tags) is stripped**» | Из файла — да; **время съёмки и координата кадра уезжают отдельными полями** и хранятся в колонках (`TripSyncPayload.swift:13-15` → `trip-photo.entity.ts:23-27`) | «Из файла фотографии удаляются все метаданные. Время съёмки и координата кадра, если они были, передаются отдельными полями — они нужны, чтобы поставить снимок на маршрут» |
| **3.5 (нет такого)** | — | Sentry вообще не упомянут | **Дописать раздел** (текст ниже) |
| 4 | «Reverse geocoding … is performed via Apple MapKit **on your device**» | `CLGeocoder` — сетевой сервис Apple, координаты уходят к Apple (`TripManager.swift:537, 834, 868, 935`) | «Определение названий мест выполняется сервисом Apple: координаты передаются Apple как поставщику платформы, нам они в этом обмене недоступны» |
| 6 | «We **do not use analytics SDKs**… no third-party trackers» | Sentry с включённым счётчиком сессий = аналитика аудитории | «Рекламных и трекинговых SDK нет. Используется один диагностический SDK — Sentry (см. §3.5)» |
| 8 | «Deleted trips, photos, vehicles… removed **immediately**» | Мягкое удаление, физическое **через 30 дней** (`cleanup.service.ts:38-62`) | «…помечаются удалёнными сразу и скрываются везде; физически стираются в течение 30 дней» |
| 8 | «If you don't sign in for 3 years, we **may delete** the account» | Код только **логирует** такие аккаунты (`cleanup.service.ts:68-92`) | Либо «мы можем удалить их по нашему решению», либо доделать удаление |
| 9 Erasure | «delete… **all** associated server-side data» | Строка `group_waitlist` переживает удаление (`group-waitlist.entity.ts:32-37`) | Починить код (предпочтительно) или назвать исключение |
| 6 Sub-processors | «Our hosting provider — … the exact name **will be published before the first public release**» | Приложение опубликовано пять релизов назад | Назвать провайдера. И проверить, как описывать российский edge-релей перед франкфуртским бэкендом — это транзит, но в реестр обработки он попадает |

**Готовый блок для §3.5 (перевести в RU-версию слово в слово):**

> **3.5 Diagnostics (crash reporting).**
> The app sends crash reports, app-hang and watchdog-termination events, session start/stop records and a 10 % sample of performance traces to **Sentry** (Functional Software, Inc.), our data processor. Data is ingested and stored in Sentry's **European region** (`ingest.de.sentry.io`); it does not leave the EU.
> Each event carries: your account identifier (a UUID — no name, no email), device model, OS version, free memory, battery level, locale, calendar and time-zone name, a device-and-app hash derived from Apple's identifierForVendor, and a trail of network requests in redacted form (method, status code, and the *shape* of the URL — query strings, fragments and all identifiers inside paths are removed before sending).
> We **do not** send screenshots, view hierarchies, session replays, profiles, request or response bodies, file paths, access tokens, or your home location.
> Legal basis: legitimate interest (GDPR Art. 6(1)(f)) in keeping the app working. Retention: as configured in our Sentry organisation — currently N days. To object, write to privacy@trip-track.app.

Ещё два абзаца, которые стоит дописать:

- **Про дом** (в §3.4 «Local-only data»): «Приблизительное расположение вашего дома **выводится на телефоне** из истории поездок, хранится только в настройках устройства и **никогда не передаётся на наши серверы**. Оно нужно единственно для подсказки «похоже, это было путешествие». Проверяемо по коду: `SettingsManager.swift:109-122`, стирается `wipeJourneyPrivateState()` (`SettingsManager.swift:160-166`). Оговорка честности: настройки устройства попадают в резервную копию iCloud, то есть к Apple, но не к нам.»
- **Про Sentry как под-обработчика** — четвёртой строкой в §6, с указанием ЕС-региона и DPA.

Обязательное по 5.1.1(i): политика должна «Identify what data… the app collects, how it collects that data, and all uses of that data» и подтвердить, что **третьи стороны** дают ту же защиту. Sentry как третья сторона сейчас не назван — это самостоятельный повод для отказа, независимо от анкеты.

---

## 7. Риск сейчас — одной честной строкой

**Отклонение ближайшего сабмита (0.6.6 build 58) я оцениваю как вероятное, а не как «может быть»: расхождение видно машине, а не только человеку** — в бандле лежат два манифеста (`TripTrack/PrivacyInfo.xcprivacy` с шестью типами и `Sentry.framework/PrivacyInfo.xcprivacy` с Crash/Performance), Xcode собирает из них Privacy Report, и он прямо противоречит карточке «Data Not Collected»; это типовой отказ по 5.1.1/5.1.2. **Удаление уже опубликованного приложения только за карточку — редкость** (обычно это следствие жалобы или запроса регулятора), но потенциал наказания в правилах прописан дословно: «Apps that share user data without user consent or otherwise complying with data privacy laws **may be removed from sale and may result in your removal from the Apple Developer Program**» (App Review Guidelines 5.1.2(i)).

**Что делать с уже опубликованными версиями — ничего отзывать не надо.** Карточка App Privacy живёт на уровне приложения, а не версии: исправленные ответы применяются сразу ко всем версиям в Store, и Apple прямо разрешает менять их без апдейта («You may update your answers at any time, and you do not need to submit an app update in order to change your answers»). Порядок действий:

1. **Сегодня, без сборки:** заполнить анкету по таблице §1 в ASC. Это снимает главное расхождение немедленно.
2. **Сегодня же:** выложить исправленную политику (обе языковые страницы, §6) — она статическая, деплой не нужен.
3. **До архива 0.6.6:** починить `PrivacyInfo.xcprivacy` (§5) — иначе Privacy Report сборки снова разойдётся с карточкой, теперь уже в другую сторону.
4. **До архива, две строки кода:** удаление `group_waitlist` при удалении аккаунта (§4.4) и `device_app_hash` в `PIISensitiveKeys` (§4.6). Первое закрывает 5.1.1(v), второе просто уменьшает объём заявленного.
5. **До архива, бэкенд:** `ev.request.url` в `sentry.ts:65-84` не чистится (в пути ездит accountId), а `SENSITIVE_KEYS` (`:16-32`) не знает заголовка `x-access-token`, которым бэкенд авторизует (`jwt-auth.guard.ts:24`). На iOS ровно эту дыру закрыли коммитом `ca16a54` — на сервере не повторили.

**Смягчающее обстоятельство, которое стоит знать:** в уже опубликованных 0.5.5–0.6.5 Sentry фактически молчал (DSN пуст → `SentryService.start()` выходит на первом guard, `SentryService.swift:30-41`), так что диагностика оттуда не уезжала вовсе. Неверной карточка была по другой причине — по аккаунту, почте, треку и фото, — и это тянется с первого релиза с входом через Apple.

**Чего я не проверял и что надо посмотреть в кабинетах, а не в коде:** срок хранения событий и настройку «Prevent Storing of IP Addresses» в организации Sentry; регион серверного `SENTRY_DSN` (в репозитории бэкенда его нет); физическое расположение бакета R2 и имя хостинг-провайдера для §6 политики.

**Sources:** [Apple — App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) · [Apple — Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests) · [Apple — Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) · [App Review Guidelines 5.1](https://developer.apple.com/app-store/review/guidelines/)