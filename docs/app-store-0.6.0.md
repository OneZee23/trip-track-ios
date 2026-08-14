# App Store Connect — 0.6.0

Всё, что нужно вставить при выкладке билда **0.6.0 (51)**. Заметки для ревьюера —
отдельно, в [app-review-notes.md](app-review-notes.md) (секция «current submission»).

Лимиты, о которые бьёшься: «What's New» — 4000 символов, промо-текст — 170,
подзаголовок — 30, ключевые слова — 100. Тексты ниже в лимиты укладываются.

---

## What's New — English

```
The biggest update since launch. TripTrack was redrawn end to end, and a trip is no
longer something only you can see.

COMPANIONS
Invite the people who were in the car. A trip becomes shared: their photos land on
it, it shows up in their history too, and nobody has to re-record the same road.

DISCUSSIONS
Comments with replies on public trips, reactions with a "who reacted" list, and
notifications that take you to the exact message.

THE TRIP ITSELF
Replay a drive like a film. Share it as a story poster or a link. A rewritten photo
viewer, scrubable speed and elevation charts, and a map that finally gets out of the
way.

FIVE TABS
Feed, Map, Record, Groups, Me. Your own map of everywhere you've driven, a calmer
recording screen, and a profile with achievements, levels and a "how others see you"
preview.

FEED THAT MAKES SENSE
"All" is now strictly by date — newest drives first, whoever they belong to. Follow
people and "For you" keeps them together.

CLUBS — COMING
A preview of what clubs will be, and a real waiting list you can join.

PRIVACY
Delete your account from inside the app: it removes everything on the server and
everything on this device, and says so before it does. All visibility switches —
public profile, trips on the global map, who can add you as a companion — now live
on one screen.
```

## «Что нового» — Русский

```
Самое большое обновление с релиза. TripTrack перерисован целиком, а поездка больше
не то, что видите только вы.

ПОПУТЧИКИ
Пригласите тех, кто ехал с вами. Поездка становится общей: их фото появляются в
ней, она попадает и в их историю, и никому не нужно записывать ту же дорогу второй
раз.

ОБСУЖДЕНИЯ
Комментарии с ответами к публичным поездкам, реакции со списком «кто отреагировал»
и уведомления, которые открывают нужную реплику.

САМА ПОЕЗДКА
Реплей маршрута — как маленькое кино. Постер для истории или ссылка. Переписанный
просмотрщик фото, графики скорости и высоты с прокруткой и карта, которая наконец
не мешает.

ПЯТЬ ВКЛАДОК
Лента, Карта, Запись, Группы, Я. Своя карта всех дорог, спокойный экран записи и
профиль с достижениями, уровнями и превью «как видят другие».

ПОНЯТНАЯ ЛЕНТА
«Все» — строго по дате: свежие поездки сверху, чьи бы они ни были. А «Для тебя»
собирает тех, на кого вы подписаны.

КЛУБЫ — СКОРО
Превью того, какими будут клубы, и настоящий список ожидания.

ПРИВАТНОСТЬ
Аккаунт удаляется прямо в приложении: стирается всё на сервере и всё на этом
устройстве — и об этом сказано до, а не после. Все переключатели видимости —
публичный профиль, поездки на глобальной карте, добавление в попутчики — собраны
на одном экране.
```

---

## Promotional text (170 chars)

```
EN: Record a drive, replay it like a film, and share it with everyone who was in the
car. Your roads, remembered.
```

```
RU: Запишите дорогу, пересмотрите её как кино и разделите с теми, кто ехал рядом.
Ваши маршруты — запомнены.
```

## Подзаголовок / Subtitle (30 chars)

```
EN: The drive, remembered
RU: Дневник ваших дорог
```

---

## Что проверить перед отправкой

1. Билд **0.6.0 (51)** — код в `ac919d4`, тег `v0.6.0` стоит на коммите документации
   поверх него (кода он не меняет).
2. Бэкенд задеплоен — без него лента идёт в старом порядке, карточки поездок в
   профиле беднее, а `trip-track.app/u/<id>` открывает промо-страницу.
3. Сайт задеплоен — прокси `/u/` и файл ассоциации.
4. Демо-аккаунт заведён и указан в App Review Information → User Account (иначе
   ревью отвалится на «не смогли проверить вход»).
5. Экран удаления аккаунта проверен на живом аккаунте: удаляет и сервер, и телефон.
6. Скриншоты пересняты — интерфейс изменился целиком, старые не подходят.
