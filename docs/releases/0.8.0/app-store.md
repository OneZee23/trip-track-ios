# App Store Connect — 0.8.0

Всё, что нужно вставить при выкладке билда **0.8.0 (63)**. Заметки для ревьюера —
в [app-review-notes.md](../app-review-notes.md), секция «current submission».

**«What's New» обязателен в КАЖДОЙ локализации карточки.** Сабмит 0.6.2
отклонили ровно за одну пропущенную.

**В карточке ДВЕНАДЦАТЬ локалей, и это НЕ языки приложения.** Заполнять ровно
их, ничего больше:

> English (генеральная) · Russian · German · Spanish (Spain) · French ·
> Italian · Polish · Indonesian · Turkish · **Finnish** · Ukrainian ·
> Portuguese (Brazil)

Два расхождения с приложением — старые и намеренно не чинятся:

- **Слот «Finnish» — это филиппинский.** Финского языка в приложении нет; при
  заведении локалей `fil` спутали с `fi`. Слот НЕ переименовываем, кладём в
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3–0.6.8 и 0.7.0.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто. Блок ниже оставлен для полноты, но вставлять
  его НЕКУДА.

**Монетизация в этом релизе отложена (решение владельца, 21 сен 2026).**
Подписка «Плюс», донат и вписанная вручную поездка спрятаны выключателем
`PlusAvailability.isEnabled = false` — их не видит никто ни в одном регионе.
Код остаётся в сборке (включат в 0.8.1 или позже), но в этот сабмит **не идёт
ни один In-App Purchase**: в App Store Connect для 0.8.0 в разделе IAP
выбирать нечего, товары заводить не нужно. Порядок ниже поэтому проще
обычного клиентского релиза — свой бэкенд-модуль `plus` можно деплоить в
любое время, сабмит от него не зависит. Полный порядок — `checklist.md`.

Ключевые слова, подзаголовок и описание карточки не меняются — только «What's
New». Лимиты: «What's New» — 4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
PLACES

Places now suggests spots you seem to visit, guessed from where your trips
start and end — save one with a tap, right from the map where all the
suggestions show up together.

EXPORT

Export your own trip as GPX or CSV from its ••• menu — free, no subscription
needed.

FIXED

The first launch after updating no longer freezes. The Apple Maps attribution
on the Atlas no longer looks like a bright plate. Car photos sync again.
```

### Russian

```
МЕСТА

Вкладка «Места» теперь подсказывает: «Похоже, вы здесь бываете» — по тому,
откуда обычно начинаются и где заканчиваются ваши поездки. Сохранить место —
один тап, все подсказки видно на той же карте, что и уже сохранённые места.

ЭКСПОРТ

В «…» своей поездки — экспорт в GPX или CSV, бесплатно, без подписки.

ИСПРАВЛЕНО

Первый запуск после обновления больше не зависает. Подпись Apple на карте
«Атласа» больше не похожа на яркую плашку. Фото машины снова синхронизируются.
```

### German

```
ORTE

Orte schlägt jetzt Stellen vor, an denen Sie öfter sind — geschätzt danach, wo
Ihre Fahrten beginnen und enden. Einen Ort speichern Sie mit einem Antippen,
alle Vorschläge stehen zusammen mit den gespeicherten Orten auf derselben
Karte.

EXPORT

Exportieren Sie Ihre eigene Fahrt als GPX oder CSV über deren •••-Menü —
kostenlos, ohne Abo.

BEHOBEN

Der erste Start nach dem Update hängt sich nicht mehr auf. Der
Apple-Maps-Hinweis im Atlas sieht nicht mehr wie eine helle Platte aus.
Autofotos werden wieder synchronisiert.
```

### Spanish (Spain)

```
LUGARES

Lugares ahora sugiere sitios que pareces visitar a menudo, calculados a partir
de dónde empiezan y terminan tus trayectos. Guardar uno es un toque, y todas
las sugerencias aparecen en el mismo mapa junto a los lugares ya guardados.

EXPORTAR

Exporta tu propio trayecto como GPX o CSV desde su menú ••• — gratis, sin
suscripción.

SOLUCIONADO

El primer inicio tras la actualización ya no se congela. El aviso de Apple
Maps en el Atlas ya no parece una placa clara. Las fotos del coche vuelven a
sincronizarse.
```

### French

```
LIEUX

Lieux suggère désormais des endroits que vous semblez fréquenter, déduits d'où
commencent et se terminent vos trajets. Enregistrer un lieu se fait d'un
geste, et toutes les suggestions apparaissent sur la même carte que les lieux
déjà enregistrés.

EXPORT

Exportez votre propre trajet en GPX ou CSV depuis son menu ••• — gratuit, sans
abonnement.

CORRIGÉ

