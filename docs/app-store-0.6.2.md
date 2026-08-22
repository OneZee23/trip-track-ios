# App Store Connect — 0.6.2

Всё, что нужно вставить при выкладке билда **0.6.2 (53)**. Заметки для ревьюера —
отдельно, в [app-review-notes.md](app-review-notes.md), секция «current submission».

Релиз **клиентский**: бэкенд и сайт трогать не нужно. Колонка `avatar_style`
на сервере полезна, но не обязательна — без неё чужие машины приезжают
легковыми, ровно как сегодня.

**В сторе по-прежнему две локализации карточки — English (U.S.) и Russian**
(см. [aso-live.md](aso-live.md)). Новых заводить в этом релизе не надо;
ключевые слова, подзаголовок и описание остаются от 0.6.1 — ASO этот релиз не
меняет. Заполняются только «What's New» и, по желанию, промо-текст.

Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New

### English

```
PICK WHAT YOU DRIVE

The garage used to hold one car in eight colours. Now it holds ten shapes:
saloon, hatchback, crossover, pickup, van, convertible, sports car, motorcycle,
scooter and bicycle — each in nine colours. Shape and colour are picked
separately, so the combination is yours.

Motorcycles, mopeds and bicycles finally look like themselves. The app has
offered those types for a while and drew all three as a car.

Your vehicle now rides along on the trip card, so you can see what you took
without opening anything.

YOUR OWN HISTORY, READ BACK

Your trips no longer introduce you to yourself: the name and avatar are gone
from your own cards — you know who you are. The level stayed, and it is now the
level you were at the time. A drive from two years ago says LVL 3 and yesterday
says LVL 9, so scrolling your history shows the distance you covered.

DRAWN, NOT BORROWED

Every empty screen, every error and every onboarding page now has a picture
drawn for this app instead of a system glyph. Lists load as an outline of the
list rather than a spinner, so the screen you are waiting for is the screen you
already see.

FIXED

Vehicle mileage is now worked out from your trips instead of counted up once.
Moving a trip to another vehicle, deleting a trip or restoring your library
from the server used to leave the number where it was.

Your car in the garage is sharp again — it was the one place in the app that
smoothed the pixels.
```

### Русский

```
ВЫБЕРИТЕ, НА ЧЁМ ЕЗДИТЕ

В гараже стояла одна машина в восьми цветах. Теперь их десять: седан, хэтчбек,
кроссовер, пикап, фургон, кабриолет, спорткар, мотоцикл, скутер и велосипед —
каждый в девяти цветах. Тип и цвет выбираются отдельно, так что сочетание ваше.

Мотоциклы, мопеды и велосипеды наконец выглядят собой. Эти типы были в
приложении давно, и все три рисовались легковой машиной.

Машина теперь едет на карточке поездки — видно, на чём ехали, не открывая
деталей.

СВОЯ ИСТОРИЯ, ПЕРЕЧИТАННАЯ

Поездки больше не представляют вас вам же: имя и аватар с ваших карточек
убраны — вы и так знаете, кто вы. Уровень остался, и теперь он тот, что был на
момент записи. На поездке двухлетней давности LVL 3, на вчерашней LVL 9 — по
ленте видно расстояние, которое вы прошли.

РИСОВАНО, А НЕ ЗАНЯТО

У каждого пустого экрана, каждой ошибки и каждой страницы онбординга теперь
своя картинка, нарисованная для этого приложения, а не системный значок.
Списки грузятся контуром списка, а не крутящимся кружком: экран, которого вы
ждёте, уже перед вами.

ИСПРАВЛЕНО

Пробег машины считается по поездкам, а не накапливается один раз. Перенос
поездки на другое авто, удаление поездки и восстановление библиотеки с сервера
раньше оставляли число прежним.

Машина в гараже снова чёткая — это было единственное место в приложении, где
пиксели сглаживались.
```

---

## 2. Promotional text (≤170)

Меняется без релиза, поиском не индексируется. Обновить, чтобы витрина
говорила про то, что в релизе:

```
EN: Ten vehicles, nine colours, one garage. Record the drive, watch it back like a film, and see what you took. Your roads, remembered.
```
```
RU: Десять машин, девять цветов, один гараж. Запишите дорогу, пересмотрите её как кино и вспомните, на чём ехали. Ваши маршруты — сохранены.
```

---

## 3. Скриншоты

Лежат в `~/Desktop/TripTrack-AppStore-0.6.1/`, шесть штук. Пять из них релиз не
трогает — их можно оставить.

> **Решение 22.08: отложено.** Скриншоты в 0.6.2 не переснимаются — времени нет,
> и релиз из-за них не задерживается. Всё, что ниже, остаётся в силе для
> следующей версии; там же и седьмой кадр. Заявку это не завернёт: кадры
> показывают работающее приложение, просто не самое новое в нём.

**Переснять `02-tap-start.png`.** На нём машина на карте —
старая бледно-янтарная; именно этот цвет в 0.6.2 и переделан. Витрина, которая
показывает цвет, которого в приложении больше нет, — это несоответствие,
заметное с первого запуска.

**Стоит добавить седьмой — гараж.** Главное в релизе не видно ни на одном из
шести кадров, а решётка из десяти силуэтов в девяти цветах — единственное, что
продаёт этот апдейт с картинки. Экран: Я → Гараж → карточка машины (или сам
пикер типа и цвета). Заголовок в духе «Pick what you drive.» / «Выберите, на
чём ездите».

Снимать на том же устройстве и в той же рамке, что остальные пять, иначе
подложка и радиус углов не совпадут.

---

## 4. Что проверить перед отправкой

1. Билд **0.6.2 (53)**. Бэкенд и сайт не трогаем.
2. «What's New» вставлен в обе локали — English (U.S.) и Russian. Больше
   локалей в карточке нет; ключевые слова и описание не меняются.
3. Промо-текст обновлён в обеих (необязательно, но он про этот релиз).
4. `02-tap-start.png` переснят, гараж добавлен седьмым.
5. **Открыть гараж на телефоне и пройти по всем девяти цветам и десяти типам.**
   Спрайты генерируются скриптом, и пропущенная пара выглядит как пустое место,
   а не как ошибка сборки — тест на матрицу это ловит, но глазами надёжнее.
6. Поставить поверх 0.6.1 (не с нуля): миграция CoreData v6 → v7 добавляет
   `avatarStyle`, и проверять её надо на базе, где уже есть машины.
7. Прокрутить свою историю поездок: уровень на старых карточках должен
   отличаться от уровня на новых, а имени и аватара на них быть не должно.
8. Демо-аккаунт в App Review Information всё ещё указан.
