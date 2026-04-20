# Compliance Roadmap

Дорожная карта юридического compliance для TripTrack. Это чеклист оффлайн-работы — то что я не могу сделать в коде, но ты должен решить/сделать сам (или с юристом) до/после публичного релиза.

⚠️ **Не юридическая консультация.** Финальные решения — с IT-юристом. Здесь — реалистичная карта решений для indie-разработчика в 2026.

## Этап 0: До TestFlight beta (сейчас)

### ✅ Сделано автоматизированно

Всё что ниже уже реализовано в коде и документах:

- [x] Delete Account flow (Apple App Store 5.1.1(v))
- [x] EXIF strip на фото перед загрузкой
- [x] Cloud sync — opt-in (не включено автоматически)
- [x] Privacy Policy + Terms on RU + EN (`docs/privacy-policy*.html`, `docs/terms*.html`)
- [x] `PrivacyInfo.xcprivacy` в bundle
- [x] Onboarding consent (продолжая — соглашаешься с Terms + Privacy)
- [x] Legal links в ProfileView
- [x] Backend logging — без PII, идентификаторы truncated
- [x] Data retention cron (30 дней для soft-deleted, warning для аккаунтов неактивных >3 лет)

### 🔨 Твоя оффлайн-работа перед beta

1. **Email для контакта по приватности** — `privacy@triptrack.app` сейчас заглушка. Варианты:
   - Купить домен `triptrack.app` (~$15/год на Namecheap/Cloudflare) → настроить email forwarder → `privacy@triptrack.app` пересылает тебе
   - Заменить все упоминания `privacy@triptrack.app` на свой gmail (быстро, но менее профессионально и светит личный email)
   - Сделать отдельный Gmail `triptrack.privacy@gmail.com` (бесплатно, компромисс)
   - **Рекомендую**: купить домен (пригодится для сайта и брендинга).

2. **Настроить GitHub Pages**
   - GitHub Settings репозитория → Pages → Source: `master` branch, `/docs` folder
   - После включения документы будут доступны по `https://onezee23.github.io/trip-track-ios/`
   - Поменять при custom domain: `CNAME` файл в `docs/`, ссылки в `AppConfig.privacyPolicyURL`
   - Проверить что все 4 файла доступны: privacy-policy.html, privacy-policy-ru.html, terms.html, terms-ru.html

3. **Решение по email для GDPR/ПДн-запросов**
   - Формально операторы ПДн обязаны отвечать на запросы пользователей в 30 дней
   - Хотя бы автоответ что запрос получен — лучше чем молчание
   - Можно настроить Zapier/IFTTT на Gmail → Telegram bot, чтобы не пропускать

## Этап 1: Публичный релиз в App Store (EN-регионы)

Эти шаги нужны перед тем как делать App Store релиз доступным во всех странах.

1. **Production backend hosting**
   - Сейчас: `192.168.1.73:3003` (твой Mac). Не для продакшн.
   - Варианты для начала:
     - **Hetzner Cloud** (€5-20/мес): Германия или Финляндия. Хорошо для EU. Нарушает 242-ФЗ для РФ юзеров.
     - **DigitalOcean Droplet** ($6-12/мес): США, Сингапур, Лондон, Амстердам, Франкфурт.
     - **Railway / Fly.io** (бесплатный tier → $5+/мес): проще деплой, автоматический SSL, Dockerfile-based.
     - **VK Cloud / Yandex Cloud** (₽600-2000/мес): серверы в РФ, соответствует 242-ФЗ. Сложнее для не-РФ юзеров (latency).
   - **TLS**: Caddy или Traefik как reverse proxy → автоматический Let's Encrypt
   - **Environment variables**: вынеси APPLE_BUNDLE_ID, JWT secret, R2 creds из `.env` в hosted provider's secret storage
   - **Database backup**: дейли pg_dump на S3/R2/B2