Le premier lancement après la mise à jour ne se fige plus. La mention Apple
Plans sur l'Atlas ne ressemble plus à une plaque claire. Les photos de la
voiture se synchronisent à nouveau.
```

### Italian

```
LUOGHI

Luoghi ora suggerisce i posti che sembri frequentare, dedotti da dove iniziano
e finiscono i tuoi viaggi. Salvarne uno è un tocco, e tutti i suggerimenti
compaiono sulla stessa mappa dei luoghi già salvati.

ESPORTA

Esporta il tuo viaggio in GPX o CSV dal suo menu ••• — gratis, senza
abbonamento.

RISOLTO

Il primo avvio dopo l'aggiornamento non si blocca più. La dicitura Apple Mappe
sull'Atlante non sembra più una targhetta chiara. Le foto dell'auto tornano a
sincronizzarsi.
```

### Polish

```
MIEJSCA

Miejsca podpowiadają teraz miejsca, które chyba odwiedzasz często — na
podstawie tego, skąd zwykle zaczynają się i kończą twoje przejazdy. Zapisanie
miejsca to jedno dotknięcie, a wszystkie podpowiedzi widać na tej samej mapie
co już zapisane miejsca.

EKSPORT

Wyeksportuj swój przejazd do GPX lub CSV z jego menu ••• — za darmo, bez
subskrypcji.

NAPRAWIONE

Pierwsze uruchomienie po aktualizacji już się nie zawiesza. Podpis Apple Maps
na Atlasie nie wygląda już jak jasna płytka. Zdjęcia samochodu znów się
synchronizują.
```

### Indonesian

```
TEMPAT

Tempat kini menyarankan lokasi yang sepertinya sering Anda kunjungi,
diperkirakan dari titik awal dan akhir perjalanan Anda. Menyimpan satu tempat
cukup satu ketukan, dan semua saran muncul di peta yang sama dengan tempat
yang sudah tersimpan.

EKSPOR

Ekspor perjalanan Anda sendiri sebagai GPX atau CSV dari menu ••• miliknya —
gratis, tanpa langganan.

DIPERBAIKI

Peluncuran pertama setelah pembaruan tidak lagi macet. Kredit Apple Maps di
Atlas tidak lagi terlihat seperti pelat terang. Foto mobil tersinkron lagi.
```

### Turkish

```
YERLER

Yerler artık sık geldiğinizi tahmin ettiği noktaları öneriyor —
yolculuklarınızın nereden başlayıp nerede bittiğine bakarak. Bir yeri
kaydetmek tek dokunuş; tüm öneriler, kaydettiğiniz yerlerle aynı haritada
görünüyor.

DIŞA AKTARMA

Kendi yolculuğunuzu ••• menüsünden GPX ya da CSV olarak dışa aktarın —
ücretsiz, abonelik gerektirmez.

DÜZELTİLENLER

Güncellemeden sonraki ilk açılış artık donmuyor. Atlas'taki Apple Haritalar
imzası artık parlak bir levha gibi görünmüyor. Araç fotoğrafları yeniden
senkronize oluyor.
```

### Filipino → вставлять в слот **Finnish**

```
MGA LUGAR

Nagmumungkahi na ngayon ang Mga Lugar ng mga lugar na mukhang madalas mong
puntahan, batay sa kung saan karaniwang nagsisimula at natatapos ang mga
biyahe mo. Isang tap lang para i-save ang isa, at lahat ng suhestiyon ay
makikita sa parehong mapa kasama ang mga nakasave nang lugar.

EXPORT

I-export ang sarili mong biyahe bilang GPX o CSV mula sa ••• menu nito —
libre, walang kailangang subscription.

NAAYOS

Hindi na humahang ang unang paglunsad pagkatapos mag-update. Ang credit ng
Apple Maps sa Atlas ay hindi na parang maliwanag na plaka. Muling nag-sync ang
mga larawan ng sasakyan.
```

### Ukrainian

```
МІСЦЯ

Вкладка «Місця» тепер підказує: «Схоже, ви тут буваєте» — за тим, звідки
зазвичай починаються і де закінчуються ваші поїздки. Зберегти місце — один
тап, усі підказки видно на тій самій карті, що й уже збережені місця.

ЕКСПОРТ

У «…» своєї поїздки — експорт у GPX або CSV, безкоштовно, без підписки.

ВИПРАВЛЕНО

Перший запуск після оновлення більше не зависає. Підпис Apple на карті
«Атласа» більше не схожий на яскраву табличку. Фото авто знову
синхронізуються.
```

### Portuguese (Brazil)

```
LUGARES

Lugares agora sugere pontos que você parece frequentar, deduzidos de onde suas
viagens costumam começar e terminar. Salvar um é um toque, e todas as
sugestões aparecem no mesmo mapa junto com os lugares já salvos.

EXPORTAR

