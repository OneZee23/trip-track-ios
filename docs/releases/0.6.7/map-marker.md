## 1. РЕШЕНИЕ

Делаем **один** маркер на оба экрана (реплей и живая запись — сегодня это два куска кода с одним и тем же боковым спрайтом в разных боксах, 40 и 44 pt), и это **строго ортографический вид СВЕРХУ, гладкой плоской векторной графикой, носом вверх, поворачиваемый кодом на точный угол**. Три вещи из исходной идеи отменяются: **кадров поворота (8/16/32) не будет** — они нужны только настоящему пиксель-арту, а его в проекте по факту нет (в `PixelCar.png` 6–7 тысяч цветов и антиалиасинг по всему полю, то есть это сглаженный растр «под пиксель», и `interpolationQuality = .none` его не «сохраняет», а рвёт, выбрасывая 6 строк из 7 при ужатии в 0.154×); **пиксель-арта на карте тоже не будет** — родство с гаражом держим палитрой, толстым контуром и игрушечными пропорциями, а не растровой техникой, потому что пиксельная сетка при свободном повороте разваливается; **и отдельных ассетов на состояния не будет вообще** — «стоит», «пауза», «нет сигнала», тень, белый ореол под линией, круг точности, конус курса, пульс рисует код, потому что ни одно из этих состояний не меняет ФОРМУ, а тень, запечённая в картинку, на южном курсе окажется над машиной и свет поедет вместе с курсом. Причина, по которой нынешний спрайт умеет только зеркалиться, — не лень автора, а геометрия: в виде сбоку и в виде три четверти зашита перспектива, и повернуть их нельзя в принципе; вид сверху — единственная проекция, инвариантная к повороту плоской карты. Карту при этом крутить НЕ будем: реплей — обзорный жанр («какой формы был маршрут»), а не навигация, и там вся отрасль (Uber, Flightradar24, Apple/Google в обзоре) держит север вверху и вращает маркер. Генерить нейросетью надо **ровно один кадр**, из которого руками получаются **три слоя** — цвет машины (все девять из гаража и любой будущий) собирает код, потому что десять генераций дадут десять разных силуэтов, а разный силуэт при повороте превращается в разное виляние.

## 2. ЧТО ГЕНЕРИТЬ

Нейросетью — **одна картинка**. В проект уезжают **три файла**, полученные из неё правками того же кадра.

| № | Файл | Зачем | Холст | Что на нём |
|---|---|---|---|---|
| 0 | `map_car_master` (в проект НЕ идёт) | исходник, из него режутся слои | 1024×1024 | машина сверху, нос вверх, фон `#FF00FF` |
| 1 | `map_car_body` | площадь краски — её код красит в цвет машины | 512×512 | только кузов, сплошной белый, чистая альфа. Без контура, без стёкол |
| 2 | `map_car_shade` | объём: код заливает тем же цветом × 0.78 | 512×512 | борта и задняя кромка, ~25–30% площади кузова, белым |
| 3 | `map_car_ink` | всё, что не красится никогда | 512×512 | тёмный контур 12 px, белый ореол 24 px СНАРУЖИ силуэта, стёкла, фары, фонари, зеркала, резина |

Геометрия (одна на все три слоя, центр совпадает до пикселя):

| Что | мастер 1024 | слои 512 | на экране (бокс 44 pt) |
|---|---|---|---|
| длина кузова | 760 px | 380 px | 33 pt |
| ширина кузова | 400 px | 200 px | 17 pt |
| пропорция | 1.9 : 1 | 1.9 : 1 | реальная 2.5:1 — карикатурим |
| тёмный контур | 24 px | 12 px | 1 pt |
| белый ореол | 48 px | 24 px | 2 pt |
| фара (каждая) | 40 px | 20 px | 1.7 pt |
| центр вращения | центр холста | центр холста | = центр колёсной базы, 45% длины от носа |
| поле сверху/снизу | ≥ 84 px | ≥ 42 px | запас под поворот, не пустота |

**Чего в списке НЕТ и почему.** Кадры углов — код поворачивает на 0.1° вместо 11.25°, и 36 углов × 9 цветов = 324 файла и ~2 МБ памяти на цвет. Девять цветных PNG — код красит маску. Тень — у неё направление света, она не имеет права вращаться. Круг точности и конус курса — они обязаны меряться в МЕТРАХ карты, а не в точках. Версия под тёмную тему — не нужна: ореол и контур несут контраст сами, а спутникового режима в приложении нет вовсе (все шесть карт на `MKStandardMapConfiguration`), так что утолщать обводку под спутник не надо. Другие типы транспорта (фургон, пикап, мотоцикл) — потом, теми же тремя слоями.

