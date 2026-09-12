# App Store Connect — 0.6.7

Всё, что нужно вставить при выкладке билда **0.6.7 (59)**. Заметки для ревьюера —
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
  него ФИЛИППИНСКИЙ текст — так делали в 0.6.3, 0.6.4 и 0.6.6.
- **Казахского в карточке нет вовсе.** В приложении он есть, в списке локалей
  между Italian и Polish пусто. Блок ниже оставлен для полноты, но вставлять
  его НЕКУДА.

Релиз **не чисто клиентский**: бэкенд деплоится первым — колонка единиц
приборки у машины и колонка валюты. Без них выбор «на приборке мили» не
переживёт переустановку, а это неверный пробег, а не косметика.

Ключевые слова, подзаголовок и описание не меняются. Лимиты: «What's New» —
4000, промо-текст — 170.

---

## 1. What's New

### English (U.S.)

```
MILES, FOR REAL

Pick miles and the whole app switches: distances, speed, elevation in feet,
fuel economy. Until now the choice only changed the labels — the numbers stayed
metric.

YOUR CAR'S DASHBOARD HAS ITS OWN UNITS

An import with a miles odometer in a metric country, or a Toyota with
kilometres while you think in miles — both are normal. The car's passport now
has a "Dashboard units" row, and it governs exactly three things: the odometer
you type in, the odometer you read, and fuel. Everything else stays in yours.

A CAR ON THE MAP, DRAWN PROPERLY

Replay now shows a car seen from above that turns to face the way you were
going, painted in that car's colour. The old one was a side view and could only
flip left or right — heading north, it drove sideways. It also fades out into a
dot when you zoom far out, instead of covering a hundred kilometres of route.

FIXED

A photo added on the finish screen lost its capture time and place, so it never
landed on the map. Replay no longer tears while you pinch the map. Crash
reports are on for the first time.
```

### Russian

```
МИЛИ ПО-НАСТОЯЩЕМУ

Выбрали мили — переключается всё приложение: расстояния, скорость, высота в
футах, расход. Раньше выбор менял только подписи, а числа оставались
километровыми.

У ПРИБОРКИ МАШИНЫ СВОИ ЕДИНИЦЫ

Американка с мильным одометром в России или тойота с километрами, когда вы
думаете в милях, — обычное дело. В паспорте машины появилась строка
«Приборка». Ей подчиняются ровно три вещи: поле ввода пробега, сам пробег и
топливо. Остальное остаётся в ваших единицах.

МАШИНКА НА КАРТЕ, НАРИСОВАННАЯ ЗАНОВО

В воспроизведении едет машина вида сверху, повёрнутая туда, куда вы ехали, и
покрашенная в цвет этой машины. Прежняя была видом сбоку и умела только
зеркалиться — на север ехала боком. А на сильном отдалении она сворачивается в
точку, вместо того чтобы накрывать собой сто километров маршрута.

ИСПРАВЛЕНО

Снимок, добавленный на экране финиша, терял время и место съёмки и не вставал
на карту. Воспроизведение больше не рвётся, когда карту щипаешь на ходу.
Впервые включены отчёты о падениях.
```

### German

```
MEILEN, RICHTIG

Wählen Sie Meilen, und die ganze App stellt um: Entfernungen, Geschwindigkeit,
Höhe in Fuß, Verbrauch. Bisher änderte die Wahl nur die Beschriftungen — die
Zahlen blieben metrisch.

DAS COCKPIT IHRES AUTOS HAT EIGENE EINHEITEN

Ein Import mit Meilentacho in einem metrischen Land, oder ein Toyota mit
Kilometern, während Sie in Meilen denken — beides ist normal. Im Fahrzeugpass
gibt es jetzt die Zeile „Cockpit-Einheiten“. Sie bestimmt genau drei Dinge: die
Eingabe des Kilometerstands, dessen Anzeige und den Kraftstoff.

EIN AUTO AUF DER KARTE, NEU GEZEICHNET

Die Wiedergabe zeigt jetzt ein Auto von oben, das sich in Fahrtrichtung dreht,
in der Farbe dieses Fahrzeugs. Das alte war eine Seitenansicht und konnte nur
spiegeln — nach Norden fuhr es seitwärts.

BEHOBEN

Ein Foto, das auf dem Abschlussbildschirm hinzugefügt wurde, verlor Zeit und
Ort der Aufnahme und landete nie auf der Karte. Die Wiedergabe reißt beim Zoomen
nicht mehr. Absturzberichte sind erstmals aktiv.
```

