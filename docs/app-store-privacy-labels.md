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
  - Описание: названия поездок, заметки, профили машин

## Что НЕ собираем (все UNCHECKED в App Store Connect)

- Financial Info
- Health & Fitness
- Contacts
- Browsing History
- Search History
- Purchase History
- Audio Data
- Gameplay Content
- Customer Support
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

1. **Age Rating**: 17+ (location services collection required)
2. **Export Compliance**: uses standard iOS crypto → declare via App Store Connect
3. **Content Rights**: подтверди что все визуалы твои
4. **Intellectual Property**: пройди checklist на товарный знак "TripTrack"
5. **App Review Information**:
   - Demo account: подготовить Apple ID для review team (или guest mode instructions)
   - Notes: объяснить что cloud sync = opt-in, core functionality работает offline
6. **Build Artefacts**: убедись что `PrivacyInfo.xcprivacy` попал в bundle (Xcode → target → Copy Bundle Resources)