**Чем генерить:** Nano Banana 2 (Gemini 3.1 Flash Image) или FLUX.1 Kontext — оба умеют править кадр, сохраняя остальное, а это ровно операция «сделай из этого маску». Midjourney не годится: прозрачности на экспорте нет, каждый кадр пришлось бы чистить отдельно.

## 3. ПРОМПТЫ

**A. Мастер.** Сгенерить 20–30 вариантов одним запросом, выбрать ОДИН по силуэту, а не по деталям. Ракурс никогда не «доводить» повторной генерацией — это самый ненадёжный навык моделей.

```
flat vector game icon, orthographic top-down view of a compact hatchback seen from
directly above, plan view, camera perpendicular to the roof, zero perspective, zero
tilt, no visible side panels, the car points straight up toward the top edge of the
frame, perfectly symmetrical left to right about the vertical axis, centered in a
square frame with generous empty margins above and below, chunky toy proportions,
body length to width about 1.9 to 1, front end tapering slightly toward the nose,
rear end squared off, cabin set back from center so the hood is longer than the
trunk, dark tinted windshield and rear window, two small warm headlights at the very
front edge, two smaller darker tail lights at the rear edge, tiny rectangular side
mirror stubs merged into the outline, four small dark tyre rectangles at the corners
poking just past the body, one single flat body color, uniform dark outline of even
thickness all around, flat solid colors only, no gradients, no reflections, no
highlights, no baked shadow, no ground, no text, no logo, no license plate, solid
flat #FF00FF background filling the whole canvas, 1024x1024
```

Негатив: `perspective, three-quarter view, isometric, tilted camera, front view, side view, photo, photorealistic, 3d render, chrome, glare, specular, gradient, drop shadow, road, parking lot, scenery, background objects, text, watermark, logo, license plate, motion blur, wheels seen from the side, people`

**B. Слой `body`** (правка выбранного кадра):

```
Use the attached image. Keep the exact same car: identical shape, identical outline,
identical position, identical size, identical rotation. Do not redraw, do not move,
do not rescale, do not add or remove any part. Output a flat silhouette mask: fill
every painted body panel of the car with pure white #FFFFFF, and make absolutely
everything else pure black #000000 — windows, windshield, headlights, tail lights,
mirrors, tyres, the outline itself, and the background. Hard edges, two colors only,
no anti-aliasing, no grey, no shading, 1024x1024.
```

**C. Слой `shade`:**

```
Use the attached image. Keep the exact same car: identical shape, identical outline,
identical position, identical size, identical rotation. Do not redraw, do not move,
do not rescale. Output a shading mask: fill pure white #FFFFFF only where the body
curves away — a narrow strip along the left flank, a narrow strip along the right
flank, and a band across the rear edge, together covering about a quarter of the
painted body area. Everything else pure black #000000, including the roof, the hood,
the windows, the outline and the background. The white strips must be symmetrical
left to right. Hard edges, two colors only, no grey, no gradient, 1024x1024.
```

**D. Слой `ink`:**

```
Use the attached image. Keep the exact same car: identical shape, identical outline,
identical position, identical size, identical rotation. Do not redraw, do not move,
do not rescale. Remove all body paint, leaving it fully transparent. Keep only: the
dark outline of even thickness around the whole car, the dark windshield and rear
window, the two warm headlights at the front edge, the two darker tail lights at the
rear edge, the mirror stubs, and the four dark tyre rectangles. Then add a clean
white halo that hugs the outside of the car's silhouette, even thickness all around,
sitting entirely outside the dark outline and never overlapping it. Transparent
everywhere else — no background fill, no shadow, no gradient, 1024x1024.
```

## 4. ЧТО ПОПРАВИТЬ РУКАМИ

Полчаса работы, без неё ассет не годится — модели стабильно промахиваются ровно в этих шести местах.

1. **Фон.** Выбить `#FF00FF`, затем пройти по кромке: после выбивки остаётся полупрозрачная маджентовая кайма, на тёмной карте она светится розовым.
2. **Симметрия.** Отзеркалить левую половину на правую и склеить. Машина выйдет слегка косой, и при повороте это читается как виляние вокруг оси.
3. **Ось.** Довернуть так, чтобы продольная ось была строго вертикальна: даже 2° уедут в постоянную ошибку курса.
4. **Центр.** Сдвинуть кузов вниз на 19 px (в масштабе 512) — чтобы в центре холста оказался центр колёсной базы, а не центр прямоугольника. Иначе маркер будет ездить вокруг точки, а не поворачиваться в ней; `centerOffset` тут не спасает — он работает в экранных координатах и с поворотом не поворачивается.
5. **Контур.** Выровнять толщину: у генерации она гуляет от 3 до 7 px, а на 33 pt это читается как разная резкость с разных сторон.
6. **Палитра.** Сплющить до 6–8 цветов, убрать градиенты и блики. «Чёрную» машину рисовать как `#2B2F36`, «белую» как `#F2F0EA` — чистые крайности сливаются с контуром и с ореолом.