### Spanish (Spain)

```
MILLAS DE VERDAD

Elige millas y cambia toda la app: distancias, velocidad, altitud en pies,
consumo. Hasta ahora la elección solo cambiaba las etiquetas; los números
seguían siendo métricos.

EL CUADRO DE TU COCHE TIENE SUS PROPIAS UNIDADES

Un importado con cuentakilómetros en millas, o un Toyota en kilómetros mientras
tú piensas en millas: ambas cosas son normales. El pasaporte del coche tiene
ahora la fila «Unidades del cuadro», y manda sobre tres cosas exactamente: el
odómetro que escribes, el que lees y el combustible.

UN COCHE EN EL MAPA, DIBUJADO DE NUEVO

La reproducción muestra un coche visto desde arriba que gira hacia donde ibas,
pintado del color de ese coche. El anterior era una vista lateral y solo podía
voltearse: hacia el norte circulaba de lado.

CORREGIDO

Una foto añadida en la pantalla final perdía la hora y el lugar de captura y
nunca aparecía en el mapa. La reproducción ya no se rompe al hacer zoom.
```

### French

```
LES MILES, POUR DE VRAI

Choisissez les miles et toute l'app bascule : distances, vitesse, altitude en
pieds, consommation. Jusqu'ici le choix ne changeait que les libellés — les
chiffres restaient métriques.

LE TABLEAU DE BORD DE VOTRE VOITURE A SES PROPRES UNITÉS

Une importée avec un compteur en miles, ou une Toyota en kilomètres alors que
vous pensez en miles : les deux sont normaux. Le passeport du véhicule a
désormais la ligne « Unités du tableau de bord ». Elle commande exactement trois
choses : la saisie du kilométrage, son affichage et le carburant.

UNE VOITURE SUR LA CARTE, REDESSINÉE

La relecture montre une voiture vue du dessus qui pivote vers votre direction,
peinte à la couleur de ce véhicule. L'ancienne était une vue de côté et ne
pouvait que se retourner : vers le nord, elle roulait de travers.

CORRIGÉ

Une photo ajoutée sur l'écran de fin perdait l'heure et le lieu de prise et
n'apparaissait jamais sur la carte. La relecture ne se déchire plus au zoom.
```

### Italian

```
MIGLIA, SUL SERIO

Scegli le miglia e cambia tutta l'app: distanze, velocità, altitudine in piedi,
consumi. Finora la scelta cambiava solo le etichette: i numeri restavano metrici.

IL CRUSCOTTO DELLA TUA AUTO HA LE SUE UNITÀ

Un'importata con contachilometri in miglia, o una Toyota in chilometri mentre
tu ragioni in miglia: entrambe le cose sono normali. Il passaporto dell'auto ha
ora la riga «Unità del cruscotto», e comanda esattamente tre cose: il
chilometraggio che digiti, quello che leggi e il carburante.

UN'AUTO SULLA MAPPA, RIDISEGNATA

Il replay mostra un'auto vista dall'alto che ruota verso la direzione di marcia,
colorata come quella vettura. La precedente era di profilo e poteva solo
specchiarsi: verso nord viaggiava di traverso.

CORRETTO

Una foto aggiunta nella schermata finale perdeva ora e luogo dello scatto e non
finiva mai sulla mappa. Il replay non si strappa più durante lo zoom.
```

### Polish

```
MILE NAPRAWDĘ

Wybierz mile, a przełącza się cała aplikacja: odległości, prędkość, wysokość w
stopach, spalanie. Dotąd wybór zmieniał tylko etykiety — liczby pozostawały
metryczne.

DESKA ROZDZIELCZA TWOJEGO AUTA MA WŁASNE JEDNOSTKI

Import z licznikiem w milach albo Toyota w kilometrach, kiedy ty myślisz w
milach — jedno i drugie jest normalne. W paszporcie auta pojawił się wiersz
„Jednostki deski rozdzielczej". Rządzi dokładnie trzema rzeczami: wpisywanym
przebiegiem, wyświetlanym przebiegiem i paliwem.

AUTO NA MAPIE, NARYSOWANE OD NOWA

Odtwarzanie pokazuje auto widziane z góry, obracające się w stronę jazdy, w
kolorze tego pojazdu. Poprzednie było widokiem z boku i umiało tylko się odbić:
na północ jechało bokiem.

NAPRAWIONO

Zdjęcie dodane na ekranie końcowym traciło czas i miejsce wykonania i nigdy nie
trafiało na mapę. Odtwarzanie nie rwie się już przy przybliżaniu.
```

