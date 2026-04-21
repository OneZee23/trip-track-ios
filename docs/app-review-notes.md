# App Store Review Notes — TripTrack v0.6.0

Paste the relevant section into App Store Connect → **App Review Information** → **Notes** when submitting the build.

---

## English (default)

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

## Russian (for RU App Store submissions)

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