2. **App Store Connect заполнение**
   - См. `docs/app-store-privacy-labels.md`
   - Добавить Privacy Policy URL в App Store Connect
   - Добавить Support URL
   - Подготовить screenshots для всех required device sizes (iPhone 15 Pro, iPhone SE, iPad если taкетaем)
   - App Review Information: Sign in demo credentials

3. **Export compliance**
   - При сабмите: "Does your app use encryption?" → Yes, standard iOS encryption
   - Скорее всего exempt (standard HTTPS + iOS crypto)

4. **Age rating**: 17+ (Infrequent/Mild Mature Themes с Frequent/Intense Use of Location Services)

## Этап 2: Запуск на РФ (отдельный этап, отдельные риски)

Открываешь TripTrack для скачивания в российском App Store = попадаешь под 152-ФЗ и 242-ФЗ. Два варианта:

### Вариант A: Соответствие 242-ФЗ (рекомендуется если целишь РФ)

1. **Регистрация в реестре Роскомнадзора как оператор ПДн**
   - Онлайн через Госуслуги, бесплатно, ~30 дней рассмотрение
   - Зарегистрировать можно как физлицо, ИП или ЮЛ
   - Форма уведомления: указать цели обработки, категории субъектов (пользователи приложения), категории данных (имя, email, геолокация, фото)
   - Указать трансграничную передачу (Apple, Cloudflare) — требуется отдельное согласие от пользователя

2. **Хостинг в России**
   - Основная БД — в российском облаке (Yandex Cloud, Selectel, VK Cloud, REG.RU)
   - Cloudflare R2 для фото — нарушает 242-ФЗ. Надо:
     - либо заменить на российский S3-compatible (например Yandex Object Storage)
     - либо оставить R2, но не давать российским юзерам включать cloud sync (сложная geo-ip логика)
   - Реалистичный путь: миграция на Yandex Cloud ($50-100/мес при твоих объёмах)

3. **Обновить Privacy Policy** — добавить что оператор — такое-то физлицо/ИП, серверы в РФ

4. **ИП или самозанятый**
   - Самозанятый: самый простой режим, 4-6% налог, оборот до 2.4M ₽/год, нельзя нанимать сотрудников. Если приложение бесплатное и без рекламы — можешь вообще не платить как физлицо, нет дохода.
   - ИП на УСН 6%: оборот до 200M ₽/год, можно нанимать, страховые взносы (~50k ₽/год). Стоит открывать если планируешь монетизацию.
   - **Для v1.0 бесплатного приложения**: физлицо без ничего. Когда будет выручка (подписка, реклама) — тогда ИП.

### Вариант B: Не таргетить РФ (проще)

1. В App Store Connect **снять регион "Россия"** из списка доступных стран
2. Privacy Policy остаётся как есть (международная)
3. Без регистрации в Роскомнадзоре
4. **Риски**: российские юзеры могут скачать из американского Apple ID; если РКН заметит что сервис targeting РФ пользователей — блокировка. Но для indie-apps с MAU < пары тысяч — вряд ли.
5. Для v1.0 — реалистичный путь. Можно позже "открыть" РФ после соответствия 242-ФЗ.

**Рекомендую**: для MVP — Вариант B. Переходить на Вариант A когда будет команда / инвестор / ясно что РФ-рынок приоритет.

## Этап 3: Рост (10k+ пользователей)

Когда пойдёт рост — дополнительные шаги:

1. **Консультация с IT-юристом** (обязательно)
   - 15-50k ₽ за разбор твоего кейса
   - Проверит политику, условия, правильность регистрации в реестре РКН
   - Найти через Pravoved, Lawhelp, рекомендации

2. **Incident response plan**
   - Что делать если произошла утечка?
   - По 152-ФЗ обязан уведомить Роскомнадзор в 24ч, пользователей в 72ч
   - Написать playbook: кого уведомлять, в каком порядке, шаблоны