### Indonesian

```
MIL, SUNGGUHAN

Pilih mil dan seluruh aplikasi ikut berubah: jarak, kecepatan, ketinggian dalam
kaki, konsumsi bahan bakar. Sebelumnya pilihan itu hanya mengubah label —
angkanya tetap metrik.

DASBOR MOBIL ANDA PUNYA SATUANNYA SENDIRI

Mobil impor dengan odometer mil, atau Toyota dengan kilometer sementara Anda
berpikir dalam mil — keduanya wajar. Paspor mobil kini punya baris "Satuan
dasbor", dan ia mengatur tepat tiga hal: odometer yang Anda ketik, yang Anda
baca, dan bahan bakar.

MOBIL DI PETA, DIGAMBAR ULANG

Pemutaran ulang menampilkan mobil dari atas yang berputar ke arah perjalanan
Anda, diwarnai sesuai mobil itu. Yang lama adalah tampak samping dan hanya bisa
membalik: ke utara ia melaju menyamping.

DIPERBAIKI

Foto yang ditambahkan di layar akhir kehilangan waktu dan tempat pengambilan
sehingga tidak pernah muncul di peta. Pemutaran ulang tidak lagi patah saat
diperbesar.
```

### Turkish

```
MİLLER, GERÇEKTEN

Mil seçin, tüm uygulama değişsin: mesafeler, hız, fit cinsinden yükseklik,
yakıt tüketimi. Şimdiye kadar bu seçim yalnızca etiketleri değiştiriyordu —
sayılar metrik kalıyordu.

ARACINIZIN GÖSTERGE PANELİNİN KENDİ BİRİMLERİ VAR

Mil göstergeli bir ithal araç ya da siz mil düşünürken kilometre gösteren bir
Toyota — ikisi de olağan. Araç pasaportuna «Gösterge birimleri» satırı eklendi
ve tam olarak üç şeyi yönetiyor: girdiğiniz kilometre, okuduğunuz kilometre ve
yakıt.

HARİTADA YENİDEN ÇİZİLMİŞ BİR ARABA

Tekrar oynatma artık yukarıdan görünen, gittiğiniz yöne dönen ve o aracın
renginde bir araba gösteriyor. Eskisi yandan görünümdü ve yalnızca
aynalanabiliyordu: kuzeye giderken yan gidiyordu.

DÜZELTİLDİ

Bitiş ekranında eklenen fotoğraf çekim zamanını ve yerini kaybediyor, haritaya
hiç düşmüyordu. Tekrar oynatma yakınlaştırırken artık kopmuyor.
```

### Filipino → вставлять в слот **Finnish**

```
MILYA, TALAGA

Piliin ang milya at magbabago ang buong app: distansya, bilis, taas sa talampakan,
konsumo ng gasolina. Dati, ang pagpili ay nagpapalit lang ng label — nananatiling
metriko ang mga numero.

MAY SARILING YUNIT ANG DASHBOARD NG SASAKYAN MO

Isang import na may odometer sa milya, o isang Toyota na nasa kilometro habang
nag-iisip ka sa milya — parehong normal. May bagong hilera na «Dashboard units»
ang pasaporte ng sasakyan, at tatlong bagay lang ang inuutusan nito: ang
odometer na tina-type mo, ang binabasa mo, at ang gasolina.

ISANG SASAKYAN SA MAPA, IGINUHIT MULI

Ang replay ay nagpapakita ngayon ng sasakyang tanaw mula sa itaas na umiikot
paharap sa dinaanan mo, kulay ng sasakyang iyon. Ang luma ay tanaw sa gilid at
kayang mag-flip lang: pahilaga, pahalang itong tumatakbo.

INAYOS

Ang larawang idinagdag sa finish screen ay nawawalan ng oras at lugar ng kuha
kaya hindi ito napupunta sa mapa. Hindi na napuputol ang replay habang
nagza-zoom.
```

### Ukrainian