Exporte sua própria viagem como GPX ou CSV pelo menu ••• dela — grátis, sem
assinatura.

CORRIGIDO

O primeiro início após a atualização não trava mais. O crédito da Apple Maps
no Atlas não parece mais uma placa clara. As fotos do carro voltam a
sincronizar.
```

### Kazakh — В КАРТОЧКЕ ЭТОЙ ЛОКАЛИ НЕТ, вставлять некуда

```
ОРЫНДАР

«Орындар» енді сіз жиі баратын жерлерді ұсынады — сапарларыңыздың әдетте
қайдан басталып, қайда аяқталатынына қарап. Орынды сақтау — бір түрту, ал
барлық ұсыныстар бұрыннан сақталған орындармен бір картада көрінеді.

ЭКСПОРТ

Өз сапарыңыздың «…» мәзірінен GPX немесе CSV форматында экспорттаңыз — тегін,
жазылымсыз.

ТҮЗЕТІЛДІ

Жаңартудан кейінгі алғашқы іске қосылу енді тоқтап қалмайды. «Атластағы» Apple
Maps жазбасы енді жарқын тақташаға ұқсамайды. Көлік фотосуреттері қайта
синхрондалады.
```

---

## 2. Промо-текст (170)

Один и тот же смысл в двенадцати локалях. Лимит — 170 знаков, проверено
`wc -m`.

**English (U.S.)**

```
Faster and more stable this time. Places now suggests spots you seem to visit, and any trip exports as GPX or CSV from its ••• menu.
```

**Russian**

```
Быстрее и стабильнее. «Места» подсказывают, где вы обычно бываете, а поездку можно выгрузить в GPX или CSV из «…».
```

**German**

```
Schneller und stabiler. Orte schlägt jetzt Stellen vor, an denen Sie öfter sind, und jede Fahrt lässt sich als GPX oder CSV exportieren.
```

**Spanish (Spain)**

```
Más rápida y estable. Lugares ahora sugiere sitios que sueles visitar, y puedes exportar cualquier trayecto como GPX o CSV.
```

**French**

```
Plus rapide et plus stable. Lieux suggère désormais des endroits que vous fréquentez, et chaque trajet s'exporte en GPX ou CSV.
```

**Italian**

```
Più veloce e stabile. Luoghi ora suggerisce i posti che frequenti, e ogni viaggio si esporta in GPX o CSV dal menu •••.
```

**Polish**

```
Szybciej i stabilniej. Miejsca podpowiadają teraz miejsca, które odwiedzasz, a każdy przejazd można wyeksportować do GPX lub CSV.
```

**Indonesian**

```
Lebih cepat dan stabil. Tempat kini menyarankan lokasi yang sering dikunjungi, dan setiap perjalanan bisa diekspor sebagai GPX atau CSV.
```

**Turkish**

```
Daha hızlı ve kararlı. Yerler artık sık geldiğiniz noktaları öneriyor, ve her yolculuğu GPX ya da CSV olarak dışa aktarabilirsiniz.
```

**Filipino → слот Finnish**

```
Mas mabilis at matatag. Nagmumungkahi na ang Mga Lugar ng lugar na madalas mong puntahan, at pwede mo nang i-export ang biyahe bilang GPX o CSV.
```

**Ukrainian**

```
Швидше і стабільніше. «Місця» підказують, де ви зазвичай буваєте, а поїздку можна вивантажити у GPX або CSV.
```

**Portuguese (Brazil)**

```
Mais rápido e estável. Lugares agora sugere pontos que você costuma visitar, e você pode exportar qualquer viagem como GPX ou CSV.
```

---

## 3. Что проверить в карточке перед «Submit»

- [ ] «What's New» заполнен во **всех двенадцати** локалях карточки. Филиппинский
      текст — в слот **Finnish**. Казахский блок пропустить, локали нет.
- [ ] **В разделе In-App Purchase выбирать нечего.** Монетизация спрятана
      выключателем (`PlusAvailability.isEnabled = false`), ни один товар в
      этот сабмит не идёт — заводить подписку и донаты в Monetization не
      нужно, это перенесено на 0.8.1.
- [ ] **App Privacy без изменений** — тип данных Purchase History в этот
      сабмит не добавляется: без товаров в билде покупок не бывает, анкета
      остаётся такой же, как в 0.6.8 и 0.7.0.
- [ ] Notes для ревьюера — блок v0.8.0 из `../app-review-notes.md`.
- [ ] Скриншоты: прежний набор остаётся валидным, в этой версии ключевые
      экраны не поменялись.
- [ ] Деплой бэкенда до сабмита НЕ обязателен — все фичи 0.8.0 клиентские
      либо уже работают с прежним бэкендом. Правило Cloudflare `/j/*` и т.п.
      в этот раз тоже не нужно: новых публичных веб-путей версия не заводит.