3. **Audit безопасности бэкенда**
   - Penetration test: 50-200k ₽
   - OWASP Top 10 checklist
   - Secure code review

4. **DPIA** (Data Protection Impact Assessment) — для GDPR при high-risk processing
   - Location tracking формально high-risk
   - Самостоятельно по ICO template (Великобритания) или с DPO

5. **Официальный DPO (Data Protection Officer)**
   - Нужен только если compulsory under GDPR (public authority, large-scale special category processing) — обычно для indie не нужен
   - Можно nominate себя как DPO в Privacy Policy если хочется формально

6. **Страхование**
   - Cyber liability insurance — дополнительная защита при серьёзной утечке
   - Для indie — не обязательно, но подумать

## Технический долг который стоит закрыть

Эти пункты не срочные но хорошо бы до беты/релиза:

- [ ] **Email infrastructure** для уведомлений об удалении аккаунта, сброса неактивных, incident notifications. Можно Postmark/SendGrid/Resend/Amazon SES ($5-20/мес)
- [ ] **Data export endpoint** — `GET /auth/export` возвращает ZIP со всеми пользовательскими данными (trips JSON + photos). Формально GDPR Art. 20 (portability). Можно отложить до v1.1.
- [ ] **Rate limiting** уже есть на `/auth/login` (5/ч) и `/auth/delete-account` (3/ч). Добавить на `/photos/upload` (100/ч) и `/sync/push` (200/ч) от abuse
- [ ] **Content moderation** для публичных поездок (когда появятся соцфичи) — фильтр названий/описаний на мат и спам
- [ ] **Abuse reporting endpoint** — `POST /social/report` для юзеров стучать на других. Обязательно если будет social feed.
- [ ] **COPPA/детская защита** — в Privacy Policy заявили 17+. Подумать если планируются fam-friendly features.
- [ ] **ApplePrivacyManifest запросы** от третьих зависимостей — у нас нет внешних SDK, это автоматически ОК

## Контрольный чеклист перед сабмитом в App Store

1. [ ] Privacy Policy + Terms захостены и доступны по HTTPS
2. [ ] Email контакт отвечает (или автоответ настроен)
3. [ ] Production backend запущен с TLS
4. [ ] App Store Connect Privacy Labels заполнены (`docs/app-store-privacy-labels.md`)
5. [ ] `PrivacyInfo.xcprivacy` в bundle, Build Settings → Copy Bundle Resources содержит его
6. [ ] Screenshots готовы
7. [ ] App Review Information с demo credentials
8. [ ] Version 0.5.0 (или новее) собирается с production signing
9. [ ] Beta-тесты на 3-5 разных девайсах (разные iOS версии, маленький iPhone SE, Pro Max)
10. [ ] Delete Account проверен end-to-end на реальном backend

## FAQ

**Q: Нужна ли мне лицензия разработчика ФСТЭК если обрабатываю ПДн?**
A: Нет. ФСТЭК-лицензия нужна только операторам критической инфраструктуры и некоторым категориям обработки (медданные, биометрия госучреждений). Indie-app не попадает.

**Q: Обязательна ли двухфакторная авторизация?**
A: Не обязательна для приложений такого класса. Sign in with Apple уже предоставляет 2FA на уровне Apple ID.

**Q: Что если иностранный пользователь зарегистрировался, путешествуя по РФ?**
A: Краткосрочное пребывание не делает его "гражданином РФ" по 152-ФЗ. Локализация требуется для данных граждан/резидентов РФ.

**Q: Могут ли просто заблокировать по адресу серверу без суда?**
A: Да, РКН может внесудебно заблокировать по жалобе. Но это обычно после нескольких месяцев игнорирования запросов регулятора.

**Q: А если использовать только Telegram-авторизацию без Apple?**
A: Не важно какой провайдер — обязательства оператора ПДн те же самые. Sign in with Apple удобен тем что Apple хранит реальный email, нам доставляется alias.