```
МИЛІ ПО-СПРАВЖНЬОМУ

Обрали милі — перемикається весь застосунок: відстані, швидкість, висота у
футах, витрата. Раніше вибір змінював лише підписи, а числа лишалися
кілометровими.

У ПРИЛАДОВОЇ ПАНЕЛІ АВТО СВОЇ ОДИНИЦІ

Американка з мильним одометром або тойота з кілометрами, коли ви думаєте в
милях, — звична річ. У паспорті авто з'явився рядок «Приладова панель». Їй
підпорядковані рівно три речі: поле введення пробігу, сам пробіг і пальне.

МАШИНКА НА КАРТІ, НАМАЛЬОВАНА НАНОВО

У відтворенні їде авто у вигляді згори, повернуте туди, куди ви їхали, і
пофарбоване в колір цього авто. Попереднє було виглядом збоку й уміло лише
дзеркалитися — на північ їхало боком.

ВИПРАВЛЕНО

Світлина, додана на екрані фінішу, втрачала час і місце зйомки й не потрапляла
на карту. Відтворення більше не рветься, коли карту щипаєш на ходу.
```

### Portuguese (Brazil)

```
MILHAS, DE VERDADE

Escolha milhas e todo o app muda: distâncias, velocidade, altitude em pés,
consumo. Até agora a escolha mudava só os rótulos — os números continuavam
métricos.

O PAINEL DO SEU CARRO TEM AS PRÓPRIAS UNIDADES

Um importado com odômetro em milhas, ou um Toyota em quilômetros enquanto você
pensa em milhas: os dois são normais. O passaporte do carro agora tem a linha
«Unidades do painel», e ela comanda exatamente três coisas: o odômetro que você
digita, o que você lê e o combustível.

UM CARRO NO MAPA, DESENHADO DE NOVO

A reprodução mostra um carro visto de cima que gira para a direção em que você
seguia, pintado na cor daquele carro. O anterior era uma vista lateral e só
sabia espelhar: para o norte, andava de lado.

CORRIGIDO

Uma foto adicionada na tela final perdia a hora e o lugar da captura e nunca
aparecia no mapa. A reprodução não se rasga mais ao dar zoom.
```

### Kazakh — В КАРТОЧКЕ ЭТОЙ ЛОКАЛИ НЕТ, вставлять некуда

```
МИЛЬ ШЫНЫМЕН

Мильді таңдасаңыз, бүкіл қолданба ауысады: қашықтық, жылдамдық, футпен
биіктік, отын шығыны. Бұрын таңдау тек жазуларды өзгертетін — сандар
метрлік күйінде қалатын.

КӨЛІКТІҢ АСПАПТАР ТАҚТАСЫНЫҢ ӨЗ ӨЛШЕМІ БАР

Миль есептегіші бар әкелінген көлік немесе сіз мильмен ойлағанда километр
көрсететін тойота — екеуі де қалыпты жағдай. Көлік паспортында «Аспаптар
тақтасы» жолы пайда болды.

КАРТАДАҒЫ КӨЛІК ҚАЙТА САЛЫНДЫ

Ойнатуда жоғарыдан көрінетін, жүрген бағытыңызға бұрылатын және сол көліктің
түсіне боялған машина жүреді.

ТҮЗЕТІЛДІ

Мәреде қосылған сурет түсірілген уақыты мен орнын жоғалтып, картаға
түспейтін. Ойнату масштабтау кезінде енді үзілмейді.
```

---

## 2. Промо-текст (170)

**RU**

```
Мили, футы и единицы приборки отдельно для каждой машины. И машинка на карте,
которая наконец поворачивается туда, куда вы едете.
```

**EN**

```
Miles, feet, and dashboard units set per car. Plus a map car that finally turns
to face the way you were going.
```

---

## 3. Что проверить в карточке перед «Submit»

- [ ] «What's New» заполнен во **всех двенадцати** локалях карточки. Филиппинский
      текст — в слот **Finnish**. Казахский блок пропустить, локали нет.
- [ ] Рейтинг 13+ на месте (лента с реакциями = «Social Media»).
- [ ] **App Privacy** заполнена по `docs/releases/app-privacy.md` — четырнадцать
      типов данных вместо «Data Not Collected». Это **обязательно** в этом
      релизе: с 0.6.7 приложение впервые действительно отправляет диагностику.
- [ ] Notes для ревьюера — блок 0.6.7 из `../app-review-notes.md`.
- [ ] Скриншоты: воспроизведение с новой машинкой — лучший кадр релиза.
- [ ] Бэкенд выкачен **до** сабмита.