Экспорт: три PNG 512×512, **один слот, без @2x/@3x** (код всегда рисует в явный бокс через `UIGraphicsImageRenderer`, масштаб экрана он берёт сам — так уже устроен `PixelCar.imageset`). Проверка перед сдачей: наложить три слоя друг на друга — контуры должны совпасть до пикселя; уменьшить до 12 pt — нос обязан читаться. Если не читается, проблема в силуэте, и деталями она не лечится.

## 5. ЧТО СДЕЛАЮ Я В КОДЕ

**Выбрасывается:** `playbackCarRight` / `playbackCarLeft`, `renderCar(mirrored:)` целиком вместе с зеркалированием, `var playbackFacesRight`, порог `abs(dx) > abs(dy) * 0.3` в `updateCarFacing`, `interpolationQuality = .none` в обоих местах (меняется на `.high`), комментарий «the sprite is drawn from the SIDE» (он вдвойне неверен — спрайт на самом деле три четверти), и файл `PositionMarker.swift` целиком: синей точки со стрелкой на экране нет с 0.1.0, на него ноль ссылок, и именно он вводит в заблуждение каждого читающего.

**Строится:**

| Что | Как |
|---|---|
| Один компонент на оба экрана | реплей поднимается с 40 pt до 44 pt, разъезд размеров закрывается |
| Слои | контейнерный `MKAnnotationView` 44 pt (тень + подложка, НЕ вращаются), внутри `UIImageView` с машиной — вращается только его слой. `frame` не раздувается, наша пружина появления не конфликтует |
| Угол | `screenAngle = course − mapView.camera.heading` — одна формула на оба экрана; в `.followWithHeading` она сама даёт нос вверх, отдельной ветки не нужно |
| Обновление | плюс `mapViewDidChangeVisibleRegion` — иначе на повёрнутой пальцами карте маркер отвяжется от дороги. И сброс поворота при `dequeue` |
| Перекраска | `tint(body)` → `tint×0.78(shade)` → `ink`, кэш девяти готовых `UIImage` по цвету, светлота тинта зажата в 22–86% |
| Курс в реплее | по геометрии с упреждением 10–15 м вперёд по прорежённой серии, не по разнице соседних кадров: полилиния хранит `Float32` (~0.4 м), при 60 кадрах межкадровый сдвиг меньше кванта и знак там — чистый шум |
| Курс в записи | `CLLocation.course` напрямую, с воротами `course ≥ 0 && courseAccuracy ≥ 0` и сырой скоростью GPS ≥ 1.4 м/с — тем же правилом, что уже сторожит одометр. Не прошло — держим последний достоверный угол |
| Дрожание на стоянке | чистой функцией под тест, как `AutoTripPolicy`: ниже порога курс ЗАМОРОЖЕН, а не ищется в шуме |
| Сглаживание | по кратчайшей дуге: `delta = ((target − current + 540) % 360) − 180`, `current += delta × 0.2` за кадр, мёртвая зона 2°, потолок 180°/с. Без этого переход 359°→1° прокрутит машину через весь круг |
| Состояния | тень (смещение 0/1, размытие 2, чёрный 22%), круг точности в метрах, конус неуверенности курса, пульс живого сигнала (только запись), пауза = насыщенность 0.35 + пилюля `pause.fill`, нет сигнала = насыщенность 0 и прозрачность 0.55 |
| Мелкий зум | ниже порога маркер схлопывается в точку с обводкой: на треке в 1000 км спрайт 44 pt накрывает сотню километров и прячет ровно тот маршрут, ради которого экран открыли |
| Reduce Motion | поворот ОСТАЁТСЯ (это информация, Apple стрелку курса тоже не выключает), убирается пружинное доведение угла, пульс и автозапуск реплея |

**Отдельно чиню мину рядом:** `LocationProvider.swift:19` переводит невалидный курс `−1` в `0`, а ноль — это не «неизвестно», это «строго на север». Поле станет опциональным, иначе новый маркер на парковке будет демонстративно смотреть на север.