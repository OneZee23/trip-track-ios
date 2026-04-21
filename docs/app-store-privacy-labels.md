# App Store Connect — Privacy Labels

Справка по заполнению **App Privacy** раздела в App Store Connect при сабмите TripTrack. Должно совпадать с `PrivacyInfo.xcprivacy` и `docs/privacy-policy.html`.

## Data Types Collected

На вопрос "Do you or your third-party partners collect data from this app?" — **Yes**.

### Location
- [x] **Precise Location**
  - Used for: App Functionality
  - Linked to user? **Yes** (когда signed-in + cloud sync ON)
  - Used for tracking? **No**
- [x] **Coarse Location**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**

### Contact Info
- [x] **Name**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
  - Optional collection (только если пользователь согласился поделиться именем при Sign in with Apple)
- [x] **Email Address**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
  - Optional (Apple hide-my-email поддерживается)

### Identifiers
- [x] **User ID**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
  - Описание: Apple subject + account UUID
- [x] **Device ID**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
  - Описание: локально сгенерированный UUID, identifying device, not advertising

### User Content
- [x] **Photos or Videos**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
- [x] **Other User Content**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
  - Описание: названия поездок, заметки, профили машин, отображаемое имя в социальных функциях

### Customer Support
- [x] **Customer Support**
  - Used for: App Functionality
  - Linked to user? **Yes**
  - Used for tracking? **No**
  - Описание: abuse reports (в рамках in-app Report) — хранятся со связью с reporter/target для модерации

## Что НЕ собираем (все UNCHECKED в App Store Connect)

- Financial Info
- Health & Fitness
- Contacts
- Browsing History
- Search History
- Purchase History
- Audio Data
- Gameplay Content
- Credit Info
- Other Financial Info
- Physical Address
- Phone Number
- Sensitive Info (race, religion, sexual orientation, political opinions, pregnancy, disability, precise health, genetic, biometric)
- **Advertising Data** (ничего)
- **Product Interaction** (ничего)
- **Performance Data** (crash data не собираем)
- **Other Diagnostic Data** (логи только локальные, экспорт по инициативе пользователя)

## Privacy Practices Summary

Получится примерно такой label при публикации:

> **Data Linked to You**
> Data collected from this app and linked to your identity:
> - Location
> - Contact Info
> - Identifiers
> - User Content
>
> **Data Not Collected**
> The developer does not collect any data from this app for tracking purposes.

Это **нормальная** privacy label для location-based apps. Не алармирующая.

## Privacy Policy URL

В поле **Privacy Policy URL**:
- После публикации docs на GitHub Pages: `https://onezee23.github.io/trip-track-ios/privacy-policy.html`
- Если настроишь custom domain (trip-track.app): `https://trip-track.app/privacy`

## Что ещё проверить перед сабмитом

1. **Age Rating**: новый questionnaire Apple (обязателен с 31 января 2026, уровни 4+/9+/13+/16+/18+).
   - User-generated content: **Yes** (публичные профили, лента друзей, реакции)
   - Unrestricted Web Access: **No**
   - Messaging or Chat: **No** (нет DM и комментов)
   - Mature/Suggestive/Horror/Violence/Alcohol/Gambling/Medical/Profanity: **No**
   - Ожидаемый рейтинг: **13+**. Polarsteps с похожим набором = 4+, но при наличии UGC безопаснее целиться в 13+.
2. **Custom EULA**: App Store Connect → App Information → License Agreement → выбери "Custom" и вставь содержимое `docs/terms.html`. Guideline 1.2 требует custom EULA с zero-tolerance clause для UGC apps.
3. **Export Compliance**: uses standard iOS crypto → declare via App Store Connect (exempt от EAR 740.17(b)).
4. **Content Rights**: подтверди что все визуалы твои (Pixel Car art, иконка)
5. **Intellectual Property**: пройди checklist на товарный знак "TripTrack" + "ROAD TRIP TRACKER"
6. **App Review Information**:
   - Demo account: подготовить Apple ID для review team (критично — иначе revew fail на проверке SIA)
   - Notes: использовать текст из `docs/app-review-notes.md`
7. **Build Artefacts**: убедись что `PrivacyInfo.xcprivacy` попал в bundle (Xcode → target → Copy Bundle Resources)
